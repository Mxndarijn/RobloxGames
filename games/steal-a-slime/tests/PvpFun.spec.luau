--!strict
-- The Fun items (FEATURES.PvP, CONTRACT.md §26.4): rank gating and prices, aimed use with no target, who each item
-- reaches, the shield and control rules, a caught thief's slime going home, the server-side records (landings,
-- bubble streams, pads, holds) and that nothing is left once their time is up. Every flag-dependent call passes the
-- flag explicitly so the specs hold in the forced-flag runs too.
local Actions = require("../src/server/Actions")
local Config = require("../src/shared/Config")
local Fixtures = require("./Fixtures")
local PvpFun = require("../src/server/PvpFun")
local PvpFunRules = require("../src/shared/PvpFunRules")
local PvpRules = require("../src/shared/PvpRules")
local PvpService = require("../src/server/PvpService")
local ServerFixtures = require("./ServerFixtures")
local StealService = require("../src/server/StealService")
local TestRunner = require("./TestRunner")
local roblox = require("@lune/roblox")

local describe, it, expect = TestRunner.describe, TestRunner.it, TestRunner.expect
local T0 = ServerFixtures.T0
local FUN = Config.PVP_FUN
local HERE = { X = 200, Y = 3, Z = -200 }
local NEAR = { X = 205, Y = 3, Z = -200 }
local FAR = { X = 290, Y = 3, Z = -200 }
local IDS = {
	"FunConfetti",
	"FunBalloon",
	"FunBubbles",
	"FunBouncePad",
	"FunSqueaky",
	"FunHatLauncher",
	"FunDanceBomb",
	"FunFireworks",
}

local current: any = nil -- the world of the running test
local positions: { [number]: any } = {}
local slimes: { [string]: any } = {}
local launches: { { userId: number, push: any } } = {}
local bubbles: { { userId: number, seconds: number, lift: number, onPop: any } } = {}
local env: PvpService.Context = {
	positionOf = function(userId: number): any?
		return positions[userId]
	end,
	pose = function(userId: number): (any?, any?)
		return positions[userId], { X = 1, Y = 0, Z = 0 }
	end,
	launch = function(userId: number, push: any): boolean
		table.insert(launches, { userId = userId, push = push })
		return true
	end,
	slimePosition = function(slimeId: string): any?
		return slimes[slimeId]
	end,
	funBubble = function(userId: number, seconds: number, lift: number, onPop): boolean
		table.insert(bubbles, { userId = userId, seconds = seconds, lift = lift, onPop = onPop })
		return true
	end,
}

local function events(): { ServerFixtures.PvpEvent }
	return ServerFixtures.pvpEvents(current)
end

-- The Effect payloads with `effect` (all Effects when nil), oldest first.
local function effects(effect: string?): { { [string]: any } }
	local out = {}
	for _, e in events() do
		if e.payload.kind == "Effect" and (effect == nil or e.payload.effect == effect) then
			table.insert(out, e.payload)
		end
	end
	return out
end

-- a: user (rank 20, owns + equips `id`, a pad slime "gem"), b and c: two other players (rank 20, unshielded).
local function setup(id: string, rebirths: number?): (any, any, any, any)
	launches, bubbles, slimes = {}, {}, {}
	positions = { [1] = HERE, [2] = NEAR, [3] = FAR }
	PvpFun.reset()
	PvpFun.register()
	local world = ServerFixtures.world()
	current = world
	local a = ServerFixtures.join(world, 1, { Fixtures.slime("gem", 3) }, 1e12)
	local b = ServerFixtures.join(world, 2, nil, 1e12)
	local c = ServerFixtures.join(world, 3, nil, 1e12)
	a.data.rebirths = rebirths or 20
	b.data.rebirths, c.data.rebirths = 20, 20
	for _, s in { a, b, c } do
		ServerFixtures.unlock(s)
		PvpService.join(world, s, T0, true)
	end
	expect((PvpService.buy(world, a, id, true))).toBe(true)
	expect((PvpService.equip(a, id, true))).toBe(true)
	return world, a, b, c
end

local function done()
	PvpService.registerLine("Fun", nil)
	PvpFun.reset()
end

local function use(world: any, a: any, id: string, at: number, aim: any?, power: number?): (boolean, string?)
	return PvpService.use(world, a, id, nil, aim, at, true, env, power)
end

-- `thief` steals the user's pad slime "gem" (the real StealService path).
local function steal(world: any, thief: any, at: number)
	expect((StealService.steal(world, thief, "gem", 1, at))).toBe(true)
	expect(thief.carry ~= nil).toBe(true)
end

local function wentHome(world: any, thief: any): boolean
	return thief.carry == nil and world.carriedBy.gem == nil and world.escaping.gem ~= nil
end

local function tick(world: any, session: any, at: number)
	PvpFun.tick(world, session, positions[session.userId], at, env)
end

local function shield(session: any)
	(PvpService.state(session) :: any).shieldUntil = math.huge
	session.data.rebirths = 0
end

local function at(x: number, y: number?, z: number?): any
	return { X = x, Y = y or 3, Z = z or -200 }
end

describe("Fun item data and gating", function()
	it("rank 0 owns only the Confetti Popper; every other item needs its rank", function()
		local zero = {}
		for _, id in IDS do
			local tool = PvpRules.tool(id) :: any
			expect(tool.line).toBe("Fun")
			if tool.rebirths == 0 then
				table.insert(zero, id)
			else
				expect(PvpRules.isUnlocked({ cash = 0, rebirths = tool.rebirths - 1, pvp = nil }, id)).toBe(false)
			end
			expect(PvpRules.isUnlocked({ cash = 0, rebirths = tool.rebirths, pvp = nil }, id)).toBe(true)
		end
		expect(zero).toEqual({ "FunConfetti" })
	end)
	it("fun items cost 0.01 x rebirthCost(gate), at least the minimum", function()
		for _, id in IDS do
			local tool = PvpRules.tool(id) :: any
			local expected = math.max(
				Config.PVP.PRICE_MIN,
				math.floor(Config.PVP.PRICE_FACTOR_FUN * require("../src/shared/Economy").rebirthCost(tool.rebirths))
			)
			expect(PvpRules.price(id)).toBe(expected)
		end
	end)
	it("no fun item has a damage field or exceeds the control cap; cooldowns respect the minimum", function()
		for _, id in IDS do
			local tool = PvpRules.tool(id) :: any
			expect(tool.cooldown >= Config.PVP.MIN_COOLDOWN).toBe(true)
			expect((tool.control or 0) <= Config.PVP.CONTROL_MAX_SECONDS).toBe(true)
			expect((tool.slowSeconds or 0) <= Config.PVP.SLOW_MAX_SECONDS).toBe(true)
			expect(tool.damage).toBeNil()
		end
	end)
end)

describe("Fun items are aimed", function()
	it("every item works with an aim alone, refuses a target, and spends its cooldown", function()
		for _, id in IDS do
			local world, a = setup(id)
			expect((PvpService.use(world, a, id, 2, NEAR, T0 + 1, true, env))).toBe(false) -- a target: refused
			expect(use(world, a, id, T0 + 1, NEAR)).toBe(true) -- ...and that started no cooldown
			expect(select(2, use(world, a, id, T0 + 1.1, NEAR))).toBe("not ready")
			local last = events()[#events()]
			expect(last.payload.kind).toBe("Cooldown")
			expect(last.target).toBe(1)
			expect(PvpService.spawnedCount(a)).toBe(0) -- the server keeps data, not Instances
			done()
		end
	end)
	it("works without an aim (a point in front of the user) and pulls a far aim in to its range", function()
		local world, a = setup("FunBalloon")
		expect(use(world, a, "FunBalloon", T0 + 1, nil)).toBe(true)
		expect(use(world, a, "FunBalloon", T0 + 10, at(1000))).toBe(true)
		local thrown = effects("Balloon")
		expect(#thrown).toBe(2)
		expect(math.abs(PvpFunRules.flatDistance(HERE, thrown[2].position) - FUN.AIM_RANGE) < 1e-6).toBe(true)
		done()
	end)
	it("is unusable when not equipped, and refused with the flag off without any event", function()
		local world, a = setup("FunConfetti")
		expect(select(2, use(world, a, "FunBubbles", T0 + 1, NEAR))).toBe("not equipped")
		ServerFixtures.clearEvents(world)
		expect(select(2, PvpService.use(world, a, "FunConfetti", nil, NEAR, T0 + 1, false, env))).toBe(
			"PvP is not open yet"
		)
		expect(#events()).toBe(0)
		done()
	end)
	it("the hold charge reaches the item through the UsePvpItem action", function()
		local world = setup("FunFireworks")
		local ctx: any = table.clone(env)
		ctx.features = { PvP = true }
		local r = Actions.handle(
			world,
			1,
			"UsePvpItem",
			{ "FunFireworks", nil, roblox.Vector3.new(210, 3, -200), 1 },
			T0 + 5,
			ctx
		)
		expect(r.ok).toBe(true)
		expect(effects("Firework")[1].count).toBe(FUN.FIREWORKS.VOLLEY)
		done()
	end)
end)

describe("Confetti Popper", function()
	it("pops along the aim, also straight up, and rains on everyone under it, the shielded too", function()
		local world, a, b, c = setup("FunConfetti", 0)
		shield(b)
		expect(use(world, a, "FunConfetti", T0 + 1, { X = HERE.X, Y = 500, Z = HERE.Z })).toBe(true)
		local e = effects("Confetti")[1]
		expect(e.position.Y).toBe(HERE.Y + FUN.CONFETTI.RANGE)
		expect(e.radius).toBe(FUN.CONFETTI.RADIUS)
		table.sort(e.targets)
		expect(e.targets).toEqual({ 1, 2 }) -- c is 90 studs away
		expect(e.mega).toBe(false)
		expect(c.carry).toBeNil()
		done()
	end)
	it("a full charge is a mega pop with a wider rain", function()
		local world, a = setup("FunConfetti")
		expect(use(world, a, "FunConfetti", T0 + 1, NEAR, 1)).toBe(true)
		local e = effects("Confetti")[1]
		expect(e.mega).toBe(true)
		expect(e.radius).toBe(FUN.CONFETTI.MEGA_RADIUS)
		done()
	end)
end)

describe("Goo Balloon", function()
	it("lands after its flight and paints everyone in the splash once", function()
		local world, a, b, c = setup("FunBalloon")
		expect(use(world, a, "FunBalloon", T0 + 1, NEAR)).toBe(true)
		local thrown = effects("Balloon")[1]
		expect(thrown.landAt).toBe(T0 + 1 + PvpFunRules.flightTime(HERE, NEAR))
		tick(world, b, thrown.landAt - 0.05)
		expect(#effects("Paint")).toBe(0) -- still in the air
		tick(world, b, thrown.landAt + 0.1)
		tick(world, b, thrown.landAt + 0.2)
		tick(world, c, thrown.landAt + 0.1)
		local paints = effects("Paint")
		expect(#paints).toBe(1)
		expect(paints[1].target).toBe(2)
		expect(paints[1].duration).toBe(FUN.BALLOON.PAINT_SECONDS)
		expect(paints[1].slowed).toBe(false)
		expect(PvpFun.walkFactor(b, thrown.landAt + 0.5)).toBe(1) -- not a thief
		done()
	end)
	it("slows a thief in the splash a little, for slowSeconds", function()
		local world, a, b = setup("FunBalloon")
		steal(world, b, T0 + 1)
		expect(use(world, a, "FunBalloon", T0 + 2, NEAR)).toBe(true)
		local landAt = effects("Balloon")[1].landAt
		tick(world, b, landAt + 0.1)
		expect(effects("Paint")[1].slowed).toBe(true)
		local tool = PvpRules.tool("FunBalloon") :: any
		expect(PvpFun.walkFactor(b, landAt + 0.5)).toBe(1 - tool.slow)
		expect(PvpFun.walkFactor(b, landAt + 0.1 + tool.slowSeconds + 0.01)).toBe(1)
		expect(b.carry ~= nil).toBe(true) -- a splash is not a catch
		done()
	end)
	it("an aim in the sky lands at the user's feet height", function()
		local world, a = setup("FunBalloon")
		expect(use(world, a, "FunBalloon", T0 + 1, at(210, 300))).toBe(true)
		expect(effects("Balloon")[1].position.Y).toBe(HERE.Y - PvpFunRules.FEET)
		done()
	end)
end)

describe("Bubble Wand", function()
	local function bubbleSpot(index: number, t: number): any
		local e = effects("Bubbles")[1]
		local stream = { origin = e.origin, direction = e.direction, startedAt = e.startedAt }
		return PvpFunRules.bubbleAt(stream, index, t)
	end
	it("a bubble that touches another player lifts them (control, walk speed 0), then lets go", function()
		local world, a, b = setup("FunBubbles")
		expect(use(world, a, "FunBubbles", T0 + 1, NEAR)).toBe(true)
		local t = T0 + 1.5
		positions[2] = bubbleSpot(1, t)
		tick(world, b, t)
		local hit = effects("Bubble")[1]
		local tool = PvpRules.tool("FunBubbles") :: any
		expect(hit.target).toBe(2)
		expect(hit.index).toBe(1)
		expect(hit.duration).toBe(tool.control)
		expect(#bubbles).toBe(1)
		expect(bubbles[1].lift).toBe(FUN.BUBBLES.LIFT)
		expect(PvpFun.frozen(b, t + 0.1)).toBe(true)
		expect(PvpFun.frozen(b, t + tool.control + 0.01)).toBe(false)
		tick(world, b, t + 0.1) -- that bubble popped; the next one only pops on a player already lifted
		local lifts = 0
		for _, e in effects("Bubble") do
			lifts += if e.duration > 0 then 1 else 0
		end
		expect(lifts).toBe(1)
		done()
	end)
	it("the user's own bubbles never catch them", function()
		local world, a = setup("FunBubbles")
		expect(use(world, a, "FunBubbles", T0 + 1, NEAR)).toBe(true)
		positions[1] = bubbleSpot(1, T0 + 1.2)
		tick(world, a, T0 + 1.2)
		expect(#effects("Bubble")).toBe(0)
		done()
	end)
	it("another player may pop it early; the bubbled player may not", function()
		local world, a, b = setup("FunBubbles")
		expect(use(world, a, "FunBubbles", T0 + 1, NEAR)).toBe(true)
		positions[2] = bubbleSpot(1, T0 + 1.5)
		tick(world, b, T0 + 1.5)
		local onPop = bubbles[1].onPop
		expect(onPop(2, T0 + 1.7)).toBe(false)
		expect(onPop(3, T0 + 1.8)).toBe(true)
		expect(PvpFun.frozen(b, T0 + 1.9)).toBe(false)
		local pop = effects("Pop")[1]
		expect(pop.target).toBe(2)
		expect(pop.attacker).toBe(3)
		expect(onPop(3, T0 + 1.9)).toBe(false) -- already popped
		done()
	end)
	it("only pops on a shielded or control-immune player", function()
		local world, a, b = setup("FunBubbles")
		shield(b)
		expect(use(world, a, "FunBubbles", T0 + 1, NEAR)).toBe(true)
		positions[2] = bubbleSpot(1, T0 + 1.5)
		tick(world, b, T0 + 1.5)
		expect(effects("Bubble")[1].duration).toBe(0)
		expect(#bubbles).toBe(0)
		expect(PvpFun.frozen(b, T0 + 1.6)).toBe(false)
		done()
	end)
	it("a bubbled thief drops the slime and it goes home", function()
		local world, a, b = setup("FunBubbles")
		steal(world, b, T0 + 1)
		expect(use(world, a, "FunBubbles", T0 + 2, NEAR)).toBe(true)
		positions[2] = bubbleSpot(1, T0 + 2.5)
		tick(world, b, T0 + 2.5)
		expect(wentHome(world, b)).toBe(true)
		expect(table.find(ServerFixtures.notifications(world, 1), "You caught P2! The slime bounced home.") ~= nil).toBe(
			true
		)
		done()
	end)
end)

describe("Bounce Pad", function()
	it("at most maxPlaced live: a new pad replaces the oldest", function()
		local world, a = setup("FunBouncePad")
		local tool = PvpRules.tool("FunBouncePad") :: any
		for i = 1, tool.maxPlaced + 1 do
			expect(use(world, a, "FunBouncePad", T0 + i * 20, at(200 + i))).toBe(true)
		end
		expect(#PvpFun.padsOf(a)).toBe(tool.maxPlaced)
		local cleared, placed = 0, 0
		for _, e in events() do
			if e.payload.kind == "TrapCleared" then
				cleared += 1
			elseif e.payload.kind == "TrapPlaced" then
				placed += 1
				expect(e.payload.itemId).toBe("FunBouncePad")
			end
		end
		expect(placed).toBe(tool.maxPlaced + 1)
		expect(cleared).toBe(1)
		done()
	end)
	it("bounces everyone who steps on it; the owner higher, with a flip", function()
		local world, a, b = setup("FunBouncePad")
		expect(use(world, a, "FunBouncePad", T0 + 1, HERE)).toBe(true)
		local tool = PvpRules.tool("FunBouncePad") :: any
		tick(world, a, T0 + 2)
		positions[2] = HERE
		tick(world, b, T0 + 2)
		expect(#launches).toBe(2)
		expect(launches[1].push.Y).toBe(tool.height)
		expect(launches[2].push.Y).toBe(FUN.BOUNCE_PAD.HEIGHT)
		local bounces = effects("Bounce")
		expect(bounces[1].flip).toBe(true)
		expect(bounces[2].flip).toBe(false)
		expect(bounces[2].velocity.Y > 0).toBe(true)
		tick(world, b, T0 + 2.1) -- re-trigger guard
		expect(#launches).toBe(2)
		tick(world, b, T0 + 2 + FUN.BOUNCE_PAD.RETRIGGER)
		expect(#launches).toBe(3)
		done()
	end)
	it("a shielded player is not bounced; a thief is, and the slime goes home", function()
		local world, a, b, c = setup("FunBouncePad")
		shield(c)
		steal(world, b, T0 + 1)
		expect(use(world, a, "FunBouncePad", T0 + 2, NEAR)).toBe(true)
		positions[3] = NEAR
		tick(world, c, T0 + 3)
		expect(#launches).toBe(0)
		tick(world, b, T0 + 3)
		expect(#launches).toBe(1)
		expect(wentHome(world, b)).toBe(true)
		done()
	end)
	it("expires after its lifetime and is cleared when its owner leaves", function()
		local world, a, b = setup("FunBouncePad")
		expect(use(world, a, "FunBouncePad", T0 + 1, NEAR)).toBe(true)
		tick(world, b, T0 + 1 + FUN.BOUNCE_PAD.SECONDS)
		expect(#PvpFun.padsOf(a)).toBe(0)
		expect(#launches).toBe(0)
		expect(use(world, a, "FunBouncePad", T0 + 100, NEAR)).toBe(true)
		PvpService.leave(world, a, T0 + 101)
		expect(#PvpFun.padsOf(a)).toBe(0)
		expect(PvpFun.liveCount()).toBe(0)
		done()
	end)
end)

describe("Squeaky Hammer", function()
	it("squashes a player flat for `control` seconds, then they spring back with a push", function()
		local world, a, b = setup("FunSqueaky")
		local tool = PvpRules.tool("FunSqueaky") :: any
		expect(use(world, a, "FunSqueaky", T0 + 1, NEAR)).toBe(true)
		local hit = effects("Squash")[1]
		expect(hit.target).toBe(2)
		expect(hit.duration).toBe(tool.control)
		expect(PvpFun.frozen(b, T0 + 1.1)).toBe(true)
		tick(world, b, T0 + 1.2)
		expect(#launches).toBe(0)
		tick(world, b, T0 + 1 + tool.control)
		expect(#launches).toBe(1)
		expect(math.abs(math.sqrt(launches[1].push.X ^ 2 + launches[1].push.Z ^ 2) - tool.nudge) < 1e-6).toBe(true)
		local boing = effects("Boing")[1]
		expect(boing.target).toBe(2)
		expect(boing.velocity.X > 0).toBe(true) -- away from the user
		expect(PvpFun.frozen(b, T0 + 1 + tool.control)).toBe(false)
		done()
	end)
	it("squashes a wild slime and a slime on any plot's pad: cosmetic only", function()
		local world, a = setup("FunSqueaky")
		positions[2] = FAR
		local wild = Fixtures.slime("wild1", 2)
		world.wild.wild1 =
			{ slime = wild, price = 0, spawnedAt = T0, expiresAt = T0 + 99, angle = 0, radius = 0 } :: any
		slimes.wild1 = at(204)
		expect(use(world, a, "FunSqueaky", T0 + 1, at(204))).toBe(true)
		slimes.gem = at(196) -- the user's own pad slime
		expect(use(world, a, "FunSqueaky", T0 + 3, at(196))).toBe(true)
		local squashes = effects("Squash")
		expect(squashes[1].slimeId).toBe("wild1")
		expect(squashes[1].duration).toBe(FUN.HAMMER.SLIME_SQUASH_SECONDS)
		expect(squashes[2].slimeId).toBe("gem")
		expect(world.wild.wild1 ~= nil).toBe(true)
		expect(a.data.slimes[1].id).toBe("gem")
		expect(world.carriedBy.gem).toBeNil()
		expect(#launches).toBe(0)
		done()
	end)
	it("three hits on the same target within the window are a combo", function()
		local world, a = setup("FunSqueaky")
		positions[2] = FAR
		slimes.gem = at(204)
		for i = 0, 2 do
			expect(use(world, a, "FunSqueaky", T0 + 1 + i * 1.5, at(204))).toBe(true)
		end
		local squashes = effects("Squash")
		expect(squashes[1].combo).toBe(false)
		expect(squashes[2].combo).toBe(false)
		expect(squashes[3].combo).toBe(true)
		done()
	end)
	it("a shielded player only gets the bonk; a whiff still squeaks", function()
		local world, a, b = setup("FunSqueaky")
		shield(b)
		expect(use(world, a, "FunSqueaky", T0 + 1, NEAR)).toBe(true)
		expect(effects("Squash")[1].duration).toBe(0)
		expect(PvpFun.frozen(b, T0 + 1.1)).toBe(false)
		positions[2] = FAR
		expect(use(world, a, "FunSqueaky", T0 + 5, at(204))).toBe(true)
		local whiff = effects("Squash")[2]
		expect(whiff.target).toBeNil()
		expect(whiff.slimeId).toBeNil()
		done()
	end)
	it("a bonked thief drops the slime and it goes home", function()
		local world, a, b = setup("FunSqueaky")
		steal(world, b, T0 + 1)
		expect(use(world, a, "FunSqueaky", T0 + 2, NEAR)).toBe(true)
		expect(wentHome(world, b)).toBe(true)
		done()
	end)
end)

describe("Slime Hat Launcher", function()
	it("the first player in the shot wears a hat; hats stack up to MAX_STACK", function()
		local world, a, b = setup("FunHatLauncher")
		for i = 1, FUN.HATS.MAX_STACK + 1 do
			expect(use(world, a, "FunHatLauncher", T0 + i * 5, NEAR)).toBe(true)
		end
		local hats = effects("Hat")
		expect(hats[1].target).toBe(2)
		expect(hats[1].stack).toBe(1)
		expect(hats[2].stack).toBe(2)
		expect(hats[#hats].stack).toBe(FUN.HATS.MAX_STACK)
		expect(PvpFun.hatCount(b, T0 + 21)).toBe(FUN.HATS.MAX_STACK)
		local tool = PvpRules.tool("FunHatLauncher") :: any
		expect(PvpFun.hatCount(b, T0 + 20 + tool.hatSeconds + 1)).toBe(0)
		done()
	end)
	it("a miss lands at the end of the shot with no wearer", function()
		local world, a = setup("FunHatLauncher")
		expect(use(world, a, "FunHatLauncher", T0 + 1, at(200, 3, -100))).toBe(true)
		local hat = effects("Hat")[1]
		expect(hat.target).toBeNil()
		expect(
			math.abs(PvpFunRules.distance({ X = HERE.X, Y = HERE.Y + 1.5, Z = HERE.Z }, hat.position) - FUN.HATS.RANGE)
				< 1e-6
		).toBe(true)
		done()
	end)
end)

describe("Dance Bomb", function()
	it("everyone else inside the disco bubble dances once (control); the user does not", function()
		local world, a, b, c = setup("FunDanceBomb")
		local tool = PvpRules.tool("FunDanceBomb") :: any
		expect(use(world, a, "FunDanceBomb", T0 + 1, NEAR)).toBe(true)
		local disco = effects("Disco")[1]
		expect(disco.duration).toBe(FUN.DANCE.SECONDS)
		positions[1] = NEAR
		tick(world, a, disco.landAt + 0.1)
		tick(world, b, disco.landAt - 0.1)
		expect(#effects("Dance")).toBe(0)
		tick(world, b, disco.landAt + 0.1)
		positions[3] = NEAR -- walks in later, while the bubble stands
		tick(world, c, disco.landAt + FUN.DANCE.SECONDS - 0.1)
		tick(world, b, disco.landAt + 0.3)
		local dances = effects("Dance")
		expect(#dances).toBe(2)
		expect(dances[1].target).toBe(2)
		expect(dances[1].duration).toBe(tool.control)
		expect(PvpFun.frozen(b, disco.landAt + 0.2)).toBe(true)
		done()
	end)
	it("a shielded player keeps walking; a thief dances and the slime goes home", function()
		local world, a, b, c = setup("FunDanceBomb")
		shield(c)
		positions[3] = NEAR
		steal(world, b, T0 + 1)
		expect(use(world, a, "FunDanceBomb", T0 + 2, NEAR)).toBe(true)
		local landAt = effects("Disco")[1].landAt
		tick(world, c, landAt + 0.1)
		tick(world, b, landAt + 0.1)
		local dances = effects("Dance")
		expect(#dances).toBe(1)
		expect(dances[1].target).toBe(2)
		expect(wentHome(world, b)).toBe(true)
		done()
	end)
end)

describe("Goo Fireworks", function()
	it("bursts in the favourite slime's colour; a full charge fires a volley", function()
		local world, a = setup("FunFireworks")
		a.data.favoriteId = "gem"
		expect(use(world, a, "FunFireworks", T0 + 1, NEAR)).toBe(true)
		expect(use(world, a, "FunFireworks", T0 + 30, NEAR, 1)).toBe(true)
		local shots = effects("Firework")
		expect(shots[1].color).toEqual({ 200 / 255, 50 / 255, 100 / 255 })
		expect(shots[1].count).toBe(1)
		expect(shots[2].count).toBe(FUN.FIREWORKS.VOLLEY)
		expect(PvpFunRules.fireworkColor({ slimes = {} })).toEqual({ 0.35, 0.9, 0.3 })
		done()
	end)
end)

describe("Fun item records end", function()
	it("landings and bubble streams are dropped once their time is up", function()
		local world, a, b = setup("FunBalloon")
		expect(use(world, a, "FunBalloon", T0 + 1, NEAR)).toBe(true)
		expect(PvpFun.liveCount()).toBe(1)
		tick(world, b, T0 + 1 + FUN.THROW_MAX_SECONDS + FUN.LANDING_WINDOW + 0.1)
		expect(PvpFun.liveCount()).toBe(0)
		done()
		world, a, b = setup("FunBubbles")
		expect(use(world, a, "FunBubbles", T0 + 1, NEAR)).toBe(true)
		positions[2] = FAR
		tick(world, b, T0 + 2 + FUN.BUBBLES.LIFETIME + FUN.BUBBLES.COUNT * FUN.BUBBLES.SPACING)
		expect(PvpFun.liveCount()).toBe(0)
		done()
	end)
end)
