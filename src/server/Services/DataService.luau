--!strict
--[[
	DataService.luau
	--------------------------------------------------------------------------
	Coins, Wins, owned stakes and inventory -- loaded on join, saved on leave.

	Degrades gracefully: if DataStores are unavailable (Studio without API
	access, or a DataStore outage) the service keeps everything in memory for
	the session and warns once. The game stays playable; progress just doesn't
	persist. That matters because you'll do most of your testing in Studio.
	--------------------------------------------------------------------------
]]

local DataStoreService = game:GetService("DataStoreService")
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")

local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
local Config = require(Shared.Config)
local Util = require(Shared.Util)

export type Profile = {
	Coins: number,
	Wins: number,
	RoundsPlayed: number,
	OwnedStakes: { [string]: boolean },
	EquippedStake: string,
	Inventory: { [string]: number },
	LoreFound: { [string]: boolean },
	TotalTasks: number,
	TotalRevives: number,
}

local DataService = {}

local store: DataStore? = nil
local storeAvailable = true
local warnedUnavailable = false

local profiles: { [Player]: Profile } = {}
local loading: { [Player]: boolean } = {}

--==========================================================================
-- Defaults
--==========================================================================

local function defaultProfile(): Profile
	local owned = {}
	if Config.Economy.StartingStake then
		owned[Config.Economy.StartingStake] = true
	end
	return {
		Coins = Config.Economy.StartingCoins,
		Wins = 0,
		RoundsPlayed = 0,
		OwnedStakes = owned,
		EquippedStake = Config.Economy.StartingStake,
		Inventory = {},
		LoreFound = {},
		TotalTasks = 0,
		TotalRevives = 0,
	}
end

--- Fills in anything a saved profile is missing, so adding a field later
--- doesn't break existing players.
local function reconcile(saved: any): Profile
	local profile = defaultProfile()
	if type(saved) ~= "table" then
		return profile
	end

	profile.Coins = tonumber(saved.Coins) or profile.Coins
	profile.Wins = tonumber(saved.Wins) or profile.Wins
	profile.RoundsPlayed = tonumber(saved.RoundsPlayed) or profile.RoundsPlayed
	profile.TotalTasks = tonumber(saved.TotalTasks) or profile.TotalTasks
	profile.TotalRevives = tonumber(saved.TotalRevives) or profile.TotalRevives

	if type(saved.OwnedStakes) == "table" then
		for id, value in saved.OwnedStakes do
			if value and Config.getStakeTier(id) then
				profile.OwnedStakes[id] = true
			end
		end
	end
	if type(saved.Inventory) == "table" then
		for id, count in saved.Inventory do
			if type(count) == "number" and count > 0 then
				profile.Inventory[id] = math.floor(count)
			end
		end
	end
	if type(saved.LoreFound) == "table" then
		for id, value in saved.LoreFound do
			if value then
				profile.LoreFound[id] = true
			end
		end
	end

	-- Never leave a player holding a stake they don't own.
	if not profile.OwnedStakes[saved.EquippedStake] then
		profile.EquippedStake = Config.Economy.StartingStake
	else
		profile.EquippedStake = saved.EquippedStake
	end

	return profile
end

--==========================================================================
-- Store access
--==========================================================================

local function key(player: Player): string
	return `player_{player.UserId}`
end

local function markUnavailable(err: any)
	storeAvailable = false
	if not warnedUnavailable then
		warnedUnavailable = true
		Util.warn(
			"DataService",
			"DataStores unavailable (%s). Progress will not persist this session. "
				.. "In Studio: Game Settings -> Security -> Enable Studio Access to API Services.",
			tostring(err)
		)
	end
end

--- Runs a DataStore call with retries and exponential backoff.
local function withRetry<T>(fn: () -> T): (boolean, T?)
	local delaySeconds = Config.Data.RetryBackoff
	for attempt = 1, Config.Data.MaxRetries do
		local ok, result = pcall(fn)
		if ok then
			return true, result
		end
		if attempt == Config.Data.MaxRetries then
			return false, result :: any
		end
		task.wait(delaySeconds)
		delaySeconds *= 2
	end
	return false, nil
end

--==========================================================================
-- Leaderstats
--==========================================================================

local function buildLeaderstats(player: Player, profile: Profile)
	local leaderstats = player:FindFirstChild("leaderstats")
	if not leaderstats then
		leaderstats = Instance.new("Folder")
		leaderstats.Name = "leaderstats"
		leaderstats.Parent = player
	end

	local coins = leaderstats:FindFirstChild("Coins") :: IntValue?
	if not coins then
		coins = Instance.new("IntValue")
		coins.Name = "Coins"
		coins.Parent = leaderstats
	end
	coins.Value = profile.Coins

	local wins = leaderstats:FindFirstChild("Wins") :: IntValue?
	if not wins then
		wins = Instance.new("IntValue")
		wins.Name = "Wins"
		wins.Parent = leaderstats
	end
	wins.Value = profile.Wins
end

local function syncLeaderstats(player: Player)
	local profile = profiles[player]
	if not profile then
		return
	end
	local leaderstats = player:FindFirstChild("leaderstats")
	if not leaderstats then
		return
	end
	local coins = leaderstats:FindFirstChild("Coins") :: IntValue?
	local wins = leaderstats:FindFirstChild("Wins") :: IntValue?
	if coins then
		coins.Value = profile.Coins
	end
	if wins then
		wins.Value = profile.Wins
	end
end

--==========================================================================
-- Load / save
--==========================================================================

local function load(player: Player)
	loading[player] = true

	local profile = defaultProfile()

	if store and storeAvailable then
		local ok, saved = withRetry(function()
			return (store :: DataStore):GetAsync(key(player))
		end)
		if ok then
			profile = reconcile(saved)
		else
			markUnavailable(saved)
			-- Don't hand a fresh profile to someone whose data merely failed to
			-- load -- they'd overwrite real progress on save. Flag them.
			profile = defaultProfile()
			player:SetAttribute("DataLoadFailed", true)
		end
	end

	if not player.Parent then
		loading[player] = nil
		return
	end

	profiles[player] = profile
	loading[player] = nil
	buildLeaderstats(player, profile)
	Util.log("DataService", "loaded %s (%d coins, %d wins)", player.Name, profile.Coins, profile.Wins)
end

local function save(player: Player)
	local profile = profiles[player]
	if not profile or not store or not storeAvailable then
		return
	end
	if player:GetAttribute("DataLoadFailed") then
		-- Their real data is still out there; writing would clobber it.
		return
	end

	local snapshot = {
		Coins = profile.Coins,
		Wins = profile.Wins,
		RoundsPlayed = profile.RoundsPlayed,
		OwnedStakes = profile.OwnedStakes,
		EquippedStake = profile.EquippedStake,
		Inventory = profile.Inventory,
		LoreFound = profile.LoreFound,
		TotalTasks = profile.TotalTasks,
		TotalRevives = profile.TotalRevives,
	}

	local ok, err = withRetry(function()
		return (store :: DataStore):UpdateAsync(key(player), function()
			return snapshot
		end)
	end)

	if not ok then
		markUnavailable(err)
	else
		Util.log("DataService", "saved %s", player.Name)
	end
end

--==========================================================================
-- Public API
--==========================================================================

--- Waits (up to `timeout`) for a player's profile to finish loading.
function DataService.getProfile(player: Player, timeout: number?): Profile?
	local deadline = os.clock() + (timeout or 10)
	while loading[player] and os.clock() < deadline do
		task.wait(0.1)
	end
	return profiles[player]
end

--- Non-yielding read. Returns nil if the profile isn't ready yet.
function DataService.peek(player: Player): Profile?
	return profiles[player]
end

function DataService.addCoins(player: Player, amount: number): number
	local profile = profiles[player]
	if not profile then
		return 0
	end
	profile.Coins = math.max(0, profile.Coins + amount)
	syncLeaderstats(player)
	return profile.Coins
end

--- Returns true if the player could afford it (and the coins were taken).
function DataService.trySpend(player: Player, amount: number): boolean
	local profile = profiles[player]
	if not profile or profile.Coins < amount then
		return false
	end
	profile.Coins -= amount
	syncLeaderstats(player)
	return true
end

function DataService.addWin(player: Player)
	local profile = profiles[player]
	if not profile then
		return
	end
	profile.Wins += 1
	syncLeaderstats(player)
end

function DataService.recordRound(player: Player, tasks: number, revives: number)
	local profile = profiles[player]
	if not profile then
		return
	end
	profile.RoundsPlayed += 1
	profile.TotalTasks += tasks
	profile.TotalRevives += revives
end

function DataService.grantStake(player: Player, stakeId: string): boolean
	local profile = profiles[player]
	if not profile or not Config.getStakeTier(stakeId) then
		return false
	end
	profile.OwnedStakes[stakeId] = true
	return true
end

function DataService.ownsStake(player: Player, stakeId: string): boolean
	local profile = profiles[player]
	return profile ~= nil and profile.OwnedStakes[stakeId] == true
end

function DataService.setEquippedStake(player: Player, stakeId: string): boolean
	local profile = profiles[player]
	if not profile or not profile.OwnedStakes[stakeId] then
		return false
	end
	profile.EquippedStake = stakeId
	return true
end

function DataService.addItem(player: Player, itemId: string, count: number)
	local profile = profiles[player]
	if not profile then
		return
	end
	profile.Inventory[itemId] = (profile.Inventory[itemId] or 0) + count
	if profile.Inventory[itemId] <= 0 then
		profile.Inventory[itemId] = nil
	end
end

function DataService.consumeItem(player: Player, itemId: string): boolean
	local profile = profiles[player]
	if not profile then
		return false
	end
	local have = profile.Inventory[itemId] or 0
	if have <= 0 then
		return false
	end
	profile.Inventory[itemId] = have - 1
	if profile.Inventory[itemId] <= 0 then
		profile.Inventory[itemId] = nil
	end
	return true
end

function DataService.markLoreFound(player: Player, noteId: string): boolean
	local profile = profiles[player]
	if not profile or profile.LoreFound[noteId] then
		return false
	end
	profile.LoreFound[noteId] = true
	return true
end

--- Serialisable snapshot for sending to the client.
function DataService.toClientPayload(player: Player)
	local profile = profiles[player]
	if not profile then
		return nil
	end
	return {
		Coins = profile.Coins,
		Wins = profile.Wins,
		RoundsPlayed = profile.RoundsPlayed,
		OwnedStakes = profile.OwnedStakes,
		EquippedStake = profile.EquippedStake,
		Inventory = profile.Inventory,
		TotalTasks = profile.TotalTasks,
		TotalRevives = profile.TotalRevives,
	}
end

--==========================================================================
-- Lifecycle
--==========================================================================

function DataService.start()
	local ok, result = pcall(function()
		return DataStoreService:GetDataStore(Config.Data.StoreName)
	end)
	if ok then
		store = result
	else
		markUnavailable(result)
	end

	Players.PlayerAdded:Connect(function(player)
		task.spawn(load, player)
	end)
	for _, player in Players:GetPlayers() do
		task.spawn(load, player)
	end

	Players.PlayerRemoving:Connect(function(player)
		save(player)
		profiles[player] = nil
		loading[player] = nil
	end)

	-- Periodic autosave, staggered so we don't burst the request budget.
	task.spawn(function()
		while true do
			task.wait(Config.Data.AutosaveInterval)
			for _, player in Players:GetPlayers() do
				if profiles[player] then
					task.spawn(save, player)
					task.wait(0.5)
				end
			end
		end
	end)

	game:BindToClose(function()
		if RunService:IsStudio() then
			return
		end
		local pending = 0
		for _, player in Players:GetPlayers() do
			pending += 1
			task.spawn(function()
				save(player)
				pending -= 1
			end)
		end
		local deadline = os.clock() + 20
		while pending > 0 and os.clock() < deadline do
			task.wait(0.1)
		end
	end)
end

return DataService
