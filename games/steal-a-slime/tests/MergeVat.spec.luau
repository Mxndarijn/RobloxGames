--!strict
-- The merge vat's requests (MergeVat, CONTRACT.md §21) through Actions.handle: VatAdd / VatRemove / VatStart /
-- VatCancel / VatCollect, the toasts after a collect, and what a brewing vat locks: income (live and offline),
-- stealing, selling and moving.
local Actions = require("../src/server/Actions")
local Carry = require("../src/server/Carry")
local Config = require("../src/shared/Config")
local Fixtures = require("./Fixtures")
local Income = require("../src/server/Income")
local PlayerData = require("../src/shared/PlayerData")
local Remotes = require("../src/shared/Remotes")
local ServerFixtures = require("./ServerFixtures")
local SlimeRoster = require("../src/shared/SlimeRoster")
local StealService = require("../src/server/StealService")
local TestRunner = require("./TestRunner")
local Validate = require("../src/shared/Validate")
local VatState = require("../src/shared/VatState")
local World = require("../src/server/World")

local describe, it, expect = TestRunner.describe, TestRunner.it, TestRunner.expect
local T0 = ServerFixtures.T0
local slime = Fixtures.slime

local CTX: Actions.Context = {
	distanceBetween = function()
		return 2
	end,
	positionOf = function()
		return nil
	end,
	features = { MoveSlime = true },
}

local function call(world: any, userId: number, action: string, args: { any }, now: number?): any
	world.sessions[userId].limiter = {}
	return Actions.handle(world, userId, action, table.pack(table.unpack(args)), now or T0, CTX)
end

local function fill(world: any, userId: number, ids: { string })
	for _, id in ids do
		assert(call(world, userId, "VatAdd", { id }).ok, id)
	end
end

describe("MergeVat: requests", function()
	it("are registered with a rate limit and the old merge requests are gone", function()
		for _, name in { "VatAdd", "VatRemove", "VatStart", "VatCancel", "VatCollect" } do
			expect(`{name}: {Remotes.ACTIONS[name] ~= nil and Validate.ACTIONS[name] ~= nil}`).toBe(`{name}: true`)
		end
		for _, name in { "Merge", "Merge3", "AutoMerge", "KeepSlime" } do
			expect(`{name}: {Remotes.ACTIONS[name]}`).toBe(`{name}: nil`)
		end
	end)

	it("fill, start, wait, collect: three Commons become one rarer slime on the first pad", function()
		local world = ServerFixtures.world()
		local s = ServerFixtures.join(world, 1, { slime("a", 1), slime("b", 1), slime("c", 1), slime("x", 2) })
		fill(world, 1, { "b", "a", "c" })
		expect(#VatState.ids(s.data)).toBe(3)
		expect(#s.data.slimes).toBe(4)
		expect(call(world, 1, "VatStart", {}).ok).toBe(true)
		local early = call(world, 1, "VatCollect", {}, T0 + 1)
		expect(early.ok).toBe(false)
		expect(early.message).toBe("still brewing")
		expect(call(world, 1, "VatCollect", {}, T0 + Config.MERGE_BREW_SECONDS[1]).ok).toBe(true)
		expect(#s.data.slimes).toBe(2)
		expect(PlayerData.findSlime(s.data, "a")).toBeNil()
		local child = s.data.slimes[2]
		expect(child.tier >= 2).toBe(true)
		expect(child.pad).toBe(2) -- "b" went in first, on pad 2
		expect(s.data.stats.merges).toBe(1)
		expect((s.data :: any).vat).toBeNil()
	end)

	it("refuses a full vat, another rarity and someone else's slime", function()
		local world = ServerFixtures.world()
		ServerFixtures.join(world, 1, { slime("a", 1), slime("b", 1), slime("c", 1), slime("d", 1), slime("r", 3) })
		ServerFixtures.join(world, 2)
		fill(world, 1, { "a" })
		expect(call(world, 1, "VatAdd", { "r" }).message).toBe("The vat takes Common slimes")
		fill(world, 1, { "b", "c" })
		expect(call(world, 1, "VatAdd", { "d" }).message).toBe("The vat is full")
		expect(call(world, 2, "VatAdd", { "d" }).message).toBe("not your slime")
	end)

	it("VatRemove leaves the slime on its pad; cancel keeps the load", function()
		local world = ServerFixtures.world()
		local s = ServerFixtures.join(world, 1, { slime("a", 1), slime("b", 1), slime("c", 1) })
		fill(world, 1, { "a", "b", "c" })
		expect(call(world, 1, "VatRemove", { "b" }).ok).toBe(true)
		expect((PlayerData.findSlime(s.data, "b") :: any).pad).toBe(2)
		fill(world, 1, { "b" })
		call(world, 1, "VatStart", {})
		expect(call(world, 1, "VatRemove", { "a" }).message).toBe("Cancel the brew first")
		expect(call(world, 1, "VatCancel", {}).ok).toBe(true)
		expect(#VatState.ids(s.data)).toBe(3)
		expect(VatState.isBrewing(s.data)).toBe(false)
	end)

	it("a slime a thief is carrying can't start or be added", function()
		local world = ServerFixtures.world()
		local s = ServerFixtures.join(world, 1, { slime("a", 1), slime("b", 1), slime("c", 1) })
		ServerFixtures.join(world, 2)
		ServerFixtures.unlock(s)
		fill(world, 1, { "a", "b" })
		Carry.grab(world, 2, "c", 1, T0)
		expect(call(world, 1, "VatAdd", { "c" }).message).toBe("slime is busy")
	end)
end)

describe("MergeVat: a brewing vat locks its slimes", function()
	local function brewing(): (any, any)
		local world = ServerFixtures.world()
		local s = ServerFixtures.join(world, 1, { slime("a", 1), slime("b", 1), slime("c", 1), slime("x", 1) })
		ServerFixtures.join(world, 2)
		ServerFixtures.unlock(s)
		fill(world, 1, { "a", "b", "c" })
		return world, s
	end

	it("before the brew they still earn and can be stolen; a stolen one leaves the vat on delivery", function()
		local world, s = brewing()
		expect(World.incomeOf(world, s) > PlayerData.slimeIncome(s.data, s.data.slimes[4]) * 3).toBe(true)
		expect((StealService.steal(world, world.sessions[2], "b", 1, T0))).toBe(true)
		PlayerData.removeSlime(s.data, "b") -- what a delivered steal does to the owner
		expect(table.concat(VatState.ids(s.data), ",")).toBe("a,c")
	end)

	it("while brewing they earn nothing, live or offline", function()
		local world, s = brewing()
		call(world, 1, "VatStart", {})
		local one = PlayerData.slimeIncome(s.data, s.data.slimes[4])
		expect(math.abs(World.incomeOf(world, s) - one) < 1e-6).toBe(true)
		local cash = s.data.cash
		s.data.lastOnline = T0 - 600
		Income.applyOffline(world, s, T0)
		local paid = s.data.cash - cash
		expect(paid > 0 and paid <= one * 600 + 1).toBe(true)
	end)

	it("while brewing they can't be stolen, sold or moved", function()
		local world, _ = brewing()
		call(world, 1, "VatStart", {})
		local ok, reason = StealService.steal(world, world.sessions[2], "a", 1, T0)
		expect(ok).toBe(false)
		expect(reason).toBe("That slime is brewing in the vat")
		expect(call(world, 1, "Sell", { "a" }).message).toBe("That slime is brewing in the vat")
		expect(call(world, 1, "MoveSlime", { "a", 4 }).message).toBe("That slime is brewing in the vat")
		expect(call(world, 1, "MoveSlime", { "x", 1 }).message).toBe("That slime is brewing in the vat")
	end)

	it("loads a slime the next rebirth would use up", function()
		local species = Config.REBIRTH_SLIMES[1][1]
		local tier = (SlimeRoster.get(species) :: any).tier
		local world = ServerFixtures.world()
		local s = ServerFixtures.join(world, 1, { slime("only", tier, { species = species }) }, 1e9)
		expect(call(world, 1, "VatAdd", { "only" }).ok).toBe(true)
		expect(VatState.contains(s.data, "only")).toBe(true)
	end)

	it("a rebirth that needs a brewing slime waits for the brew", function()
		local species = Config.REBIRTH_SLIMES[1][1]
		local tier = 1 -- a rarity a new player may brew
		local world = ServerFixtures.world()
		local s = ServerFixtures.join(world, 1, {
			slime("weak", tier, { species = species, size = 0.5 }),
			slime("n1", tier, { species = species, size = 1.5 }),
			slime("n2", tier, { size = 1.5 }),
			slime("n3", tier, { size = 1.5 }),
		}, 1e9)
		fill(world, 1, { "n1", "n2", "n3" })
		assert(call(world, 1, "VatStart", {}).ok, "start")
		PlayerData.removeSlime(s.data, "weak") -- stolen: now the brewing one is the only match
		local res = call(world, 1, "Rebirth", {})
		expect(res.ok).toBe(false)
		expect(res.message).toBe("A slime the rebirth needs is brewing in the vat")
		expect(s.data.rebirths).toBe(0)
	end)
end)

describe("MergeVat: toasts", function()
	local function soda(id: string, species: string)
		return slime(id, 1, { species = species })
	end
	local function brewAndCollect(world: any, ids: { string })
		fill(world, 1, ids)
		call(world, 1, "VatStart", {})
		assert(call(world, 1, "VatCollect", {}, T0 + 3600).ok, "collect")
	end

	it("a recipe hit says 'discovered' the first time and 'brewed' after", function()
		local world = ServerFixtures.world()
		ServerFixtures.join(world, 1, {
			soda("a", "bubbles"),
			soda("b", "gummy"),
			soda("c", "mochi"),
			soda("d", "bubbles"),
			soda("e", "gummy"),
			soda("f", "mochi"),
		})
		brewAndCollect(world, { "a", "b", "c" })
		expect(table.find(ServerFixtures.notifications(world, 1), "You discovered Soda Pop!") ~= nil).toBe(true)
		brewAndCollect(world, { "d", "e", "f" })
		expect(table.find(ServerFixtures.notifications(world, 1), "You brewed a Soda Pop!") ~= nil).toBe(true)
	end)

	it("a random merge names the new slime and no recipe", function()
		local world = ServerFixtures.world()
		ServerFixtures.join(world, 1, { soda("a", "gummy"), soda("b", "gummy"), soda("c", "pebble") })
		brewAndCollect(world, { "a", "b", "c" })
		local texts = ServerFixtures.notifications(world, 1)
		local merged = false
		for _, text in texts do
			expect(string.find(text, "discovered", 1, true)).toBeNil()
			merged = merged or string.find(text, "Merged into", 1, true) ~= nil
		end
		expect(merged).toBe(true)
	end)
end)
