--!strict
--[[
	ClawShow (pure, contract/exclusive-shop.md §7.2)

	The claw show at the Exclusive Shop: after a purchase is granted, the trophy slime on the roof lowers its goo hand
	into the claw box, grabs the bought seat from its pedestal (or a prize capsule for an item without a 3D model),
	carries it to the gold funnel and drops it; it pops out of the prize chute on the counter under the buyer's banner
	and flies off. Every client plays the same show from the same server time. No Roblox APIs.

	Stand frame: the ExclusiveShopStand's own frame (Roblox axes, origin on the ground, front -Z,
	WorldLayout.clawPoint). Times are seconds since the show's start.

	  STEPS            the steps in order, each { name, seconds } (Config.EXCLUSIVE_SHOP.claw.steps)
	  DURATION         the whole show
	  CAPSULE          the `display` of a show that takes a prize capsule (0)
	  target(display)  the bottom of the prize at rest: a pedestal top, or the capsule spot
	  frame(display, t) the show at t: `hand` (the hand's top), `prize` (its bottom and scale, nil when hidden),
	                   `holding` (the pedestal's seat is out of its spot), `banner` (the buyer's banner shows),
	                   `done`
	  bannerText(e)    the banner's words: "<buyer> got <label>!", "<buyer> gifted <label>!" or "<buyer> got a prize!"
	  schedule(q, now) the server's queue: the start time of a new show, or nil when it would wait too long
]]

local Config = if script then require(script.Parent.Parent.Shared.Config) else require("../../shared/Config")
local WorldLayout = if script then require(script.Parent.WorldLayout) else require("./WorldLayout")

export type Vec = { number }
export type Event = { startAt: number, display: number, buyer: string, label: string?, gift: boolean? }
export type Frame = {
	hand: Vec,
	prize: { pos: Vec, scale: number }?,
	holding: boolean,
	banner: boolean,
	done: boolean,
}
export type Queue = { nextFree: number }

local CLAW = Config.EXCLUSIVE_SHOP.claw
local LAYOUT = WorldLayout.EXCLUSIVE_CLAW
local ORDER = { "aim", "drop", "grab", "lift", "carry", "release", "pop", "show", "fly" }

local ClawShow = {}

ClawShow.CAPSULE = 0

local steps = {}
local starts: { [string]: number } = {}
local total = 0
for _, name in ORDER do
	local seconds = (CLAW.steps :: any)[name] :: number
	starts[name] = total
	total += seconds
	table.insert(steps, table.freeze({ name = name, seconds = seconds }))
end
ClawShow.STEPS = table.freeze(steps)
ClawShow.DURATION = total

local function point(p: { number }): Vec
	return WorldLayout.clawPoint(p)
end

local IDLE = point(LAYOUT.handIdle)
local FUNNEL = point(LAYOUT.funnelTop)
local MOUTH = point(LAYOUT.chuteMouth)
-- The claw box's inside in the stand frame (kit x flips to -X; kit y is Z).
local BOX_X = { -LAYOUT.boxX[2] * LAYOUT.scale, -LAYOUT.boxX[1] * LAYOUT.scale }
local BOX_Z = { LAYOUT.boxZ[1] * LAYOUT.scale, LAYOUT.boxZ[2] * LAYOUT.scale }

local function ease(a: number): number
	local x = math.clamp(a, 0, 1)
	return x * x * (3 - 2 * x)
end

local function lerp(a: Vec, b: Vec, t: number): Vec
	return { a[1] + (b[1] - a[1]) * t, a[2] + (b[2] - a[2]) * t, a[3] + (b[3] - a[3]) * t }
end

-- How far into step `name` the show is at t, 0..1 (eased).
local function into(name: string, t: number): number
	local seconds = (CLAW.steps :: any)[name] :: number
	return ease((t - starts[name]) / seconds)
end

function ClawShow.target(display: number): Vec
	local spot = LAYOUT.displays[display]
	return point(if spot then spot else LAYOUT.capsule)
end

-- The hand's top right over a prize at rest height, inside the box.
local function over(at: Vec): Vec
	return { math.clamp(at[1], BOX_X[1], BOX_X[2]), IDLE[2], math.clamp(at[3], BOX_Z[1], BOX_Z[2]) }
end

function ClawShow.frame(display: number, t: number): Frame
	local target = ClawShow.target(display)
	local hover = over(target)
	local grabAt = { hover[1], target[2] + CLAW.grabDepth, hover[3] }
	local funnel = over(FUNNEL)
	local depth = CLAW.grabDepth
	local hand: Vec
	if t < starts.drop then
		hand = lerp(IDLE, hover, into("aim", t))
	elseif t < starts.grab then
		hand = lerp(hover, grabAt, into("drop", t))
	elseif t < starts.lift then
		hand = grabAt
	elseif t < starts.carry then
		hand = lerp(grabAt, hover, into("lift", t))
	elseif t < starts.release then
		hand = lerp(hover, funnel, into("carry", t))
	else
		local back = math.clamp((t - starts.pop) / CLAW.returnSeconds, 0, 1)
		hand = lerp(funnel, IDLE, ease(back))
	end

	local prize: { pos: Vec, scale: number }? = nil
	local held = t >= starts.lift and t < starts.release
	if t >= starts.grab and t < starts.lift then
		prize = { pos = target, scale = 1 }
	elseif held then
		prize = { pos = { hand[1], hand[2] - depth, hand[3] }, scale = 1 }
	elseif t >= starts.release and t < starts.pop then
		local a = into("release", t)
		local from = { funnel[1], funnel[2] - depth, funnel[3] }
		prize = { pos = lerp(from, FUNNEL, a), scale = 1 - 0.7 * a }
	elseif t >= starts.pop and t < starts.fly then
		local a = into("pop", t)
		local up = { MOUTH[1], MOUTH[2] + CLAW.popRise, MOUTH[3] - CLAW.popOut }
		prize = { pos = lerp(MOUTH, up, a), scale = math.max(a, 0.05) }
	elseif t >= starts.fly and t < total then
		local a = into("fly", t)
		local up = { MOUTH[1], MOUTH[2] + CLAW.popRise, MOUTH[3] - CLAW.popOut }
		prize = { pos = { up[1], up[2] + CLAW.flyRise * a, up[3] }, scale = math.max(1 - a, 0.05) }
	end

	return {
		hand = hand,
		prize = prize,
		holding = display ~= ClawShow.CAPSULE and t >= starts.grab and t < total,
		banner = t >= starts.pop and t < total,
		done = t >= total,
	}
end

function ClawShow.bannerText(event: Event): string
	if event.label and event.label ~= "" then
		return if event.gift then `{event.buyer} gifted {event.label}!` else `{event.buyer} got {event.label}!`
	end
	return `{event.buyer} got a prize!`
end

function ClawShow.schedule(queue: Queue, now: number): number?
	local startAt = math.max(now + CLAW.lead, queue.nextFree)
	if startAt - now > CLAW.maxWait then
		return nil
	end
	queue.nextFree = startAt + ClawShow.DURATION + CLAW.gap
	return startAt
end

return table.freeze(ClawShow)
