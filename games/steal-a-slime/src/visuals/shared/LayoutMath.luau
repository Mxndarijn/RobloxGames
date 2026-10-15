--!strict
--[[
	LayoutMath (owner: Archer)

	Tiny vector / rotation helpers shared by SlimeLayout and WorldLayout.
	Pure Luau, no Roblox APIs, so layouts run under Lune for the render proof.

	Rotations are Roblox Orientation angles in degrees { x, y, z }, applied
	like CFrame.fromOrientation: R = Ry(y) * Rx(x) * Rz(z).
]]

export type Vec = { number } -- { x, y, z }
export type Mat = { { number } } -- 3x3, row-major

local LayoutMath = {}

local function rx(a: number): Mat
	local c, s = math.cos(a), math.sin(a)
	return { { 1, 0, 0 }, { 0, c, -s }, { 0, s, c } }
end

local function ry(a: number): Mat
	local c, s = math.cos(a), math.sin(a)
	return { { c, 0, s }, { 0, 1, 0 }, { -s, 0, c } }
end

local function rz(a: number): Mat
	local c, s = math.cos(a), math.sin(a)
	return { { c, -s, 0 }, { s, c, 0 }, { 0, 0, 1 } }
end

function LayoutMath.matMul(a: Mat, b: Mat): Mat
	local out = {}
	for i = 1, 3 do
		out[i] = {}
		for j = 1, 3 do
			out[i][j] = a[i][1] * b[1][j] + a[i][2] * b[2][j] + a[i][3] * b[3][j]
		end
	end
	return out
end

function LayoutMath.apply(m: Mat, v: Vec): Vec
	return {
		m[1][1] * v[1] + m[1][2] * v[2] + m[1][3] * v[3],
		m[2][1] * v[1] + m[2][2] * v[2] + m[2][3] * v[3],
		m[3][1] * v[1] + m[3][2] * v[2] + m[3][3] * v[3],
	}
end

-- Orientation degrees -> rotation matrix (CFrame.fromOrientation order).
function LayoutMath.orientation(rot: Vec): Mat
	local d = math.pi / 180
	return LayoutMath.matMul(LayoutMath.matMul(ry(rot[2] * d), rx(rot[1] * d)), rz(rot[3] * d))
end

-- Orientation that points a part's front face (-Z) along unit vector n,
-- then rolls it `roll` degrees around that axis.
function LayoutMath.facing(n: Vec, roll: number?): Vec
	local d = 180 / math.pi
	local pitch = math.asin(math.clamp(n[2], -1, 1)) * d
	local yaw = math.atan2(-n[1], -n[3]) * d
	return { pitch, yaw, roll or 0 }
end

-- Unit direction from yaw/pitch degrees; yaw 0 / pitch 0 is the slime's
-- front (-Z), positive yaw turns towards the viewer's right (-X).
function LayoutMath.direction(yaw: number, pitch: number): Vec
	local d = math.pi / 180
	local a, b = yaw * d, pitch * d
	return { -math.sin(a) * math.cos(b), math.sin(b), -math.cos(a) * math.cos(b) }
end

function LayoutMath.add(a: Vec, b: Vec): Vec
	return { a[1] + b[1], a[2] + b[2], a[3] + b[3] }
end

function LayoutMath.scale(v: Vec, k: number): Vec
	return { v[1] * k, v[2] * k, v[3] * k }
end

return table.freeze(LayoutMath)
