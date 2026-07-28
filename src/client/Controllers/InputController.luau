--!strict
--[[
	InputController.luau
	--------------------------------------------------------------------------
	Keyboard, gamepad and touch input.

	Everything is bound through ContextActionService rather than
	UserInputService, because CAS gives us mobile buttons for free -- pass
	`createTouchButton = true` and phone players get a real control instead of
	nothing. Given that most Roblox horror players are on phones, that isn't
	optional.

	Nothing here decides anything. Sprint sends intent to the server, which
	owns speed; attack sends intent, which the server validates. A client that
	spams these gets no advantage.
	--------------------------------------------------------------------------
]]

local ContextActionService = game:GetService("ContextActionService")
local Players = game:GetService("Players")
local UserInputService = game:GetService("UserInputService")

local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
local Config = require(Shared.Config)
local Net = require(Shared.Net)
local StateKeys = require(Shared.StateKeys)

local player = Players.LocalPlayer

local InputController = {}

local ACTION_SPRINT = "DollysHome_Sprint"
local ACTION_CROUCH = "DollysHome_Crouch"
local ACTION_ATTACK = "DollysHome_Attack"
local ACTION_HIDE = "DollysHome_LeaveHiding"
local ACTION_HEAL = "DollysHome_Heal"
local ACTION_SPEED = "DollysHome_Speed"

local sprinting = false
local crouching = false

--==========================================================================
-- Guards
--==========================================================================

--- Input is ignored while downed, eliminated, or between rounds.
local function canAct(): boolean
	if player:GetAttribute(StateKeys.Player.Injured) == true then
		return false
	end
	if player:GetAttribute(StateKeys.Player.Eliminated) == true then
		return false
	end
	return Net.getStateValue(StateKeys.Game.Phase, "") == StateKeys.Phase.Active
end

--==========================================================================
-- Handlers
--==========================================================================

local function onSprint(_action: string, state: Enum.UserInputState): Enum.ContextActionResult
	if state == Enum.UserInputState.Begin then
		if not canAct() then
			return Enum.ContextActionResult.Pass
		end
		sprinting = true
	elseif state == Enum.UserInputState.End or state == Enum.UserInputState.Cancel then
		sprinting = false
	else
		return Enum.ContextActionResult.Pass
	end

	Net.Events.SetSprinting:FireServer(sprinting)
	return Enum.ContextActionResult.Sink
end

local function onCrouch(_action: string, state: Enum.UserInputState): Enum.ContextActionResult
	if state ~= Enum.UserInputState.Begin then
		return Enum.ContextActionResult.Pass
	end
	if not canAct() then
		return Enum.ContextActionResult.Pass
	end

	-- Toggle rather than hold: crouch-walking is something you do for a whole
	-- corridor, and holding a key for thirty seconds is miserable on a phone.
	crouching = not crouching
	Net.Events.SetCrouching:FireServer(crouching)
	return Enum.ContextActionResult.Sink
end

local function onAttack(_action: string, state: Enum.UserInputState): Enum.ContextActionResult
	if state ~= Enum.UserInputState.Begin then
		return Enum.ContextActionResult.Pass
	end
	if not canAct() then
		return Enum.ContextActionResult.Pass
	end
	if player:GetAttribute(StateKeys.Player.Hidden) == true then
		return Enum.ContextActionResult.Pass
	end

	Net.Events.Attack:FireServer()
	return Enum.ContextActionResult.Sink
end

local function onLeaveHiding(_action: string, state: Enum.UserInputState): Enum.ContextActionResult
	if state ~= Enum.UserInputState.Begin then
		return Enum.ContextActionResult.Pass
	end
	if player:GetAttribute(StateKeys.Player.Hidden) ~= true then
		return Enum.ContextActionResult.Pass
	end

	Net.Events.RequestHide:FireServer()
	return Enum.ContextActionResult.Sink
end

local function useConsumable(itemId: string)
	return function(_action: string, state: Enum.UserInputState): Enum.ContextActionResult
		if state ~= Enum.UserInputState.Begin then
			return Enum.ContextActionResult.Pass
		end
		Net.Events.UseConsumable:FireServer(itemId)
		return Enum.ContextActionResult.Sink
	end
end

--==========================================================================
-- Lifecycle
--==========================================================================

function InputController.start()
	local touch = UserInputService.TouchEnabled

	ContextActionService:BindAction(
		ACTION_SPRINT,
		onSprint,
		touch,
		Enum.KeyCode.LeftShift,
		Enum.KeyCode.RightShift,
		Enum.KeyCode.ButtonL3
	)
	ContextActionService:SetTitle(ACTION_SPRINT, "RUN")

	ContextActionService:BindAction(ACTION_CROUCH, onCrouch, touch, Enum.KeyCode.C, Enum.KeyCode.ButtonB)
	ContextActionService:SetTitle(ACTION_CROUCH, "CROUCH")

	ContextActionService:BindAction(
		ACTION_ATTACK,
		onAttack,
		touch,
		Enum.UserInputType.MouseButton1,
		Enum.KeyCode.ButtonR2
	)
	ContextActionService:SetTitle(ACTION_ATTACK, "STAKE")

	ContextActionService:BindAction(ACTION_HIDE, onLeaveHiding, touch, Enum.KeyCode.Q, Enum.KeyCode.ButtonY)
	ContextActionService:SetTitle(ACTION_HIDE, "EXIT")

	ContextActionService:BindAction(ACTION_HEAL, useConsumable(Config.Shop.HealthPotion.Id), false, Enum.KeyCode.One)
	ContextActionService:BindAction(ACTION_SPEED, useConsumable(Config.Shop.SpeedPotion.Id), false, Enum.KeyCode.Two)

	-- Position the touch buttons out of the way of the movement thumbstick.
	if touch then
		ContextActionService:SetPosition(ACTION_SPRINT, UDim2.new(1, -160, 1, -180))
		ContextActionService:SetPosition(ACTION_ATTACK, UDim2.new(1, -90, 1, -180))
		ContextActionService:SetPosition(ACTION_CROUCH, UDim2.new(1, -160, 1, -110))
		ContextActionService:SetPosition(ACTION_HIDE, UDim2.new(1, -90, 1, -110))
	end

	-- Release the sprint flag if the round ends or the player goes down while
	-- the key is still held, so they don't come back stuck at sprint speed.
	local function clearIfNeeded()
		if sprinting and not canAct() then
			sprinting = false
			Net.Events.SetSprinting:FireServer(false)
		end
		if crouching and not canAct() then
			crouching = false
			Net.Events.SetCrouching:FireServer(false)
		end
	end

	player:GetAttributeChangedSignal(StateKeys.Player.Injured):Connect(clearIfNeeded)
	player:GetAttributeChangedSignal(StateKeys.Player.Eliminated):Connect(clearIfNeeded)
	Net.getState():GetAttributeChangedSignal(StateKeys.Game.Phase):Connect(clearIfNeeded)
end

function InputController.isCrouching(): boolean
	return crouching
end

return InputController
