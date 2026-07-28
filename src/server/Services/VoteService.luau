--!strict
--[[
	VoteService.luau
	--------------------------------------------------------------------------
	Map voting during the intermission.

	Vote counts live as attributes on ReplicatedStorage.DollysHome.State.Votes,
	one per map id, so the tally updates on every client the instant it changes
	without a single RemoteEvent firing.
	--------------------------------------------------------------------------
]]

local Players = game:GetService("Players")

local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
local Config = require(Shared.Config)
local Net = require(Shared.Net)
local StateKeys = require(Shared.StateKeys)
local Util = require(Shared.Util)

local VoteService = {}

local votes: { [Player]: string } = {}
local open = false
local rng = Random.new()

--==========================================================================
-- Tally
--==========================================================================

local function publishTally()
	local counts: { [string]: number } = {}
	for _, map in Config.getEnabledMaps() do
		counts[map.Id] = 0
	end
	for _, mapId in votes do
		if counts[mapId] ~= nil then
			counts[mapId] += 1
		end
	end

	local folder = Net.getVotesFolder()
	for mapId, count in counts do
		if folder:GetAttribute(mapId) ~= count then
			folder:SetAttribute(mapId, count)
		end
	end
end

local function isVotable(mapId: string): boolean
	for _, map in Config.getEnabledMaps() do
		if map.Id == mapId then
			return true
		end
	end
	return false
end

--==========================================================================
-- Public
--==========================================================================

function VoteService.openVoting()
	table.clear(votes)
	open = true
	Net.setStateValue(StateKeys.Game.VotingOpen, true)
	publishTally()
end

--- Closes voting and returns the winning map id. Ties break randomly.
function VoteService.closeVoting(): string
	open = false
	Net.setStateValue(StateKeys.Game.VotingOpen, false)

	local enabled = Config.getEnabledMaps()
	if #enabled == 0 then
		Util.warn("VoteService", "no maps are enabled in Config.Maps")
		return "TheHouse"
	end

	local counts: { [string]: number } = {}
	for _, map in enabled do
		counts[map.Id] = 0
	end
	for _, mapId in votes do
		if counts[mapId] ~= nil then
			counts[mapId] += 1
		end
	end

	local best = -1
	local leaders: { string } = {}
	for _, map in enabled do
		local count = counts[map.Id]
		if count > best then
			best = count
			leaders = { map.Id }
		elseif count == best then
			table.insert(leaders, map.Id)
		end
	end

	local winner = Util.pick(leaders, rng) or enabled[1].Id
	Net.setStateValue(StateKeys.Game.NextMapId, winner)
	Util.log("VoteService", "map vote won by %s (%d votes)", winner, best)
	return winner
end

function VoteService.getVote(player: Player): string?
	return votes[player]
end

function VoteService.isOpen(): boolean
	return open
end

--==========================================================================
-- Lifecycle
--==========================================================================

function VoteService.start()
	Net.Events.CastVote.OnServerEvent:Connect(function(player, mapId)
		if not open or type(mapId) ~= "string" or not isVotable(mapId) then
			return
		end
		-- Voting again just moves your vote.
		votes[player] = mapId
		publishTally()
	end)

	Players.PlayerRemoving:Connect(function(player)
		if votes[player] then
			votes[player] = nil
			publishTally()
		end
	end)

	publishTally()
end

return VoteService
