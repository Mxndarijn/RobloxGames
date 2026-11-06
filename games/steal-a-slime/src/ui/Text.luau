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
	  Text.displayFont()                                        -- the FontFace that replaces Fredoka One for
	                                                            -- this language (Widgets.create applies it)

	Translate when the text is drawn, never at require time: the translator is fetched once the client runs
	(init.client warms it while the loading screen is up), so a module constant would stay English.

	Which language: Roblox's player Translator on the client (RobloxTranslator). In Studio the
	LocalizationService attribute TestLocale forces one ("pseudo" for the long-text pseudo-language, or a
	locale id such as "ru-ru"). LocalizationService.RobloxLocaleId == "pseudo" does the same in the
	UiHarness. Servers and plain Lune get English.
]]

local Localize = if script
	then require(
		game:GetService("ReplicatedStorage"):WaitForChild("Lib"):WaitForChild("locale"):WaitForChild("Localize")
	)
	else require("../../../../shared/luau/src/locale/Localize")
local LocaleFonts = if script
	then require(
		game:GetService("ReplicatedStorage"):WaitForChild("Lib"):WaitForChild("locale"):WaitForChild("LocaleFonts")
	)
	else require("../../../../shared/luau/src/locale/LocaleFonts")
local RobloxTranslator = if script
	then require(
		game:GetService("ReplicatedStorage"):WaitForChild("Lib"):WaitForChild("locale"):WaitForChild("RobloxTranslator")
	)
	else require("../../../../shared/luau/src/locale/RobloxTranslator")
local Strings = if script
	then require(game:GetService("ReplicatedStorage"):WaitForChild("Shared"):WaitForChild("Strings"))
	else require("../shared/Strings")
local EggKind = if script
	then require(game:GetService("ReplicatedStorage"):WaitForChild("Shared"):WaitForChild("EggKind"))
	else require("../shared/EggKind")
local Genome = if script
	then require(game:GetService("ReplicatedStorage"):WaitForChild("Shared"):WaitForChild("Genome"))
	else require("../shared/Genome")

local Text = {}

Text.catalog = Strings.catalog

-- The display font (Fredoka One) draws only Western European letters; Roblox draws any other letter in a thin
-- fallback font mid-word. For those languages titles and buttons use Nunito Heavy (checked in Studio: it draws
-- Cyrillic and extended Latin itself, and Roblox's CJK, Hangul and Thai fallback matches its weight).
local NUNITO_HEAVY: any = if typeof(Font) == "table" or typeof(Font) == "userdata"
	then Font.new("rbxasset://fonts/families/Nunito.json", Enum.FontWeight.Heavy)
	else nil -- plain Lune: no fonts
Text.FONTS = table.freeze({
	latinExt = NUNITO_HEAVY,
	vietnamese = NUNITO_HEAVY,
	cyrillic = NUNITO_HEAVY,
	greek = NUNITO_HEAVY,
	japanese = NUNITO_HEAVY,
	korean = NUNITO_HEAVY,
	chinese = NUNITO_HEAVY,
	thai = NUNITO_HEAVY,
	arabic = NUNITO_HEAVY,
	hebrew = NUNITO_HEAVY,
	devanagari = NUNITO_HEAVY,
} :: { [string]: Font })

type Translator = RobloxTranslator.Translator

local englishTranslator = RobloxTranslator.english(Strings.catalog)
local pseudo = RobloxTranslator.pseudo(Strings.catalog)
local current: Translator? = nil
local currentFor: string? = nil
local building: string? = nil -- the translator being fetched right now
local waiting: { thread } = {} -- threads that asked while it was being fetched

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

-- LocalizationService.RobloxLocaleId, or nil where it can't be read (a bare DataModel under Lune).
local function robloxLocaleId(loc: any): string?
	local ok, id = pcall(function()
		return loc.RobloxLocaleId
	end)
	return if ok and type(id) == "string" and id ~= "" then id else nil
end

-- The forced locale: Studio's TestLocale attribute, or "pseudo" from the UiHarness. Nil = the player's own.
local function forced(): string?
	local loc, run = services()
	if loc == nil then
		return nil
	end
	local robloxLocale = robloxLocaleId(loc)
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
	-- Another thread is fetching it (the loading screen and the UI start together): sleep until that one is done.
	if building == want then
		table.insert(waiting, coroutine.running())
		coroutine.yield()
		if current and currentFor == want then
			return current
		end
	end
	local loc, run = services()
	local tr: Translator = englishTranslator
	if force == "pseudo" then
		tr = pseudo
	elseif loc and run and run.IsClient and run:IsClient() then
		local Players = game:GetService("Players")
		building = want
		local ok, made = pcall(RobloxTranslator.new, Strings.catalog, {
			localization = loc,
			player = if force then nil else Players.LocalPlayer,
			locale = force,
		})
		building = nil
		tr = if ok then made else englishTranslator
	end
	current, currentFor = tr, want
	local sleepers = waiting
	waiting = {}
	for _, thread in sleepers do
		task.spawn(thread)
	end
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
	local filled: { [string]: any } = if args then table.clone(args) else {}
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
	return (if loc then robloxLocaleId(loc) else nil) or "en-us"
end

-- The FontFace that replaces the display font (Fredoka One) for this language, or nil to keep it.
function Text.displayFont(): Font?
	return LocaleFonts.pick(Text.fontLocale(), Text.FONTS :: any, nil :: Font?)
end

return table.freeze(Text)
