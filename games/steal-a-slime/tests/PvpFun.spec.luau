--!strict
-- The Fun items (FEATURES.PvP, CONTRACT.md §26): rank gating, prices, cooldowns, safe zones, per-item targeting, the
-- Bounce Pad record, Squeaky slap sharing, Hat Launcher friends, Effect events, flag-off refusal, nothing spawned.
-- Every flag-dependent call passes the flag explicitly so the specs hold in the forced-flag runs too.
local Config = require("../src/shared/Config")
local PvpFun = require("../src/server/PvpFun")
local PvpRules = require("../src/shared/PvpRules")
local PvpService = require("../src/server/PvpService")
local ServerFixtures = require("./ServerFixtures")
local TestRunner = require("./TestRunner")

local describe, it, expect = TestRunner.describe, TestRunner.it, TestRunner.expect
local T0 = ServerFixtures.T0
local HERE = { X = 200, Y = 3, Z = -200 } -- clear of every safe zone
local NEAR = { X = 205, Y = 3, Z = -200 }
local FOUNTAIN = { X = 1, Y = 3, Z = 1 }
local FUN = {
	"FunConfetti",
	"FunBalloon",
	"FunBubbles",
	"FunBouncePad",
	"FunSqueaky",
	"FunHatLauncher",
	"FunDanceBomb",
	"FunFireworks",
}

local events: { { target: number?, payload: { [string]: any } } } = {}
local positions: { [number]: any } = {}
local launches: { { userId: number, push: any } } = {}
local plot = true
local friends = false
local env = {
	positionOf = function(userId: number): any?
		return positions[userId]
	end,
	onOwnPlot = function(): boolean
		return plot
	end,
}

local function effects(): { { [string]: any } }
	local out = {}
	for _, e in events do
		if e.payload.kind == "Effect" then
			table.insert(out, e.payload)
		end
	end
	return out
end

-- a: attacker (rank 20, owns + equips `id`), b: second player.
local function setup(id: string, rebirths: number?): (any, any, any)
	events, launches, plot, friends = {}, {}, true, false
	positions = { [1] = HERE, [2] = NEAR }
	PvpService.setSink(function(target, payload)
		table.insert(events, { target = target, payload = payload })
	end, function()
		return T0
	end)
	PvpFun.reset()
	PvpFun.setEnv({
		launcher = function(userId, push)
			table.insert(launches, { userId = userId, push = push })
			return true
		end,
		onOwnPlot = function()
			return plot
		end,
		areFriends = function()
			return friends
		end,
	})
	PvpFun.register()
	local world = ServerFixtures.world()
	local a = ServerFixtures.join(world, 1, nil, 1e12)
	local b = ServerFixtures.join(world, 2, nil, 1e12)
	a.data.rebirths, b.data.rebirths = rebirths or 20, 20
	PvpService.join(a, T0, true)
	PvpService.join(b, T0, true)
	expect((PvpService.buy(world, a, id, true))).toBe(true)
	expect((PvpService.equip(a, id, true))).toBe(true)
	return world, a, b
end

local function done()
	PvpService.setSink(nil)
	PvpService.registerLine("Fun", nil)
	PvpFun.setEnv(nil)
	PvpFun.reset()
end

local function use(world: any, a: any, id: string, at: number, target: number?, aim: any?): (boolean, string?)
	return PvpService.use(world, a, id, target, aim, at, true, env)
end

local function thief(b: any)
	b.carry = { kind = "stolen", slimeId = "gem" } :: any
end

describe("Fun item data and gating", function()
	it("rank 0 owns only the Confetti Popper; every other item needs its rank", function()
		local zero = {}
		for _, id in FUN do
			local tool = PvpRules.tool(id) :: any
			expect(tool.line).toBe("Fun")
			expect(tool.cosmetic == true or id == "FunBouncePad" or id == "FunSqueaky" or id == "FunDanceBomb").toBe(
				true
			)
			if tool.rebirths == 0 then
				table.insert(zero, id)
			end
			if tool.rebirths > 0 then
				expect(PvpRules.isUnlocked({ cash = 0, rebirths = tool.rebirths - 1, pvp = nil }, id)).toBe(false)
			end
			expect(PvpRules.isUnlocked({ cash = 0, rebirths = tool.rebirths, pvp = nil }, id)).toBe(true)
		end
		expect(zero).toEqual({ "FunConfetti" })
		local data = { cash = 1e12, rebirths = 0, pvp = nil }
		expect(select(2, PvpRules.buy(data :: any, "FunBalloon", true))).toBe("needs 1 rebirths")
		expect((PvpRules.buy(data :: any, "FunConfetti", true))).toBe(true)
	end)
	it("fun items cost 0.01 x rebirthCost(gate), at least the minimum", function()
		for _, id in FUN do
			local tool = PvpRules.tool(id) :: any
			local expected = math.max(
				Config.PVP.PRICE_MIN,
				math.floor(Config.PVP.PRICE_FACTOR_FUN * require("../src/shared/Economy").rebirthCost(tool.rebirths))
			)
			expect(PvpRules.price(id)).toBe(expected)
		end
		expect(Config.PVP.PRICE_FACTOR_FUN).toBe(0.01)
	end)
	it("no fun item has a damage field or exceeds the control cap; cooldowns respect the minimum", function()
		for _, id in FUN do
			local tool = PvpRules.tool(id) :: any
			expect(tool.cooldown >= Config.PVP.MIN_COOLDOWN).toBe(true)
			expect((tool.control or 0) <= Config.PVP.CONTROL_MAX_SECONDS).toBe(true)
			expect(tool.damage).toBeNil()
		end
	end)
end)

describe("Confetti, Bubbles", function()
	it("Confetti works in a safe zone, fires a Cosmetic Effect to everyone and a Cooldown to the user", function()
		local world, a = setup("FunConfetti", 0)
		positions[1] = FOUNTAIN
		expect(use(world, a, "FunConfetti", T0 + 1)).toBe(true)
		local e = effects()[1]
		expect(e.kind).toBe("Effect")
		expect(e.effect).toBe("Cosmetic")
		expect(e.itemId).toBe("FunConfetti")
		expect(e.attacker).toBe(1)
		expect(e.duration).toBe(Config.PVP.FX_SECONDS)
		expect(events[1].target).toBeNil()
		expect(events[#events].payload.kind).toBe("Cooldown")
		expect(events[#events].target).toBe(1)
		expect(PvpService.spawnedCount(a)).toBe(0)
		done()
	end)
	it("honours the 5 s cooldown and takes no target", function()
		local world, a = setup("FunConfetti", 0)
		expect(use(world, a, "FunConfetti", T0 + 1)).toBe(true)
		expect(select(2, use(world, a, "FunConfetti", T0 + 3))).toBe("not ready")
		expect(use(world, a, "FunConfetti", T0 + 6.1)).toBe(true)
		expect(select(2, use(world, a, "FunConfetti", T0 + 20, 2))).toBe("no target needed")
		done()
	end)
	it("Bubbles are refused in a safe zone", function()
		local world, a = setup("FunBubbles")
		positions[1] = FOUNTAIN
		expect(select(2, use(world, a, "FunBubbles", T0 + 1))).toBe("safe zone")
		positions[1] = HERE
		expect(use(world, a, "FunBubbles", T0 + 1)).toBe(true)
		expect(effects()[1].itemId).toBe("FunBubbles")
		done()
	end)
	it("is unusable when not owned or not equipped", function()
		local world, a = setup("FunConfetti")
		expect(select(2, use(world, a, "FunBubbles", T0 + 1))).toBe("not equipped")
		done()
	end)
end)

describe("Balloon", function()
	it("needs an aim in range, outside safe zones, and fires decal params", function()
		local world, a = setup("FunBalloon")
		expect(select(2, use(world, a, "FunBalloon", T0 + 1))).toBe("no aim")
		expect(select(2, use(world, a, "FunBalloon", T0 + 1, nil, { X = 300, Y = 3, Z = -200 }))).toBe("too far away")
		expect(select(2, use(world, a, "FunBalloon", T0 + 1, nil, { X = 1, Y = 3, Z = 1 }))).toBe("too far away")
		expect(use(world, a, "FunBalloon", T0 + 1, nil, { X = 210, Y = 3, Z = -200 })).toBe(true)
		local e = effects()[1]
		expect(e.position.X).toBe(210)
		expect(e.duration).toBe(10)
		expect(e.count).toBe(8)
		expect(select(2, use(world, a, "FunBalloon", T0 + 2, nil, { X = 210, Y = 3, Z = -200 }))).toBe("not ready")
		done()
	end)
	it("takes a real Vector3 aim (a native vector, as the Request remote delivers it)", function()
		local world, a = setup("FunBalloon")
		local aim = vector.create(210, 3, -200)
		expect(use(world, a, "FunBalloon", T0 + 1, nil, aim)).toBe(true)
		expect(effects()[1].position).toBe(aim) -- sent on as the vector, so clients can draw it
		done()
	end)
	it("is disabled in safe zones (user or aim) and hits no player", function()
		local world, a = setup("FunBalloon")
		positions[1] = FOUNTAIN
		expect(select(2, use(world, a, "FunBalloon", T0 + 1, nil, { X = 2, Y = 3, Z = 2 }))).toBe("safe zone")
		positions[1] = { X = 30, Y = 3, Z = 30 }
		expect(select(2, use(world, a, "FunBalloon", T0 + 1, nil, { X = 1, Y = 3, Z = 1 }))).toBe("safe zone")
		positions[1] = HERE
		expect(select(2, use(world, a, "FunBalloon", T0 + 1, 2, { X = 205, Y = 3, Z = -200 }))).toBe("no target needed")
		done()
	end)
end)

describe("Fireworks", function()
	it("own plot only", function()
		local world, a = setup("FunFireworks")
		plot = false
		expect(select(2, use(world, a, "FunFireworks", T0 + 1))).toBe("only on your plot")
		plot = true
		expect(use(world, a, "FunFireworks", T0 + 1)).toBe(true)
		local e = effects()[1]
		expect(e.effect).toBe("Cosmetic")
		expect(e.duration).toBe(Config.PVP.FIREWORKS_SECONDS)
		expect(select(2, use(world, a, "FunFireworks", T0 + 5))).toBe("not ready")
		expect(launches).toEqual({})
		done()
	end)
end)

describe("Hat Launcher", function()
	it("works on yourself with no target", function()
		local world, a = setup("FunHatLauncher")
		expect(use(world, a, "FunHatLauncher", T0 + 1)).toBe(true)
		local e = effects()[1]
		expect(e.target).toBe(1)
		expect(e.duration).toBe(30)
		done()
	end)
	it("works on Roblox friends only, in reach", function()
		local world, a = setup("FunHatLauncher")
		expect(select(2, use(world, a, "FunHatLauncher", T0 + 1, 2))).toBe("friends only")
		friends = true
		positions[2] = { X = 260, Y = 3, Z = -200 }
		expect(select(2, use(world, a, "FunHatLauncher", T0 + 1, 2))).toBe("too far away")
		positions[2] = NEAR
		expect(use(world, a, "FunHatLauncher", T0 + 1, 2)).toBe(true)
		expect(effects()[1].target).toBe(2)
		expect(effects()[1].duration).toBe(30)
		expect(launches).toEqual({})
		done()
	end)
	it("a friend in a safe zone or under the new-player shield is refused", function()
		local world, a, b = setup("FunHatLauncher")
		friends = true
		positions[2] = FOUNTAIN
		expect(select(2, use(world, a, "FunHatLauncher", T0 + 1, 2))).toBe("target is in a safe zone")
		positions[2] = NEAR
		b.data.rebirths = 0
		PvpService.join(b, T0, true)
		expect(select(2, use(world, a, "FunHatLauncher", T0 + 1, 2))).toBe("target is shielded")
		done()
	end)
end)

describe("Squeaky Hammer", function()
	it("squeaks only on a non-thief, nudges 2 studs on a thief and shares the slap cooldown", function()
		local world, a, b = setup("FunSqueaky")
		expect(use(world, a, "FunSqueaky", T0 + 10, 2)).toBe(true) -- own plot, no slime: squeak only
		expect(launches).toEqual({})
		expect(effects()[1].push).toBeNil()
		expect(a.lastSlapAt).toBe(T0 + 10)
		thief(b)
		plot = false
		expect(use(world, a, "FunSqueaky", T0 + 20, 2)).toBe(true)
		expect(#launches).toBe(1)
		expect(launches[1].userId).toBe(2)
		local h = math.sqrt(launches[1].push.X ^ 2 + launches[1].push.Z ^ 2)
		expect(math.abs(h - 2) < 1e-9).toBe(true)
		expect(launches[1].push.Y <= Config.PVP.KNOCKBACK_ARC_HEIGHT).toBe(true)
		expect(math.abs(effects()[2].push - 2) < 1e-9).toBe(true)
		expect((PvpService.state(b) :: any).controlUntil).toBe(T0 + 20 + Config.PVP.FUN_NUDGE_CONTROL_SECONDS)
		expect(a.lastSlapAt).toBe(T0 + 20)
		done()
	end)
	it("is refused while the base slap is on cooldown (shared) and starts no hammer cooldown", function()
		local world, a = setup("FunSqueaky")
		a.lastSlapAt = T0 + 10
		expect(select(2, use(world, a, "FunSqueaky", T0 + 10.5, 2))).toBe("slap on cooldown")
		expect(next((PvpService.state(a) :: any).cooldowns)).toBeNil()
		done()
	end)
	it("a non-thief off the plot is refused; reach is checked", function()
		local world, a = setup("FunSqueaky")
		plot = false
		expect(select(2, use(world, a, "FunSqueaky", T0 + 10, 2))).toBe("only on your plot or against a thief")
		plot = true
		positions[2] = { X = 260, Y = 3, Z = -200 }
		expect(select(2, use(world, a, "FunSqueaky", T0 + 10, 2))).toBe("too far away")
		done()
	end)
end)

describe("Dance Bomb", function()
	it("thieves on your own plot only, 2 s of control, then immunity", function()
		local world, a, b = setup("FunDanceBomb")
		expect(select(2, use(world, a, "FunDanceBomb", T0 + 1, 2))).toBe("only thieves")
		thief(b)
		plot = false
		expect(select(2, use(world, a, "FunDanceBomb", T0 + 1, 2))).toBe("only on your plot")
		plot = true
		expect(select(2, use(world, a, "FunDanceBomb", T0 + 1))).toBe("no target")
		expect(use(world, a, "FunDanceBomb", T0 + 1, 2)).toBe(true)
		local e = effects()[1]
		expect(e.effect).toBe("Dance")
		expect(e.target).toBe(2)
		expect(e.duration).toBe(2)
		local state = PvpService.state(b) :: any
		expect(state.controlUntil).toBe(T0 + 3)
		expect(state.immuneUntil).toBe(T0 + 3 + Config.PVP.CONTROL_IMMUNITY_SECONDS)
		expect(select(2, use(world, a, "FunDanceBomb", T0 + 20, 2))).toBe("not ready")
		done()
	end)
	it("a shielded or immune thief is refused without a cooldown", function()
		local world, a, b = setup("FunDanceBomb")
		thief(b)
		local state = PvpService.state(b) :: any
		state.immuneUntil = T0 + 100
		expect(select(2, use(world, a, "FunDanceBomb", T0 + 1, 2))).toBe("target is immune")
		expect(next((PvpService.state(a) :: any).cooldowns)).toBeNil()
		done()
	end)
end)

describe("Bounce Pad", function()
	it("is placed on your own plot only, max 1, announced by TrapPlaced, zero server parts", function()
		local world, a = setup("FunBouncePad")
		plot = false
		expect(select(2, use(world, a, "FunBouncePad", T0 + 1))).toBe("only on your plot")
		plot = true
		expect(use(world, a, "FunBouncePad", T0 + 1)).toBe(true)
		local placed = events[1].payload
		expect(placed.kind).toBe("TrapPlaced")
		expect(placed.itemId).toBe("FunBouncePad")
		expect(placed.owner).toBe(1)
		expect(PvpFun.padOf(a) ~= nil).toBe(true)
		expect(select(2, use(world, a, "FunBouncePad", T0 + 12))).toBe("already placed")
		expect(PvpService.spawnedCount(a)).toBe(0)
		done()
	end)
	it("expires and clears with TrapCleared, then can be placed again", function()
		local world, a = setup("FunBouncePad")
		expect(use(world, a, "FunBouncePad", T0 + 1)).toBe(true)
		local later = T0 + 1 + Config.PVP.BOUNCE_PAD_SECONDS
		expect(use(world, a, "FunBouncePad", later)).toBe(true)
		local cleared = 0
		for _, e in events do
			if e.payload.kind == "TrapCleared" then
				cleared += 1
			end
		end
		expect(cleared).toBe(1)
		done()
	end)
	it(
		"launches the owner straight up, and a thief with control immunity; visitors without a slime are ignored",
		function()
			local world, a, b = setup("FunBouncePad")
			expect(use(world, a, "FunBouncePad", T0 + 1)).toBe(true)
			-- the owner steps on it
			PvpFun.tick(a, HERE, T0 + 2)
			expect(#launches).toBe(1)
			expect(launches[1].userId).toBe(1)
			expect(launches[1].push.X).toBe(0)
			expect(launches[1].push.Z).toBe(0)
			expect(launches[1].push.Y).toBe(25)
			PvpFun.tick(a, HERE, T0 + 2.5) -- still within the retrigger window
			expect(#launches).toBe(1)
			-- a visitor without a slime: nothing
			PvpFun.tick(b, HERE, T0 + 3)
			expect(#launches).toBe(1)
			-- a thief bounces once, then is immune
			thief(b)
			PvpFun.tick(b, HERE, T0 + 4)
			expect(#launches).toBe(2)
			expect(launches[2].userId).toBe(2)
			expect(launches[2].push.X).toBe(0)
			local all = effects()
			expect(#all).toBe(2) -- the owner's own bounce, then the thief's
			expect(all[1].target).toBe(1)
			expect(all[1].velocity.Y > 0 and all[1].velocity.X == 0).toBe(true)
			local e = all[2]
			expect(e.effect).toBe("Bounce")
			expect(e.target).toBe(2)
			expect(e.duration).toBe(1.2)
			expect(e.velocity.Y > 0).toBe(true)
			expect((PvpService.state(b) :: any).controlUntil).toBe(T0 + 4 + 1.2)
			PvpFun.tick(b, HERE, T0 + 5)
			expect(#launches).toBe(2)
			-- away from the pad: nothing
			PvpFun.tick(a, { X = 100, Y = 3, Z = -200 }, T0 + 30)
			expect(#launches).toBe(2)
			done()
		end
	)
	it("is gone when its owner leaves", function()
		local world, a, b = setup("FunBouncePad")
		expect(use(world, a, "FunBouncePad", T0 + 1)).toBe(true)
		PvpService.leave(a, T0 + 5)
		thief(b)
		PvpFun.tick(b, HERE, T0 + 6)
		expect(#launches).toBe(0)
		expect(PvpFun.padOf(a)).toBeNil()
		done()
	end)
end)

describe("Fun items with the flag off", function()
	it("refuses with no event, no state, no pad", function()
		local world, a = setup("FunConfetti", 0)
		events = {}
		for _, id in FUN do
			local ok, reason = PvpService.use(world, a, id, nil, nil, T0 + 1, false, env)
			expect(ok).toBe(false)
			expect(reason).toBe("PvP is not open yet")
		end
		expect(#events).toBe(0)
		expect(PvpFun.padOf(a)).toBeNil()
		expect(PvpService.spawnedCount(a)).toBe(0)
		PvpFun.tick(a, HERE, T0 + 1) -- no pads: a no-op
		expect(#launches).toBe(0)
		done()
	end)
end)
