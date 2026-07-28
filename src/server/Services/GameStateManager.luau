--!strict
--[[
	GameStateManager.luau
	--------------------------------------------------------------------------
	The round loop.

	  INTERMISSION (50s)  lobby, map voting for the first 30
	  STARTING     (6s)   map loads, killers spawn, players are placed
	  ACTIVE       (600s) the round
	  RESULTS      (15s)  scoreboard, payouts
	  -> back to INTERMISSION

	Phase and deadline replicate as attributes rather than a ticking counter:
	the server writes PhaseEndsAt once, and every client renders its own smooth
	countdown against the synced clock. One write per phase instead of one per
	second, and no drift.
	--------------------------------------------------------------------------
]]

local Players = game:GetService("Players")

local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
local Config = require(Shared.Config)
local Net = require(Shared.Net)
local StateKeys = require(Shared.StateKeys)
local Util = require(Shared.Util)

local AvaService = require(script.Parent.AvaService)
local CombatService = require(script.Parent.CombatService)
local HelperService = require(script.Parent.HelperService)
local HidingService = require(script.Parent.HidingService)
local KillerService = require(script.Parent.KillerService)
local MapService = require(script.Parent.MapService)
local NoiseService = require(script.Parent.NoiseService)
local ObjectiveService = require(script.Parent.ObjectiveService)
local PlayerService = require(script.Parent.PlayerService)
local RevivalService = require(script.Parent.RevivalService)
local SafeZoneService = require(script.Parent.SafeZoneService)
local StatsService = require(script.Parent.StatsService)
local TeamService = require(script.Parent.TeamService)
local VoteService = require(script.Parent.VoteService)

local GameStateManager = {}

local PHASE = StateKeys.Phase

local roundNumber = 0
local objectivesComplete = false
local roundDecided = false
local rng = Random.new()

--==========================================================================
-- Phase helpers
--==========================================================================

local function setPhase(phase: string, duration: number)
	Net.setStateValue(StateKeys.Game.Phase, phase)
	Net.setStateValue(StateKeys.Game.PhaseStartedAt, Util.now())
	Net.setStateValue(StateKeys.Game.PhaseEndsAt, Util.now() + duration)
	Util.log("GameState", "phase -> %s (%ds)", phase, duration)
end

local function refreshCounts()
	Net.setStateValue(StateKeys.Game.AlivePlayers, #TeamService.getAlive())
	Net.setStateValue(StateKeys.Game.TotalPlayers, #Players:GetPlayers())
end

local function teleportToLobby(player: Player)
	local spawns = MapService.getLobbySpawns()
	if #spawns == 0 then
		return
	end
	local destination = spawns[rng:NextInteger(1, #spawns)]
	local character = player.Character
	if character and character.PrimaryPart then
		character:PivotTo(destination)
	end
end

local function teleportAllToLobby()
	for _, player in Players:GetPlayers() do
		teleportToLobby(player)
	end
end

--==========================================================================
-- Win / loss
--==========================================================================

--[[
	Called whenever the roster or objective progress changes. Deliberately
	idempotent and guarded by `roundDecided`, because a wipe and the last
	objective completing can land in the same frame.
]]
local function evaluateRound()
	if Net.getStateValue(StateKeys.Game.Phase, "") ~= PHASE.Active or roundDecided then
		return
	end

	refreshCounts()

	if objectivesComplete then
		-- Someone has to be left standing to have actually escaped.
		if #TeamService.getAlive() > 0 then
			roundDecided = true
			GameStateManager.finishRound(true)
		else
			roundDecided = true
			GameStateManager.finishRound(false)
		end
		return
	end

	if TeamService.isWipe() then
		roundDecided = true
		GameStateManager.finishRound(false)
	end
end

--==========================================================================
-- Phases
--==========================================================================

local function runIntermission()
	setPhase(PHASE.Intermission, Config.Round.IntermissionSeconds)
	Net.setStateValue(StateKeys.Game.Result, "")
	Net.setStateValue(StateKeys.Game.MapId, "")
	Net.setStateValue(StateKeys.Game.MapName, "")
	Net.setStateValue(StateKeys.Game.KillerNames, "")
	Net.setStateValue(StateKeys.Game.ComboId, "")

	TeamService.resetAll()
	NoiseService.resetAll()
	StatsService.clear()
	for _, player in Players:GetPlayers() do
		PlayerService.resetRoundModifiers(player)
	end

	teleportAllToLobby()
	refreshCounts()

	Net.fireAll("RoundStatus", {
		Phase = PHASE.Intermission,
		EndsAt = Net.getStateValue(StateKeys.Game.PhaseEndsAt, 0),
	})

	VoteService.openVoting()
	task.wait(Config.Round.VotingSeconds)
	local mapId = VoteService.closeVoting()

	local info = MapService.getMapInfo(mapId)
	Net.fireAll("Announce", {
		Kind = "MapChosen",
		Text = `Next map: {info and info.Name or mapId}`,
	})

	-- The rest of the intermission is just the countdown.
	local remaining = Net.getStateValue(StateKeys.Game.PhaseEndsAt, Util.now()) - Util.now()
	if remaining > 0 then
		task.wait(remaining)
	end

	return mapId
end

--- True if there are enough people to bother starting.
local function hasEnoughPlayers(): boolean
	return #Players:GetPlayers() >= Config.Round.MinPlayersToStart
end

local function runStarting(mapId: string): boolean
	setPhase(PHASE.Starting, Config.Round.StartupSeconds)
	roundNumber += 1
	objectivesComplete = false
	roundDecided = false

	Net.setStateValue(StateKeys.Game.RoundNumber, roundNumber)

	local map = MapService.load(mapId)
	if not map then
		Net.fireAll("Announce", { Kind = "Error", Text = "That map failed to load. Falling back to The House." })
		map = MapService.load("TheHouse")
		if not map then
			Util.warn("GameState", "no map could be loaded; aborting round")
			return false
		end
		mapId = "TheHouse"
	end

	local info = MapService.getMapInfo(mapId)
	Net.setStateValue(StateKeys.Game.MapId, mapId)
	Net.setStateValue(StateKeys.Game.MapName, info and info.Name or mapId)

	-- Objectives first: setupFuses needs to darken the safe zones before
	-- anybody is standing in one.
	local comboId = ObjectiveService.beginRound()
	Net.setStateValue(StateKeys.Game.ComboId, comboId)

	-- No-op on any map without a DH_AvaGrave part.
	AvaService.spawn()

	-- Everyone currently in the server joins the round.
	local participants = Players:GetPlayers()
	for _, player in participants do
		TeamService.enterRound(player)
		CombatService.syncEquipped(player)
		PlayerService.resetRoundModifiers(player)
		NoiseService.reset(player)
	end
	StatsService.beginRound(participants)

	local spawns = MapService.getPlayerSpawns()
	local placements = MapService.allocateSpawns(spawns, #participants, rng)
	for index, player in participants do
		local character = player.Character
		local placement = placements[index]
		if character and character.PrimaryPart and placement then
			character:PivotTo(placement)
			local _, humanoid = Util.getCharacterParts(player)
			if humanoid then
				humanoid.Health = humanoid.MaxHealth
			end
		end
	end

	local killerIds = KillerService.selectKillers()
	local spawned = KillerService.spawnKillers(killerIds)
	Net.setStateValue(StateKeys.Game.KillerNames, table.concat(KillerService.getActiveNames(), ", "))

	if #spawned == 0 then
		Util.warn("GameState", "no killers spawned -- the round will be trivially winnable")
	end

	refreshCounts()

	Net.fireAll("RoundStatus", {
		Phase = PHASE.Starting,
		EndsAt = Net.getStateValue(StateKeys.Game.PhaseEndsAt, 0),
		MapId = mapId,
		MapName = info and info.Name or mapId,
		Killers = KillerService.getActiveNames(),
		Objective = ObjectiveService.describe(),
		Objectives = ObjectiveService.getSnapshot(),
	})

	task.wait(Config.Round.StartupSeconds)
	return true
end

local function runActive()
	setPhase(PHASE.Active, Config.Round.RoundSeconds)

	Net.fireAll("RoundStatus", {
		Phase = PHASE.Active,
		EndsAt = Net.getStateValue(StateKeys.Game.PhaseEndsAt, 0),
		MapName = Net.getStateValue(StateKeys.Game.MapName, ""),
		Killers = KillerService.getActiveNames(),
		Objective = ObjectiveService.describe(),
		Objectives = ObjectiveService.getSnapshot(),
	})

	HelperService.beginRound()

	local deadline = Net.getStateValue(StateKeys.Game.PhaseEndsAt, Util.now())
	while Util.now() < deadline and not roundDecided do
		evaluateRound()
		task.wait(0.5)
	end

	if not roundDecided then
		-- The clock ran out.
		roundDecided = true
		GameStateManager.finishRound(false)
	end
end

--==========================================================================
-- Round end
--==========================================================================

function GameStateManager.finishRound(victory: boolean)
	if Net.getStateValue(StateKeys.Game.Phase, "") == PHASE.Results then
		return
	end

	setPhase(PHASE.Results, Config.Round.ResultsSeconds)
	Net.setStateValue(StateKeys.Game.Result, victory and "Victory" or "Defeat")

	KillerService.freezeAll()
	HelperService.endRound()
	HidingService.releaseAll()
	RevivalService.clearAll()

	local results = StatsService.endRound(victory)

	Net.fireAll("RoundResults", {
		Victory = victory,
		MapName = Net.getStateValue(StateKeys.Game.MapName, ""),
		Killers = KillerService.getActiveNames(),
		Objectives = ObjectiveService.getSnapshot(),
		Results = results,
		EndsAt = Net.getStateValue(StateKeys.Game.PhaseEndsAt, 0),
	})

	Util.log("GameState", "round %d ended: %s", roundNumber, victory and "VICTORY" or "DEFEAT")
end

local function runResults()
	-- The results screen shows over the frozen map for a beat before everyone
	-- is pulled back to the lobby, so players can see where it went wrong.
	task.wait(Config.Round.ResultsSeconds)

	KillerService.despawnAll()
	ObjectiveService.endRound()
	SafeZoneService.clearTemporary()
	AvaService.despawn()
	TeamService.resetAll()

	teleportAllToLobby()
	MapService.unload()

	task.wait(Config.Round.PostResultsSeconds)
end

--==========================================================================
-- Main loop
--==========================================================================

local function waitForPlayers()
	while not hasEnoughPlayers() do
		Net.setStateValue(StateKeys.Game.Phase, PHASE.Intermission)
		Net.setStateValue(StateKeys.Game.PhaseEndsAt, Util.now() + 5)
		Net.fireAll("Announce", {
			Kind = "Waiting",
			Text = `Waiting for players ({#Players:GetPlayers()}/{Config.Round.MinPlayersToStart})`,
		})
		task.wait(3)
	end
end

function GameStateManager.start()
	Net.setStateValue(StateKeys.Game.Phase, PHASE.Booting)
	Net.setStateValue(StateKeys.Game.Result, "")
	Net.setStateValue(StateKeys.Game.RoundNumber, 0)

	-- Objective completion and roster changes both feed the same evaluation.
	ObjectiveService.setCompletionCallback(function()
		objectivesComplete = true
		evaluateRound()
	end)
	RevivalService.setRosterChangedCallback(function()
		evaluateRound()
	end)

	-- A player joining mid-round watches from the lobby; one leaving might have
	-- been the last one standing.
	Players.PlayerAdded:Connect(function(player)
		task.wait(1)
		if Net.getStateValue(StateKeys.Game.Phase, "") == PHASE.Active then
			TeamService.exitRound(player, false)
			player:SetAttribute(StateKeys.Player.Spectating, true)
			teleportToLobby(player)
			Net.fire(player, "Announce", {
				Kind = "Spectating",
				Text = "A round is already under way. You'll join the next one.",
			})
		end
		refreshCounts()
	end)

	Players.PlayerRemoving:Connect(function()
		task.defer(evaluateRound)
	end)

	-- Answering the RemoteFunction lets a client that joined late rebuild its
	-- HUD without waiting for the next phase change.
	Net.Functions.GetRoundSnapshot.OnServerInvoke = function()
		return {
			Phase = Net.getStateValue(StateKeys.Game.Phase, PHASE.Booting),
			EndsAt = Net.getStateValue(StateKeys.Game.PhaseEndsAt, 0),
			MapId = Net.getStateValue(StateKeys.Game.MapId, ""),
			MapName = Net.getStateValue(StateKeys.Game.MapName, ""),
			Killers = KillerService.getActiveNames(),
			Objective = ObjectiveService.describe(),
			Objectives = ObjectiveService.getSnapshot(),
			RoundNumber = roundNumber,
		}
	end

	task.spawn(function()
		while true do
			local ok, err = pcall(function()
				waitForPlayers()

				local mapId = runIntermission()

				if not hasEnoughPlayers() then
					return
				end

				if runStarting(mapId) then
					runActive()
					runResults()
				end
			end)

			if not ok then
				Util.warn("GameState", "round loop error: %s", tostring(err))
				-- Reset to something sane rather than wedging the server.
				pcall(function()
					KillerService.despawnAll()
					ObjectiveService.endRound()
					HelperService.endRound()
					RevivalService.clearAll()
					HidingService.releaseAll()
					TeamService.resetAll()
					MapService.unload()
					teleportAllToLobby()
				end)
				task.wait(5)
			end

			task.wait(0.5)
		end
	end)
end

return GameStateManager
