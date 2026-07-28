--!nonstrict
--[[
	Sounds.luau
	--------------------------------------------------------------------------
	Every sound the game plays, in one table.

	THE IDS ARE BLANK ON PURPOSE. Picking audio is a taste decision and a
	licensing one, and neither belongs in a code file. Upload or find what you
	want on the Creator Store, paste the ids in here, and every system that
	plays them starts working -- nothing else has to change. Anything left blank
	is skipped silently, so the game runs fine with no audio at all.

	The design document's audio direction, for reference when you're choosing:

	  Bob      heavy dragging footsteps, one boot scraping; funeral bells
	  Barbara  a lullaby hummed too high; sharp heels
	  Billy    chains, lantern oil dripping, labored breathing
	  Robert   pages turning, whispered Latin
	  Baby     giggling that echoes; nails on wood; a lullaby that gets louder

	The per-killer approach sounds are the single highest-value audio in the
	game -- they're how a player identifies *which* thing is hunting them, and
	therefore how they decide whether to run or hold still.
	--------------------------------------------------------------------------
]]

local Sounds = {}

--- Continuous heartbeat; rate and volume scale with killer proximity.
Sounds.Heartbeat = ""

--- Ambience, looped per map.
Sounds.Ambience = {
	Lobby = "",
	TheHouse = "",
	TheYard = "",
	MenensLair = "",
	TheGraveyard = "",
}

--- Per-killer approach loop. Played at the killer's position, so it's
--- directional -- which is the whole point.
Sounds.KillerApproach = {
	Bob = "",
	Barbara = "",
	Billy = "",
	Robert = "",
	Baby = "",
}

--- One-shots.
Sounds.Effects = {
	TaskComplete = "",
	PotionCollect = "",
	CrossCollect = "",
	MirrorShatter = "",
	ClockChime = "",
	PotionBrew = "",
	StakeHit = "",
	StakeMiss = "",
	PlayerDowned = "",
	PlayerRevived = "",
	HideEnter = "",
	HideExit = "",
	Discovered = "",
	SafeZoneOpen = "",
	HelperAppear = "",
	RoundStart = "",
	Victory = "",
	Defeat = "",
	CoinTally = "",
	VoteCast = "",
}

--- True if an id is set and looks like an asset reference.
function Sounds.isSet(id: string?): boolean
	return type(id) == "string" and id ~= "" and id ~= "rbxassetid://0"
end

--[[
	Creates a Sound if the id is set, otherwise returns nil. Callers should
	handle nil rather than assume -- that's what makes the blank table safe.
]]
function Sounds.create(id: string?, parent: Instance, props: { [string]: any }?): Sound?
	if not Sounds.isSet(id) then
		return nil
	end

	local sound = Instance.new("Sound")
	sound.SoundId = id :: string
	if props then
		for key, value in props do
			(sound :: any)[key] = value
		end
	end
	sound.Parent = parent
	return sound
end

return Sounds
