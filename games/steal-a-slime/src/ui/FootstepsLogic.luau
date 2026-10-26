--!strict
--[[
	FootstepsLogic (pure): which step sound a floor gets and when the next steps fall (ui/Footsteps plays them).

	  FootstepsLogic.setFor(material, snowCover, cfg) -> Sounds.VARIANTS group or nil (nil = Roblox's own step)
	  FootstepsLogic.stride(walkSpeed, cfg) -> studs per step
	  FootstepsLogic.new(stride, cfg) -> Walker
	  FootstepsLogic.reset(walker, stride, cfg)          standing, in the air or off a step floor
	  FootstepsLogic.advance(walker, speed, horizon, stride, cfg) -> { number }
	      the steps due in the next `horizon` seconds at `speed` studs / s, as delays from now

	Steps follow the distance walked, so they speed up with the walk. `advance` looks one call ahead: called from a
	slow loop (every 0.1 s) it hands out delays inside that window, so the steps still fall on the stride.
	`cfg` = Config.AUDIO.SLIME.
]]

local FootstepsLogic = {}

FootstepsLogic.MAX_PER_CALL = 4 -- steps one call may schedule (a long hitch must not burst)

export type Walker = { untilNext: number } -- studs to the next step

function FootstepsLogic.setFor(material: string?, snowCover: number?, cfg: any): string?
	if type(material) ~= "string" then
		return nil
	end
	local set = cfg.STEP_MATERIALS[material]
	if set and type(snowCover) == "number" and snowCover >= cfg.SNOW_COVER_MIN then
		return cfg.SNOW_STEPS[set] or set
	end
	return set
end

function FootstepsLogic.stride(walkSpeed: number?, cfg: any): number
	local w = if type(walkSpeed) == "number" and walkSpeed > 0 then walkSpeed else cfg.STRIDE_WALK_SPEED
	return math.clamp(cfg.STRIDE_STUDS * math.sqrt(w / cfg.STRIDE_WALK_SPEED), cfg.STRIDE_MIN, cfg.STRIDE_MAX)
end

function FootstepsLogic.new(stride: number, cfg: any): Walker
	return { untilNext = stride * cfg.FIRST_STEP_SHARE }
end

function FootstepsLogic.reset(walker: Walker, stride: number, cfg: any)
	walker.untilNext = stride * cfg.FIRST_STEP_SHARE
end

function FootstepsLogic.advance(walker: Walker, speed: number, horizon: number, stride: number, cfg: any): { number }
	if speed < cfg.STEP_MIN_SPEED or horizon <= 0 then
		FootstepsLogic.reset(walker, stride, cfg)
		return {}
	end
	local d = speed * horizon
	local u = math.min(walker.untilNext, stride)
	local out: { number } = {}
	while u <= d and #out < FootstepsLogic.MAX_PER_CALL do
		table.insert(out, u / speed)
		u += stride
	end
	walker.untilNext = math.max(u - d, 0)
	return out
end

return FootstepsLogic
