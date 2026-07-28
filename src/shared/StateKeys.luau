--!strict
--[[
	StateKeys.luau
	--------------------------------------------------------------------------
	String constants for replicated attributes, so a typo is a nil index rather
	than a silent no-op. Server writes them, client reads them.
	--------------------------------------------------------------------------
]]

local StateKeys = {}

-- Attributes on ReplicatedStorage.DollysHome.State ------------------------
StateKeys.Game = {
	Phase = "Phase", -- "Booting" | "Intermission" | "Starting" | "Active" | "Results"
	PhaseEndsAt = "PhaseEndsAt", -- workspace:GetServerTimeNow() deadline; client renders the countdown
	PhaseStartedAt = "PhaseStartedAt",
	MapId = "MapId",
	MapName = "MapName",
	NextMapId = "NextMapId", -- announced once voting closes
	KillerNames = "KillerNames", -- comma-joined display names
	ComboId = "ComboId",
	AlivePlayers = "AlivePlayers",
	TotalPlayers = "TotalPlayers",
	Result = "Result", -- "" | "Victory" | "Defeat"
	VotingOpen = "VotingOpen",
	RoundNumber = "RoundNumber",
}

-- Phase values ------------------------------------------------------------
StateKeys.Phase = {
	Booting = "Booting",
	Intermission = "Intermission",
	Starting = "Starting",
	Active = "Active",
	Results = "Results",
}

-- Attributes on each objective Configuration ------------------------------
StateKeys.Objective = {
	Label = "Label",
	ShortLabel = "ShortLabel",
	Current = "Current",
	Goal = "Goal",
	Complete = "Complete",
	Order = "Order",
	Detail = "Detail", -- free-form line, e.g. "Garlic, Holy Water"
}

-- Attributes on Player ----------------------------------------------------
StateKeys.Player = {
	Noise = "Noise",
	NoiseTier = "NoiseTier",
	Stamina = "Stamina",
	Sprinting = "Sprinting",
	Alive = "Alive", -- in the round and on their feet
	Injured = "Injured", -- downed, bleeding out
	Eliminated = "Eliminated", -- out for the round
	Hidden = "Hidden",
	HidingKind = "HidingKind",
	ReviveEndsAt = "ReviveEndsAt", -- server time the bleed-out expires
	RoundTasks = "RoundTasks", -- individual contribution this round
	RoundRevives = "RoundRevives",
	EquippedStake = "EquippedStake",
	StakeReadyAt = "StakeReadyAt",
	CarriedCrosses = "CarriedCrosses",
	SpeedBoostUntil = "SpeedBoostUntil",
	InSafeZone = "InSafeZone",
	Spectating = "Spectating",
}

-- Attributes on a killer model -------------------------------------------
StateKeys.Killer = {
	KillerId = "KillerId",
	AIState = "AIState", -- "Patrol" | "Investigate" | "Chase" | "Stunned"
	Health = "Health",
	MaxHealth = "MaxHealth",
	StunnedUntil = "StunnedUntil",
	TargetName = "TargetName",
}

return StateKeys
