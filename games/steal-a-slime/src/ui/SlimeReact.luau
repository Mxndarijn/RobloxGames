--!strict
--[[
	SlimeReact (pure, contract/slime-life.md)

	How a slime reacts to the local player and to what happens around it, by
	temperament (Shared.SlimePersona): a slime you can afford and reach turns
	to you and bounces ("pick me"), a Shy one shrinks away, a Show-off turns
	its back, a Feisty one glares and stamps, a Lazy one barely looks. Plus the
	nerves before the drain and the startle when a neighbour is grabbed. No
	Roblox APIs; tests/ui/SlimeReact.spec covers it.

	  SlimeReact.toPlayer(temper, distance, toYaw, afford, now, out?) -> Pose
	      toYaw = yaw from the slime's heading to the player (+ = left)
	  SlimeReact.nerves(secondsLeft) -> number      0..1 before the drain
	  SlimeReact.startle(since) -> number           lift (studs at size 1) after a fright
]]

local SlimeReact = {}

SlimeReact.REACT_DISTANCE = 20 -- studs: the player gets noticed inside this
SlimeReact.NEAR = 12 -- studs: close enough to react fully ("pick me" needs reach too)
SlimeReact.NERVES_SECONDS = 6 -- seconds of nerves before the despawn telegraph takes over
SlimeReact.STARTLE_SECONDS = 0.45
SlimeReact.STARTLE_DISTANCE = 18 -- studs: neighbours of a grabbed slime that startle
SlimeReact.WATCH_SECONDS = 2.4 -- how long they then watch the carrier

export type Pose = {
	yaw: number, -- target yaw from the heading
	weight: number, -- 0..1 how much of the turn to take
	lift: number, -- studs at size 1
	sy: number,
	lean: number, -- studs sideways (+ = right)
	face: string?,
	emote: string?, -- SlimeBeats.Emote names
}

local function smooth(u: number): number
	u = math.clamp(u, 0, 1)
	return u * u * (3 - 2 * u)
end

local function reset(out: Pose?): Pose
	local p: Pose = out or {} :: any
	p.yaw, p.weight, p.lift, p.sy, p.lean, p.face, p.emote = 0, 0, 0, 1, 0, nil, nil
	return p
end

function SlimeReact.toPlayer(
	temper: string,
	distance: number,
	toYaw: number,
	afford: boolean,
	now: number,
	out: Pose?
): Pose
	local p = reset(out)
	if not (distance == distance) or distance >= SlimeReact.REACT_DISTANCE then
		return p
	end
	local w = smooth((SlimeReact.REACT_DISTANCE - distance) / 8)
	local near = distance < SlimeReact.NEAR
	local towards = -math.sin(toYaw) -- the player's side: + = right
	if afford and near then
		-- "Pick me": faces you and bounces, so you can read the lane at a glance.
		p.yaw, p.weight = toYaw, 0.85 * w
		p.lift = 0.22 * (0.5 - 0.5 * math.cos(now * 5)) * w -- a soft bounce, about 0.8 Hz
		p.face = "happy"
		p.emote = "love"
		if temper == "Curious" or temper == "Bouncy" then
			p.lean = towards * 0.7 * w
		end
	elseif near and temper == "Shy" then
		p.yaw, p.weight = toYaw + math.pi * 0.7, 0.6 * w
		p.sy = 1 - 0.18 * w
		p.lean = -towards * 0.6 * w
		p.face = "worried"
		p.emote = "dots"
	elseif near and temper == "Feisty" then
		p.yaw, p.weight = toYaw, 0.9 * w
		p.sy = 1 + 0.08 * w
		p.lean = towards * 0.5 * w
		p.lift = 0.15 * (0.5 - 0.5 * math.cos(now * 6)) * w
		p.face = "angry"
		p.emote = "angry"
	elseif near and temper == "Showoff" then
		p.yaw, p.weight = toYaw + 2.3, 0.7 * w
		p.face = "smug"
		p.emote = "star"
	elseif temper == "Lazy" then
		p.yaw, p.weight = toYaw, 0.25 * w
		p.face = "sleepy"
	else
		p.yaw, p.weight = toYaw, (if temper == "Curious" then 0.8 else 0.55) * w
		p.face = if near then "surprised" else nil
	end
	return p
end

-- 0 until NERVES_SECONDS before the despawn telegraph, then up to 1.
function SlimeReact.nerves(secondsLeft: number): number
	if secondsLeft ~= secondsLeft then
		return 0
	end
	return smooth((SlimeReact.NERVES_SECONDS - secondsLeft) / 1.5)
end

function SlimeReact.startle(since: number): number
	if since < 0 or since >= SlimeReact.STARTLE_SECONDS then
		return 0
	end
	return 0.9 * math.sin(math.pi * since / SlimeReact.STARTLE_SECONDS)
end

return SlimeReact
