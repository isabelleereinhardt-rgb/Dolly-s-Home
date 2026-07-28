--!strict
--[[
	ShopService.luau
	--------------------------------------------------------------------------
	Stakes (permanent unlocks) and potions (consumables), bought with coins in
	the lobby.

	The design doc flags the shop as "later", so this is deliberately minimal:
	server-validated purchases, an inventory that persists, and a catalogue the
	client renders. It is not a storefront with rotating stock and bundles --
	when you want that, the catalogue below is the only thing that has to grow.
	--------------------------------------------------------------------------
]]

local Players = game:GetService("Players")

local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
local Config = require(Shared.Config)
local Net = require(Shared.Net)
local StateKeys = require(Shared.StateKeys)
local Util = require(Shared.Util)

local DataService = require(script.Parent.DataService)
local MapService = require(script.Parent.MapService)
local PlayerService = require(script.Parent.PlayerService)
local RevivalService = require(script.Parent.RevivalService)
local TeamService = require(script.Parent.TeamService)

local ShopService = {}

--==========================================================================
-- Catalogue
--==========================================================================

--- Everything buyable, built from Config so prices live in one place.
function ShopService.getCatalogue()
	local stakes = {}
	for _, tier in Config.Stakes.Tiers do
		table.insert(stakes, {
			Id = tier.Id,
			Kind = "Stake",
			Name = tier.Name,
			Rarity = tier.Id,
			Cost = tier.Cost,
			Damage = tier.Damage,
			StunSeconds = tier.StunSeconds,
			Colour = tier.Color,
			Order = tier.Order,
			Description = `{tier.Damage} damage, stuns for {tier.StunSeconds} seconds.`,
		})
	end
	table.sort(stakes, function(a, b)
		return a.Order < b.Order
	end)

	local consumables = {
		{
			Id = Config.Shop.SpeedPotion.Id,
			Kind = "Consumable",
			Name = Config.Shop.SpeedPotion.Name,
			Cost = Config.Shop.SpeedPotion.Cost,
			Description = Config.Shop.SpeedPotion.Description,
			Colour = Color3.fromRGB(110, 180, 255),
		},
		{
			Id = Config.Shop.HealthPotion.Id,
			Kind = "Consumable",
			Name = Config.Shop.HealthPotion.Name,
			Cost = Config.Shop.HealthPotion.Cost,
			Description = Config.Shop.HealthPotion.Description,
			Colour = Color3.fromRGB(120, 230, 150),
		},
	}

	return { Stakes = stakes, Consumables = consumables }
end

--==========================================================================
-- Purchasing
--==========================================================================

local function findStake(id: string)
	return Config.getStakeTier(id)
end

local function findConsumable(id: string)
	if id == Config.Shop.SpeedPotion.Id then
		return Config.Shop.SpeedPotion
	elseif id == Config.Shop.HealthPotion.Id then
		return Config.Shop.HealthPotion
	end
	return nil
end

--- Returns (success, message).
function ShopService.purchase(player: Player, itemId: string): (boolean, string)
	if type(itemId) ~= "string" then
		return false, "Unknown item."
	end

	local profile = DataService.peek(player)
	if not profile then
		return false, "Your data is still loading."
	end

	local stake = findStake(itemId)
	if stake then
		if profile.OwnedStakes[itemId] then
			return false, "You already own that."
		end
		if not DataService.trySpend(player, stake.Cost) then
			return false, `Not enough coins ({stake.Cost} needed).`
		end
		DataService.grantStake(player, itemId)
		DataService.setEquippedStake(player, itemId)
		player:SetAttribute(StateKeys.Player.EquippedStake, itemId)
		return true, `{stake.Name} unlocked and equipped.`
	end

	local consumable = findConsumable(itemId)
	if consumable then
		if not DataService.trySpend(player, consumable.Cost) then
			return false, `Not enough coins ({consumable.Cost} needed).`
		end
		DataService.addItem(player, itemId, 1)
		return true, `{consumable.Name} added to your satchel.`
	end

	return false, "Unknown item."
end

--==========================================================================
-- Using consumables
--==========================================================================

function ShopService.useConsumable(player: Player, itemId: string): (boolean, string)
	local consumable = findConsumable(itemId)
	if not consumable then
		return false, "You can't use that."
	end

	if itemId == Config.Shop.HealthPotion.Id then
		if not TeamService.isInRound(player) then
			return false, "Only during a round."
		end
		local _, humanoid = Util.getCharacterParts(player)
		local isDowned = RevivalService.isDowned(player)
		if humanoid and humanoid.Health >= humanoid.MaxHealth and not isDowned then
			return false, "You're already at full health."
		end
		if not DataService.consumeItem(player, itemId) then
			return false, "You don't have one."
		end
		RevivalService.fullHeal(player)
		return true, "Restored to full health."
	end

	if itemId == Config.Shop.SpeedPotion.Id then
		if not DataService.consumeItem(player, itemId) then
			return false, "You don't have one."
		end
		PlayerService.applySpeedPotion(player, Config.Shop.SpeedPotion.DurationSeconds)
		return true, `Double speed for {math.floor(Config.Shop.SpeedPotion.DurationSeconds / 60)} minutes.`
	end

	return false, "You can't use that."
end

--==========================================================================
-- Lobby stand
--==========================================================================

local function attachStandPrompt()
	local lobby = MapService.getLobby()
	if not lobby then
		return
	end

	for _, descendant in lobby:GetDescendants() do
		if descendant:IsA("BasePart") and descendant:GetAttribute("DollysHomeShop") then
			if descendant:FindFirstChildOfClass("ProximityPrompt") then
				continue
			end
			local prompt = Instance.new("ProximityPrompt")
			prompt.Name = "ShopPrompt"
			prompt.ActionText = "Browse"
			prompt.ObjectText = "Peddler's Cart"
			prompt.HoldDuration = 0
			prompt.MaxActivationDistance = 12
			prompt.RequiresLineOfSight = false
			prompt.Parent = descendant

			prompt.Triggered:Connect(function(player)
				Net.fire(player, "Announce", { Kind = "OpenShop" })
			end)
		end
	end
end

--==========================================================================
-- Lifecycle
--==========================================================================

function ShopService.start()
	Net.Functions.GetProfile.OnServerInvoke = function(player)
		return {
			Profile = DataService.toClientPayload(player),
			Catalogue = ShopService.getCatalogue(),
		}
	end

	Net.Events.Purchase.OnServerEvent:Connect(function(player, itemId)
		local ok, message = ShopService.purchase(player, itemId)
		Net.fire(player, "Announce", {
			Kind = ok and "ShopSuccess" or "ShopError",
			Text = message,
			Profile = DataService.toClientPayload(player),
		})
	end)

	Net.Events.UseConsumable.OnServerEvent:Connect(function(player, itemId)
		if type(itemId) ~= "string" then
			return
		end
		local ok, message = ShopService.useConsumable(player, itemId)
		Net.fire(player, "Announce", {
			Kind = ok and "ShopSuccess" or "ShopError",
			Text = message,
			Profile = DataService.toClientPayload(player),
		})
	end)

	Players.PlayerAdded:Connect(function(player)
		task.spawn(function()
			DataService.getProfile(player, 15)
			local profile = DataService.peek(player)
			if profile then
				player:SetAttribute(StateKeys.Player.EquippedStake, profile.EquippedStake)
			end
		end)
	end)

	task.defer(attachStandPrompt)
end

return ShopService
