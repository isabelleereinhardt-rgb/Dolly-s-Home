--!strict
--[[
	Theme.luau
	--------------------------------------------------------------------------
	One place for every colour, font and spacing value the UI uses.

	The palette follows the design document's Southern Gothic direction --
	deep browns, muted greens and dusty greys, with crimson for danger, pale
	gold for safety and a sick green for the family's eyes. The results screen
	borrows Murder Mystery 2's structure (big banner, ranked avatars, counting
	coins) but not its colours; a cheerful cyan VICTORY would fight everything
	else on screen.
	--------------------------------------------------------------------------
]]

local Theme = {}

--==========================================================================
-- Colour
--==========================================================================
Theme.Colour = {
	-- Surfaces
	Backdrop = Color3.fromRGB(10, 9, 11),
	Panel = Color3.fromRGB(24, 21, 22),
	PanelRaised = Color3.fromRGB(34, 30, 31),
	PanelSunken = Color3.fromRGB(16, 14, 15),
	Divider = Color3.fromRGB(58, 50, 48),

	-- Text
	Text = Color3.fromRGB(232, 224, 210),
	TextDim = Color3.fromRGB(158, 148, 138),
	TextFaint = Color3.fromRGB(104, 96, 90),
	TextInverse = Color3.fromRGB(18, 16, 16),

	-- Accents
	Gold = Color3.fromRGB(214, 176, 102), -- safe zones, coins, highlights
	Crimson = Color3.fromRGB(168, 38, 38), -- danger, defeat
	CrimsonBright = Color3.fromRGB(226, 72, 62),
	Moss = Color3.fromRGB(104, 130, 92), -- victory, the swamp
	MossBright = Color3.fromRGB(146, 190, 128),
	Bone = Color3.fromRGB(206, 198, 178),
	Ghost = Color3.fromRGB(146, 190, 235), -- Robby & Benny

	-- Noise meter, matching Config.Noise.Tiers
	NoiseQuiet = Color3.fromRGB(96, 190, 118),
	NoiseModerate = Color3.fromRGB(224, 202, 90),
	NoiseLoud = Color3.fromRGB(232, 146, 58),
	NoiseExtreme = Color3.fromRGB(226, 62, 58),

	Health = Color3.fromRGB(196, 62, 62),
	Stamina = Color3.fromRGB(126, 176, 216),
}

--==========================================================================
-- Type
--==========================================================================
Theme.Font = {
	Display = Enum.Font.GothamBlack, -- VICTORY / DEFEAT
	Heading = Enum.Font.GothamBold,
	Body = Enum.Font.GothamMedium,
	Numeric = Enum.Font.GothamBold,
	Flavour = Enum.Font.Merriweather, -- lore notes, Ava, killer lines
}

Theme.TextSize = {
	Display = 56,
	Title = 26,
	Heading = 20,
	Body = 16,
	Small = 14,
	Tiny = 12,
}

--==========================================================================
-- Layout
--==========================================================================
Theme.Radius = {
	Small = UDim.new(0, 4),
	Medium = UDim.new(0, 8),
	Large = UDim.new(0, 14),
}

Theme.Padding = {
	Tight = 6,
	Normal = 12,
	Loose = 20,
}

--- Extra top inset so the HUD clears Roblox's own top bar on every device.
Theme.TopBarInset = 42

--==========================================================================
-- Motion
--==========================================================================
Theme.Tween = {
	Fast = TweenInfo.new(0.15, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
	Normal = TweenInfo.new(0.28, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
	Slow = TweenInfo.new(0.5, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
	Bounce = TweenInfo.new(0.7, Enum.EasingStyle.Back, Enum.EasingDirection.Out),
}

--==========================================================================
-- Helpers
--==========================================================================

--- Colour for a noise tier name (as replicated on the player's NoiseTier attribute).
function Theme.noiseColour(tierName: string): Color3
	if tierName == "Extreme" then
		return Theme.Colour.NoiseExtreme
	elseif tierName == "Loud" then
		return Theme.Colour.NoiseLoud
	elseif tierName == "Moderate" then
		return Theme.Colour.NoiseModerate
	end
	return Theme.Colour.NoiseQuiet
end

--- Human-readable label for a noise tier.
function Theme.noiseLabel(tierName: string): string
	if tierName == "Extreme" then
		return "DEAFENING"
	elseif tierName == "Loud" then
		return "LOUD"
	elseif tierName == "Moderate" then
		return "CAUTION"
	end
	return "QUIET"
end

function Theme.rarityColour(rarity: string): Color3
	if rarity == "Legendary" then
		return Color3.fromRGB(240, 200, 100)
	elseif rarity == "Rare" then
		return Color3.fromRGB(120, 160, 220)
	elseif rarity == "Uncommon" then
		return Color3.fromRGB(190, 195, 205)
	end
	return Color3.fromRGB(150, 128, 98)
end

return Theme
