--!strict
--[[
	ResultsController.luau
	--------------------------------------------------------------------------
	The end-of-round screen, built on the Murder Mystery 2 structure the design
	document asks for: a dimmed but still visible map, a banner that lands
	first, then the ranked players, then the payouts counting up.

	The sequencing matters more than any single element. Everything arriving at
	once reads as a wall of numbers; staggered by a couple of hundred
	milliseconds it reads as a result being announced.
	--------------------------------------------------------------------------
]]

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")

local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
local Net = require(Shared.Net)
local StateKeys = require(Shared.StateKeys)
local Util = require(Shared.Util)

local Theme = require(script.Parent.Parent.UI.Theme)
local Widgets = require(script.Parent.Parent.UI.Widgets)

local player = Players.LocalPlayer

local ResultsController = {}

local gui: ScreenGui
local backdrop: Frame
local banner: TextLabel
local subtitle: TextLabel
local rowContainer: ScrollingFrame
local footer: TextLabel

local currentEndsAt = 0
local thumbnailCache: { [number]: string } = {}

--==========================================================================
-- Avatars
--==========================================================================

--- Roblox's headshot endpoint, cached per user for the session. Falls back to
--- an empty image rather than erroring if the request fails.
local function getThumbnail(userId: number): string
	if thumbnailCache[userId] then
		return thumbnailCache[userId]
	end
	local ok, content = pcall(function()
		return Players:GetUserThumbnailAsync(
			userId,
			Enum.ThumbnailType.HeadShot,
			Enum.ThumbnailSize.Size100x100
		)
	end)
	local result = ok and content or ""
	thumbnailCache[userId] = result
	return result
end

--==========================================================================
-- Construction
--==========================================================================

local function build()
	gui = Widgets.new("ScreenGui", {
		Name = "DollysHomeResults",
		ResetOnSpawn = false,
		IgnoreGuiInset = true,
		DisplayOrder = 20,
		Enabled = false,
		Parent = player:WaitForChild("PlayerGui"),
	}) :: ScreenGui

	-- Dimmed, not opaque: you can still see where the bodies fell.
	backdrop = Widgets.new("Frame", {
		Name = "Backdrop",
		Size = UDim2.fromScale(1, 1),
		BackgroundColor3 = Theme.Colour.Backdrop,
		BackgroundTransparency = 0.35,
		BorderSizePixel = 0,
		Parent = gui,
	}) :: Frame

	Widgets.new("ImageLabel", {
		Name = "Vignette",
		Size = UDim2.fromScale(1, 1),
		BackgroundTransparency = 1,
		Image = "rbxassetid://5107152351",
		ImageColor3 = Color3.new(0, 0, 0),
		ImageTransparency = 0.35,
		ScaleType = Enum.ScaleType.Stretch,
		Parent = backdrop,
	})

	banner = Widgets.outlinedLabel("VICTORY", {
		Name = "Banner",
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0.06, 0),
		Size = UDim2.new(0, 700, 0, 76),
		Font = Theme.Font.Display,
		TextSize = Theme.TextSize.Display,
		TextXAlignment = Enum.TextXAlignment.Center,
		TextColor3 = Theme.Colour.MossBright,
		Parent = gui,
	})

	subtitle = Widgets.outlinedLabel("", {
		Name = "Subtitle",
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0.06, 78),
		Size = UDim2.new(0, 700, 0, 22),
		Font = Theme.Font.Flavour,
		TextSize = Theme.TextSize.Body,
		TextXAlignment = Enum.TextXAlignment.Center,
		TextColor3 = Theme.Colour.Bone,
		Parent = gui,
	})

	local panel = Widgets.panel({
		Name = "Rankings",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.new(0.5, 0, 0.56, 0),
		Size = UDim2.new(0, 620, 0, 380),
		BackgroundTransparency = 0.1,
		Parent = gui,
	})
	Widgets.padding(Theme.Padding.Normal).Parent = panel

	Widgets.label("PLAYER RANKINGS", {
		Size = UDim2.new(1, 0, 0, 20),
		Font = Theme.Font.Heading,
		TextSize = Theme.TextSize.Small,
		TextColor3 = Theme.Colour.Gold,
		Parent = panel,
	})

	rowContainer = Widgets.new("ScrollingFrame", {
		Name = "Rows",
		Position = UDim2.new(0, 0, 0, 26),
		Size = UDim2.new(1, 0, 1, -26),
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		ScrollBarThickness = 4,
		ScrollBarImageColor3 = Theme.Colour.Divider,
		CanvasSize = UDim2.new(),
		AutomaticCanvasSize = Enum.AutomaticSize.Y,
		Parent = panel,
	}) :: ScrollingFrame
	Widgets.list(Enum.FillDirection.Vertical, 6).Parent = rowContainer

	footer = Widgets.outlinedLabel("", {
		Name = "Footer",
		AnchorPoint = Vector2.new(0.5, 1),
		Position = UDim2.new(0.5, 0, 0.96, 0),
		Size = UDim2.new(0, 500, 0, 26),
		Font = Theme.Font.Heading,
		TextSize = Theme.TextSize.Body,
		TextXAlignment = Enum.TextXAlignment.Center,
		TextColor3 = Theme.Colour.TextDim,
		Parent = gui,
	})
end

--==========================================================================
-- Rows
--==========================================================================

local function buildRow(result: any, index: number)
	local isYou = result.UserId == player.UserId

	local row = Widgets.panel({
		Name = `Rank{index}`,
		Size = UDim2.new(1, -8, 0, 56),
		BackgroundColor3 = isYou and Theme.Colour.PanelRaised or Theme.Colour.PanelSunken,
		BackgroundTransparency = 0.2,
		LayoutOrder = index,
		Parent = rowContainer,
	})
	Widgets.padding(Theme.Padding.Tight, { Left = 10, Right = 10 }).Parent = row

	if isYou then
		local stroke = row:FindFirstChildOfClass("UIStroke")
		if stroke then
			stroke.Color = Theme.Colour.Gold
			stroke.Transparency = 0
		end
	end

	Widgets.label(`#{index}`, {
		Size = UDim2.new(0, 34, 1, 0),
		Font = Theme.Font.Numeric,
		TextSize = Theme.TextSize.Heading,
		TextColor3 = result.IsTopPerformer and Theme.Colour.Gold or Theme.Colour.TextDim,
		Parent = row,
	})

	local avatar = Widgets.new("ImageLabel", {
		Position = UDim2.new(0, 38, 0.5, -20),
		Size = UDim2.fromOffset(40, 40),
		BackgroundColor3 = Theme.Colour.Backdrop,
		BorderSizePixel = 0,
		Image = "",
		-- Eliminated players are desaturated, as in the reference screens.
		ImageColor3 = result.Eliminated and Color3.fromRGB(120, 110, 110) or Color3.new(1, 1, 1),
		Parent = row,
	})
	Widgets.corner(UDim.new(1, 0)).Parent = avatar

	task.spawn(function()
		avatar.Image = getThumbnail(result.UserId)
	end)

	local nameLabel = Widgets.label(result.DisplayName, {
		Position = UDim2.new(0, 86, 0, 8),
		Size = UDim2.new(1, -240, 0, 20),
		Font = Theme.Font.Heading,
		TextSize = Theme.TextSize.Body,
		TextColor3 = isYou and Theme.Colour.Gold or Theme.Colour.Text,
		TextTruncate = Enum.TextTruncate.AtEnd,
		Parent = row,
	})
	if result.Eliminated then
		nameLabel.TextColor3 = Theme.Colour.TextFaint
	end

	Widgets.label(`Tasks {result.Tasks}     Revives {result.Revives}`, {
		Position = UDim2.new(0, 86, 0, 28),
		Size = UDim2.new(1, -240, 0, 18),
		TextSize = Theme.TextSize.Tiny,
		TextColor3 = Theme.Colour.TextDim,
		Parent = row,
	})

	local coinLabel = Widgets.label("0", {
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.new(1, 0, 0, 8),
		Size = UDim2.new(0, 120, 0, 22),
		Font = Theme.Font.Numeric,
		TextSize = Theme.TextSize.Heading,
		TextColor3 = Theme.Colour.Gold,
		TextXAlignment = Enum.TextXAlignment.Right,
		Parent = row,
	})

	local tagText = result.Eliminated and "Eliminated" or "Survived"
	Widgets.label(tagText, {
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.new(1, 0, 0, 30),
		Size = UDim2.new(0, 120, 0, 16),
		TextSize = Theme.TextSize.Tiny,
		TextColor3 = result.Eliminated and Theme.Colour.Crimson or Theme.Colour.MossBright,
		TextXAlignment = Enum.TextXAlignment.Right,
		Parent = row,
	})

	if result.IsTopPerformer then
		Widgets.label("★", {
			AnchorPoint = Vector2.new(1, 0.5),
			Position = UDim2.new(0, 82, 0.5, 0),
			Size = UDim2.fromOffset(18, 18),
			TextSize = 16,
			TextColor3 = Theme.Colour.Gold,
			TextXAlignment = Enum.TextXAlignment.Center,
			Parent = row,
		})
	end

	-- Slide in, then count the coins up.
	row.Position = UDim2.new(0, 40, 0, 0)
	row.BackgroundTransparency = 1
	task.delay(0.06 * index, function()
		if not row.Parent then
			return
		end
		TweenService:Create(row, Theme.Tween.Normal, { BackgroundTransparency = 0.2 }):Play()
		Widgets.countUp(coinLabel, 0, result.Coins, 0.8, function(value)
			return `+{math.floor(value)}`
		end)
	end)
end

--==========================================================================
-- Show / hide
--==========================================================================

function ResultsController.show(payload: any)
	rowContainer:ClearAllChildren()
	Widgets.list(Enum.FillDirection.Vertical, 6).Parent = rowContainer

	local victory = payload.Victory == true
	currentEndsAt = payload.EndsAt or (Util.now() + 15)

	banner.Text = victory and "YOU GOT OUT" or "THE HOUSE KEPT YOU"
	banner.TextColor3 = victory and Theme.Colour.MossBright or Theme.Colour.CrimsonBright

	local killers = payload.Killers and #payload.Killers > 0 and table.concat(payload.Killers, " and ") or "the family"
	subtitle.Text = victory and `Every task finished. {killers} went hungry.`
		or `{killers} is still down there, waiting for the next ones.`

	gui.Enabled = true

	-- Banner first, rows after.
	backdrop.BackgroundTransparency = 1
	banner.TextTransparency = 1
	subtitle.TextTransparency = 1
	banner.Position = UDim2.new(0.5, 0, 0.02, 0)

	TweenService:Create(backdrop, Theme.Tween.Slow, { BackgroundTransparency = 0.35 }):Play()
	TweenService:Create(banner, Theme.Tween.Bounce, { Position = UDim2.new(0.5, 0, 0.06, 0) }):Play()
	TweenService:Create(banner, Theme.Tween.Normal, { TextTransparency = 0 }):Play()
	task.delay(0.25, function()
		TweenService:Create(subtitle, Theme.Tween.Normal, { TextTransparency = 0 }):Play()
	end)

	task.delay(0.4, function()
		for index, result in payload.Results or {} do
			buildRow(result, index)
		end
	end)
end

function ResultsController.hide()
	if not gui.Enabled then
		return
	end
	TweenService:Create(backdrop, Theme.Tween.Normal, { BackgroundTransparency = 1 }):Play()
	TweenService:Create(banner, Theme.Tween.Normal, { TextTransparency = 1 }):Play()
	TweenService:Create(subtitle, Theme.Tween.Normal, { TextTransparency = 1 }):Play()
	task.wait(0.3)
	gui.Enabled = false
	rowContainer:ClearAllChildren()
end

--==========================================================================
-- Lifecycle
--==========================================================================

function ResultsController.start()
	build()

	Net.Events.RoundResults.OnClientEvent:Connect(function(payload)
		local ok, err = pcall(ResultsController.show, payload)
		if not ok then
			warn(`[ResultsController] {err}`)
		end
	end)

	Net.getState():GetAttributeChangedSignal(StateKeys.Game.Phase):Connect(function()
		local phase = Net.getStateValue(StateKeys.Game.Phase, "")
		if phase ~= StateKeys.Phase.Results then
			task.spawn(ResultsController.hide)
		end
	end)

	RunService.Heartbeat:Connect(function()
		if not gui.Enabled then
			return
		end
		local remaining = math.max(0, currentEndsAt - Util.now())
		footer.Text = `Returning to the lobby in {math.ceil(remaining)}`
	end)
end

return ResultsController
