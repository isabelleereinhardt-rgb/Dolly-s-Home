--!strict
--[[
	PlayerService.luau
	--------------------------------------------------------------------------
	The single authority on how fast a player moves.

	Sprinting, hiding, being downed, carrying a pile of iron crosses and
	drinking a speed potion all want to set WalkSpeed, and if each of them wrote
	it directly the last one to fire would win -- which is how you end up frozen
	in place after climbing out of a locker.

	Instead every one of those is an attribute, and this service recomputes the
	final speed from all of them a few times a second. Attributes are the truth;
	WalkSpeed is derived.
	--------------------------------------------------------------------------
]]

local Players = game:GetService("Players")

local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
local Config = require(Shared.Config)
local Net = require(Shared.Net)
local StateKeys = require(Shared.StateKeys)
local Util = require(Shared.Util)

local NoiseService = require(script.Parent.NoiseService)
local TeamService = require(script.Parent.TeamService)

local PlayerService = {}

local sprintRequested: { [Player]: boolean } = {}
local lastSprintAt: { [Player]: number } = {}

--==========================================================================
-- Speed
--==========================================================================

--- Computes what this player's WalkSpeed should be right now.
local function resolveSpeed(player: Player): number
	if player:GetAttribute(StateKeys.Player.Hidden) == true then
		return 0
	end
	if player:GetAttribute(StateKeys.Player.Injured) == true then
		return Config.Revival.CrawlSpeed
	end

	local speed = Config.Player.WalkSpeed

	local stamina = (player:GetAttribute(StateKeys.Player.Stamina) or Config.Player.MaxStamina) :: number
	local wantsSprint = sprintRequested[player] == true
	local canSprint = not Config.Player.StaminaEnabled or stamina > 0

	if wantsSprint and canSprint and TeamService.isAlive(player) then
		speed = Config.Player.SprintSpeed
	end

	-- Crosses weigh you down: each one you're carrying compounds the penalty,
	-- up to six.
	local crosses = (player:GetAttribute(StateKeys.Player.CarriedCrosses) or 0) :: number
	if crosses > 0 then
		speed *= Config.Objectives.Crosses.CarrySlowdown ^ math.min(crosses, 6)
	end

	-- Speed potion.
	local boostUntil = (player:GetAttribute(StateKeys.Player.SpeedBoostUntil) or 0) :: number
	if boostUntil > Util.now() then
		speed *= Config.Shop.SpeedPotion.Multiplier
	end

	return math.max(6, speed)
end

--- Recomputes and applies a player's movement speed immediately.
function PlayerService.refreshSpeed(player: Player)
	local _, humanoid = Util.getCharacterParts(player)
	if not humanoid then
		return
	end

	local target = resolveSpeed(player)
	if math.abs(humanoid.WalkSpeed - target) > 0.05 then
		humanoid.WalkSpeed = target
	end

	local shouldJump = target > 0
		and player:GetAttribute(StateKeys.Player.Hidden) ~= true
		and player:GetAttribute(StateKeys.Player.Injured) ~= true
	local desiredJump = shouldJump and Config.Player.JumpPower or 0
	if humanoid.JumpPower ~= desiredJump then
		humanoid.JumpPower = desiredJump
	end
end

--==========================================================================
-- Stamina
--==========================================================================

local function stepStamina(player: Player, dt: number)
	if not Config.Player.StaminaEnabled then
		return
	end

	local stamina = (player:GetAttribute(StateKeys.Player.Stamina) or Config.Player.MaxStamina) :: number

	local _, humanoid, root = Util.getCharacterParts(player)
	local moving = false
	if root then
		local velocity = root.AssemblyLinearVelocity
		moving = Vector3.new(velocity.X, 0, velocity.Z).Magnitude > Config.Player.WalkSpeed + 1
	end

	local isSprinting = sprintRequested[player] == true and moving and stamina > 0 and TeamService.isAlive(player)

	if isSprinting then
		stamina -= Config.Player.StaminaDrainPerSecond * dt
		lastSprintAt[player] = Util.now()
	elseif Util.now() - (lastSprintAt[player] or 0) >= Config.Player.StaminaRegenDelay then
		stamina += Config.Player.StaminaRegenPerSecond * dt
	end

	stamina = math.clamp(stamina, 0, Config.Player.MaxStamina)
	player:SetAttribute(StateKeys.Player.Stamina, math.floor(stamina * 10 + 0.5) / 10)

	if stamina <= 0 and sprintRequested[player] then
		-- Out of breath. Drop the request so they have to press again once
		-- they've recovered, rather than stuttering at the threshold.
		sprintRequested[player] = false
		player:SetAttribute(StateKeys.Player.Sprinting, false)
	end
end

--==========================================================================
-- Consumables
--==========================================================================

function PlayerService.applySpeedPotion(player: Player, durationSeconds: number)
	player:SetAttribute(StateKeys.Player.SpeedBoostUntil, Util.now() + durationSeconds)
	PlayerService.refreshSpeed(player)
end

--- Clears round-scoped movement modifiers (crosses, hiding). The speed potion
--- is deliberately NOT cleared -- it's bought with coins and runs on real time.
function PlayerService.resetRoundModifiers(player: Player)
	player:SetAttribute(StateKeys.Player.CarriedCrosses, 0)
	sprintRequested[player] = false
	player:SetAttribute(StateKeys.Player.Sprinting, false)
	player:SetAttribute(StateKeys.Player.Stamina, Config.Player.MaxStamina)
	NoiseService.setCrouching(player, false)
	PlayerService.refreshSpeed(player)
end

--==========================================================================
-- Lifecycle
--==========================================================================

function PlayerService.start()
	Net.Events.SetSprinting.OnServerEvent:Connect(function(player, wantsSprint)
		sprintRequested[player] = wantsSprint == true
		player:SetAttribute(StateKeys.Player.Sprinting, sprintRequested[player])
		PlayerService.refreshSpeed(player)
	end)

	Net.Events.SetCrouching.OnServerEvent:Connect(function(player, wantsCrouch)
		-- Crouching only changes how much noise you make; NoiseService owns it.
		NoiseService.setCrouching(player, wantsCrouch == true)
	end)

	local function onPlayerAdded(player: Player)
		player:SetAttribute(StateKeys.Player.Stamina, Config.Player.MaxStamina)
		player:SetAttribute(StateKeys.Player.Sprinting, false)
		player:SetAttribute(StateKeys.Player.CarriedCrosses, 0)
		player:SetAttribute(StateKeys.Player.SpeedBoostUntil, 0)

		player.CharacterAdded:Connect(function()
			task.wait(0.2)
			PlayerService.refreshSpeed(player)
		end)
	end

	Players.PlayerAdded:Connect(onPlayerAdded)
	for _, player in Players:GetPlayers() do
		onPlayerAdded(player)
	end

	Players.PlayerRemoving:Connect(function(player)
		sprintRequested[player] = nil
		lastSprintAt[player] = nil
	end)

	task.spawn(function()
		local last = os.clock()
		while true do
			task.wait(0.1)
			local now = os.clock()
			local dt = now - last
			last = now

			for _, player in Players:GetPlayers() do
				local ok, err = pcall(function()
					stepStamina(player, dt)
					PlayerService.refreshSpeed(player)
				end)
				if not ok then
					Util.warn("PlayerService", "update failed for %s: %s", player.Name, tostring(err))
				end
			end
		end
	end)
end

return PlayerService
