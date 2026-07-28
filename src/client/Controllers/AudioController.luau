--!strict
--[[
	AudioController.luau
	--------------------------------------------------------------------------
	Proximity dread: a heartbeat that gets faster and louder as the nearest
	killer closes, and per-killer approach loops played from the killer's own
	position so they're directional.

	Killers are found client-side via the DH_ActiveKiller tag rather than
	replicated over a remote. Their models are already replicated -- their
	positions are public knowledge to the engine, so there's nothing to hide by
	withholding them, and reading tags locally costs the server nothing.

	Every SoundId in Shared/Sounds.luau is blank until you fill it in; this
	controller does nothing audible until then and does not error.
	--------------------------------------------------------------------------
]]

local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local SoundService = game:GetService("SoundService")

local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
local Config = require(Shared.Config)
local Net = require(Shared.Net)
local Sounds = require(Shared.Sounds)
local StateKeys = require(Shared.StateKeys)
local Tags = require(Shared.Tags)
local Util = require(Shared.Util)

local player = Players.LocalPlayer

local AudioController = {}

-- Distance at which the heartbeat starts, and where it peaks.
local HEARTBEAT_START = 70
local HEARTBEAT_PEAK = 12

local heartbeat: Sound? = nil
local ambience: Sound? = nil
local approachSounds: { [Model]: Sound } = {}
local currentAmbienceKey = ""

--==========================================================================
-- Heartbeat
--==========================================================================

local function nearestKillerDistance(): (number, string?)
	local origin = Util.getPosition(player)
	if not origin then
		return math.huge, nil
	end

	local best = math.huge
	local bestId: string? = nil

	for _, model in CollectionService:GetTagged(Tags.ActiveKiller) do
		if not model:IsA("Model") or not model.PrimaryPart then
			continue
		end
		local distance = (model.PrimaryPart.Position - origin).Magnitude
		if distance < best then
			best = distance
			bestId = model:GetAttribute(StateKeys.Killer.KillerId) :: string?
		end
	end

	return best, bestId
end

local function updateHeartbeat(dt: number)
	if not heartbeat then
		return
	end

	local inRound = Net.getStateValue(StateKeys.Game.Phase, "") == StateKeys.Phase.Active
	local safe = player:GetAttribute(StateKeys.Player.InSafeZone) == true
	local eliminated = player:GetAttribute(StateKeys.Player.Eliminated) == true

	local targetVolume = 0
	local targetPitch = 1

	if inRound and not safe and not eliminated then
		local distance = nearestKillerDistance()
		if distance < HEARTBEAT_START then
			-- 0 at the outer edge, 1 when they're on top of you.
			local closeness = math.clamp(
				(HEARTBEAT_START - distance) / (HEARTBEAT_START - HEARTBEAT_PEAK),
				0,
				1
			)
			targetVolume = closeness * 0.55
			targetPitch = 0.85 + closeness * 0.75
		end

		-- Being downed is its own kind of panic.
		if player:GetAttribute(StateKeys.Player.Injured) == true then
			targetVolume = math.max(targetVolume, 0.45)
			targetPitch = math.max(targetPitch, 1.4)
		end
	end

	heartbeat.Volume = Util.damp(heartbeat.Volume, targetVolume, 4, dt)
	heartbeat.PlaybackSpeed = Util.damp(heartbeat.PlaybackSpeed, targetPitch, 4, dt)

	if heartbeat.Volume > 0.005 and not heartbeat.IsPlaying then
		heartbeat:Play()
	elseif heartbeat.Volume <= 0.005 and heartbeat.IsPlaying then
		heartbeat:Stop()
	end
end

--==========================================================================
-- Per-killer approach loops
--==========================================================================

local function syncApproachSounds()
	local seen: { [Model]: boolean } = {}

	for _, model in CollectionService:GetTagged(Tags.ActiveKiller) do
		if not model:IsA("Model") or not model.PrimaryPart then
			continue
		end
		seen[model] = true

		if approachSounds[model] then
			continue
		end

		local killerId = model:GetAttribute(StateKeys.Killer.KillerId) :: string?
		local soundId = killerId and Sounds.KillerApproach[killerId] or nil
		local sound = Sounds.create(soundId, model.PrimaryPart, {
			Looped = true,
			Volume = 0.6,
			RollOffMode = Enum.RollOffMode.InverseTapered,
			RollOffMinDistance = 8,
			RollOffMaxDistance = 90,
		})

		if sound then
			sound:Play()
			approachSounds[model] = sound
		end
	end

	for model, sound in approachSounds do
		if not seen[model] or not model.Parent then
			sound:Destroy()
			approachSounds[model] = nil
		end
	end
end

--==========================================================================
-- Ambience
--==========================================================================

local function updateAmbience()
	local phase = Net.getStateValue(StateKeys.Game.Phase, "")
	local mapId = Net.getStateValue(StateKeys.Game.MapId, "") :: string

	local key = (phase == StateKeys.Phase.Active or phase == StateKeys.Phase.Starting) and mapId ~= "" and mapId
		or "Lobby"

	if key == currentAmbienceKey then
		return
	end
	currentAmbienceKey = key

	if ambience then
		ambience:Destroy()
		ambience = nil
	end

	ambience = Sounds.create(Sounds.Ambience[key], SoundService, {
		Looped = true,
		Volume = 0.35,
	})
	if ambience then
		ambience:Play()
	end
end

--==========================================================================
-- One-shots
--==========================================================================

local function playEffect(name: string, volume: number?)
	local sound = Sounds.create(Sounds.Effects[name], SoundService, { Volume = volume or 0.6 })
	if sound then
		sound:Play()
		sound.Ended:Once(function()
			sound:Destroy()
		end)
	end
end

AudioController.playEffect = playEffect

--==========================================================================
-- Lifecycle
--==========================================================================

function AudioController.start()
	heartbeat = Sounds.create(Sounds.Heartbeat, SoundService, {
		Looped = true,
		Volume = 0,
	})

	Net.Events.TaskCompleted.OnClientEvent:Connect(function()
		playEffect("TaskComplete")
	end)

	Net.Events.InjuredAlert.OnClientEvent:Connect(function(payload)
		if payload.Kind == "Downed" then
			playEffect(payload.UserId == player.UserId and "PlayerDowned" or "Discovered", 0.5)
		elseif payload.Kind == "Revived" then
			playEffect("PlayerRevived", 0.5)
		end
	end)

	Net.Events.RoundResults.OnClientEvent:Connect(function(payload)
		playEffect(payload.Victory and "Victory" or "Defeat", 0.7)
	end)

	Net.Events.HelperMessage.OnClientEvent:Connect(function()
		playEffect("HelperAppear", 0.5)
	end)

	local state = Net.getState()
	state:GetAttributeChangedSignal(StateKeys.Game.Phase):Connect(updateAmbience)
	state:GetAttributeChangedSignal(StateKeys.Game.MapId):Connect(updateAmbience)
	updateAmbience()

	CollectionService:GetInstanceAddedSignal(Tags.ActiveKiller):Connect(syncApproachSounds)
	CollectionService:GetInstanceRemovedSignal(Tags.ActiveKiller):Connect(syncApproachSounds)
	syncApproachSounds()

	RunService.Heartbeat:Connect(function(dt)
		local ok, err = pcall(updateHeartbeat, dt)
		if not ok and Config.Debug.Verbose then
			warn(`[AudioController] {err}`)
		end
	end)
end

return AudioController
