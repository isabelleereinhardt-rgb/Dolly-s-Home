--!strict
--[[
	SafeZoneService.luau
	--------------------------------------------------------------------------
	Tracks which players are standing inside an active safe zone and sets the
	InSafeZone attribute accordingly.

	Two things read that attribute: KillerAgent (which refuses to target or
	attack anyone inside one) and the HUD (which shows the player they're safe).
	Keeping the check in one place means the permanent map safe zones and
	Robby's temporary ones behave identically without either system knowing
	about the other.
	--------------------------------------------------------------------------
]]

local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")

local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
local StateKeys = require(Shared.StateKeys)
local Tags = require(Shared.Tags)
local Util = require(Shared.Util)

local SafeZoneService = {}

local ZONE_TAGS = { Tags.SafeZone, Tags.TempSafeZone }

--- Radius of a zone part -- explicit attribute if set, otherwise inferred.
local function radiusOf(zone: BasePart): number
	local explicit = zone:GetAttribute("Radius") :: number?
	if explicit then
		return explicit
	end
	return math.max(zone.Size.X, zone.Size.Z) / 2
end

--- Returns the zone containing this position, or nil.
function SafeZoneService.zoneAt(position: Vector3): BasePart?
	for _, tag in ZONE_TAGS do
		for _, zone in CollectionService:GetTagged(tag) do
			if not zone:IsA("BasePart") or not zone.Parent then
				continue
			end
			-- Skip zones inside ServerStorage map templates; only the live map
			-- counts. (CollectionService returns everything under `game`.)
			if not zone:IsDescendantOf(workspace) then
				continue
			end
			if zone:GetAttribute("Active") == false then
				continue
			end
			-- Compare in the zone's own space so rotated / rectangular zones
			-- behave sensibly rather than always being treated as circles.
			local localPoint = zone.CFrame:PointToObjectSpace(position)
			local half = zone.Size / 2
			if
				math.abs(localPoint.X) <= half.X
				and math.abs(localPoint.Z) <= half.Z
				and math.abs(localPoint.Y) <= math.max(half.Y, 8)
			then
				return zone
			end
		end
	end
	return nil
end

--- Creates a temporary safe zone (Robby's doing). Returns the part.
function SafeZoneService.createTemporary(position: Vector3, radius: number, duration: number): BasePart
	local zone = Instance.new("Part")
	zone.Name = "TemporarySafeZone"
	zone.Shape = Enum.PartType.Cylinder
	zone.Size = Vector3.new(14, radius * 2, radius * 2)
	zone.CFrame = CFrame.new(position + Vector3.new(0, 5, 0)) * CFrame.Angles(0, 0, math.pi / 2)
	zone.Anchored = true
	zone.CanCollide = false
	zone.CanQuery = false
	zone.Material = Enum.Material.Neon
	zone.Color = Color3.fromRGB(140, 190, 255)
	zone.Transparency = 0.82
	zone:SetAttribute("Active", true)
	zone:SetAttribute("Radius", radius)
	zone.Parent = workspace
	CollectionService:AddTag(zone, Tags.TempSafeZone)

	local light = Instance.new("PointLight")
	light.Color = Color3.fromRGB(150, 200, 255)
	light.Brightness = 2.5
	light.Range = radius * 2
	light.Parent = zone

	task.delay(duration, function()
		if zone.Parent then
			-- Fade out so it doesn't just vanish out from under someone.
			for step = 1, 10 do
				zone.Transparency = 0.82 + (step / 10) * 0.18
				light.Brightness = 2.5 * (1 - step / 10)
				task.wait(0.05)
			end
			zone:Destroy()
		end
	end)

	return zone
end

function SafeZoneService.clearTemporary()
	for _, zone in CollectionService:GetTagged(Tags.TempSafeZone) do
		zone:Destroy()
	end
end

function SafeZoneService.start()
	task.spawn(function()
		while true do
			task.wait(0.2)
			for _, player in Players:GetPlayers() do
				local position = Util.getPosition(player)
				local inZone = position ~= nil and SafeZoneService.zoneAt(position) ~= nil
				if player:GetAttribute(StateKeys.Player.InSafeZone) ~= inZone then
					player:SetAttribute(StateKeys.Player.InSafeZone, inZone)
				end
			end
		end
	end)
end

return SafeZoneService
