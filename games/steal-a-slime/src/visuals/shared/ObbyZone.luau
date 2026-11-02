--!strict
--[[
	ObbyZone (pure; CFrame and Vector3 maths only, no Roblox API at load time)

	"Is the player in this zone?" for the obby's controllers (ObbyMoves: moon, dark and sticky walls; ObbyFx: lift
	columns and gusts). The player is a vertical line from `a` (low, near the feet) to `b` (high, near the head), not
	only the root's centre, so a body that visibly stands in a zone counts even while the root is just outside it.
	Zones are tested in their own frame, so a turned part (yaw, pitch or roll) and a moved part (pass the CFrame it
	has now) need nothing extra.

	  ObbyZone.body(root, down, up)                        -> (a, b)   the line from `down` under to `up` over root
	  ObbyZone.touches(cf, size, shape, a, b, side)        -> boolean  the line, grown `side` studs sideways, meets the
	                                                                    part (shape "box", "ball", "cylinder": a
	                                                                    Roblox cylinder, round round its X axis, or
	                                                                    "ellipsoid": the ball a Sphere SpecialMesh
	                                                                    stretches to fill the box, like a moon bubble)
	  ObbyZone.lineInEllipsoid(ax, ay, az, bx, by, bz, rx, ry, rz)
	                                                       -> boolean  exact: the line a..b (in the ellipsoid's frame,
	                                                                    from its centre) meets the ellipsoid of radii r
	  ObbyZone.nearestFace(cf, size, a, b)                 -> (number, Vector3)  studs from the line to the box and the
	                                                                    outward (world) normal of the face it is off
	  ObbyZone.bottomY(cf, size)                           -> number   the lowest world height of the box
	  ObbyZone.shapeOf(part)                               -> string   "box" | "ball" | "cylinder" | "ellipsoid"

	`side` only grows a part across (each axis by its horizontal share): a column grown by 1 is 1 wider all round but
	not taller, so the height a zone starts at stays exactly where it is drawn.
	Callers keep the edge steady with two pads: one to come in (the smaller) and one to stay in, so standing on the
	edge never flickers.
]]

local ObbyZone = {}

ObbyZone.STEP = 0.25 -- studs between the points tested along the body line

local function horizontal(v: Vector3): number
	return math.sqrt(math.max(0, 1 - v.Y * v.Y))
end

-- The points along a..b at most STEP apart (both ends included).
local function count(a: Vector3, b: Vector3): number
	return math.max(1, math.ceil((b - a).Magnitude / ObbyZone.STEP))
end

function ObbyZone.body(root: Vector3, down: number, up: number): (Vector3, Vector3)
	return root - Vector3.new(0, down, 0), root + Vector3.new(0, up, 0)
end

function ObbyZone.shapeOf(part: any): string
	-- A Sphere SpecialMesh draws the part as the ellipsoid inscribed in its box (ObbyParts' moon bubble), whatever
	-- its Shape: test what is drawn.
	local mesh = part:FindFirstChildOfClass("SpecialMesh")
	if mesh and mesh.MeshType == Enum.MeshType.Sphere then
		return "ellipsoid"
	end
	if part:IsA("Part") then
		local shape = part.Shape
		if shape == Enum.PartType.Ball then
			return "ball"
		elseif shape == Enum.PartType.Cylinder then
			return "cylinder"
		end
	end
	return "box"
end

-- Exact (no sampling): squash the ellipsoid to the unit ball, then the line's nearest point to the centre is where
-- |u + t d|^2 is least for t in 0..1.
function ObbyZone.lineInEllipsoid(
	ax: number,
	ay: number,
	az: number,
	bx: number,
	by: number,
	bz: number,
	rx: number,
	ry: number,
	rz: number
): boolean
	if rx <= 0 or ry <= 0 or rz <= 0 then
		return false
	end
	local ux, uy, uz = ax / rx, ay / ry, az / rz
	local dx, dy, dz = (bx - ax) / rx, (by - ay) / ry, (bz - az) / rz
	local dd = dx * dx + dy * dy + dz * dz
	local t = if dd > 1e-12 then math.clamp(-(ux * dx + uy * dy + uz * dz) / dd, 0, 1) else 0
	local px, py, pz = ux + dx * t, uy + dy * t, uz + dz * t
	return px * px + py * py + pz * pz <= 1
end

function ObbyZone.touches(cf: CFrame, size: Vector3, shape: string, a: Vector3, b: Vector3, side: number): boolean
	local gx = side * horizontal(cf.XVector)
	local gy = side * horizontal(cf.YVector)
	local gz = side * horizontal(cf.ZVector)
	local hx, hy, hz = size.X / 2, size.Y / 2, size.Z / 2
	if shape == "ellipsoid" then
		local qa, qb = cf:PointToObjectSpace(a), cf:PointToObjectSpace(b)
		return ObbyZone.lineInEllipsoid(qa.X, qa.Y, qa.Z, qb.X, qb.Y, qb.Z, hx + gx, hy + gy, hz + gz)
	end
	local n = count(a, b)
	for i = 0, n do
		local q = cf:PointToObjectSpace(a + (b - a) * (i / n))
		if shape == "ball" then
			if q.Magnitude <= hx + side then
				return true
			end
		elseif shape == "cylinder" then
			local r = math.min(hy, hz) + side
			if math.abs(q.X) <= hx + gx and q.Y * q.Y + q.Z * q.Z <= r * r then
				return true
			end
		elseif math.abs(q.X) <= hx + gx and math.abs(q.Y) <= hy + gy and math.abs(q.Z) <= hz + gz then
			return true
		end
	end
	return false
end

function ObbyZone.nearestFace(cf: CFrame, size: Vector3, a: Vector3, b: Vector3): (number, Vector3)
	local h = size / 2
	local n = count(a, b)
	local best = math.huge
	local bestQ = Vector3.zero
	local bestD = Vector3.zero
	for i = 0, n do
		local q = cf:PointToObjectSpace(a + (b - a) * (i / n))
		local c = Vector3.new(math.clamp(q.X, -h.X, h.X), math.clamp(q.Y, -h.Y, h.Y), math.clamp(q.Z, -h.Z, h.Z))
		local d = q - c
		local distance = d.Magnitude
		if distance < best then
			best, bestQ, bestD = distance, q, d
		end
	end
	local axis: Vector3
	if best > 1e-4 then
		-- off the face it sticks out of most
		local ax, ay, az = math.abs(bestD.X), math.abs(bestD.Y), math.abs(bestD.Z)
		axis = if ax >= ay and ax >= az
			then Vector3.new(if bestD.X < 0 then -1 else 1, 0, 0)
			elseif az >= ay then Vector3.new(0, 0, if bestD.Z < 0 then -1 else 1)
			else Vector3.new(0, if bestD.Y < 0 then -1 else 1, 0)
	else
		-- inside the box (it moved into you): the face it is least deep behind
		local px, py, pz = h.X - math.abs(bestQ.X), h.Y - math.abs(bestQ.Y), h.Z - math.abs(bestQ.Z)
		axis = if px <= py and px <= pz
			then Vector3.new(if bestQ.X < 0 then -1 else 1, 0, 0)
			elseif pz <= py then Vector3.new(0, 0, if bestQ.Z < 0 then -1 else 1)
			else Vector3.new(0, if bestQ.Y < 0 then -1 else 1, 0)
		best = 0
	end
	return best, cf:VectorToWorldSpace(axis)
end

function ObbyZone.bottomY(cf: CFrame, size: Vector3): number
	local h = size / 2
	return cf.Position.Y - (math.abs(cf.XVector.Y) * h.X + math.abs(cf.YVector.Y) * h.Y + math.abs(cf.ZVector.Y) * h.Z)
end

return ObbyZone
