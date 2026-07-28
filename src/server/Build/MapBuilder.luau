--!nonstrict
--[[
	MapBuilder.luau
	--------------------------------------------------------------------------
	Builds The House from HouseData and tags everything the gameplay code needs.

	This is no longer a placeholder greybox -- it is the mockup's actual level
	design: four floors, the real room bounds, the fifteen hiding spots where
	they were placed, the designed patrol routes, and the exact 5 mirrors /
	14 crosses / 15 bottles the objectives ask for.

	What is still approximate is the DRESSING -- furniture is boxes at the right
	size rather than modelled sofas and bookshelves. The mockups are still being
	tweaked, so this stays cheap to change. When you want the real furniture,
	the props.js builders port into Primitives the same way the walls did.

	If a Model exists at ServerStorage/Maps/TheHouse, MapService loads that
	instead and none of this runs.
	--------------------------------------------------------------------------
]]

local CollectionService = game:GetService("CollectionService")

local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
local Config = require(Shared.Config)
local Palette = require(Shared.Palette)
local Tags = require(Shared.Tags)
local Util = require(Shared.Util)

local HouseData = require(script.Parent.HouseData)
local Primitives = require(script.Parent.Primitives)

local MapBuilder = {}

local SLAB_THICKNESS = 1

--==========================================================================
-- Helpers
--==========================================================================

local function folder(name: string, parent: Instance): Folder
	local f = Instance.new("Folder")
	f.Name = name
	f.Parent = parent
	return f
end

local function marker(name: string, position: Vector3, parent: Instance, style: string?): BasePart
	local part = Primitives.part(name, style, position, Vector3.new(2, 1, 2), 0, parent)
	part.Transparency = style and part.Transparency or 1
	part.CanCollide = false
	part.CanQuery = false
	return part
end

--==========================================================================
-- Shell
--==========================================================================

--[[
	Subtracts a rectangular hole from a rectangle, returning the pieces left
	over -- up to four, cut left / right / near / far around the hole.

	This is what turns a solid floor slab into one with a stairwell in it.
	Rectangles are {x0, x1, z0, z1}.
]]
local function subtractHole(rect, hole)
	-- No overlap: the rectangle survives whole.
	if hole.x1 <= rect.x0 or hole.x0 >= rect.x1 or hole.z1 <= rect.z0 or hole.z0 >= rect.z1 then
		return { rect }
	end

	local cutX0 = math.max(rect.x0, hole.x0)
	local cutX1 = math.min(rect.x1, hole.x1)
	local cutZ0 = math.max(rect.z0, hole.z0)
	local cutZ1 = math.min(rect.z1, hole.z1)

	local pieces = {}
	local function add(x0, x1, z0, z1)
		if x1 - x0 > 0.05 and z1 - z0 > 0.05 then
			table.insert(pieces, { x0 = x0, x1 = x1, z0 = z0, z1 = z1 })
		end
	end

	add(rect.x0, cutX0, rect.z0, rect.z1) -- left of the hole
	add(cutX1, rect.x1, rect.z0, rect.z1) -- right of the hole
	add(cutX0, cutX1, rect.z0, cutZ0) -- near side
	add(cutX0, cutX1, cutZ1, rect.z1) -- far side
	return pieces
end

local function slabPieces(room, floorName: string)
	local pieces = { { x0 = room.x0, x1 = room.x1, z0 = room.z0, z1 = room.z1 } }

	for _, hole in HouseData.FloorHoles do
		if hole.f ~= floorName then
			continue
		end
		local next_ = {}
		for _, piece in pieces do
			for _, remainder in subtractHole(piece, hole) do
				table.insert(next_, remainder)
			end
		end
		pieces = next_
	end

	return pieces
end

local function buildFloorShell(floorName: string, parent: Instance)
	local y = HouseData.FloorY[floorName]
	local height = HouseData.WallHeight[floorName]

	local structure = folder(`Structure_{floorName}`, parent)

	-- One slab per room, so the floor finish reads per space -- minus any
	-- stairwell openings cut through it.
	for _, room in HouseData.roomsOn(floorName) do
		for index, piece in slabPieces(room, floorName) do
			Primitives.box(
				`slab_{room.id}_{index}`,
				room.mat,
				piece.x0,
				piece.x1,
				y - SLAB_THICKNESS,
				y,
				piece.z0,
				piece.z1,
				structure
			)
		end
	end

	-- Walls.
	for index, wall in HouseData.Walls[floorName] or {} do
		local style = wall.ext and "plaster" or (floorName == "basement" and "stone" or "paperGrn")
		Primitives.wall(
			structure,
			`{wall.ext and "ext_wall" or "wall"}_{floorName}_{index}`,
			style,
			wall.a,
			wall.b,
			y,
			height,
			wall.t,
			wall.doors
		)
	end

	-- Ceiling over the top storey only; the floors below get one from the slab
	-- of the storey above them.
	if floorName == "attic" then
		for _, room in HouseData.roomsOn(floorName) do
			Primitives.box(
				`roof_{room.id}`,
				"shingle",
				room.x0,
				room.x1,
				y + height,
				y + height + SLAB_THICKNESS,
				room.z0,
				room.z1,
				structure
			)
		end
	end
end

local function buildVerticalLinks(parent: Instance)
	local structure = folder("VerticalLinks", parent)

	for _, stair in HouseData.Stairs do
		Primitives.stairs(stair.name, stair.mat, stair.from, stair.to, stair.width, structure)
	end

	for _, ladder in HouseData.Ladders do
		Primitives.ladder(ladder.name, ladder.bottom, ladder.height, structure)
	end
end

--==========================================================================
-- Gameplay markers
--==========================================================================

local function buildHides(parent: Instance)
	local hides = folder("HidingSpots", parent)

	for index, hide in HouseData.Hides do
		local shape = HouseData.HideShape[hide.t]
		if not shape then
			Util.warn("MapBuilder", 'unknown hiding spot type "%s"', hide.t)
			continue
		end

		local position = HouseData.toWorld(hide.f, hide.p, shape.size.Y / 2)
		local part = Primitives.part(`Hide_{shape.Kind}_{index}`, shape.mat, position, shape.size, hide.r, hides)

		-- Beds, tables and bathtubs are hidden *under* or *in*, so players have
		-- to be able to walk into them. Lockers and closets are solid.
		part.CanCollide = shape.solid

		part:SetAttribute("Kind", shape.Kind)
		part:SetAttribute("Zone", HouseData.zoneAt(hide.f, hide.p[1], hide.p[2]))
		part:SetAttribute("Label", hide.n)
		CollectionService:AddTag(part, Tags.HidingSpot)
	end
end

local function buildNoisyTiles(parent: Instance)
	local tiles = folder("NoisyTiles", parent)

	for index, noisy in HouseData.Noisy do
		local y = HouseData.FloorY[noisy.f]
		local tile = Primitives.box(
			`NoisyTile_{index}`,
			"noisy",
			noisy.p[1] - noisy.s[1] / 2,
			noisy.p[1] + noisy.s[1] / 2,
			y + 0.05,
			y + 0.3,
			noisy.p[2] - noisy.s[2] / 2,
			noisy.p[2] + noisy.s[2] / 2,
			tiles
		)
		tile.CanCollide = false
		tile:SetAttribute("Noise", Config.Noise.Actions.CreakyFloor)
		tile:SetAttribute("Label", noisy.n)
		CollectionService:AddTag(tile, Tags.NoisyTile)
	end
end

local function buildSafeZones(parent: Instance)
	local zones = folder("SafeZones", parent)

	for index, zone in HouseData.SafeZones do
		local centre = HouseData.toWorld(zone.f, zone.p, 6)

		-- A box volume rather than a disc: SafeZoneService tests points in the
		-- part's own space, so a box gives predictable edges.
		local volume = Primitives.part(
			`SafeZone_{index}`,
			"safe",
			centre,
			Vector3.new(zone.r * 2, 12, zone.r * 2),
			0,
			zones
		)
		volume.CanCollide = false
		volume.CanQuery = false
		volume:SetAttribute("Radius", zone.r)
		volume:SetAttribute("Active", true)
		volume:SetAttribute("Label", zone.n)
		CollectionService:AddTag(volume, Tags.SafeZone)

		-- The three entrances the design document calls for.
		for entranceIndex, entrance in zone.ent do
			local post = Primitives.cyl(
				`SafeZoneEntrance_{index}_{entranceIndex}`,
				"safe",
				HouseData.toWorld(zone.f, entrance, 2),
				1.4,
				4,
				0,
				zones
			)
			post.CanCollide = false
		end
	end
end

--- One tagged spawn point per fixed item position from the mockup.
local function buildTaskSpawns(parent: Instance)
	local spawns = folder("TaskSpawns", parent)

	local function place(list, taskType: string, prefix: string)
		for index, entry in list do
			local point = marker(
				`{prefix}Spawn_{index}`,
				HouseData.toWorld(entry.f, entry.p, 3),
				spawns
			)
			point:SetAttribute("TaskType", taskType)
			point:SetAttribute("Zone", HouseData.zoneAt(entry.f, entry.p[1], entry.p[2]))
			CollectionService:AddTag(point, Tags.TaskSpawn)
		end
	end

	-- Counts here are exactly the objective goals: 15 / 14 / 5.
	place(HouseData.Bottles, "Potion", "Bottle")
	place(HouseData.Crosses, "Cross", "Cross")
	place(HouseData.Mirrors, "Mirror", "Mirror")
end

local function buildObjectiveProps(parent: Instance)
	local props = folder("Objectives", parent)

	for _, pin in HouseData.TaskPins do
		local position = HouseData.toWorld(pin.f, pin.p, 2)

		if pin.k == "clock" then
			local clock = Primitives.part(
				"GrandfatherClock",
				"woodDark",
				position + Vector3.new(0, 5, 0),
				Vector3.new(4, 14, 3),
				0,
				props
			)
			clock:SetAttribute("Zone", HouseData.zoneAt(pin.f, pin.p[1], pin.p[2]))
			CollectionService:AddTag(clock, Tags.Clock)
		else
			local ingredientId = Palette.IngredientId[pin.k]
			local pedestal = Primitives.part(
				`Ingredient_{ingredientId}`,
				"stone",
				position,
				Vector3.new(3, 4, 3),
				0,
				props
			)
			pedestal:SetAttribute("Ingredient", ingredientId)
			pedestal:SetAttribute("Zone", HouseData.zoneAt(pin.f, pin.p[1], pin.p[2]))
			CollectionService:AddTag(pedestal, Tags.IngredientSpawn)

			-- A glowing sample sitting on it, in the ingredient's own colour.
			local sample = Primitives.sph(
				`IngredientGlow_{ingredientId}`,
				Palette.Ingredient[pin.k],
				position + Vector3.new(0, 3, 0),
				1.1,
				nil,
				props
			)
			sample.CanCollide = false
		end
	end

	-- Ritual table.
	local ritual = Primitives.part(
		"RitualTable",
		"blood",
		HouseData.toWorld(HouseData.RitualTable.f, HouseData.RitualTable.p, 2),
		Vector3.new(10, 4, 6),
		0,
		props
	)
	ritual:SetAttribute("Zone", "RitualRoom")
	CollectionService:AddTag(ritual, Tags.RitualTable)

	-- Fuse boxes.
	for index, fuse in HouseData.FuseBoxes do
		local box = Primitives.part(
			`FuseBox_{index}`,
			"metal",
			HouseData.toWorld(fuse.f, fuse.p, 6),
			Vector3.new(3, 4, 1.5),
			0,
			props
		)
		box:SetAttribute("Zone", HouseData.zoneAt(fuse.f, fuse.p[1], fuse.p[2]))
		CollectionService:AddTag(box, Tags.FuseBox)
	end
end

local function buildSpawns(parent: Instance)
	local spawns = folder("Spawns", parent)

	for index, point in HouseData.PlayerSpawns.pts do
		local part = marker(
			`PlayerSpawn_{index}`,
			HouseData.toWorld(HouseData.PlayerSpawns.f, point, 3),
			spawns,
			"spawnP"
		)
		part.Transparency = 0.7
		CollectionService:AddTag(part, Tags.PlayerSpawn)
	end

	for index, spawn in HouseData.KillerSpawns do
		local part = marker(`KillerSpawn_{index}`, HouseData.toWorld(spawn.f, spawn.p, 4), spawns)
		part:SetAttribute("Who", spawn.who)
		part:SetAttribute("Zone", HouseData.zoneAt(spawn.f, spawn.p[1], spawn.p[2]))
		CollectionService:AddTag(part, Tags.KillerSpawn)
	end

	for index, spawn in HouseData.HelperSpawns do
		local part = marker(`HelperSpawn_{index}`, HouseData.toWorld(spawn.f, spawn.p, 3), spawns)
		part:SetAttribute("Zone", HouseData.zoneAt(spawn.f, spawn.p[1], spawn.p[2]))
		CollectionService:AddTag(part, Tags.HelperSpawn)
	end
end

--[[
	Patrol routes.

	Each waypoint carries the killer it belongs to and its position in the loop,
	so MapService can hand a killer its own designed route in order instead of
	guessing from room names.
]]
local function buildPatrolRoutes(parent: Instance)
	local routes = folder("PatrolRoutes", parent)

	for _, route in HouseData.Routes do
		local routeFolder = folder(route.killer, routes)

		for order, point in route.pts do
			local node = marker(`{route.killer}_{order}`, HouseData.toWorld(route.f, point, 2), routeFolder)
			node:SetAttribute("Killer", route.killer)
			node:SetAttribute("Order", order)
			node:SetAttribute("Zone", HouseData.zoneAt(route.f, point[1], point[2]))
			CollectionService:AddTag(node, Tags.PatrolNode)
		end
	end

	-- Baby can also use the ducts nobody else fits through.
	for _, hide in HouseData.Hides do
		if hide.t == "duct" then
			local node = marker(
				"Crawlspace",
				HouseData.toWorld(hide.f, hide.p, 2),
				routes
			)
			node:SetAttribute("Killer", "Baby")
			node:SetAttribute("Zone", "Crawlspace")
			CollectionService:AddTag(node, Tags.PatrolNode)
			CollectionService:AddTag(node, Tags.Crawlspace)
		end
	end
end

local function buildLoreNotes(parent: Instance)
	local notes = folder("LoreNotes", parent)

	-- One note per room that the design document gives a document to.
	local placements = {
		{ f = "ground", p = { 40, 24 }, id = "BobLedger" },
		{ f = "ground", p = { 44, 4 }, id = "BarbaraBills" },
		{ f = "second", p = { -46, 24 }, id = "BillyLetter" },
		{ f = "second", p = { 40, -36 }, id = "RobertJournal" },
		{ f = "second", p = { -46, -32 }, id = "AvaDiary1" },
		{ f = "attic", p = { -18, -14 }, id = "AvaDiary2" },
		{ f = "basement", p = { 20, -30 }, id = "PreviousVictim" },
	}

	for _, placement in placements do
		local note = Primitives.part(
			"LoreNote",
			"cloth",
			HouseData.toWorld(placement.f, placement.p, 0.3),
			Vector3.new(2, 0.2, 2.6),
			math.random() * math.pi,
			notes
		)
		note.CanCollide = false
		note:SetAttribute("NoteId", placement.id)
		CollectionService:AddTag(note, Tags.LoreNote)
	end
end

--==========================================================================
-- Dressing and atmosphere
--==========================================================================

--- Simple furniture blocks at the right size and colour. Deliberately cheap --
--- swap these for the props.js builders when the designs settle.
local function buildDressing(parent: Instance)
	local dressing = folder("Dressing", parent)

	local FURNITURE = {
		{ f = "ground", id = "living", items = { { "sofa", "clothRed", Vector3.new(12, 4, 5), { -40, 38 } }, { "rug", "carpet", Vector3.new(20, 0.2, 14), { -38, 28 } } } },
		{ f = "ground", id = "library", items = { { "bookshelf", "woodDark", Vector3.new(3, 12, 16), { -56, -10 } }, { "bookshelf", "woodDark", Vector3.new(3, 12, 16), { -20, -26 } } } },
		{ f = "ground", id = "dining", items = { { "longtable", "woodDark", Vector3.new(8, 4, 20), { 38, 30 } } } },
		{ f = "ground", id = "kitchen", items = { { "counter", "tile", Vector3.new(20, 5, 4), { 38, 10 } }, { "stove", "metal", Vector3.new(6, 6, 5), { 54, 8 } } } },
		{ f = "ground", id = "ritual", items = { { "altarstep", "stone", Vector3.new(14, 1, 10), { 0, -30 } } } },
		{ f = "second", id = "study", items = { { "desk", "woodDark", Vector3.new(10, 4, 5), { 44, -30 } } } },
		{ f = "basement", id = "cellar", items = { { "barrelstack", "woodDark", Vector3.new(10, 8, 6), { -34, -8 } } } },
		{ f = "basement", id = "boilerR", items = { { "boiler", "metal", Vector3.new(8, 10, 8), { 40, -30 } } } },
		{ f = "basement", id = "storage", items = { { "shelfrack", "metal", Vector3.new(4, 10, 16), { 8, 16 } } } },
	}

	for _, group in FURNITURE do
		for _, item in group.items do
			local name, style, size, position = item[1], item[2], item[3], item[4]
			Primitives.part(
				name,
				style,
				HouseData.toWorld(group.f, position, size.Y / 2),
				size,
				0,
				dressing
			)
		end
	end
end

local function buildAtmosphere(parent: Instance)
	local lights = folder("Lighting", parent)
	local rng = Random.new(20250728)

	for _, room in HouseData.Rooms do
		local centre = Vector3.new(
			(room.x0 + room.x1) / 2,
			HouseData.FloorY[room.f] + HouseData.WallHeight[room.f] - 2.5,
			(room.z0 + room.z1) / 2
		)

		local candle = Primitives.sph(`Candle_{room.id}`, "flame", centre, 0.5, nil, lights)
		candle.CanCollide = false

		local light = candle:FindFirstChildOfClass("PointLight")
		if light then
			light.Range = math.max(room.x1 - room.x0, room.z1 - room.z0) * 0.75
			light.Shadows = true

			-- Flicker. Cheap, and it sells the whole thing.
			task.spawn(function()
				while candle.Parent do
					light.Brightness = rng:NextNumber(1.4, 2.6)
					task.wait(rng:NextNumber(0.08, 0.4))
				end
			end)
		end
	end
end

--==========================================================================
-- The House
--==========================================================================

function MapBuilder.buildHouse(): Model
	local model = Instance.new("Model")
	model.Name = "TheHouse"

	for _, floorName in HouseData.FloorOrder do
		buildFloorShell(floorName, model)
	end
	buildVerticalLinks(model)

	buildHides(model)
	buildNoisyTiles(model)
	buildSafeZones(model)
	buildTaskSpawns(model)
	buildObjectiveProps(model)
	buildSpawns(model)
	buildPatrolRoutes(model)
	buildLoreNotes(model)
	buildDressing(model)
	buildAtmosphere(model)

	-- Ground beneath the basement, so falling out of the map isn't fatal and
	-- pathfinding always has something to project onto.
	local ground = Primitives.box(
		"Ground",
		"moss",
		-130,
		130,
		HouseData.FloorY.basement - SLAB_THICKNESS - 4,
		HouseData.FloorY.basement - SLAB_THICKNESS,
		-110,
		110,
		model
	)
	model.PrimaryPart = ground

	return model
end

--==========================================================================
-- The lobby
--==========================================================================

--- Lives well above the maps so nothing can ever overlap it.
function MapBuilder.buildLobby(): Model
	local ORIGIN = Vector3.new(0, 500, 0)
	local SIZE = 120

	local model = Instance.new("Model")
	model.Name = "Lobby"

	local floor = Primitives.part("LobbyFloor", "stone", ORIGIN, Vector3.new(SIZE, 4, SIZE), 0, model)

	for _, spec in
		{
			{ Vector3.new(SIZE, 24, 2), Vector3.new(0, 14, -SIZE / 2) },
			{ Vector3.new(SIZE, 24, 2), Vector3.new(0, 14, SIZE / 2) },
			{ Vector3.new(2, 24, SIZE), Vector3.new(-SIZE / 2, 14, 0) },
			{ Vector3.new(2, 24, SIZE), Vector3.new(SIZE / 2, 14, 0) },
		}
	do
		local wall = Primitives.part("LobbyWall", "plaster", ORIGIN + spec[2], spec[1], 0, model)
		wall.Transparency = 0.25
	end

	--[[
		Roblox's own respawn point, and the default for everyone.

		Deliberately Neutral rather than team-locked: if it were locked to the
		Lost team and a mid-round player somehow respawned while still on
		Survivors, Roblox would find no matching spawn and drop them at the
		world origin. GameStateManager teleports players onto the map explicitly
		at round start, so "everyone respawns in the lobby" is exactly what we
		want from the engine.
	]]
	local spawn = Instance.new("SpawnLocation")
	spawn.Name = "LobbySpawn"
	spawn.Size = Vector3.new(20, 1, 20)
	spawn.CFrame = CFrame.new(ORIGIN + Vector3.new(0, 2.5, 0))
	spawn.Anchored = true
	spawn.Color = Color3.fromRGB(181, 154, 88)
	spawn.Material = Enum.Material.Marble
	spawn.Neutral = true
	spawn.Duration = 0 -- no forcefield; it would look wrong on a horror map
	spawn.Parent = model
	CollectionService:AddTag(spawn, Tags.LobbySpawn)

	for index = 1, 12 do
		local angle = (index / 12) * math.pi * 2
		local point = marker(
			`LobbySpawnPoint_{index}`,
			ORIGIN + Vector3.new(math.cos(angle) * 22, 4, math.sin(angle) * 22),
			model
		)
		CollectionService:AddTag(point, Tags.LobbySpawn)
	end

	-- Shop plinth. ShopService attaches the ProximityPrompt.
	local shop = Primitives.part("ShopStand", "woodDark", ORIGIN + Vector3.new(-34, 5, 0), Vector3.new(8, 6, 4), 0, model)
	shop:SetAttribute("DollysHomeShop", true)

	local sign = Instance.new("BillboardGui")
	sign.Name = "Sign"
	sign.Size = UDim2.fromScale(8, 2)
	sign.StudsOffsetWorldSpace = Vector3.new(0, 5, 0)
	sign.MaxDistance = 90
	sign.Parent = shop

	local label = Instance.new("TextLabel")
	label.Size = UDim2.fromScale(1, 1)
	label.BackgroundTransparency = 1
	label.Font = Enum.Font.GothamBold
	label.Text = "PEDDLER'S CART"
	label.TextColor3 = Color3.fromRGB(240, 220, 180)
	label.TextScaled = true
	label.Parent = sign

	-- Ambient light, so the lobby isn't pitch black under the horror lighting.
	local lamp = Primitives.sph("LobbyLamp", "flame", ORIGIN + Vector3.new(0, 22, 0), 1, nil, model)
	lamp.CanCollide = false
	local lampLight = lamp:FindFirstChildOfClass("PointLight")
	if lampLight then
		lampLight.Brightness = 3
		lampLight.Range = 100
	end

	model.PrimaryPart = floor
	return model
end

--==========================================================================
-- Dispatch
--==========================================================================

function MapBuilder.build(mapId: string): Model?
	if mapId == "TheHouse" then
		return MapBuilder.buildHouse()
	end
	Util.warn(
		"MapBuilder",
		'no generator for map "%s" -- build it in Studio and save it to ServerStorage/Maps/%s',
		mapId,
		mapId
	)
	return nil
end

return MapBuilder
