--!strict
--[[
	Config.luau
	--------------------------------------------------------------------------
	Every tunable number in Dolly's Home lives here. Nothing else should hard-code
	a balance value -- if you want to change how the game feels, change it here.

	Where the two design documents disagreed, the value used is noted with a
	`-- DOC:` comment and explained in docs/DESIGN_DECISIONS.md.
	--------------------------------------------------------------------------
]]

local Config = {}

--==========================================================================
-- ROUND FLOW
--==========================================================================
Config.Round = {
	-- Lobby / intermission
	IntermissionSeconds = 50,
	VotingSeconds = 30, -- voting window inside the intermission
	MinPlayersToStart = 1, -- set to 2+ before release; 1 makes solo testing easy

	-- Start transition
	StartupSeconds = 6,

	-- The round itself
	RoundSeconds = 600, -- 10 minutes

	-- Results
	ResultsSeconds = 15, -- DOC: doc says both 15s and 5s; 15s chosen
	PostResultsSeconds = 5,
}

--==========================================================================
-- PLAYER
--==========================================================================
Config.Player = {
	MaxHealth = 100,
	WalkSpeed = 16,
	SprintSpeed = 24,
	JumpPower = 50,

	-- Sprinting drains stamina; 0 stamina forces a walk until it recovers.
	-- Set StaminaEnabled = false for the pure design-doc behaviour (unlimited sprint).
	StaminaEnabled = true,
	MaxStamina = 100,
	StaminaDrainPerSecond = 14,
	StaminaRegenPerSecond = 9,
	StaminaRegenDelay = 1.5,
}

--==========================================================================
-- NOISE SYSTEM  (the heart of the stealth loop)
--==========================================================================
Config.Noise = {
	Max = 100,

	-- Continuous generation (per second)
	WalkRate = 0.5,
	SprintRate = 2.0,
	CrouchRate = 0.15,

	-- Instant spikes
	Actions = {
		OpenDoor = 15,
		CollectItem = 10,
		BreakMirror = 25,
		BrewPotion = 40, -- applied over BrewPotionSeconds
		AdjustClock = 50,
		Land = 8,
		CreakyFloor = 12,
		EnterHidingSpot = 5,
		Attack = 20,
		Revive = 8,
	},
	BrewPotionSeconds = 10,

	-- Decay (per second)
	DecayIdle = 0.5,
	DecayCrouched = 0.3,
	-- Hiding settles you fast, so a locker feels like relief rather than a
	-- two-minute wait for the meter to come down.
	DecayHidden = 6,

	-- Detection tiers. `Range` is how far a killer can hear a player sitting at
	-- that noise level, before the killer's own hearing multiplier is applied.
	-- Priority breaks ties when several players are audible at once.
	Tiers = {
		{ Name = "Quiet", Min = 0, Max = 9.999, Range = 12, Response = "Ignore", Priority = 0, Color = Color3.fromRGB(90, 220, 120) },
		{ Name = "Moderate", Min = 10, Max = 29.999, Range = 40, Response = "Turn", Priority = 1, Color = Color3.fromRGB(240, 220, 90) },
		{ Name = "Loud", Min = 30, Max = 49.999, Range = 60, Response = "Investigate", Priority = 2, Color = Color3.fromRGB(245, 155, 60) },
		{ Name = "Extreme", Min = 50, Max = math.huge, Range = math.huge, Response = "Rush", Priority = 3, Color = Color3.fromRGB(235, 70, 70) },
	},

	-- How often the server recomputes noise (Hz). Higher = smoother meter, more work.
	TickRate = 10,
	-- Don't replicate a change smaller than this (cuts attribute churn hard).
	ReplicateEpsilon = 0.25,
}

--==========================================================================
-- KILLER AI
--==========================================================================
Config.Killer = {
	PatrolSpeed = 16,

	-- Attacking
	AttackRange = 7,
	AttackDamage = 55, -- two connected hits down a full-health player
	AttackCooldown = 1.6,
	AttackWindup = 0.35,

	-- State timing
	InvestigateMemory = 10, -- seconds spent searching a noise source before giving up
	ChaseGiveUpSilence = 8, -- seconds of silence + no line of sight before dropping chase
	SearchRadius = 18, -- how far the killer wanders around an investigation point
	HidingSpotCheckChance = 0.3, -- chance to search a hiding spot while investigating
	HidingSpotCheckChanceClose = 0.5, -- chance when the killer is right on top of it
	HidingSpotCheckRange = 14,
	LongHideSuspicionSeconds = 30, -- camping one spot this long makes killers suspicious

	-- Health / stakes
	RegenPerSecond = -1, -- computed below from RegenFullSeconds
	RegenFullSeconds = 60, -- full HP bar regenerates in this many seconds
	RegenDelayAfterHit = 5,

	-- Pathfinding
	RepathInterval = 0.6,
	WaypointReachedDistance = 4,
	AgentRadius = 2.5,
	AgentHeight = 5,
	AgentCanJump = true,

	-- Vision is a *backup* sense only. Killers are blind by design; this exists
	-- so a player standing directly in front of one for several seconds is not
	-- completely invisible. Set Enabled = false for pure sound-only hunting.
	Vision = {
		Enabled = true,
		Range = 14,
		FieldOfViewDegrees = 70,
	},

	-- How many killers spawn each round
	SpawnChanceTwo = 0.3, -- DOC: 70% one killer, 30% two
	MaxActive = 2,
	LorePairs = { { "Bob", "Barbara" } }, -- thematic pairings that get a bonus roll
	LorePairChance = 0.35,
}

--==========================================================================
-- COMBAT (stakes)
--==========================================================================
-- DOC: the two documents give two different stake tables. The later, more
-- detailed one is used (damage 30/45/60/90, stun 10/15/20/30s, cost 50/150/300/750).
Config.Stakes = {
	AttackRange = 8,
	Cooldown = 3,

	Tiers = {
		{
			Id = "Common",
			Name = "Wooden Stake",
			Damage = 30,
			StunSeconds = 10,
			Cost = 50,
			Color = Color3.fromRGB(140, 105, 70),
			Order = 1,
		},
		{
			Id = "Uncommon",
			Name = "Silver-Tipped Stake",
			Damage = 45,
			StunSeconds = 15,
			Cost = 150,
			Color = Color3.fromRGB(190, 195, 205),
			Order = 2,
		},
		{
			Id = "Rare",
			Name = "Rune-Carved Stake",
			Damage = 60,
			StunSeconds = 20,
			Cost = 300,
			Color = Color3.fromRGB(120, 160, 220),
			Order = 3,
		},
		{
			Id = "Legendary",
			Name = "Ashwood Reliquary",
			Damage = 90,
			StunSeconds = 30,
			Cost = 750,
			Color = Color3.fromRGB(240, 200, 100),
			Order = 4,
		},
	},

	-- Killers are immortal. Draining their HP bar only extends the stun.
	StunOnDepleted = 8, -- bonus stun seconds when a hit empties the bar
}

--==========================================================================
-- REVIVAL
--==========================================================================
Config.Revival = {
	BleedOutSeconds = 30,
	ReviveHoldSeconds = 3,
	ReviveHealthPercent = 0.5,
	PostReviveImmunitySeconds = 2,
	ReviveRange = 10,

	-- Design doc body says injured players cannot move; the "Flee the Facility"
	-- inspiration section suggests letting them crawl. Set > 0 to enable crawling.
	CrawlSpeed = 0,

	CoinsPerRevive = 20, -- DOC: 10 in one section, 20 in the award table; 20 used
}

--==========================================================================
-- OBJECTIVES
--==========================================================================
Config.Objectives = {
	Potions = {
		Goal = 15,
		ActiveAtOnce = 5,
		RespawnDelay = 30,
		HoldSeconds = 5,
	},
	Mirrors = {
		Goal = 5,
		HoldSeconds = 0, -- instant on interact
	},
	Crosses = {
		Goal = 14,
		HoldSeconds = 3,
		CarrySlowdown = 0.9, -- walk speed multiplier while carrying crosses
	},
	Ingredients = {
		Items = { "BloodSample", "HolyWater", "Garlic", "MagicDust" },
		HoldSeconds = 3,
		RitualHoldSeconds = 6,
	},
	Clock = {
		HoldSeconds = 2,
		ToleranceMinutes = 5, -- how close the player must set the hands
	},
	SafeZone = {
		Goal = 3,
		HoldSeconds = 4,
	},
}

--==========================================================================
-- HIDING
--==========================================================================
Config.Hiding = {
	ExitDelay = 1, -- anti hide-spam
	EnterDuration = 0.5,
	NoiseWhileHidden = 0, -- hidden players generate no movement noise
}

--==========================================================================
-- HELPER NPCs (Robby & Benny)
--==========================================================================
Config.Helpers = {
	AppearancesPerRound = { Min = 3, Max = 4 },
	FirstAppearanceDelay = 60,
	AppearanceGap = { Min = 70, Max = 130 },

	-- DOC: the PDFs say 15, 20 and 30 in three different places. The
	-- characters.js mockup settles it at 30, and is the most recent statement.
	SafeZoneDuration = 30,
	SafeZoneRadius = 18,
	SafeZoneKillerRepelRadius = 24,

	WarnRange = 30, -- Benny warns when a killer is this close
	VisibleSeconds = 25,

	-- "Identity Fraud" inspiration: rare chance the helper is Robert in disguise.
	ImposterChance = 0.05,
}

--==========================================================================
-- ECONOMY
--==========================================================================
-- DOC: two coin tables exist. The round-end award table is used as the source of
-- truth because it is the more complete of the two.
Config.Economy = {
	WinCoins = 50,
	ParticipationCoins = 25,
	CoinsPerTask = 10,
	CoinsPerRevive = 20,
	TopRankBonus = 50,

	StartingCoins = 0,
	StartingStake = "Common", -- everyone owns the basic stake from the start
}

Config.Shop = {
	-- DOC: prices differ between sections. Stake prices come from the tier table
	-- above; consumables use the "Consumable Items" section values.
	SpeedPotion = {
		Id = "SpeedPotion",
		Name = "Swamp Runner's Draught",
		Cost = 200,
		Description = "Run at double speed for 10 minutes of real time.",
		Multiplier = 2,
		DurationSeconds = 600,
		Consumable = true,
	},
	HealthPotion = {
		Id = "HealthPotion",
		Name = "Bayou Restorative",
		Cost = 100,
		Description = "Instantly restore yourself to full health.",
		Consumable = true,
	},
}

--==========================================================================
-- MAPS
--==========================================================================
Config.Maps = {
	{ Id = "TheHouse", Name = "The House", Description = "The decaying plantation manor.", Enabled = true },
	{ Id = "TheYard", Name = "The Yard", Description = "Overgrown gardens and the old well.", Enabled = false },
	{ Id = "MenensLair", Name = "Menen's Lair", Description = "A pocket dimension that will not hold still.", Enabled = false },
	{ Id = "TheGraveyard", Name = "The Graveyard", Description = "Family crypts, and Ava's grave.", Enabled = false },
}

--==========================================================================
-- DATA PERSISTENCE
--==========================================================================
Config.Data = {
	StoreName = "DollysHome_PlayerData_v1",
	AutosaveInterval = 120,
	MaxRetries = 4,
	RetryBackoff = 2,
}

--==========================================================================
-- DEBUG
--==========================================================================
Config.Debug = {
	Verbose = false, -- print state transitions to the output window
	ShowKillerState = false, -- billboard above each killer showing its AI state
	ShowNoiseInOutput = false,
}

--==========================================================================
-- Derived values
--==========================================================================
Config.Killer.RegenPerSecond = 1 / Config.Killer.RegenFullSeconds -- fraction of max HP per second

--- Returns the noise tier table for a given noise level.
function Config.getNoiseTier(level: number)
	for _, tier in Config.Noise.Tiers do
		if level >= tier.Min and level <= tier.Max then
			return tier
		end
	end
	return Config.Noise.Tiers[1]
end

--- Returns the stake tier table for an id, or nil.
function Config.getStakeTier(id: string?)
	if not id then
		return nil
	end
	for _, tier in Config.Stakes.Tiers do
		if tier.Id == id then
			return tier
		end
	end
	return nil
end

--- Returns only the maps currently playable.
function Config.getEnabledMaps()
	local out = {}
	for _, map in Config.Maps do
		if map.Enabled then
			table.insert(out, map)
		end
	end
	return out
end

return Config
