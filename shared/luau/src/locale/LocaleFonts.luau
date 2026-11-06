--!strict
--[[
	LocaleFonts: which writing system a Roblox locale id uses, so a game can swap a display font that
	lacks those glyphs for one that has them. Pure.

	Many cartoon display fonts (Fredoka One, Lilita One, Luckiest Guy) only draw Latin letters; Roblox then
	draws missing glyphs in its fallback font, mixed into the same word. A game lists a font per script it
	needs to change and keeps its own font everywhere else:

	  LocaleFonts.pick("ru-ru", { cyrillic = NunitoHeavy }, FredokaOne) --> NunitoHeavy
	  LocaleFonts.pick("es-es", { cyrillic = NunitoHeavy }, FredokaOne) --> FredokaOne
]]

local LocaleFonts = {}

export type Script =
	"latin"
	| "latinExt"
	| "vietnamese"
	| "cyrillic"
	| "greek"
	| "japanese"
	| "korean"
	| "chinese"
	| "thai"
	| "arabic"
	| "hebrew"
	| "devanagari"

-- "latin": the Western European letters (Latin-1) most display fonts have. "latinExt": Latin letters beyond
-- it (Turkish ş ğ İ, Polish ż ł ą, Czech ř, ...), which many display fonts lack.
local BY_LANGUAGE: { [string]: Script } = {
	tr = "latinExt",
	pl = "latinExt",
	cs = "latinExt",
	sk = "latinExt",
	hu = "latinExt",
	ro = "latinExt",
	hr = "latinExt",
	sl = "latinExt",
	lt = "latinExt",
	lv = "latinExt",
	et = "latinExt",
	az = "latinExt",
	ru = "cyrillic",
	uk = "cyrillic",
	bg = "cyrillic",
	be = "cyrillic",
	kk = "cyrillic",
	sr = "cyrillic",
	mk = "cyrillic",
	el = "greek",
	ja = "japanese",
	ko = "korean",
	zh = "chinese",
	th = "thai",
	ar = "arabic",
	fa = "arabic",
	he = "hebrew",
	hi = "devanagari",
	vi = "vietnamese",
}

-- The language part of a locale id: "pt-br" -> "pt", "zh_CN" -> "zh".
function LocaleFonts.language(localeId: string): string
	return string.lower(string.match(localeId or "", "^(%a+)") or "")
end

function LocaleFonts.script(localeId: string): Script
	return BY_LANGUAGE[LocaleFonts.language(localeId)] or "latin"
end

-- Whether the locale's script is written without spaces between words (line breaks fall anywhere).
function LocaleFonts.noSpaces(localeId: string): boolean
	local s = LocaleFonts.script(localeId)
	return s == "japanese" or s == "chinese" or s == "thai"
end

-- `fonts[script]` for the locale's script when the game gave one, else `default`.
function LocaleFonts.pick<T>(localeId: string, fonts: { [string]: T }, default: T): T
	local font = fonts[LocaleFonts.script(localeId)]
	if font ~= nil then
		return font
	end
	return default
end

return table.freeze(LocaleFonts)
