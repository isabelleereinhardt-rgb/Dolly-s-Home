--!strict
--[[
	Palette.luau
	--------------------------------------------------------------------------
	The material language, ported from the `MAT` and `INGREDIENT_MAT` tables in
	the props.js mockup.

	Three.js materials carry colour, roughness, metalness, emissive and opacity.
	Roblox has Color3 + a Material enum + Transparency, and gets "emissive" by
	using Enum.Material.Neon. So each entry here records the original intent and
	the closest Roblox expression of it:

	  Colour      -> Part.Color
	  Material    -> Part.Material   (chosen from roughness/metalness)
	  Transparency-> 1 - opacity
	  Glow        -> forces Neon, and optionally attaches a PointLight

	When you tweak a colour in the mockup, change it here and it changes
	everywhere in the game at once.
	--------------------------------------------------------------------------
]]

export type Style = {
	Colour: Color3,
	Material: Enum.Material,
	Transparency: number?,
	Glow: number?, -- PointLight brightness; nil for no light
	GlowRange: number?,
}

local Palette = {}

local function style(colour: Color3, material: Enum.Material, transparency: number?, glow: number?, range: number?): Style
	return {
		Colour = colour,
		Material = material,
		Transparency = transparency,
		Glow = glow,
		GlowRange = range,
	}
end

--==========================================================================
-- Structure
--==========================================================================
Palette.Style = {
	plaster = style(Color3.fromRGB(141, 132, 116), Enum.Material.Plaster),
	paperGrn = style(Color3.fromRGB(92, 106, 79), Enum.Material.Fabric),
	paperRust = style(Color3.fromRGB(125, 83, 64), Enum.Material.Fabric),
	woodFloor = style(Color3.fromRGB(107, 80, 58), Enum.Material.WoodPlanks),
	woodDark = style(Color3.fromRGB(63, 46, 34), Enum.Material.Wood),
	woodPale = style(Color3.fromRGB(138, 116, 88), Enum.Material.WoodPlanks),
	tile = style(Color3.fromRGB(156, 150, 138), Enum.Material.Concrete),
	stone = style(Color3.fromRGB(90, 90, 86), Enum.Material.Slate),
	brick = style(Color3.fromRGB(99, 68, 58), Enum.Material.Brick),
	shingle = style(Color3.fromRGB(65, 58, 52), Enum.Material.Slate),
	metal = style(Color3.fromRGB(126, 122, 114), Enum.Material.Metal),
	brass = style(Color3.fromRGB(181, 154, 88), Enum.Material.Metal),
	glass = style(Color3.fromRGB(185, 207, 210), Enum.Material.Glass, 0.66),
	cloth = style(Color3.fromRGB(142, 135, 120), Enum.Material.Fabric),
	clothRed = style(Color3.fromRGB(93, 34, 38), Enum.Material.Fabric),
	carpet = style(Color3.fromRGB(77, 54, 48), Enum.Material.Fabric),
	moss = style(Color3.fromRGB(111, 127, 92), Enum.Material.Grass),
	wax = style(Color3.fromRGB(216, 205, 178), Enum.Material.SmoothPlastic),
	flame = style(Color3.fromRGB(255, 217, 160), Enum.Material.Neon, nil, 2.2, 16),
	blood = style(Color3.fromRGB(102, 21, 26), Enum.Material.SmoothPlastic),

	--======================================================================
	-- Gameplay overlays. Emissive in the mockup so they read against the dim
	-- shell -- Neon here, for the same reason.
	--======================================================================
	hide = style(Color3.fromRGB(18, 48, 55), Enum.Material.SmoothPlastic, 0.58),
	hideEdge = style(Color3.fromRGB(47, 211, 232), Enum.Material.Neon, nil, 1.4, 10),
	noisy = style(Color3.fromRGB(122, 42, 16), Enum.Material.WoodPlanks, 0.28),
	safe = style(Color3.fromRGB(92, 74, 21), Enum.Material.Neon, 0.4, 1.0, 22),
	spawnP = style(Color3.fromRGB(31, 74, 42), Enum.Material.Neon, nil, 1.0, 10),
	spawnK = style(Color3.fromRGB(74, 18, 32), Enum.Material.Neon, nil, 1.1, 10),
	potion = style(Color3.fromRGB(58, 42, 106), Enum.Material.Neon, 0.15, 1.2, 14),
	mirror = style(Color3.fromRGB(207, 228, 232), Enum.Material.Glass, 0.2, 0.7, 10),
	cross = style(Color3.fromRGB(216, 196, 138), Enum.Material.Neon, nil, 0.5, 12),
	ghost = style(Color3.fromRGB(217, 201, 138), Enum.Material.ForceField, 0.5, 1.1, 16),
	ink = style(Color3.fromRGB(42, 47, 49), Enum.Material.SmoothPlastic),
	inkLift = style(Color3.fromRGB(59, 66, 69), Enum.Material.SmoothPlastic),
} :: { [string]: Style }

--==========================================================================
-- The four sealing-ritual ingredients
--==========================================================================
Palette.Ingredient = {
	blood = style(Color3.fromRGB(109, 20, 24), Enum.Material.Neon, 0.1, 0.9, 12),
	holy = style(Color3.fromRGB(207, 232, 255), Enum.Material.Neon, 0.25, 1.1, 14),
	garlic = style(Color3.fromRGB(228, 220, 196), Enum.Material.SmoothPlastic, nil, 0.3, 8),
	dust = style(Color3.fromRGB(74, 63, 122), Enum.Material.Neon, 0.15, 1.3, 14),
} :: { [string]: Style }

--- Ingredient key in the mockup -> the id ObjectiveService uses.
Palette.IngredientId = {
	blood = "BloodSample",
	holy = "HolyWater",
	garlic = "Garlic",
	dust = "MagicDust",
}

--==========================================================================
-- Patrol route colours, one per killer (from house.js ROUTES)
--==========================================================================
Palette.RouteColour = {
	Bob = Color3.fromRGB(201, 162, 39),
	Barbara = Color3.fromRGB(192, 57, 43),
	Billy = Color3.fromRGB(217, 119, 6),
	Robert = Color3.fromRGB(46, 134, 171),
	Baby = Color3.fromRGB(125, 91, 166),
}

--==========================================================================
-- Lookup
--==========================================================================

function Palette.get(name: string): Style
	return Palette.Style[name] or Palette.Style.ink
end

--- Applies a style to a part, attaching a PointLight if the style glows.
function Palette.apply(part: BasePart, styleOrName: Style | string)
	local resolved: Style
	if type(styleOrName) == "string" then
		resolved = Palette.get(styleOrName)
	else
		resolved = styleOrName
	end

	part.Color = resolved.Colour
	part.Material = resolved.Material
	if resolved.Transparency then
		part.Transparency = resolved.Transparency
	end

	if resolved.Glow then
		local light = Instance.new("PointLight")
		light.Color = resolved.Colour
		light.Brightness = resolved.Glow
		light.Range = resolved.GlowRange or 12
		light.Parent = part
	end
end

return Palette
