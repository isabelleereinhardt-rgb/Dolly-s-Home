--!strict
--[[
	ObjectiveData.luau
	--------------------------------------------------------------------------
	Definitions for every task type, plus the round combinations they're drawn
	from. ObjectiveService reads this table -- adding a new objective means
	adding an entry here and (if it's a new Kind) a handler in ObjectiveService.

	Kinds:
	  "collect"     -- pick up N items spawned at tagged points
	  "ingredients" -- collect 4 named items, then use the ritual table
	  "clock"       -- set the grandfather clock to a randomized time
	  "fuses"       -- restore power to N safe zone entrances
	--------------------------------------------------------------------------
]]

local Config = require(script.Parent.Config)

export type ObjectiveDef = {
	Id: string,
	Kind: string,
	Label: string,
	ShortLabel: string,
	Goal: number,
	SpawnTaskType: string?,
	HoldSeconds: number,
	Description: string,
	CompletionNoise: number?,
	Icon: string?,
}

local ObjectiveData = {}

ObjectiveData.Definitions = {
	Potions = {
		Id = "Potions",
		Kind = "collect",
		Label = "Collect Potions",
		ShortLabel = "Potions",
		Goal = Config.Objectives.Potions.Goal,
		SpawnTaskType = "Potion",
		HoldSeconds = Config.Objectives.Potions.HoldSeconds,
		Description = "Fifteen bottles are hidden through the house. Only five sit out at a time -- take one and another is set out somewhere else a half-minute later.",
		Icon = "rbxassetid://0",
	},

	Mirrors = {
		Id = "Mirrors",
		Kind = "collect",
		Label = "Recover Mirror Fragments",
		ShortLabel = "Mirrors",
		Goal = Config.Objectives.Mirrors.Goal,
		SpawnTaskType = "Mirror",
		HoldSeconds = Config.Objectives.Mirrors.HoldSeconds,
		Description = "Five shards of the family mirror, tucked into drawers and behind paintings. They come away in your hand the moment you touch them.",
		CompletionNoise = Config.Noise.Actions.BreakMirror,
		Icon = "rbxassetid://0",
	},

	Crosses = {
		Id = "Crosses",
		Kind = "collect",
		Label = "Gather Blessed Crosses",
		ShortLabel = "Crosses",
		Goal = Config.Objectives.Crosses.Goal,
		SpawnTaskType = "Cross",
		HoldSeconds = Config.Objectives.Crosses.HoldSeconds,
		Description = "Fourteen iron crosses. They are heavier than they look, and you will feel every one you carry.",
		Icon = "rbxassetid://0",
	},

	Ingredients = {
		Id = "Ingredients",
		Kind = "ingredients",
		Label = "Brew the Sealing Potion",
		ShortLabel = "Sealing Potion",
		Goal = #Config.Objectives.Ingredients.Items,
		HoldSeconds = Config.Objectives.Ingredients.HoldSeconds,
		Description = "Blood from the ritual room, holy water from the cellar, garlic from the kitchen, magic dust from the study. Bring all four to the ritual table.",
		CompletionNoise = Config.Noise.Actions.BrewPotion,
		Icon = "rbxassetid://0",
	},

	Clock = {
		Id = "Clock",
		Kind = "clock",
		Label = "Set the Grandfather Clock",
		ShortLabel = "Clock",
		Goal = 1,
		HoldSeconds = Config.Objectives.Clock.HoldSeconds,
		Description = "The clock stopped at the hour Ava died. Set it right -- and brace yourself, because it will chime.",
		CompletionNoise = Config.Noise.Actions.AdjustClock,
		Icon = "rbxassetid://0",
	},

	SafeZones = {
		Id = "SafeZones",
		Kind = "fuses",
		Label = "Restore the Sanctified Barriers",
		ShortLabel = "Safe Zones",
		Goal = Config.Objectives.SafeZone.Goal,
		HoldSeconds = Config.Objectives.SafeZone.HoldSeconds,
		Description = "Three fuse boxes feed the blessed lamps at the safe zone doors. Get them all burning again.",
		Icon = "rbxassetid://0",
	},
} :: { [string]: ObjectiveDef }

--[[
	Round combinations. Potions is the primary objective and appears in every
	set, matching the design doc. Weight biases the random pick -- higher weight
	means the combo comes up more often.
]]
ObjectiveData.Combos = {
	{ Id = "Reflections", Objectives = { "Potions", "Mirrors" }, Weight = 3 },
	{ Id = "Consecration", Objectives = { "Potions", "Crosses" }, Weight = 3 },
	{ Id = "TheSealing", Objectives = { "Potions", "Ingredients", "Clock" }, Weight = 2 },
	{ Id = "Sanctuary", Objectives = { "Potions", "Mirrors", "SafeZones" }, Weight = 2 },
	{ Id = "TheLongNight", Objectives = { "Potions", "Crosses", "Ingredients" }, Weight = 1 },
}

--[[
	Environmental storytelling. Tag a part DH_LoreNote and set its NoteId
	attribute to one of these keys.
]]
ObjectiveData.LoreNotes = {
	BobLedger = {
		Title = "Funeral Ledger, page 14",
		Author = "Bob",
		Body = "Third notice from the bank. If the crop fails again we lose the house and every acre with it. I will not be the one who loses what my father built. There has to be something left to trade.",
	},
	BarbaraBills = {
		Title = "Doctor's Bill, unpaid",
		Author = "Barbara",
		Body = "For the treatment of the youngest child -- fourteen dollars. For the second visit -- eleven. Bob says not to worry. Bob says a great many things now.",
	},
	BillyLetter = {
		Title = "Unsent letter",
		Author = "Billy",
		Body = "Dear Sirs, I am writing regarding admission to the medical college. I am the eldest of six and can offer no reference but my own hand. I have written this eleven times. I have sent it none.",
	},
	RobertJournal = {
		Title = "Journal, water-damaged",
		Author = "Robert",
		Body = "Father chose Billy. Father always chooses Billy. I have read every book in this house and it has bought me nothing at all.",
	},
	AvaDiary1 = {
		Title = "Ava's diary, torn page",
		Author = "Ava",
		Body = "They think Menen is a stranger. He came when I called him and he stays because I ask. I only wanted to know whether they would choose me. I am sorry that I wanted to know.",
	},
	AvaDiary2 = {
		Title = "Ava's diary, last page",
		Author = "Ava",
		Body = "I have given them thirty days. I gave them thirty days the last time too, and the time before. I am not certain any more whether I am testing them or punishing myself.",
	},
	PreviousVictim = {
		Title = "Scratched into the floorboards",
		Author = "Unknown",
		Body = "DO NOT RUN. IT ONLY HEARS YOU. -- there are four more sets of scratches beneath this one, in four different hands.",
	},
}

--- Picks a weighted-random objective combination.
function ObjectiveData.pickCombo(rng: Random?)
	local random = rng or Random.new()
	local total = 0
	for _, combo in ObjectiveData.Combos do
		total += combo.Weight
	end

	local roll = random:NextNumber() * total
	for _, combo in ObjectiveData.Combos do
		roll -= combo.Weight
		if roll <= 0 then
			return combo
		end
	end
	return ObjectiveData.Combos[1]
end

function ObjectiveData.get(id: string): ObjectiveDef?
	return ObjectiveData.Definitions[id]
end

return ObjectiveData
