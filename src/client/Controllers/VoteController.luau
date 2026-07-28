--!strict
--[[
	VoteController.luau
	--------------------------------------------------------------------------
	The lobby map vote.

	Counts come straight off the replicated Votes attributes, so every client
	sees the tally shift the instant anyone clicks -- no polling, no remote per
	vote.
	--------------------------------------------------------------------------
]]

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")

local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
local Config = require(Shared.Config)
local Net = require(Shared.Net)
local StateKeys = require(Shared.StateKeys)
local Util = require(Shared.Util)

local Theme = require(script.Parent.Parent.UI.Theme)
local Widgets = require(script.Parent.Parent.UI.Widgets)

local player = Players.LocalPlayer

local VoteController = {}

local gui: ScreenGui
local panel: Frame
local timerLabel: TextLabel

type MapCard = {
	Button: TextButton,
	CountLabel: TextLabel,
	Highlight: UIStroke,
	MapId: string,
}

local cards: { MapCard } = {}
local myVote: string? = nil

--==========================================================================
-- Construction
--==========================================================================

local function buildCard(mapInfo: any, index: number, total: number, parent: Instance): MapCard
	local width = 1 / total

	local button = Widgets.button("", {
		Name = mapInfo.Id,
		Size = UDim2.new(width, -8, 1, 0),
		Position = UDim2.new(width * (index - 1), 4, 0, 0),
		BackgroundColor3 = Theme.Colour.PanelSunken,
		Parent = parent,
	})

	local highlight = button:FindFirstChildOfClass("UIStroke") :: UIStroke
	highlight.Color = Theme.Colour.Divider
	highlight.Thickness = 2

	Widgets.label(mapInfo.Name, {
		Position = UDim2.new(0, 12, 0, 12),
		Size = UDim2.new(1, -24, 0, 22),
		Font = Theme.Font.Heading,
		TextSize = Theme.TextSize.Heading,
		TextColor3 = Theme.Colour.Text,
		Parent = button,
	})

	Widgets.label(mapInfo.Description, {
		Position = UDim2.new(0, 12, 0, 36),
		Size = UDim2.new(1, -24, 0, 34),
		TextSize = Theme.TextSize.Tiny,
		TextColor3 = Theme.Colour.TextFaint,
		TextWrapped = true,
		TextYAlignment = Enum.TextYAlignment.Top,
		Parent = button,
	})

	local countLabel = Widgets.label("0 votes", {
		AnchorPoint = Vector2.new(0, 1),
		Position = UDim2.new(0, 12, 1, -10),
		Size = UDim2.new(1, -24, 0, 18),
		Font = Theme.Font.Numeric,
		TextSize = Theme.TextSize.Small,
		TextColor3 = Theme.Colour.Gold,
		Parent = button,
	})

	local card: MapCard = {
		Button = button,
		CountLabel = countLabel,
		Highlight = highlight,
		MapId = mapInfo.Id,
	}

	button.MouseButton1Click:Connect(function()
		if not Net.getStateValue(StateKeys.Game.VotingOpen, false) then
			return
		end
		myVote = mapInfo.Id
		Net.Events.CastVote:FireServer(mapInfo.Id)
		VoteController.refresh()
	end)

	return card
end

local function build()
	gui = Widgets.new("ScreenGui", {
		Name = "DollysHomeVote",
		ResetOnSpawn = false,
		IgnoreGuiInset = true,
		DisplayOrder = 11,
		Enabled = false,
		Parent = player:WaitForChild("PlayerGui"),
	}) :: ScreenGui

	panel = Widgets.panel({
		Name = "VotePanel",
		AnchorPoint = Vector2.new(0.5, 1),
		Position = UDim2.new(0.5, 0, 1, -24),
		Size = UDim2.new(0, 720, 0, 190),
		BackgroundTransparency = 0.1,
		Parent = gui,
	})
	Widgets.padding(Theme.Padding.Normal).Parent = panel

	Widgets.label("VOTE FOR THE NEXT MAP", {
		Size = UDim2.new(1, 0, 0, 22),
		Font = Theme.Font.Heading,
		TextSize = Theme.TextSize.Heading,
		TextColor3 = Theme.Colour.Gold,
		TextXAlignment = Enum.TextXAlignment.Center,
		Parent = panel,
	})

	timerLabel = Widgets.label("", {
		Position = UDim2.new(0, 0, 0, 22),
		Size = UDim2.new(1, 0, 0, 16),
		TextSize = Theme.TextSize.Tiny,
		TextColor3 = Theme.Colour.TextDim,
		TextXAlignment = Enum.TextXAlignment.Center,
		Parent = panel,
	})

	local row = Widgets.new("Frame", {
		Name = "Cards",
		Position = UDim2.new(0, 0, 0, 44),
		Size = UDim2.new(1, 0, 1, -50),
		BackgroundTransparency = 1,
		Parent = panel,
	})

	local maps = Config.getEnabledMaps()
	for index, mapInfo in maps do
		table.insert(cards, buildCard(mapInfo, index, #maps, row))
	end

	-- Maps you can't vote for yet still show, greyed out, so players can see
	-- what's coming.
	local disabledRow = Widgets.label("", {
		Name = "Locked",
		AnchorPoint = Vector2.new(0.5, 1),
		Position = UDim2.new(0.5, 0, 1, 2),
		Size = UDim2.new(1, 0, 0, 14),
		TextSize = Theme.TextSize.Tiny,
		TextColor3 = Theme.Colour.TextFaint,
		TextXAlignment = Enum.TextXAlignment.Center,
		Parent = panel,
	})

	local locked = {}
	for _, mapInfo in Config.Maps do
		if not mapInfo.Enabled then
			table.insert(locked, mapInfo.Name)
		end
	end
	if #locked > 0 then
		disabledRow.Text = `Coming soon: {table.concat(locked, ", ")}`
	end
end

--==========================================================================
-- Updates
--==========================================================================

function VoteController.refresh()
	local votes = Net.getVotesFolder()
	for _, card in cards do
		local count = (votes:GetAttribute(card.MapId) :: number?) or 0
		card.CountLabel.Text = count == 1 and "1 vote" or `{count} votes`

		local isMine = myVote == card.MapId
		TweenService:Create(card.Highlight, Theme.Tween.Fast, {
			Color = isMine and Theme.Colour.Gold or Theme.Colour.Divider,
		}):Play()
		TweenService:Create(card.Button, Theme.Tween.Fast, {
			BackgroundColor3 = isMine and Theme.Colour.PanelRaised or Theme.Colour.PanelSunken,
		}):Play()
	end
end

local function updateVisibility()
	local phase = Net.getStateValue(StateKeys.Game.Phase, "")
	local votingOpen = Net.getStateValue(StateKeys.Game.VotingOpen, false)
	local shouldShow = votingOpen and phase == StateKeys.Phase.Intermission

	if gui.Enabled ~= shouldShow then
		gui.Enabled = shouldShow
		if shouldShow then
			myVote = nil
			VoteController.refresh()
		end
	end
end

--==========================================================================
-- Lifecycle
--==========================================================================

function VoteController.start()
	build()

	local state = Net.getState()
	state:GetAttributeChangedSignal(StateKeys.Game.VotingOpen):Connect(updateVisibility)
	state:GetAttributeChangedSignal(StateKeys.Game.Phase):Connect(updateVisibility)

	Net.getVotesFolder().AttributeChanged:Connect(function()
		if gui.Enabled then
			VoteController.refresh()
		end
	end)

	RunService.Heartbeat:Connect(function()
		if not gui.Enabled then
			return
		end
		-- Voting closes partway through the intermission, not at the end of it,
		-- so count against the start plus the voting window rather than
		-- PhaseEndsAt.
		local startedAt = Net.getStateValue(StateKeys.Game.PhaseStartedAt, 0) :: number
		local closesAt = startedAt + Config.Round.VotingSeconds
		local remaining = math.max(0, closesAt - Util.now())
		timerLabel.Text = `Voting closes in {math.ceil(remaining)}s`
	end)

	updateVisibility()
	VoteController.refresh()
end

return VoteController
