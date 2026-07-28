--!strict
--[[
	ModalController.luau
	--------------------------------------------------------------------------
	The four things that take over the screen: lore notes, the grandfather clock
	minigame, Ava's questions, and the shop.

	One modal at a time, one shared frame, one close path. Modals opened during
	a round do NOT pause anything -- reading a note while Barbara is two rooms
	away is meant to be a bad idea.
	--------------------------------------------------------------------------
]]

local Players = game:GetService("Players")
local TweenService = game:GetService("TweenService")

local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
local Config = require(Shared.Config)
local Net = require(Shared.Net)

local Theme = require(script.Parent.Parent.UI.Theme)
local Widgets = require(script.Parent.Parent.UI.Widgets)

local player = Players.LocalPlayer

local ModalController = {}

local gui: ScreenGui
local backdrop: TextButton
local frame: Frame
local titleLabel: TextLabel
local bodyContainer: Frame
local closeButton: TextButton

local isOpen = false

--==========================================================================
-- Shell
--==========================================================================

local function build()
	gui = Widgets.new("ScreenGui", {
		Name = "DollysHomeModal",
		ResetOnSpawn = false,
		IgnoreGuiInset = true,
		DisplayOrder = 25,
		Enabled = false,
		Parent = player:WaitForChild("PlayerGui"),
	}) :: ScreenGui

	backdrop = Widgets.new("TextButton", {
		Name = "Backdrop",
		Size = UDim2.fromScale(1, 1),
		BackgroundColor3 = Theme.Colour.Backdrop,
		BackgroundTransparency = 0.4,
		BorderSizePixel = 0,
		Text = "",
		AutoButtonColor = false,
		Parent = gui,
	}) :: TextButton

	frame = Widgets.panel({
		Name = "Frame",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.new(0.5, 0, 0.5, 0),
		Size = UDim2.new(0, 560, 0, 380),
		BackgroundTransparency = 0.02,
		Parent = gui,
	})
	Widgets.padding(Theme.Padding.Loose).Parent = frame

	titleLabel = Widgets.label("", {
		Size = UDim2.new(1, -40, 0, 28),
		Font = Theme.Font.Heading,
		TextSize = Theme.TextSize.Title,
		TextColor3 = Theme.Colour.Gold,
		Parent = frame,
	})

	closeButton = Widgets.button("✕", {
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.new(1, 0, 0, 0),
		Size = UDim2.fromOffset(32, 32),
		BackgroundColor3 = Theme.Colour.PanelSunken,
		TextSize = Theme.TextSize.Body,
		Parent = frame,
	})

	bodyContainer = Widgets.new("Frame", {
		Name = "Body",
		Position = UDim2.new(0, 0, 0, 40),
		Size = UDim2.new(1, 0, 1, -40),
		BackgroundTransparency = 1,
		Parent = frame,
	}) :: Frame

	closeButton.MouseButton1Click:Connect(function()
		ModalController.close()
	end)
	backdrop.MouseButton1Click:Connect(function()
		ModalController.close()
	end)
end

local function openShell(title: string, height: number)
	bodyContainer:ClearAllChildren()
	titleLabel.Text = title
	frame.Size = UDim2.new(0, 560, 0, height)
	gui.Enabled = true
	isOpen = true

	frame.Position = UDim2.new(0.5, 0, 0.54, 0)
	backdrop.BackgroundTransparency = 1
	TweenService:Create(backdrop, Theme.Tween.Fast, { BackgroundTransparency = 0.4 }):Play()
	TweenService:Create(frame, Theme.Tween.Normal, { Position = UDim2.new(0.5, 0, 0.5, 0) }):Play()
end

function ModalController.close()
	if not isOpen then
		return
	end
	isOpen = false
	gui.Enabled = false
	bodyContainer:ClearAllChildren()
end

function ModalController.isOpen(): boolean
	return isOpen
end

--==========================================================================
-- Lore notes
--==========================================================================

function ModalController.showLoreNote(payload: any)
	openShell(payload.Title or "A scrap of paper", 340)

	Widgets.label(payload.Author and `-- {payload.Author}` or "", {
		Size = UDim2.new(1, 0, 0, 20),
		Font = Theme.Font.Body,
		TextSize = Theme.TextSize.Small,
		TextColor3 = Theme.Colour.TextFaint,
		Parent = bodyContainer,
	})

	local body = Widgets.label(payload.Body or "", {
		Position = UDim2.new(0, 0, 0, 28),
		Size = UDim2.new(1, 0, 1, -70),
		Font = Theme.Font.Flavour,
		TextSize = Theme.TextSize.Body,
		TextColor3 = Theme.Colour.Bone,
		TextWrapped = true,
		TextYAlignment = Enum.TextYAlignment.Top,
		LineHeight = 1.3,
		Parent = bodyContainer,
	})
	body.RichText = false

	local dismiss = Widgets.button("Put it back", {
		AnchorPoint = Vector2.new(0.5, 1),
		Position = UDim2.new(0.5, 0, 1, 0),
		Size = UDim2.new(0, 180, 0, 36),
		Parent = bodyContainer,
	})
	dismiss.MouseButton1Click:Connect(ModalController.close)
end

--==========================================================================
-- Grandfather clock
--==========================================================================

--[[
	Hour and minute pickers rather than draggable hands.

	Dragging a clock hand is charming on desktop and unusable on a phone, and
	the tension here should come from standing still in a dark dining room for
	eight seconds, not from fighting a touch target.
]]
function ModalController.showClock(payload: any)
	local targetHour = payload.TargetHour or 12
	local targetMinute = payload.TargetMinute or 0

	openShell("The Grandfather Clock", 400)

	Widgets.label(
		`It stopped at the hour she died. Set the hands to {string.format("%d:%02d", targetHour, targetMinute)}.`,
		{
			Size = UDim2.new(1, 0, 0, 36),
			Font = Theme.Font.Flavour,
			TextSize = Theme.TextSize.Small,
			TextColor3 = Theme.Colour.Bone,
			TextWrapped = true,
			Parent = bodyContainer,
		}
	)

	local selectedHour = 12
	local selectedMinute = 0

	local readout = Widgets.label("12:00", {
		Position = UDim2.new(0, 0, 0, 40),
		Size = UDim2.new(1, 0, 0, 42),
		Font = Theme.Font.Numeric,
		TextSize = 36,
		TextColor3 = Theme.Colour.Gold,
		TextXAlignment = Enum.TextXAlignment.Center,
		Parent = bodyContainer,
	})

	local function refresh()
		readout.Text = string.format("%d:%02d", selectedHour, selectedMinute)
	end

	--- A row of small selector buttons. `format` matters: minutes need "%02d"
	--- so five past reads as :05 rather than :5.
	local function pickerRow(caption: string, y: number, values: { number }, format: string, onPick: (number) -> ())
		Widgets.label(caption, {
			Position = UDim2.new(0, 0, 0, y),
			Size = UDim2.new(1, 0, 0, 16),
			Font = Theme.Font.Heading,
			TextSize = Theme.TextSize.Tiny,
			TextColor3 = Theme.Colour.TextDim,
			Parent = bodyContainer,
		})

		local row = Widgets.new("Frame", {
			Position = UDim2.new(0, 0, 0, y + 18),
			Size = UDim2.new(1, 0, 0, 30),
			BackgroundTransparency = 1,
			Parent = bodyContainer,
		})

		local buttons: { TextButton } = {}
		local width = 1 / #values

		for index, value in values do
			local button = Widgets.button(string.format(format, value), {
				Position = UDim2.new(width * (index - 1), 2, 0, 0),
				Size = UDim2.new(width, -4, 1, 0),
				BackgroundColor3 = Theme.Colour.PanelSunken,
				TextSize = Theme.TextSize.Small,
				Parent = row,
			})
			buttons[index] = button

			button.MouseButton1Click:Connect(function()
				onPick(value)
				for otherIndex, other in buttons do
					other.BackgroundColor3 = otherIndex == index and Theme.Colour.PanelRaised
						or Theme.Colour.PanelSunken
				end
				refresh()
			end)
		end
	end

	local hours = {}
	for hour = 1, 12 do
		table.insert(hours, hour)
	end
	local minutes = {}
	for step = 0, 11 do
		table.insert(minutes, step * 5)
	end

	pickerRow("HOUR", 92, hours, "%d", function(value)
		selectedHour = value
	end)
	pickerRow("MINUTE", 148, minutes, "%02d", function(value)
		selectedMinute = value
	end)

	Widgets.label(
		"It will chime when you get it right. Everything in the house will hear it.",
		{
			Position = UDim2.new(0, 0, 0, 208),
			Size = UDim2.new(1, 0, 0, 30),
			Font = Theme.Font.Flavour,
			TextSize = Theme.TextSize.Tiny,
			TextColor3 = Theme.Colour.CrimsonBright,
			TextWrapped = true,
			TextXAlignment = Enum.TextXAlignment.Center,
			Parent = bodyContainer,
		}
	)

	local confirm = Widgets.button("Set the hands", {
		AnchorPoint = Vector2.new(0.5, 1),
		Position = UDim2.new(0.5, 0, 1, 0),
		Size = UDim2.new(0, 200, 0, 38),
		BackgroundColor3 = Theme.Colour.PanelRaised,
		Parent = bodyContainer,
	})
	confirm.MouseButton1Click:Connect(function()
		Net.Events.SubmitClock:FireServer(selectedHour, selectedMinute)
		ModalController.close()
	end)

	refresh()
end

--==========================================================================
-- Ava
--==========================================================================

function ModalController.showAva(question: any)
	openShell("Ava", 360)

	Widgets.label(question.Text or "", {
		Size = UDim2.new(1, 0, 0, 96),
		Font = Theme.Font.Flavour,
		TextSize = Theme.TextSize.Body,
		TextColor3 = Theme.Colour.Ghost,
		TextWrapped = true,
		TextYAlignment = Enum.TextYAlignment.Top,
		LineHeight = 1.3,
		Parent = bodyContainer,
	})

	local list = Widgets.new("Frame", {
		Position = UDim2.new(0, 0, 0, 104),
		Size = UDim2.new(1, 0, 1, -104),
		BackgroundTransparency = 1,
		Parent = bodyContainer,
	})
	Widgets.list(Enum.FillDirection.Vertical, 8).Parent = list

	for index, option in question.Options or {} do
		local button = Widgets.button(option.Text, {
			Size = UDim2.new(1, 0, 0, 42),
			BackgroundColor3 = Theme.Colour.PanelSunken,
			TextSize = Theme.TextSize.Small,
			TextXAlignment = Enum.TextXAlignment.Left,
			LayoutOrder = index,
			Parent = list,
		})
		Widgets.padding(Theme.Padding.Normal, { Top = 0, Bottom = 0 }).Parent = button

		button.MouseButton1Click:Connect(function()
			Net.Events.AvaRespond:FireServer(question.Id, option.Id)
			-- She never argues with the answer.
			bodyContainer:ClearAllChildren()
			Widgets.label("She looks at you for a long moment, and says nothing at all.", {
				Size = UDim2.new(1, 0, 1, -50),
				Font = Theme.Font.Flavour,
				TextSize = Theme.TextSize.Body,
				TextColor3 = Theme.Colour.Ghost,
				TextWrapped = true,
				TextXAlignment = Enum.TextXAlignment.Center,
				Parent = bodyContainer,
			})
			task.delay(3, ModalController.close)
		end)
	end
end

--==========================================================================
-- Shop
--==========================================================================

local function buildShopRow(item: any, owned: boolean, coins: number, parent: Instance, layoutOrder: number)
	local row = Widgets.panel({
		Size = UDim2.new(1, -8, 0, 60),
		BackgroundColor3 = Theme.Colour.PanelSunken,
		BackgroundTransparency = 0.15,
		LayoutOrder = layoutOrder,
		Parent = parent,
	})
	Widgets.padding(Theme.Padding.Normal, { Top = 8, Bottom = 8 }).Parent = row

	local accent = item.Colour or Theme.Colour.Text
	if item.Rarity then
		accent = Theme.rarityColour(item.Rarity)
	end

	Widgets.label(item.Name, {
		Size = UDim2.new(1, -140, 0, 20),
		Font = Theme.Font.Heading,
		TextSize = Theme.TextSize.Body,
		TextColor3 = accent,
		Parent = row,
	})

	Widgets.label(item.Description or "", {
		Position = UDim2.new(0, 0, 0, 22),
		Size = UDim2.new(1, -140, 0, 22),
		TextSize = Theme.TextSize.Tiny,
		TextColor3 = Theme.Colour.TextDim,
		TextWrapped = true,
		Parent = row,
	})

	local affordable = coins >= item.Cost
	local label = owned and "Owned" or `{item.Cost} coins`

	local button = Widgets.button(label, {
		AnchorPoint = Vector2.new(1, 0.5),
		Position = UDim2.new(1, 0, 0.5, 0),
		Size = UDim2.new(0, 120, 0, 34),
		BackgroundColor3 = owned and Theme.Colour.PanelSunken or Theme.Colour.PanelRaised,
		TextColor3 = owned and Theme.Colour.TextFaint
			or (affordable and Theme.Colour.Gold or Theme.Colour.TextFaint),
		TextSize = Theme.TextSize.Small,
		Parent = row,
	})

	if not owned then
		button.MouseButton1Click:Connect(function()
			Net.Events.Purchase:FireServer(item.Id)
			task.delay(0.3, function()
				if isOpen then
					ModalController.showShop()
				end
			end)
		end)
	end
end

function ModalController.showShop()
	local ok, data = pcall(function()
		return Net.Functions.GetProfile:InvokeServer()
	end)

	if not ok or not data or not data.Profile then
		openShell("Peddler's Cart", 200)
		Widgets.label("The peddler isn't here yet. Try again in a moment.", {
			Size = UDim2.new(1, 0, 1, 0),
			TextColor3 = Theme.Colour.TextDim,
			TextWrapped = true,
			Parent = bodyContainer,
		})
		return
	end

	local profile = data.Profile
	local catalogue = data.Catalogue

	openShell("Peddler's Cart", 460)

	Widgets.label(`Your coins: {profile.Coins}`, {
		Size = UDim2.new(1, 0, 0, 22),
		Font = Theme.Font.Numeric,
		TextSize = Theme.TextSize.Body,
		TextColor3 = Theme.Colour.Gold,
		Parent = bodyContainer,
	})

	local scroll = Widgets.new("ScrollingFrame", {
		Position = UDim2.new(0, 0, 0, 28),
		Size = UDim2.new(1, 0, 1, -28),
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		ScrollBarThickness = 4,
		ScrollBarImageColor3 = Theme.Colour.Divider,
		CanvasSize = UDim2.new(),
		AutomaticCanvasSize = Enum.AutomaticSize.Y,
		Parent = bodyContainer,
	})
	Widgets.list(Enum.FillDirection.Vertical, 6).Parent = scroll

	local order = 0

	local function heading(text: string)
		order += 1
		Widgets.label(text, {
			Size = UDim2.new(1, 0, 0, 22),
			Font = Theme.Font.Heading,
			TextSize = Theme.TextSize.Small,
			TextColor3 = Theme.Colour.TextDim,
			LayoutOrder = order,
			Parent = scroll,
		})
	end

	heading("STAKES")
	for _, item in catalogue.Stakes or {} do
		order += 1
		buildShopRow(item, profile.OwnedStakes[item.Id] == true, profile.Coins, scroll, order)
	end

	heading("CONSUMABLES")
	for _, item in catalogue.Consumables or {} do
		order += 1
		local held = profile.Inventory[item.Id] or 0
		local copy = table.clone(item)
		if held > 0 then
			copy.Description = `{item.Description}  (you have {held})`
		end
		buildShopRow(copy, false, profile.Coins, scroll, order)
	end

	heading("EQUIPPED")
	order += 1
	local equipRow = Widgets.new("Frame", {
		Size = UDim2.new(1, -8, 0, 40),
		BackgroundTransparency = 1,
		LayoutOrder = order,
		Parent = scroll,
	})
	Widgets.list(Enum.FillDirection.Horizontal, 6).Parent = equipRow

	for _, tier in Config.Stakes.Tiers do
		if profile.OwnedStakes[tier.Id] then
			local isEquipped = profile.EquippedStake == tier.Id
			local button = Widgets.button(tier.Id, {
				Size = UDim2.new(0, 118, 1, 0),
				BackgroundColor3 = isEquipped and Theme.Colour.PanelRaised or Theme.Colour.PanelSunken,
				TextColor3 = isEquipped and Theme.rarityColour(tier.Id) or Theme.Colour.TextDim,
				TextSize = Theme.TextSize.Small,
				Parent = equipRow,
			})
			button.MouseButton1Click:Connect(function()
				Net.Events.EquipStake:FireServer(tier.Id)
				task.delay(0.25, function()
					if isOpen then
						ModalController.showShop()
					end
				end)
			end)
		end
	end
end

--==========================================================================
-- Lifecycle
--==========================================================================

function ModalController.start()
	build()

	Net.Events.LoreNoteRead.OnClientEvent:Connect(function(payload)
		ModalController.showLoreNote(payload)
	end)

	Net.Events.AvaDialogue.OnClientEvent:Connect(function(question)
		ModalController.showAva(question)
	end)

	Net.Events.Announce.OnClientEvent:Connect(function(payload)
		if type(payload) ~= "table" then
			return
		end
		if payload.Kind == "ClockMinigame" then
			ModalController.showClock(payload)
		elseif payload.Kind == "OpenShop" then
			ModalController.showShop()
		end
	end)
end

return ModalController
