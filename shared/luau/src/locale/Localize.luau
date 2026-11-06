--!strict
--[[
	Localize: pure text catalog for player-facing strings.

	Every string a player reads has a stable key and one English source pattern. Dynamic parts are named
	parameters in braces, so a translator (or Roblox automatic translation) gets the whole sentence:
	  "steal.done" = "You stole {slime}!"   not   "You stole " .. name .. "!"
	The `{name}` syntax is the same as Roblox LocalizationTable named parameters.

	* catalog(groups)          builds and checks a catalog from key → source tables.
	* msg(key, args)           a message value: a plain table that can cross a remote or sit in State.
	                           An arg can itself be a message ("{item} bought" with a translated item name).
	* text(catalog, lookup, v) the string for a message (or a plain string, returned as it is). `lookup`
	                           gives the translated pattern for an entry, or nil for the English source.
	                           A translation that lost or added a parameter falls back to the source.
	* format(pattern, args)    fills `{name}` parameters; unknown ones stay as written.
	* pseudo(text)             the long-text pseudo-language: accented letters, about 40% longer, wrapped in
	                           [ ]. Used by layout gates and Studio checks; parameters and rich-text tags stay.
	* untranslated(text)       true when a string has words outside pseudo brackets (a missed string).
	* csv(catalog)             the catalog as a Rojo LocalizationTable CSV (Key, Source, Context, Example).
]]

local Localize = {}

export type Args = { [string]: any }
export type Message = { key: string, args: Args? }
export type Text = string | Message
export type Def = string | { source: string, example: Args? }
export type Entry = { key: string, source: string, params: { string }, example: Args? }
export type Catalog = { entries: { Entry }, byKey: { [string]: Entry } }
export type Lookup = (entry: Entry) -> string?

local KEY_PATTERN = "^%a[%w_]*$" -- one dot-separated part of a key
local PARAM = "{([%a_][%w_]*)}"

-- Whether `key` is a valid catalog key: dot-separated parts of letters, digits and underscores.
function Localize.validKey(key: string): boolean
	if type(key) ~= "string" or key == "" then
		return false
	end
	for _, part in string.split(key, ".") do
		if not string.match(part, KEY_PATTERN) then
			return false
		end
	end
	return true
end

-- The parameter names in `pattern`, sorted, each once.
function Localize.params(pattern: string): { string }
	local seen: { [string]: boolean } = {}
	local out: { string } = {}
	for name in string.gmatch(pattern, PARAM) do
		if not seen[name] then
			seen[name] = true
			table.insert(out, name)
		end
	end
	table.sort(out)
	return out
end

local function sameParams(a: { string }, b: { string }): boolean
	if #a ~= #b then
		return false
	end
	for i, name in a do
		if b[i] ~= name then
			return false
		end
	end
	return true
end

-- Builds a catalog from one or more `{ [key] = def }` tables. Errors on a bad or repeated key, an empty
-- source, or an example that does not name exactly the source's parameters.
function Localize.catalog(groups: { { [string]: Def } }): Catalog
	local byKey: { [string]: Entry } = {}
	local entries: { Entry } = {}
	for _, group in groups do
		for key, def in group do
			assert(Localize.validKey(key), `Localize: bad key {key}`)
			assert(byKey[key] == nil, `Localize: key {key} is defined twice`)
			local source: string, example: Args? = "", nil
			if type(def) == "string" then
				source = def
			elseif type(def) == "table" then
				source, example = def.source, def.example
			end
			assert(type(source) == "string" and source ~= "", `Localize: key {key} has no source text`)
			local params = Localize.params(source)
			if example then
				local named = {}
				for name in example do
					table.insert(named, name)
				end
				table.sort(named)
				assert(sameParams(named, params), `Localize: example for {key} must name exactly its parameters`)
			end
			local entry: Entry =
				table.freeze({ key = key, source = source, params = table.freeze(params), example = example })
			byKey[key] = entry
			table.insert(entries, entry)
		end
	end
	table.sort(entries, function(a: Entry, b: Entry)
		return a.key < b.key
	end)
	return table.freeze({ entries = table.freeze(entries), byKey = table.freeze(byKey) })
end

function Localize.has(catalog: Catalog, key: string): boolean
	return catalog.byKey[key] ~= nil
end

function Localize.msg(key: string, args: Args?): Message
	return { key = key, args = args }
end

function Localize.isMessage(value: any): boolean
	return type(value) == "table" and type(value.key) == "string"
end

local function show(value: any): string
	if type(value) == "number" then
		if value == math.floor(value) and math.abs(value) < 1e15 then
			return string.format("%d", value)
		end
		return tostring(value)
	end
	return tostring(value)
end

-- Fills `{name}` parameters of `pattern` from `args`. A parameter with no arg stays as written.
function Localize.format(pattern: string, args: Args?): string
	if args == nil then
		return pattern
	end
	local values = args :: Args
	return (
		string.gsub(pattern, PARAM, function(name: string): string?
			local value = values[name]
			if value == nil then
				return nil
			end
			return show(value)
		end)
	)
end

-- `translated` when it has the same parameters as `source`, else `source`.
function Localize.safePattern(source: string, translated: string?): string
	if type(translated) ~= "string" or translated == "" then
		return source
	end
	if sameParams(Localize.params(source), Localize.params(translated)) then
		return translated
	end
	return source
end

-- The string for `value`: a plain string comes back as it is; a message is looked up, its message args
-- are resolved first, and its parameters filled. An unknown key comes back as the key, so it shows.
function Localize.text(catalog: Catalog, lookup: Lookup?, value: Text): string
	if type(value) == "string" then
		return value
	end
	if not Localize.isMessage(value) then
		return show(value)
	end
	local message = value :: Message
	local entry = catalog.byKey[message.key]
	if entry == nil then
		return message.key
	end
	local args: Args = {}
	for name, arg in message.args or {} do
		args[name] = if Localize.isMessage(arg) then Localize.text(catalog, lookup, arg) else arg
	end
	local pattern = entry.source
	if lookup then
		pattern = Localize.safePattern(entry.source, lookup(entry))
	end
	return Localize.format(pattern, args)
end

-- The English text for a message (no translation).
function Localize.english(catalog: Catalog, value: Text): string
	return Localize.text(catalog, nil, value)
end

-- Pseudo-language ------------------------------------------------------------------------------------

local ACCENT: { [string]: string } = {
	a = "á",
	e = "é",
	i = "í",
	o = "ó",
	u = "ú",
	y = "ý",
	c = "ç",
	n = "ñ",
	A = "Á",
	E = "É",
	I = "Í",
	O = "Ó",
	U = "Ú",
	Y = "Ý",
	C = "Ç",
	N = "Ñ",
}
local VOWELS = "aeiouyAEIOUY"

Localize.PSEUDO_GROWTH = 0.4 -- extra letters per word, as a share of its length

local function pseudoWord(word: string): string
	local out = string.gsub(word, "%a", function(ch: string): string
		return ACCENT[ch] or ch
	end)
	local extra = math.ceil(#word * Localize.PSEUDO_GROWTH)
	local vowel = string.match(word, `[{VOWELS}]`)
	local pad = if vowel then ACCENT[string.lower(vowel)] else string.sub(word, -1)
	return out .. string.rep(pad, extra)
end

-- `text` in the pseudo-language. `{params}` and `<rich text>` tags are kept as they are.
function Localize.pseudo(text: string): string
	local out = {}
	local i = 1
	while i <= #text do
		local ch = string.sub(text, i, i)
		local close = if ch == "{"
			then string.find(text, "}", i, true)
			elseif ch == "<" then string.find(text, ">", i, true)
			else nil
		if close then
			table.insert(out, string.sub(text, i, close))
			i = close + 1
		else
			local word = string.match(text, "^%a+", i)
			if word then
				table.insert(out, pseudoWord(word))
				i += #word
			else
				table.insert(out, ch)
				i += 1
			end
		end
	end
	return "[" .. table.concat(out) .. "]"
end

-- True when `text` still has a word (two ASCII letters in a row) outside pseudo brackets and rich-text
-- tags: on a pseudo-language screen, that is a string that did not go through the catalog.
function Localize.untranslated(text: string): boolean
	local rest = string.gsub(text, "%b<>", "")
	rest = string.gsub(rest, "%b[]", "")
	return string.find(rest, "%a%a") ~= nil
end

-- CSV ------------------------------------------------------------------------------------------------

local function csvField(value: string): string
	if string.find(value, '[,"\r\n]') then
		return '"' .. string.gsub(value, '"', '""') .. '"'
	end
	return value
end

-- The catalog as a LocalizationTable CSV in key order: Key, Source, Context, Example (the source filled with the
-- entry's example args). Roblox allows one entry per Source + Context, so an English text used under several
-- keys gets its key as Context; every other Context stays empty (Roblox uses it to match instance paths).
function Localize.csv(catalog: Catalog): string
	local uses: { [string]: number } = {}
	for _, entry in catalog.entries do
		uses[entry.source] = (uses[entry.source] or 0) + 1
	end
	local lines = { "Key,Source,Context,Example" }
	for _, entry in catalog.entries do
		local example = if entry.example then Localize.format(entry.source, entry.example) else ""
		local context = if uses[entry.source] > 1 then entry.key else ""
		table.insert(lines, `{csvField(entry.key)},{csvField(entry.source)},{csvField(context)},{csvField(example)}`)
	end
	return table.concat(lines, "\n") .. "\n"
end

return table.freeze(Localize)
