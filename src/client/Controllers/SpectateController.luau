--!strict
--[[
	SpectateController.luau
	--------------------------------------------------------------------------
	After you're eliminated -- or if you joined while a round was already
	running -- the camera follows whoever is still alive.

	Deliberately no chat bridge back to the living. "Ghosting" (dead players
	calling out killer positions in voice or chat) ruins the tension the whole
	noise system exists to create, and the design document calls it out
	specifically.
	--------------------------------------------------------------------------
]]

local ContextActionService = game:GetService("ContextActionService")
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local Workspace = game:GetService("Workspace")

local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
local Net = require(Shared.Net)
local StateKeys = require(Shared.StateKeys)
local Util = require(Shared.Util)

local Theme = require(script.Parent.Parent.UI.Theme)
local Widgets = require(script.Parent.Parent.UI.Widgets)

local player = Players.LocalPlayer

local SpectateController = {}

local ACTION_NEXT = "DollysHome_SpectateNext"
local ACTION_PREV = "DollysHome_SpectatePrev"

local gui: ScreenGui
local nameLabel: TextLabel

local spectating = false
local targetIndex = 1
local currentTarget: Player? = nil

--==========================================================================
-- Targets
--==========================================================================

local function getTargets(): { Player }
	local out = {}
	for _, other in Players:GetPlayers() do
		if other == player then
			continue
		end
		if other:GetAttribute(StateKeys.Player.Alive) == true or other:GetAttribute(StateKeys.Player.Injured) == true then
			if Util.getPosition(other) then
				table.insert(out, other)
			end
		end
	end
	table.sort(out, function(a, b)
		return a.UserId < b.UserId
	end)
	return out
end

local function cycle(delta: number)
	local targets = getTargets()
	if #targets == 0 then
		return
	end
	targetIndex = ((targetIndex - 1 + delta) % #targets) + 1
	currentTarget = targets[targetIndex]
end

--==========================================================================
-- Camera
--==========================================================================

local function beginSpectating()
	if spectating then
		return
	end
	spectating = true
	gui.Enabled = true

	local camera = Workspace.CurrentCamera
	if camera then
		camera.CameraType = Enum.CameraType.Scriptable
	end

	targetIndex = 1
	cycle(0)

	ContextActionService:BindAction(ACTION_NEXT, function(_a, state)
		if state == Enum.UserInputState.Begin then
			cycle(1)
		end
		return Enum.ContextActionResult.Sink
	end, UserInputService.TouchEnabled, Enum.KeyCode.Tab, Enum.KeyCode.E, Enum.KeyCode.ButtonR1)
	ContextActionService:SetTitle(ACTION_NEXT, "NEXT")

	ContextActionService:BindAction(ACTION_PREV, function(_a, state)
		if state == Enum.UserInputState.Begin then
			cycle(-1)
		end
		return Enum.ContextActionResult.Sink
	end, UserInputService.TouchEnabled, Enum.KeyCode.Q, Enum.KeyCode.ButtonL1)
	ContextActionService:SetTitle(ACTION_PREV, "PREV")
end

local function endSpectating()
	if not spectating then
		return
	end
	spectating = false
	gui.Enabled = false
	currentTarget = nil

	ContextActionService:UnbindAction(ACTION_NEXT)
	ContextActionService:UnbindAction(ACTION_PREV)

	local camera = Workspace.CurrentCamera
	local character = player.Character
	if camera then
		camera.CameraType = Enum.CameraType.Custom
		if character then
			local humanoid = character:FindFirstChildOfClass("Humanoid")
			if humanoid then
				camera.CameraSubject = humanoid
			end
		end
	end
end

local function updateCamera(dt: number)
	if not spectating then
		return
	end

	local camera = Workspace.CurrentCamera
	if not camera then
		return
	end

	-- The target might have been eliminated since we picked them.
	if not currentTarget or not currentTarget.Parent or not Util.getPosition(currentTarget) then
		cycle(1)
	end

	local target = currentTarget
	if not target then
		nameLabel.Text = "Nobody left to watch."
		return
	end

	local position = Util.getPosition(target)
	if not position then
		return
	end

	-- Trail behind and above, easing in so switching targets isn't a snap cut.
	local goal = CFrame.lookAt(position + Vector3.new(0, 9, 14), position)
	camera.CFrame = camera.CFrame:Lerp(goal, math.clamp(dt * 6, 0, 1))

	local injuredNote = target:GetAttribute(StateKeys.Player.Injured) == true and "  (down)" or ""
	nameLabel.Text = `Watching {target.DisplayName}{injuredNote}    -    Tab / E to cycle`
end

--==========================================================================
-- Construction
--==========================================================================

local function build()
	gui = Widgets.new("ScreenGui", {
		Name = "DollysHomeSpectate",
		ResetOnSpawn = false,
		IgnoreGuiInset = true,
		DisplayOrder = 8,
		Enabled = false,
		Parent = player:WaitForChild("PlayerGui"),
	}) :: ScreenGui

	local panel = Widgets.panel({
		AnchorPoint = Vector2.new(0.5, 1),
		Position = UDim2.new(0.5, 0, 1, -60),
		Size = UDim2.new(0, 460, 0, 40),
		BackgroundTransparency = 0.25,
		Parent = gui,
	})
	Widgets.padding(Theme.Padding.Tight).Parent = panel

	nameLabel = Widgets.label("", {
		Size = UDim2.fromScale(1, 1),
		TextSize = Theme.TextSize.Small,
		TextColor3 = Theme.Colour.TextDim,
		TextXAlignment = Enum.TextXAlignment.Center,
		Parent = panel,
	})
end

--==========================================================================
-- Lifecycle
--==========================================================================

local function evaluate()
	local phase = Net.getStateValue(StateKeys.Game.Phase, "")
	local shouldSpectate = phase == StateKeys.Phase.Active
		and player:GetAttribute(StateKeys.Player.Spectating) == true
		and #getTargets() > 0

	if shouldSpectate then
		beginSpectating()
	else
		endSpectating()
	end
end

function SpectateController.start()
	build()

	player:GetAttributeChangedSignal(StateKeys.Player.Spectating):Connect(evaluate)
	player:GetAttributeChangedSignal(StateKeys.Player.Eliminated):Connect(evaluate)
	Net.getState():GetAttributeChangedSignal(StateKeys.Game.Phase):Connect(evaluate)

	player.CharacterAdded:Connect(function()
		task.wait(0.5)
		evaluate()
	end)

	RunService.RenderStepped:Connect(function(dt)
		local ok = pcall(updateCamera, dt)
		if not ok then
			endSpectating()
		end
	end)

	evaluate()
end

return SpectateController
