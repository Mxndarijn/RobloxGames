--!strict
--[[
	Text: the player's language for every string the UI shows (shared Strings catalog + shared/luau locale).

	  Text.t("shop.buy", { price = Format.formatCash(cost) })   -- a key with named parameters
	  Text.text(value)                                          -- a plain string or a Localize message
	                                                            -- (the server sends messages in results)
	  Text.count("hud.slimes", n)                               -- "<key>.one" when n == 1, else "<key>.other";
	                                                            -- {count} is filled with n
	  Text.data("upgrade", def.id, "name", def.name)            -- a Config name ("data.<kind>.<id>.<field>")
	  Text.slime(slime)                                         -- "Gold Rare Bubbles" in the player's order
	  Text.font(Theme.Font)                                     -- a display font that has the language's letters

	Translate when the text is drawn, never at require time: the translator is fetched once the client runs
	(init.client warms it while the loading screen is up), so a module constant would stay English.

	Which language: Roblox's player Translator on the client (RobloxTranslator). In Studio the
	LocalizationService attribute TestLocale forces one ("pseudo" for the long-text pseudo-language, or a
	locale id such as "ru-ru"). LocalizationService.RobloxLocaleId == "pseudo" does the same in the
	UiHarness. Servers and plain Lune get English.
]]

local Lib = if script then (game:GetService("ReplicatedStorage") :: any):WaitForChild("Lib") else nil
local Shared = if script then (game:GetService("ReplicatedStorage") :: any):WaitForChild("Shared") else nil
local Localize = if Lib then require(Lib.locale.Localize) else require("../../../../shared/luau/src/locale/Localize")
local LocaleFonts = if Lib
	then require(Lib.locale.LocaleFonts)
	else require("../../../../shared/luau/src/locale/LocaleFonts")
local RobloxTranslator = if Lib
	then require(Lib.locale.RobloxTranslator)
	else require("../../../../shared/luau/src/locale/RobloxTranslator")
local Strings = if Shared then require(Shared.Strings) else require("../shared/Strings")
local EggKind = if Shared then require(Shared.EggKind) else require("../shared/EggKind")
local Genome = if Shared then require(Shared.Genome) else require("../shared/Genome")

local Text = {}

Text.catalog = Strings.catalog

-- Display fonts per writing system, for a locale whose letters Fredoka One does not draw. Nil = keep the
-- game's font (Roblox draws CJK, Thai and Korean in its own fallback font either way).
Text.FONTS = table.freeze({
	cyrillic = Enum.Font.Nunito,
	greek = Enum.Font.Nunito,
	vietnamese = Enum.Font.Nunito,
} :: { [string]: any })

type Translator = RobloxTranslator.Translator

local englishTranslator = RobloxTranslator.english(Strings.catalog)
local pseudo = RobloxTranslator.pseudo(Strings.catalog)
local current: Translator? = nil
local currentFor: string? = nil

local function services(): (any, any)
	if not script then
		return nil, nil
	end
	local ok, loc = pcall(function()
		return game:GetService("LocalizationService")
	end)
	local okRun, run = pcall(function()
		return game:GetService("RunService")
	end)
	return if ok then loc else nil, if okRun then run else nil
end

-- The forced locale: Studio's TestLocale attribute, or "pseudo" from the UiHarness. Nil = the player's own.
local function forced(): string?
	local loc, run = services()
	if loc == nil then
		return nil
	end
	local robloxLocale = (loc :: any).RobloxLocaleId
	if robloxLocale == "pseudo" then
		return "pseudo"
	end
	if run and run:IsStudio() then
		local test = loc:GetAttribute("TestLocale")
		if type(test) == "string" and test ~= "" then
			return test
		end
	end
	return nil
end

-- The translator for this client (made on first use; yields up to a few seconds while Roblox loads the
-- cloud translations).
function Text.translator(): Translator
	local force = forced()
	local want = force or "player"
	if current and currentFor == want then
		return current
	end
	local loc, run = services()
	local tr: Translator = englishTranslator
	if force == "pseudo" then
		tr = pseudo
	elseif loc and run and run.IsClient and run:IsClient() then
		local Players = game:GetService("Players")
		tr = RobloxTranslator.new(Strings.catalog, {
			localization = loc,
			player = if force then nil else Players.LocalPlayer,
			locale = force,
		})
	end
	current, currentFor = tr, want
	return tr
end

-- The locale id the UI is drawn in ("en-us", "pt-br", "pseudo").
function Text.locale(): string
	return Text.translator().locale
end

function Text.t(key: string, args: Localize.Args?): string
	return Text.translator().t(key, args)
end

function Text.text(value: Localize.Text): string
	return Text.translator().text(value)
end

-- A message value (Localize.msg), for text built in one place and drawn in another.
Text.msg = Localize.msg

-- "<key>.one" when n == 1, else "<key>.other", with {count} = n (and any other args).
function Text.count(key: string, n: number, args: Localize.Args?): string
	local filled: Localize.Args = if args then table.clone(args) else {}
	if filled.count == nil then
		filled.count = n
	end
	return Text.t(key .. (if n == 1 then ".one" else ".other"), filled)
end

-- A Config name or description in the player's language; `english` (the Config value) when the catalog
-- has no such key.
function Text.data(kind: string, id: any, field: string?, english: string?): string
	local key = Strings.dataKey(kind, id, field)
	if Localize.has(Strings.catalog, key) then
		return Text.t(key)
	end
	return english or key
end

-- The data key, for a message built now and drawn later.
Text.dataKey = Strings.dataKey

-- A slime's display name in the player's language (Genome.displayName, translated): shine and rarity words
-- translated in the language's word order, the species name (a proper noun) as it is. An egg shows its egg name.
function Text.slime(slime: any): string
	if type(slime) ~= "table" then
		return ""
	end
	local kind = EggKind.of(slime)
	if kind then
		return Text.t("common.egg_name", { kind = Text.data("eggKind", kind.id, "name", kind.name) })
	end
	local rarity = Text.data("rarity", Genome.rarity(slime.tier).name, "name", Genome.rarity(slime.tier).name)
	local name = tostring(slime.name or "")
	local shine = Genome.shine(slime)
	if shine then
		local shineName = Text.data("shine", shine.id, "name", tostring(slime.shine))
		return Text.t("common.slime_shine", { shine = shineName, rarity = rarity, name = name })
	end
	return Text.t("common.slime", { rarity = rarity, name = name })
end

-- The locale the fonts follow: the forced one, else the Roblox app's language. Never yields, so Widgets can
-- pick its Theme fonts at require time.
function Text.fontLocale(): string
	local force = forced()
	if force then
		return force
	end
	local loc = services()
	local id = if loc then (loc :: any).RobloxLocaleId else nil
	return if type(id) == "string" and id ~= "" then id else "en-us"
end

-- `default` (the game's display font), or the font Text.FONTS gives for the language's writing system.
function Text.font(default: any): any
	return LocaleFonts.pick(Text.fontLocale(), Text.FONTS, default)
end

return table.freeze(Text)
