--!strict
--[[
	Tags.luau
	--------------------------------------------------------------------------
	CollectionService tag names. This is the contract between the code and
	whatever you build in Studio.

	Tag a part in Studio (Studio -> View -> Tag Editor) and the game will find
	it and wire it up. You never have to touch a script to add a hiding spot or
	a potion spawn -- just tag a part.

	See docs/MAP_BUILDING.md for the full reference, including the attributes
	each tag understands.
	--------------------------------------------------------------------------
]]

local Tags = {
	-- Spawns -------------------------------------------------------------
	LobbySpawn = "DH_LobbySpawn", -- where players stand between rounds
	PlayerSpawn = "DH_PlayerSpawn", -- where players start a round on a map
	KillerSpawn = "DH_KillerSpawn", -- where killers enter the map

	-- Navigation ---------------------------------------------------------
	PatrolNode = "DH_PatrolNode", -- Attribute: Zone (string) -- see KillerData.PatrolZones
	Crawlspace = "DH_Crawlspace", -- patrol node only Baby can use

	-- Objectives ---------------------------------------------------------
	TaskSpawn = "DH_TaskSpawn", -- Attribute: TaskType ("Potion"|"Cross"|"Mirror"|"Any")
	IngredientSpawn = "DH_IngredientSpawn", -- Attribute: Ingredient (BloodSample|HolyWater|Garlic|MagicDust)
	RitualTable = "DH_RitualTable", -- where the four ingredients get combined
	Clock = "DH_Clock", -- the grandfather clock minigame
	FuseBox = "DH_FuseBox", -- safe-zone activation objective

	-- Stealth ------------------------------------------------------------
	HidingSpot = "DH_HidingSpot", -- Attribute: Kind (Locker|Bed|Table|Closet|Duct)
	NoisyTile = "DH_NoisyTile", -- Attribute: Noise (number, default Config.Noise.Actions.CreakyFloor)
	Door = "DH_Door", -- Attribute: Noise (number, default Config.Noise.Actions.OpenDoor)

	-- Landmarks ----------------------------------------------------------
	SafeZone = "DH_SafeZone", -- permanent safe zone volume
	AvaGrave = "DH_AvaGrave", -- Ava dialogue NPC anchor (Graveyard map)
	HelperSpawn = "DH_HelperSpawn", -- candidate spots for Robby/Benny to appear
	LoreNote = "DH_LoreNote", -- Attribute: NoteId (string) -> ObjectiveData.LoreNotes

	-- Runtime-only (added by code, not by you) ----------------------------
	ActiveKiller = "DH_ActiveKiller",
	ActiveHelper = "DH_ActiveHelper",
	TaskItem = "DH_TaskItem",
	TempSafeZone = "DH_TempSafeZone",
}

return Tags
