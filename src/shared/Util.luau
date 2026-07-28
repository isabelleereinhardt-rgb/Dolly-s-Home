--!nonstrict
--[[
	Util.luau
	--------------------------------------------------------------------------
	Small shared helpers. Nothing here knows anything about Dolly's Home
	specifically -- it's all generic plumbing.
	--------------------------------------------------------------------------
]]

local Players = game:GetService("Players")
local Workspace = game:GetService("Workspace")

local Util = {}

--==========================================================================
-- Time
--==========================================================================

--- Server-synced clock. Safe to compare across server and client.
function Util.now(): number
	return Workspace:GetServerTimeNow()
end

--- Formats seconds as M:SS (clamped at zero).
function Util.formatClock(seconds: number): string
	local total = math.max(0, math.floor(seconds))
	return string.format("%d:%02d", total // 60, total % 60)
end

--==========================================================================
-- Characters
--==========================================================================

--- Returns (character, humanoid, rootPart) if the player has a live character.
function Util.getCharacterParts(player: Player): (Model?, Humanoid?, BasePart?)
	local character = player.Character
	if not character or not character.Parent then
		return nil, nil, nil
	end
	local humanoid = character:FindFirstChildOfClass("Humanoid")
	local root = character:FindFirstChild("HumanoidRootPart") :: BasePart?
	return character, humanoid, root
end

--- True if the player has a character with a humanoid above zero health.
function Util.isCharacterAlive(player: Player): boolean
	local _, humanoid = Util.getCharacterParts(player)
	return humanoid ~= nil and humanoid.Health > 0
end

--- Position of a player's root part, or nil.
function Util.getPosition(player: Player): Vector3?
	local _, _, root = Util.getCharacterParts(player)
	return root and root.Position or nil
end

--- Owning Player of an instance inside a character model, or nil.
function Util.getPlayerFromDescendant(instance: Instance): Player?
	local model = instance:FindFirstAncestorOfClass("Model")
	while model do
		local player = Players:GetPlayerFromCharacter(model)
		if player then
			return player
		end
		model = model:FindFirstAncestorOfClass("Model")
	end
	return nil
end

--==========================================================================
-- Tables
--==========================================================================

--- Fisher-Yates, in place. Returns the same table for chaining.
function Util.shuffle<T>(list: { T }, rng: Random?): { T }
	local random = rng or Random.new()
	for i = #list, 2, -1 do
		local j = random:NextInteger(1, i)
		list[i], list[j] = list[j], list[i]
	end
	return list
end

--- One random element, or nil for an empty list.
function Util.pick<T>(list: { T }, rng: Random?): T?
	if #list == 0 then
		return nil
	end
	local random = rng or Random.new()
	return list[random:NextInteger(1, #list)]
end

--- Up to `count` distinct random elements.
function Util.pickMany<T>(list: { T }, count: number, rng: Random?): { T }
	local copy = table.clone(list)
	Util.shuffle(copy, rng)
	local out = {}
	for i = 1, math.min(count, #copy) do
		out[i] = copy[i]
	end
	return out
end

--- Shallow copy.
function Util.copy<T>(source: { [any]: any }): { [any]: any }
	local out = {}
	for key, value in source do
		out[key] = value
	end
	return out
end

--- Number of key/value pairs in a dictionary.
function Util.count(dict: { [any]: any }): number
	local n = 0
	for _ in dict do
		n += 1
	end
	return n
end

--==========================================================================
-- Instances
--==========================================================================

--- Instance.new plus a property table, in one call.
function Util.create(className: string, props: { [string]: any }?): any
	local instance = Instance.new(className)
	if props then
		local parent = props.Parent
		for key, value in props do
			if key ~= "Parent" then
				(instance :: any)[key] = value
			end
		end
		if parent then
			instance.Parent = parent
		end
	end
	return instance
end

--- Welds `part` to `to` with a WeldConstraint and makes it non-colliding.
function Util.weld(part: BasePart, to: BasePart)
	part.Anchored = false
	part.CanCollide = false
	local weld = Instance.new("WeldConstraint")
	weld.Part0 = part
	weld.Part1 = to
	weld.Parent = part
end

--- Attaches an Attachment at a local offset.
function Util.attachment(parent: BasePart, offset: Vector3?): Attachment
	local attachment = Instance.new("Attachment")
	attachment.Position = offset or Vector3.zero
	attachment.Parent = parent
	return attachment
end

--==========================================================================
-- Math
--==========================================================================

function Util.lerp(a: number, b: number, alpha: number): number
	return a + (b - a) * alpha
end

--- Frame-rate independent exponential approach. `speed` is roughly
--- "how many e-foldings per second".
function Util.damp(current: number, target: number, speed: number, dt: number): number
	return target + (current - target) * math.exp(-speed * dt)
end

--- Signed horizontal angle in degrees between a facing direction and a target.
function Util.angleTo(from: CFrame, target: Vector3): number
	local flatLook = Vector3.new(from.LookVector.X, 0, from.LookVector.Z)
	local flatDir = Vector3.new(target.X - from.Position.X, 0, target.Z - from.Position.Z)
	if flatLook.Magnitude < 1e-4 or flatDir.Magnitude < 1e-4 then
		return 0
	end
	local dot = math.clamp(flatLook.Unit:Dot(flatDir.Unit), -1, 1)
	return math.deg(math.acos(dot))
end

--==========================================================================
-- Debug
--==========================================================================

local Config = require(script.Parent.Config)

function Util.log(scope: string, message: string, ...: any)
	if Config.Debug.Verbose then
		print(`[DollysHome/{scope}] ` .. string.format(message, ...))
	end
end

function Util.warn(scope: string, message: string, ...: any)
	warn(`[DollysHome/{scope}] ` .. string.format(message, ...))
end

return Util
