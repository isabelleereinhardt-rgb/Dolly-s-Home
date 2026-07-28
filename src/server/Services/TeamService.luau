--!strict
--[[
	TeamService.luau
	--------------------------------------------------------------------------
	Two teams: Survivors (in the round, on their feet) and Lost (lobby,
	spectating, eliminated). Killers are NPCs, not players, so they need no team.

	The team a player is on is the single source of truth for "are they in the
	round". Player attributes (Alive/Injured/Eliminated) describe *how* they are
	in it.
	--------------------------------------------------------------------------
]]

local Players = game:GetService("Players")
local Teams = game:GetService("Teams")

local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
local StateKeys = require(Shared.StateKeys)
local Util = require(Shared.Util)

local TeamService = {}

local survivors: Team
local lost: Team

local SURVIVOR_COLOR = BrickColor.new("Bright green")
local LOST_COLOR = BrickColor.new("Really black")

--==========================================================================
-- Setup
--==========================================================================

local function ensureTeam(name: string, color: BrickColor, autoAssign: boolean): Team
	local team = Teams:FindFirstChild(name) :: Team?
	if not team then
		team = Instance.new("Team")
		team.Name = name
		team.Parent = Teams
	end
	team.TeamColor = color
	team.AutoAssignable = autoAssign
	return team
end

--==========================================================================
-- Queries
--==========================================================================

function TeamService.getSurvivorTeam(): Team
	return survivors
end

function TeamService.getLostTeam(): Team
	return lost
end

--- Is this player in the current round at all (alive or injured)?
function TeamService.isInRound(player: Player): boolean
	return player.Team == survivors and player:GetAttribute(StateKeys.Player.Eliminated) ~= true
end

--- On their feet and playable.
function TeamService.isAlive(player: Player): boolean
	return TeamService.isInRound(player) and player:GetAttribute(StateKeys.Player.Injured) ~= true
end

function TeamService.isInjured(player: Player): boolean
	return TeamService.isInRound(player) and player:GetAttribute(StateKeys.Player.Injured) == true
end

--- Everyone still in the round, standing or downed.
function TeamService.getParticipants(): { Player }
	local out = {}
	for _, player in Players:GetPlayers() do
		if TeamService.isInRound(player) then
			table.insert(out, player)
		end
	end
	return out
end

--- Everyone on their feet.
function TeamService.getAlive(): { Player }
	local out = {}
	for _, player in Players:GetPlayers() do
		if TeamService.isAlive(player) then
			table.insert(out, player)
		end
	end
	return out
end

function TeamService.getInjured(): { Player }
	local out = {}
	for _, player in Players:GetPlayers() do
		if TeamService.isInjured(player) then
			table.insert(out, player)
		end
	end
	return out
end

function TeamService.countAlive(): number
	return #TeamService.getAlive()
end

--- True once nobody is left standing *and* nobody is still bleeding out.
function TeamService.isWipe(): boolean
	return #TeamService.getParticipants() == 0
end

--==========================================================================
-- Assignment
--==========================================================================

--- Puts a player into the round with a clean slate.
function TeamService.enterRound(player: Player)
	player.Team = survivors
	player.Neutral = false
	player:SetAttribute(StateKeys.Player.Alive, true)
	player:SetAttribute(StateKeys.Player.Injured, false)
	player:SetAttribute(StateKeys.Player.Eliminated, false)
	player:SetAttribute(StateKeys.Player.Spectating, false)
	player:SetAttribute(StateKeys.Player.ReviveEndsAt, 0)
	player:SetAttribute(StateKeys.Player.RoundTasks, 0)
	player:SetAttribute(StateKeys.Player.RoundRevives, 0)
	player:SetAttribute(StateKeys.Player.CarriedCrosses, 0)
	player:SetAttribute(StateKeys.Player.Noise, 0)
	player:SetAttribute(StateKeys.Player.Hidden, false)
	player:SetAttribute(StateKeys.Player.InSafeZone, false)
	Util.log("TeamService", "%s entered the round", player.Name)
end

--- Removes a player from the round (eliminated, or the round just ended).
function TeamService.exitRound(player: Player, eliminated: boolean)
	player.Team = lost
	player.Neutral = false
	player:SetAttribute(StateKeys.Player.Alive, false)
	player:SetAttribute(StateKeys.Player.Injured, false)
	player:SetAttribute(StateKeys.Player.Eliminated, eliminated)
	player:SetAttribute(StateKeys.Player.ReviveEndsAt, 0)
	player:SetAttribute(StateKeys.Player.Hidden, false)
	player:SetAttribute(StateKeys.Player.InSafeZone, false)
	player:SetAttribute(StateKeys.Player.Spectating, eliminated)
end

--- Everyone back to the lobby, round stats cleared.
function TeamService.resetAll()
	for _, player in Players:GetPlayers() do
		TeamService.exitRound(player, false)
		player:SetAttribute(StateKeys.Player.Spectating, false)
		player:SetAttribute(StateKeys.Player.RoundTasks, 0)
		player:SetAttribute(StateKeys.Player.RoundRevives, 0)
		player:SetAttribute(StateKeys.Player.CarriedCrosses, 0)
		player:SetAttribute(StateKeys.Player.Noise, 0)
	end
end

--==========================================================================
-- Lifecycle
--==========================================================================

function TeamService.start()
	survivors = ensureTeam("Survivors", SURVIVOR_COLOR, false)
	lost = ensureTeam("Lost", LOST_COLOR, true)

	local function onPlayerAdded(player: Player)
		player.Team = lost
		player.Neutral = false
		player:SetAttribute(StateKeys.Player.Alive, false)
		player:SetAttribute(StateKeys.Player.Injured, false)
		player:SetAttribute(StateKeys.Player.Eliminated, false)
		player:SetAttribute(StateKeys.Player.Noise, 0)
		player:SetAttribute(StateKeys.Player.NoiseTier, "Quiet")
		player:SetAttribute(StateKeys.Player.Stamina, 100)
		player:SetAttribute(StateKeys.Player.RoundTasks, 0)
		player:SetAttribute(StateKeys.Player.RoundRevives, 0)
	end

	Players.PlayerAdded:Connect(onPlayerAdded)
	for _, player in Players:GetPlayers() do
		onPlayerAdded(player)
	end
end

return TeamService
