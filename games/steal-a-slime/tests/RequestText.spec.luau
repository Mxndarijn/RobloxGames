--!strict
-- Refusal reasons leave the server as Localize messages (server/RequestText) whose English is the reason itself.
local Actions = require("../src/server/Actions")
local Localize = require("../../../shared/luau/src/locale/Localize")
local RequestText = require("../src/server/RequestText")
local ServerFixtures = require("./ServerFixtures")
local Strings = require("../src/shared/Strings")
local TestRunner = require("./TestRunner")

local describe, it, expect = TestRunner.describe, TestRunner.it, TestRunner.expect

local function english(value: any): string
	return Localize.english(Strings.catalog, value)
end

describe("RequestText", function()
	it("turns a known reason into its message, and back into the same English", function()
		local m = RequestText.message("not enough cash")
		expect(Localize.isMessage(m)).toBe(true)
		expect(m.key).toBe("world.reason.not_enough_cash")
		expect(english(m)).toBe("not enough cash")
	end)

	it("fills a reason's parameters from the text", function()
		local m = RequestText.message("need $1.25K")
		expect(m.key).toBe("world.reason.need_cash")
		expect(m.args.price).toBe("$1.25K")
		expect(english(RequestText.message("Rebirth 12 to grab this"))).toBe("Rebirth 12 to grab this")
		expect(english(RequestText.message("you can only hold 5"))).toBe("you can only hold 5")
	end)

	it("sends rarity and shop names as their data messages", function()
		local vat = RequestText.message("The vat takes Common slimes")
		expect(vat.key).toBe("world.reason.vat_takes")
		local rarity = Strings.dataKey("rarity", "Common", "name")
		if Localize.has(Strings.catalog, rarity) then
			expect(vat.args.rarity.key).toBe(rarity)
		end
		expect(english(vat)).toBe("The vat takes Common slimes")
		expect(english(RequestText.message("open the Item Shop first"))).toBe("open the Item Shop first")
	end)

	it("keeps an unknown reason, a message and an empty text as they are", function()
		expect(RequestText.message("something new")).toBe("something new")
		expect(RequestText.message("")).toBe("")
		local m = Localize.msg("world.reason.too_fast")
		expect(RequestText.message(m)).toBe(m)
	end)

	it("result keeps the English in `reason` and leaves a success alone", function()
		local ok = { ok = true }
		expect(RequestText.result(ok)).toBe(ok)
		local res = RequestText.result({ ok = false, message = "too fast", code = "Busy" })
		expect(res.reason).toBe("too fast")
		expect(res.code).toBe("Busy")
		expect(res.message.key).toBe("world.reason.too_fast")
	end)

	it("covers the refusals real actions give", function()
		local world = ServerFixtures.world()
		local s = ServerFixtures.join(world, 1, {}, 0)
		local ctx: Actions.Context = {
			distanceBetween = function()
				return 2
			end,
			positionOf = function()
				return nil
			end,
		}
		local missed = {}
		for _, call in { { "BuySpeedCoil" }, { "Rebirth" }, { "VatStart" }, { "ClaimQuest", 99 }, { "Drop" } } do
			s.limiter = {}
			local res = Actions.handle(world, 1, call[1], { call[2] }, ServerFixtures.T0, ctx)
			if not res.ok and type(RequestText.message(res.message)) == "string" then
				table.insert(missed, `{call[1]}: {res.message}`)
			end
		end
		expect(table.concat(missed, ", ")).toBe("")
	end)
end)
