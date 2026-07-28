--!strict
--[[
	KillerData.luau
	--------------------------------------------------------------------------
	The cursed family. Stats, patrol preferences, and voice lines.

	NAMING NOTE
	The source documents spell the youngest child three ways -- "Babby", "Baby",
	and "Bobby" -- and describe what is almost certainly one character twice
	(a crawling child who uses vents, and a fast child who sings lullabies).
	They are merged here into a single killer, "Baby", who has both traits.
	If you want them as two separate killers, copy the Baby entry, rename it
	"Bobby", and drop `CanUseCrawlspaces` from one of them. Nothing else needs
	to change -- the roster is read from this table.

	HearingMultiplier scales the global detection ranges in Config.Noise.Tiers.
	1.0 is the baseline (a 45-stud listener). Robert hears best, Baby worst.
	--------------------------------------------------------------------------
]]

export type KillerProfile = {
	Id: string,
	Name: string,
	Title: string,
	Role: "Killer" | "Helper",
	MaxHealth: number,
	ChaseSpeed: number,
	PatrolSpeed: number,
	HearingRange: number,
	HearingMultiplier: number,
	Persistence: number,
	SearchAggression: number,
	CanUseCrawlspaces: boolean?,
	PatrolZones: { string },
	BodyColor: Color3,
	AccentColor: Color3,
	EyeColor: Color3,
	Scale: number,
	Appearance: string,
	AudioCue: string,
	Lines: { string },
}

local KillerData = {}

KillerData.Profiles = {
	--======================================================================
	Bob = {
		Id = "Bob",
		Name = "Bob",
		Title = "The Broken Patriarch",
		Role = "Killer",
		MaxHealth = 620,
		ChaseSpeed = 21,
		PatrolSpeed = 15,
		HearingRange = 50,
		HearingMultiplier = 50 / 45,
		-- Persistence multiplies how long a killer stays in chase/investigate.
		Persistence = 1.4,
		SearchAggression = 1.0,
		PatrolZones = { "Foyer", "DiningRoom", "LivingRoom", "MasterBedroom", "Hallway" },
		BodyColor = Color3.fromRGB(58, 48, 44),
		AccentColor = Color3.fromRGB(28, 26, 30),
		EyeColor = Color3.fromRGB(180, 40, 30),
		Scale = 1.15,
		Appearance = "Tall and gaunt, missing his right hand, dragging one leg in a tattered gentleman's suit.",
		AudioCue = "Heavy uneven footsteps and a low growl. One boot drags.",
		Lines = {
			"Where did it all go wrong?",
			"Barbara... why did you do this to me?",
			"The family must stay together...",
			"I only wanted us to last.",
		},
	},

	--======================================================================
	Barbara = {
		Id = "Barbara",
		Name = "Barbara",
		Title = "The Violent Matriarch",
		Role = "Killer",
		MaxHealth = 620,
		ChaseSpeed = 22, -- fastest killer
		PatrolSpeed = 16,
		HearingRange = 45,
		HearingMultiplier = 1.0,
		Persistence = 1.5,
		SearchAggression = 1.5, -- checks hiding spots far more often
		PatrolZones = { "Kitchen", "DiningRoom", "Pantry", "ChildrensRoom", "Hallway" },
		BodyColor = Color3.fromRGB(92, 46, 52),
		AccentColor = Color3.fromRGB(120, 22, 28),
		EyeColor = Color3.fromRGB(230, 60, 60),
		Scale = 1.05,
		Appearance = "A blood-stained Victorian dress, wild hair, and hands she never washed clean.",
		AudioCue = "A lullaby hummed too high, and sharp heels on floorboards.",
		Lines = {
			"My children need to eat!",
			"I'm still a good mother!",
			"Don't run from mother!",
			"Come back. Come back and let me look at you.",
		},
	},

	--======================================================================
	Billy = {
		Id = "Billy",
		Name = "Billy",
		Title = "The Eldest's Burden",
		Role = "Killer",
		MaxHealth = 430,
		ChaseSpeed = 20,
		PatrolSpeed = 17, -- covers ground fast on patrol
		HearingRange = 40,
		HearingMultiplier = 40 / 45,
		Persistence = 0.9,
		SearchAggression = 1.3, -- thorough rather than aggressive
		PatrolZones = { "Cellar", "Storage", "BoilerRoom", "Hallway", "Foyer" },
		BodyColor = Color3.fromRGB(74, 70, 52),
		AccentColor = Color3.fromRGB(46, 44, 34),
		EyeColor = Color3.fromRGB(220, 200, 70),
		Scale = 1.0,
		Appearance = "Torn farmhand clothing, skeletal features, a broken lantern he still carries.",
		AudioCue = "Chains rattling, lantern oil dripping, labored breathing.",
		Lines = {
			"I tried to be a good brother...",
			"This wasn't supposed to happen.",
			"Stop hiding. It'll be quick.",
			"Somebody had to hold this family together.",
		},
	},

	--======================================================================
	Robert = {
		Id = "Robert",
		Name = "Robert",
		Title = "The Resentful Scholar",
		Role = "Killer",
		MaxHealth = 430,
		ChaseSpeed = 19,
		PatrolSpeed = 14,
		HearingRange = 55, -- best ears in the family
		HearingMultiplier = 55 / 45,
		Persistence = 1.1,
		SearchAggression = 1.1,
		PatrolZones = { "Library", "Study", "RitualRoom", "Foyer" },
		BodyColor = Color3.fromRGB(48, 44, 58),
		AccentColor = Color3.fromRGB(30, 28, 38),
		EyeColor = Color3.fromRGB(150, 90, 220),
		Scale = 1.05,
		Appearance = "Tattered scholar's robes, cracked spectacles hanging off his face, ink-stained hands.",
		AudioCue = "Pages rustling and whispered Latin.",
		Lines = {
			"I deserved more than this!",
			"I should have been the one...",
			"Pride is all I have left.",
			"I'll find you first. I always do.",
		},
	},

	--======================================================================
	Baby = {
		Id = "Baby",
		Name = "Baby",
		Title = "The Innocent Corrupted",
		Role = "Killer",
		MaxHealth = 430,
		-- Stats from the characters.js mockup, which supersedes the PDF's
		-- "Very Fast / Small detection" wording.
		ChaseSpeed = 20,
		PatrolSpeed = 17,
		HearingRange = 40,
		HearingMultiplier = 40 / 45,
		Persistence = 0.7, -- loses interest quickly, then finds you again
		SearchAggression = 1.4,
		CanUseCrawlspaces = true,
		PatrolZones = { "ChildrensRoom", "Attic", "Crawlspace", "Hallway", "LivingRoom" },
		BodyColor = Color3.fromRGB(112, 104, 96),
		AccentColor = Color3.fromRGB(150, 140, 130),
		EyeColor = Color3.fromRGB(120, 230, 140),
		Scale = 0.7, -- child-sized
		Appearance = "Child-sized and wrong, in a torn nightgown, moving on all fours as often as not.",
		AudioCue = "Giggling that echoes, nails scratching wood, a lullaby that gets louder as she nears.",
		Lines = {
			"Let's play hide and seek!",
			"Found you!",
			"Why won't you play with me?",
			"Ring around the rosie...",
		},
	},

	--======================================================================
	-- HELPERS -- never selected as killers.
	--======================================================================
	Robby = {
		Id = "Robby",
		Name = "Robby",
		Title = "The Helper",
		Role = "Helper",
		MaxHealth = 430,
		ChaseSpeed = 0,
		PatrolSpeed = 0,
		HearingRange = 0,
		HearingMultiplier = 0,
		Persistence = 0,
		SearchAggression = 0,
		PatrolZones = {},
		BodyColor = Color3.fromRGB(120, 150, 190),
		AccentColor = Color3.fromRGB(180, 210, 240),
		EyeColor = Color3.fromRGB(120, 200, 255),
		Scale = 1.0,
		Appearance = "Flickering and translucent, still mostly himself, tired around the eyes.",
		AudioCue = "A soft chime, like wind through a broken window.",
		Lines = {
			"Hide here, quickly!",
			"I'm so sorry for what they've become...",
			"Ava... please forgive us.",
			"You can make it out. I believe in you.",
		},
	},

	Benny = {
		Id = "Benny",
		Name = "Benny",
		Title = "The Helper",
		Role = "Helper",
		MaxHealth = 430,
		ChaseSpeed = 0,
		PatrolSpeed = 0,
		HearingRange = 0,
		HearingMultiplier = 0,
		Persistence = 0,
		SearchAggression = 0,
		PatrolZones = {},
		BodyColor = Color3.fromRGB(130, 170, 150),
		AccentColor = Color3.fromRGB(190, 230, 210),
		EyeColor = Color3.fromRGB(140, 255, 190),
		Scale = 0.92,
		Appearance = "The youngest of the brothers, curious-eyed, barely marked by the curse.",
		AudioCue = "A whisper right beside your ear.",
		Lines = {
			"Shh! Someone's coming this way!",
			"I didn't want this... none of us did.",
			"Ava... we're so sorry.",
			"It's behind the bookshelf. Go, go!",
		},
	},
} :: { [string]: KillerProfile }

--- Killer ids eligible to be selected as the round's hunters.
function KillerData.getKillerRoster(): { string }
	local out = {}
	for id, profile in KillerData.Profiles do
		if profile.Role == "Killer" then
			table.insert(out, id)
		end
	end
	table.sort(out)
	return out
end

--- Helper ids (Robby, Benny). Never hunt the players.
function KillerData.getHelperRoster(): { string }
	local out = {}
	for id, profile in KillerData.Profiles do
		if profile.Role == "Helper" then
			table.insert(out, id)
		end
	end
	table.sort(out)
	return out
end

function KillerData.get(id: string): KillerProfile?
	return KillerData.Profiles[id]
end

return KillerData
