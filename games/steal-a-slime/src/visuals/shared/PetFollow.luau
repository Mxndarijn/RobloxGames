--!strict
--[[
	PetFollow (follow pet motion, pure Luau)

	The glide of a FollowPets pet (and its cloud) behind its owner. Plain numbers in a reused state table, no
	Roblox types and no allocations per step:
	  * position: a critically damped spring toward the owner's back offset, solved exactly (exp form), so the
	    result after a second is the same at 30, 60 or 144 fps and never overshoots a still target;
	  * yaw: exponential approach along the shortest angle, facing the pet's own travel direction while it moves
	    and the owner's heading when it rests;
	  * bob: a small sine added to the height only (not part of the spring state);
	  * snap: the first step, or a target further than SNAP_DISTANCE (teleport, respawn), jumps straight there.
	Yaw 0 faces -Z (Roblox default); CFrame.Angles(0, yaw, 0) turns the pet by `yaw`.
]]

export type State = {
	x: number,
	y: number,
	z: number,
	vx: number,
	vy: number,
	vz: number,
	yaw: number,
	bob: number, -- current bob height (-BOB_AMPLITUDE .. BOB_AMPLITUDE), added by the caller to y
	time: number,
	phase: number,
	ready: boolean,
}

local PetFollow = {}

PetFollow.OFFSET_X = 2.1 -- right of the owner
PetFollow.OFFSET_Z = 2.4 -- behind the owner
PetFollow.OFFSET_Y = -1.7 -- from the HumanoidRootPart centre to the cloud centre (feet at -3, cloud hovers ~1 above)
PetFollow.OMEGA = 9 -- spring stiffness (1/s): ~0.5 s to settle, ~3.5 studs of lag at a 16 stud/s sprint
PetFollow.YAW_RATE = 8 -- 1/s
PetFollow.TURN_SPEED = 1.5 -- studs/s of own horizontal speed above which the pet faces its travel direction
PetFollow.SNAP_DISTANCE = 60
PetFollow.MAX_DT = 0.25 -- a hitch longer than this is treated as 0.25 s
PetFollow.BOB_AMPLITUDE = 0.14
PetFollow.BOB_RATE = 3.2 -- rad/s

function PetFollow.new(phase: number?): State
	return {
		x = 0,
		y = 0,
		z = 0,
		vx = 0,
		vy = 0,
		vz = 0,
		yaw = 0,
		bob = 0,
		time = 0,
		phase = phase or 0,
		ready = false,
	}
end

-- Smallest signed angle from `from` to `to`, in (-pi, pi].
function PetFollow.angleDelta(from: number, to: number): number
	local d = (to - from) % (2 * math.pi)
	if d > math.pi then
		d -= 2 * math.pi
	end
	return d
end

-- Yaw (Angles(0, yaw, 0)) of a horizontal look vector; nil-free: a zero vector gives 0.
function PetFollow.yawOf(lookX: number, lookZ: number): number
	if lookX == 0 and lookZ == 0 then
		return 0
	end
	return math.atan2(-lookX, -lookZ)
end

-- Advance `s` by `dt` seconds toward the owner at (rx, ry, rz) facing yaw `ownerYaw`. The goal is the owner's
-- back offset turned by ownerYaw. Returns nothing: read s.x / s.y + s.bob / s.z / s.yaw.
function PetFollow.step(s: State, dt: number, rx: number, ry: number, rz: number, ownerYaw: number)
	if not (dt > 0) then
		dt = 0 -- also catches NaN
	elseif dt > PetFollow.MAX_DT then
		dt = PetFollow.MAX_DT
	end
	local c, sn = math.cos(ownerYaw), math.sin(ownerYaw)
	local gx = rx + PetFollow.OFFSET_X * c + PetFollow.OFFSET_Z * sn
	local gy = ry + PetFollow.OFFSET_Y
	local gz = rz - PetFollow.OFFSET_X * sn + PetFollow.OFFSET_Z * c

	local dx, dy, dz = s.x - gx, s.y - gy, s.z - gz
	local limit = PetFollow.SNAP_DISTANCE
	if not s.ready or dx * dx + dy * dy + dz * dz > limit * limit then
		s.ready = true
		s.x, s.y, s.z = gx, gy, gz
		s.vx, s.vy, s.vz = 0, 0, 0
		s.yaw = ownerYaw
		s.time = 0
	else
		-- exact critically damped spring: d' = (d + (v + w d) t) e^-wt, v' = (v - w (v + w d) t) e^-wt
		local w = PetFollow.OMEGA
		local e = math.exp(-w * dt)
		local jx, jy, jz = s.vx + w * dx, s.vy + w * dy, s.vz + w * dz
		s.x = gx + (dx + jx * dt) * e
		s.y = gy + (dy + jy * dt) * e
		s.z = gz + (dz + jz * dt) * e
		s.vx = (s.vx - w * jx * dt) * e
		s.vy = (s.vy - w * jy * dt) * e
		s.vz = (s.vz - w * jz * dt) * e

		local speed = math.sqrt(s.vx * s.vx + s.vz * s.vz)
		local want = if speed > PetFollow.TURN_SPEED then PetFollow.yawOf(s.vx, s.vz) else ownerYaw
		s.yaw += PetFollow.angleDelta(s.yaw, want) * (1 - math.exp(-PetFollow.YAW_RATE * dt))
		s.time += dt
	end
	s.bob = math.sin(s.time * PetFollow.BOB_RATE + s.phase) * PetFollow.BOB_AMPLITUDE
end

return PetFollow
