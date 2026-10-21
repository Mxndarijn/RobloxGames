--!strict
--[[
	SlimeAttention (pure, contract/slime-life.md "Alive attention")

	A slime that watches something never holds one pose. Its look darts in small quick saccades around what it
	watches (a glance a little left, a little right, back), and now and then it tilts its head, the way a curious
	animal does. The caller adds the yaw and roll to whatever turn a reaction asked for, scaled by how engaged the
	slime is (the reaction's weight). No Roblox APIs; tests/ui/SlimeAttention.spec covers it.

	  SlimeAttention.new(now, rand) -> State
	  SlimeAttention.step(state, now, rand, engaged) -> (yaw, roll)   radians; engaged 0..1 (0 = idle: no tilts)
]]

local SlimeAttention = {}

SlimeAttention.SACCADE = 0.26 -- radians: how far a glance darts either side of the target
SlimeAttention.SACCADE_EVERY = table.freeze({ 0.5, 1.6 }) -- seconds between glances
SlimeAttention.SACCADE_TIME = 0.08 -- seconds a glance takes (eyes are quick)
SlimeAttention.TILT = 0.2 -- radians of a head tilt
SlimeAttention.TILT_EVERY = table.freeze({ 1.8, 4.5 }) -- seconds between tilts while engaged
SlimeAttention.TILT_TIME = 0.3 -- seconds to tilt over (and back)

export type State = {
	yawFrom: number,
	yawTo: number,
	yawAt: number,
	nextYaw: number,
	tiltFrom: number,
	tiltTo: number,
	tiltAt: number,
	nextTilt: number,
}

type Rand = () -> number

local function between(range: { number }, rand: Rand): number
	return range[1] + rand() * (range[2] - range[1])
end

local function smooth(u: number): number
	u = math.clamp(u, 0, 1)
	return u * u * (3 - 2 * u)
end

function SlimeAttention.new(now: number, rand: Rand): State
	return {
		yawFrom = 0,
		yawTo = 0,
		yawAt = now,
		nextYaw = now + between(SlimeAttention.SACCADE_EVERY, rand),
		tiltFrom = 0,
		tiltTo = 0,
		tiltAt = now,
		nextTilt = now + between(SlimeAttention.TILT_EVERY, rand),
	}
end

local function current(from: number, to: number, at: number, span: number, now: number): number
	return from + (to - from) * smooth((now - at) / span)
end

function SlimeAttention.step(st: State, now: number, rand: Rand, engaged: number): (number, number)
	if now >= st.nextYaw then
		st.yawFrom = current(st.yawFrom, st.yawTo, st.yawAt, SlimeAttention.SACCADE_TIME, now)
		-- a third of the glances come back to the target, so the look keeps returning to it
		st.yawTo = if rand() < 0.33 then 0 else (rand() * 2 - 1) * SlimeAttention.SACCADE
		st.yawAt = now
		st.nextYaw = now + between(SlimeAttention.SACCADE_EVERY, rand)
	end
	if now >= st.nextTilt then
		st.tiltFrom = current(st.tiltFrom, st.tiltTo, st.tiltAt, SlimeAttention.TILT_TIME, now)
		-- tilt to a side, or straighten up again
		st.tiltTo = if st.tiltTo ~= 0 or rand() < 0.3 then 0 else (if rand() < 0.5 then -1 else 1) * SlimeAttention.TILT
		st.tiltAt = now
		st.nextTilt = now + between(SlimeAttention.TILT_EVERY, rand)
	end
	local e = math.clamp(engaged, 0, 1)
	local yaw = current(st.yawFrom, st.yawTo, st.yawAt, SlimeAttention.SACCADE_TIME, now)
	local roll = current(st.tiltFrom, st.tiltTo, st.tiltAt, SlimeAttention.TILT_TIME, now)
	return yaw * e, roll * e
end

return SlimeAttention
