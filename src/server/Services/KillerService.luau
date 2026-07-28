--!strict
--[[
	KillerService.luau
	--------------------------------------------------------------------------
	Chooses which family members hunt this round, spawns them, and owns their
	agents for the round's lifetime.

	Rig source, same pattern as maps:
	  1. ServerStorage/Killers/<Name>  -- your real rig
	  2. RigBuilder placeholder
	--------------------------------------------------------------------------
]]

local ServerStorage = game:GetService("ServerStorage")
local Workspace = game:GetService("Workspace")

local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
local Config = require(Shared.Config)
local KillerData = require(Shared.KillerData)
local StateKeys = require(Shared.StateKeys)
local Util = require(Shared.Util)

local KillerAgent = require(script.Parent.Parent.AI.KillerAgent)
local MapService = require(script.Parent.MapService)
local RigBuilder = require(script.Parent.Parent.Build.RigBuilder)

local KillerService = {}

local KILLERS_FOLDER_NAME = "ActiveKillers"

local agents: { [string]: KillerAgent.Agent } = {}
local rng = Random.new()

--==========================================================================
-- Internal
--==========================================================================

local function killersFolder(): Folder
	local folder = Workspace:FindFirstChild(KILLERS_FOLDER_NAME) :: Folder?
	if not folder then
		folder = Instance.new("Folder")
		folder.Name = KILLERS_FOLDER_NAME
		folder.Parent = Workspace
	end
	return folder
end

local function buildRig(killerId: string): Model?
	local stored = ServerStorage:FindFirstChild("Killers")
	if stored then
		local template = stored:FindFirstChild(killerId)
		if template and template:IsA("Model") then
			Util.log("KillerService", "using hand-built rig for %s", killerId)
			return template:Clone()
		end
	end
	return RigBuilder.build(killerId, false)
end

--==========================================================================
-- Selection
--==========================================================================

--[[
	Picks this round's hunters.

	  70%  one killer
	  30%  two killers

	When two are drawn there's a chance the pair is one of the lore pairings
	(Bob and Barbara), because two people who tore each other apart hunting the
	same house together is more interesting than two names out of a hat.
]]
function KillerService.selectKillers(): { string }
	local roster = KillerData.getKillerRoster()
	if #roster == 0 then
		return {}
	end

	local count = rng:NextNumber() < Config.Killer.SpawnChanceTwo and 2 or 1
	count = math.min(count, Config.Killer.MaxActive, #roster)

	if count >= 2 and rng:NextNumber() < Config.Killer.LorePairChance then
		local pair = Util.pick(Config.Killer.LorePairs, rng)
		if pair then
			local valid = true
			for _, id in pair do
				if not KillerData.get(id) then
					valid = false
				end
			end
			if valid then
				return table.clone(pair)
			end
		end
	end

	return Util.pickMany(roster, count, rng)
end

--==========================================================================
-- Spawning
--==========================================================================

function KillerService.spawnKillers(killerIds: { string }): { string }
	KillerService.despawnAll()

	local spawns = MapService.getKillerSpawns()
	if #spawns == 0 then
		Util.warn("KillerService", "map has no killer spawns; falling back to player spawns")
		spawns = MapService.getPlayerSpawns()
	end
	if #spawns == 0 then
		Util.warn("KillerService", "no spawn points at all -- killers cannot be placed")
		return {}
	end

	local placements = MapService.allocateSpawns(spawns, #killerIds, rng)
	local spawned = {}

	for index, killerId in killerIds do
		local model = buildRig(killerId)
		if not model then
			Util.warn("KillerService", 'could not build a rig for "%s"', killerId)
			continue
		end

		model.Name = killerId
		model.Parent = killersFolder()

		local placement = placements[index] or placements[1]
		if placement then
			model:PivotTo(placement)
		end

		local agent = KillerAgent.new(killerId, model)
		if not agent then
			model:Destroy()
			continue
		end

		agents[killerId] = agent
		agent:start()
		table.insert(spawned, killerId)

		Util.log("KillerService", "spawned %s", killerId)
	end

	return spawned
end

function KillerService.despawnAll()
	for id, agent in agents do
		agent:stop()
		agents[id] = nil
	end
	local folder = Workspace:FindFirstChild(KILLERS_FOLDER_NAME)
	if folder then
		folder:Destroy()
	end
end

--==========================================================================
-- Queries
--==========================================================================

function KillerService.getAgents(): { [string]: KillerAgent.Agent }
	return agents
end

function KillerService.getAgentForModel(model: Instance): KillerAgent.Agent?
	for _, agent in agents do
		if agent.model == model then
			return agent
		end
	end
	return nil
end

--- The nearest killer to a position, with the distance. Used by the client
--- heartbeat and by Benny's warnings.
function KillerService.getNearest(position: Vector3): (KillerAgent.Agent?, number)
	local best: KillerAgent.Agent? = nil
	local bestDistance = math.huge
	for _, agent in agents do
		local distance = (agent:getPosition() - position).Magnitude
		if distance < bestDistance then
			best = agent
			bestDistance = distance
		end
	end
	return best, bestDistance
end

--- Display names of the active killers, for the round banner.
function KillerService.getActiveNames(): { string }
	local names = {}
	for id in agents do
		local profile = KillerData.get(id)
		table.insert(names, profile and profile.Name or id)
	end
	table.sort(names)
	return names
end

--- Freezes every killer (used the moment a round is decided, so nobody gets
--- downed during the results screen).
function KillerService.freezeAll()
	for _, agent in agents do
		agent.active = false
		agent.humanoid.WalkSpeed = 0
		agent.model:SetAttribute(StateKeys.Killer.AIState, "Idle")
	end
end

return KillerService
