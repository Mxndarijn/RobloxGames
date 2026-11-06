--!strict
-- The Strings catalog (src/shared/Strings) and the LocalizationTable made from it (locale/Strings.csv,
-- scripts/gen-locale): every key sits in its area, every source is one whole string, and the shipped CSV
-- matches the catalog.
local fs = require("@lune/fs")

local Localize = require("../../../shared/luau/src/locale/Localize")
local Strings = require("../src/shared/Strings")
local TestRunner = require("./TestRunner")

local describe, it, expect = TestRunner.describe, TestRunner.it, TestRunner.expect

describe("Strings catalog", function()
	it("keeps each area's keys under its prefix", function()
		local wrong = {}
		for _, area in Strings.AREAS do
			for key in area.defs do
				if string.sub(key, 1, #area.prefix) ~= area.prefix then
					table.insert(wrong, `{area.name}: {key}`)
				end
			end
		end
		expect(table.concat(wrong, ", ")).toBe("")
	end)

	it("has no leftover placeholder styles and no padding spaces", function()
		local bad = {}
		for _, entry in Strings.catalog.entries do
			local s = entry.source
			if
				string.find(s, "<n>", 1, true)
				or string.find(s, "<s>", 1, true)
				or string.find(s, "%%[sd]")
				or string.match(s, "^%s")
				or string.match(s, "%s$")
			then
				table.insert(bad, entry.key)
			end
		end
		expect(table.concat(bad, ", ")).toBe("")
	end)

	it("gives every count key both a .one and an .other form", function()
		local missing = {}
		for _, entry in Strings.catalog.entries do
			local base, form = string.match(entry.key, "^(.*)%.(%a+)$")
			if base and (form == "one" or form == "other") then
				local twin = base .. (if form == "one" then ".other" else ".one")
				if not Localize.has(Strings.catalog, twin) then
					table.insert(missing, twin)
				end
			end
		end
		expect(table.concat(missing, ", ")).toBe("")
	end)

	it("ships a fresh locale/Strings.csv (run lune run scripts/gen-locale)", function()
		local shipped = if fs.isFile("locale/Strings.csv") then fs.readFile("locale/Strings.csv") else ""
		shipped = string.gsub(shipped, "\r\n", "\n")
		expect(shipped == Localize.csv(Strings.catalog)).toBe(true)
	end)
end)
