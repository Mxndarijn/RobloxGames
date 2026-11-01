--!strict
--[[
	PetFollow (follow pet motion, pure Luau)

	How a FollowPets pet (and its cloud) flies after its owner: on a leash, so it only moves when it has to.
	Plain numbers in a reused state table, no Roblox types and no allocations per step:
	  * leash: the pet keeps its bearing from the owner and is pulled in to FOLLOW studs (flat) when the owner gets
	    further away, pushed out to NEAR when the owner comes closer, and left alone in between. The owner turning
	    on the spot moves nothing. While the owner walks, the bearing drifts to behind-right of the direction they
	    walk (BIAS_RATE), so the pet trails beside the path instead of in front of the camera; an owner walking
	    straight at the pet makes it step aside to that side instead of fleeing ahead;
	  * motion: a critically damped spring toward that goal, solved exactly (exp form), so the result after a second
	    is the same at 30, 60 or 144 fps and never overshoots a still goal; the height has its own softer spring;
	  * height: OFFSET_Y under the owner's root, but while the owner is in the air (`grounded == false`) the pet
	    keeps the height they left the ground at, so a jump doesn't throw the cloud up; a drop below it is followed;
	  * yaw: while it flies faster than TURN_SPEED the pet turns toward its travel direction, at most YAW_MAX_RATE;
	    at rest it keeps facing where it faced (the owner turning doesn't turn it);
	  * bob: a small sine added to the height only (not part of the spring state);
	  * snap: the first step, or an owner further than SNAP_DISTANCE (teleport, respawn), puts it straight at the
	    owner's back-right offset (OFFSET_X right, OFFSET_Z behind, turned by the owner's heading).
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
	floor: number, -- the owner's root height while grounded (held during a jump)
	air: number, -- seconds the owner has been in the air
	ox: number, -- owner position last step
	oz: number,
	ovx: number, -- owner's smoothed flat velocity
	ovz: number,
}

local PetFollow = {}

PetFollow.OFFSET_X = 2.6 -- right of the owner (snap spot)
PetFollow.OFFSET_Z = 2.9 -- behind the owner (snap spot)
PetFollow.OFFSET_Y = -1.45 -- from the HumanoidRootPart centre to the cloud centre (feet at -3, cloud hovers above)
PetFollow.FOLLOW = math.sqrt(PetFollow.OFFSET_X ^ 2 + PetFollow.OFFSET_Z ^ 2) -- leash length, flat studs (~3.9)
PetFollow.NEAR = 2.6 -- closer than this and the pet backs off
PetFollow.BIAS_RATE = 5 -- 1/s: how fast the bearing drifts behind-right of a walking owner
PetFollow.DODGE_RATE = 9 -- 1/s: the same swing when the owner walks straight at the pet
PetFollow.SWING_SPEED = 14 -- studs/s: the swing round the owner is never faster than this
PetFollow.WALKING = 2 -- studs/s of owner speed that counts as walking (for the drift)
PetFollow.OWNER_SMOOTH = 20 -- 1/s: smoothing of the owner's measured velocity
PetFollow.FEED = 0.85 -- share of the owner's leash-tugging speed the goal carries (1 = no lag at all)
PetFollow.PUSH = 1.15 -- the same at NEAR: an owner walking into the pet pushes it ahead a bit faster than they walk
PetFollow.EDGE = 0.05 -- studs: this close to the leash end counts as at it
PetFollow.MAX_OWNER_SPEED = 50 -- studs/s: faster owner moves count as this fast
PetFollow.OMEGA = 7 -- flat spring stiffness (1/s)
PetFollow.AIR_HOLD = 1.2 -- s: in the air longer than a jump, the pet follows the height anyway
PetFollow.OMEGA_Y = 5 -- height spring stiffness (1/s): softer, so steps and ramps glide
PetFollow.YAW_RATE = 8 -- 1/s
PetFollow.YAW_MAX_RATE = math.rad(200) -- the pet never turns faster than this (rad/s)
PetFollow.TURN_SPEED = 1.5 -- studs/s of own flat speed above which the pet turns toward its travel direction
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
		floor = 0,
		air = 0,
		ox = 0,
		oz = 0,
		ovx = 0,
		ovz = 0,
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

local function snap(s: State, rx: number, ry: number, rz: number, ownerYaw: number)
	local c, sn = math.cos(ownerYaw), math.sin(ownerYaw)
	s.ready = true
	s.x = rx + PetFollow.OFFSET_X * c + PetFollow.OFFSET_Z * sn
	s.y = ry + PetFollow.OFFSET_Y
	s.z = rz - PetFollow.OFFSET_X * sn + PetFollow.OFFSET_Z * c
	s.vx, s.vy, s.vz = 0, 0, 0
	s.yaw = ownerYaw
	s.time = 0
	s.floor = ry
	s.air = 0
	s.ox, s.oz = rx, rz
	s.ovx, s.ovz = 0, 0
end

-- Advance `s` by `dt` seconds after the owner whose root is at (rx, ry, rz), facing yaw `ownerYaw` (used only for
-- a snap). `grounded` false = the owner is in the air (jumping, falling); nil counts as grounded. Returns nothing:
-- read s.x / s.y + s.bob / s.z / s.yaw.
function PetFollow.step(s: State, dt: number, rx: number, ry: number, rz: number, ownerYaw: number, grounded: boolean?)
	if not (dt > 0) then
		dt = 0 -- also catches NaN
	elseif dt > PetFollow.MAX_DT then
		dt = PetFollow.MAX_DT
	end
	local fx, fz = s.x - rx, s.z - rz
	local limit = PetFollow.SNAP_DISTANCE
	if not s.ready or fx * fx + (s.y - ry) ^ 2 + fz * fz > limit * limit then
		snap(s, rx, ry, rz, ownerYaw)
	elseif dt > 0 then
		local px, pz = s.x, s.z
		-- Owner velocity, smoothed (only its direction and size matter).
		local k = 1 - math.exp(-PetFollow.OWNER_SMOOTH * dt)
		s.ovx += ((rx - s.ox) / dt - s.ovx) * k
		s.ovz += ((rz - s.oz) / dt - s.ovz) * k
		local ov = math.sqrt(s.ovx * s.ovx + s.ovz * s.ovz)
		if ov > PetFollow.MAX_OWNER_SPEED then -- a short teleport is not a walk
			s.ovx, s.ovz = s.ovx / ov * PetFollow.MAX_OWNER_SPEED, s.ovz / ov * PetFollow.MAX_OWNER_SPEED
		end
		s.ox, s.oz = rx, rz

		-- Height the pet aims for: the owner's root while grounded, held while they are in the air (up to AIR_HOLD).
		s.air = if grounded == false then s.air + dt else 0
		if grounded ~= false or ry < s.floor or s.air > PetFollow.AIR_HOLD then
			s.floor = ry
		end
		local gy = s.floor + PetFollow.OFFSET_Y

		-- Bearing from the owner to the pet (unit, flat).
		local dist = math.sqrt(fx * fx + fz * fz)
		local bx, bz
		if dist > 1e-4 then
			bx, bz = fx / dist, fz / dist
		else
			bx, bz = math.sin(ownerYaw), math.cos(ownerYaw) -- right on top of the owner: back off behind
		end
		local ospeed = math.sqrt(s.ovx * s.ovx + s.ovz * s.ovz)
		if ospeed > PetFollow.WALKING then
			-- Behind-right of the way the owner walks: behind = -t, right of t = (-t.z, t.x).
			local tx, tz = s.ovx / ospeed, s.ovz / ospeed
			local wx = -tx * PetFollow.OFFSET_Z - tz * PetFollow.OFFSET_X
			local wz = -tz * PetFollow.OFFSET_Z + tx * PetFollow.OFFSET_X
			local wl = math.sqrt(wx * wx + wz * wz)
			wx, wz = wx / wl, wz / wl
			-- Swing round the owner toward that side: turn the pet's bearing (and the pet with it) part of the way.
			-- Walked into from the front, it swings fast (DODGE_RATE) instead of being pushed ahead.
			local front = bx * tx + bz * tz
			local rate = if front > 0.5 and dist < PetFollow.FOLLOW then PetFollow.DODGE_RATE else PetFollow.BIAS_RATE
			local angle = math.atan2(bx * wz - bz * wx, bx * wx + bz * wz) * (1 - math.exp(-rate * dt))
			local cap = PetFollow.SWING_SPEED * dt / math.max(dist, 1) -- never faster than SWING_SPEED round the owner
			angle = math.clamp(angle, -cap, cap)
			local c, sn = math.cos(angle), math.sin(angle)
			bx, bz = bx * c - bz * sn, bx * sn + bz * c
			if dist > 1e-4 then
				s.x, s.z = rx + bx * dist, rz + bz * dist
			end
		end
		local want = math.clamp(dist, PetFollow.NEAR, PetFollow.FOLLOW)
		local gx, gz = rx + bx * want, rz + bz * want
		-- The goal's own velocity: the part of the owner's walk that tugs the leash (away from the pet at its end,
		-- into the pet at NEAR), times FEED. The spring chases the goal's motion, so a walking owner is trailed at
		-- the leash length instead of a long spring lag behind it.
		local radial = s.ovx * bx + s.ovz * bz -- > 0: the owner moves toward the pet
		local gvx, gvz = 0, 0
		if radial < 0 and dist >= PetFollow.FOLLOW - PetFollow.EDGE then
			gvx, gvz = PetFollow.FEED * radial * bx, PetFollow.FEED * radial * bz
		elseif radial > 0 and dist <= PetFollow.NEAR + PetFollow.EDGE then
			gvx, gvz = PetFollow.PUSH * radial * bx, PetFollow.PUSH * radial * bz -- a bit faster than the owner
		end

		-- Exact critically damped springs on (position - goal, velocity - goal velocity), the goal moving at its
		-- velocity through the step and reaching (gx, gz) at its end:
		-- d' = (d + (u + w d) t) e^-wt, u' = (u - w (u + w d) t) e^-wt
		local w, wy = PetFollow.OMEGA, PetFollow.OMEGA_Y
		local e, ey = math.exp(-w * dt), math.exp(-wy * dt)
		local dx, dy, dz = s.x - (gx - gvx * dt), s.y - gy, s.z - (gz - gvz * dt)
		local ux, uz = s.vx - gvx, s.vz - gvz
		local jx, jy, jz = ux + w * dx, s.vy + wy * dy, uz + w * dz
		s.x = gx + (dx + jx * dt) * e
		s.y = gy + (dy + jy * dt) * ey
		s.z = gz + (dz + jz * dt) * e
		s.vx = gvx + (ux - w * jx * dt) * e
		s.vy = (s.vy - wy * jy * dt) * ey
		s.vz = gvz + (uz - w * jz * dt) * e

		-- Facing follows how it actually moved this step (the swing round the owner included).
		local mx, mz = (s.x - px) / dt, (s.z - pz) / dt
		if mx * mx + mz * mz > PetFollow.TURN_SPEED * PetFollow.TURN_SPEED then
			local turn = PetFollow.angleDelta(s.yaw, PetFollow.yawOf(mx, mz)) * (1 - math.exp(-PetFollow.YAW_RATE * dt))
			local cap = PetFollow.YAW_MAX_RATE * dt
			s.yaw += math.clamp(turn, -cap, cap)
		end
		s.time += dt
	end
	s.bob = math.sin(s.time * PetFollow.BOB_RATE + s.phase) * PetFollow.BOB_AMPLITUDE
end

return PetFollow
