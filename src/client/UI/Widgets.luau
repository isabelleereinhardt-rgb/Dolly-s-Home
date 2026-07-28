--!nonstrict
--[[
	Widgets.luau
	--------------------------------------------------------------------------
	A tiny declarative layer over Instance.new, plus the handful of composite
	widgets the HUD reuses.

	Building the UI in code rather than shipping .rbxmx files keeps it
	reviewable in a diff -- you can see a colour change in a pull request
	instead of a binary blob.
	--------------------------------------------------------------------------
]]

local TweenService = game:GetService("TweenService")

local Theme = require(script.Parent.Theme)

local Widgets = {}

--==========================================================================
-- Core
--==========================================================================

--[[
	Widgets.new("Frame", { Size = ... }, { child, child })

	`props.Parent` is applied last so children exist before the instance enters
	the tree -- one reflow instead of several.
]]
function Widgets.new(className: string, props: { [string]: any }?, children: { Instance }?): any
	local instance = Instance.new(className)
	local parent = nil

	if props then
		parent = props.Parent
		for key, value in props do
			if key ~= "Parent" then
				(instance :: any)[key] = value
			end
		end
	end

	if children then
		for _, child in children do
			child.Parent = instance
		end
	end

	if parent then
		instance.Parent = parent
	end
	return instance
end

function Widgets.corner(radius: UDim?): UICorner
	return Widgets.new("UICorner", { CornerRadius = radius or Theme.Radius.Medium })
end

function Widgets.stroke(colour: Color3?, thickness: number?, transparency: number?): UIStroke
	return Widgets.new("UIStroke", {
		Color = colour or Theme.Colour.Divider,
		Thickness = thickness or 1,
		Transparency = transparency or 0,
		ApplyStrokeMode = Enum.ApplyStrokeMode.Border,
	})
end

function Widgets.padding(all: number?, overrides: { [string]: number }?): UIPadding
	local value = all or Theme.Padding.Normal
	local padding = Widgets.new("UIPadding", {
		PaddingTop = UDim.new(0, (overrides and overrides.Top) or value),
		PaddingBottom = UDim.new(0, (overrides and overrides.Bottom) or value),
		PaddingLeft = UDim.new(0, (overrides and overrides.Left) or value),
		PaddingRight = UDim.new(0, (overrides and overrides.Right) or value),
	})
	return padding
end

function Widgets.list(direction: Enum.FillDirection?, gap: number?, align: Enum.HorizontalAlignment?): UIListLayout
	return Widgets.new("UIListLayout", {
		FillDirection = direction or Enum.FillDirection.Vertical,
		Padding = UDim.new(0, gap or Theme.Padding.Tight),
		HorizontalAlignment = align or Enum.HorizontalAlignment.Left,
		SortOrder = Enum.SortOrder.LayoutOrder,
	})
end

--==========================================================================
-- Text
--==========================================================================

function Widgets.label(text: string, props: { [string]: any }?): TextLabel
	local merged: { [string]: any } = {
		Text = text,
		BackgroundTransparency = 1,
		Font = Theme.Font.Body,
		TextSize = Theme.TextSize.Body,
		TextColor3 = Theme.Colour.Text,
		TextXAlignment = Enum.TextXAlignment.Left,
		TextYAlignment = Enum.TextYAlignment.Center,
		Size = UDim2.new(1, 0, 0, 20),
	}
	if props then
		for key, value in props do
			merged[key] = value
		end
	end
	return Widgets.new("TextLabel", merged)
end

--- A label with an outline, for text sitting over the game world.
function Widgets.outlinedLabel(text: string, props: { [string]: any }?): TextLabel
	local label = Widgets.label(text, props)
	Widgets.new("UIStroke", {
		Color = Color3.new(0, 0, 0),
		Thickness = 2,
		Transparency = 0.35,
		Parent = label,
	})
	return label
end

--==========================================================================
-- Containers
--==========================================================================

function Widgets.panel(props: { [string]: any }?, children: { Instance }?): Frame
	local merged: { [string]: any } = {
		BackgroundColor3 = Theme.Colour.Panel,
		BackgroundTransparency = 0.12,
		BorderSizePixel = 0,
	}
	if props then
		for key, value in props do
			merged[key] = value
		end
	end

	local frame = Widgets.new("Frame", merged, children) :: Frame
	Widgets.corner(Theme.Radius.Medium).Parent = frame
	Widgets.stroke(Theme.Colour.Divider, 1, 0.4).Parent = frame
	return frame
end

--==========================================================================
-- Bars
--==========================================================================

export type Bar = {
	Root: Frame,
	Fill: Frame,
	Label: TextLabel,
	set: (self: Bar, alpha: number, text: string?, colour: Color3?) -> (),
}

--[[
	A labelled progress bar. `set` tweens the fill so a noise spike reads as a
	surge rather than a jump.
]]
function Widgets.bar(labelText: string, colour: Color3, props: { [string]: any }?): Bar
	local root = Widgets.new("Frame", {
		BackgroundTransparency = 1,
		Size = UDim2.new(1, 0, 0, 34),
	})
	if props then
		for key, value in props do
			(root :: any)[key] = value
		end
	end

	local caption = Widgets.label(labelText, {
		Size = UDim2.new(1, 0, 0, 14),
		Font = Theme.Font.Heading,
		TextSize = Theme.TextSize.Tiny,
		TextColor3 = Theme.Colour.TextDim,
		Parent = root,
	})

	local track = Widgets.new("Frame", {
		Position = UDim2.new(0, 0, 0, 17),
		Size = UDim2.new(1, 0, 0, 12),
		BackgroundColor3 = Theme.Colour.PanelSunken,
		BorderSizePixel = 0,
		Parent = root,
	}) :: Frame
	Widgets.corner(Theme.Radius.Small).Parent = track

	local fill = Widgets.new("Frame", {
		Size = UDim2.new(0, 0, 1, 0),
		BackgroundColor3 = colour,
		BorderSizePixel = 0,
		Parent = track,
	}) :: Frame
	Widgets.corner(Theme.Radius.Small).Parent = fill

	local bar: Bar
	bar = {
		Root = root,
		Fill = fill,
		Label = caption,
		set = function(_self, alpha: number, text: string?, newColour: Color3?)
			local clamped = math.clamp(alpha, 0, 1)
			TweenService:Create(fill, Theme.Tween.Fast, { Size = UDim2.new(clamped, 0, 1, 0) }):Play()
			if newColour then
				TweenService:Create(fill, Theme.Tween.Fast, { BackgroundColor3 = newColour }):Play()
			end
			if text then
				caption.Text = text
			end
		end,
	}
	return bar
end

--==========================================================================
-- Buttons
--==========================================================================

--- A text button with press and hover feedback wired up.
function Widgets.button(text: string, props: { [string]: any }?): TextButton
	local merged: { [string]: any } = {
		Text = text,
		Font = Theme.Font.Heading,
		TextSize = Theme.TextSize.Body,
		TextColor3 = Theme.Colour.Text,
		BackgroundColor3 = Theme.Colour.PanelRaised,
		BorderSizePixel = 0,
		AutoButtonColor = false,
		Size = UDim2.new(0, 160, 0, 40),
	}
	if props then
		for key, value in props do
			merged[key] = value
		end
	end

	local button = Widgets.new("TextButton", merged) :: TextButton
	Widgets.corner(Theme.Radius.Medium).Parent = button
	Widgets.stroke(Theme.Colour.Divider, 1, 0.3).Parent = button

	local base = button.BackgroundColor3
	local hover = base:Lerp(Color3.new(1, 1, 1), 0.12)

	button.MouseEnter:Connect(function()
		TweenService:Create(button, Theme.Tween.Fast, { BackgroundColor3 = hover }):Play()
	end)
	button.MouseLeave:Connect(function()
		TweenService:Create(button, Theme.Tween.Fast, { BackgroundColor3 = base }):Play()
	end)
	button.MouseButton1Down:Connect(function()
		TweenService:Create(button, Theme.Tween.Fast, { BackgroundTransparency = 0.25 }):Play()
	end)
	button.MouseButton1Up:Connect(function()
		TweenService:Create(button, Theme.Tween.Fast, { BackgroundTransparency = 0 }):Play()
	end)

	return button
end

--==========================================================================
-- Effects
--==========================================================================

--- Counts a number up, MM2-style. Returns immediately; runs in its own thread.
function Widgets.countUp(label: TextLabel, from: number, to: number, duration: number, format: ((number) -> string)?)
	task.spawn(function()
		local start = os.clock()
		local render = format or function(value: number)
			return tostring(math.floor(value))
		end
		while true do
			local alpha = math.min(1, (os.clock() - start) / duration)
			-- Ease out, so it slams up then settles.
			local eased = 1 - (1 - alpha) ^ 3
			label.Text = render(from + (to - from) * eased)
			if alpha >= 1 then
				break
			end
			task.wait()
		end
		label.Text = render(to)
	end)
end

--- Fades an instance's Transparency-ish property in from hidden.
function Widgets.fadeIn(instance: Instance, property: string, target: number, tweenInfo: TweenInfo?)
	local any = instance :: any
	any[property] = 1
	TweenService:Create(instance, tweenInfo or Theme.Tween.Normal, { [property] = target }):Play()
end

Widgets.Theme = Theme

return Widgets
