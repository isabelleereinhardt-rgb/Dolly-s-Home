--!nonstrict
--[[
	KillerAgent.luau
	--------------------------------------------------------------------------
	One instance per active killer. Runs a four-state machine:

	  PATROL       walk a route through the killer's favoured rooms
	  INVESTIGATE  something was heard; go there and search around it
	  CHASE        a loud noise or a direct sighting; run the target down
	  STUNNED      staked; frozen in place

	The family is blind. Everything they know comes from NoiseService, which
	means a player's noise meter is the whole conversation between them and the
	AI. Vision exists only as a short-range backstop so standing directly in
	front of a killer isn't free (and can be switched off in Config).

	Two coroutines per agent: a think loop that decides *where*, and a
	navigation loop that handles *how*. They communicate through
	`self.destination` plus a version counter, so a new decision cancels an
	in-flight path immediately rather than waiting for the old walk to finish.
	--------------------------------------------------------------------------
]]

local CollectionService = game:GetService("CollectionService")
local PathfindingService = game:GetService("PathfindingService")
local Workspace = game:GetService("Workspace")

local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
local Config = require(Shared.Config)
local KillerData = require(Shared.KillerData)
local Net = require(Shared.Net)
local StateKeys = require(Shared.StateKeys)
local Tags = require(Shared.Tags)
local Util = require(Shared.Util)

local HidingService = require(script.Parent.Parent.Services.HidingService)
local MapService = require(script.Parent.Parent.Services.MapService)
local NoiseService = require(script.Parent.Parent.Services.NoiseService)
local RevivalService = require(script.Parent.Parent.Services.RevivalService)
local TeamService = require(script.Parent.Parent.Services.TeamService)

local STATE = {
	Patrol = "Patrol",
	Investigate = "Investigate",
	Chase = "Chase",
	Stunned = "Stunned",
}

local THINK_INTERVAL = 0.15

local KillerAgent = {}
KillerAgent.__index = KillerAgent

export type Agent = typeof(setmetatable({} :: any, KillerAgent))

--==========================================================================
-- Safe zones
--==========================================================================

--- Returns (centre, radius) of the active safe zone containing `position`.
local function safeZoneContaining(position: Vector3): (Vector3?, number?)
	for _, tag in { Tags.SafeZone, Tags.TempSafeZone } do
		for _, zone in CollectionService:GetTagged(tag) do
			if not zone:IsA("BasePart") or not zone.Parent then
				continue
			end
			-- Only zones in the live map; CollectionService also returns the
			-- ones sitting in ServerStorage map templates.
			if not zone:IsDescendantOf(Workspace) then
				continue
			end
			if zone:GetAttribute("Active") == false then
				continue
			end
			local radius = (zone:GetAttribute("Radius") :: number?)
				or math.max(zone.Size.X, zone.Size.Z) / 2
			if (zone.Position - position).Magnitude <= radius then
				return zone.Position, radius
			end
		end
	end
	return nil, nil
end

--==========================================================================
-- Construction
--==========================================================================

function KillerAgent.new(killerId: string, model: Model): Agent?
	local profile = KillerData.get(killerId)
	if not profile then
		Util.warn("KillerAgent", 'unknown killer id "%s"', killerId)
		return nil
	end

	local humanoid = model:FindFirstChildOfClass("Humanoid")
	local root = model.PrimaryPart or model:FindFirstChild("HumanoidRootPart") :: BasePart?
	if not humanoid or not root then
		Util.warn("KillerAgent", "%s has no Humanoid or HumanoidRootPart", model.Name)
		return nil
	end

	local self = setmetatable({}, KillerAgent)

	self.killerId = killerId
	self.profile = profile
	self.model = model
	self.humanoid = humanoid
	self.root = root

	self.state = STATE.Patrol
	self.active = false

	self.destination = nil :: Vector3?
	self.destVersion = 0
	self.navComplete = -1

	self.target = nil :: Player?
	self.lastHeardPosition = nil :: Vector3?
	self.lastHeardAt = 0
	self.silenceSince = 0
	self.investigateUntil = 0

	self.stunnedUntil = 0
	self.health = profile.MaxHealth
	self.lastHitAt = 0
	self.lastAttackAt = 0
	self.lastLineAt = 0

	-- Passing the id gets this killer their hand-authored route from the map
	-- data, in order, rather than a guess from room names.
	self.patrolNodes = MapService.getPatrolNodes(killerId, profile.PatrolZones, profile.CanUseCrawlspaces)
	self.patrolIndex = 1
	self.rng = Random.new()

	self.path = PathfindingService:CreatePath({
		AgentRadius = Config.Killer.AgentRadius,
		AgentHeight = Config.Killer.AgentHeight,
		AgentCanJump = Config.Killer.AgentCanJump,
		WaypointSpacing = 6,
	})

	self.stuckPosition = root.Position
	self.stuckSince = os.clock()

	model:SetAttribute(StateKeys.Killer.KillerId, killerId)
	model:SetAttribute(StateKeys.Killer.AIState, STATE.Patrol)
	model:SetAttribute(StateKeys.Killer.Health, self.health)
	model:SetAttribute(StateKeys.Killer.MaxHealth, profile.MaxHealth)
	model:SetAttribute(StateKeys.Killer.StunnedUntil, 0)
	CollectionService:AddTag(model, Tags.ActiveKiller)

	if Config.Debug.ShowKillerState then
		self:_buildDebugLabel()
	end

	return self
end

function KillerAgent:_buildDebugLabel()
	local billboard = Instance.new("BillboardGui")
	billboard.Name = "DebugState"
	billboard.Size = UDim2.fromScale(10, 2)
	billboard.StudsOffsetWorldSpace = Vector3.new(0, 5, 0)
	billboard.AlwaysOnTop = true
	billboard.Parent = self.model

	local label = Instance.new("TextLabel")
	label.Size = UDim2.fromScale(1, 1)
	label.BackgroundTransparency = 1
	label.Font = Enum.Font.Code
	label.TextColor3 = Color3.fromRGB(255, 220, 120)
	label.TextStrokeTransparency = 0
	label.TextScaled = true
	label.Parent = billboard

	task.spawn(function()
		while self.active or self.model.Parent do
			label.Text = `{self.profile.Name}: {self.state} ({math.floor(self.health)})`
			task.wait(0.2)
		end
	end)
end

--==========================================================================
-- State
--==========================================================================

function KillerAgent:_setState(newState: string)
	if self.state == newState then
		return
	end
	self.state = newState
	self.model:SetAttribute(StateKeys.Killer.AIState, newState)

	if newState == STATE.Chase then
		self.humanoid.WalkSpeed = self.profile.ChaseSpeed
	elseif newState == STATE.Investigate then
		-- A shade quicker than a patrol, but not a sprint.
		self.humanoid.WalkSpeed = self.profile.PatrolSpeed + 2
	elseif newState == STATE.Patrol then
		self.humanoid.WalkSpeed = self.profile.PatrolSpeed
		self.target = nil
		self.model:SetAttribute(StateKeys.Killer.TargetName, "")
	elseif newState == STATE.Stunned then
		self.humanoid.WalkSpeed = 0
		self:_setDestination(nil)
	end

	Util.log("KillerAgent", "%s -> %s", self.profile.Name, newState)
end

function KillerAgent:_setDestination(position: Vector3?)
	self.destination = position
	self.destVersion += 1
end

--==========================================================================
-- Senses
--==========================================================================

function KillerAgent:_hasLineOfSight(position: Vector3): boolean
	local origin = self.root.Position + Vector3.new(0, 2, 0)
	local direction = position - origin
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = { self.model }
	params.IgnoreWater = true

	local result = Workspace:Raycast(origin, direction, params)
	if not result then
		return true
	end
	-- Anything within a couple of studs of the target counts as reaching it.
	return (result.Position - position).Magnitude < 3
end

--- Short-range sight, used only as a backstop to the hearing system.
function KillerAgent:_findVisibleTarget(): (Player?, Vector3?)
	if not Config.Killer.Vision.Enabled then
		return nil, nil
	end

	for _, player in TeamService.getAlive() do
		if player:GetAttribute(StateKeys.Player.Hidden) == true then
			continue
		end
		if player:GetAttribute(StateKeys.Player.InSafeZone) == true then
			continue
		end

		local position = Util.getPosition(player)
		if not position then
			continue
		end
		if (position - self.root.Position).Magnitude > Config.Killer.Vision.Range then
			continue
		end
		if Util.angleTo(self.root.CFrame, position) > Config.Killer.Vision.FieldOfViewDegrees / 2 then
			continue
		end
		if self:_hasLineOfSight(position) then
			return player, position
		end
	end
	return nil, nil
end

--==========================================================================
-- Actions
--==========================================================================

function KillerAgent:_speak()
	local now = Util.now()
	if now - self.lastLineAt < 12 then
		return
	end
	self.lastLineAt = now

	local line = Util.pick(self.profile.Lines, self.rng)
	if not line then
		return
	end

	-- Only players close enough to hear it get the line.
	for _, player in TeamService.getParticipants() do
		local position = Util.getPosition(player)
		if position and (position - self.root.Position).Magnitude < 55 then
			Net.fire(player, "Announce", {
				Kind = "KillerLine",
				Text = line,
				Speaker = self.profile.Name,
			})
		end
	end
end

function KillerAgent:_tryAttack(player: Player): boolean
	local now = Util.now()
	if now - self.lastAttackAt < Config.Killer.AttackCooldown then
		return false
	end

	local position = Util.getPosition(player)
	if not position then
		return false
	end
	if (position - self.root.Position).Magnitude > Config.Killer.AttackRange then
		return false
	end
	if player:GetAttribute(StateKeys.Player.InSafeZone) == true then
		return false
	end

	self.lastAttackAt = now

	-- Brief windup so a hit is dodgeable rather than instantaneous.
	task.delay(Config.Killer.AttackWindup, function()
		if not self.active or self.state == STATE.Stunned then
			return
		end
		local currentPosition = Util.getPosition(player)
		if not currentPosition then
			return
		end
		if (currentPosition - self.root.Position).Magnitude > Config.Killer.AttackRange + 3 then
			return -- they got out of reach
		end
		RevivalService.applyDamage(player, Config.Killer.AttackDamage, self.profile.Name)
	end)

	return true
end

--- Rolls to tear open hiding spots near an investigation point.
function KillerAgent:_searchHidingSpots(around: Vector3)
	local spots = HidingService.getSpotsNear(around, Config.Killer.HidingSpotCheckRange)
	for _, spot in spots do
		local distance = (spot.Position - self.root.Position).Magnitude
		local chance = distance < 8 and Config.Killer.HidingSpotCheckChanceClose
			or Config.Killer.HidingSpotCheckChance
		chance *= self.profile.SearchAggression

		-- Someone camping a spot for a long time has all but told the family
		-- where they are.
		if HidingService.isSpotSuspicious(spot) then
			chance = math.min(1, chance * 2)
		end

		if self.rng:NextNumber() <= chance then
			local found = HidingService.searchSpot(spot)
			if found then
				self.target = found
				self:_setState(STATE.Chase)
				local position = Util.getPosition(found)
				if position then
					self:_setDestination(position)
				end
				return
			end
		end
	end
end

--==========================================================================
-- Think loop
--==========================================================================

function KillerAgent:_pickPatrolDestination()
	if #self.patrolNodes == 0 then
		self.patrolNodes =
			MapService.getPatrolNodes(self.killerId, self.profile.PatrolZones, self.profile.CanUseCrawlspaces)
		if #self.patrolNodes == 0 then
			return
		end
	end

	-- Mostly walk the route in order (so patrols read as routes, not as random
	-- teleporting), but jump elsewhere occasionally so players can't set a watch
	-- by it.
	if self.rng:NextNumber() < 0.25 then
		self.patrolIndex = self.rng:NextInteger(1, #self.patrolNodes)
	else
		self.patrolIndex = (self.patrolIndex % #self.patrolNodes) + 1
	end

	local node = self.patrolNodes[self.patrolIndex]
	if node and node.Parent then
		self:_setDestination(node.Position)
	end
end

function KillerAgent:_think()
	local now = Util.now()

	-- Stun ----------------------------------------------------------------
	if now < self.stunnedUntil then
		if self.state ~= STATE.Stunned then
			self:_setState(STATE.Stunned)
		end
		return
	elseif self.state == STATE.Stunned then
		-- Coming out of a stun, they resume hunting whoever staked them.
		self:_setState(self.target and STATE.Chase or STATE.Investigate)
		self.investigateUntil = now + Config.Killer.InvestigateMemory
	end

	-- Health regeneration --------------------------------------------------
	if now - self.lastHitAt > Config.Killer.RegenDelayAfterHit and self.health < self.profile.MaxHealth then
		self.health = math.min(
			self.profile.MaxHealth,
			self.health + self.profile.MaxHealth * Config.Killer.RegenPerSecond * THINK_INTERVAL
		)
		self.model:SetAttribute(StateKeys.Killer.Health, math.floor(self.health))
	end

	-- Safe zones repel ------------------------------------------------------
	local zoneCentre, zoneRadius = safeZoneContaining(self.root.Position)
	if zoneCentre and zoneRadius then
		local away = self.root.Position - zoneCentre
		if away.Magnitude < 0.1 then
			away = self.root.CFrame.LookVector
		end
		self:_setDestination(zoneCentre + away.Unit * (zoneRadius + 12))
		self:_setState(STATE.Patrol)
		return
	end

	-- Hearing ----------------------------------------------------------------
	local heardPlayer, heardPosition, tier =
		NoiseService.findAudibleTarget(self.root.Position, self.profile.HearingMultiplier)

	local seenPlayer, seenPosition = self:_findVisibleTarget()
	if seenPlayer and seenPosition then
		heardPlayer, heardPosition = seenPlayer, seenPosition
		tier = Config.Noise.Tiers[#Config.Noise.Tiers]
	end

	if heardPlayer and heardPosition and tier then
		self.lastHeardPosition = heardPosition
		self.lastHeardAt = now
		self.silenceSince = 0

		if tier.Response == "Rush" or tier.Response == "Investigate" or seenPlayer then
			self.target = heardPlayer
			self.model:SetAttribute(StateKeys.Killer.TargetName, heardPlayer.DisplayName)
			self:_setState(STATE.Chase)
			self:_setDestination(heardPosition)
			self:_speak()
		elseif tier.Response == "Turn" then
			if self.state ~= STATE.Chase then
				self:_setState(STATE.Investigate)
				self.investigateUntil = now + Config.Killer.InvestigateMemory * self.profile.Persistence
				self:_setDestination(heardPosition)
			end
		end
	elseif self.silenceSince == 0 then
		self.silenceSince = now
	end

	-- Per-state behaviour -----------------------------------------------------
	if self.state == STATE.Chase then
		local target = self.target
		if not target or not TeamService.isAlive(target) then
			self.target = nil
			self:_setState(STATE.Investigate)
			self.investigateUntil = now + Config.Killer.InvestigateMemory
			return
		end

		if target:GetAttribute(StateKeys.Player.InSafeZone) == true then
			-- Can't follow them in. Prowl the perimeter instead.
			self:_setState(STATE.Investigate)
			self.investigateUntil = now + Config.Killer.InvestigateMemory
			return
		end

		local targetPosition = Util.getPosition(target)
		if targetPosition then
			local visible = self:_hasLineOfSight(targetPosition)
			local audible = heardPlayer == target

			if visible or audible then
				self.lastHeardPosition = targetPosition
				self.lastHeardAt = now
				self:_setDestination(targetPosition)
				self:_tryAttack(target)
			else
				-- Lost them. Persistence decides how long they keep coming.
				local silence = now - self.lastHeardAt
				if silence > Config.Killer.ChaseGiveUpSilence * self.profile.Persistence then
					self.target = nil
					self:_setState(STATE.Investigate)
					self.investigateUntil = now + Config.Killer.InvestigateMemory
					self:_searchHidingSpots(self.lastHeardPosition or self.root.Position)
				else
					self:_setDestination(self.lastHeardPosition or targetPosition)
				end
			end
		end
		return
	end

	if self.state == STATE.Investigate then
		if now > self.investigateUntil then
			self:_setState(STATE.Patrol)
			self:_pickPatrolDestination()
			return
		end

		local arrived = self.navComplete == self.destVersion
		if arrived or not self.destination then
			-- Poke around the area: check hiding spots, then wander a little.
			self:_searchHidingSpots(self.root.Position)
			if self.state ~= STATE.Investigate then
				return -- the search turned up someone
			end

			local anchor = self.lastHeardPosition or self.root.Position
			local angle = self.rng:NextNumber(0, math.pi * 2)
			local radius = self.rng:NextNumber(4, Config.Killer.SearchRadius)
			self:_setDestination(anchor + Vector3.new(math.cos(angle) * radius, 0, math.sin(angle) * radius))
		end
		return
	end

	-- Patrol
	if self.navComplete == self.destVersion or not self.destination then
		self:_pickPatrolDestination()
	end
end

--==========================================================================
-- Navigation loop
--==========================================================================

function KillerAgent:_onStuck()
	-- Jump and pick somewhere else. Better than standing in a doorway forever.
	self.humanoid.Jump = true
	if self.state == STATE.Patrol then
		self:_pickPatrolDestination()
	else
		local angle = self.rng:NextNumber(0, math.pi * 2)
		self:_setDestination(self.root.Position + Vector3.new(math.cos(angle) * 12, 0, math.sin(angle) * 12))
	end
end

function KillerAgent:_walkWaypoints(waypoints: { PathWaypoint }, version: number): boolean
	for index = 2, #waypoints do
		if not self.active or self.destVersion ~= version then
			return false
		end

		local waypoint = waypoints[index]
		if waypoint.Action == Enum.PathWaypointAction.Jump then
			self.humanoid.Jump = true
		end
		self.humanoid:MoveTo(waypoint.Position)

		local deadline = os.clock() + 4
		while self.active and self.destVersion == version do
			local delta = self.root.Position - waypoint.Position
			if Vector3.new(delta.X, 0, delta.Z).Magnitude <= Config.Killer.WaypointReachedDistance then
				break
			end
			if os.clock() > deadline then
				self:_onStuck()
				return false
			end
			task.wait(0.05)
		end
	end
	return true
end

function KillerAgent:_navigate()
	while self.active do
		local version = self.destVersion
		local destination = self.destination

		if destination and self.state ~= STATE.Stunned then
			local ok = pcall(function()
				self.path:ComputeAsync(self.root.Position, destination)
			end)

			if ok and self.path.Status == Enum.PathStatus.Success then
				self:_walkWaypoints(self.path:GetWaypoints(), version)
			else
				-- No path (a target on the far side of a wall, or a destination
				-- inside geometry). Head that way directly and let the think loop
				-- pick something better next tick.
				self.humanoid:MoveTo(destination)
				task.wait(0.4)
			end

			if self.destVersion == version then
				self.navComplete = version
			end
		end

		task.wait(0.1)
	end
end

--==========================================================================
-- Public
--==========================================================================

--- Applies stake damage. Returns the killer's remaining HP.
--- Killers are immortal; emptying the bar just buys a longer stun.
function KillerAgent:damage(amount: number, stunSeconds: number): number
	self.lastHitAt = Util.now()
	self.health = math.max(0, self.health - amount)
	self.model:SetAttribute(StateKeys.Killer.Health, math.floor(self.health))

	local stun = stunSeconds
	if self.health <= 0 then
		stun += Config.Stakes.StunOnDepleted
		self.health = 0
	end
	self:stun(stun)
	return self.health
end

function KillerAgent:stun(seconds: number)
	self.stunnedUntil = math.max(self.stunnedUntil, Util.now() + seconds)
	self.model:SetAttribute(StateKeys.Killer.StunnedUntil, self.stunnedUntil)
	self:_setState(STATE.Stunned)
	self.humanoid.WalkSpeed = 0
	self.humanoid:MoveTo(self.root.Position)
end

function KillerAgent:getHealth(): number
	return self.health
end

function KillerAgent:isStunned(): boolean
	return Util.now() < self.stunnedUntil
end

function KillerAgent:getPosition(): Vector3
	return self.root.Position
end

function KillerAgent:start()
	if self.active then
		return
	end
	self.active = true

	self.humanoid.WalkSpeed = self.profile.PatrolSpeed
	self:_pickPatrolDestination()

	task.spawn(function()
		while self.active do
			local ok, err = pcall(function()
				self:_think()
			end)
			if not ok then
				Util.warn("KillerAgent", "%s think failed: %s", self.profile.Name, tostring(err))
			end
			task.wait(THINK_INTERVAL)
		end
	end)

	task.spawn(function()
		local ok, err = pcall(function()
			self:_navigate()
		end)
		if not ok then
			Util.warn("KillerAgent", "%s navigation failed: %s", self.profile.Name, tostring(err))
		end
	end)
end

function KillerAgent:stop()
	self.active = false
	self.target = nil
	self:_setDestination(nil)
	if self.model.Parent then
		CollectionService:RemoveTag(self.model, Tags.ActiveKiller)
		self.model:Destroy()
	end
end

KillerAgent.STATE = STATE

return KillerAgent
