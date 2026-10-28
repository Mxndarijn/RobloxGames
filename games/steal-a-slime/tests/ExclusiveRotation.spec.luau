--!strict
local T = require("./TestRunner")
local describe, it, expect = T.describe, T.it, T.expect
local Config = require("../src/shared/Config")
local ExclusiveRotation = require("../src/shared/ExclusiveRotation")

describe("ExclusiveRotation", function()
	it("features the configured number of distinct Exclusive seats", function()
		for week = 2800, 2830 do
			local list = ExclusiveRotation.featured(week)
			expect(#list).toBe(Config.EXCLUSIVE_SHOP.featuredCount)
			local seen = {}
			for _, id in list do
				expect(seen[id]).toBeNil()
				seen[id] = true
				expect(table.find(ExclusiveRotation.SEATS, id) ~= nil).toBe(true)
			end
		end
	end)

	it("is the same for the same week and changes between weeks", function()
		expect(table.concat(ExclusiveRotation.featured(2811), ",")).toBe(
			table.concat(ExclusiveRotation.featured(2811), ",")
		)
		local changed = 0
		for week = 2800, 2810 do
			if
				table.concat(ExclusiveRotation.featured(week), ",")
				~= table.concat(ExclusiveRotation.featured(week + 1), ",")
			then
				changed += 1
			end
		end
		expect(changed >= 9).toBe(true)
	end)

	it("maps a unix time to its UTC week", function()
		expect(ExclusiveRotation.week(0)).toBe(0)
		expect(ExclusiveRotation.week(7 * 24 * 3600 - 1)).toBe(0)
		expect(ExclusiveRotation.week(7 * 24 * 3600)).toBe(1)
	end)
end)
