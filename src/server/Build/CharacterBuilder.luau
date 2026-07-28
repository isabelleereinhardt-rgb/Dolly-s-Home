--!nonstrict
--[[
	CharacterBuilder.luau
	--------------------------------------------------------------------------
	The family, built from a spec table.

	Ported from killers.js and characters.js at SILHOUETTE level, not vertex
	level. The mockups are still being tweaked, so this is deliberately
	data-driven: every character is a row in `Specs` below, and changing how one
	looks means changing numbers, not geometry code. Nobody has to re-port a
	character because their coat got longer.

	What each row controls:
	  Height     total studs (a survivor is 5, so Bob at 6.4 towers)
	  Slim       body width multiplier
	  Lean       forward hunch
	  Skin/Cloth/Accent/Eye   palette keys, below
	  Features   the signature silhouette details that make them readable at
	             distance in a dark corridor

	That last field is the important one. In a room lit by one candle you do not
	see a face -- you see an outline. So each of them carries exactly one thing
	nobody else has:

	  Bob       the wrist stump where Barbara tore his hand off
	  Barbara   that hand, still carried
	  Billy     a meat hook on a chain
	  Robert    cracked spectacles on a chain
	  Baby      the doll this house is named for
	  Robby     the family lantern, unlit
	  Benny     a hand raised mid-warning
	  Ava       a shroud that dissolves instead of feet
	  Menen     a crown of antlers
	--------------------------------------------------------------------------
]]

local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
local Palette = require(Shared.Palette)

local Primitives = require(script.Parent.Primitives)

local CharacterBuilder = {}

--==========================================================================
-- Palette, from killers.js `M` and characters.js `CM`
--==========================================================================
local function style(colour: Color3, material: Enum.Material, transparency: number?, glow: number?, range: number?)
	return {
		Colour = colour,
		Material = material,
		Transparency = transparency,
		Glow = glow,
		GlowRange = range,
	}
end

CharacterBuilder.Palette = {
	-- Flesh
	flesh = style(Color3.fromRGB(138, 128, 120), Enum.Material.SmoothPlastic),
	fleshWarm = style(Color3.fromRGB(149, 135, 119), Enum.Material.SmoothPlastic),
	fleshCold = style(Color3.fromRGB(125, 122, 119), Enum.Material.SmoothPlastic),
	bruise = style(Color3.fromRGB(88, 74, 82), Enum.Material.SmoothPlastic),
	hollow = style(Color3.fromRGB(78, 72, 67), Enum.Material.SmoothPlastic),

	-- Dark
	shade = style(Color3.fromRGB(22, 21, 19), Enum.Material.SmoothPlastic),
	shadeLift = style(Color3.fromRGB(39, 37, 33), Enum.Material.SmoothPlastic),
	maw = style(Color3.fromRGB(8, 7, 10), Enum.Material.SmoothPlastic),

	-- Detail
	teeth = style(Color3.fromRGB(214, 207, 188), Enum.Material.SmoothPlastic),
	nail = style(Color3.fromRGB(90, 81, 72), Enum.Material.SmoothPlastic),
	gum = style(Color3.fromRGB(77, 36, 39), Enum.Material.SmoothPlastic),
	blood = style(Color3.fromRGB(102, 21, 26), Enum.Material.SmoothPlastic),
	bloodWet = style(Color3.fromRGB(141, 28, 24), Enum.Material.Glass, 0.15),
	metal = style(Color3.fromRGB(143, 138, 125), Enum.Material.Metal),
	brass = style(Color3.fromRGB(181, 154, 88), Enum.Material.Metal),

	-- Eyes. The brightest thing on any of them, by design.
	eye = style(Color3.fromRGB(255, 246, 226), Enum.Material.Neon, nil, 1.1, 11),
	eyeEmber = style(Color3.fromRGB(216, 50, 28), Enum.Material.Neon, nil, 1.3, 13),
	eyeGold = style(Color3.fromRGB(242, 217, 138), Enum.Material.Neon, nil, 1.0, 12),
	eyeGhost = style(Color3.fromRGB(159, 212, 255), Enum.Material.Neon, nil, 1.2, 14),

	-- Cloth
	suit = style(Color3.fromRGB(43, 39, 36), Enum.Material.Fabric),
	suitWorn = style(Color3.fromRGB(59, 53, 47), Enum.Material.Fabric),
	dress = style(Color3.fromRGB(171, 91, 41), Enum.Material.Fabric),
	dressFade = style(Color3.fromRGB(201, 138, 79), Enum.Material.Fabric),
	grime = style(Color3.fromRGB(138, 92, 49), Enum.Material.Fabric),
	shorts = style(Color3.fromRGB(187, 104, 54), Enum.Material.Fabric),
	linen = style(Color3.fromRGB(168, 158, 138), Enum.Material.Fabric),
	hairPale = style(Color3.fromRGB(199, 188, 164), Enum.Material.Fabric),
	hairDark = style(Color3.fromRGB(30, 25, 22), Enum.Material.Fabric),

	-- Helpers and spirits
	helper = style(Color3.fromRGB(154, 162, 160), Enum.Material.ForceField, 0.22),
	helperCloth = style(Color3.fromRGB(107, 99, 83), Enum.Material.Fabric, 0.28),
	gold = style(Color3.fromRGB(242, 217, 138), Enum.Material.Neon, 0.38, 1.4, 16),
	ava = style(Color3.fromRGB(188, 201, 204), Enum.Material.ForceField, 0.5),
	avaCloth = style(Color3.fromRGB(214, 216, 208), Enum.Material.ForceField, 0.58),
	void_ = style(Color3.fromRGB(11, 10, 13), Enum.Material.SmoothPlastic),
	ember = style(Color3.fromRGB(216, 50, 28), Enum.Material.Neon, nil, 1.6, 18),
	bone = style(Color3.fromRGB(214, 207, 188), Enum.Material.SmoothPlastic),
}

local P = CharacterBuilder.Palette

--==========================================================================
-- Specs
--==========================================================================
CharacterBuilder.Specs = {
	Bob = {
		Height = 6.4, -- tallest of them; he looms
		Slim = 0.98,
		Lean = 0.08,
		Skin = "fleshCold",
		Cloth = "suit",
		Accent = "suitWorn",
		Hair = "hairDark",
		Eye = "eye",
		Features = { "stump", "frockcoat", "cravat", "watchchain" },
	},
	Barbara = {
		Height = 5.9,
		Slim = 0.9,
		Lean = 0.02,
		Skin = "flesh",
		Cloth = "dress",
		Accent = "dressFade",
		Hair = "hairDark",
		Eye = "eye",
		Features = { "skirt", "laceCollar", "bloodBib", "trophyHand" },
	},
	Billy = {
		Height = 5.6,
		Slim = 0.86,
		Lean = 0.05,
		Skin = "fleshWarm",
		Cloth = "shorts",
		Accent = "grime",
		Hair = "hairPale",
		Eye = "eye",
		Features = { "ropeBelt", "meatHook", "dirt" },
	},
	Robert = {
		Height = 5.8,
		Slim = 0.92,
		Lean = -0.02, -- upright; pride is all he has left
		Skin = "fleshCold",
		Cloth = "shade",
		Accent = "shadeLift",
		Hair = "hairDark",
		Eye = "eye",
		Features = { "cassock", "highCollar", "spectacles" },
	},
	Baby = {
		Height = 3.3,
		Slim = 1.15, -- squat and wrong
		Lean = 0.45, -- hauls itself along on its arms
		Crawler = true,
		Skin = "flesh",
		Cloth = "linen",
		Accent = "linen",
		Hair = "hairPale",
		Eye = "eye",
		Features = { "ribCage", "nightshirt", "doll", "maw" },
	},

	-- Helpers and story NPCs -------------------------------------------------
	Robby = {
		Height = 5.4,
		Slim = 0.94,
		Lean = 0.04,
		Ghostly = true,
		Skin = "helper",
		Cloth = "helperCloth",
		Accent = "helperCloth",
		Hair = "helperCloth",
		Eye = "eyeGold",
		Features = { "lantern", "aura" },
	},
	Benny = {
		Height = 4.9,
		Slim = 0.88,
		Lean = -0.03,
		Ghostly = true,
		Skin = "helper",
		Cloth = "helperCloth",
		Accent = "helperCloth",
		Hair = "helperCloth",
		Eye = "eyeGold",
		Features = { "raisedHand", "aura" },
	},
	Ava = {
		Height = 5.2,
		Slim = 0.86,
		Lean = 0,
		Ghostly = true,
		Float = 0.35,
		NoFeet = true,
		Skin = "ava",
		Cloth = "avaCloth",
		Accent = "avaCloth",
		Hair = "ava",
		Eye = "eyeGhost",
		Features = { "shroud", "veil", "aura" },
	},
	--[[
		Robert wearing his brother's face.

		Identical to Robby in every respect except the eyes, which burn red
		instead of gold. That one difference is the entire mechanic: a player
		who runs to a helper without looking gets nothing, and a player who
		learns to check gets a moment of real dread every time one appears.
	]]
	RobbyImposter = {
		Height = 5.4,
		Slim = 0.94,
		Lean = 0.04,
		Ghostly = true,
		Skin = "helper",
		Cloth = "helperCloth",
		Accent = "helperCloth",
		Hair = "helperCloth",
		Eye = "eyeEmber",
		Features = { "lantern", "aura" },
	},

	Menen = {
		Height = 8.4, -- towers over everything
		Slim = 0.78,
		Lean = 0.02,
		Float = 0.6,
		NoFeet = true,
		Skin = "void_",
		Cloth = "void_",
		Accent = "shadeLift",
		Hair = "void_",
		Eye = "eyeEmber",
		Features = { "robe", "mask", "antlers" },
	},
}

--==========================================================================
-- Shared body
--==========================================================================

local function capsule(model, name, styleKey, a: Vector3, b: Vector3, radius: number)
	return Primitives.capsule(name, P[styleKey] or styleKey, a, b, radius, model)
end

local function ball(model, name, styleKey, position: Vector3, radius: number, scale: Vector3?)
	return Primitives.sph(name, P[styleKey] or styleKey, position, radius, scale, model)
end

local function slab(model, name, styleKey, position: Vector3, size: Vector3, rotY: number?)
	return Primitives.part(name, P[styleKey] or styleKey, position, size, rotY, model)
end

--[[
	The proportional humanoid from characters.js, ported.

	Everything is driven off total height, so a 3.3-stud crawler and an 8.4-stud
	demon come out of the same function with the same proportions.
]]
local function buildBody(model: Model, spec)
	local h = spec.Height
	local slim = spec.Slim or 1
	local lean = spec.Lean or 0
	local float = spec.Float or 0

	local hipY = h * 0.50 + float
	local chestY = h * 0.68 + float
	local shY = h * 0.78 + float
	local w = h * 0.105 * slim

	-- Lean tips the upper body forward over the hips.
	local function z(y: number): number
		return (y - hipY) * lean
	end

	local skin = spec.Skin

	-- Torso ----------------------------------------------------------------
	capsule(model, "chest", skin, Vector3.new(0, shY, z(shY)), Vector3.new(0, chestY - h * 0.06, z(chestY)), w * 1.3)
	capsule(model, "abdomen", skin, Vector3.new(0, chestY - h * 0.05, z(chestY)), Vector3.new(0, hipY, z(hipY)), w * 1.08)
	capsule(model, "pelvis", skin, Vector3.new(0, hipY + h * 0.01, z(hipY)), Vector3.new(0, hipY - h * 0.05, z(hipY)), w * 1.15)
	capsule(model, "shoulders", skin, Vector3.new(-w * 1.5, shY, z(shY)), Vector3.new(w * 1.5, shY, z(shY)), w * 0.55)

	-- Cloth yoke over the shoulders.
	if spec.Cloth then
		capsule(model, "cloth_yoke", spec.Cloth, Vector3.new(-w * 1.62, shY + w * 0.06, z(shY)), Vector3.new(w * 1.62, shY + w * 0.06, z(shY)), w * 0.68)
	end

	-- Head ------------------------------------------------------------------
	local r = h * 0.115
	local headY = h - r * 1.12 + float
	local headZ = z(h * 0.90)

	capsule(model, "neck", skin, Vector3.new(0, headY - r * 1.5, headZ), Vector3.new(0, headY - r * 0.4, headZ + r * 0.1), r * 0.42)
	ball(model, "Head", skin, Vector3.new(0, headY, headZ), r, Vector3.new(0.88, 1.06, 1.0))
	ball(model, "jaw", skin, Vector3.new(0, headY - r * 0.55, headZ + r * 0.28), r * 0.6, Vector3.new(0.9, 0.62, 0.9))
	capsule(model, "brow", skin, Vector3.new(-r * 0.55, headY + r * 0.22, headZ + r * 0.6), Vector3.new(r * 0.55, headY + r * 0.22, headZ + r * 0.6), r * 0.16)

	for _, side in { -1, 1 } do
		local eye = ball(model, "Eye", spec.Eye, Vector3.new(side * r * 0.38, headY + r * 0.02, headZ + r * 0.78), r * 0.16, Vector3.new(1, 1, 0.6))
		eye.CanCollide = false
		ball(model, "ear", skin, Vector3.new(side * r * 0.9, headY - r * 0.05, headZ), r * 0.2, Vector3.new(0.35, 0.9, 0.7))
	end

	if spec.Hair then
		ball(model, "hair", spec.Hair, Vector3.new(0, headY + r * 0.34, headZ - r * 0.06), r * 1.02, Vector3.new(0.94, 0.78, 1.0))
	end

	-- Arms -------------------------------------------------------------------
	local wrists = {}
	for _, side in { -1, 1 } do
		local key = side < 0 and "L" or "R"
		local shoulder = Vector3.new(side * w * 1.55, shY - h * 0.02, z(shY))

		local elbow, wrist
		if spec.Crawler then
			-- Planted forward, taking the body's weight.
			elbow = Vector3.new(side * w * 2.0, hipY * 0.7, z(shY) + h * 0.22)
			wrist = Vector3.new(side * w * 2.1, h * 0.05 + float, z(shY) + h * 0.42)
		else
			elbow = Vector3.new(side * (w * 1.55 + h * 0.06), shY - h * 0.16, z(shY) + h * 0.02)
			wrist = Vector3.new(elbow.X + side * h * 0.02, elbow.Y - h * 0.18, elbow.Z + h * 0.05)
		end

		capsule(model, `upper_arm_{key}`, skin, shoulder, elbow, w * 0.5)
		capsule(model, `forearm_{key}`, skin, elbow, wrist, w * 0.4)

		-- Bob's right hand is missing; his stump is built as a feature instead.
		if not (spec.Features and table.find(spec.Features, "stump") and side > 0) then
			ball(model, `hand_{key}`, skin, wrist, w * 0.42, Vector3.new(1, 0.8, 1.1))
		end
		wrists[key] = wrist
	end

	-- Legs ---------------------------------------------------------------------
	if not spec.NoFeet then
		for _, side in { -1, 1 } do
			local key = side < 0 and "L" or "R"
			local hip = Vector3.new(side * w * 0.78, hipY - h * 0.04, z(hipY))

			local knee, ankle
			if spec.Crawler then
				-- Curled and useless; they never grew.
				knee = Vector3.new(side * w * 0.9, h * 0.20 + float, z(hipY) - h * 0.20)
				ankle = Vector3.new(side * w * 0.75, h * 0.06 + float, z(hipY) - h * 0.10)
			else
				knee = Vector3.new(side * w * 0.82, h * 0.27 + float, 0)
				ankle = Vector3.new(side * w * 0.85, h * 0.045 + float, 0)
			end

			capsule(model, `thigh_{key}`, skin, hip, knee, w * 0.7)
			capsule(model, `shin_{key}`, skin, knee, ankle, w * 0.48)
			local foot = slab(model, `foot_{key}`, spec.Accent or skin, ankle + Vector3.new(0, -h * 0.01, h * 0.05), Vector3.new(w * 1.05, h * 0.06, h * 0.2))
			foot.CanCollide = false
		end
	end

	return {
		h = h,
		w = w,
		hipY = hipY,
		shY = shY,
		headY = headY,
		headR = r,
		float = float,
		wrists = wrists,
	}
end

--==========================================================================
-- Signature features
--==========================================================================

local FEATURES = {}

--- Bob: the wrist Barbara tore his hand off at.
function FEATURES.stump(model, spec, J)
	local wrist = J.wrists.R
	ball(model, "wrist_stump", "hollow", wrist, J.w * 0.38)
	ball(model, "stump_bone", "teeth", wrist + Vector3.new(0, -J.w * 0.2, 0), J.w * 0.16)
	for index = 1, 3 do
		local drip = ball(model, "blood_run", "blood", wrist + Vector3.new(0, -J.w * (0.4 + index * 0.35), 0), J.w * 0.1)
		drip.CanCollide = false
	end
end

--- Bob: the frock coat, tattered at the hem.
function FEATURES.frockcoat(model, spec, J)
	Primitives.lathe("frock_coat", P[spec.Cloth], {
		{ J.w * 1.5, J.shY - J.h * 0.06 },
		{ J.w * 1.7, J.hipY },
		{ J.w * 1.85, J.hipY - J.h * 0.16 },
	}, Vector3.zero, model)
	for index = 0, 7 do
		local angle = index / 8 * math.pi * 2
		local tatter = slab(model, "coat_tatter", spec.Cloth, Vector3.new(math.cos(angle) * J.w * 1.8, J.hipY - J.h * 0.22, math.sin(angle) * J.w * 1.8), Vector3.new(J.w * 0.5, J.h * 0.12, 0.12))
		tatter.CanCollide = false
	end
end

function FEATURES.cravat(model, spec, J)
	slab(model, "cravat", "linen", Vector3.new(0, J.headY - J.headR * 1.7, J.w * 0.9), Vector3.new(J.w * 1.1, J.h * 0.06, J.w * 0.5)).CanCollide = false
end

function FEATURES.watchchain(model, spec, J)
	for index = 0, 4 do
		local link = ball(model, "watch_chain", "brass", Vector3.new(-J.w * 0.9 + index * J.w * 0.28, J.hipY + J.h * 0.09 - index * J.h * 0.012, J.w * 1.05), 0.05)
		link.CanCollide = false
	end
	ball(model, "pocket_watch", "brass", Vector3.new(J.w * 0.35, J.hipY + J.h * 0.05, J.w * 1.05), 0.13).CanCollide = false
end

--- Barbara: the long rust skirt.
function FEATURES.skirt(model, spec, J)
	Primitives.lathe("dress_skirt", P[spec.Cloth], {
		{ J.w * 1.2, J.hipY + J.h * 0.02 },
		{ J.w * 1.9, J.hipY - J.h * 0.18 },
		{ J.w * 2.3, J.hipY - J.h * 0.38 },
	}, Vector3.zero, model)
	for index = 0, 9 do
		local angle = index / 10 * math.pi * 2
		local tatter = slab(model, "skirt_tatter", spec.Accent, Vector3.new(math.cos(angle) * J.w * 2.25, J.hipY - J.h * 0.44, math.sin(angle) * J.w * 2.25), Vector3.new(J.w * 0.45, J.h * 0.1, 0.1))
		tatter.CanCollide = false
	end
end

function FEATURES.laceCollar(model, spec, J)
	Primitives.cyl("lace_collar", P.linen, Vector3.new(0, J.headY - J.headR * 1.55, J.headR * 0.1), J.w * 1.1, 0.22, 0, model).CanCollide = false
	ball(model, "cameo_brooch", "bone", Vector3.new(0, J.headY - J.headR * 1.75, J.w * 0.95), 0.13).CanCollide = false
end

--- Barbara: she has not washed since.
function FEATURES.bloodBib(model, spec, J)
	slab(model, "blood_bib", "blood", Vector3.new(0, J.shY - J.h * 0.09, J.w * 1.15), Vector3.new(J.w * 1.5, J.h * 0.14, 0.1)).CanCollide = false
	ball(model, "blood_drip_chin", "bloodWet", Vector3.new(0, J.headY - J.headR * 0.95, J.headR * 0.7), 0.09).CanCollide = false
end

--- Barbara: she is still carrying Bob's hand.
function FEATURES.trophyHand(model, spec, J)
	local hold = J.wrists.L + Vector3.new(0, -J.h * 0.06, 0)
	ball(model, "trophy_hand_palm", "hollow", hold, J.w * 0.36, Vector3.new(1, 0.7, 1.2))
	for index = 0, 3 do
		local finger = capsule(model, "trophy_finger", "hollow", hold + Vector3.new((index - 1.5) * J.w * 0.18, -J.w * 0.15, J.w * 0.2), hold + Vector3.new((index - 1.5) * J.w * 0.2, -J.w * 0.5, J.w * 0.35), J.w * 0.08)
		for _, part in finger do
			part.CanCollide = false
		end
	end
	ball(model, "trophy_sinew", "bloodWet", hold + Vector3.new(0, J.w * 0.3, 0), J.w * 0.14).CanCollide = false
end

function FEATURES.ropeBelt(model, spec, J)
	Primitives.cyl("rope_belt", P.linen, Vector3.new(0, J.hipY + J.h * 0.02, 0), J.w * 1.25, 0.18, 0, model).CanCollide = false
end

--- Billy: a meat hook on a length of chain.
function FEATURES.meatHook(model, spec, J)
	local grip = J.wrists.R
	for index = 0, 5 do
		local link = ball(model, "chain_link", "metal", grip + Vector3.new(0, -index * J.h * 0.045, 0), 0.07)
		link.CanCollide = false
	end
	local hookBase = grip + Vector3.new(0, -J.h * 0.28, 0)
	capsule(model, "meat_hook", "metal", hookBase, hookBase + Vector3.new(0, -J.h * 0.1, 0), 0.08)
	Primitives.cone("hook_point", P.metal, hookBase + Vector3.new(0, -J.h * 0.1, 0), hookBase + Vector3.new(J.w * 0.4, -J.h * 0.16, 0), 0.08, 3, model)
	ball(model, "hook_blood", "bloodWet", hookBase + Vector3.new(J.w * 0.2, -J.h * 0.14, 0), 0.07).CanCollide = false
end

function FEATURES.dirt(model, spec, J)
	for index = 0, 4 do
		local smear = slab(model, "dirt_smear", "grime", Vector3.new((index % 2 == 0 and -1 or 1) * J.w * 0.8, J.hipY + index * J.h * 0.05, J.w * 0.95), Vector3.new(J.w * 0.5, J.h * 0.035, 0.06))
		smear.CanCollide = false
	end
end

--- Robert: the cassock.
function FEATURES.cassock(model, spec, J)
	Primitives.lathe("cassock", P[spec.Cloth], {
		{ J.w * 1.35, J.shY - J.h * 0.04 },
		{ J.w * 1.6, J.hipY },
		{ J.w * 1.75, J.hipY - J.h * 0.34 },
	}, Vector3.zero, model)
	for _, side in { -1, 1 } do
		slab(model, "stole", spec.Accent, Vector3.new(side * J.w * 0.55, J.shY - J.h * 0.13, J.w * 1.1), Vector3.new(J.w * 0.32, J.h * 0.26, 0.09)).CanCollide = false
	end
end

function FEATURES.highCollar(model, spec, J)
	Primitives.cyl("high_collar", P[spec.Accent], Vector3.new(0, J.headY - J.headR * 1.35, 0), J.w * 0.95, J.h * 0.05, 0, model).CanCollide = false
end

--- Robert: cracked spectacles, hanging off his face on a chain.
function FEATURES.spectacles(model, spec, J)
	local front = J.headR * 0.85
	for _, side in { -1, 1 } do
		local rim = Primitives.cyl("spectacle_rim", P.brass, Vector3.new(side * J.headR * 0.38, J.headY + J.headR * 0.02, front), J.headR * 0.26, 0.05, 0, model)
		rim.CFrame = CFrame.new(side * J.headR * 0.38, J.headY + J.headR * 0.02, front) * CFrame.Angles(math.pi / 2, 0, 0)
		rim.CanCollide = false
		local glass = Primitives.cyl("spectacle_glass", P.bone, Vector3.new(side * J.headR * 0.38, J.headY + J.headR * 0.02, front - 0.01), J.headR * 0.22, 0.02, 0, model)
		glass.CFrame = rim.CFrame
		glass.Transparency = 0.6
		glass.CanCollide = false
	end
	slab(model, "spectacle_bridge", "brass", Vector3.new(0, J.headY + J.headR * 0.02, front), Vector3.new(J.headR * 0.3, 0.04, 0.04)).CanCollide = false
end

--- Baby: ribs showing through.
function FEATURES.ribCage(model, spec, J)
	for index = 0, 4 do
		local rib = capsule(model, "rib", "teeth", Vector3.new(-J.w * 0.9, J.shY - index * J.h * 0.05, J.w * 0.5), Vector3.new(J.w * 0.9, J.shY - index * J.h * 0.05, J.w * 0.5), 0.05)
		for _, part in rib do
			part.CanCollide = false
		end
	end
end

function FEATURES.nightshirt(model, spec, J)
	Primitives.lathe("nightshirt", P[spec.Cloth], {
		{ J.w * 1.3, J.shY - J.h * 0.05 },
		{ J.w * 1.5, J.hipY },
		{ J.w * 1.5, J.hipY - J.h * 0.18 },
	}, Vector3.zero, model)
end

--- Baby: the doll this house is named for.
function FEATURES.doll(model, spec, J)
	local hold = J.wrists.L + Vector3.new(0, J.h * 0.05, 0)
	slab(model, "dolly_doll", "linen", hold, Vector3.new(J.w * 0.7, J.h * 0.2, J.w * 0.4)).CanCollide = false
	ball(model, "doll_head", "linen", hold + Vector3.new(0, J.h * 0.14, 0), J.w * 0.32).CanCollide = false
	ball(model, "doll_hair", "hairDark", hold + Vector3.new(0, J.h * 0.17, -0.04), J.w * 0.3, Vector3.new(1, 0.7, 1)).CanCollide = false
	for _, side in { -1, 1 } do
		ball(model, "doll_eye", "shade", hold + Vector3.new(side * J.w * 0.12, J.h * 0.15, J.w * 0.26), 0.045).CanCollide = false
	end
end

function FEATURES.maw(model, spec, J)
	ball(model, "maw", "gum", Vector3.new(0, J.headY - J.headR * 0.55, J.headR * 0.72), J.headR * 0.36, Vector3.new(1.1, 0.9, 0.6)).CanCollide = false
	for index = 0, 5 do
		local x = (index / 5 - 0.5) * J.headR * 0.62
		Primitives.cone("tooth", P.teeth, Vector3.new(x, J.headY - J.headR * 0.28, J.headR * 0.8), Vector3.new(x, J.headY - J.headR * 0.62, J.headR * 0.78), 0.05, 3, model)
	end
end

--- Robby: the family lantern, unlit.
function FEATURES.lantern(model, spec, J)
	local hold = J.wrists.R + Vector3.new(0, -J.h * 0.05, 0)
	Primitives.cyl("lantern_base", P[spec.Cloth], hold, 0.22, 0.14, 0, model).CanCollide = false
	local glass = Primitives.cyl("lantern_glass", P.gold, hold + Vector3.new(0, 0.3, 0), 0.19, 0.5, 0, model)
	glass.CanCollide = false
	Primitives.cyl("lantern_cap", P[spec.Cloth], hold + Vector3.new(0, 0.62, 0), 0.22, 0.14, 0, model).CanCollide = false
end

--- Benny: hand up, mid-warning.
function FEATURES.raisedHand(model, spec, J)
	local hold = J.wrists.L + Vector3.new(0, J.h * 0.22, J.w * 0.3)
	ball(model, "warning_glow", "gold", hold, 0.24).CanCollide = false
	for index = 0, 2 do
		ball(model, "whisper", "gold", hold + Vector3.new(-0.1 - index * 0.16, 0.28 + index * 0.24, index * 0.08), 0.09 - index * 0.02).CanCollide = false
	end
end

--- Ava: a shroud that dissolves into mist instead of feet.
function FEATURES.shroud(model, spec, J)
	Primitives.lathe("shroud", P[spec.Cloth], {
		{ J.w * 1.1, J.shY - J.h * 0.05 },
		{ J.w * 1.6, J.hipY },
		{ J.w * 2.1, J.hipY - J.h * 0.3 },
		{ J.w * 2.4, J.float },
	}, Vector3.zero, model)
	for index = 0, 11 do
		local angle = index / 12 * math.pi * 2
		local wisp = capsule(model, "shroud_wisp", spec.Cloth, Vector3.new(math.cos(angle) * J.w * 2.2, J.float + 0.4, math.sin(angle) * J.w * 2.2), Vector3.new(math.cos(angle) * J.w * 2.5, 0.05, math.sin(angle) * J.w * 2.5), 0.07)
		for _, part in wisp do
			part.CanCollide = false
		end
	end
end

function FEATURES.veil(model, spec, J)
	Primitives.lathe("veil", P[spec.Cloth], {
		{ J.headR * 0.6, J.headY + J.headR },
		{ J.headR * 1.1, J.headY - J.headR * 1.4 },
	}, Vector3.zero, model)
end

--- Menen: a robe of nothing, hemmed in embers.
function FEATURES.robe(model, spec, J)
	Primitives.lathe("robe", P.void_, {
		{ J.w * 1.4, J.shY },
		{ J.w * 2.0, J.hipY },
		{ J.w * 2.8, J.hipY - J.h * 0.3 },
		{ J.w * 3.4, J.float },
	}, Vector3.zero, model)
	for index = 0, 11 do
		local angle = index / 12 * math.pi * 2
		if index % 2 == 0 then
			ball(model, "hem_ember", "ember", Vector3.new(math.cos(angle) * J.w * 3.4, J.float + 0.1, math.sin(angle) * J.w * 3.4), 0.09).CanCollide = false
		end
	end
end

--- Menen: a smooth bone face with no mouth.
function FEATURES.mask(model, spec, J)
	ball(model, "mask", "bone", Vector3.new(0, J.headY, J.headR * 0.5), J.headR * 0.95, Vector3.new(0.86, 1.08, 0.5)).CanCollide = false
	for _, side in { -1, 1 } do
		ball(model, "mask_socket", "void_", Vector3.new(side * J.headR * 0.34, J.headY + J.headR * 0.08, J.headR * 0.95), J.headR * 0.22, Vector3.new(1.2, 0.85, 0.5)).CanCollide = false
	end
end

--- Menen: three tines a side.
function FEATURES.antlers(model, spec, J)
	for _, side in { -1, 1 } do
		local base = Vector3.new(side * J.headR * 0.6, J.headY + J.headR * 0.6, -J.headR * 0.1)
		for tine = 0, 2 do
			local tip = base + Vector3.new(side * (0.22 + tine * 0.14) * J.h * 0.12, (0.5 - tine * 0.06) * J.h * 0.1, (-0.12 - tine * 0.1) * J.h * 0.1)
			local horn = capsule(model, "antler", "bone", base, tip, 0.09 - tine * 0.02)
			for _, part in horn do
				part.CanCollide = false
			end
			base = tip
		end
	end
end

--- Robby, Benny, Ava: they are lit from within.
function FEATURES.aura(model, spec, J)
	local disc = Primitives.disc("aura_ground", P.gold, Vector3.new(0, 0.08, 0), J.h * 0.3, 0.15, model)
	disc.Transparency = 0.75
	disc.CanCollide = false
end

--==========================================================================
-- Build
--==========================================================================

--[[
	Builds a character. Returns a Model ready for Humanoid:MoveTo -- a
	HumanoidRootPart set as PrimaryPart, everything else welded to it, and a
	HipHeight matching the rig's proportions.
]]
function CharacterBuilder.build(id: string): Model?
	local spec = CharacterBuilder.Specs[id]
	if not spec then
		return nil
	end

	local model = Instance.new("Model")
	model.Name = id

	-- The root is invisible and does the colliding; everything visible welds to
	-- it. That keeps physics to one simple box no matter how detailed the rig.
	local root = Instance.new("Part")
	root.Name = "HumanoidRootPart"
	root.Size = Vector3.new(spec.Height * 0.28, spec.Height * 0.34, spec.Height * 0.2)
	root.Transparency = 1
	root.CanCollide = true
	root.Anchored = true -- unanchored below, once everything is welded
	root.CFrame = CFrame.new(0, spec.Height * 0.62 + (spec.Float or 0), 0)
	root.Parent = model
	model.PrimaryPart = root

	local joints = buildBody(model, spec)

	for _, feature in spec.Features or {} do
		local builder = FEATURES[feature]
		if builder then
			local ok, err = pcall(builder, model, spec, joints)
			if not ok then
				warn(`[CharacterBuilder] {id} feature "{feature}" failed: {err}`)
			end
		end
	end

	-- Weld every decorative part to the root, then let physics take over.
	for _, part in model:GetChildren() do
		if part:IsA("BasePart") and part ~= root then
			part.Anchored = false
			part.CanCollide = false
			part.Massless = true
			part.CanQuery = false
			local weld = Instance.new("WeldConstraint")
			weld.Part0 = root
			weld.Part1 = part
			weld.Parent = part
		end
	end
	root.Anchored = false

	local humanoid = Instance.new("Humanoid")
	humanoid.RequiresNeck = false -- no Motor6D neck on this rig
	humanoid.BreakJointsOnDeath = false
	humanoid.AutoRotate = true
	humanoid.MaxSlopeAngle = 65
	humanoid.DisplayDistanceType = Enum.HumanoidDisplayDistanceType.None
	humanoid.NameDisplayDistance = 0
	humanoid.HealthDisplayDistance = 0
	-- The family is immortal; CombatService tracks their HP as an attribute.
	humanoid.MaxHealth = math.huge
	humanoid.Health = math.huge
	humanoid.HipHeight = spec.Height * 0.45 + (spec.Float or 0)
	humanoid.Parent = model

	return model
end

return CharacterBuilder
