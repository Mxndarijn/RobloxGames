--!strict
--[[
	SlimeBeats (pure, contract/slime-life.md)

	The pose of a lane slime during one of its ParadeChoreo beats: how it turns,
	leans, squashes and lifts, its face and its emote. The server only stops
	and restarts the slime (ParadeChoreo.offset); this is what the client
	shows while it stands. No Roblox APIs; tests/ui/SlimeBeats.spec covers it.

	  SlimeBeats.pose(kind, phase, u, side, now, out?) -> Pose
	      phase "pre" | "stop" | "post" (ParadeChoreo.beatAt), u 0..1 through it,
	      side = -1 | 1, now = any running clock (wiggles)
]]

local Shared = if script then (game:GetService("ReplicatedStorage") :: any).Shared else nil
local ParadeLane = if Shared then require(Shared.ParadeLane) else require("../shared/ParadeLane")

local SlimeBeats = {}

SlimeBeats.SNIFF_LEAN = ParadeLane.ROOM * 0.6 -- studs a sniff leans out towards the lane edge

export type Emote = "love" | "alert" | "ask" | "star" | "note" | "dots" | "sleep" | "dizzy" | "angry" | "sweat"

export type Pose = {
	yaw: number?, -- radians from the heading (+ = left), nil = no turn
	lean: number, -- studs sideways (+ = right)
	tilt: number, -- radians, + = nose down
	roll: number, -- radians, + = lean right
	lift: number, -- studs at size 1
	sx: number,
	sy: number,
	face: string?, -- "happy" | "asleep" | "surprised" | "excited" | "dizzy" | "smug" | "worried" | "angry" | "focus"
	emote: Emote?,
}

local function smooth(u: number): number
	u = math.clamp(u, 0, 1)
	return u * u * (3 - 2 * u)
end

local function lerp(a: number, b: number, t: number): number
	return a + (b - a) * t
end

local function reset(out: Pose?): Pose
	local p: Pose = out or {} :: any
	p.yaw, p.lean, p.tilt, p.roll, p.lift, p.sx, p.sy, p.face, p.emote = nil, 0, 0, 0, 0, 1, 1, nil, nil
	return p
end

-- Look keys (yaw from the heading): forward, back over the left shoulder, right, a little left, forward.
local LOOK = { 0, 2.2, -1.5, 0.4, 0 }

function SlimeBeats.pose(kind: string, phase: string, u: number, side: number, now: number, out: Pose?): Pose
	local p = reset(out)
	if phase == "none" then
		return p
	end
	if kind == "look" then
		if phase == "stop" then
			local x = u * 4
			local i = math.min(4, math.floor(x) + 1)
			p.yaw = lerp(LOOK[i], LOOK[math.min(5, i + 1)], smooth((x - (i - 1)) * 1.6))
			p.face = "surprised"
			if u > 0.2 then
				p.emote = "ask"
			end
		end
	elseif kind == "sniff" then
		local reach = if phase == "stop" then smooth(u * 3) elseif phase == "post" then 1 - smooth(u * 2) else 0
		p.lean = side * SlimeBeats.SNIFF_LEAN * reach
		p.roll = side * 0.12 * reach
		if phase == "post" then
			p.yaw = -side * 1.2 * reach
		elseif phase == "stop" then
			p.yaw = -side * 1.2 * smooth(u * 3)
			p.tilt = 0.35
			if u > 0.15 and u < 0.75 then
				p.sy = 1 + 0.05 * math.sin(now * 38)
			end
			p.face = if u < 0.8 then "focus" else "happy"
			p.emote = if u < 0.75 then "dots" else "note"
		end
	elseif kind == "slurp" then
		if phase == "stop" then
			local dip = math.sin(math.pi * u)
			p.sy = (1 - 0.22 * dip) * (1 + 0.06 * math.sin(now * 20) * dip)
			p.sx = 1 + 0.18 * dip
			p.tilt = 0.6 * dip
			p.face = if u < 0.7 then "focus" else "happy"
			if u > 0.55 then
				p.emote = "love"
			end
		end
	elseif kind == "nap" then
		if phase == "pre" then
			p.face = "asleep"
		elseif phase == "stop" then
			local settle = smooth(u * 4)
			if u < 0.86 then
				p.sy = 1 - 0.14 * settle + 0.03 * math.sin(now * 2.2)
				p.sx = 1 + 0.1 * settle
				p.face = "asleep"
				p.emote = "sleep"
			else
				local v = (u - 0.86) / 0.14
				p.lift = 1.2 * math.sin(math.pi * v)
				p.face = "surprised"
				p.emote = "alert"
			end
		else
			p.face = "worried"
			p.emote = "sweat"
			p.tilt = 0.15
		end
	elseif kind == "trip" then
		if phase == "stop" then
			if u < 0.35 then
				local v = u / 0.35
				p.tilt = 0.9 * math.sin(math.pi * math.min(1, v * 1.4))
				p.sy = 1 - 0.25 * math.sin(math.pi * v)
				p.sx = 1 + 0.2 * math.sin(math.pi * v)
				p.face = "surprised"
			else
				p.yaw = math.sin(now * 22) * 0.5 * (1 - u)
				p.face = "dizzy"
				p.emote = "dizzy"
			end
		end
	elseif kind == "spin" then
		if phase == "stop" then
			if u < 0.6 then
				local v = u / 0.6
				p.lift = 2.4 * math.sin(math.pi * v)
				p.yaw = 2 * math.pi * smooth(v)
				p.sy = 1 + 0.12 * math.sin(math.pi * v)
				p.face = "excited"
			else
				p.tilt = -0.18 * math.sin(math.pi * (u - 0.6) / 0.4)
				p.face = "smug"
				p.emote = "star"
			end
		end
	elseif kind == "cheer" then
		if phase == "stop" then
			local v = (u * 2) % 1
			local s = math.sin(math.pi * v)
			p.lift = 1.1 * s
			p.sy = 1 + 0.15 * s - 0.15 * (1 - s) ^ 8
			p.face = "happy"
			p.emote = "note"
		end
	elseif kind == "hide" then
		if phase == "stop" then
			local v = math.sin(math.pi * math.clamp(u * 1.2, 0, 1))
			p.sy = 1 - 0.35 * v
			p.sx = 1 + 0.15 * v
			p.roll = math.sin(now * 40) * 0.03 * v
			p.yaw = math.sin(now * 2) * 0.8 * v
			p.face = "worried"
			if u > 0.3 then
				p.emote = "dots"
			end
		end
	elseif kind == "zoom" then
		if phase == "pre" then
			p.tilt = 0.2
			p.face = "excited"
			p.emote = "alert"
		elseif phase == "stop" then
			p.sy = 1 + 0.06 * math.sin(now * 16)
			p.face = "happy"
			p.emote = "note"
		end
	elseif kind == "huff" then
		if phase == "stop" then
			local puff = math.sin(math.pi * math.clamp(u * 1.3, 0, 1))
			p.sy = 1 + 0.16 * puff
			p.sx = 1 + 0.1 * puff
			p.face = "angry"
			if u > 0.25 then
				p.emote = "angry"
			end
			if u > 0.55 and u < 0.8 then
				p.lift = 0.35 * math.abs(math.sin(now * 18))
			end
		end
	elseif kind == "stuck" then
		if phase == "stop" then
			if u < 0.82 then
				-- two tugs upwards, bottom glued to the goo
				local tug = math.max(0, math.sin(math.pi * ((u / 0.82) * 2.5)))
				p.sy = 1 + 0.38 * tug
				p.sx = 1 - 0.18 * tug
				p.roll = math.sin(now * 26) * 0.06 * (1 - tug)
				p.face = if tug > 0.5 then "focus" else "worried"
				if u > 0.3 then
					p.emote = if u > 0.5 then "sweat" else "alert"
				end
			else
				local v = (u - 0.82) / 0.18
				p.lift = 1.6 * math.sin(math.pi * v) -- pop!
				p.sy = 1 + 0.2 * math.sin(math.pi * v)
				p.face = "excited"
				p.emote = "note"
			end
		end
	end
	return p
end

return SlimeBeats
