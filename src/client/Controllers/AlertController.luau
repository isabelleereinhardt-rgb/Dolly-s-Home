--!strict
--[[
	AlertController.luau
	--------------------------------------------------------------------------
	Everything transient: task-completion toasts, downed-teammate alerts with a
	direction arrow, and the killers' muttering.

	The injured alert is the important one. The design document asks for an
	on-screen indicator of a downed player's location so nearby teammates can
	respond, and getting that readable matters more than anything else here --
	a rescue that arrives at twenty-nine seconds is the best moment the game
	has.
	--------------------------------------------------------------------------
]]

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local Workspace = game:GetService("Workspace")

local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
local Net = require(Shared.Net)
local StateKeys = require(Shared.StateKeys)
local Util = require(Shared.Util)

local Theme = require(script.Parent.Parent.UI.Theme)
local Widgets = require(script.Parent.Parent.UI.Widgets)

local player = Players.LocalPlayer

local AlertController = {}

local gui: ScreenGui
local toastList: Frame
local subtitle: TextLabel

type InjuredEntry = {
	UserId: number,
	Name: string,
	ExpiresAt: number,
	Frame: Frame,
	NameLabel: TextLabel,
	ArrowLabel: TextLabel,
	TimeLabel: TextLabel,
}

local injured: { [number]: InjuredEntry } = {}
local injuredList: Frame

--==========================================================================
-- Toasts
--==========================================================================

local TOAST_STYLE: { [string]: { Colour: Color3, Icon: string } } = {
	Task = { Colour = Theme.Colour.MossBright, Icon = "✓" },
	Objective = { Colour = Theme.Colour.Gold, Icon = "!" },
	Danger = { Colour = Theme.Colour.CrimsonBright, Icon = "!" },
	Helper = { Colour = Theme.Colour.Ghost, Icon = "~" },
	Combat = { Colour = Theme.Colour.Bone, Icon = "×" },
	Stake = { Colour = Theme.Colour.CrimsonBright, Icon = "×" },
	Info = { Colour = Theme.Colour.Text, Icon = "·" },
	Error = { Colour = Theme.Colour.Crimson, Icon = "×" },
	Success = { Colour = Theme.Colour.MossBright, Icon = "✓" },
}

function AlertController.toast(text: string, kind: string?, duration: number?)
	if text == "" then
		return
	end

	local style = TOAST_STYLE[kind or "Info"] or TOAST_STYLE.Info

	local frame = Widgets.panel({
		Size = UDim2.new(0, 400, 0, 34),
		BackgroundTransparency = 0.15,
		LayoutOrder = -math.floor(os.clock() * 1000),
		Parent = toastList,
	})
	Widgets.padding(Theme.Padding.Tight, { Left = 10, Right = 10 }).Parent = frame

	local label = Widgets.label(`{style.Icon}   {text}`, {
		Size = UDim2.fromScale(1, 1),
		TextColor3 = style.Colour,
		TextSize = Theme.TextSize.Small,
		TextXAlignment = Enum.TextXAlignment.Center,
		TextTruncate = Enum.TextTruncate.AtEnd,
		Parent = frame,
	})

	frame.BackgroundTransparency = 1
	label.TextTransparency = 1
	TweenService:Create(frame, Theme.Tween.Fast, { BackgroundTransparency = 0.15 }):Play()
	TweenService:Create(label, Theme.Tween.Fast, { TextTransparency = 0 }):Play()

	task.delay(duration or 4, function()
		if not frame.Parent then
			return
		end
		TweenService:Create(frame, Theme.Tween.Normal, { BackgroundTransparency = 1 }):Play()
		TweenService:Create(label, Theme.Tween.Normal, { TextTransparency = 1 }):Play()
		task.wait(0.3)
		frame:Destroy()
	end)
end

--==========================================================================
-- Subtitles (killer and helper dialogue)
--==========================================================================

local subtitleToken = 0

function AlertController.subtitle(speaker: string, text: string, colour: Color3, duration: number?)
	subtitleToken += 1
	local token = subtitleToken

	subtitle.Text = `{speaker}:  "{text}"`
	subtitle.TextColor3 = colour
	TweenService:Create(subtitle, Theme.Tween.Fast, { TextTransparency = 0 }):Play()

	task.delay(duration or 5, function()
		if subtitleToken == token then
			TweenService:Create(subtitle, Theme.Tween.Normal, { TextTransparency = 1 }):Play()
		end
	end)
end

--==========================================================================
-- Injured alerts
--==========================================================================

local function addInjured(payload: any)
	if payload.UserId == player.UserId then
		return -- your own state is on the status banner, not in the teammate list
	end
	if injured[payload.UserId] then
		injured[payload.UserId].ExpiresAt = payload.ExpiresAt
		return
	end

	local frame = Widgets.panel({
		Size = UDim2.new(0, 280, 0, 44),
		BackgroundColor3 = Theme.Colour.Crimson,
		BackgroundTransparency = 0.55,
		Parent = injuredList,
	})
	Widgets.padding(Theme.Padding.Tight, { Left = 10, Right = 10 }).Parent = frame

	local arrow = Widgets.label("▲", {
		Size = UDim2.new(0, 30, 1, 0),
		Font = Theme.Font.Heading,
		TextSize = 22,
		TextColor3 = Theme.Colour.CrimsonBright,
		TextXAlignment = Enum.TextXAlignment.Center,
		Parent = frame,
	})

	local nameLabel = Widgets.label(`{payload.Name} is down`, {
		Position = UDim2.new(0, 34, 0, 2),
		Size = UDim2.new(1, -34, 0, 18),
		Font = Theme.Font.Heading,
		TextSize = Theme.TextSize.Small,
		TextColor3 = Theme.Colour.Text,
		Parent = frame,
	})

	local timeLabel = Widgets.label("", {
		Position = UDim2.new(0, 34, 0, 20),
		Size = UDim2.new(1, -34, 0, 14),
		TextSize = Theme.TextSize.Tiny,
		TextColor3 = Theme.Colour.Bone,
		Parent = frame,
	})

	injured[payload.UserId] = {
		UserId = payload.UserId,
		Name = payload.Name,
		ExpiresAt = payload.ExpiresAt or (Util.now() + 30),
		Frame = frame,
		NameLabel = nameLabel,
		ArrowLabel = arrow,
		TimeLabel = timeLabel,
	}

	AlertController.toast(`{payload.Name} is injured!`, "Danger", 3)
end

local function removeInjured(userId: number)
	local entry = injured[userId]
	if not entry then
		return
	end
	injured[userId] = nil
	if entry.Frame.Parent then
		entry.Frame:Destroy()
	end
end

--[[
	Points the arrow at the downed player and reports the distance.

	The rotation is computed in camera space so "up" on the arrow always means
	"straight ahead", which is the only mapping people read correctly without
	thinking about it.
]]
local function updateInjuredArrows()
	local camera = Workspace.CurrentCamera
	if not camera then
		return
	end

	local origin = Util.getPosition(player) or camera.CFrame.Position

	for userId, entry in injured do
		local remaining = math.max(0, entry.ExpiresAt - Util.now())
		if remaining <= 0 then
			removeInjured(userId)
			continue
		end

		local target = Players:GetPlayerByUserId(userId)
		local targetPosition = target and Util.getPosition(target)

		if targetPosition then
			local toTarget = targetPosition - origin
			local flat = Vector3.new(toTarget.X, 0, toTarget.Z)

			local look = camera.CFrame.LookVector
			local flatLook = Vector3.new(look.X, 0, look.Z)

			if flat.Magnitude > 0.1 and flatLook.Magnitude > 0.1 then
				local right = flatLook:Cross(Vector3.yAxis)
				local angle = math.atan2(flat.Unit:Dot(right), flat.Unit:Dot(flatLook.Unit))
				entry.ArrowLabel.Rotation = math.deg(angle)
			end

			entry.TimeLabel.Text = `{math.ceil(remaining)}s  -  {math.floor(flat.Magnitude)} studs away`
		else
			entry.TimeLabel.Text = `{math.ceil(remaining)}s`
		end

		-- Turns red and pulses as the clock runs out.
		local urgency = 1 - (remaining / 30)
		entry.Frame.BackgroundTransparency = 0.55 - urgency * 0.2
		if remaining <= 10 then
			local pulse = (math.sin(os.clock() * 8) + 1) / 2
			entry.ArrowLabel.TextColor3 = Theme.Colour.CrimsonBright:Lerp(Theme.Colour.Text, pulse * 0.6)
		end
	end
end

--==========================================================================
-- Construction
--==========================================================================

local function build()
	gui = Widgets.new("ScreenGui", {
		Name = "DollysHomeAlerts",
		ResetOnSpawn = false,
		IgnoreGuiInset = true,
		DisplayOrder = 12,
		Parent = player:WaitForChild("PlayerGui"),
	}) :: ScreenGui

	toastList = Widgets.new("Frame", {
		Name = "Toasts",
		AnchorPoint = Vector2.new(0.5, 1),
		Position = UDim2.new(0.5, 0, 1, -150),
		Size = UDim2.new(0, 400, 0, 200),
		BackgroundTransparency = 1,
		Parent = gui,
	}) :: Frame
	Widgets.new("UIListLayout", {
		FillDirection = Enum.FillDirection.Vertical,
		VerticalAlignment = Enum.VerticalAlignment.Bottom,
		HorizontalAlignment = Enum.HorizontalAlignment.Center,
		Padding = UDim.new(0, 5),
		SortOrder = Enum.SortOrder.LayoutOrder,
		Parent = toastList,
	})

	injuredList = Widgets.new("Frame", {
		Name = "Injured",
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.new(1, -16, 0, Theme.TopBarInset),
		Size = UDim2.new(0, 280, 0, 300),
		BackgroundTransparency = 1,
		Parent = gui,
	}) :: Frame
	Widgets.new("UIListLayout", {
		FillDirection = Enum.FillDirection.Vertical,
		HorizontalAlignment = Enum.HorizontalAlignment.Right,
		Padding = UDim.new(0, 6),
		SortOrder = Enum.SortOrder.LayoutOrder,
		Parent = injuredList,
	})

	--[[
		Dialogue subtitles.

		Moved well clear of the bottom of the screen: at -110 they landed inside
		the map-vote panel during the intermission, and the flavour font at body
		size with a heavy stroke turned into an unreadable smear over the game
		world. Bigger text, a lighter stroke, and its own strip of screen.
	]]
	subtitle = Widgets.new("TextLabel", {
		Name = "Subtitle",
		AnchorPoint = Vector2.new(0.5, 1),
		Position = UDim2.new(0.5, 0, 1, -260),
		Size = UDim2.new(0, 720, 0, 34),
		BackgroundTransparency = 1,
		Font = Theme.Font.Flavour,
		TextSize = Theme.TextSize.Title,
		TextXAlignment = Enum.TextXAlignment.Center,
		TextTransparency = 1,
		TextColor3 = Theme.Colour.Bone,
		Parent = gui,
	}) :: TextLabel

	Widgets.new("UIStroke", {
		Color = Color3.new(0, 0, 0),
		Thickness = 3,
		Transparency = 0,
		Parent = subtitle,
	})
end

--==========================================================================
-- Lifecycle
--==========================================================================

function AlertController.start()
	build()

	Net.Events.TaskCompleted.OnClientEvent:Connect(function(payload)
		AlertController.toast(`{payload.Label} -- done!`, "Task", 5)
	end)

	Net.Events.TaskProgress.OnClientEvent:Connect(function(payload)
		if payload.Complete then
			return -- TaskCompleted already covers it
		end
		if payload.By then
			AlertController.toast(`{payload.Label}  {payload.Current}/{payload.Goal}`, "Info", 2)
		end
	end)

	Net.Events.InjuredAlert.OnClientEvent:Connect(function(payload)
		if payload.Kind == "Downed" then
			addInjured(payload)
		elseif payload.Kind == "Revived" then
			removeInjured(payload.UserId)
			if payload.ReviverName then
				AlertController.toast(`{payload.ReviverName} revived {payload.Name}`, "Success", 3)
			end
		elseif payload.Kind == "Eliminated" then
			removeInjured(payload.UserId)
			AlertController.toast(`{payload.Name} didn't make it.`, "Danger", 4)
		end
	end)

	Net.Events.HelperMessage.OnClientEvent:Connect(function(payload)
		AlertController.subtitle(payload.Helper, payload.Text, Theme.Colour.Ghost, 6)
		if payload.SafeZone then
			AlertController.toast("Robby has opened sanctified ground nearby.", "Helper", 5)
		end
	end)

	Net.Events.Announce.OnClientEvent:Connect(function(payload)
		if type(payload) ~= "table" then
			return
		end

		local kind = payload.Kind

		if kind == "KillerLine" then
			AlertController.subtitle(payload.Speaker, payload.Text, Theme.Colour.CrimsonBright, 5)
		elseif kind == "Stake" then
			AlertController.toast(
				`{payload.Text}  ({math.floor(payload.Health)}/{payload.MaxHealth} -- stunned {payload.StunSeconds}s)`,
				"Stake",
				4
			)
		elseif kind == "MapChosen" or kind == "Objective" or kind == "Waiting" or kind == "Spectating" then
			AlertController.toast(payload.Text, "Objective", 4)
		elseif kind == "Danger" then
			AlertController.toast(payload.Text, "Danger", 3)
		elseif kind == "Combat" then
			AlertController.toast(payload.Text, "Combat", 2)
		elseif kind == "ShopSuccess" then
			AlertController.toast(payload.Text, "Success", 3)
		elseif kind == "ShopError" then
			AlertController.toast(payload.Text, "Error", 3)
		elseif kind == "Error" then
			AlertController.toast(payload.Text, "Error", 4)
		end
	end)

	-- Clear round-scoped chatter between rounds. Without this a killer's last
	-- line, or Robby's, hangs around into the lobby.
	Net.getState():GetAttributeChangedSignal(StateKeys.Game.Phase):Connect(function()
		local phase = Net.getStateValue(StateKeys.Game.Phase, "")
		if phase ~= StateKeys.Phase.Active then
			for userId in injured do
				removeInjured(userId)
			end
			subtitleToken += 1
			subtitle.TextTransparency = 1
		end
	end)

	RunService.RenderStepped:Connect(function()
		local ok = pcall(updateInjuredArrows)
		if not ok then
			-- A player leaving mid-frame is the usual cause; the next frame is fine.
		end
	end)
end

return AlertController
