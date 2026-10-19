--!strict
-- Owner-only plot pad purchases (LockPrompt / BuyPadPrompt / MergePrompt) with WorldShopsStrict ON: they are measured against
-- THEIR OWN prompt part (PlotPadGuard), never against the Item Shop stand, which is far from every plot.
local Actions = require("../src/server/Actions")
local Config = require("../src/shared/Config")
local Fixtures = require("./Fixtures")
local PlotPadGuard = require("../src/server/PlotPadGuard")
local ServerFixtures = require("./ServerFixtures")
local ShopGuard = require("../src/server/ShopGuard")
local TestRunner = require("./TestRunner")

local describe, it, expect = TestRunner.describe, TestRunner.it, TestRunner.expect
local T0 = ServerFixtures.T0
local RANGE = PlotPadGuard.range()

local function setup(slimes: { any }?)
	local world = ServerFixtures.world()
	local session = ServerFixtures.join(world, 1, slimes, 10_000_000)
	ServerFixtures.unlock(session)
	local env = {
		world = world,
		session = session,
		pad = { distance = 3, alive = true } :: PlotPadGuard.Access,
		shop = { distance = 500, alive = true } :: ShopGuard.Access, -- the Item Shop stand is nowhere near the plot
		kinds = {} :: { string },
		ctx = {} :: Actions.Context,
	}
	env.ctx = {
		distanceBetween = function()
			return 2
		end,
		positionOf = function()
			return nil
		end,
		features = { WorldShops = true, WorldShopsStrict = true },
		shopAccess = function()
			return env.shop
		end,
		plotPadAccess = function(_userId, kind)
			table.insert(env.kinds, kind)
			return env.pad
		end,
	}
	return env
end

local function prompt(env: any, kind: string, ...: any)
	env.session.limiter = {}
	return Actions.handlePlotPad(env.world, 1, kind, table.pack(...), T0 + 100, env.ctx)
end

local function request(env: any, action: string, ...: any)
	env.session.limiter = {}
	return Actions.handle(env.world, 1, action, table.pack(...), T0 + 100, env.ctx)
end

describe("PlotPadGuard", function()
	it("range is the prompt distance plus the slack, and exactly the range counts", function()
		expect(RANGE).toBe(Config.PLOT_PAD_PROMPT_DISTANCE + Config.PLOT_PAD_RANGE_SLACK)
		expect(PlotPadGuard.check({ distance = RANGE, alive = true })).toBeNil()
		expect(PlotPadGuard.check({ distance = RANGE + 0.1, alive = true })).toBe("OutOfRange")
		expect(PlotPadGuard.check({ distance = 0, alive = false })).toBe("Dead")
		expect(PlotPadGuard.check({ distance = nil, alive = true })).toBe("NoCharacter")
		expect(PlotPadGuard.check(nil)).toBe("NoCharacter")
		expect(PlotPadGuard.check({ distance = 0 / 0, alive = true })).toBe("NoCharacter")
		expect(PlotPadGuard.MESSAGES.OutOfRange).toBe("walk closer to your lock pad")
	end)
end)

describe("plot pad prompts under WorldShopsStrict", function()
	it(
		"without the pad check, Request Lock far from the shop fails like the live bug (too far from the shop)",
		function()
			local env = setup()
			env.ctx.plotPadAccess = nil
			expect(request(env, "Lock").code).toBe("OutOfRange")
		end
	)
	it("Lock: the owner at their own pad locks, with the Item Shop far away", function()
		local env = setup()
		local cash = env.session.data.cash
		local res = prompt(env, "Lock")
		expect(res.ok).toBe(true)
		expect(env.session.lockUntil > T0 + 100).toBeTruthy()
		expect(env.session.data.cash < cash).toBe(true)
		expect(env.kinds[1]).toBe("Lock")
	end)
	it("Lock: too far from the pad, no character, or dead is refused without charging", function()
		local env = setup()
		local cash = env.session.data.cash
		env.pad = { distance = RANGE + 1, alive = true }
		expect(prompt(env, "Lock").message).toBe("walk closer to your lock pad")
		env.pad = { distance = nil, alive = true }
		expect(prompt(env, "Lock").ok).toBe(false)
		env.pad = { distance = 1, alive = false }
		expect(prompt(env, "Lock").ok).toBe(false)
		expect(env.session.data.cash).toBe(cash)
		expect(env.session.lockUntil).toBe(0)
	end)
	it("BuyPad from the pad works; too far does not", function()
		local env = setup()
		env.session.data.padsUnlocked = 4
		env.pad = { distance = RANGE + 5, alive = true }
		expect(prompt(env, "BuyPad").ok).toBe(false)
		expect(env.session.data.padsUnlocked).toBe(4)
		env.pad = { distance = 2, alive = true }
		expect(prompt(env, "BuyPad").ok).toBe(true)
		expect(env.session.data.padsUnlocked).toBe(5)
	end)
	it("Merge from the vat works; too far does not", function()
		local env = setup({ Fixtures.slime("a", 1), Fixtures.slime("b", 1) })
		env.pad = { distance = RANGE + 5, alive = true }
		expect(prompt(env, "Merge", "a", "b").ok).toBe(false)
		expect(#env.session.data.slimes).toBe(2)
		env.pad = { distance = 2, alive = true }
		expect(prompt(env, "Merge", "a", "b").ok).toBe(true)
		expect(env.session.data.slimes[1].tier).toBe(2)
	end)
	it("only the three pad kinds go through handlePlotPad", function()
		local env = setup()
		expect(prompt(env, "BuySpeedCoil").message).toBe("unknown action")
		expect(prompt(env, "BuyLockUpgrade").message).toBe("unknown action")
	end)
	it("the bypass is private: the shared ctx still gates the shop purchases", function()
		local env = setup()
		prompt(env, "Lock")
		expect(env.ctx.strictBypass).toBeNil()
		env.session.lockUntil = 0
		env.pad = { distance = 500, alive = true } -- far from the pad too
		expect(request(env, "Lock").code).toBe("OutOfRange")
		expect(request(env, "BuyLockUpgrade").code).toBe("OutOfRange")
		expect(request(env, "BuySpeedCoil").code).toBe("OutOfRange")
		expect(request(env, "Sell", "nope").code).toBeNil() -- not a shop item: never gated
	end)
	it("HUD Request Lock works while standing at the pad (strict), else needs the shop as before", function()
		local env = setup()
		env.pad = { distance = 2, alive = true }
		expect(request(env, "Lock").ok).toBe(true)
		env.session.lockUntil = 0
		env.pad = { distance = RANGE + 1, alive = true }
		expect(request(env, "Lock").code).toBe("OutOfRange")
		request(env, "OpenShop", "ItemShop") -- far: refused
		env.shop = { distance = 3, alive = true }
		expect(request(env, "OpenShop", "ItemShop").ok).toBe(true)
		expect(request(env, "Lock").ok).toBe(true) -- shop path unchanged
	end)
	it("ShopBuy ItemShop/Lock stays on the shop path (pad position is irrelevant)", function()
		local env = setup()
		env.pad = { distance = 2, alive = true }
		expect(request(env, "ShopBuy", "ItemShop", "Lock").code).toBe("NotOpen")
		env.shop = { distance = 3, alive = true }
		request(env, "OpenShop", "ItemShop")
		expect(request(env, "ShopBuy", "ItemShop", "Lock").ok).toBe(true)
	end)
end)

describe("Actions.triggerPlotPrompt", function()
	local function trigger(env: any, userId: number, plotIndex: number, kind: string)
		env.session.limiter = {}
		return Actions.triggerPlotPrompt(env.world, userId, plotIndex, kind, T0 + 100, env.ctx)
	end
	it("someone else's plot answers with a toast naming the owner, a free plot says nobody owns it", function()
		local env = setup()
		local other = ServerFixtures.join(env.world, 2, nil, 5000)
		expect(trigger(env, 2, env.session.plotIndex, "Lock").ok).toBe(false)
		expect(ServerFixtures.notifications(env.world, 2)).toEqual({ `This is {env.session.name}'s base` })
		expect(env.session.lockUntil).toBe(0)
		local free = env.world.plotCount
		expect(env.world.plots[free]).toBeNil()
		trigger(env, 2, free, "Lock")
		expect(ServerFixtures.notifications(env.world, 2)[2]).toBe("Nobody owns this plot")
		expect(other.data.cash).toBe(5000)
	end)
	it("the owner's Lock runs the pad action", function()
		local env = setup()
		expect(trigger(env, 1, env.session.plotIndex, "Lock").ok).toBe(true)
		expect(env.session.lockUntil > T0 + 100).toBe(true)
	end)
	it("Merge with the 3-slime vat on leaves the pick to the owner's merge menu", function()
		local env = setup({ Fixtures.slime("a", 1), Fixtures.slime("b", 1) })
		env.ctx.features = { MergeVat3 = true }
		expect(trigger(env, 1, env.session.plotIndex, "Merge").ok).toBe(true)
		expect(ServerFixtures.notifications(env.world, 1)).toEqual({})
		expect(#env.session.data.slimes).toBe(2)
	end)
	it("Merge with the vat off picks the pair itself and toasts when there is none", function()
		local env = setup({ Fixtures.slime("a", 1), Fixtures.slime("b", 2) })
		env.ctx.features = { MergeVat3 = false }
		expect(trigger(env, 1, env.session.plotIndex, "Merge").ok).toBe(false)
		expect(ServerFixtures.notifications(env.world, 1)).toEqual({ "Need two slimes of the same rarity" })
		env = setup({ Fixtures.slime("a", 1), Fixtures.slime("b", 1) })
		env.ctx.features = { MergeVat3 = false }
		expect(trigger(env, 1, env.session.plotIndex, "Merge").ok).toBe(true)
		expect(env.session.data.slimes[1].tier).toBe(2)
	end)
	it("a refused pad action toasts its reason", function()
		local env = setup()
		env.pad = { distance = RANGE + 1, alive = true }
		expect(trigger(env, 1, env.session.plotIndex, "Lock").ok).toBe(false)
		expect(ServerFixtures.notifications(env.world, 1)).toEqual({ "walk closer to your lock pad" })
	end)
end)
