--!strict
-- Save v12 -> v13 (SaveData.migrateV12): the Goo Factory and Mushroom Pagoda became Exclusive, so a player whose
-- rebirths had unlocked them (20 / 25, SaveData.REBIRTH_BASES_V12) owns them after loading.
local Config = require("../src/shared/Config")
local PlotBases = require("../src/shared/PlotBases")
local SaveData = require("../src/shared/SaveData")
local TestRunner = require("./TestRunner")

local describe, it, expect = TestRunner.describe, TestRunner.it, TestRunner.expect

local function v12(rebirths: number, extra: { [string]: any }?): { [string]: any }
	local raw = SaveData.serialize(require("../src/shared/PlayerData").new(), 1700000000) :: any
	raw.version = 12
	raw.rebirths = rebirths
	for k, v in extra or {} do
		raw[k] = v
	end
	return raw
end

describe("SaveData.migrateV12", function()
	it("gives the factory at 20 rebirths and the pagoda at 25, nothing below", function()
		local function owned(rebirths: number): string
			local d = SaveData.deserialize(v12(rebirths))
			table.sort(d.ownedStyles.plotBase or {})
			return table.concat(d.ownedStyles.plotBase or {}, ",")
		end
		expect(owned(0)).toBe("")
		expect(owned(19)).toBe("")
		expect(owned(20)).toBe("factory")
		expect(owned(25)).toBe("factory,pagoda")
		expect(Config.SAVE_VERSION).toBe(13)
	end)
	it("keeps an equipped Pagoda equipped and other owned bases owned, without repeats", function()
		local raw = v12(25, { plotBase = "pagoda", ownedStyles = { plotBase = { "rocket", "pagoda" } } })
		local d = SaveData.deserialize(raw)
		expect(PlotBases.current(d)).toBe("pagoda")
		table.sort(d.ownedStyles.plotBase)
		expect(table.concat(d.ownedStyles.plotBase, ",")).toBe("factory,pagoda,rocket")
	end)
	it("runs once: a v13 save with fewer bases is left as it is", function()
		local raw = v12(25)
		raw.version = 13
		local d = SaveData.deserialize(raw)
		expect(#(d.ownedStyles.plotBase or {})).toBe(0)
		expect(SaveData.migrateV12(SaveData.migrateV12(v12(20))).ownedStyles.plotBase).toEqual({ "factory" })
	end)
end)
