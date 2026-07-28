--!strict
--[[
	HidingService.luau
	--------------------------------------------------------------------------
	Lockers, beds, tables, closets and ducts.

	Hiding is a genuine trade-off rather than a safe button: you stop making
	noise and killers can't target you, but you can't do tasks, you can't see
	much, and sitting in one spot too long makes the family suspicious of it --
	which raises the odds a passing killer tears the door open.
	--------------------------------------------------------------------------
]]

local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")

local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
local Config = require(Shared.Config)
local Net = require(Shared.Net)
local StateKeys = require(Shared.StateKeys)
local Tags = require(Shared.Tags)
local Util = require(Shared.Util)

local NoiseService = require(script.Parent.NoiseService)
local TeamService = require(script.Parent.TeamService)

local HidingService = {}

type HideRecord = {
	Spot: BasePart,
	EnteredAt: number,
	RestoreTransparency: { [BasePart]: number },
	RestoreCollide: { [BasePart]: boolean },
	RestoreCFrame: CFrame,
}

local hidden: { [Player]: HideRecord } = {}
local occupants: { [BasePart]: { Player } } = {}
local lastExit: { [Player]: number } = {}
local prompts: { [BasePart]: ProximityPrompt } = {}

--==========================================================================
-- Queries
--==========================================================================

function HidingService.isHidden(player: Player): boolean
	return hidden[player] ~= nil
end

function HidingService.getSpot(player: Player): BasePart?
	local record = hidden[player]
	return record and record.Spot or nil
end

function HidingService.getOccupants(spot: BasePart): { Player }
	return occupants[spot] or {}
end

--- Seconds the player has been in their current spot, or 0.
function HidingService.getHideDuration(player: Player): number
	local record = hidden[player]
	if not record then
		return 0
	end
	return Util.now() - record.EnteredAt
end

--- A spot is "suspicious" once someone has camped it past the threshold.
--- KillerAgent weights its searches toward these.
function HidingService.isSpotSuspicious(spot: BasePart): boolean
	for _, player in occupants[spot] or {} do
		if HidingService.getHideDuration(player) >= Config.Killer.LongHideSuspicionSeconds then
			return true
		end
	end
	return false
end

--- Hiding spots within `radius` of a position, suspicious ones first.
function HidingService.getSpotsNear(position: Vector3, radius: number): { BasePart }
	local found = {}
	for spot in occupants do
		if spot.Parent and (spot.Position - position).Magnitude <= radius then
			table.insert(found, spot)
		end
	end
	table.sort(found, function(a, b)
		local aSus = HidingService.isSpotSuspicious(a) and 1 or 0
		local bSus = HidingService.isSpotSuspicious(b) and 1 or 0
		if aSus ~= bSus then
			return aSus > bSus
		end
		return (a.Position - position).Magnitude < (b.Position - position).Magnitude
	end)
	return found
end

--==========================================================================
-- Enter / exit
--==========================================================================

local function characterParts(character: Model): { BasePart }
	local parts = {}
	for _, descendant in character:GetDescendants() do
		if descendant:IsA("BasePart") then
			table.insert(parts, descendant)
		end
	end
	return parts
end

local function enter(player: Player, spot: BasePart): boolean
	if hidden[player] then
		return false
	end
	if not TeamService.isAlive(player) then
		return false
	end

	local exitedAt = lastExit[player]
	if exitedAt and Util.now() - exitedAt < Config.Hiding.ExitDelay then
		return false
	end

	local character, humanoid, root = Util.getCharacterParts(player)
	if not character or not humanoid or not root then
		return false
	end

	-- Don't let a player hide across the map from the prompt.
	if (root.Position - spot.Position).Magnitude > 16 then
		return false
	end

	local record: HideRecord = {
		Spot = spot,
		EnteredAt = Util.now(),
		RestoreTransparency = {},
		RestoreCollide = {},
		RestoreCFrame = root.CFrame,
	}

	for _, bodyPart in characterParts(character) do
		record.RestoreTransparency[bodyPart] = bodyPart.Transparency
		record.RestoreCollide[bodyPart] = bodyPart.CanCollide
		bodyPart.Transparency = 1
		bodyPart.CanCollide = false
	end

	-- Tuck them inside the prop and pin them there.
	root.CFrame = CFrame.new(spot.Position)
	root.Anchored = true
	humanoid.WalkSpeed = 0
	humanoid.JumpPower = 0
	humanoid:SetStateEnabled(Enum.HumanoidStateType.Jumping, false)

	hidden[player] = record
	occupants[spot] = occupants[spot] or {}
	table.insert(occupants[spot], player)

	player:SetAttribute(StateKeys.Player.Hidden, true)
	player:SetAttribute(StateKeys.Player.HidingKind, spot:GetAttribute("Kind") or "Spot")

	NoiseService.add(player, Config.Noise.Actions.EnterHidingSpot, "hide")
	Util.log("HidingService", "%s hid in %s", player.Name, spot.Name)
	return true
end

local function exit(player: Player, discovered: boolean?): boolean
	local record = hidden[player]
	if not record then
		return false
	end

	hidden[player] = nil
	lastExit[player] = Util.now()

	local list = occupants[record.Spot]
	if list then
		local index = table.find(list, player)
		if index then
			table.remove(list, index)
		end
	end

	local character, humanoid, root = Util.getCharacterParts(player)
	if character then
		for bodyPart, transparency in record.RestoreTransparency do
			if bodyPart.Parent then
				bodyPart.Transparency = transparency
			end
		end
		for bodyPart, canCollide in record.RestoreCollide do
			if bodyPart.Parent then
				bodyPart.CanCollide = canCollide
			end
		end
	end

	if root then
		root.Anchored = false
		-- Step out of the prop rather than out into a wall.
		local offset = record.Spot.CFrame.LookVector * 4
		root.CFrame = CFrame.new(record.Spot.Position + offset + Vector3.new(0, 1, 0))
	end

	if humanoid then
		humanoid.WalkSpeed = Config.Player.WalkSpeed
		humanoid.JumpPower = Config.Player.JumpPower
		humanoid:SetStateEnabled(Enum.HumanoidStateType.Jumping, true)
	end

	player:SetAttribute(StateKeys.Player.Hidden, false)
	player:SetAttribute(StateKeys.Player.HidingKind, "")

	if discovered then
		-- Being found is loud: you scramble out, and everything hears it.
		NoiseService.add(player, Config.Noise.Actions.OpenDoor * 2, "discovered")
		Net.fire(player, "Announce", {
			Kind = "Danger",
			Text = "You've been found!",
		})
	end

	return true
end

--- Public: yank a player out of hiding (a killer tore the door open).
function HidingService.forceOut(player: Player)
	exit(player, true)
end

--- Public: is anyone hiding in this spot right now?
function HidingService.searchSpot(spot: BasePart): Player?
	local list = occupants[spot]
	if not list or #list == 0 then
		return nil
	end
	local found = list[1]
	HidingService.forceOut(found)
	return found
end

--- Public: everyone out (round end, or a wipe).
function HidingService.releaseAll()
	for player in hidden do
		exit(player, false)
	end
end

--==========================================================================
-- Prompt wiring
--==========================================================================

local function attachPrompt(spot: Instance)
	if not spot:IsA("BasePart") or prompts[spot] then
		return
	end

	-- CollectionService returns tagged instances anywhere under `game`, which
	-- includes the map templates sitting in ServerStorage. Those must be left
	-- alone: prompting a template would do nothing useful, and the prompt would
	-- then be cloned into the live map alongside the one we add here.
	if not spot:IsDescendantOf(workspace) then
		return
	end

	-- A hand-built map may already carry a prompt from a previous session's
	-- template edit. Clear it so we never end up with two.
	local stale = spot:FindFirstChild("HidePrompt")
	if stale then
		stale:Destroy()
	end

	local kind = spot:GetAttribute("Kind") or "Spot"
	local verb = ({
		Locker = "Hide in Locker",
		Closet = "Hide in Closet",
		Bed = "Hide Under Bed",
		Table = "Hide Under Table",
		Duct = "Crawl into Duct",
		Bathtub = "Hide in Bathtub",
		Barrel = "Hide in Barrel",
	})[kind] or "Hide"

	local prompt = Instance.new("ProximityPrompt")
	prompt.Name = "HidePrompt"
	prompt.ActionText = verb
	prompt.ObjectText = "Hiding Spot"
	prompt.HoldDuration = Config.Hiding.EnterDuration
	prompt.MaxActivationDistance = 10
	prompt.RequiresLineOfSight = false
	prompt.Parent = spot

	prompt.Triggered:Connect(function(player)
		if hidden[player] then
			exit(player, false)
		else
			enter(player, spot)
		end
	end)

	occupants[spot] = occupants[spot] or {}
	prompts[spot] = prompt
end

local function detachPrompt(spot: Instance)
	if not spot:IsA("BasePart") then
		return
	end
	local prompt = prompts[spot]
	if prompt then
		prompt:Destroy()
		prompts[spot] = nil
	end
	for _, player in occupants[spot] or {} do
		exit(player, false)
	end
	occupants[spot] = nil
end

--==========================================================================
-- Lifecycle
--==========================================================================

function HidingService.start()
	for _, spot in CollectionService:GetTagged(Tags.HidingSpot) do
		attachPrompt(spot)
	end
	CollectionService:GetInstanceAddedSignal(Tags.HidingSpot):Connect(attachPrompt)
	CollectionService:GetInstanceRemovedSignal(Tags.HidingSpot):Connect(detachPrompt)

	-- Exiting via keypress, for players who'd rather not hunt for the prompt.
	Net.Events.RequestHide.OnServerEvent:Connect(function(player)
		if hidden[player] then
			exit(player, false)
		end
	end)

	Players.PlayerRemoving:Connect(function(player)
		local record = hidden[player]
		if record then
			local list = occupants[record.Spot]
			if list then
				local index = table.find(list, player)
				if index then
					table.remove(list, index)
				end
			end
		end
		hidden[player] = nil
		lastExit[player] = nil
	end)

	-- If a character is removed while hidden (respawn, elimination) the record
	-- would leak and the spot would look permanently occupied.
	Players.PlayerAdded:Connect(function(player)
		player.CharacterRemoving:Connect(function()
			if hidden[player] then
				exit(player, false)
			end
		end)
	end)
	for _, player in Players:GetPlayers() do
		player.CharacterRemoving:Connect(function()
			if hidden[player] then
				exit(player, false)
			end
		end)
	end
end

return HidingService
