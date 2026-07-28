--!strict
--[[
	Net.luau
	--------------------------------------------------------------------------
	Remote plumbing and the replicated game state container.

	Two ways state reaches the client:

	1. ATTRIBUTES on ReplicatedStorage/DollysHome/State. Roblox replicates
	   attribute changes automatically, so the round phase, map, objective
	   progress and so on cost us no RemoteEvent traffic at all. The client
	   reads them with GetAttribute and listens with GetAttributeChangedSignal.

	2. REMOTES, below, for one-off messages that aren't state -- "a task was
	   just completed", "here are the round results", "I want to vote".

	The server builds the folder; the client waits for it.
	--------------------------------------------------------------------------
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local IS_SERVER = RunService:IsServer()
local ROOT_NAME = "DollysHome"

-- Server -> Client, or Client -> Server, fire-and-forget.
local REMOTE_EVENTS = {
	-- Server -> all clients
	"RoundStatus", -- phase changes with a payload (map, killers, objective blurb)
	"TaskCompleted", -- an objective finished; drives the toast + sound
	"TaskProgress", -- incremental progress on an objective
	"InjuredAlert", -- a player went down / was revived / bled out
	"RoundResults", -- the end-of-round scoreboard payload
	"Announce", -- generic system message toast
	"KillerProximity", -- heartbeat intensity + which killer is near
	"HelperMessage", -- Robby/Benny dialogue
	"AvaDialogue", -- graveyard NPC dialogue
	"LoreNoteRead", -- a lore note was picked up

	-- Client -> Server
	"CastVote", -- map vote
	"SetSprinting", -- sprint key held/released
	"SetCrouching", -- crouch key held/released
	"RequestHide", -- enter/exit a hiding spot
	"Attack", -- swing the equipped stake
	"EquipStake", -- change equipped stake
	"SubmitClock", -- grandfather clock minigame answer
	"Purchase", -- buy from the shop
	"UseConsumable", -- drink a potion
	"SpectateTarget", -- cycle spectate camera
	"AvaRespond", -- answer Ava's question
}

-- Request/response. Used sparingly -- they block the caller.
local REMOTE_FUNCTIONS = {
	"GetProfile", -- coins, wins, owned stakes, inventory
	"GetRoundSnapshot", -- full state for a client that joined mid-round
}

local Net = {}

Net.Events = {} :: { [string]: RemoteEvent }
Net.Functions = {} :: { [string]: RemoteFunction }

local root: Instance
local eventsFolder: Instance
local functionsFolder: Instance

--==========================================================================
-- Bootstrap
--==========================================================================

local function buildServer()
	root = ReplicatedStorage:FindFirstChild(ROOT_NAME) or Instance.new("Folder")
	root.Name = ROOT_NAME
	root.Parent = ReplicatedStorage

	eventsFolder = root:FindFirstChild("Events") or Instance.new("Folder")
	eventsFolder.Name = "Events"
	eventsFolder.Parent = root

	functionsFolder = root:FindFirstChild("Functions") or Instance.new("Folder")
	functionsFolder.Name = "Functions"
	functionsFolder.Parent = root

	for _, name in REMOTE_EVENTS do
		local remote = eventsFolder:FindFirstChild(name)
		if not remote then
			remote = Instance.new("RemoteEvent")
			remote.Name = name
			remote.Parent = eventsFolder
		end
		Net.Events[name] = remote :: RemoteEvent
	end

	for _, name in REMOTE_FUNCTIONS do
		local remote = functionsFolder:FindFirstChild(name)
		if not remote then
			remote = Instance.new("RemoteFunction")
			remote.Name = name
			remote.Parent = functionsFolder
		end
		Net.Functions[name] = remote :: RemoteFunction
	end

	-- Replicated state container.
	local state = root:FindFirstChild("State")
	if not state then
		state = Instance.new("Configuration")
		state.Name = "State"
		state.Parent = root
	end

	local objectives = state:FindFirstChild("Objectives")
	if not objectives then
		objectives = Instance.new("Folder")
		objectives.Name = "Objectives"
		objectives.Parent = state
	end

	local votes = state:FindFirstChild("Votes")
	if not votes then
		votes = Instance.new("Configuration")
		votes.Name = "Votes"
		votes.Parent = state
	end
end

local function buildClient()
	root = ReplicatedStorage:WaitForChild(ROOT_NAME, 30)
	assert(root, "[Net] DollysHome folder never replicated -- is the server bootstrap running?")

	eventsFolder = root:WaitForChild("Events")
	functionsFolder = root:WaitForChild("Functions")

	for _, name in REMOTE_EVENTS do
		Net.Events[name] = eventsFolder:WaitForChild(name) :: RemoteEvent
	end
	for _, name in REMOTE_FUNCTIONS do
		Net.Functions[name] = functionsFolder:WaitForChild(name) :: RemoteFunction
	end
end

if IS_SERVER then
	buildServer()
else
	buildClient()
end

--==========================================================================
-- Public helpers
--==========================================================================

function Net.getRoot(): Instance
	return root
end

--- The Configuration instance carrying the replicated round state.
function Net.getState(): Configuration
	return (root:FindFirstChild("State") or root:WaitForChild("State")) :: Configuration
end

--- Folder holding one Configuration per active objective.
function Net.getObjectivesFolder(): Folder
	local state = Net.getState()
	return (state:FindFirstChild("Objectives") or state:WaitForChild("Objectives")) :: Folder
end

--- Configuration whose attributes are `mapId -> voteCount`.
function Net.getVotesFolder(): Configuration
	local state = Net.getState()
	return (state:FindFirstChild("Votes") or state:WaitForChild("Votes")) :: Configuration
end

--- Convenience: read a state attribute with a fallback.
function Net.getStateValue(key: string, default: any): any
	local value = Net.getState():GetAttribute(key)
	if value == nil then
		return default
	end
	return value
end

--- Server only. Sets a state attribute (skipping redundant writes).
function Net.setStateValue(key: string, value: any)
	assert(IS_SERVER, "[Net] setStateValue is server-only")
	local state = Net.getState()
	if state:GetAttribute(key) ~= value then
		state:SetAttribute(key, value)
	end
end

--- Server only. Fires a RemoteEvent at every player.
function Net.fireAll(eventName: string, ...: any)
	assert(IS_SERVER, "[Net] fireAll is server-only")
	local remote = Net.Events[eventName]
	assert(remote, `[Net] unknown remote event "{eventName}"`)
	remote:FireAllClients(...)
end

--- Server only. Fires a RemoteEvent at one player.
function Net.fire(player: Player, eventName: string, ...: any)
	assert(IS_SERVER, "[Net] fire is server-only")
	local remote = Net.Events[eventName]
	assert(remote, `[Net] unknown remote event "{eventName}"`)
	remote:FireClient(player, ...)
end

return Net
