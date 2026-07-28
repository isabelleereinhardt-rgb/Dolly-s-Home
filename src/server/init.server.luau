--!strict
--[[
	init.server.luau
	--------------------------------------------------------------------------
	Server bootstrap for Dolly's Home.

	Start order matters. Services that only wire up event handlers can go in any
	order, but a few have real dependencies:

	  * Net must exist before anything fires a remote (requiring Shared.Net
	    builds the folder, which the first require below does).
	  * TeamService creates the teams every other service checks membership
	    against.
	  * MapService.buildLobby must run before ShopService looks for the shop
	    stand and before GameStateManager tries to teleport anyone.
	  * GameStateManager goes last, because starting it starts the round loop.
	--------------------------------------------------------------------------
]]

local Lighting = game:GetService("Lighting")
local Players = game:GetService("Players")

local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
local Config = require(Shared.Config)
local Net = require(Shared.Net) -- builds ReplicatedStorage.DollysHome
local StateKeys = require(Shared.StateKeys)

--[[
	Atmosphere.

	These are set here rather than left to the Rojo project file, so the game
	looks right whether it was synced with Rojo or dragged in from an .rbxmx.
	Each is applied on its own so that one unwritable property (Technology is
	Studio-only on some versions) can't take the rest down with it.
]]
local function applyAtmosphere()
	--[[
		Fog is the single biggest lever on how this reads.

		The first pass used FogEnd = 260, which does nothing at all indoors --
		the whole house is only 116 x 88 studs, so you are never far enough from
		anything for fog to engage. Pulling it in to 85 means a corridor fades
		to black about a room and a half away, which is exactly the distance at
		which "something is down there" beats "there is nothing down there".
	]]
	local lightingProps = {
		Ambient = Color3.fromRGB(8, 8, 11),
		OutdoorAmbient = Color3.fromRGB(14, 16, 22),
		Brightness = 0.35,
		ClockTime = 0,
		GeographicLatitude = 30,
		FogColor = Color3.fromRGB(10, 11, 12),
		FogStart = 12,
		FogEnd = 85,
		GlobalShadows = true,
		EnvironmentDiffuseScale = 0.12,
		EnvironmentSpecularScale = 0.08,
		Technology = Enum.Technology.ShadowMap,
	}

	for property, value in lightingProps do
		pcall(function()
			(Lighting :: any)[property] = value
		end)
	end

	-- Haze, so light has something to fall through and distance actually reads.
	pcall(function()
		local atmosphere = Lighting:FindFirstChildOfClass("Atmosphere") or Instance.new("Atmosphere")
		atmosphere.Density = 0.42
		atmosphere.Offset = 0.1
		atmosphere.Color = Color3.fromRGB(140, 140, 132)
		atmosphere.Decay = Color3.fromRGB(58, 62, 55)
		atmosphere.Glare = 0.1
		atmosphere.Haze = 1.6
		atmosphere.Parent = Lighting
	end)

	-- Drain the colour a little and crush the blacks. The mockup's palette is
	-- already muted; this stops Roblox's renderer brightening it back up.
	pcall(function()
		local grade = Lighting:FindFirstChild("DollysHomeGrade") :: ColorCorrectionEffect?
			or Instance.new("ColorCorrectionEffect")
		grade.Name = "DollysHomeGrade"
		grade.Brightness = -0.06
		grade.Contrast = 0.16
		grade.Saturation = -0.22
		grade.TintColor = Color3.fromRGB(226, 226, 236)
		grade.Parent = Lighting
	end)

	-- Players who reset come back to the lobby; three seconds is long enough to
	-- read the results screen but short enough not to feel like a punishment.
	pcall(function()
		Players.RespawnTime = 3
	end)
end

applyAtmosphere()

local Services = script.Services

local AvaService = require(Services.AvaService)
local CombatService = require(Services.CombatService)
local DataService = require(Services.DataService)
local GameStateManager = require(Services.GameStateManager)
local HidingService = require(Services.HidingService)
local MapService = require(Services.MapService)
local NoiseService = require(Services.NoiseService)
local ObjectiveService = require(Services.ObjectiveService)
local PlayerService = require(Services.PlayerService)
local RevivalService = require(Services.RevivalService)
local SafeZoneService = require(Services.SafeZoneService)
local ShopService = require(Services.ShopService)
local StatsService = require(Services.StatsService)
local TeamService = require(Services.TeamService)
local VoteService = require(Services.VoteService)

Net.setStateValue(StateKeys.Game.Phase, StateKeys.Phase.Booting)

local START_ORDER: { { Name: string, Start: () -> () } } = {
	{ Name = "TeamService", Start = TeamService.start },
	{ Name = "DataService", Start = DataService.start },
	{ Name = "NoiseService", Start = NoiseService.start },
	{ Name = "PlayerService", Start = PlayerService.start },
	{ Name = "RevivalService", Start = RevivalService.start },
	{ Name = "HidingService", Start = HidingService.start },
	{ Name = "SafeZoneService", Start = SafeZoneService.start },
	{ Name = "ObjectiveService", Start = ObjectiveService.start },
	{ Name = "CombatService", Start = CombatService.start },
	{ Name = "VoteService", Start = VoteService.start },
	{ Name = "StatsService", Start = StatsService.start },
	{ Name = "AvaService", Start = AvaService.start },
	{ Name = "ShopService", Start = ShopService.start },
}

MapService.buildLobby()

for _, entry in START_ORDER do
	local ok, err = pcall(entry.Start)
	if not ok then
		warn(`[DollysHome] {entry.Name} failed to start: {err}`)
	end
end

GameStateManager.start()

print(
	`[DollysHome] server ready -- {Config.Round.RoundSeconds // 60} minute rounds, `
		.. `{Config.Round.IntermissionSeconds}s intermission, `
		.. `{#Config.getEnabledMaps()} map(s) enabled.`
)
