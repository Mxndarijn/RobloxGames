--!strict
-- The data strings (src/shared/Strings/Data): Config names and descriptions become catalog keys with the
-- Config English as their source, and counted titles become .one / .other keys with {count}.
local Config = require("../src/shared/Config")
local Localize = require("../../../shared/luau/src/locale/Localize")
local PlayerData = require("../src/shared/PlayerData")
local PlayerSettings = require("../src/shared/PlayerSettings")
local Quests = require("../src/shared/Quests")
local Shops = require("../src/shared/Shops")
local Strings = require("../src/shared/Strings")
local TestRunner = require("./TestRunner")

local describe, it, expect = TestRunner.describe, TestRunner.it, TestRunner.expect

local catalog = Strings.catalog

-- "key=source" for every (kind, id, field) whose catalog source is not `english`.
local function mismatches(list: { { any } }): string
	local bad = {}
	for _, row in list do
		local kind, id, field, english = row[1], row[2], row[3], row[4]
		local k = Strings.dataKey(kind, id, field)
		local entry = catalog.byKey[k]
		if entry == nil or entry.source ~= english then
			table.insert(bad, `{k}={if entry then entry.source else "missing"}`)
		end
	end
	return table.concat(bad, ", ")
end

describe("Data strings", function()
	it("keys every upgrade's name and text with the Config English", function()
		local list = {}
		for _, def in Config.UPGRADES do
			table.insert(list, { "upgrade", def.id, "name", def.name })
			table.insert(list, { "upgrade", def.id, "text", def.text })
		end
		expect(mismatches(list)).toBe("")
	end)

	it("keys rarities, rebirth titles, shines and cosmetics by their id or name", function()
		local list = {}
		for _, r in Config.RARITIES do
			table.insert(list, { "rarity", r.name, "name", r.name })
		end
		for _, t in Config.REBIRTH_TIERS do
			table.insert(list, { "rebirthTier", t.title, "title", t.title })
		end
		for _, s in Config.SHINES do
			table.insert(list, { "shine", s.id, "name", s.id })
		end
		for _, def in Config.PET_SEATS do
			table.insert(list, { "petSeat", def.id, "name", def.name })
		end
		for _, def in Config.PLOT_SKINS do
			table.insert(list, { "plotSkin", def.id, "name", def.name })
		end
		for _, def in Config.EXCLUSIVE_SHOP.hats do
			table.insert(list, { "slimeHat", def.id, "name", def.name })
		end
		for _, def in Config.CONSUMABLES do
			table.insert(list, { "consumable", def.id, "text", def.text })
		end
		for id, w in Config.WEATHER do
			table.insert(list, { "weather", id, "displayName", w.displayName })
		end
		expect(mismatches(list)).toBe("")
	end)

	it("gives goal and daily quest titles .one and .other forms with {count}", function()
		local bad = {}
		local function check(kind: string, row: any)
			local base = Strings.dataKey(kind, row.id, "title")
			local one, other = catalog.byKey[base .. ".one"], catalog.byKey[base .. ".other"]
			if one == nil or other == nil then
				table.insert(bad, `{base} missing`)
				return
			end
			local filled = Localize.format(other.source, { count = 7 })
			local expected = string.gsub(string.gsub(row.title, "<n>", "7"), "<s>", "s")
			if filled ~= expected or one.params[1] ~= "count" then
				table.insert(bad, `{base}: {filled}`)
			end
		end
		for _, goal in Config.GOALS do
			check("goal", goal)
		end
		for _, quest in Config.DAILY_QUESTS.pool do
			check("dailyQuest", quest)
		end
		expect(table.concat(bad, ", ")).toBe("")
		local catch = catalog.byKey[Strings.dataKey("goal", "Catch", "title") .. ".one"]
		expect(Localize.format(catch.source, { count = 1 })).toBe("Catch 1 slime")
	end)

	it("leaves no <n> or <s> in any data source", function()
		local bad = {}
		for _, entry in catalog.entries do
			if
				string.sub(entry.key, 1, 5) == "data."
				and (string.find(entry.source, "<n>", 1, true) or string.find(entry.source, "<s>", 1, true))
			then
				table.insert(bad, entry.key)
			end
		end
		expect(table.concat(bad, ", ")).toBe("")
	end)

	it("keys every shop item and settings row", function()
		local list = {}
		for id, shop in Shops.SHOPS do
			table.insert(list, { "shops", id, "name", shop.name })
			for _, item in shop.items do
				table.insert(list, { "shopItem", item.id, "name", item.name })
				table.insert(list, { "shopItem", item.id, "text", item.text })
			end
		end
		for _, tab in PlayerSettings.TABS do
			table.insert(list, { "playerSettings", tab.key, "label", tab.label })
			for _, entry in tab.entries do
				table.insert(list, { "playerSettings", entry.id, "name", entry.name })
				for i, label in entry.labels or {} do
					table.insert(list, { "playerSettings", entry.id, `labels_{i}`, label })
				end
			end
		end
		expect(mismatches(list)).toBe("")
	end)

	it("sends daily quest titles and boost rewards as messages that read as before in English", function()
		local function view(id: string, target: number): any
			local data = PlayerData.new()
			data.quests = { day = Quests.day(0), slots = { { id = id, target = target, base = 0, claimed = false } } }
			return Quests.view(data, 0).quests[1]
		end
		local english = function(v: any): string
			return Localize.english(catalog, v)
		end
		expect(english(view("Lock", 1).title)).toBe("Lock your base 1 time")
		expect(english(view("Catch", 5).title)).toBe("Catch 5 slimes")
		expect(english(view("Earn", 20000).title)).toBe("Earn $20K today")
		expect(english(view("Merge", 2).reward)).toBe("2x income for 5m")
		expect(english(view("Catch", 5).reward)).toBe("+$400")
	end)

	it("does not key slime species names", function()
		expect(catalog.byKey["data.slime.bumble.name"] == nil).toBe(true)
	end)
end)
