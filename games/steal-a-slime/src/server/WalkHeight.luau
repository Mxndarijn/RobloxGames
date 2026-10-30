--!strict
--[[
	WalkHeight (pure)

	The height of a slime walking back to the lane (contract/slime-walk.md), one Heartbeat at a time. The adapter
	(WorldView) finds the ground under the slime's next spot with a ray from STEP_UP above its height down to
	RAY_DEPTH, and passes it here (nil = nothing below).

	* A step: ground at most STEP_DOWN below, or anything above (stairs, ramps, a curb): the slime eases onto it at
	  Y_RATE, so it never snaps over an edge.
	* A ledge: ground more than STEP_DOWN below (off the fountain, a jar roof, a bridge): it falls with GRAVITY while
	  it keeps walking, so it drops off the edge in an arc, and lands on that ground.
	* Nothing below (off the map's edge): it keeps its height.
]]

local WalkHeight = {}

WalkHeight.STEP_UP = 3 -- studs above its height the ground ray starts (steps and ramps it walks up)
WalkHeight.STEP_DOWN = 1.5 -- studs: ground further below than this is a ledge it falls off
WalkHeight.RAY_DEPTH = 300 -- studs below its height the ground ray looks (the fountain crown is under 50 up)
WalkHeight.Y_RATE = 10 -- 1 / s: how fast its height follows a step
WalkHeight.GRAVITY = 140 -- studs / s^2 it falls with (characters fall at 196; a slime drops a little softer)

export type State = {
	y: number,
	vy: number, -- studs / s, below 0 while it falls
}

function WalkHeight.new(y: number): State
	return { y = y, vy = 0 }
end

-- Whether it is in the air (falling off a ledge).
function WalkHeight.falling(state: State): boolean
	return state.vy < 0
end

-- The state `dt` seconds on, over `ground` (the height under its next spot, nil = none).
function WalkHeight.step(state: State, ground: number?, dt: number): State
	if ground == nil then
		return { y = state.y, vy = 0 }
	end
	if state.vy < 0 or ground < state.y - WalkHeight.STEP_DOWN then
		local vy = state.vy - WalkHeight.GRAVITY * dt
		local y = state.y + vy * dt
		if y <= ground then
			return { y = ground, vy = 0 } -- landed
		end
		return { y = y, vy = vy }
	end
	return { y = state.y + (ground - state.y) * math.min(1, dt * WalkHeight.Y_RATE), vy = 0 }
end

return WalkHeight
