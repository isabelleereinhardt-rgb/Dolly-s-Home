--!strict
--[[
	NoiseService.luau
	--------------------------------------------------------------------------
	The stealth loop's core. Every player carries a noise value from 0 to 100.

	This is deliberately SERVER-AUTHORITATIVE. The server samples each
	character's velocity itself rather than trusting a client-reported number,
	so an exploiter can't simply report "I am silent" while sprinting. Sprinting
	is a server-applied WalkSpeed change requested over a remote, which means
	the server always knows the difference between a walk and a run.

	The value replicates to clients as a Player attribute -- Roblox handles the
	replication for us, so the noise meter costs zero RemoteEvent traffic.
	--------------------------------------------------------------------------
]]

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")

local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
local Config = require(Shared.Config)
local StateKeys = require(Shared.StateKeys)
local Util = require(Shared.Util)

local TeamService = require(script.Parent.TeamService)

local NoiseService = {}

-- Internal high-resolution noise values. The Player attribute is a rounded,
-- rate-limited mirror of these.
local levels: { [Player]: number } = {}
local lastReplicated: { [Player]: number } = {}
local crouching: { [Player]: boolean } = {}

-- Sustained noise sources with a duration, e.g. brewing a potion.
type Sustained = { player: Player, perSecond: number, remaining: number }
local sustained: { Sustained } = {}

-- The most recent significant noise each player made, for killer memory.
export type NoiseEvent = {
	Player: Player,
	Position: Vector3,
	Level: number,
	Priority: number,
	At: number,
}

local running = false

--==========================================================================
-- Reads
--==========================================================================

function NoiseService.getLevel(player: Player): number
	return levels[player] or 0
end

function NoiseService.getTier(player: Player)
	return Config.getNoiseTier(NoiseService.getLevel(player))
end

--==========================================================================
-- Writes
--==========================================================================

--- Adds an instant noise spike. `reason` is for debugging only.
function NoiseService.add(player: Player, amount: number, reason: string?)
	if amount <= 0 then
		return
	end
	if not TeamService.isInRound(player) then
		return
	end
	levels[player] = math.clamp((levels[player] or 0) + amount, 0, Config.Noise.Max)
	if Config.Debug.ShowNoiseInOutput then
		print(`[Noise] {player.Name} +{amount} ({reason or "?"}) -> {math.floor(levels[player])}`)
	end
end

--- Adds noise spread over a duration (potion brewing, cranking a valve).
function NoiseService.addOverTime(player: Player, total: number, seconds: number, reason: string?)
	if total <= 0 or seconds <= 0 then
		NoiseService.add(player, total, reason)
		return
	end
	table.insert(sustained, {
		player = player,
		perSecond = total / seconds,
		remaining = seconds,
	})
end

--- Spikes everyone within `radius` of a world position. Used for map-wide
--- events like the grandfather clock chiming, which is not any one player's
--- fault but wakes the whole house.
function NoiseService.addAtPosition(position: Vector3, amount: number, radius: number, reason: string?)
	for _, player in TeamService.getParticipants() do
		local playerPos = Util.getPosition(player)
		if playerPos and (playerPos - position).Magnitude <= radius then
			NoiseService.add(player, amount, reason)
		end
	end
end

function NoiseService.setCrouching(player: Player, isCrouching: boolean)
	crouching[player] = isCrouching
end

function NoiseService.reset(player: Player)
	levels[player] = 0
	lastReplicated[player] = -1
	crouching[player] = false
	player:SetAttribute(StateKeys.Player.Noise, 0)
	player:SetAttribute(StateKeys.Player.NoiseTier, Config.Noise.Tiers[1].Name)
end

function NoiseService.resetAll()
	for _, player in Players:GetPlayers() do
		NoiseService.reset(player)
	end
	table.clear(sustained)
end

--==========================================================================
-- Killer-facing queries
--==========================================================================

--[[
	Returns the player a killer at `origin` should react to, or nil.

	A player is audible when their noise tier's range (scaled by the killer's
	hearing multiplier) reaches the killer. Louder tiers win; among equal tiers,
	the closer player wins. Players who are hidden, injured, in a safe zone, or
	out of the round are skipped.

	Returns: player, position, tier
]]
function NoiseService.findAudibleTarget(origin: Vector3, hearingMultiplier: number)
	local bestPlayer: Player? = nil
	local bestPosition: Vector3? = nil
	local bestTier = nil
	local bestPriority = -1
	local bestDistance = math.huge

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

		local level = levels[player] or 0
		local tier = Config.getNoiseTier(level)
		if tier.Response == "Ignore" then
			-- Still audible if the killer is practically standing on them.
			if (position - origin).Magnitude > tier.Range * hearingMultiplier then
				continue
			end
		end

		local range = tier.Range == math.huge and math.huge or tier.Range * hearingMultiplier
		local distance = (position - origin).Magnitude
		if distance > range then
			continue
		end

		if tier.Priority > bestPriority or (tier.Priority == bestPriority and distance < bestDistance) then
			bestPlayer = player
			bestPosition = position
			bestTier = tier
			bestPriority = tier.Priority
			bestDistance = distance
		end
	end

	return bestPlayer, bestPosition, bestTier
end

--==========================================================================
-- Update loop
--==========================================================================

local function replicate(player: Player)
	local level = levels[player] or 0
	local previous = lastReplicated[player]
	if previous and math.abs(level - previous) < Config.Noise.ReplicateEpsilon then
		return
	end
	lastReplicated[player] = level

	local rounded = math.floor(level * 10 + 0.5) / 10
	player:SetAttribute(StateKeys.Player.Noise, rounded)

	local tier = Config.getNoiseTier(level)
	if player:GetAttribute(StateKeys.Player.NoiseTier) ~= tier.Name then
		player:SetAttribute(StateKeys.Player.NoiseTier, tier.Name)
	end
end

local function step(dt: number)
	-- Sustained sources first.
	for index = #sustained, 1, -1 do
		local entry = sustained[index]
		if not entry.player.Parent then
			table.remove(sustained, index)
			continue
		end
		local slice = math.min(dt, entry.remaining)
		NoiseService.add(entry.player, entry.perSecond * slice, "sustained")
		entry.remaining -= slice
		if entry.remaining <= 0 then
			table.remove(sustained, index)
		end
	end

	for _, player in Players:GetPlayers() do
		local level = levels[player]
		if level == nil then
			levels[player] = 0
			level = 0
		end

		if not TeamService.isAlive(player) then
			-- Out of the round, downed, or in the lobby: bleed noise off fast so
			-- a revived player doesn't come back loud.
			if level > 0 then
				levels[player] = math.max(0, level - Config.Noise.DecayIdle * 3 * dt)
			end
			replicate(player)
			continue
		end

		local _, humanoid, root = Util.getCharacterParts(player)
		if not humanoid or not root then
			replicate(player)
			continue
		end

		local hidden = player:GetAttribute(StateKeys.Player.Hidden) == true
		local isCrouching = crouching[player] == true

		-- Horizontal speed only -- falling shouldn't read as running.
		local velocity = root.AssemblyLinearVelocity
		local speed = Vector3.new(velocity.X, 0, velocity.Z).Magnitude

		local generated = 0
		if not hidden and speed > 1 then
			-- Anything above the walk baseline counts as a run. Using measured
			-- speed rather than the sprint flag means speed potions, conveyors
			-- and exploited WalkSpeed all correctly read as loud.
			local walkThreshold = Config.Player.WalkSpeed + 1
			if isCrouching then
				generated = Config.Noise.CrouchRate
			elseif speed > walkThreshold then
				-- Scale between walk and sprint rates by how fast they're going.
				local over = math.clamp(
					(speed - walkThreshold) / math.max(1, Config.Player.SprintSpeed - walkThreshold),
					0,
					2
				)
				generated = Util.lerp(Config.Noise.WalkRate, Config.Noise.SprintRate, math.min(over, 1))
					+ math.max(0, over - 1) * Config.Noise.SprintRate * 0.5
			else
				generated = Config.Noise.WalkRate * (speed / Config.Player.WalkSpeed)
			end
		end

		if generated > 0 then
			levels[player] = math.clamp(level + generated * dt, 0, Config.Noise.Max)
		else
			local decay = isCrouching and Config.Noise.DecayCrouched or Config.Noise.DecayIdle
			levels[player] = math.max(0, level - decay * dt)
		end

		replicate(player)
	end
end

--==========================================================================
-- Lifecycle
--==========================================================================

function NoiseService.start()
	if running then
		return
	end
	running = true

	Players.PlayerAdded:Connect(function(player)
		NoiseService.reset(player)
	end)
	Players.PlayerRemoving:Connect(function(player)
		levels[player] = nil
		lastReplicated[player] = nil
		crouching[player] = nil
	end)
	for _, player in Players:GetPlayers() do
		NoiseService.reset(player)
	end

	-- Fixed-rate loop rather than per-frame: noise doesn't need 60 Hz, and
	-- 10 Hz keeps attribute replication sane with a full server.
	task.spawn(function()
		local interval = 1 / Config.Noise.TickRate
		local last = os.clock()
		while true do
			task.wait(interval)
			local now = os.clock()
			local dt = now - last
			last = now
			local ok, err = pcall(step, dt)
			if not ok then
				Util.warn("NoiseService", "step failed: %s", tostring(err))
			end
		end
	end)
end

return NoiseService
