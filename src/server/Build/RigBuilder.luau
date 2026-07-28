--!nonstrict
--[[
	RigBuilder.luau
	--------------------------------------------------------------------------
	Placeholder character rigs for the killers, the helper ghosts, and Ava.

	Same deal as MapBuilder: this exists so the AI, chases and stuns are all
	testable before anyone models a Victorian vampire. Drop a proper rig into
	ServerStorage/Killers/<Name> and KillerService uses that instead.

	A custom rig only needs three things for Humanoid:MoveTo and
	PathfindingService to work: a Humanoid, a part named HumanoidRootPart set as
	the model's PrimaryPart, and a sensible HipHeight. Everything else here is
	decoration welded on top.
	--------------------------------------------------------------------------
]]

local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
local KillerData = require(Shared.KillerData)

local RigBuilder = {}

local ROOT_SIZE = Vector3.new(3, 3.2, 1.8)
local HIP_HEIGHT = 2.2

local function limb(name: string, size: Vector3, color: Color3, parent: Model, root: BasePart, offset: CFrame): BasePart
	local p = Instance.new("Part")
	p.Name = name
	p.Size = size
	p.Color = color
	p.Material = Enum.Material.SmoothPlastic
	p.CanCollide = false
	p.CanQuery = false
	p.Massless = true
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	p.CFrame = root.CFrame * offset
	p.Parent = parent

	local weld = Instance.new("WeldConstraint")
	weld.Part0 = root
	weld.Part1 = p
	weld.Parent = p
	return p
end

--[[
	Builds a rig for a family member.

	`ghostly` renders the rig translucent and non-colliding -- used for Robby,
	Benny and Ava, who are present but not physical.
]]
function RigBuilder.build(killerId: string, ghostly: boolean?): Model?
	local profile = KillerData.get(killerId)
	if not profile then
		return nil
	end

	local scale = profile.Scale
	local isGhost = ghostly == true

	local model = Instance.new("Model")
	model.Name = profile.Name

	-- Body / root ---------------------------------------------------------
	local root = Instance.new("Part")
	root.Name = "HumanoidRootPart"
	root.Size = ROOT_SIZE * scale
	root.Color = profile.BodyColor
	root.Material = isGhost and Enum.Material.ForceField or Enum.Material.SmoothPlastic
	root.Transparency = isGhost and 0.45 or 0
	root.CanCollide = not isGhost
	root.TopSurface = Enum.SurfaceType.Smooth
	root.BottomSurface = Enum.SurfaceType.Smooth
	root.Parent = model
	model.PrimaryPart = root

	local torsoTop = (ROOT_SIZE.Y / 2) * scale

	-- Head ----------------------------------------------------------------
	local head = limb(
		"Head",
		Vector3.new(1.9, 1.9, 1.9) * scale,
		profile.BodyColor:Lerp(Color3.new(1, 1, 1), 0.15),
		model,
		root,
		CFrame.new(0, torsoTop + 0.95 * scale, 0)
	)
	head.Shape = Enum.PartType.Block
	head.Transparency = root.Transparency
	head.Material = root.Material

	-- Eyes: the only bright thing on the model, so you register a killer in a
	-- dark room the instant it turns toward you.
	for _, side in { -1, 1 } do
		local eye = limb(
			"Eye",
			Vector3.new(0.34, 0.22, 0.2) * scale,
			profile.EyeColor,
			model,
			root,
			CFrame.new(side * 0.42 * scale, torsoTop + 1.05 * scale, -0.95 * scale)
		)
		eye.Material = Enum.Material.Neon
		eye.Transparency = 0

		local glow = Instance.new("PointLight")
		glow.Color = profile.EyeColor
		glow.Brightness = 0.7
		glow.Range = 9
		glow.Parent = eye
	end

	-- Arms ----------------------------------------------------------------
	local armSize = Vector3.new(1, 2.9, 1) * scale
	limb("RightArm", armSize, profile.AccentColor, model, root, CFrame.new(2 * scale, -0.1 * scale, 0))
	-- Bob lost his right hand to Barbara. His arm ends early.
	local leftLength = (killerId == "Bob") and 1.8 or 2.9
	limb(
		"LeftArm",
		Vector3.new(1, leftLength, 1) * scale,
		profile.AccentColor,
		model,
		root,
		CFrame.new(-2 * scale, (-0.1 + (2.9 - leftLength) / 2) * scale, 0)
	)

	-- Legs ----------------------------------------------------------------
	local legSize = Vector3.new(1.15, HIP_HEIGHT, 1.15) * scale
	for _, side in { -1, 1 } do
		limb(
			"Leg",
			legSize,
			profile.AccentColor:Lerp(Color3.new(0, 0, 0), 0.3),
			model,
			root,
			CFrame.new(side * 0.75 * scale, -(torsoTop + (HIP_HEIGHT / 2) * scale), 0)
		)
	end

	-- Humanoid ------------------------------------------------------------
	local humanoid = Instance.new("Humanoid")
	humanoid.Name = "Humanoid"
	humanoid.HipHeight = HIP_HEIGHT * scale
	humanoid.RequiresNeck = false -- there is no Motor6D neck on this rig
	humanoid.BreakJointsOnDeath = false
	humanoid.AutoRotate = true
	humanoid.MaxSlopeAngle = 65
	humanoid.DisplayDistanceType = Enum.HumanoidDisplayDistanceType.None
	humanoid.NameDisplayDistance = 0
	humanoid.HealthDisplayDistance = 0
	-- Killers are immortal. Their "health" is tracked as an attribute by
	-- CombatService; this Humanoid must never actually die.
	humanoid.MaxHealth = math.huge
	humanoid.Health = math.huge
	humanoid.WalkSpeed = profile.PatrolSpeed
	humanoid.Parent = model

	if isGhost then
		-- Ghosts drift; they don't need to path around furniture.
		humanoid.WalkSpeed = 8
	end

	return model
end

--[[
	Ava's grave ghost. She isn't in KillerData (she isn't family any more), so
	she gets her own small builder.
]]
function RigBuilder.buildAva(): Model
	local model = Instance.new("Model")
	model.Name = "Ava"

	local root = Instance.new("Part")
	root.Name = "HumanoidRootPart"
	root.Size = Vector3.new(2.6, 3, 1.6)
	root.Color = Color3.fromRGB(180, 190, 215)
	root.Material = Enum.Material.ForceField
	root.Transparency = 0.5
	root.Anchored = true
	root.CanCollide = false
	root.Parent = model
	model.PrimaryPart = root

	local head = limb("Head", Vector3.new(1.7, 1.7, 1.7), Color3.fromRGB(205, 212, 230), model, root, CFrame.new(0, 2.3, 0))
	head.Anchored = true
	head.Material = Enum.Material.ForceField
	head.Transparency = 0.4

	local glow = Instance.new("PointLight")
	glow.Color = Color3.fromRGB(160, 190, 255)
	glow.Brightness = 1.6
	glow.Range = 22
	glow.Parent = root

	local humanoid = Instance.new("Humanoid")
	humanoid.RequiresNeck = false
	humanoid.BreakJointsOnDeath = false
	humanoid.MaxHealth = math.huge
	humanoid.Health = math.huge
	humanoid.WalkSpeed = 0
	humanoid.DisplayDistanceType = Enum.HumanoidDisplayDistanceType.None
	humanoid.Parent = model

	return model
end

return RigBuilder
