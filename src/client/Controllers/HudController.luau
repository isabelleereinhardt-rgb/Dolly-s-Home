--!strict
--[[
	HudController.luau
	--------------------------------------------------------------------------
	The in-round HUD: timer, objective tracker, noise meter, health, stamina.

	Almost everything here is driven by replicated attributes rather than
	RemoteEvents. The noise meter in particular updates ten times a second, and
	doing that over a remote for twelve players would be a lot of traffic for a
	number Roblox will happily replicate for free.
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

local HudController = {}

local gui: ScreenGui
local timerLabel: TextLabel
local phaseLabel: TextLabel
local mapLabel: TextLabel
local killerLabel: TextLabel
local objectiveList: Frame
local noiseBar: Widgets.Bar
local noiseValue: TextLabel
local staminaBar: Widgets.Bar
local healthBar: Widgets.Bar
local stakeLabel: TextLabel
local statusLabel: TextLabel
local vignette: Frame

local objectiveRows: { [string]: { Row: Frame, Label: TextLabel, Detail: TextLabel } } = {}

--==========================================================================
-- Construction
--==========================================================================

local function buildTopBar(parent: Instance)
	local top = Widgets.panel({
		Name = "TopBar",
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0, Theme.TopBarInset),
		Size = UDim2.new(0, 420, 0, 68),
		BackgroundTransparency = 0.25,
		Parent = parent,
	})
	Widgets.padding(Theme.Padding.Tight).Parent = top

	timerLabel = Widgets.label("10:00", {
		Size = UDim2.new(1, 0, 0, 34),
		Font = Theme.Font.Numeric,
		TextSize = 32,
		TextXAlignment = Enum.TextXAlignment.Center,
		Parent = top,
	})

	phaseLabel = Widgets.label("", {
		Position = UDim2.new(0, 0, 0, 34),
		Size = UDim2.new(1, 0, 0, 16),
		TextSize = Theme.TextSize.Small,
		TextColor3 = Theme.Colour.TextDim,
		TextXAlignment = Enum.TextXAlignment.Center,
		Parent = top,
	})

	local footer = Widgets.new("Frame", {
		Position = UDim2.new(0, 0, 0, 50),
		Size = UDim2.new(1, 0, 0, 14),
		BackgroundTransparency = 1,
		Parent = top,
	})

	mapLabel = Widgets.label("", {
		Size = UDim2.new(0.5, 0, 1, 0),
		TextSize = Theme.TextSize.Tiny,
		TextColor3 = Theme.Colour.TextFaint,
		Parent = footer,
	})

	killerLabel = Widgets.label("", {
		Position = UDim2.new(0.5, 0, 0, 0),
		Size = UDim2.new(0.5, 0, 1, 0),
		TextSize = Theme.TextSize.Tiny,
		TextColor3 = Theme.Colour.CrimsonBright,
		TextXAlignment = Enum.TextXAlignment.Right,
		Parent = footer,
	})
end

local function buildObjectiveTracker(parent: Instance)
	local panel = Widgets.panel({
		Name = "Objectives",
		Position = UDim2.new(0, 16, 0, Theme.TopBarInset),
		Size = UDim2.new(0, 250, 0, 40),
		BackgroundTransparency = 0.25,
		AutomaticSize = Enum.AutomaticSize.Y,
		Parent = parent,
	})
	Widgets.padding(Theme.Padding.Normal).Parent = panel

	Widgets.label("OBJECTIVES", {
		Size = UDim2.new(1, 0, 0, 16),
		Font = Theme.Font.Heading,
		TextSize = Theme.TextSize.Tiny,
		TextColor3 = Theme.Colour.Gold,
		Parent = panel,
	})

	objectiveList = Widgets.new("Frame", {
		Name = "List",
		Position = UDim2.new(0, 0, 0, 20),
		Size = UDim2.new(1, 0, 0, 0),
		BackgroundTransparency = 1,
		AutomaticSize = Enum.AutomaticSize.Y,
		Parent = panel,
	}) :: Frame
	Widgets.list(Enum.FillDirection.Vertical, 4).Parent = objectiveList
end

local function buildVitals(parent: Instance)
	local panel = Widgets.panel({
		Name = "Vitals",
		AnchorPoint = Vector2.new(0, 1),
		Position = UDim2.new(0, 16, 1, -16),
		Size = UDim2.new(0, 240, 0, 132),
		BackgroundTransparency = 0.25,
		Parent = parent,
	})
	Widgets.padding(Theme.Padding.Normal).Parent = panel

	-- Noise first: it is the number that decides whether you live.
	noiseBar = Widgets.bar("NOISE", Theme.Colour.NoiseQuiet, {
		Size = UDim2.new(1, 0, 0, 34),
		Parent = panel,
	})
	noiseBar.Root.Parent = panel

	noiseValue = Widgets.label("QUIET", {
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.new(1, 0, 0, 0),
		Size = UDim2.new(0.6, 0, 0, 14),
		Font = Theme.Font.Heading,
		TextSize = Theme.TextSize.Tiny,
		TextXAlignment = Enum.TextXAlignment.Right,
		TextColor3 = Theme.Colour.NoiseQuiet,
		Parent = noiseBar.Root,
	})

	healthBar = Widgets.bar("HEALTH", Theme.Colour.Health, {
		Position = UDim2.new(0, 0, 0, 42),
		Size = UDim2.new(1, 0, 0, 34),
		Parent = panel,
	})
	healthBar.Root.Parent = panel

	staminaBar = Widgets.bar("STAMINA", Theme.Colour.Stamina, {
		Position = UDim2.new(0, 0, 0, 84),
		Size = UDim2.new(1, 0, 0, 34),
		Parent = panel,
	})
	staminaBar.Root.Parent = panel
end

local function buildStakeReadout(parent: Instance)
	local panel = Widgets.panel({
		Name = "Stake",
		AnchorPoint = Vector2.new(1, 1),
		Position = UDim2.new(1, -16, 1, -16),
		Size = UDim2.new(0, 190, 0, 52),
		BackgroundTransparency = 0.25,
		Parent = parent,
	})
	Widgets.padding(Theme.Padding.Normal).Parent = panel

	Widgets.label("STAKE", {
		Size = UDim2.new(1, 0, 0, 14),
		Font = Theme.Font.Heading,
		TextSize = Theme.TextSize.Tiny,
		TextColor3 = Theme.Colour.TextDim,
		Parent = panel,
	})

	stakeLabel = Widgets.label("Wooden Stake", {
		Position = UDim2.new(0, 0, 0, 16),
		Size = UDim2.new(1, 0, 0, 18),
		TextSize = Theme.TextSize.Small,
		TextColor3 = Theme.Colour.Bone,
		Parent = panel,
	})
end

local function buildStatusBanner(parent: Instance)
	statusLabel = Widgets.outlinedLabel("", {
		Name = "Status",
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0, Theme.TopBarInset + 80),
		Size = UDim2.new(0, 520, 0, 32),
		Font = Theme.Font.Heading,
		TextSize = Theme.TextSize.Heading,
		TextXAlignment = Enum.TextXAlignment.Center,
		TextColor3 = Theme.Colour.Gold,
		TextTransparency = 1,
		Parent = parent,
	})
end

--- Edge glow that pulses harder as noise climbs, so you feel how loud you are
--- without having to look away from the room you're in.
local function buildVignette(parent: Instance): ImageLabel
	vignette = Widgets.new("Frame", {
		Name = "Vignette",
		Size = UDim2.fromScale(1, 1),
		BackgroundTransparency = 1,
		ZIndex = 0,
		Parent = parent,
	}) :: Frame

	return Widgets.new("ImageLabel", {
		Name = "Glow",
		Size = UDim2.fromScale(1, 1),
		BackgroundTransparency = 1,
		-- Roblox's stock radial-fade asset, used here as a soft edge mask.
		Image = "rbxassetid://5107152351",
		ImageColor3 = Theme.Colour.Crimson,
		ImageTransparency = 1,
		ScaleType = Enum.ScaleType.Stretch,
		Parent = vignette,
	}) :: ImageLabel
end

--==========================================================================
-- Updates
--==========================================================================

local function syncObjectives()
	local folder = Net.getObjectivesFolder()
	local seen: { [string]: boolean } = {}

	for _, child in folder:GetChildren() do
		if not child:IsA("Configuration") then
			continue
		end
		seen[child.Name] = true

		local row = objectiveRows[child.Name]
		if not row then
			local container = Widgets.new("Frame", {
				Name = child.Name,
				Size = UDim2.new(1, 0, 0, 30),
				BackgroundTransparency = 1,
				LayoutOrder = (child:GetAttribute(StateKeys.Objective.Order) :: number?) or 1,
				Parent = objectiveList,
			}) :: Frame

			local main = Widgets.label("", {
				Size = UDim2.new(1, 0, 0, 17),
				TextSize = Theme.TextSize.Small,
				Parent = container,
			})

			local detail = Widgets.label("", {
				Position = UDim2.new(0, 0, 0, 16),
				Size = UDim2.new(1, 0, 0, 13),
				TextSize = Theme.TextSize.Tiny,
				TextColor3 = Theme.Colour.TextFaint,
				Parent = container,
			})

			row = { Row = container, Label = main, Detail = detail }
			objectiveRows[child.Name] = row
		end

		local label = (child:GetAttribute(StateKeys.Objective.ShortLabel) :: string?) or child.Name
		local current = (child:GetAttribute(StateKeys.Objective.Current) :: number?) or 0
		local goal = (child:GetAttribute(StateKeys.Objective.Goal) :: number?) or 1
		local complete = child:GetAttribute(StateKeys.Objective.Complete) == true
		local detail = (child:GetAttribute(StateKeys.Objective.Detail) :: string?) or ""

		row.Label.Text = complete and `✓  {label}` or `○  {label}   {current}/{goal}`
		row.Label.TextColor3 = complete and Theme.Colour.MossBright or Theme.Colour.Text
		row.Detail.Text = detail
		row.Detail.Visible = detail ~= ""
		row.Row.Size = UDim2.new(1, 0, 0, detail ~= "" and 30 or 18)
	end

	for id, row in objectiveRows do
		if not seen[id] then
			row.Row:Destroy()
			objectiveRows[id] = nil
		end
	end
end

local function updateNoise()
	local level = (player:GetAttribute(StateKeys.Player.Noise) :: number?) or 0
	local tierName = (player:GetAttribute(StateKeys.Player.NoiseTier) :: string?) or "Quiet"
	local colour = Theme.noiseColour(tierName)

	noiseBar:set(level / Config.Noise.Max, `NOISE  {math.floor(level)}`, colour)
	noiseValue.Text = Theme.noiseLabel(tierName)
	noiseValue.TextColor3 = colour
end

local function updateVitals()
	local _, humanoid = Util.getCharacterParts(player)
	if humanoid and humanoid.MaxHealth > 0 then
		healthBar:set(humanoid.Health / humanoid.MaxHealth, `HEALTH  {math.floor(humanoid.Health)}`)
	end

	local stamina = (player:GetAttribute(StateKeys.Player.Stamina) :: number?) or Config.Player.MaxStamina
	staminaBar.Root.Visible = Config.Player.StaminaEnabled
	staminaBar:set(stamina / Config.Player.MaxStamina, "STAMINA")

	local stakeId = (player:GetAttribute(StateKeys.Player.EquippedStake) :: string?) or Config.Economy.StartingStake
	local tier = Config.getStakeTier(stakeId)
	if tier then
		local readyAt = (player:GetAttribute(StateKeys.Player.StakeReadyAt) :: number?) or 0
		local cooling = readyAt - Util.now()
		if cooling > 0 then
			stakeLabel.Text = `{tier.Name}  ({string.format("%.1f", cooling)}s)`
			stakeLabel.TextColor3 = Theme.Colour.TextFaint
		else
			stakeLabel.Text = tier.Name
			stakeLabel.TextColor3 = Theme.rarityColour(tier.Id)
		end
	end
end

local function updateStatus()
	local text = ""
	local colour = Theme.Colour.Gold

	if player:GetAttribute(StateKeys.Player.Injured) == true then
		local endsAt = (player:GetAttribute(StateKeys.Player.ReviveEndsAt) :: number?) or 0
		local remaining = math.max(0, math.ceil(endsAt - Util.now()))
		text = `YOU ARE INJURED  -  {remaining}s  -  CALL FOR HELP`
		colour = Theme.Colour.CrimsonBright
	elseif player:GetAttribute(StateKeys.Player.Eliminated) == true then
		text = "ELIMINATED  -  SPECTATING"
		colour = Theme.Colour.TextDim
	elseif player:GetAttribute(StateKeys.Player.InSafeZone) == true then
		text = "SANCTIFIED GROUND  -  THEY CANNOT REACH YOU HERE"
		colour = Theme.Colour.Gold
	elseif player:GetAttribute(StateKeys.Player.Hidden) == true then
		local kind = (player:GetAttribute(StateKeys.Player.HidingKind) :: string?) or "Spot"
		text = `HIDDEN ({kind})  -  PRESS E OR Q TO COME OUT`
		colour = Theme.Colour.Bone
	end

	if statusLabel.Text ~= text then
		statusLabel.Text = text
		TweenService:Create(statusLabel, Theme.Tween.Fast, { TextTransparency = text == "" and 1 or 0 }):Play()
	end
end

local function updateTimer()
	local phase = Net.getStateValue(StateKeys.Game.Phase, StateKeys.Phase.Booting)
	local endsAt = Net.getStateValue(StateKeys.Game.PhaseEndsAt, 0) :: number
	local remaining = math.max(0, endsAt - Util.now())

	timerLabel.Text = Util.formatClock(remaining)

	if phase == StateKeys.Phase.Active then
		phaseLabel.Text = "TIME REMAINING"
		timerLabel.TextColor3 = remaining <= 60 and Theme.Colour.CrimsonBright or Theme.Colour.Text
	elseif phase == StateKeys.Phase.Intermission then
		phaseLabel.Text = "NEXT ROUND IN"
		timerLabel.TextColor3 = Theme.Colour.Text
	elseif phase == StateKeys.Phase.Starting then
		phaseLabel.Text = "THE HOUSE IS WAKING UP"
		timerLabel.TextColor3 = Theme.Colour.Gold
	elseif phase == StateKeys.Phase.Results then
		phaseLabel.Text = "ROUND OVER"
		timerLabel.TextColor3 = Theme.Colour.TextDim
	else
		phaseLabel.Text = "STARTING UP"
	end

	local mapName = Net.getStateValue(StateKeys.Game.MapName, "") :: string
	mapLabel.Text = mapName ~= "" and mapName or ""

	local killers = Net.getStateValue(StateKeys.Game.KillerNames, "") :: string
	killerLabel.Text = killers ~= "" and `Hunting: {killers}` or ""

	-- Hide the round-only panels during the intermission.
	local inRound = phase == StateKeys.Phase.Active or phase == StateKeys.Phase.Starting
	local objectivePanel = objectiveList.Parent
	if objectivePanel and objectivePanel:IsA("GuiObject") then
		objectivePanel.Visible = inRound
	end
end

--- The vignette breathes with your noise level, so you feel the danger without
--- having to look at the meter.
local function updateVignette(gradient: ImageLabel, dt: number)
	local level = (player:GetAttribute(StateKeys.Player.Noise) :: number?) or 0
	local injured = player:GetAttribute(StateKeys.Player.Injured) == true

	local intensity = math.clamp(level / Config.Noise.Max, 0, 1) * 0.55
	if injured then
		intensity = 0.75
	end

	local pulse = 0
	if intensity > 0.1 then
		pulse = math.sin(os.clock() * (2 + intensity * 6)) * 0.06 * intensity
	end

	local target = 1 - math.clamp(intensity + pulse, 0, 0.8)
	gradient.ImageTransparency = Util.damp(gradient.ImageTransparency, target, 6, dt)
	gradient.ImageColor3 = injured and Theme.Colour.Crimson
		or Theme.noiseColour((player:GetAttribute(StateKeys.Player.NoiseTier) :: string?) or "Quiet")
end

--==========================================================================
-- Lifecycle
--==========================================================================

function HudController.start()
	gui = Widgets.new("ScreenGui", {
		Name = "DollysHomeHUD",
		ResetOnSpawn = false,
		IgnoreGuiInset = true,
		ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
		DisplayOrder = 10,
		Parent = player:WaitForChild("PlayerGui"),
	}) :: ScreenGui

	local gradient = buildVignette(gui)
	buildTopBar(gui)
	buildObjectiveTracker(gui)
	buildVitals(gui)
	buildStakeReadout(gui)
	buildStatusBanner(gui)

	local objectivesFolder = Net.getObjectivesFolder()
	objectivesFolder.ChildAdded:Connect(function(child)
		syncObjectives()
		child.AttributeChanged:Connect(syncObjectives)
	end)
	objectivesFolder.ChildRemoved:Connect(syncObjectives)
	for _, child in objectivesFolder:GetChildren() do
		child.AttributeChanged:Connect(syncObjectives)
	end
	syncObjectives()

	-- Attribute-driven pieces update on change rather than every frame.
	player:GetAttributeChangedSignal(StateKeys.Player.Noise):Connect(updateNoise)
	player:GetAttributeChangedSignal(StateKeys.Player.NoiseTier):Connect(updateNoise)
	updateNoise()

	RunService.RenderStepped:Connect(function(dt)
		local ok, err = pcall(function()
			updateTimer()
			updateVitals()
			updateStatus()
			updateVignette(gradient, dt)
		end)
		if not ok and Config.Debug.Verbose then
			warn(`[HudController] {err}`)
		end
	end)
end

function HudController.setVisible(visible: boolean)
	if gui then
		gui.Enabled = visible
	end
end

return HudController
