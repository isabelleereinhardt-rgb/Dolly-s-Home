--!strict
--[[
	MapService.luau
	--------------------------------------------------------------------------
	Loads a map for the round and answers "where are the X's on this map?"

	Map source, in priority order:
	  1. ServerStorage/Maps/<MapId>  -- your real, hand-built map
	  2. MapBuilder greybox          -- the generated placeholder

	Every other service asks MapService for tagged instances rather than
	touching Workspace directly, so swapping in a real map changes nothing
	anywhere else.
	--------------------------------------------------------------------------
]]

local CollectionService = game:GetService("CollectionService")
local ServerStorage = game:GetService("ServerStorage")
local Workspace = game:GetService("Workspace")

local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
local Config = require(Shared.Config)
local Tags = require(Shared.Tags)
local Util = require(Shared.Util)

local MapBuilder = require(script.Parent.Parent.Build.MapBuilder)

local MapService = {}

local ACTIVE_FOLDER_NAME = "ActiveMap"
local LOBBY_FOLDER_NAME = "Lobby"

local activeMap: Model? = nil
local activeMapId: string? = nil
local lobby: Model? = nil

-- Tag lookups are cached per load. Rebuilt on every map change.
local cache: { [string]: { Instance } } = {}

--==========================================================================
-- Internal
--==========================================================================

local function activeFolder(): Folder
	local folder = Workspace:FindFirstChild(ACTIVE_FOLDER_NAME) :: Folder?
	if not folder then
		folder = Instance.new("Folder")
		folder.Name = ACTIVE_FOLDER_NAME
		folder.Parent = Workspace
	end
	return folder
end

local function clearCache()
	table.clear(cache)
end

--- All instances with `tag` that are descendants of the active map.
local function collect(tag: string): { Instance }
	if cache[tag] then
		return cache[tag]
	end

	local out = {}
	local map = activeMap
	for _, instance in CollectionService:GetTagged(tag) do
		if map and instance:IsDescendantOf(map) then
			table.insert(out, instance)
		end
	end
	cache[tag] = out
	return out
end

--==========================================================================
-- Lobby
--==========================================================================

function MapService.buildLobby()
	if lobby and lobby.Parent then
		return
	end

	local built: Model
	local existing = ServerStorage:FindFirstChild(LOBBY_FOLDER_NAME)
	if existing and existing:IsA("Model") then
		built = existing:Clone()
		Util.log("MapService", "using hand-built lobby from ServerStorage")
	else
		built = MapBuilder.buildLobby()
		Util.log("MapService", "generated placeholder lobby")
	end

	built.Name = LOBBY_FOLDER_NAME
	built.Parent = Workspace
	lobby = built
end

function MapService.getLobby(): Model?
	return lobby
end

--- Spawn CFrames in the lobby, cycled if there are more players than pads.
function MapService.getLobbySpawns(): { CFrame }
	local out = {}
	local root = lobby
	for _, instance in CollectionService:GetTagged(Tags.LobbySpawn) do
		if root and instance:IsDescendantOf(root) and instance:IsA("BasePart") then
			table.insert(out, instance.CFrame + Vector3.new(0, 4, 0))
		end
	end
	if #out == 0 and lobby and lobby.PrimaryPart then
		table.insert(out, lobby.PrimaryPart.CFrame + Vector3.new(0, 6, 0))
	end
	return out
end

--==========================================================================
-- Map loading
--==========================================================================

function MapService.unload()
	local folder = Workspace:FindFirstChild(ACTIVE_FOLDER_NAME)
	if folder then
		folder:Destroy()
	end
	activeMap = nil
	activeMapId = nil
	clearCache()
end

--- Loads `mapId` into Workspace.ActiveMap. Returns the model, or nil on failure.
function MapService.load(mapId: string): Model?
	MapService.unload()

	local source: Model? = nil
	local mapsFolder = ServerStorage:FindFirstChild("Maps")
	if mapsFolder then
		local stored = mapsFolder:FindFirstChild(mapId)
		if stored and stored:IsA("Model") then
			source = stored:Clone()
			Util.log("MapService", "loaded hand-built map %s", mapId)
		end
	end

	if not source then
		source = MapBuilder.build(mapId)
		if source then
			Util.log("MapService", "generated greybox for %s", mapId)
		end
	end

	if not source then
		Util.warn("MapService", 'could not load map "%s"', mapId)
		return nil
	end

	source.Parent = activeFolder()
	activeMap = source
	activeMapId = mapId
	clearCache()

	MapService.validate()
	return source
end

function MapService.getActiveMap(): Model?
	return activeMap
end

function MapService.getActiveMapId(): string?
	return activeMapId
end

function MapService.getMapInfo(mapId: string)
	for _, map in Config.Maps do
		if map.Id == mapId then
			return map
		end
	end
	return nil
end

--==========================================================================
-- Tagged lookups
--==========================================================================

local function partsOnly(instances: { Instance }): { BasePart }
	local out = {}
	for _, instance in instances do
		if instance:IsA("BasePart") then
			table.insert(out, instance)
		end
	end
	return out
end

function MapService.getTagged(tag: string): { Instance }
	return collect(tag)
end

function MapService.getTaggedParts(tag: string): { BasePart }
	return partsOnly(collect(tag))
end

function MapService.getPlayerSpawns(): { BasePart }
	return MapService.getTaggedParts(Tags.PlayerSpawn)
end

function MapService.getKillerSpawns(): { BasePart }
	return MapService.getTaggedParts(Tags.KillerSpawn)
end

function MapService.getHelperSpawns(): { BasePart }
	return MapService.getTaggedParts(Tags.HelperSpawn)
end

function MapService.getHidingSpots(): { BasePart }
	return MapService.getTaggedParts(Tags.HidingSpot)
end

function MapService.getNoisyTiles(): { BasePart }
	return MapService.getTaggedParts(Tags.NoisyTile)
end

function MapService.getSafeZones(): { BasePart }
	return MapService.getTaggedParts(Tags.SafeZone)
end

--- Task spawn points, optionally filtered to a TaskType. Points marked "Any"
--- always match, so a builder can tag a generic spot and forget about it.
function MapService.getTaskSpawns(taskType: string?): { BasePart }
	local all = MapService.getTaggedParts(Tags.TaskSpawn)
	if not taskType then
		return all
	end
	local out = {}
	for _, spawnPoint in all do
		local declared = spawnPoint:GetAttribute("TaskType")
		if declared == nil or declared == "Any" or declared == taskType then
			table.insert(out, spawnPoint)
		end
	end
	return out
end

function MapService.getIngredientSpawn(ingredient: string): BasePart?
	for _, spawnPoint in MapService.getTaggedParts(Tags.IngredientSpawn) do
		if spawnPoint:GetAttribute("Ingredient") == ingredient then
			return spawnPoint
		end
	end
	return nil
end

function MapService.getFuseBoxes(): { BasePart }
	return MapService.getTaggedParts(Tags.FuseBox)
end

function MapService.getClock(): BasePart?
	return MapService.getTaggedParts(Tags.Clock)[1]
end

function MapService.getRitualTable(): BasePart?
	return MapService.getTaggedParts(Tags.RitualTable)[1]
end

function MapService.getLoreNotes(): { BasePart }
	return MapService.getTaggedParts(Tags.LoreNote)
end

--[[
	Patrol nodes for a killer, in the order they should be walked.

	Three tiers, best first:

	  1. A DESIGNED ROUTE -- nodes carrying `Killer = <id>`, sorted by their
	     `Order` attribute. This is what the House ships with: a hand-authored
	     loop per killer, so Barbara really does prowl the kitchen and Robert
	     really does haunt the study.
	  2. ZONE MATCH -- nodes whose `Zone` is one of the killer's preferred rooms
	     from KillerData. This is the fallback for a hand-built map that tagged
	     zones but not routes.
	  3. EVERYTHING -- so a map with bare untagged nodes still produces patrols
	     rather than killers standing still.

	Crawlspace nodes are filtered out unless the killer can use them.
]]
function MapService.getPatrolNodes(killerId: string?, zones: { string }?, canUseCrawlspaces: boolean?): { BasePart }
	local usable = {}
	for _, node in MapService.getTaggedParts(Tags.PatrolNode) do
		if CollectionService:HasTag(node, Tags.Crawlspace) and not canUseCrawlspaces then
			continue
		end
		table.insert(usable, node)
	end

	-- 1. The killer's own designed route.
	if killerId then
		local route = {}
		for _, node in usable do
			if node:GetAttribute("Killer") == killerId then
				table.insert(route, node)
			end
		end
		if #route >= 3 then
			table.sort(route, function(a, b)
				return ((a:GetAttribute("Order") :: number?) or 0) < ((b:GetAttribute("Order") :: number?) or 0)
			end)
			return route
		end
	end

	-- 2. Rooms this killer favours.
	if zones and #zones > 0 then
		local wanted: { [string]: boolean } = {}
		for _, zone in zones do
			wanted[zone] = true
		end

		local preferred = {}
		for _, node in usable do
			local zone = node:GetAttribute("Zone")
			if type(zone) == "string" and wanted[zone] then
				table.insert(preferred, node)
			end
		end

		-- A killer with two nodes can't meaningfully patrol; widen the net.
		if #preferred >= 3 then
			return preferred
		end
	end

	-- 3. Anything at all.
	return usable
end

--==========================================================================
-- Spawn placement
--==========================================================================

--- `count` spawn CFrames drawn from `spawns`, shuffled, cycling if needed.
function MapService.allocateSpawns(spawns: { BasePart }, count: number, rng: Random?): { CFrame }
	local out = {}
	if #spawns == 0 then
		return out
	end

	local pool = Util.shuffle(table.clone(spawns), rng)
	for index = 1, count do
		local spawnPart = pool[((index - 1) % #pool) + 1]
		-- Nudge repeats sideways so players don't spawn inside each other.
		local ring = math.floor((index - 1) / #pool)
		local offset = Vector3.zero
		if ring > 0 then
			local angle = (index / count) * math.pi * 2
			offset = Vector3.new(math.cos(angle) * 3 * ring, 0, math.sin(angle) * 3 * ring)
		end
		table.insert(out, CFrame.new(spawnPart.Position + offset + Vector3.new(0, 3.5, 0)))
	end
	return out
end

--==========================================================================
-- Validation
--==========================================================================

--[[
	Warns about anything the round needs but the map doesn't have. This is the
	single most useful thing when you swap in a hand-built map and something
	silently doesn't work -- the output window tells you which tag you forgot.
]]
function MapService.validate(): boolean
	local problems = {}

	local function require_(tag: string, minimum: number, what: string)
		local found = #collect(tag)
		if found < minimum then
			table.insert(problems, `{what}: found {found}, need at least {minimum} (tag "{tag}")`)
		end
	end

	require_(Tags.PlayerSpawn, 1, "Player spawns")
	require_(Tags.KillerSpawn, 1, "Killer spawns")
	require_(Tags.PatrolNode, 4, "Patrol nodes")
	require_(Tags.TaskSpawn, Config.Objectives.Potions.ActiveAtOnce, "Task spawn points")
	require_(Tags.HidingSpot, 3, "Hiding spots")

	if #problems > 0 then
		Util.warn("MapService", 'map "%s" is missing things:', activeMapId or "?")
		for _, problem in problems do
			warn(`   - {problem}`)
		end
		warn("   See docs/MAP_BUILDING.md for the tag reference.")
		return false
	end

	return true
end

return MapService
