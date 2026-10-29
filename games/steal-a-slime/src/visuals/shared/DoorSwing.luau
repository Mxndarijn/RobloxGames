--!strict
--[[
	DoorSwing (pure; CFrame math only, no Roblox API at load time)

	The door look between its two poses: `shut` (StopperShut) and `open` (StopperParked). When the two poses differ
	by a turn round a vertical axis (the jar's round door on its hinge pin) the door turns round that axis; when they
	only differ by a move (the factory's shutter) it slides. LockMotion plays it when a plot locks or opens.

	  DoorSwing.pose(shut, open, f)  -> CFrame   f = 0 shut .. 1 open
	  DoorSwing.ease(t, overshoot)   -> number   0..1 eased out, with a small settle past the end when overshoot > 0

	DoorSwing.TIMING holds how long each part of the motion takes.
]]

local DoorSwing = {}

DoorSwing.TIMING = table.freeze({
	closeSeconds = 0.45, -- the door swings shut
	openSeconds = 0.6, -- the door swings open
	ringSeconds = 0.3, -- the door's lock ring fades to its new colour
	-- ease-out-back strength: how far the door swings past its end before it settles (0.6 is about 2.5 %, a few
	-- degrees past shut; none when opening, so the open door never swings into the glass beside it)
	closeOvershoot = 0.6,
	openOvershoot = 0,
})

local MIN_TURN = 1e-3 -- radians: less than this between the poses counts as no turn (a slide)

-- 0..1 eased out; `overshoot` > 0 swings past 1 before it settles (ease-out-back), 0 is a plain cubic ease-out.
function DoorSwing.ease(t: number, overshoot: number): number
	local x = math.clamp(t, 0, 1) - 1
	local c = overshoot
	return 1 + (c + 1) * x * x * x + c * x * x
end

-- The pose `f` of the way from `shut` (0) to `open` (1). `f` outside 0..1 carries on past either end (the settle).
function DoorSwing.pose(shut: CFrame, open: CFrame, f: number): CFrame
	local move = open * shut:Inverse() -- the world move that takes the shut door to the open one
	local _, yaw, _ = move:ToEulerAnglesYXZ()
	local t = move.Position
	if math.abs(yaw) < MIN_TURN then
		return CFrame.new(t * f) * shut
	end
	-- The vertical axis the move turns round: the point p with R p + t = p (flat, x and z).
	local a = move:VectorToWorldSpace(Vector3.new(1, 0, 0))
	local b = move:VectorToWorldSpace(Vector3.new(0, 0, 1))
	local m11, m12, m21, m22 = 1 - a.X, -b.X, -a.Z, 1 - b.Z
	local det = m11 * m22 - m12 * m21
	local px = (t.X * m22 - m12 * t.Z) / det
	local pz = (m11 * t.Z - m21 * t.X) / det
	local pivot = Vector3.new(px, 0, pz)
	return CFrame.new(Vector3.new(0, t.Y * f, 0))
		* CFrame.new(pivot)
		* CFrame.Angles(0, yaw * f, 0)
		* CFrame.new(-pivot)
		* shut
end

return table.freeze(DoorSwing)
