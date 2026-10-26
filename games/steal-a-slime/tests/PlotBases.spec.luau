--!strict
-- Plot bases: the building a plot stands in, unlocked by rebirths and chosen apart from the skin (CONTRACT.md §44):
-- the config, the unlock rule, the equip remote, State and the save field. FEATURES.BaseShapes is off by default.
local Actions = require("../src/server/Actions")
local Config = require("../src/shared/Config")
local PlayerData = require("../src/shared/PlayerData")
local PlotBases = require("../src/shared/PlotBases")
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

describe("plot bases: config", function()
	it("lists the jar first (everyone's), then the factory at rebirth 20 and the pagoda at rebirth 25", function()
		expect(Config.PLOT_BASE_DEFAULT).toBe("jar")
		local ids, gates = {}, {}
		for _, base in Config.PLOT_BASES do
			table.insert(ids, base.id)
			table.insert(gates, base.rebirths or 0)
		end
		expect(ids).toEqual({ "jar", "factory", "pagoda" })
		expect(gates).toEqual({ 0, 20, 25 })
	end)
	it("is a rate-limited Request action", function()
		expect(Remotes.ACTIONS.EquipPlotBase.args[1]).toBe("string")
		expect(Validate.ACTIONS.EquipPlotBase ~= nil).toBe(true)
	end)
end)

describe("plot bases: unlock and equip", function()
	it("unlocks a base at its rebirth count: one short is locked", function()
		local factory = PlotBases.get("factory") :: Config.PlotBase
		expect(PlotBases.unlocked(reborn(19), factory)).toBe(false)
		expect(PlotBases.unlocked(reborn(20), factory)).toBe(true)
		local pagoda = PlotBases.get("pagoda") :: Config.PlotBase
		expect(PlotBases.unlocked(reborn(24), pagoda)).toBe(false)
		expect(PlotBases.unlocked(reborn(25), pagoda)).toBe(true)
		expect(PlotBases.unlocked(reborn(0), PlotBases.get("jar") :: Config.PlotBase)).toBe(true)
	end)
	it("equip refuses unknown and locked bases and leaves the profile alone", function()
		local data = reborn(5)
		expect(select(2, PlotBases.equip(data, "bogus"))).toBe("unknown plot base")
		expect(select(2, PlotBases.equip(data, "factory"))).toBe("plot base is locked")
		expect(data.plotBase).toBe("jar")
		expect((PlotBases.equip(data, "jar"))).toBe(true)
	end)
	it("current() shows the jar while a saved base is still locked", function()
		local data = reborn(10)
		data.plotBase = "pagoda"
		expect(PlotBases.current(data)).toBe("jar")
		data.rebirths = 25
		expect(PlotBases.current(data)).toBe("pagoda")
	end)
	it("view() lists every base with its gate, the equipped one marked", function()
		local data = reborn(20)
		data.plotBase = "factory"
		local view = PlotBases.view(data)
		expect(#view).toBe(#Config.PLOT_BASES)
		expect(view[1].id).toBe("jar")
		expect(view[2].unlocked).toBe(true)
		expect(view[2].equipped).toBe(true)
		expect(view[3].unlocked).toBe(false)
		expect(view[3].rebirths).toBe(25)
	end)
	it("the Request refuses a locked base, and equips it once the rebirths are there", function()
		local world = ServerFixtures.world()
		local session = ServerFixtures.join(world, 1, {}, 0)
		local res = equip(world, 1, "factory")
		expect(res.ok).toBe(false)
		expect(res.message).toBe("plot base is locked")
		session.data.rebirths = 20
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
		session.data.rebirths = 30
		local res = equip(world, 1, "pagoda", offCtx)
		expect(res.ok).toBe(false)
		expect(res.message).toBe("plot bases are off")
		expect(session.data.plotBase).toBe("jar")
		local state = Snapshot.build(world, session, T0)
		expect(state.plotBase).toBeNil()
		expect(state.plotBases).toBeNil()
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
end)
