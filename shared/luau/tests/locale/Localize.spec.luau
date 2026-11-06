--!strict
local LocaleFonts = require("../../src/locale/LocaleFonts")
local Localize = require("../../src/locale/Localize")
local RobloxTranslator = require("../../src/locale/RobloxTranslator")
local T = require("../../testing/TestRunner")
local describe, it, expect = T.describe, T.it, T.expect

local catalog = Localize.catalog({
	{
		["shop.buy"] = { source = "Buy {item} for {price}", example = { item = "Speed Coil", price = "$1.2K" } },
		["item.coil"] = "Speed Coil",
		["common.close"] = "Close",
	},
	{ ["steal.done"] = "You stole {slime}!" },
})

describe("Localize.catalog", function()
	it("sorts entries by key and finds them", function()
		expect(#catalog.entries).toBe(4)
		expect(catalog.entries[1].key).toBe("common.close")
		expect(Localize.has(catalog, "steal.done")).toBe(true)
		expect(catalog.byKey["shop.buy"].params[1]).toBe("item")
	end)

	it("refuses bad keys, repeats, empty sources and wrong examples", function()
		expect(pcall(Localize.catalog, { { ["bad key"] = "x" } })).toBe(false)
		expect(pcall(Localize.catalog, { { ["a.b"] = "x" }, { ["a.b"] = "y" } })).toBe(false)
		expect(pcall(Localize.catalog, { { ["a.b"] = "" } })).toBe(false)
		expect(pcall(Localize.catalog, { { ["a.b"] = { source = "{x}", example = { y = 1 } } } })).toBe(false)
	end)

	it("checks key shape", function()
		expect(Localize.validKey("hud.cash_rate")).toBe(true)
		expect(Localize.validKey("hud..x")).toBe(false)
		expect(Localize.validKey("1hud")).toBe(false)
	end)
end)

describe("Localize.format and text", function()
	it("fills named parameters and keeps unknown ones", function()
		expect(Localize.format("{a} and {b}", { a = "x", b = 2 })).toBe("x and 2")
		expect(Localize.format("{a} and {b}", { a = "x" })).toBe("x and {b}")
		expect(Localize.format("100% {a}", { a = "%1" })).toBe("100% %1")
	end)

	it("gives English for a message and resolves message args first", function()
		local m = Localize.msg("shop.buy", { item = Localize.msg("item.coil"), price = "$5" })
		expect(Localize.english(catalog, m)).toBe("Buy Speed Coil for $5")
		expect(Localize.text(catalog, nil, "plain")).toBe("plain")
		expect(Localize.text(catalog, nil, Localize.msg("no.such"))).toBe("no.such")
	end)

	it("uses the looked-up pattern for every level", function()
		local es: { [string]: string } = {
			["shop.buy"] = "Comprar {item} por {price}",
			["item.coil"] = "Bobina de velocidad",
		}
		local lookup = function(entry: Localize.Entry): string?
			return es[entry.key]
		end
		local m = Localize.msg("shop.buy", { item = Localize.msg("item.coil"), price = "$5" })
		expect(Localize.text(catalog, lookup, m)).toBe("Comprar Bobina de velocidad por $5")
		expect(Localize.text(catalog, lookup, Localize.msg("common.close"))).toBe("Close")
	end)

	it("falls back to the source when a translation lost or added a parameter", function()
		expect(Localize.safePattern("Buy {item}", "Comprar")).toBe("Buy {item}")
		expect(Localize.safePattern("Buy {item}", "Comprar {item} {x}")).toBe("Buy {item}")
		expect(Localize.safePattern("Buy {item}", "{item} kaufen")).toBe("{item} kaufen")
		expect(Localize.safePattern("Buy", nil)).toBe("Buy")
	end)
end)

describe("Localize.pseudo", function()
	it("accents letters, grows about 40% and wraps in brackets", function()
		local p = Localize.pseudo("Close")
		expect(string.sub(p, 1, 1)).toBe("[")
		expect(string.sub(p, -1)).toBe("]")
		expect(utf8.len(p) :: number >= math.floor(5 * 1.4) + 2).toBe(true)
		expect(string.find(p, "Ç", 1, true) ~= nil).toBe(true)
	end)

	it("keeps parameters and rich-text tags", function()
		local p = Localize.pseudo('Buy {item} <font color="#fff">now</font>')
		expect(string.find(p, "{item}", 1, true) ~= nil).toBe(true)
		expect(string.find(p, '<font color="#fff">', 1, true) ~= nil).toBe(true)
		expect(string.find(p, "</font>", 1, true) ~= nil).toBe(true)
	end)

	it("spots strings that skipped the catalog", function()
		expect(Localize.untranslated(Localize.pseudo("Close"))).toBe(false)
		expect(Localize.untranslated("$1.2K")).toBe(false)
		expect(Localize.untranslated("x3 ⭐")).toBe(false)
		expect(Localize.untranslated("Close")).toBe(true)
		expect(Localize.untranslated(Localize.pseudo("Buy {item}") .. " Lv 3")).toBe(true)
	end)
end)

describe("Localize.csv", function()
	it("writes a LocalizationTable CSV with quoting and examples", function()
		local c = Localize.catalog({ { ["a.b"] = 'Say "hi", {name}', ["a.a"] = "Line\ntwo" } })
		local csv = Localize.csv(c)
		local lines = string.split(csv, "\n")
		expect(lines[1]).toBe("Key,Source,Context,Example")
		expect(lines[2]).toBe('a.a,"Line')
		expect(string.find(csv, 'a.b,"Say ""hi"", {name}",,', 1, true) ~= nil).toBe(true)
		local dup = Localize.csv(Localize.catalog({ { ["a.x"] = "Close", ["b.x"] = "Close", ["c.x"] = "Open" } }))
		expect(string.find(dup, "a.x,Close,a.x,", 1, true) ~= nil).toBe(true)
		expect(string.find(dup, "b.x,Close,b.x,", 1, true) ~= nil).toBe(true)
		expect(string.find(dup, "c.x,Open,,", 1, true) ~= nil).toBe(true)
		local ex = Localize.csv(catalog)
		expect(string.find(ex, "shop.buy,Buy {item} for {price},,Buy Speed Coil for $1.2K", 1, true) ~= nil).toBe(true)
	end)
end)

describe("Localize manual translations", function()
	it("adds one column per locale and leaves other cells empty", function()
		local csv = Localize.csv(catalog, { ["common.close"] = { de = "Zu", es = "Cerrar" } })
		local lines = string.split(csv, "\n")
		expect(lines[1]).toBe("Key,Source,Context,Example,de,es")
		expect(lines[2]).toBe("common.close,Close,,,Zu,Cerrar")
		expect(lines[3]).toBe("item.coil,Speed Coil,,,,")
	end)

	it("refuses unknown keys and lost or added parameters", function()
		local bad = Localize.checkManual(catalog, {
			["no.such"] = { de = "x" },
			["steal.done"] = { de = "Gestohlen!", es = "¡Robaste a {slime}!" },
		})
		expect(#bad).toBe(2)
		expect(pcall(Localize.csv, catalog, { ["no.such"] = { de = "x" } })).toBe(false)
	end)
end)

describe("LocaleFonts", function()
	it("maps locale ids to scripts", function()
		expect(LocaleFonts.script("ru-ru")).toBe("cyrillic")
		expect(LocaleFonts.script("pt-br")).toBe("latin")
		expect(LocaleFonts.script("tr-tr")).toBe("latinExt")
		expect(LocaleFonts.script("zh-cn")).toBe("chinese")
		expect(LocaleFonts.script("ja-jp")).toBe("japanese")
		expect(LocaleFonts.script("th-th")).toBe("thai")
		expect(LocaleFonts.script("")).toBe("latin")
		expect(LocaleFonts.noSpaces("ja-jp")).toBe(true)
		expect(LocaleFonts.noSpaces("de-de")).toBe(false)
	end)

	it("picks the game's font for a script, else the default", function()
		expect(LocaleFonts.pick("ru-ru", { cyrillic = "Nunito" }, "Fredoka")).toBe("Nunito")
		expect(LocaleFonts.pick("es-es", { cyrillic = "Nunito" }, "Fredoka")).toBe("Fredoka")
	end)
end)

-- A stand-in for Roblox's Translator: FormatByKey errors on unknown keys like the real one.
local function fakeTranslator(locale: string, byKey: { [string]: string }, bySource: { [string]: string })
	return {
		LocaleId = locale,
		FormatByKey = function(_self: any, key: string, args: { [string]: any }): string
			local pattern = byKey[key]
			if pattern == nil then
				error("key not found")
			end
			return Localize.format(pattern, args)
		end,
		Translate = function(_self: any, _context: any, text: string): string
			return bySource[text] or text
		end,
	}
end

local function service(tr: any)
	return {
		GetTranslatorForPlayer = function()
			return tr
		end,
		GetTranslatorForPlayerAsync = function()
			return tr
		end,
		GetTranslatorForLocaleAsync = function()
			return tr
		end,
	}
end

local syncDeps = {
	spawn = function(fn: () -> ())
		fn()
	end,
	wait = function() end,
	warn = function() end,
	context = {},
}

describe("RobloxTranslator", function()
	it("reads keyed patterns, then source matches, else English", function()
		local tr = fakeTranslator("es-es", { ["shop.buy"] = "Comprar {item} por {price}" }, { ["Close"] = "Cerrar" })
		local deps = table.clone(syncDeps) :: any
		deps.localization = service(tr)
		deps.player = {}
		local t = RobloxTranslator.new(catalog, deps)
		expect(t.locale).toBe("es-es")
		expect(t.t("shop.buy", { item = Localize.msg("item.coil"), price = "$5" })).toBe("Comprar Speed Coil por $5")
		expect(t.t("common.close")).toBe("Cerrar")
		expect(t.t("steal.done", { slime = "Bob" })).toBe("You stole Bob!")
	end)

	it("skips the lookup for English and gives pseudo when asked", function()
		local tr = fakeTranslator("en-us", { ["common.close"] = "Shut" }, {})
		local deps = table.clone(syncDeps) :: any
		deps.localization = service(tr)
		deps.player = {}
		expect(RobloxTranslator.new(catalog, deps).t("common.close")).toBe("Close")
		expect(RobloxTranslator.pseudo(catalog).t("common.close")).toBe(Localize.pseudo("Close"))
		expect(RobloxTranslator.english(catalog).t("steal.done", { slime = "Bob" })).toBe("You stole Bob!")
	end)

	it("answers a forced locale from the place's tables while the cloud fetch hangs", function()
		local english = fakeTranslator("ru-ru", { ["common.close"] = "Close" }, {})
		local russian = fakeTranslator("ru-ru", { ["common.close"] = "Закрыть" }, {})
		local function tableOf(tr: any)
			return {
				IsA = function(_self: any, class: string): boolean
					return class == "LocalizationTable"
				end,
				GetTranslator = function()
					return tr
				end,
			}
		end
		local deps = table.clone(syncDeps) :: any
		deps.spawn = function() end -- the async translator never arrives
		deps.locale = "ru-ru"
		deps.localization = {
			GetChildren = function()
				return { tableOf(english), tableOf(russian) }
			end,
		}
		local t = RobloxTranslator.new(catalog, deps)
		expect(t.t("common.close")).toBe("Закрыть")
		expect(t.t("steal.done", { slime = "Bob" })).toBe("You stole Bob!")
	end)

	it("keeps English when Roblox has no translator", function()
		local deps = table.clone(syncDeps) :: any
		deps.localization = {
			GetTranslatorForPlayer = function()
				error("no")
			end,
			GetTranslatorForPlayerAsync = function()
				error("no")
			end,
		}
		deps.player = {}
		expect(RobloxTranslator.new(catalog, deps).t("common.close")).toBe("Close")
	end)
end)
