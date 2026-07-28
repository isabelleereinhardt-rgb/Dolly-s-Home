--!nonstrict
--[[
	Primitives.luau
	--------------------------------------------------------------------------
	The Luau equivalent of the primitive helpers in props.js, so the map data
	can be transcribed almost line for line.

	Three.js -> Roblox translation notes:

	  BoxGeometry      -> Part, Shape = Block                      (exact)
	  CylinderGeometry -> Part, Shape = Cylinder                   (see below)
	  SphereGeometry   -> Part, Shape = Ball, scaled               (exact enough)
	  RingGeometry     -> a thin Cylinder part                     (solid, not a ring)
	  CapsuleGeometry  -> Cylinder + two Balls                     (3 parts)
	  ConeGeometry     -> a short stack of shrinking cylinders     (approximation)
	  LatheGeometry    -> a stack of cylinders following the profile

	The one that trips people up: a Roblox Cylinder part's circular axis is X,
	not Y. A "standing" cylinder therefore needs a 90-degree roll. `cyl` below
	handles that, so callers can think in Three.js terms (height along Y).

	Cones and lathes are approximations by design -- the mockups are still being
	tweaked, so segment counts are kept low and readable rather than smooth.
	--------------------------------------------------------------------------
]]

local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
local Palette = require(Shared.Palette)

local Primitives = {}

-- Roblox Cylinder parts are circular around X; Three.js cylinders are around Y.
local STAND_UP = CFrame.Angles(0, 0, math.pi / 2)

--==========================================================================
-- Core
--==========================================================================

local function finish(part: BasePart, name: string, style: any, parent: Instance?): BasePart
	part.Name = name
	part.Anchored = true
	part.TopSurface = Enum.SurfaceType.Smooth
	part.BottomSurface = Enum.SurfaceType.Smooth
	if style then
		Palette.apply(part, style)
	end
	part.Parent = parent
	return part
end

--- Box from world-space bounds. Mirrors props.js `box(name, mat, x0,x1, y0,y1, z0,z1)`.
function Primitives.box(name, style, x0, x1, y0, y1, z0, z1, parent): BasePart
	local part = Instance.new("Part")
	part.Size = Vector3.new(math.abs(x1 - x0), math.abs(y1 - y0), math.abs(z1 - z0))
	part.CFrame = CFrame.new((x0 + x1) / 2, (y0 + y1) / 2, (z0 + z1) / 2)
	return finish(part, name, style, parent)
end

--- Box by centre + size, optional Y rotation. Mirrors props.js `part()`.
function Primitives.part(name, style, position: Vector3, size: Vector3, rotY: number?, parent): BasePart
	local part = Instance.new("Part")
	part.Size = size
	part.CFrame = CFrame.new(position) * CFrame.Angles(0, rotY or 0, 0)
	return finish(part, name, style, parent)
end

--- Cylinder standing on its end (height along Y), like Three.js.
function Primitives.cyl(name, style, position: Vector3, radius: number, height: number, rotY: number?, parent): BasePart
	local part = Instance.new("Part")
	part.Shape = Enum.PartType.Cylinder
	-- X is the circular axis, so X is the height and Y/Z are the diameter.
	part.Size = Vector3.new(height, radius * 2, radius * 2)
	part.CFrame = CFrame.new(position) * CFrame.Angles(0, rotY or 0, 0) * STAND_UP
	return finish(part, name, style, parent)
end

--- Sphere, optionally scaled per axis. Mirrors props.js `sph()`.
function Primitives.sph(name, style, position: Vector3, radius: number, scale: Vector3?, parent): BasePart
	local part = Instance.new("Part")
	part.Shape = Enum.PartType.Ball
	local s = scale or Vector3.one
	part.Size = Vector3.new(radius * 2 * s.X, radius * 2 * s.Y, radius * 2 * s.Z)
	part.CFrame = CFrame.new(position)
	return finish(part, name, style, parent)
end

--- Flat disc lying in the XZ plane. props.js uses a ring; a solid disc reads
--- the same from above and costs one part instead of a mesh.
function Primitives.disc(name, style, position: Vector3, radius: number, thickness: number?, parent): BasePart
	local part = Instance.new("Part")
	part.Shape = Enum.PartType.Cylinder
	part.Size = Vector3.new(thickness or 0.2, radius * 2, radius * 2)
	part.CFrame = CFrame.new(position) * STAND_UP
	part.CanCollide = false
	return finish(part, name, style, parent)
end

--==========================================================================
-- Composites
--==========================================================================

--- A capsule between two points: a cylinder with a ball on each end.
function Primitives.capsule(name, style, a: Vector3, b: Vector3, radius: number, parent): { BasePart }
	local delta = b - a
	local length = delta.Magnitude
	local out = {}

	if length > 0.02 then
		local shaft = Instance.new("Part")
		shaft.Shape = Enum.PartType.Cylinder
		shaft.Size = Vector3.new(length, radius * 2, radius * 2)
		-- lookAt points +Z down the axis; roll it so the cylinder's X aligns.
		shaft.CFrame = CFrame.lookAt((a + b) / 2, b) * CFrame.Angles(0, math.pi / 2, 0)
		table.insert(out, finish(shaft, name .. "_shaft", style, parent))
	end

	for index, point in { a, b } do
		local cap = Instance.new("Part")
		cap.Shape = Enum.PartType.Ball
		cap.Size = Vector3.new(radius * 2, radius * 2, radius * 2)
		cap.CFrame = CFrame.new(point)
		table.insert(out, finish(cap, `{name}_cap{index}`, style, parent))
	end

	return out
end

--- A cone / spike from `a` to `b`, approximated as a stack of shrinking discs.
function Primitives.cone(name, style, a: Vector3, b: Vector3, radius: number, segments: number?, parent): { BasePart }
	local steps = segments or 4
	local out = {}
	for index = 0, steps - 1 do
		local t0, t1 = index / steps, (index + 1) / steps
		local p0, p1 = a:Lerp(b, t0), a:Lerp(b, t1)
		local r = radius * (1 - (t0 + t1) / 2)
		if r > 0.01 then
			local segment = Instance.new("Part")
			segment.Shape = Enum.PartType.Cylinder
			segment.Size = Vector3.new((p1 - p0).Magnitude, r * 2, r * 2)
			segment.CFrame = CFrame.lookAt((p0 + p1) / 2, p1) * CFrame.Angles(0, math.pi / 2, 0)
			table.insert(out, finish(segment, `{name}_{index}`, style, parent))
		end
	end
	return out
end

--[[
	A lathe: a profile of {radius, y} pairs revolved around the Y axis,
	built as a stack of cylinders. Used for skirts, robes and bottles.
]]
function Primitives.lathe(name, style, profile: { { number } }, origin: Vector3, parent): { BasePart }
	local out = {}
	for index = 1, #profile - 1 do
		local r0, y0 = profile[index][1], profile[index][2]
		local r1, y1 = profile[index + 1][1], profile[index + 1][2]
		local height = math.abs(y1 - y0)
		local radius = math.max((r0 + r1) / 2, 0.02)
		if height > 0.02 and radius > 0.02 then
			table.insert(
				out,
				Primitives.cyl(
					`{name}_{index}`,
					style,
					origin + Vector3.new(0, (y0 + y1) / 2, 0),
					radius,
					height,
					nil,
					parent
				)
			)
		end
	end
	return out
end

--==========================================================================
-- Walls
--==========================================================================

export type Door = {
	c: number, -- centre along the wall run
	w: number?, -- width (default 5)
	h: number?, -- height (default 7.5)
	sill: number?, -- >0 makes it a window: wall is kept below this height
}

--[[
	A wall run between two [x, z] points with doorway and window gaps.
	Faithful port of props.js `wall()`.

	`a` and `b` are {x, z}. The run is treated as horizontal (along X) when the
	X span is the larger of the two, otherwise it runs along Z.
]]
function Primitives.wall(
	parent: Instance,
	name: string,
	style: any,
	a: { number },
	b: { number },
	y0: number,
	height: number,
	thickness: number?,
	doors: { any }?
): { BasePart }
	local t = thickness or 1
	local horizontal = math.abs(b[1] - a[1]) >= math.abs(b[2] - a[2])

	local lo = math.min(horizontal and a[1] or a[2], horizontal and b[1] or b[2])
	local hi = math.max(horizontal and a[1] or a[2], horizontal and b[1] or b[2])
	local fixed = horizontal and a[2] or a[1]

	-- Normalise: a bare number means a plain doorway at that centre.
	local openings = {}
	for _, entry in doors or {} do
		local door
		if type(entry) == "number" then
			door = { c = entry, w = 5, h = 7.5, sill = 0 }
		else
			door = {
				c = entry.c,
				w = entry.w or 5,
				h = entry.h or 7.5,
				sill = entry.sill or 0,
			}
		end
		table.insert(openings, door)
	end
	table.sort(openings, function(p, q)
		return p.c < q.c
	end)

	-- Build the list of solid segments as {start, finish, bottomY, topY}.
	local segments = {}
	local cursor = lo
	for _, door in openings do
		local s = math.max(lo, door.c - door.w / 2)
		local e = math.min(hi, door.c + door.w / 2)
		if s > cursor then
			table.insert(segments, { cursor, s, 0, height })
		end
		if door.sill > 0 then
			table.insert(segments, { s, e, 0, door.sill }) -- wall beneath a window
		end
		if door.h < height then
			table.insert(segments, { s, e, door.h, height }) -- lintel above
		end
		cursor = math.max(cursor, e)
	end
	if cursor < hi then
		table.insert(segments, { cursor, hi, 0, height })
	end

	local built = {}
	for index, segment in segments do
		local s, e, by, ty = segment[1], segment[2], segment[3], segment[4]
		local length, segHeight = e - s, ty - by
		if length > 0.02 and segHeight > 0.02 then
			local part = Instance.new("Part")
			part.Size = if horizontal
				then Vector3.new(length, segHeight, t)
				else Vector3.new(t, segHeight, length)
			part.CFrame = CFrame.new(
				horizontal and (s + e) / 2 or fixed,
				y0 + by + segHeight / 2,
				horizontal and fixed or (s + e) / 2
			)
			table.insert(built, finish(part, `{name}_{index}`, style, parent))
		end
	end

	-- Glass in the window openings.
	for _, door in openings do
		if door.sill > 0 then
			local pane = Instance.new("Part")
			local paneHeight = door.h - door.sill - 0.4
			if paneHeight > 0.1 then
				pane.Size = if horizontal
					then Vector3.new(door.w - 0.5, paneHeight, 0.2)
					else Vector3.new(0.2, paneHeight, door.w - 0.5)
				pane.CFrame = CFrame.new(
					horizontal and door.c or fixed,
					y0 + door.sill + paneHeight / 2,
					horizontal and fixed or door.c
				)
				pane.CanCollide = false
				table.insert(built, finish(pane, "window_glass", "glass", parent))
			end
		end
	end

	return built
end

--==========================================================================
-- Stairs
--==========================================================================

--[[
	Steps from `from` to `to`. Built as real steps rather than a ramp because
	PathfindingService handles both, but steps read as architecture.

	Rise per step is kept under 2 studs so humanoids climb without jumping.
]]
function Primitives.stairs(name: string, style: any, from: Vector3, to: Vector3, width: number, parent: Instance): { BasePart }
	local delta = to - from
	local rise = math.abs(delta.Y)
	local stepCount = math.max(2, math.ceil(rise / 1.2))
	local horizontal = Vector3.new(delta.X, 0, delta.Z)
	local direction = horizontal.Magnitude > 0.01 and horizontal.Unit or Vector3.new(0, 0, 1)
	local run = horizontal.Magnitude
	local tread = run / stepCount
	local riser = delta.Y / stepCount

	local out = {}
	for index = 1, stepCount do
		local centre = from
			+ direction * (tread * (index - 0.5))
			+ Vector3.new(0, riser * index - math.abs(riser) / 2, 0)

		local step = Instance.new("Part")
		step.Size = Vector3.new(width, math.max(math.abs(riser), 0.6), tread)
		step.CFrame = CFrame.lookAt(centre, centre + direction)
		table.insert(out, finish(step, `{name}_step{index}`, style, parent))
	end
	return out
end

--- A climbable truss, for the attic ladder. Humanoids and pathfinding both
--- understand TrussParts, which a decorative ladder of welded rungs would not.
function Primitives.ladder(name: string, bottom: Vector3, height: number, parent: Instance): BasePart
	local truss = Instance.new("TrussPart")
	truss.Name = name
	truss.Anchored = true
	truss.Size = Vector3.new(2, height, 2)
	truss.CFrame = CFrame.new(bottom + Vector3.new(0, height / 2, 0))
	truss.Color = Color3.fromRGB(138, 116, 88)
	truss.Material = Enum.Material.Wood
	truss.Parent = parent
	return truss
end

return Primitives
