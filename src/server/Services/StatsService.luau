--!strict
--[[
	StatsService.luau
	--------------------------------------------------------------------------
	End-of-round scoring: who did what, what it's worth, and the ranked list the
	results screen renders.

	Ranking is tasks + revives, deliberately weighting revives higher, because
	sprinting across a dark house to pick a teammate up is a bigger ask than
	grabbing a bottle off a shelf.
	--------------------------------------------------------------------------
]]

local Players = game:GetService("Players")

local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
local Config = require(Shared.Config)
local StateKeys = require(Shared.StateKeys)
local Util = require(Shared.Util)

local DataService = require(script.Parent.DataService)

local StatsService = {}

local REVIVE_RANK_WEIGHT = 2

export type PlayerResult = {
	UserId: number,
	Name: string,
	DisplayName: string,
	Tasks: number,
	Revives: number,
	Survived: boolean,
	Eliminated: boolean,
	Coins: number,
	Wins: number,
	Rank: number,
	IsTopPerformer: boolean,
}

-- Everyone who was in the round when it started, so a player who was
-- eliminated (and is therefore off the Survivors team by now) still appears on
-- the scoreboard and still gets paid.
local roster: { [Player]: boolean } = {}

--==========================================================================
-- Roster
--==========================================================================

function StatsService.beginRound(participants: { Player })
	table.clear(roster)
	for _, player in participants do
		roster[player] = true
		player:SetAttribute(StateKeys.Player.RoundTasks, 0)
		player:SetAttribute(StateKeys.Player.RoundRevives, 0)
	end
end

function StatsService.addParticipant(player: Player)
	roster[player] = true
end

--==========================================================================
-- Scoring
--==========================================================================

local function scoreOf(tasks: number, revives: number): number
	return tasks + revives * REVIVE_RANK_WEIGHT
end

--[[
	Tallies the round, pays everyone, and returns the payload for the results
	screen.

	Payouts follow the design doc's award table:
	  participation  +25   (everyone who was in the round, dead or alive)
	  victory        +50   (survivors only)
	  per task       +10
	  per revive     +20
	  top performer  +50
]]
function StatsService.endRound(victory: boolean): { PlayerResult }
	local results: { PlayerResult } = {}

	for player in roster do
		if not player.Parent then
			continue
		end

		local tasks = (player:GetAttribute(StateKeys.Player.RoundTasks) or 0) :: number
		local revives = (player:GetAttribute(StateKeys.Player.RoundRevives) or 0) :: number
		local eliminated = player:GetAttribute(StateKeys.Player.Eliminated) == true
		local survived = not eliminated

		table.insert(results, {
			UserId = player.UserId,
			Name = player.Name,
			DisplayName = player.DisplayName,
			Tasks = tasks,
			Revives = revives,
			Survived = survived,
			Eliminated = eliminated,
			Coins = 0,
			Wins = 0,
			Rank = 0,
			IsTopPerformer = false,
		})
	end

	table.sort(results, function(a, b)
		local scoreA, scoreB = scoreOf(a.Tasks, a.Revives), scoreOf(b.Tasks, b.Revives)
		if scoreA ~= scoreB then
			return scoreA > scoreB
		end
		if a.Survived ~= b.Survived then
			return a.Survived
		end
		return a.DisplayName < b.DisplayName
	end)

	-- Nobody who did nothing gets a "top performer" bonus, even if they came
	-- first in an empty field.
	local topScore = #results > 0 and scoreOf(results[1].Tasks, results[1].Revives) or 0

	local byUserId: { [number]: Player } = {}
	for player in roster do
		byUserId[player.UserId] = player
	end

	for index, result in results do
		result.Rank = index

		local coins = Config.Economy.ParticipationCoins
		coins += result.Tasks * Config.Economy.CoinsPerTask
		coins += result.Revives * Config.Economy.CoinsPerRevive

		if victory and result.Survived then
			coins += Config.Economy.WinCoins
		end

		if index == 1 and topScore > 0 then
			coins += Config.Economy.TopRankBonus
			result.IsTopPerformer = true
		end

		result.Coins = coins

		local player = byUserId[result.UserId]
		if player then
			DataService.addCoins(player, coins)
			DataService.recordRound(player, result.Tasks, result.Revives)
			if victory and result.Survived then
				DataService.addWin(player)
			end
			local profile = DataService.peek(player)
			result.Wins = profile and profile.Wins or 0
		end
	end

	Util.log("StatsService", "round scored: %d players, victory=%s", #results, tostring(victory))
	return results
end

function StatsService.clear()
	table.clear(roster)
	for _, player in Players:GetPlayers() do
		player:SetAttribute(StateKeys.Player.RoundTasks, 0)
		player:SetAttribute(StateKeys.Player.RoundRevives, 0)
	end
end

function StatsService.start()
	Players.PlayerRemoving:Connect(function(player)
		roster[player] = nil
	end)
end

return StatsService
