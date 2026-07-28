--!nonstrict
--[[
	MapBuilder.luau
	--------------------------------------------------------------------------
	Generates a greybox of The House, fully tagged, so the game is playable the
	moment you press Play -- before a single piece of art exists.

	THIS IS SCAFFOLDING, NOT THE FINAL MAP. When you build the real manor in
	Studio, save it into ServerStorage/Maps/TheHouse and MapService will use
	yours instead of this one automatically. Nothing in the gameplay code cares
	which one it got; it only reads CollectionService tags. See
	docs/MAP_BUILDING.md for the tag reference.

	Layout: two floors on a room grid, connected by a ramp through the Foyer.
	Walls are generated along room boundaries with doorways punched into shared
	edges, which produces the confusing, loops-back-on-itself feel the design
	doc asks for without anyone hand-placing a wall.
	--------------------------------------------------------------------------
]]

local CollectionService = game:GetService("CollectionService")

local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
local Config = require(Shared.Config)
local Tags = require(Shared.Tags)
local Util = require(Shared.Util)

local MapBuilder = {}

--==========================================================================
-- Geometry constants (studs)
--==========================================================================
local WALL_HEIGHT = 18
local WALL_THICKNESS = 1.5
local FLOOR_THICKNESS = 2
local FLOOR_HEIGHT = WALL_HEIGHT + FLOOR_THICKNESS -- vertical pitch between storeys
local DOOR_WIDTH = 11
local DOOR_HEIGHT = 13

--==========================================================================
-- Palette
--==========================================================================
local PALETTE = {
	Floor = Color3.fromRGB(64, 52, 42),
	FloorUpper = Color3.fromRGB(72, 58, 46),
	Wall = Color3.fromRGB(88, 84, 72),
	WallAccent = Color3.fromRGB(70, 74, 62),
	Trim = Color3.fromRGB(46, 38, 32),
	Prop = Color3.fromRGB(78, 62, 48),
	Metal = Color3.fromRGB(96, 96, 100),
	Glass = Color3.fromRGB(150, 170, 175),
	Lobby = Color3.fromRGB(44, 46, 58),
	LobbyAccent = Color3.fromRGB(140, 110, 70),
}

--==========================================================================
-- Room definitions
--==========================================================================
-- Rects are half-open [x1, x2) x [z1, z2) in local map space.
-- Zone must match a name used in KillerData.PatrolZones for patrols to favour it.
type RoomDef = {
	Id: string,
	Zone: string,
	Floor: number,
	x1: number,
	z1: number,
	x2: number,
	z2: number,
	NoFloor: boolean?,
	NoCeiling: boolean?,
}

local ROOMS: { RoomDef } = {
	-- GROUND FLOOR ---------------------------------------------------------
	{ Id = "Kitchen", Zone = "Kitchen", Floor = 0, x1 = 0, z1 = 0, x2 = 36, z2 = 36 },
	{ Id = "Pantry", Zone = "Pantry", Floor = 0, x1 = 36, z1 = 0, x2 = 60, z2 = 36 },
	{ Id = "DiningRoom", Zone = "DiningRoom", Floor = 0, x1 = 60, z1 = 0, x2 = 96, z2 = 36 },
	{ Id = "LivingRoom", Zone = "LivingRoom", Floor = 0, x1 = 96, z1 = 0, x2 = 132, z2 = 36 },

	{ Id = "Library", Zone = "Library", Floor = 0, x1 = 0, z1 = 36, x2 = 36, z2 = 72 },
	{ Id = "Hallway", Zone = "Hallway", Floor = 0, x1 = 36, z1 = 36, x2 = 96, z2 = 72 },
	{ Id = "RitualRoom", Zone = "RitualRoom", Floor = 0, x1 = 96, z1 = 36, x2 = 132, z2 = 72 },

	{ Id = "Cellar", Zone = "Cellar", Floor = 0, x1 = 0, z1 = 72, x2 = 44, z2 = 108 },
	{ Id = "Foyer", Zone = "Foyer", Floor = 0, x1 = 44, z1 = 72, x2 = 88, z2 = 108, NoCeiling = true },
	{ Id = "Storage", Zone = "Storage", Floor = 0, x1 = 88, z1 = 72, x2 = 110, z2 = 108 },
	{ Id = "BoilerRoom", Zone = "BoilerRoom", Floor = 0, x1 = 110, z1 = 72, x2 = 132, z2 = 108 },

	-- UPPER FLOOR ----------------------------------------------------------
	{ Id = "MasterBedroom", Zone = "MasterBedroom", Floor = 1, x1 = 0, z1 = 0, x2 = 44, z2 = 40 },
	{ Id = "ChildrensRoom", Zone = "ChildrensRoom", Floor = 1, x1 = 44, z1 = 0, x2 = 88, z2 = 40 },
	{ Id = "Study", Zone = "Study", Floor = 1, x1 = 88, z1 = 0, x2 = 132, z2 = 40 },

	{ Id = "UpperHall", Zone = "Hallway", Floor = 1, x1 = 0, z1 = 40, x2 = 132, z2 = 72 },

	{ Id = "Bathroom", Zone = "Bathroom", Floor = 1, x1 = 0, z1 = 72, x2 = 44, z2 = 108 },
	-- The stairwell has no floor: it is the open shaft above the Foyer. Declaring
	-- it as a room means the wall builder punches a doorway from UpperHall into
	-- it, which is where the ramp arrives.
	{ Id = "Stairwell", Zone = "Foyer", Floor = 1, x1 = 44, z1 = 72, x2 = 88, z2 = 108, NoFloor = true },
	{ Id = "Attic", Zone = "Attic", Floor = 1, x1 = 88, z1 = 72, x2 = 132, z2 = 108 },
}

-- Extra wall openings the automatic doorway pass can't infer.
-- Axis "x": a gap in a wall that runs along X, at the given z. And vice versa.
type Opening = { Floor: number, Axis: string, Coord: number, From: number, To: number }
local EXTRA_OPENINGS: { Opening } = {
	-- Wide opening between the upper hall and the stairwell shaft, so the ramp
	-- arrives into an open landing rather than a doorway.
	{ Floor = 1, Axis = "x", Coord = 72, From = 50, To = 82 },
}

--==========================================================================
-- Per-room contents
--==========================================================================
type RoomContents = {
	Hiding: { { Kind: string, Count: number } }?,
	TaskSpawns: number?,
	NoisyTiles: number?,
	PatrolNodes: number?,
	Ingredient: string?,
	Special: string?,
	LoreNote: string?,
	PlayerSpawn: boolean?,
	KillerSpawn: boolean?,
	HelperSpawn: boolean?,
	SafeZone: boolean?,
	Crawlspace: boolean?,
}

local CONTENTS: { [string]: RoomContents } = {
	Kitchen = {
		Hiding = { { Kind = "Table", Count = 2 }, { Kind = "Closet", Count = 1 } },
		TaskSpawns = 3,
		NoisyTiles = 4,
		PatrolNodes = 3,
		Ingredient = "Garlic",
		LoreNote = "BarbaraBills",
	},
	Pantry = {
		Hiding = { { Kind = "Closet", Count = 2 } },
		TaskSpawns = 2,
		NoisyTiles = 1,
		PatrolNodes = 2,
		HelperSpawn = true,
	},
	DiningRoom = {
		Hiding = { { Kind = "Table", Count = 3 } },
		TaskSpawns = 3,
		NoisyTiles = 2,
		PatrolNodes = 3,
		Special = "Clock",
		LoreNote = "BobLedger",
	},
	LivingRoom = {
		Hiding = { { Kind = "Table", Count = 2 }, { Kind = "Closet", Count = 1 } },
		TaskSpawns = 3,
		NoisyTiles = 2,
		PatrolNodes = 3,
		HelperSpawn = true,
	},
	Library = {
		Hiding = { { Kind = "Closet", Count = 2 } },
		TaskSpawns = 3,
		NoisyTiles = 1,
		PatrolNodes = 3,
		SafeZone = true,
		LoreNote = "RobertJournal",
	},
	Hallway = {
		Hiding = { { Kind = "Closet", Count = 1 } },
		TaskSpawns = 2,
		NoisyTiles = 6,
		PatrolNodes = 4,
		HelperSpawn = true,
	},
	RitualRoom = {
		Hiding = { { Kind = "Table", Count = 1 } },
		TaskSpawns = 2,
		NoisyTiles = 2,
		PatrolNodes = 2,
		Ingredient = "BloodSample",
		Special = "RitualTable",
	},
	Cellar = {
		Hiding = { { Kind = "Locker", Count = 2 }, { Kind = "Table", Count = 1 } },
		TaskSpawns = 3,
		NoisyTiles = 3,
		PatrolNodes = 3,
		Ingredient = "HolyWater",
		KillerSpawn = true,
		SafeZone = true,
	},
	Foyer = {
		Hiding = { { Kind = "Table", Count = 1 } },
		TaskSpawns = 2,
		NoisyTiles = 3,
		PatrolNodes = 3,
		PlayerSpawn = true,
		LoreNote = "PreviousVictim",
	},
	Storage = {
		Hiding = { { Kind = "Locker", Count = 3 } },
		TaskSpawns = 3,
		NoisyTiles = 2,
		PatrolNodes = 2,
		HelperSpawn = true,
	},
	BoilerRoom = {
		Hiding = { { Kind = "Locker", Count = 1 } },
		TaskSpawns = 2,
		NoisyTiles = 5,
		PatrolNodes = 2,
		KillerSpawn = true,
	},

	MasterBedroom = {
		Hiding = { { Kind = "Bed", Count = 2 }, { Kind = "Closet", Count = 1 } },
		TaskSpawns = 3,
		NoisyTiles = 2,
		PatrolNodes = 3,
		KillerSpawn = true,
	},
	ChildrensRoom = {
		Hiding = { { Kind = "Bed", Count = 3 }, { Kind = "Closet", Count = 2 } },
		TaskSpawns = 3,
		NoisyTiles = 2,
		PatrolNodes = 3,
		Crawlspace = true,
		LoreNote = "AvaDiary1",
	},
	Study = {
		Hiding = { { Kind = "Table", Count = 2 } },
		TaskSpawns = 3,
		NoisyTiles = 1,
		PatrolNodes = 2,
		Ingredient = "MagicDust",
		LoreNote = "BillyLetter",
	},
	UpperHall = {
		Hiding = { { Kind = "Closet", Count = 2 } },
		TaskSpawns = 3,
		NoisyTiles = 6,
		PatrolNodes = 4,
		HelperSpawn = true,
	},
	Bathroom = {
		Hiding = { { Kind = "Closet", Count = 1 }, { Kind = "Table", Count = 1 } },
		TaskSpawns = 2,
		NoisyTiles = 2,
		PatrolNodes = 2,
	},
	Attic = {
		Hiding = { { Kind = "Locker", Count = 2 }, { Kind = "Duct", Count = 2 } },
		TaskSpawns = 3,
		NoisyTiles = 3,
		PatrolNodes = 3,
		KillerSpawn = true,
		SafeZone = true,
		Crawlspace = true,
		LoreNote = "AvaDiary2",
	},
	Stairwell = {
		PatrolNodes = 2,
	},
}

--==========================================================================
-- Part helpers
--==========================================================================

local function part(props: { [string]: any }): BasePart
	local p = Instance.new("Part")
	p.Anchored = true
	p.CanCollide = true
	p.Material = Enum.Material.Wood
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	for key, value in props do
		if key ~= "Parent" then
			(p :: any)[key] = value
		end
	end
	p.Parent = props.Parent
	return p
end

local function floorY(floor: number): number
	return floor * FLOOR_HEIGHT
end

local function roomCenter(room: RoomDef): Vector3
	return Vector3.new((room.x1 + room.x2) / 2, floorY(room.Floor), (room.z1 + room.z2) / 2)
end

--==========================================================================
-- Walls
--==========================================================================

--[[
	Builds one edge of a room as a run of wall segments with gaps.

	`axis` is the direction the wall RUNS along:
	  "x" -> the wall runs along X at a fixed Z
	  "z" -> the wall runs along Z at a fixed X
]]
local function buildEdge(
	container: Instance,
	floor: number,
	axis: string,
	coord: number,
	from: number,
	to: number,
	gaps: { { number } }
)
	table.sort(gaps, function(a, b)
		return a[1] < b[1]
	end)

	-- Merge overlapping gaps so two neighbours sharing an edge don't fight.
	local merged: { { number } } = {}
	for _, gap in gaps do
		local last = merged[#merged]
		if last and gap[1] <= last[2] then
			last[2] = math.max(last[2], gap[2])
		else
			table.insert(merged, { gap[1], gap[2] })
		end
	end

	local y = floorY(floor)

	local function segment(a: number, b: number, height: number, yOffset: number)
		local length = b - a
		if length <= 0.05 then
			return
		end
		local mid = (a + b) / 2
		local size, position
		if axis == "x" then
			size = Vector3.new(length, height, WALL_THICKNESS)
			position = Vector3.new(mid, y + yOffset + height / 2, coord)
		else
			size = Vector3.new(WALL_THICKNESS, height, length)
			position = Vector3.new(coord, y + yOffset + height / 2, mid)
		end
		part({
			Name = "Wall",
			Size = size,
			CFrame = CFrame.new(position),
			Color = PALETTE.Wall,
			Material = Enum.Material.Plaster,
			Parent = container,
		})
	end

	-- Solid runs between the gaps.
	local cursor = from
	for _, gap in merged do
		segment(cursor, math.max(cursor, gap[1]), WALL_HEIGHT, 0)
		-- Lintel above each doorway.
		if WALL_HEIGHT > DOOR_HEIGHT then
			segment(gap[1], gap[2], WALL_HEIGHT - DOOR_HEIGHT, DOOR_HEIGHT)
		end
		cursor = math.max(cursor, gap[2])
	end
	segment(cursor, to, WALL_HEIGHT, 0)
end

--- Rooms on `floor` whose edge sits flush against the given edge, with the
--- overlapping span along the shared axis.
local function findNeighbours(room: RoomDef, side: string): { { room: RoomDef, from: number, to: number } }
	local out = {}
	for _, other in ROOMS do
		if other == room or other.Floor ~= room.Floor then
			continue
		end

		if side == "north" and math.abs(other.z2 - room.z1) < 0.01 then
			local from, to = math.max(room.x1, other.x1), math.min(room.x2, other.x2)
			if to - from > 1 then
				table.insert(out, { room = other, from = from, to = to })
			end
		elseif side == "south" and math.abs(other.z1 - room.z2) < 0.01 then
			local from, to = math.max(room.x1, other.x1), math.min(room.x2, other.x2)
			if to - from > 1 then
				table.insert(out, { room = other, from = from, to = to })
			end
		elseif side == "west" and math.abs(other.x2 - room.x1) < 0.01 then
			local from, to = math.max(room.z1, other.z1), math.min(room.z2, other.z2)
			if to - from > 1 then
				table.insert(out, { room = other, from = from, to = to })
			end
		elseif side == "east" and math.abs(other.x1 - room.x2) < 0.01 then
			local from, to = math.max(room.z1, other.z1), math.min(room.z2, other.z2)
			if to - from > 1 then
				table.insert(out, { room = other, from = from, to = to })
			end
		end
	end
	return out
end

local function gapsFor(
	room: RoomDef,
	side: string,
	axis: string,
	coord: number
): { { number } }
	local gaps: { { number } } = {}

	for _, neighbour in findNeighbours(room, side) do
		local span = neighbour.to - neighbour.from
		local width = math.min(DOOR_WIDTH, span - 3)
		if width > 2 then
			local mid = (neighbour.from + neighbour.to) / 2
			table.insert(gaps, { mid - width / 2, mid + width / 2 })
		end
	end

	for _, opening in EXTRA_OPENINGS do
		if opening.Floor == room.Floor and opening.Axis == axis and math.abs(opening.Coord - coord) < 0.01 then
			table.insert(gaps, { opening.From, opening.To })
		end
	end

	return gaps
end

--[[
	Every interior boundary must be built exactly once, or coincident walls
	z-fight and double the part count. The rule: a room always builds its
	minimum-X and minimum-Z edges, and builds its maximum edges only when
	nothing is on the other side. Each shared boundary therefore belongs to
	whichever room is on its far side, and exterior walls belong to the only
	room that touches them.
]]
local function buildWalls(container: Instance)
	for _, room in ROOMS do
		buildEdge(container, room.Floor, "x", room.z1, room.x1, room.x2, gapsFor(room, "north", "x", room.z1))
		buildEdge(container, room.Floor, "z", room.x1, room.z1, room.z2, gapsFor(room, "west", "z", room.x1))

		if #findNeighbours(room, "south") == 0 then
			buildEdge(container, room.Floor, "x", room.z2, room.x1, room.x2, gapsFor(room, "south", "x", room.z2))
		end
		if #findNeighbours(room, "east") == 0 then
			buildEdge(container, room.Floor, "z", room.x2, room.z1, room.z2, gapsFor(room, "east", "z", room.x2))
		end
	end
end

--==========================================================================
-- Floors and ceilings
--==========================================================================

local function buildFloors(container: Instance)
	for _, room in ROOMS do
		if room.NoFloor then
			continue
		end
		local width = room.x2 - room.x1
		local depth = room.z2 - room.z1
		part({
			Name = `Floor_{room.Id}`,
			Size = Vector3.new(width, FLOOR_THICKNESS, depth),
			CFrame = CFrame.new(
				(room.x1 + room.x2) / 2,
				floorY(room.Floor) - FLOOR_THICKNESS / 2,
				(room.z1 + room.z2) / 2
			),
			Color = room.Floor == 0 and PALETTE.Floor or PALETTE.FloorUpper,
			Material = Enum.Material.WoodPlanks,
			Parent = container,
		})
	end

	-- Roof over the top storey.
	local topFloor = 0
	for _, room in ROOMS do
		topFloor = math.max(topFloor, room.Floor)
	end
	for _, room in ROOMS do
		if room.Floor == topFloor and not room.NoCeiling then
			part({
				Name = `Roof_{room.Id}`,
				Size = Vector3.new(room.x2 - room.x1, FLOOR_THICKNESS, room.z2 - room.z1),
				CFrame = CFrame.new(
					(room.x1 + room.x2) / 2,
					floorY(room.Floor) + WALL_HEIGHT + FLOOR_THICKNESS / 2,
					(room.z1 + room.z2) / 2
				),
				Color = PALETTE.Trim,
				Material = Enum.Material.Slate,
				Parent = container,
			})
		end
	end
end

--- The ramp up through the stairwell shaft.
local function buildStairs(container: Instance)
	local bottomZ, topZ = 104, 74
	local x = 66
	local width = 14
	local rise = FLOOR_HEIGHT
	local run = bottomZ - topZ
	local length = math.sqrt(run * run + rise * rise)

	local ramp = part({
		Name = "Staircase",
		Size = Vector3.new(width, 1.5, length),
		Color = PALETTE.Trim,
		Material = Enum.Material.WoodPlanks,
		Parent = container,
	})
	ramp.CFrame = CFrame.lookAt(
		Vector3.new(x, rise / 2 - 0.75, (bottomZ + topZ) / 2),
		Vector3.new(x, rise - 0.75, topZ)
	)

	-- Landing at the top so the humanoid steps off flat.
	part({
		Name = "StairLanding",
		Size = Vector3.new(width, FLOOR_THICKNESS, 6),
		CFrame = CFrame.new(x, floorY(1) - FLOOR_THICKNESS / 2, topZ - 2),
		Color = PALETTE.Trim,
		Material = Enum.Material.WoodPlanks,
		Parent = container,
	})

	-- Railings so players don't walk off the side of the ramp.
	for _, offset in { -1, 1 } do
		local rail = part({
			Name = "StairRail",
			Size = Vector3.new(0.8, 5, length),
			Color = PALETTE.Trim,
			Material = Enum.Material.Wood,
			Parent = container,
		})
		rail.CFrame = ramp.CFrame * CFrame.new(offset * width / 2, 3, 0)
	end
end

--==========================================================================
-- Props and tagged points
--==========================================================================

--- A point inside a room, inset from the walls, on a jittered grid so props
--- don't stack on top of each other.
local function scatter(room: RoomDef, rng: Random, inset: number): Vector3
	local x = rng:NextNumber(room.x1 + inset, room.x2 - inset)
	local z = rng:NextNumber(room.z1 + inset, room.z2 - inset)
	return Vector3.new(x, floorY(room.Floor), z)
end

local HIDE_SPOT_SPECS = {
	Locker = { Size = Vector3.new(4, 9, 3), Color = PALETTE.Metal, Material = Enum.Material.Metal, YOffset = 4.5 },
	Closet = { Size = Vector3.new(6, 10, 4), Color = PALETTE.Prop, Material = Enum.Material.Wood, YOffset = 5 },
	Bed = { Size = Vector3.new(8, 3, 12), Color = PALETTE.Prop, Material = Enum.Material.Fabric, YOffset = 1.5 },
	Table = { Size = Vector3.new(11, 4, 6), Color = PALETTE.Prop, Material = Enum.Material.Wood, YOffset = 2 },
	Duct = { Size = Vector3.new(5, 4, 5), Color = PALETTE.Metal, Material = Enum.Material.DiamondPlate, YOffset = 2 },
}

local function buildRoomContents(container: Instance, room: RoomDef, rng: Random)
	local contents = CONTENTS[room.Id]
	if not contents then
		return
	end

	local folder = Instance.new("Folder")
	folder.Name = room.Id
	folder.Parent = container

	-- Hiding spots -------------------------------------------------------
	for _, spec in contents.Hiding or {} do
		local shape = HIDE_SPOT_SPECS[spec.Kind]
		if not shape then
			continue
		end
		for _ = 1, spec.Count do
			local position = scatter(room, rng, 7)
			local prop = part({
				Name = `Hide_{spec.Kind}`,
				Size = shape.Size,
				CFrame = CFrame.new(position + Vector3.new(0, shape.YOffset, 0))
					* CFrame.Angles(0, rng:NextNumber(0, math.pi * 2), 0),
				Color = shape.Color,
				Material = shape.Material,
				Parent = folder,
			})
			-- Tables and beds are hidden *under*, so players must be able to walk
			-- through them; lockers and closets are solid.
			prop.CanCollide = spec.Kind ~= "Table" and spec.Kind ~= "Bed"
			prop:SetAttribute("Kind", spec.Kind)
			prop:SetAttribute("Zone", room.Zone)
			CollectionService:AddTag(prop, Tags.HidingSpot)
		end
	end

	-- Task item spawn points ---------------------------------------------
	for index = 1, contents.TaskSpawns or 0 do
		local position = scatter(room, rng, 6)
		local marker = part({
			Name = `TaskSpawn_{index}`,
			Size = Vector3.new(1, 1, 1),
			CFrame = CFrame.new(position + Vector3.new(0, 3, 0)),
			Transparency = 1,
			CanCollide = false,
			Parent = folder,
		})
		marker:SetAttribute("TaskType", "Any")
		marker:SetAttribute("Zone", room.Zone)
		CollectionService:AddTag(marker, Tags.TaskSpawn)
	end

	-- Creaky floorboards ---------------------------------------------------
	for index = 1, contents.NoisyTiles or 0 do
		local position = scatter(room, rng, 4)
		local tile = part({
			Name = `NoisyTile_{index}`,
			Size = Vector3.new(rng:NextNumber(5, 9), 0.25, rng:NextNumber(5, 9)),
			CFrame = CFrame.new(position + Vector3.new(0, 0.12, 0)),
			-- Subtly darker than the floor: visible if you're looking, invisible
			-- if you're running.
			Color = PALETTE.Floor:Lerp(Color3.new(0, 0, 0), 0.25),
			Material = Enum.Material.WoodPlanks,
			CanCollide = false,
			Parent = folder,
		})
		tile:SetAttribute("Noise", Config.Noise.Actions.CreakyFloor)
		CollectionService:AddTag(tile, Tags.NoisyTile)
	end

	-- Patrol waypoints -----------------------------------------------------
	for index = 1, contents.PatrolNodes or 0 do
		local position = scatter(room, rng, 6)
		local node = part({
			Name = `Patrol_{index}`,
			Size = Vector3.new(1, 1, 1),
			CFrame = CFrame.new(position + Vector3.new(0, 2, 0)),
			Transparency = 1,
			CanCollide = false,
			Parent = folder,
		})
		node:SetAttribute("Zone", room.Zone)
		CollectionService:AddTag(node, Tags.PatrolNode)
		if contents.Crawlspace then
			CollectionService:AddTag(node, Tags.Crawlspace)
		end
	end

	-- Sealing-potion ingredient -------------------------------------------
	if contents.Ingredient then
		local position = scatter(room, rng, 8)
		local pedestal = part({
			Name = `Ingredient_{contents.Ingredient}`,
			Size = Vector3.new(3, 4, 3),
			CFrame = CFrame.new(position + Vector3.new(0, 2, 0)),
			Color = PALETTE.Trim,
			Material = Enum.Material.Slate,
			Parent = folder,
		})
		pedestal:SetAttribute("Ingredient", contents.Ingredient)
		pedestal:SetAttribute("Zone", room.Zone)
		CollectionService:AddTag(pedestal, Tags.IngredientSpawn)
	end

	-- One-off interactables -------------------------------------------------
	if contents.Special == "Clock" then
		local position = Vector3.new(room.x1 + 4, floorY(room.Floor), (room.z1 + room.z2) / 2)
		local clock = part({
			Name = "GrandfatherClock",
			Size = Vector3.new(4, 14, 3),
			CFrame = CFrame.new(position + Vector3.new(0, 7, 0)),
			Color = Color3.fromRGB(58, 40, 28),
			Material = Enum.Material.Wood,
			Parent = folder,
		})
		clock:SetAttribute("Zone", room.Zone)
		CollectionService:AddTag(clock, Tags.Clock)
	elseif contents.Special == "RitualTable" then
		local table_ = part({
			Name = "RitualTable",
			Size = Vector3.new(10, 4, 6),
			CFrame = CFrame.new(roomCenter(room) + Vector3.new(0, 2, 0)),
			Color = Color3.fromRGB(40, 26, 26),
			Material = Enum.Material.Marble,
			Parent = folder,
		})
		table_:SetAttribute("Zone", room.Zone)
		CollectionService:AddTag(table_, Tags.RitualTable)
	end

	-- Fuse boxes back the safe-zone objective; put one wherever there's a zone.
	if contents.SafeZone then
		local center = roomCenter(room)
		local zone = part({
			Name = "SafeZone",
			Size = Vector3.new(20, 12, 20),
			CFrame = CFrame.new(center + Vector3.new(0, 6, 0)),
			Transparency = 0.85,
			Color = Color3.fromRGB(240, 210, 130),
			Material = Enum.Material.Neon,
			CanCollide = false,
			Parent = folder,
		})
		CollectionService:AddTag(zone, Tags.SafeZone)

		local fuse = part({
			Name = "FuseBox",
			Size = Vector3.new(3, 4, 1.5),
			CFrame = CFrame.new(Vector3.new(room.x1 + 3, floorY(room.Floor) + 6, room.z1 + 6)),
			Color = PALETTE.Metal,
			Material = Enum.Material.DiamondPlate,
			Parent = folder,
		})
		fuse:SetAttribute("Zone", room.Zone)
		CollectionService:AddTag(fuse, Tags.FuseBox)
	end

	-- Spawn markers ---------------------------------------------------------
	if contents.PlayerSpawn then
		for index = 1, 12 do
			local angle = (index / 12) * math.pi * 2
			local center = roomCenter(room)
			local marker = part({
				Name = `PlayerSpawn_{index}`,
				Size = Vector3.new(2, 1, 2),
				CFrame = CFrame.new(center + Vector3.new(math.cos(angle) * 12, 3, math.sin(angle) * 12)),
				Transparency = 1,
				CanCollide = false,
				Parent = folder,
			})
			CollectionService:AddTag(marker, Tags.PlayerSpawn)
		end
	end

	if contents.KillerSpawn then
		local marker = part({
			Name = "KillerSpawn",
			Size = Vector3.new(2, 1, 2),
			CFrame = CFrame.new(roomCenter(room) + Vector3.new(0, 4, 0)),
			Transparency = 1,
			CanCollide = false,
			Parent = folder,
		})
		marker:SetAttribute("Zone", room.Zone)
		CollectionService:AddTag(marker, Tags.KillerSpawn)
	end

	if contents.HelperSpawn then
		local marker = part({
			Name = "HelperSpawn",
			Size = Vector3.new(2, 1, 2),
			CFrame = CFrame.new(roomCenter(room) + Vector3.new(0, 3, 0)),
			Transparency = 1,
			CanCollide = false,
			Parent = folder,
		})
		marker:SetAttribute("Zone", room.Zone)
		CollectionService:AddTag(marker, Tags.HelperSpawn)
	end

	-- Environmental storytelling -------------------------------------------
	if contents.LoreNote then
		local note = part({
			Name = "LoreNote",
			Size = Vector3.new(2, 0.2, 2.6),
			CFrame = CFrame.new(scatter(room, rng, 8) + Vector3.new(0, 0.3, 0))
				* CFrame.Angles(0, rng:NextNumber(0, math.pi * 2), 0),
			Color = Color3.fromRGB(212, 198, 160),
			Material = Enum.Material.SmoothPlastic,
			CanCollide = false,
			Parent = folder,
		})
		note:SetAttribute("NoteId", contents.LoreNote)
		CollectionService:AddTag(note, Tags.LoreNote)
	end
end

--==========================================================================
-- Lighting props
--==========================================================================

local function buildAtmosphere(container: Instance, rng: Random)
	for _, room in ROOMS do
		if room.NoFloor then
			continue
		end
		local center = roomCenter(room)
		local lamp = part({
			Name = "Candle",
			Size = Vector3.new(0.8, 1.6, 0.8),
			CFrame = CFrame.new(center + Vector3.new(0, WALL_HEIGHT - 3, 0)),
			Color = Color3.fromRGB(220, 200, 150),
			Material = Enum.Material.Neon,
			CanCollide = false,
			Parent = container,
		})

		local light = Instance.new("PointLight")
		light.Color = Color3.fromRGB(255, 190, 120)
		light.Brightness = 1.1
		light.Range = math.max(room.x2 - room.x1, room.z2 - room.z1) * 0.85
		light.Shadows = true
		light.Parent = lamp

		-- Flicker. Cheap, and it sells the whole thing.
		task.spawn(function()
			while lamp.Parent do
				light.Brightness = rng:NextNumber(0.75, 1.25)
				task.wait(rng:NextNumber(0.08, 0.4))
			end
		end)
	end
end

--==========================================================================
-- Public: the House
--==========================================================================

function MapBuilder.buildHouse(): Model
	local rng = Random.new(20250728) -- fixed seed: the greybox is the same every time

	local model = Instance.new("Model")
	model.Name = "TheHouse"

	local structure = Instance.new("Folder")
	structure.Name = "Structure"
	structure.Parent = model

	local props = Instance.new("Folder")
	props.Name = "Props"
	props.Parent = model

	buildFloors(structure)
	buildWalls(structure)
	buildStairs(structure)

	for _, room in ROOMS do
		buildRoomContents(props, room, rng)
	end

	buildAtmosphere(props, rng)

	-- A ground slab under everything, so falling off the ramp isn't fatal and
	-- pathfinding has something to project onto.
	part({
		Name = "Ground",
		Size = Vector3.new(260, 4, 240),
		CFrame = CFrame.new(66, -FLOOR_THICKNESS - 2, 54),
		Color = Color3.fromRGB(38, 42, 34),
		Material = Enum.Material.Ground,
		Parent = structure,
	})

	model.PrimaryPart = structure:FindFirstChild("Ground") :: BasePart
	return model
end

--==========================================================================
-- Public: the lobby
--==========================================================================

--- The lobby lives well above the maps so nothing can ever overlap it.
function MapBuilder.buildLobby(): Model
	local ORIGIN = Vector3.new(0, 500, 0)
	local SIZE = 120

	local model = Instance.new("Model")
	model.Name = "Lobby"

	local floor = part({
		Name = "LobbyFloor",
		Size = Vector3.new(SIZE, 4, SIZE),
		CFrame = CFrame.new(ORIGIN),
		Color = PALETTE.Lobby,
		Material = Enum.Material.Slate,
		Parent = model,
	})

	-- Perimeter walls, so nobody walks off the edge mid-vote.
	for _, spec in
		{
			{ Vector3.new(SIZE, 24, 2), Vector3.new(0, 14, -SIZE / 2) },
			{ Vector3.new(SIZE, 24, 2), Vector3.new(0, 14, SIZE / 2) },
			{ Vector3.new(2, 24, SIZE), Vector3.new(-SIZE / 2, 14, 0) },
			{ Vector3.new(2, 24, SIZE), Vector3.new(SIZE / 2, 14, 0) },
		}
	do
		part({
			Name = "LobbyWall",
			Size = spec[1],
			CFrame = CFrame.new(ORIGIN + spec[2]),
			Color = PALETTE.Lobby,
			Material = Enum.Material.Concrete,
			Transparency = 0.25,
			Parent = model,
		})
	end

	-- Roblox's own respawn point, and the default for everyone.
	--
	-- Deliberately Neutral rather than locked to the Lost team: if it were
	-- team-locked and a mid-round player somehow respawned while still on
	-- Survivors, Roblox would find no matching spawn and drop them at the world
	-- origin. GameStateManager teleports players onto the map explicitly at
	-- round start, so "everyone respawns in the lobby" is exactly the behaviour
	-- we want from the engine.
	local spawn = Instance.new("SpawnLocation")
	spawn.Name = "LobbySpawn"
	spawn.Size = Vector3.new(20, 1, 20)
	spawn.CFrame = CFrame.new(ORIGIN + Vector3.new(0, 2.5, 0))
	spawn.Anchored = true
	spawn.Color = PALETTE.LobbyAccent
	spawn.Material = Enum.Material.Marble
	spawn.Neutral = true
	spawn.Duration = 0 -- no spawn forcefield; it would look wrong on a horror map
	spawn.Parent = model
	CollectionService:AddTag(spawn, Tags.LobbySpawn)

	-- Extra spawn markers so a full server doesn't stack everyone on one pad.
	for index = 1, 12 do
		local angle = (index / 12) * math.pi * 2
		local marker = part({
			Name = `LobbySpawnPoint_{index}`,
			Size = Vector3.new(2, 1, 2),
			CFrame = CFrame.new(ORIGIN + Vector3.new(math.cos(angle) * 22, 4, math.sin(angle) * 22)),
			Transparency = 1,
			CanCollide = false,
			Parent = model,
		})
		CollectionService:AddTag(marker, Tags.LobbySpawn)
	end

	-- Shop plinth. ShopService attaches the ProximityPrompt.
	local shop = part({
		Name = "ShopStand",
		Size = Vector3.new(8, 6, 4),
		CFrame = CFrame.new(ORIGIN + Vector3.new(-34, 5, 0)),
		Color = PALETTE.LobbyAccent,
		Material = Enum.Material.Wood,
		Parent = model,
	})
	shop:SetAttribute("DollysHomeShop", true)

	local shopSign = Instance.new("BillboardGui")
	shopSign.Name = "Sign"
	shopSign.Size = UDim2.fromScale(8, 2)
	shopSign.StudsOffsetWorldSpace = Vector3.new(0, 5, 0)
	shopSign.AlwaysOnTop = false
	shopSign.MaxDistance = 90
	shopSign.Parent = shop

	local shopLabel = Instance.new("TextLabel")
	shopLabel.Size = UDim2.fromScale(1, 1)
	shopLabel.BackgroundTransparency = 1
	shopLabel.Font = Enum.Font.GothamBold
	shopLabel.Text = "PEDDLER'S CART"
	shopLabel.TextColor3 = Color3.fromRGB(240, 220, 180)
	shopLabel.TextScaled = true
	shopLabel.Parent = shopSign

	-- Ambient light so the lobby isn't pitch black under the horror lighting.
	local lampPost = part({
		Name = "LobbyLamp",
		Size = Vector3.new(2, 2, 2),
		CFrame = CFrame.new(ORIGIN + Vector3.new(0, 22, 0)),
		Color = Color3.fromRGB(255, 235, 200),
		Material = Enum.Material.Neon,
		CanCollide = false,
		Parent = model,
	})
	local lobbyLight = Instance.new("PointLight")
	lobbyLight.Brightness = 3
	lobbyLight.Range = 100
	lobbyLight.Color = Color3.fromRGB(255, 225, 190)
	lobbyLight.Parent = lampPost

	model.PrimaryPart = floor
	return model
end

--==========================================================================
-- Dispatch
--==========================================================================

--- Generates a greybox for `mapId`, or nil if there's no generator for it.
function MapBuilder.build(mapId: string): Model?
	if mapId == "TheHouse" then
		return MapBuilder.buildHouse()
	end
	Util.warn(
		"MapBuilder",
		'no greybox generator for map "%s" -- build it in Studio and save it to ServerStorage/Maps/%s',
		mapId,
		mapId
	)
	return nil
end

return MapBuilder
