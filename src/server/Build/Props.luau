--!nonstrict
--[[
	Props.luau
	--------------------------------------------------------------------------
	The hiding spots and task props, ported from props.js.

	Every builder returns a Model whose origin sits ON THE FLOOR and faces +Z,
	matching the mockup's convention, so MapBuilder can place one with a single
	PivotTo using the rotation straight out of HouseData.

	The mockup marks the interior of each hiding spot with a cyan `MAT.hide`
	volume so you can see the crawl space in the viewer. That volume is kept
	here but made invisible, and it becomes the part carrying the DH_HidingSpot
	tag -- the space you actually hide in is the thing the game tags, which is
	tidier than tagging the whole cabinet.
	--------------------------------------------------------------------------
]]

local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
local Palette = require(Shared.Palette)

local Primitives = require(script.Parent.Primitives)

local Props = {}

--==========================================================================
-- Helpers
--==========================================================================

local function model(name: string): Model
	local m = Instance.new("Model")
	m.Name = name
	return m
end

--- props.js `box(name, mat, x0,x1, y0,y1, z0,z1)`.
local function box(parent, name, style, x0, x1, y0, y1, z0, z1): BasePart
	return Primitives.box(name, style, x0, x1, y0, y1, z0, z1, parent)
end

--- The invisible interior volume. Returned so the caller can tag it.
local function void(parent, x0, x1, y0, y1, z0, z1): BasePart
	local part = Primitives.box("HideVolume", nil, x0, x1, y0, y1, z0, z1, parent)
	part.Transparency = 1
	part.CanCollide = false
	part.CanQuery = false
	return part
end

--- Marks which part of a built prop is the hide volume.
local function tagVolume(m: Model, volume: BasePart): Model
	m.PrimaryPart = volume
	m:SetAttribute("HideVolume", volume.Name)
	return m
end

--==========================================================================
-- Hiding spots
--==========================================================================

function Props.hideLocker(count: number?): Model
	local m = model("HideLocker")
	local n = count or 2
	local W, H, D, t = 4.4, 6.0, 2.6, 0.25

	local volume
	for index = 0, n - 1 do
		local x = index * (W + 0.12)
		box(m, `locker_body_{index}`, "metal", x - W / 2, x + W / 2, 0, H, -D / 2, D / 2)
		local interior = void(m, x - W / 2 + t, x + W / 2 - t, t, H - t, -D / 2 + t, D / 2)
		volume = volume or interior

		box(m, `locker_door_{index}`, "metal", x - W / 2 + 0.15, x + W / 2 - 0.15, 0.25, H - 0.25, D / 2, D / 2 + 0.18)
		-- Ventilation slats: the slit you watch the room through.
		for slat = 0, 3 do
			box(m, `locker_slat_{index}_{slat}`, "ink", x - 1.3, x + 1.3, H - 1.1 - slat * 0.45, H - 0.9 - slat * 0.45, D / 2 + 0.19, D / 2 + 0.26)
		end
		Primitives.cyl(`locker_handle_{index}`, "brass", Vector3.new(x + W / 2 - 0.6, H * 0.5, D / 2 + 0.34), 0.11, 1.1, 0, m)
		box(m, `locker_foot_{index}`, "ink", x - W / 2, x + W / 2, 0, 0.25, -D / 2, D / 2)
	end

	return tagVolume(m, volume)
end

function Props.hideBed(): Model
	local m = model("HideBed")
	local W, L, clear = 5.6, 8.6, 1.5 -- 1.5 studs of crawl space
	local top = clear + 0.35

	box(m, "bed_frame", "woodDark", -W / 2, W / 2, clear, top, -L / 2, L / 2)
	box(m, "bed_mattress", "cloth", -W / 2 + 0.2, W / 2 - 0.2, top, top + 0.7, -L / 2 + 0.2, L / 2 - 0.2)
	box(m, "bed_quilt", "clothRed", -W / 2 - 0.15, W / 2 + 0.15, top + 0.2, top + 0.65, -L / 2 + 2.4, L / 2 + 0.2)
	box(m, "bed_pillow", "cloth", -1.9, 1.9, top + 0.65, top + 1.05, -L / 2 + 0.6, -L / 2 + 2.2)
	box(m, "bed_headboard", "woodDark", -W / 2, W / 2, 0, top + 2.2, -L / 2 - 0.3, -L / 2)
	box(m, "bed_footboard", "woodDark", -W / 2, W / 2, 0, top + 0.9, L / 2, L / 2 + 0.3)

	for _, sx in { -1, 1 } do
		for _, sz in { -1, 1 } do
			Primitives.cyl(
				"bed_leg",
				"woodDark",
				Vector3.new(sx * (W / 2 - 0.35), clear / 2, sz * (L / 2 - 0.4)),
				0.24,
				clear,
				0,
				m
			)
		end
	end

	return tagVolume(m, void(m, -W / 2 + 0.4, W / 2 - 0.4, 0.1, clear - 0.05, -L / 2 + 0.5, L / 2 - 0.5))
end

function Props.hideTable(width: number?, length: number?): Model
	local m = model("HideTable")
	local W, L = width or 7, length or 13
	local clear = 2.7 -- a crouched player clears the apron
	local top = clear + 0.4

	box(m, "table_top", "woodDark", -W / 2, W / 2, clear + 0.05, top, -L / 2, L / 2)
	box(m, "table_apron", "woodDark", -W / 2 + 0.4, W / 2 - 0.4, clear - 0.3, clear + 0.05, -L / 2 + 0.4, L / 2 - 0.4)

	for _, sx in { -1, 1 } do
		for _, sz in { -1, 1 } do
			Primitives.part(
				"table_leg",
				"woodDark",
				Vector3.new(sx * (W / 2 - 0.5), (clear - 0.3) / 2, sz * (L / 2 - 0.5)),
				Vector3.new(0.5, clear - 0.3, 0.5),
				0,
				m
			)
		end
	end

	return tagVolume(m, void(m, -W / 2 + 0.6, W / 2 - 0.6, 0.1, clear - 0.35, -L / 2 + 0.6, L / 2 - 0.6))
end

function Props.hideCloset(): Model
	local m = model("HideCloset")
	local W, H, D, t = 5.0, 6.4, 2.8, 0.3

	box(m, "closet_carcass", "woodPale", -W / 2, W / 2, 0, H, -D / 2, D / 2)
	local volume = void(m, -W / 2 + t, W / 2 - t, t, H - t, -D / 2 + t, D / 2)

	box(m, "closet_door_L", "woodPale", -W / 2, -0.1, 0.2, H - 0.2, D / 2, D / 2 + 0.2)

	-- One door hangs ajar. That's the tell that tells players it's usable.
	local ajar = Primitives.part(
		"closet_door_R",
		"woodPale",
		Vector3.new(W / 4, H / 2, D / 2 + 0.1),
		Vector3.new(W / 2 - 0.1, H - 0.4, 0.2),
		0,
		m
	)
	ajar.CFrame = CFrame.new(W / 2 - 0.05, H / 2, D / 2 + 0.1)
		* CFrame.Angles(0, -0.75, 0)
		* CFrame.new(-(W / 4), 0, 0)

	Primitives.cyl("closet_knob_L", "brass", Vector3.new(-0.45, H / 2, D / 2 + 0.3), 0.16, 0.3, 0, m)
	box(m, "closet_crown", "woodPale", -W / 2 - 0.25, W / 2 + 0.25, H, H + 0.35, -D / 2 - 0.25, D / 2 + 0.25)

	return tagVolume(m, volume)
end

function Props.hideDuct(length: number?): Model
	local m = model("HideDuct")
	local len = length or 10
	local O, t = 4.0, 0.3 -- bore 3.4 square; a prone player crawls

	box(m, "duct_shell", "metal", -O / 2, O / 2, 0, O, -len / 2, len / 2)
	local volume = void(m, -O / 2 + t, O / 2 - t, t, O - t, -len / 2 - 0.1, len / 2 + 0.1)

	for index = 0, math.floor(len / 2.6) - 1 do
		local z = -len / 2 + 1.3 + index * 2.6
		box(m, `duct_rib_{index}`, "metal", -O / 2 - 0.2, O / 2 + 0.2, 0, O + 0.2, z - 0.2, z + 0.2)
	end

	box(m, "duct_grate", "metal", -O / 2, O / 2, 0, O, len / 2, len / 2 + 0.16)
	for index = 0, 5 do
		box(m, `duct_grate_slot_{index}`, "ink", -O / 2 + 0.4, O / 2 - 0.4, 0.6 + index * 0.5, 0.85 + index * 0.5, len / 2 + 0.15, len / 2 + 0.24)
	end

	return tagVolume(m, volume)
end

function Props.hideBarrel(): Model
	local m = model("HideBarrel")
	local H = 3.8 -- hogshead cask

	Primitives.lathe(
		"barrel_staves",
		"woodDark",
		{ { 1.55, 0 }, { 1.95, 0.6 }, { 2.15, 1.9 }, { 1.95, 3.2 }, { 1.55, H } },
		Vector3.zero,
		m
	)

	for _, y in { 0.6, 1.9, 3.2 } do
		local hoop = Primitives.cyl("barrel_hoop", "metal", Vector3.new(0, y, 0), y == 1.9 and 2.2 or 2.0, 0.26, 0, m)
		hoop.CanCollide = false
	end

	Primitives.cyl("barrel_lid", "woodPale", Vector3.new(0.3, H + 0.1, 0.2), 1.5, 0.18, 0, m)

	return tagVolume(m, void(m, -1.75, 1.75, H * 0.05, H * 0.95, -1.75, 1.75))
end

function Props.hideBathtub(): Model
	local m = model("HideBathtub")
	local W, L, H, t = 4.4, 7.6, 2.4, 0.35

	box(m, "tub_shell", "tile", -W / 2, W / 2, 0.5, H, -L / 2, L / 2)
	local volume = void(m, -W / 2 + t, W / 2 - t, 0.8, H + 0.1, -L / 2 + t, L / 2 - t)
	box(m, "tub_rim", "tile", -W / 2 - 0.18, W / 2 + 0.18, H, H + 0.25, -L / 2 - 0.18, L / 2 + 0.18)

	for _, sx in { -1, 1 } do
		for _, sz in { -1, 1 } do
			Primitives.cyl(
				"tub_foot",
				"brass",
				Vector3.new(sx * (W / 2 - 0.5), 0.25, sz * (L / 2 - 0.7)),
				0.24,
				0.5,
				0,
				m
			)
		end
	end

	Primitives.cyl("tub_tap", "brass", Vector3.new(0, H + 0.8, -L / 2 + 0.35), 0.14, 1.2, 0, m)

	return tagVolume(m, volume)
end

--- Dispatch by the mockup's hiding-spot type name.
Props.HideBuilders = {
	locker = Props.hideLocker,
	bed = Props.hideBed,
	table = Props.hideTable,
	closet = Props.hideCloset,
	duct = Props.hideDuct,
	barrel = Props.hideBarrel,
	bathtub = Props.hideBathtub,
}

--==========================================================================
-- Task props
--==========================================================================

function Props.grandfatherClock(): Model
	local m = model("GrandfatherClock")
	local S = 0.3 -- the mockup builds it oversized and scales down
	local H = 22 * S

	box(m, "clock_case", "woodDark", -3.6 * S, 3.6 * S, 0, H, -2.4 * S, 2.4 * S)
	box(m, "clock_plinth", "woodDark", -4.4 * S, 4.4 * S, 0, 2.4 * S, -3 * S, 3 * S)
	box(m, "clock_glass", "glass", -2.6 * S, 2.6 * S, 5 * S, H - 6.5 * S, 2.3 * S, 2.6 * S)
	Primitives.cyl("clock_pendulum_rod", "brass", Vector3.new(0, 9 * S, 2.1 * S), 0.16 * S, 8 * S, 0, m)
	box(m, "clock_hood", "woodDark", -4.3 * S, 4.3 * S, H - 6.5 * S, H, -3 * S, 3 * S)

	local face = Primitives.cyl("clock_face", "wax", Vector3.new(0, H - 3.2 * S, 2.9 * S), 2.9 * S, 0.35 * S, 0, m)
	face.CFrame = CFrame.new(0, H - 3.2 * S, 2.9 * S) * CFrame.Angles(math.pi / 2, 0, 0)

	local hour = Primitives.part("clock_hand_hour", "ink", Vector3.new(0.5 * S, H - 3.2 * S, 3.15 * S), Vector3.new(2.0 * S, 0.28 * S, 0.12 * S), 0, m)
	hour.CanCollide = false
	local minute = Primitives.part("clock_hand_minute", "ink", Vector3.new(-0.3 * S, H - 2.4 * S, 3.15 * S), Vector3.new(0.28 * S, 2.8 * S, 0.12 * S), 0, m)
	minute.CanCollide = false

	m.PrimaryPart = m:FindFirstChild("clock_case") :: BasePart
	return m
end

function Props.crossProp(): Model
	local m = model("BlessedCross")
	local S = 0.37
	box(m, "cross_upright", "cross", -0.45 * S, 0.45 * S, 0, 5.4 * S, -0.28 * S, 0.28 * S)
	box(m, "cross_arm", "cross", -1.9 * S, 1.9 * S, 3.4 * S, 4.3 * S, -0.28 * S, 0.28 * S)
	local glow = Primitives.sph("cross_glow", "cross", Vector3.new(0, 3.85 * S, 0), 0.55 * S, nil, m)
	glow.CanCollide = false
	m.PrimaryPart = m:FindFirstChild("cross_upright") :: BasePart
	return m
end

function Props.potionBottle(): Model
	local m = model("PotionBottle")
	local S = 0.28

	Primitives.lathe("potion_glass", "potion", {
		{ 1.5 * S, 0.2 * S },
		{ 1.7 * S, 1.6 * S },
		{ 1.2 * S, 3.0 * S },
		{ 0.55 * S, 3.6 * S },
		{ 0.5 * S, 4.6 * S },
		{ 0.7 * S, 4.9 * S },
	}, Vector3.zero, m)

	Primitives.cyl("potion_cork", "woodPale", Vector3.new(0, 5.2 * S, 0), 0.55 * S, 0.9 * S, 0, m)

	for _, part in m:GetChildren() do
		if part:IsA("BasePart") then
			part.CanCollide = false
		end
	end
	m.PrimaryPart = m:FindFirstChildWhichIsA("BasePart")
	return m
end

function Props.mirrorShard(seed: number?): Model
	local m = model("MirrorShard")
	local rng = Random.new(seed or 1)
	-- The mockup extrudes an irregular polygon; three overlapping slivers at
	-- angles read the same way in-engine for a fraction of the parts.
	for index = 1, 3 do
		local shard = Primitives.part(
			`mirror_glass_{index}`,
			"mirror",
			Vector3.new(rng:NextNumber(-0.2, 0.2), 0.5 + index * 0.18, rng:NextNumber(-0.2, 0.2)),
			Vector3.new(rng:NextNumber(0.5, 1.0), rng:NextNumber(0.9, 1.6), 0.07),
			rng:NextNumber(0, math.pi),
			m
		)
		shard.CanCollide = false
		shard.CFrame = shard.CFrame * CFrame.Angles(rng:NextNumber(-0.5, 0.5), 0, rng:NextNumber(-0.4, 0.4))
	end
	m.PrimaryPart = m:FindFirstChildWhichIsA("BasePart")
	return m
end

function Props.ritualTable(): Model
	local m = model("RitualTable")
	local S = 0.43
	local W, L, top = 18 * S, 10 * S, 6 * S

	box(m, "altar_slab", "stone", -W / 2, W / 2, top, top + 1.2 * S, -L / 2, L / 2)
	box(m, "altar_base", "stone", -W / 2 + 2 * S, W / 2 - 2 * S, 0, top, -L / 2 + 1.5 * S, L / 2 - 1.5 * S)

	for index = 0, 4 do
		local x = (-6 + index * 3) * S
		Primitives.cyl("altar_candle", "wax", Vector3.new(x, top + (1.2 + 1.4) * S, -2.6 * S), 0.5 * S, 2.8 * S, 0, m)
		local flame = Primitives.sph("altar_flame", "flame", Vector3.new(x, top + (1.2 + 3.1) * S, -2.6 * S), 0.42 * S, Vector3.new(1, 1.7, 1), m)
		flame.CanCollide = false
	end

	-- The four ingredient slots, each glowing in its own colour.
	for index, key in { "blood", "holy", "garlic", "dust" } do
		local x = (-6.5 + (index - 1) * 4.4) * S
		Primitives.cyl("ingredient_slot", "stone", Vector3.new(x, top + 1.4 * S, 3.4 * S), 1.1 * S, 0.4 * S, 0, m)
		local sample = Primitives.sph("ingredient_sample", Palette.Ingredient[key], Vector3.new(x, top + 2.4 * S, 3.4 * S), 1.0 * S, Vector3.new(1, 1.3, 1), m)
		sample.CanCollide = false
		sample:SetAttribute("Ingredient", Palette.IngredientId[key])
	end

	m.PrimaryPart = m:FindFirstChild("altar_slab") :: BasePart
	return m
end

--- A single ingredient sitting on its pedestal.
function Props.ingredientProp(key: string): Model
	local m = model(`Ingredient_{Palette.IngredientId[key] or key}`)
	Primitives.cyl("pedestal", "stone", Vector3.new(0, 1.5, 0), 1.3, 3, 0, m)
	local sample = Primitives.sph("sample", Palette.Ingredient[key], Vector3.new(0, 3.7, 0), 0.9, Vector3.new(1, 1.25, 1), m)
	sample.CanCollide = false
	m.PrimaryPart = m:FindFirstChild("pedestal") :: BasePart
	return m
end

function Props.fuseBox(): Model
	local m = model("FuseBox")
	box(m, "fuse_case", "metal", -1.5, 1.5, 0, 4, -0.75, 0.75)
	box(m, "fuse_door", "metal", -1.3, 1.3, 0.3, 3.7, 0.75, 0.95)
	local lamp = Primitives.sph("fuse_lamp", "safe", Vector3.new(0, 4.4, 0), 0.35, nil, m)
	lamp.CanCollide = false
	m.PrimaryPart = m:FindFirstChild("fuse_case") :: BasePart
	return m
end

return Props
