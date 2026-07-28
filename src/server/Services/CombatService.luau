--!strict
--[[
	CombatService.luau
	--------------------------------------------------------------------------
	Stakes.

	Killers are immortal, and that is the point: draining a killer's bar buys
	you a stun, not a kill. Combat here is an escape tool -- something you spend
	to pull a killer off a downed teammate -- rather than a win condition. The
	stronger stakes buy longer stuns, not lethality.

	The swing is validated entirely on the server: cooldown, range and facing
	are all rechecked here, so a client firing the Attack remote in a loop gets
	nothing.
	--------------------------------------------------------------------------
]]

local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
local Config = require(Shared.Config)
local Net = require(Shared.Net)
local StateKeys = require(Shared.StateKeys)
local Util = require(Shared.Util)

local DataService = require(script.Parent.DataService)
local KillerService = require(script.Parent.KillerService)
local NoiseService = require(script.Parent.NoiseService)
local TeamService = require(script.Parent.TeamService)

local CombatService = {}

--==========================================================================
-- Helpers
--==========================================================================

local function getEquippedTier(player: Player)
	local equipped = player:GetAttribute(StateKeys.Player.EquippedStake) :: string?
	if not equipped then
		local profile = DataService.peek(player)
		equipped = profile and profile.EquippedStake or Config.Economy.StartingStake
		player:SetAttribute(StateKeys.Player.EquippedStake, equipped)
	end
	return Config.getStakeTier(equipped)
end

--- The killer in front of the player, within range, if any.
local function findTarget(player: Player)
	local _, _, root = Util.getCharacterParts(player)
	if not root then
		return nil
	end

	local best = nil
	local bestDistance = math.huge

	for _, agent in KillerService.getAgents() do
		local distance = (agent:getPosition() - root.Position).Magnitude
		if distance > Config.Stakes.AttackRange then
			continue
		end
		-- Has to be roughly in front of you, not behind your back.
		if Util.angleTo(root.CFrame, agent:getPosition()) > 80 then
			continue
		end
		if distance < bestDistance then
			best = agent
			bestDistance = distance
		end
	end

	return best
end

local function playHitEffect(position: Vector3, color: Color3)
	local spark = Instance.new("Part")
	spark.Name = "StakeHit"
	spark.Anchored = true
	spark.CanCollide = false
	spark.CanQuery = false
	spark.Size = Vector3.new(1, 1, 1)
	spark.Transparency = 1
	spark.CFrame = CFrame.new(position)
	spark.Parent = workspace

	local emitter = Instance.new("ParticleEmitter")
	emitter.Color = ColorSequence.new(color)
	emitter.Lifetime = NumberRange.new(0.25, 0.5)
	emitter.Speed = NumberRange.new(8, 16)
	emitter.SpreadAngle = Vector2.new(180, 180)
	emitter.Rate = 0
	emitter.Size = NumberSequence.new(0.5)
	emitter.Parent = spark
	emitter:Emit(24)

	game:GetService("Debris"):AddItem(spark, 1.5)
end

--==========================================================================
-- Attacks
--==========================================================================

function CombatService.attack(player: Player)
	if not TeamService.isAlive(player) then
		return
	end
	if player:GetAttribute(StateKeys.Player.Hidden) == true then
		return
	end

	local now = Util.now()
	local readyAt = (player:GetAttribute(StateKeys.Player.StakeReadyAt) or 0) :: number
	if now < readyAt then
		return
	end

	local tier = getEquippedTier(player)
	if not tier then
		return
	end

	player:SetAttribute(StateKeys.Player.StakeReadyAt, now + Config.Stakes.Cooldown)

	-- Swinging is loud whether or not you connect.
	NoiseService.add(player, Config.Noise.Actions.Attack, "stake swing")

	local agent = findTarget(player)
	if not agent then
		Net.fire(player, "Announce", { Kind = "Combat", Text = "You swing at nothing." })
		return
	end

	local remaining = agent:damage(tier.Damage, tier.StunSeconds)
	playHitEffect(agent:getPosition() + Vector3.new(0, 2, 0), Color3.fromRGB(220, 60, 60))

	Net.fireAll("Announce", {
		Kind = "Stake",
		Text = `{player.DisplayName} staked {agent.profile.Name}!`,
		KillerId = agent.killerId,
		KillerName = agent.profile.Name,
		Health = remaining,
		MaxHealth = agent.profile.MaxHealth,
		StunSeconds = tier.StunSeconds,
	})

	Util.log("CombatService", "%s hit %s for %d (%d left)", player.Name, agent.profile.Name, tier.Damage, remaining)
end

--==========================================================================
-- Equipping
--==========================================================================

function CombatService.equip(player: Player, stakeId: string)
	if not DataService.ownsStake(player, stakeId) then
		return
	end
	if DataService.setEquippedStake(player, stakeId) then
		player:SetAttribute(StateKeys.Player.EquippedStake, stakeId)
	end
end

--- Puts a player's saved stake onto their attribute at round start.
function CombatService.syncEquipped(player: Player)
	local profile = DataService.peek(player)
	local equipped = profile and profile.EquippedStake or Config.Economy.StartingStake
	player:SetAttribute(StateKeys.Player.EquippedStake, equipped)
	player:SetAttribute(StateKeys.Player.StakeReadyAt, 0)
end

--==========================================================================
-- Lifecycle
--==========================================================================

function CombatService.start()
	Net.Events.Attack.OnServerEvent:Connect(function(player)
		local ok, err = pcall(CombatService.attack, player)
		if not ok then
			Util.warn("CombatService", "attack failed: %s", tostring(err))
		end
	end)

	Net.Events.EquipStake.OnServerEvent:Connect(function(player, stakeId)
		if type(stakeId) == "string" then
			CombatService.equip(player, stakeId)
		end
	end)
end

return CombatService
