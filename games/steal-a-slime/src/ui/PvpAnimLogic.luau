--!strict
--[[
	PvpAnimLogic (pure, CONTRACT.md §26.3): the procedural use animations of the Bat and the PvP items.

	A pose is { [joint name]: { rx, ry, rz, py } } (radians about the joint's own C0 axes, py studs), added on top of
	whatever the Animator plays (ui/PvpAnim writes it into Motor6D.Transform). R15 joint names only.
	Angles: Shoulder / Elbow rx > 0 swings the limb forward and up, RightShoulder rz > 0 swings the arm out to the
	right (LeftShoulder rz > 0 swings the left arm in), Waist ry > 0 turns the chest to the left (right shoulder
	forward), Waist rx > 0 leans the chest back.

	  PvpAnimLogic.kindFor(itemId, tools)   "swing" | "punch" | "blast" | "throw" | "pop" | "blow" | "bonk" | "use"
	                                        (nil = no animation); "dance", "flip" and "hit" play on an affected player
	  PvpAnimLogic.pose(kind, elapsed)      the use pose `elapsed` seconds in, nil once it is over
	  PvpAnimLogic.holdFor(itemId, tools)   the pose while the item is equipped (nil for the Bat: its Tool pose)
	  PvpAnimLogic.combine(hold, w, anim)   hold x weight + the use pose, one table
	No Roblox API: Lune tests it.
]]

local PvpAnimLogic = {}

export type Angles = { rx: number?, ry: number?, rz: number?, py: number? }
export type Pose = { [string]: Angles }
type Key = { t: number, pose: Pose }
export type Clip = { seconds: number, keys: { Key } }

PvpAnimLogic.RANGE = 120 -- studs from the camera: farther characters are not animated
PvpAnimLogic.HOLD_RATE = 8 -- per second: how fast the hold pose fades in / out
PvpAnimLogic.JOINTS = table.freeze({
	"RightShoulder",
	"RightElbow",
	"RightWrist",
	"LeftShoulder",
	"LeftElbow",
	"Waist",
	"Neck",
	"Root",
})

local REST: Pose = {}
local DISCO_RIGHT: Pose = {
	RightShoulder = { rx = 2.7, rz = 0.3 },
	LeftShoulder = { rx = -0.3 },
	Waist = { rz = 0.22 },
	Root = { py = -0.15 },
}
local DISCO_LEFT: Pose = {
	RightShoulder = { rx = 0.2 },
	LeftShoulder = { rx = 2.7, rz = -0.3 },
	Waist = { rz = -0.22 },
}

-- Each clip starts and ends at rest (t = 0 and t = 1 are empty), so it never leaves a joint bent.
local CLIPS: { [string]: Clip } = {
	-- the Bat: wind up over the right shoulder, then a fast diagonal swing across the body
	swing = {
		seconds = 0.4,
		keys = {
			{ t = 0, pose = REST },
			{
				t = 0.3,
				pose = {
					RightShoulder = { rx = 0.7, rz = 0.7 },
					RightElbow = { rx = 0.5 },
					Waist = { ry = -0.55 },
				},
			},
			{
				t = 0.55,
				pose = {
					RightShoulder = { rx = -0.3, rz = -0.6 },
					RightElbow = { rx = 0.1 },
					Waist = { ry = 0.55, rx = -0.1 },
				},
			},
			{ t = 1, pose = REST },
		},
	},
	-- glove: cock the fist back, then a straight jab with the chest turning into it
	punch = {
		seconds = 0.32,
		keys = {
			{ t = 0, pose = REST },
			{
				t = 0.3,
				pose = { RightShoulder = { rx = -0.35, rz = 0.15 }, RightElbow = { rx = 1.0 }, Waist = { ry = -0.4 } },
			},
			{
				t = 0.5,
				pose = { RightShoulder = { rx = 0.15 }, RightElbow = { rx = -0.1 }, Waist = { ry = 0.45, rx = -0.12 } },
			},
			{ t = 1, pose = REST },
		},
	},
	-- blaster: settle the aim, then the recoil kicks the barrel up and the chest back
	blast = {
		seconds = 0.45,
		keys = {
			{ t = 0, pose = REST },
			{ t = 0.15, pose = { RightShoulder = { rx = 0.08 }, Waist = { rx = -0.05 } } },
			{
				t = 0.3,
				pose = {
					RightShoulder = { rx = 0.45 },
					RightElbow = { rx = 0.3 },
					LeftShoulder = { rx = 0.35 },
					Waist = { rx = 0.18 },
					Neck = { rx = 0.12 },
				},
			},
			{ t = 1, pose = REST },
		},
	},
	-- trap / pad / balloon / rocket: swing the arm back low, then an under-arm toss forward
	throw = {
		seconds = 0.5,
		keys = {
			{ t = 0, pose = REST },
			{
				t = 0.35,
				pose = { RightShoulder = { rx = -1.9, rz = 0.1 }, RightElbow = { rx = 0.2 }, Waist = { ry = -0.25 } },
			},
			{
				t = 0.65,
				pose = { RightShoulder = { rx = 0.25 }, RightElbow = { rx = -0.1 }, Waist = { ry = 0.2, rx = -0.15 } },
			},
			{ t = 1, pose = REST },
		},
	},
	-- confetti / bubbles / hats / dance bomb: raise it high and give it a twirl
	use = {
		seconds = 0.55,
		keys = {
			{ t = 0, pose = REST },
			{
				t = 0.35,
				pose = { RightShoulder = { rx = 1.2, rz = 0.2 }, RightWrist = { ry = 0.8 }, Waist = { rz = 0.1 } },
			},
			{
				t = 0.6,
				pose = { RightShoulder = { rx = 1.3, rz = 0.1 }, RightWrist = { ry = -0.8 }, Waist = { rz = -0.1 } },
			},
			{ t = 1, pose = REST },
		},
	},
	-- Confetti Popper: point it high, then the pop kicks the arm and the chest back
	pop = {
		seconds = 0.45,
		keys = {
			{ t = 0, pose = REST },
			{
				t = 0.35,
				pose = { RightShoulder = { rx = 2.3, rz = 0.15 }, RightElbow = { rx = 0.2 }, Waist = { rx = 0.05 } },
			},
			{
				t = 0.55,
				pose = {
					RightShoulder = { rx = 2.6, rz = 0.25 },
					RightElbow = { rx = 0.6 },
					Waist = { rx = 0.22 },
					Neck = { rx = 0.2 },
				},
			},
			{ t = 1, pose = REST },
		},
	},
	-- Bubble Wand: the wand to the lips, a long blow, then a sweep to send the bubbles off
	blow = {
		seconds = 0.9,
		keys = {
			{ t = 0, pose = REST },
			{
				t = 0.25,
				pose = { RightShoulder = { rx = 1.5, rz = -0.25 }, RightElbow = { rx = 1.7 }, Neck = { rx = -0.1 } },
			},
			{
				t = 0.6,
				pose = { RightShoulder = { rx = 1.5, rz = -0.2 }, RightElbow = { rx = 1.5 }, Waist = { rx = 0.08 } },
			},
			{
				t = 0.8,
				pose = { RightShoulder = { rx = 1.4, rz = 0.4 }, RightElbow = { rx = 0.2 }, Waist = { ry = 0.2 } },
			},
			{ t = 1, pose = REST },
		},
	},
	-- Squeaky Hammer: a big overhead wind-up, then a smash straight down with the chest folding into it
	bonk = {
		seconds = 0.42,
		keys = {
			{ t = 0, pose = REST },
			{
				t = 0.4,
				pose = { RightShoulder = { rx = 2.9, rz = 0.1 }, RightElbow = { rx = 0.7 }, Waist = { rx = 0.25 } },
			},
			{
				t = 0.62,
				pose = {
					RightShoulder = { rx = 0.5 },
					RightElbow = { rx = 0.05 },
					Waist = { rx = -0.3 },
					Neck = { rx = -0.1 },
				},
			},
			{ t = 1, pose = REST },
		},
	},
	-- Dance Bomb victim: disco points, hip sways and a twist, two seconds of it
	dance = {
		seconds = 2,
		keys = {
			{ t = 0, pose = REST },
			{ t = 0.12, pose = DISCO_RIGHT },
			{ t = 0.27, pose = DISCO_LEFT },
			{ t = 0.42, pose = DISCO_RIGHT },
			{ t = 0.57, pose = DISCO_LEFT },
			{
				t = 0.72,
				pose = {
					RightShoulder = { rx = 2.4, rz = 0.9 },
					LeftShoulder = { rx = 2.4, rz = -0.9 },
					Waist = { ry = 0.5 },
					Root = { py = -0.2 },
				},
			},
			{
				t = 0.87,
				pose = {
					RightShoulder = { rx = 2.4, rz = 0.9 },
					LeftShoulder = { rx = 2.4, rz = -0.9 },
					Waist = { ry = -0.5 },
				},
			},
			{ t = 1, pose = REST },
		},
	},
	-- Bounce Pad owner: a full backflip (it ends a whole turn round, so the snap back to rest is invisible)
	flip = {
		seconds = 0.7,
		keys = {
			{ t = 0, pose = REST },
			{ t = 0.33, pose = { Root = { rx = -2.1, py = 0.6 }, Waist = { rx = -0.3 } } },
			{ t = 0.66, pose = { Root = { rx = -4.2, py = 0.6 }, Waist = { rx = -0.3 } } },
			{ t = 0.9999, pose = { Root = { rx = -2 * math.pi } } },
			{ t = 1, pose = REST },
		},
	},
	-- the victim of a push: a squash down, then the chest snaps back with the arms flung out
	hit = {
		seconds = 0.45,
		keys = {
			{ t = 0, pose = REST },
			{ t = 0.12, pose = { Root = { py = -0.35 }, Waist = { rx = -0.15 } } },
			{
				t = 0.35,
				pose = {
					Root = { py = 0.1 },
					Waist = { rx = 0.4 },
					Neck = { rx = 0.35 },
					RightShoulder = { rz = 0.7, rx = 0.3 },
					LeftShoulder = { rz = -0.7, rx = 0.3 },
				},
			},
			{ t = 1, pose = REST },
		},
	},
}
for _, clip in CLIPS do
	table.freeze(clip.keys)
	table.freeze(clip)
end
PvpAnimLogic.CLIPS = table.freeze(CLIPS)

-- The equipped pose: the right arm out in front (the item shows). Blasters take the left hand to the barrel.
PvpAnimLogic.HOLD = table.freeze({
	RightShoulder = { rx = 1.35, rz = 0.05 },
	RightElbow = { rx = 0.25 },
} :: Pose)
PvpAnimLogic.HOLD_TWO_HANDS = table.freeze({
	RightShoulder = { rx = 1.4, rz = 0.05 },
	RightElbow = { rx = 0.2 },
	LeftShoulder = { rx = 1.35, rz = 0.55 },
	LeftElbow = { rx = 0.45 },
} :: Pose)

local THROWN = table.freeze({ FunBouncePad = true, FunBalloon = true, FunFireworks = true, FunDanceBomb = true })
-- Fun items with a pose of their own (CONTRACT.md §26.4).
local FUN_KIND: { [string]: string } =
	table.freeze({ FunConfetti = "pop", FunBubbles = "blow", FunSqueaky = "bonk", FunHatLauncher = "blast" })

local function toolOf(itemId: string, tools: { any }): any
	for _, def in tools do
		if def.id == itemId then
			return def
		end
	end
	return nil
end

-- The use animation of `itemId` ("Bat" or a Config.PVP_TOOLS id; `tools` = Config.PVP_TOOLS).
function PvpAnimLogic.kindFor(itemId: any, tools: { any }): string?
	if itemId == "Bat" then
		return "swing"
	end
	if type(itemId) ~= "string" then
		return nil
	end
	if FUN_KIND[itemId] then
		return FUN_KIND[itemId]
	end
	local tool = toolOf(itemId, tools)
	if not tool then
		return nil
	end
	if tool.line == "Knockback" then
		return "punch"
	elseif tool.line == "Blaster" then
		return "blast"
	elseif tool.line == "Trap" or THROWN[itemId] then
		return "throw"
	end
	return "use"
end

function PvpAnimLogic.holdFor(itemId: any, tools: { any }): Pose?
	if type(itemId) ~= "string" then
		return nil
	end
	local tool = toolOf(itemId, tools)
	if not tool then
		return nil
	end
	return if tool.line == "Blaster" then PvpAnimLogic.HOLD_TWO_HANDS else PvpAnimLogic.HOLD
end

local function smooth(x: number): number
	return x * x * (3 - 2 * x)
end

local FIELDS = { "rx", "ry", "rz", "py" }

-- The pose of clip `kind` at `elapsed` seconds: keys blended with smoothstep; nil when unknown or over.
function PvpAnimLogic.pose(kind: string, elapsed: number): Pose?
	local clip = CLIPS[kind]
	if not clip or elapsed ~= elapsed or elapsed < 0 or elapsed >= clip.seconds then
		return nil
	end
	local t = elapsed / clip.seconds
	local keys = clip.keys
	for i = 1, #keys - 1 do
		local a, b = keys[i], keys[i + 1]
		if t <= b.t then
			local k = smooth(math.clamp((t - a.t) / math.max(b.t - a.t, 1e-6), 0, 1))
			local out: Pose = {}
			for _, joint in PvpAnimLogic.JOINTS do
				local pa, pb = a.pose[joint], b.pose[joint]
				if pa or pb then
					local angles: Angles = {}
					for _, f in FIELDS do
						local va = if pa then (pa :: any)[f] or 0 else 0
						local vb = if pb then (pb :: any)[f] or 0 else 0
						local v = va + (vb - va) * k
						if v ~= 0 then
							(angles :: any)[f] = v
						end
					end
					out[joint] = angles
				end
			end
			return out
		end
	end
	return nil
end

-- hold x weight + anim, joint by joint (either may be nil).
function PvpAnimLogic.combine(hold: Pose?, weight: number, anim: Pose?): Pose
	local out: Pose = {}
	for _, joint in PvpAnimLogic.JOINTS do
		local h = if hold and weight > 0 then hold[joint] else nil
		local a = if anim then anim[joint] else nil
		if h or a then
			local angles: Angles = {}
			for _, f in FIELDS do
				local v = (if h then ((h :: any)[f] or 0) * weight else 0) + (if a then (a :: any)[f] or 0 else 0)
				if v ~= 0 then
					(angles :: any)[f] = v
				end
			end
			out[joint] = angles
		end
	end
	return out
end

-- Moves `weight` toward `target` (0 or 1) at HOLD_RATE per second.
function PvpAnimLogic.approach(weight: number, target: number, dt: number): number
	local step = PvpAnimLogic.HOLD_RATE * math.max(dt, 0)
	if weight < target then
		return math.min(target, weight + step)
	end
	return math.max(target, weight - step)
end

return PvpAnimLogic
