--!strict
--[[
	HouseData.luau
	--------------------------------------------------------------------------
	MAP 1 -- THE HOUSE. Transcribed from the house.js mockup.

	Decaying Louisiana plantation manor: basement, ground, second floor and
	attic. Footprint 116 x 88 studs. Everything is in ROBLOX STUDS already, so
	the numbers below are the mockup's numbers unchanged -- which means when you
	move a hiding spot in the mockup, you change one line here and nothing else.

	This file is DATA ONLY. MapBuilder turns it into parts and tags.

	Positions are {x, z}; the Y comes from the floor the entry belongs to.
	--------------------------------------------------------------------------
]]

local HouseData = {}

--==========================================================================
-- Vertical layout
--==========================================================================
HouseData.FloorY = {
	basement = -11,
	ground = 0,
	second = 11,
	attic = 22,
}

HouseData.WallHeight = {
	basement = 9,
	ground = 10,
	second = 9,
	attic = 7,
}

--- Bottom to top, which is the order they get built in.
HouseData.FloorOrder = { "basement", "ground", "second", "attic" }

local W_EXT = 1.2
local W_INT = 0.8

--==========================================================================
-- Rooms
--==========================================================================
export type Room = {
	f: string,
	id: string,
	name: string,
	x0: number,
	x1: number,
	z0: number,
	z1: number,
	mat: string,
	note: string,
	zone: string, -- maps onto KillerData.PatrolZones
}

HouseData.Rooms = {
	-- GROUND ---------------------------------------------------------------
	{ f = "ground", id = "foyer", name = "Foyer", x0 = -16, x1 = 16, z0 = 8, z1 = 44, mat = "woodFloor", note = "Central hub, grand stair", zone = "Foyer" },
	{ f = "ground", id = "living", name = "Living Room", x0 = -58, x1 = -18, z0 = 14, z1 = 44, mat = "carpet", note = "Sofas, curtains", zone = "LivingRoom" },
	{ f = "ground", id = "library", name = "Library", x0 = -58, x1 = -18, z0 = -44, z1 = 12, mat = "woodFloor", note = "Safe zone behind shelf", zone = "Library" },
	{ f = "ground", id = "dining", name = "Dining Room", x0 = 18, x1 = 58, z0 = 14, z1 = 44, mat = "woodFloor", note = "Long table, chairs", zone = "DiningRoom" },
	{ f = "ground", id = "kitchen", name = "Kitchen", x0 = 18, x1 = 58, z0 = -14, z1 = 12, mat = "tile", note = "Garlic, noisy tiles", zone = "Kitchen" },
	{ f = "ground", id = "pantry", name = "Pantry", x0 = 18, x1 = 36, z0 = -44, z1 = -16, mat = "tile", note = "Closet hide", zone = "Pantry" },
	{ f = "ground", id = "cstair", name = "Cellar Stair", x0 = 38, x1 = 58, z0 = -44, z1 = -16, mat = "stone", note = "Down to basement", zone = "Cellar" },
	{ f = "ground", id = "ritual", name = "Ritual Room", x0 = -16, x1 = 16, z0 = -44, z1 = 6, mat = "stone", note = "Blood sample, altar", zone = "RitualRoom" },

	-- SECOND ---------------------------------------------------------------
	{ f = "second", id = "landing", name = "Landing", x0 = -16, x1 = 16, z0 = -44, z1 = 44, mat = "woodFloor", note = "Stair well, attic ladder", zone = "Hallway" },
	{ f = "second", id = "master", name = "Master Bedroom", x0 = -58, x1 = -18, z0 = 10, z1 = 44, mat = "carpet", note = "Bob & Barbara, bed hide", zone = "MasterBedroom" },
	{ f = "second", id = "child1", name = "Child's Room I", x0 = -58, x1 = -18, z0 = -18, z1 = 8, mat = "woodFloor", note = "Closet, under-bed", zone = "ChildrensRoom" },
	{ f = "second", id = "child2", name = "Child's Room II", x0 = -58, x1 = -18, z0 = -44, z1 = -20, mat = "woodFloor", note = "Closet, under-bed", zone = "ChildrensRoom" },
	{ f = "second", id = "bath", name = "Bathroom", x0 = 18, x1 = 58, z0 = 22, z1 = 44, mat = "tile", note = "Bathtub hide", zone = "Bathroom" },
	{ f = "second", id = "child3", name = "Child's Room III", x0 = 18, x1 = 58, z0 = -6, z1 = 20, mat = "woodFloor", note = "Duct entry, closet", zone = "ChildrensRoom" },
	{ f = "second", id = "study", name = "Study", x0 = 18, x1 = 58, z0 = -44, z1 = -8, mat = "woodFloor", note = "Magic dust, desk", zone = "Study" },

	-- BASEMENT -------------------------------------------------------------
	{ f = "basement", id = "cellar", name = "Wine Cellar", x0 = -40, x1 = -4, z0 = -36, z1 = 30, mat = "stone", note = "Holy water, barrels", zone = "Cellar" },
	{ f = "basement", id = "storage", name = "Storage Room", x0 = 4, x1 = 50, z0 = 2, z1 = 30, mat = "stone", note = "Lockers, shelves", zone = "Storage" },
	{ f = "basement", id = "boilerR", name = "Boiler Room", x0 = 4, x1 = 50, z0 = -36, z1 = 0, mat = "stone", note = "Steam vents, loud", zone = "BoilerRoom" },

	-- ATTIC ----------------------------------------------------------------
	{ f = "attic", id = "attic", name = "Attic", x0 = -26, x1 = 26, z0 = -22, z1 = 22, mat = "woodPale", note = "Cramped, safe zone", zone = "Attic" },
} :: { Room }

--==========================================================================
-- Walls
--==========================================================================
-- A door is either a bare number (plain 5-wide doorway at that centre) or a
-- table {c, w, h, sill}. `sill > 0` makes it a window.
local function win(c: number, w: number?)
	return { c = c, w = w or 6, h = 7, sill = 3 }
end

HouseData.Walls = {
	ground = {
		{ a = { -58, 44 }, b = { 58, 44 }, t = W_EXT, ext = true, doors = { { c = 0, w = 8, h = 9 }, win(-34), win(-24), win(30), win(42) } },
		{ a = { -58, -44 }, b = { 58, -44 }, t = W_EXT, ext = true, doors = { { c = 27, w = 5, h = 7.5 }, win(-40), win(-8), win(8), win(48) } },
		{ a = { -58, -44 }, b = { -58, 44 }, t = W_EXT, ext = true, doors = { win(-30), win(0), win(24), win(38) } },
		{ a = { 58, -44 }, b = { 58, 44 }, t = W_EXT, ext = true, doors = { win(-30), win(0), win(24), win(38) } },
		{ a = { -17, -44 }, b = { -17, 44 }, t = W_INT, doors = { 30, -10 } },
		{ a = { 17, -44 }, b = { 17, 44 }, t = W_INT, doors = { 30, -6 } },
		{ a = { -58, 13 }, b = { -17, 13 }, t = W_INT, doors = { -38 } },
		{ a = { 17, 13 }, b = { 58, 13 }, t = W_INT, doors = { 44 } },
		{ a = { 17, -15 }, b = { 58, -15 }, t = W_INT, doors = { 27, 50 } },
		{ a = { 37, -44 }, b = { 37, -15 }, t = W_INT, doors = {} },
		{ a = { -17, 7 }, b = { 17, 7 }, t = W_INT, doors = { { c = 0, w = 7 } } },
	},
	second = {
		{ a = { -58, 44 }, b = { 58, 44 }, t = W_EXT, ext = true, doors = { win(-34), win(0), win(34) } },
		{ a = { -58, -44 }, b = { 58, -44 }, t = W_EXT, ext = true, doors = { win(-34), win(0), win(34) } },
		{ a = { -58, -44 }, b = { -58, 44 }, t = W_EXT, ext = true, doors = { win(-28), win(0), win(28) } },
		{ a = { 58, -44 }, b = { 58, 44 }, t = W_EXT, ext = true, doors = { win(-28), win(0), win(28) } },
		{ a = { -17, -44 }, b = { -17, 44 }, t = W_INT, doors = { 28, -4, -30 } },
		{ a = { 17, -44 }, b = { 17, 44 }, t = W_INT, doors = { 32, 6, -24 } },
		{ a = { -58, 9 }, b = { -17, 9 }, t = W_INT, doors = {} },
		{ a = { -58, -19 }, b = { -17, -19 }, t = W_INT, doors = {} },
		{ a = { 17, 21 }, b = { 58, 21 }, t = W_INT, doors = {} },
		{ a = { 17, -7 }, b = { 58, -7 }, t = W_INT, doors = {} },
	},
	basement = {
		{ a = { -40, 30 }, b = { 50, 30 }, t = W_EXT, ext = true, doors = {} },
		{ a = { -40, -36 }, b = { 50, -36 }, t = W_EXT, ext = true, doors = {} },
		{ a = { -40, -36 }, b = { -40, 30 }, t = W_EXT, ext = true, doors = {} },
		{ a = { 50, -36 }, b = { 50, 30 }, t = W_EXT, ext = true, doors = {} },
		{ a = { 0, -36 }, b = { 0, 30 }, t = W_INT, doors = { 16, -20 } },
		{ a = { 0, 1 }, b = { 50, 1 }, t = W_INT, doors = { 22 } },
	},
	attic = {
		{ a = { -26, 22 }, b = { 26, 22 }, t = W_INT, doors = { win(0, 6) } },
		{ a = { -26, -22 }, b = { 26, -22 }, t = W_INT, doors = { win(0, 6) } },
		{ a = { -26, -22 }, b = { -26, 22 }, t = W_INT, doors = {} },
		{ a = { 26, -22 }, b = { 26, 22 }, t = W_INT, doors = {} },
	},
}

--==========================================================================
-- Vertical connections
--==========================================================================
-- Explicit from/to rather than the mockup's (width, rise, run, dir) form, so
-- the two floors they join is unambiguous and pathfinding always works.
HouseData.Stairs = {
	{ name = "GrandStair", from = Vector3.new(-8, 0, 40), to = Vector3.new(-8, 11, 18), width = 10, mat = "woodDark" },
	-- The cellar stair descends within the Cellar Stair room (z -44..-16) and
	-- arrives in the Boiler Room. The mockup's run would have surfaced in the
	-- kitchen, so it is turned to head -Z instead.
	{ name = "CellarStair", from = Vector3.new(48, 0, -20), to = Vector3.new(48, -11, -34), width = 7, mat = "stone" },
}

HouseData.Ladders = {
	{ name = "AtticLadder", bottom = Vector3.new(0, 11, -13.7), height = 11 },
}

--[[
	Openings cut through floor slabs, so the stairs and the ladder actually
	arrive somewhere instead of into the underside of the storey above.

	Each is a rectangle on the named floor; MapBuilder subtracts them from that
	floor's room slabs.
]]
HouseData.FloorHoles = {
	-- Grand stairwell, up through the second-floor landing.
	{ f = "second", x0 = -14, x1 = -2, z0 = 16, z1 = 42 },
	-- Cellar stair, down through the ground floor.
	{ f = "ground", x0 = 44, x1 = 52, z0 = -36, z1 = -17 },
	-- Attic hatch.
	{ f = "attic", x0 = -3, x1 = 3, z0 = -17, z1 = -10 },
}

--==========================================================================
-- Hiding spots
--==========================================================================
-- `t` is the mockup's type; Kind is what HidingService puts on the prompt.
export type Hide = { f: string, t: string, p: { number }, r: number, n: string }

HouseData.Hides = {
	{ f = "ground", t = "table", p = { 38, 30 }, r = 0, n = "Dining table" },
	{ f = "ground", t = "closet", p = { 24, -38 }, r = 0, n = "Pantry closet" },
	{ f = "ground", t = "table", p = { -44, -30 }, r = math.pi / 2, n = "Library desk" },
	{ f = "ground", t = "locker", p = { -52, 34 }, r = math.pi / 2, n = "Hall press" },
	{ f = "ground", t = "duct", p = { 46, -6 }, r = 0, n = "Kitchen shaft" },
	{ f = "second", t = "bed", p = { -40, 30 }, r = 0, n = "Master bed" },
	{ f = "second", t = "bed", p = { -42, -4 }, r = 0, n = "Child I bed" },
	{ f = "second", t = "closet", p = { -24, -30 }, r = -math.pi / 2, n = "Child II closet" },
	{ f = "second", t = "bathtub", p = { 46, 34 }, r = 0, n = "Bathtub" },
	{ f = "second", t = "duct", p = { 22, 8 }, r = math.pi / 2, n = "Child III duct" },
	{ f = "second", t = "table", p = { 44, -30 }, r = 0, n = "Study desk" },
	{ f = "basement", t = "barrel", p = { -30, 16 }, r = 0, n = "Cellar barrel" },
	{ f = "basement", t = "barrel", p = { -22, -18 }, r = 0, n = "Cellar barrel" },
	{ f = "basement", t = "locker", p = { 40, 22 }, r = -math.pi / 2, n = "Storage lockers" },
	{ f = "attic", t = "closet", p = { -18, 12 }, r = 0, n = "Attic trunk press" },
} :: { Hide }

--- Mockup type -> the Kind attribute HidingService reads, plus the prop shape.
HouseData.HideShape = {
	locker = { Kind = "Locker", size = Vector3.new(4, 9, 3), solid = true, mat = "metal" },
	closet = { Kind = "Closet", size = Vector3.new(6, 10, 4), solid = true, mat = "woodDark" },
	bed = { Kind = "Bed", size = Vector3.new(8, 3, 12), solid = false, mat = "cloth" },
	table = { Kind = "Table", size = Vector3.new(11, 4, 6), solid = false, mat = "woodDark" },
	duct = { Kind = "Duct", size = Vector3.new(5, 4, 5), solid = true, mat = "metal" },
	bathtub = { Kind = "Bathtub", size = Vector3.new(6, 3.5, 11), solid = false, mat = "tile" },
	barrel = { Kind = "Barrel", size = Vector3.new(4.5, 6, 4.5), solid = true, mat = "woodDark" },
}

--==========================================================================
-- Noisy floor patches
--==========================================================================
HouseData.Noisy = {
	{ f = "ground", p = { 0, 26 }, s = { 22, 12 }, n = "Foyer glass" },
	{ f = "ground", p = { 0, 0 }, s = { 16, 10 }, n = "Hall boards" },
	{ f = "ground", p = { 36, 0 }, s = { 24, 12 }, n = "Kitchen tiles" },
	{ f = "ground", p = { -38, 12 }, s = { 14, 8 }, n = "Library door" },
	{ f = "second", p = { 0, 20 }, s = { 20, 12 }, n = "Landing boards" },
	{ f = "second", p = { 0, -24 }, s = { 20, 12 }, n = "Back hall" },
	{ f = "second", p = { 30, 6 }, s = { 12, 12 }, n = "Child III floor" },
	{ f = "basement", p = { 24, -18 }, s = { 26, 16 }, n = "Boiler grating" },
	{ f = "basement", p = { -20, 4 }, s = { 16, 12 }, n = "Cellar shards" },
}

--==========================================================================
-- Safe zones
--==========================================================================
-- Each has three entrances, as the design document asks for.
HouseData.SafeZones = {
	{ f = "ground", p = { -46, -22 }, r = 13, n = "Library safe zone", ent = { { -46, -8 }, { -32, -22 }, { -46, -36 } } },
	{ f = "attic", p = { 4, 0 }, r = 12, n = "Attic safe zone", ent = { { 4, 14 }, { 16, 0 }, { -8, 0 } } },
	{ f = "basement", p = { -20, 20 }, r = 12, n = "Cellar safe zone", ent = { { -6, 20 }, { -20, 6 }, { -34, 20 } } },
}

--==========================================================================
-- Objectives
--==========================================================================
-- The four sealing ingredients and the grandfather clock.
HouseData.TaskPins = {
	{ f = "ground", p = { -6, -34 }, k = "blood", n = "Blood Sample" },
	{ f = "ground", p = { 44, -6 }, k = "garlic", n = "Garlic" },
	{ f = "basement", p = { -34, -26 }, k = "holy", n = "Holy Water" },
	{ f = "second", p = { 30, -34 }, k = "dust", n = "Magic Dust" },
	{ f = "ground", p = { -13, 12 }, k = "clock", n = "Grandfather Clock" },
}

HouseData.RitualTable = { f = "ground", p = { 0, -30 } }

-- Exactly 5 / 14 / 15, matching the objective goals in Config.
HouseData.Mirrors = {
	{ f = "ground", p = { -50, 4 } },
	{ f = "ground", p = { 50, 26 } },
	{ f = "second", p = { -30, 38 } },
	{ f = "second", p = { 50, 32 } },
	{ f = "basement", p = { 30, 26 } },
}

HouseData.Crosses = {
	{ f = "ground", p = { -12, 40 } },
	{ f = "ground", p = { 12, 40 } },
	{ f = "ground", p = { -30, 40 } },
	{ f = "ground", p = { 30, 40 } },
	{ f = "ground", p = { -54, -20 } },
	{ f = "ground", p = { 8, -20 } },
	{ f = "ground", p = { 54, 6 } },
	{ f = "second", p = { -54, 40 } },
	{ f = "second", p = { -54, -40 } },
	{ f = "second", p = { 54, 40 } },
	{ f = "second", p = { 54, -40 } },
	{ f = "second", p = { 0, 0 } },
	{ f = "basement", p = { -36, 26 } },
	{ f = "basement", p = { 46, -32 } },
}

HouseData.Bottles = {
	{ f = "ground", p = { -6, 20 } },
	{ f = "ground", p = { -40, 24 } },
	{ f = "ground", p = { -24, -6 } },
	{ f = "ground", p = { 26, 22 } },
	{ f = "ground", p = { 52, -10 } },
	{ f = "ground", p = { 10, -12 } },
	{ f = "ground", p = { 22, -40 } },
	{ f = "second", p = { -24, 20 } },
	{ f = "second", p = { -48, -14 } },
	{ f = "second", p = { -30, -36 } },
	{ f = "second", p = { 40, 36 } },
	{ f = "second", p = { 24, -20 } },
	{ f = "basement", p = { -12, -30 } },
	{ f = "basement", p = { 12, 24 } },
	{ f = "basement", p = { 44, 8 } },
}

--- Fuse boxes for the safe-zone objective, one beside each safe zone.
HouseData.FuseBoxes = {
	{ f = "ground", p = { -56, -22 } },
	{ f = "attic", p = { 24, 0 } },
	{ f = "basement", p = { -38, 20 } },
}

--==========================================================================
-- Spawns
--==========================================================================
HouseData.PlayerSpawns = {
	f = "ground",
	pts = { { -8, 40 }, { 0, 40 }, { 8, 40 }, { -8, 32 }, { 0, 32 }, { 8, 32 } },
}

HouseData.KillerSpawns = {
	{ f = "ground", p = { 46, 36 }, who = "Bob / Barbara" },
	{ f = "second", p = { 0, -38 }, who = "Robert / Baby" },
	{ f = "basement", p = { 26, -30 }, who = "Billy" },
}

--- Where Robby and Benny can appear.
HouseData.HelperSpawns = {
	{ f = "ground", p = { -30, 28 } },
	{ f = "ground", p = { 30, -30 } },
	{ f = "ground", p = { 0, -10 } },
	{ f = "second", p = { -36, 20 } },
	{ f = "second", p = { 36, -20 } },
	{ f = "basement", p = { -16, 10 } },
	{ f = "attic", p = { 12, 8 } },
}

--==========================================================================
-- Patrol routes
--==========================================================================
--[[
	Designed routes, one per killer -- these replace the zone-guessing the
	greybox used. Each is a closed loop walked in order.

	The mockup's fifth route is labelled "bobby"; per docs/DESIGN_DECISIONS.md
	that character is merged into Baby, so the route is assigned to her.
]]
HouseData.Routes = {
	{
		killer = "Bob",
		f = "ground",
		pts = { { 0, 40 }, { 0, 20 }, { -13, 14 }, { -40, 26 }, { -40, 40 }, { 0, 40 }, { 30, 30 }, { 46, 20 }, { 40, 0 }, { 10, -12 }, { 0, -30 }, { 0, 20 } },
	},
	{
		killer = "Barbara",
		f = "ground",
		pts = { { 44, 0 }, { 30, -8 }, { 46, -20 }, { 26, -38 }, { 22, -20 }, { 44, 24 }, { 30, 40 }, { 0, 34 }, { -30, 38 }, { -40, 20 }, { -20, 10 }, { 44, 0 } },
	},
	{
		killer = "Billy",
		f = "basement",
		pts = { { 26, -30 }, { 10, -20 }, { 10, 20 }, { 40, 24 }, { 46, 8 }, { 26, -6 }, { -10, -10 }, { -30, -26 }, { -34, 20 }, { -8, 24 }, { 10, 10 } },
	},
	{
		killer = "Robert",
		f = "second",
		pts = { { 30, -34 }, { 44, -20 }, { 24, -12 }, { 0, -20 }, { 0, 20 }, { -30, 30 }, { -50, 20 }, { -44, -10 }, { -24, -30 }, { 0, -38 }, { 30, -34 } },
	},
	{
		killer = "Baby",
		f = "second",
		pts = { { 0, 30 }, { 22, 8 }, { 46, -6 }, { 24, -30 }, { 0, -38 }, { -24, -30 }, { -44, -4 }, { -40, 30 }, { -20, 38 }, { 0, 30 } },
	},
}

--==========================================================================
-- Lookups
--==========================================================================

--- World position for a {x, z} pair on a named floor.
function HouseData.toWorld(floor: string, p: { number }, yOffset: number?): Vector3
	local y = HouseData.FloorY[floor] or 0
	return Vector3.new(p[1], y + (yOffset or 0), p[2])
end

--- The room containing a point on a floor, or nil.
function HouseData.roomAt(floor: string, x: number, z: number): Room?
	for _, room in HouseData.Rooms do
		if room.f == floor and x >= room.x0 and x <= room.x1 and z >= room.z0 and z <= room.z1 then
			return room
		end
	end
	return nil
end

--- Zone name for a point, used to tag patrol nodes and props.
function HouseData.zoneAt(floor: string, x: number, z: number): string
	local room = HouseData.roomAt(floor, x, z)
	return room and room.zone or "Hallway"
end

function HouseData.roomsOn(floor: string): { Room }
	local out = {}
	for _, room in HouseData.Rooms do
		if room.f == floor then
			table.insert(out, room)
		end
	end
	return out
end

return HouseData
