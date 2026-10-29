--!strict
-- Plot bases: the building a plot stands in, unlocked by rebirths or bought (Exclusive) and chosen apart from the skin
-- (CONTRACT.md §44): the config, the unlock rule, the equip remote, State and the save field.
local Actions = require("../src/server/Actions")
local Config = require("../src/shared/Config")
local PlayerData = require("../src/shared/PlayerData")
local PlotBases = require("../src/shared/PlotBases")
local Purchases = require("../src/server/Purchases")
local Remotes = require("../src/shared/Remotes")
local SaveData = require("../src/shared/SaveData")
local ServerFixtures = require("./ServerFixtures")
local Snapshot = require("../src/server/Snapshot")
local TestRunner = require("./TestRunner")
local Validate = require("../src/shared/Validate")

local describe, it, expect = TestRunner.describe, TestRunner.it, TestRunner.expect
local T0 = ServerFixtures.T0

local ctx: Actions.Context = {
	distanceBetween = function()
		return 2
	end,
	positionOf = function()
		return nil
	end,
	features = { BaseShapes = true },
}
local offCtx: Actions.Context = { distanceBetween = ctx.distanceBetween, positionOf = ctx.positionOf }

local function equip(world: any, userId: number, id: any, c: Actions.Context?)
	world.sessions[userId].limiter = {}
	return Actions.handle(world, userId, "EquipPlotBase", { id }, T0 + 100, c or ctx)
end

local function reborn(n: number): PlayerData.Data
	local data = PlayerData.new()
	data.rebirths = n
	return data
end

local EXCLUSIVE = { "factory", "pagoda", "carousel", "rocket", "treehouse", "lighthouse", "snowglobe" }

local function owning(ids: { string }, rebirths: number?): PlayerData.Data
	local data = reborn(rebirths or 0)
	data.ownedStyles.plotBase = table.clone(ids)
	return data
end

describe("plot bases: config", function()
	it("lists the jar first (everyone's), then the Exclusive bases; none is unlocked by rebirths", function()
		expect(Config.PLOT_BASE_DEFAULT).toBe("jar")
		local ids = {}
		for _, base in Config.PLOT_BASES do
			table.insert(ids, base.id)
			expect(`{base.id}: {base.rebirths}`).toBe(`{base.id}: nil`)
		end
		expect(ids).toEqual({ "jar", table.unpack(EXCLUSIVE) })
	end)
	it("sells each Exclusive base as Base_<id> at its price, also as a gift", function()
		local prices = {
			factory = 399,
			pagoda = 399,
			carousel = 599,
			rocket = 499,
			treehouse = 499,
			lighthouse = 399,
			snowglobe = 399,
		}
		for _, id in EXCLUSIVE do
			local base = PlotBases.get(id) :: Config.PlotBase
			expect(base.exclusive).toBe(true)
			local product = Config.EXCLUSIVE_SHOP.products[`Base_{id}`]
			expect(product.robux).toBe(prices[id])
			expect(product.robux).toBe(base.robux)
			expect(product.grant.kind).toBe("plotBase")
			expect(product.grant.style).toBe(id)
			expect(Purchases.giftable(`Base_{id}`)).toBe(true)
			expect(Config.EXCLUSIVE_SHOP.products[`Gift_Base_{id}`].robux).toBe(prices[id])
		end
		expect(Config.EXCLUSIVE_SHOP.products.Base_jar).toBeNil()
	end)
	it("is a rate-limited Request action", function()
		expect(Remotes.ACTIONS.EquipPlotBase.args[1]).toBe("string")
		expect(Validate.ACTIONS.EquipPlotBase ~= nil).toBe(true)
	end)
end)

describe("plot bases: unlock and equip", function()
	it("the Goo Factory and Mushroom Pagoda are bought, never unlocked by rebirths", function()
		local factory = PlotBases.get("factory") :: Config.PlotBase
		expect(PlotBases.unlocked(reborn(30), factory)).toBe(false)
		expect(PlotBases.unlocked(owning({ "factory" }), factory)).toBe(true)
		local pagoda = PlotBases.get("pagoda") :: Config.PlotBase
		expect(PlotBases.unlocked(reborn(30), pagoda)).toBe(false)
		expect(PlotBases.unlocked(owning({ "pagoda" }), pagoda)).toBe(true)
		expect(PlotBases.unlocked(reborn(0), PlotBases.get("jar") :: Config.PlotBase)).toBe(true)
	end)
	it("equip refuses unknown and locked bases and leaves the profile alone", function()
		local data = reborn(5)
		expect(select(2, PlotBases.equip(data, "bogus"))).toBe("unknown plot base")
		expect(select(2, PlotBases.equip(data, "factory"))).toBe("plot base is locked")
		expect(data.plotBase).toBe("jar")
		expect((PlotBases.equip(data, "jar"))).toBe(true)
	end)
	it("current() shows the jar while a saved base is not owned", function()
		local data = reborn(30)
		data.plotBase = "pagoda"
		expect(PlotBases.current(data)).toBe("jar")
		data.ownedStyles.plotBase = { "pagoda" }
		expect(PlotBases.current(data)).toBe("pagoda")
	end)
	it("view() lists every base, the owned and equipped one marked", function()
		local data = owning({ "factory" })
		data.plotBase = "factory"
		local view = PlotBases.view(data)
		expect(#view).toBe(#Config.PLOT_BASES)
		expect(view[1].id).toBe("jar")
		expect(view[2].unlocked).toBe(true)
		expect(view[2].equipped).toBe(true)
		expect(view[3].unlocked).toBe(false)
		expect(view[3].productKey).toBe("Base_pagoda")
	end)
	it("the Request refuses a base not owned, and equips it once bought", function()
		local world = ServerFixtures.world()
		local session = ServerFixtures.join(world, 1, {}, 0)
		session.data.rebirths = 30
		local res = equip(world, 1, "factory")
		expect(res.ok).toBe(false)
		expect(res.message).toBe("plot base is locked")
		expect(Purchases.grant(world, session, "Base_factory", T0, { features = {} })).toBe(true)
		res = equip(world, 1, "factory")
		expect(res.ok).toBe(true)
		expect(session.data.plotBase).toBe("factory")
	end)
	it("the Request rejects bad arguments", function()
		local world = ServerFixtures.world()
		ServerFixtures.join(world, 1, {}, 0)
		expect(equip(world, 1, nil).ok).toBe(false)
		expect(equip(world, 1, 12).ok).toBe(false)
		expect(equip(world, 1, "bogus").message).toBe("unknown plot base")
	end)
	it("with the flag off the Request is refused and State carries no base fields", function()
		local world = ServerFixtures.world()
		local session = ServerFixtures.join(world, 1, {}, 0)
		session.data.ownedStyles.plotBase = { "pagoda" }
		local res = equip(world, 1, "pagoda", offCtx)
		expect(res.ok).toBe(false)
		expect(res.message).toBe("plot bases are off")
		expect(session.data.plotBase).toBe("jar")
		local state = Snapshot.build(world, session, T0)
		expect(state.plotBase).toBeNil()
		expect(state.plotBases).toBeNil()
	end)
end)

describe("plot bases: Exclusive", function()
	it("an Exclusive base is locked until owned, and no number of rebirths unlocks it", function()
		local rocket = PlotBases.get("rocket") :: Config.PlotBase
		expect(PlotBases.unlocked(reborn(0), rocket)).toBe(false)
		expect(PlotBases.unlocked(reborn(1000), rocket)).toBe(false)
		expect(PlotBases.unlocked(owning({ "rocket" }), rocket)).toBe(true)
		expect(PlotBases.unlocked(owning({ "carousel" }, 1000), rocket)).toBe(false)
	end)
	it("equip refuses an Exclusive base not owned and equips an owned one", function()
		local data = reborn(1000)
		expect(select(2, PlotBases.equip(data, "lighthouse"))).toBe("plot base is locked")
		expect(data.plotBase).toBe("jar")
		data.ownedStyles.plotBase = { "lighthouse" }
		expect((PlotBases.equip(data, "lighthouse"))).toBe(true)
		expect(data.plotBase).toBe("lighthouse")
		expect(PlotBases.current(data)).toBe("lighthouse")
	end)
	it("current() falls back to the jar once an equipped Exclusive base is no longer owned", function()
		local data = owning({ "snowglobe" })
		assert(PlotBases.equip(data, "snowglobe"))
		data.ownedStyles.plotBase = {}
		expect(PlotBases.current(data)).toBe("jar")
		expect(data.plotBase).toBe("snowglobe") -- kept: it shows again if owned again
	end)
	it("view() gives an Exclusive base its flag, product key and price; owned ones unlocked", function()
		local view = PlotBases.view(owning({ "treehouse" }, 30))
		local byId = {}
		for _, v in view do
			byId[v.id] = v
		end
		expect(byId.carousel.exclusive).toBe(true)
		expect(byId.carousel.productKey).toBe("Base_carousel")
		expect(byId.carousel.robux).toBe(599)
		expect(byId.carousel.unlocked).toBe(false)
		expect(byId.treehouse.unlocked).toBe(true)
		expect(byId.pagoda.exclusive).toBe(true)
		expect(byId.pagoda.productKey).toBe("Base_pagoda")
		expect(byId.pagoda.unlocked).toBe(false) -- 30 rebirths no longer unlock it
		expect(byId.jar.exclusive).toBeNil()
	end)
	it("the Request refuses an Exclusive base until it is bought, then equips it", function()
		local world = ServerFixtures.world()
		local session = ServerFixtures.join(world, 1, {}, 0)
		session.data.rebirths = 100
		expect(equip(world, 1, "carousel").message).toBe("plot base is locked")
		expect(Purchases.grant(world, session, "Base_carousel", T0, { features = {} })).toBe(true)
		expect(equip(world, 1, "carousel").ok).toBe(true)
		expect(PlotBases.current(session.data)).toBe("carousel")
	end)
end)

describe("plot bases: save", function()
	it("round-trips the equipped base at the current SAVE_VERSION", function()
		local data = reborn(25)
		data.plotBase = "pagoda"
		local out = SaveData.serialize(data, T0)
		expect(out.plotBase).toBe("pagoda")
		expect(out.version).toBe(Config.SAVE_VERSION)
		expect(SaveData.deserialize(out).plotBase).toBe("pagoda")
	end)
	it("loads missing and unknown bases as the jar, and keeps a known one even while locked", function()
		local raw = SaveData.serialize(PlayerData.new(), T0)
		raw.plotBase = nil
		expect(SaveData.deserialize(raw).plotBase).toBe("jar")
		raw.plotBase = "castle"
		expect(SaveData.deserialize(raw).plotBase).toBe("jar")
		raw.plotBase = 7
		expect(SaveData.deserialize(raw).plotBase).toBe("jar")
		raw.plotBase = "factory"
		raw.rebirths = 0
		expect(SaveData.deserialize(raw).plotBase).toBe("factory")
		expect(SaveData.deserialize(nil).plotBase).toBe("jar")
	end)
	it("keeps owned Exclusive bases and drops unknown, non-exclusive and repeated ids", function()
		local data = owning({ "rocket", "jar", "castle", "rocket", "lighthouse" })
		data.plotBase = "rocket"
		local back = SaveData.deserialize(SaveData.serialize(data, T0))
		expect(back.ownedStyles.plotBase).toEqual({ "rocket", "lighthouse" })
		expect(back.plotBase).toBe("rocket")
		expect(PlotBases.current(back)).toBe("rocket")
		local none = SaveData.deserialize(SaveData.serialize(reborn(0), T0))
		expect(none.ownedStyles.plotBase).toBeNil()
	end)
end)
