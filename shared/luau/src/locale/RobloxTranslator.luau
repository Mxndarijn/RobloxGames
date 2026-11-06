--!strict
--[[
	RobloxTranslator (adapter, client): looks catalog entries up in Roblox's Translator for the local
	player's language, so Localize.text gets translated patterns.

	  local tr = RobloxTranslator.new(catalog, { localization = LocalizationService, player = Players.LocalPlayer })
	  label.Text = tr.t("shop.buy", { price = "$1.2K" })

	Lookup order for an entry, cached per key:
	  1. Translator:FormatByKey(key) with each parameter passed as "{name}", so the translated *pattern*
	     comes back (keyed entries: the uploaded catalog CSV in the cloud table, or a LocalizationTable).
	  2. Translator:Translate(context, source): the source-text match (entries Roblox captured itself).
	  3. nil: the English source.
	English locales skip the lookup. `locale = "pseudo"` gives Localize.pseudo of every source (Studio and
	layout checks). The Translator is fetched with GetTranslatorForPlayerAsync in its own thread; until it
	arrives (at most `timeout` seconds of waiting in `new`, default 8), the non-yielding GetTranslatorForPlayer
	is used. A forced locale (Studio) starts with the place's own LocalizationTables, since the cloud fetch can
	take 10 s or more there.
]]

local Localize = if script then require(script.Parent.Localize) else require("./Localize")

local RobloxTranslator = {}

export type Deps = {
	localization: any, -- LocalizationService
	player: any?, -- the local Player; nil with `locale`
	locale: string?, -- force a locale id, or "pseudo"
	context: any?, -- Instance passed to Translator:Translate (default: game)
	timeout: number?, -- seconds `new` waits for the async Translator (default 8)
	spawn: ((fn: () -> ()) -> ())?,
	wait: ((seconds: number) -> ())?,
	warn: ((...any) -> ())?,
}

export type Translator = {
	locale: string,
	catalog: Localize.Catalog,
	lookup: Localize.Lookup,
	text: (value: Localize.Text) -> string,
	t: (key: string, args: Localize.Args?) -> string,
}

local function placeholders(entry: Localize.Entry): { [string]: string }
	local out = {}
	for _, name in entry.params do
		out[name] = `\{{name}\}`
	end
	return out
end

function RobloxTranslator.new(catalog: Localize.Catalog, deps: Deps): Translator
	local spawn = deps.spawn or task.spawn
	local wait = deps.wait or task.wait
	local warnFn = deps.warn or warn
	local context = deps.context or (if game then game else nil)
	local roblox: any = nil
	local cache: { [string]: string | false } = {}
	local self = { catalog = catalog, locale = deps.locale or "en-us" } :: Translator

	local function use(translator: any)
		if translator then
			roblox = translator
			self.locale = deps.locale or translator.LocaleId or self.locale
			table.clear(cache)
		end
	end

	local settled = false -- the async fetch returned (with a translator or an error)
	if deps.locale ~= "pseudo" and (deps.locale or deps.player) then
		if deps.locale then
			-- Until the cloud translator arrives (in Studio it can take 10 s or never come), the tables in the
			-- place answer: one LocalizationTable translator each, asked in order.
			local tables = {}
			local children = if deps.localization.GetChildren then deps.localization:GetChildren() else {}
			for _, child in children do
				local okTable, tr = pcall(function()
					return if child:IsA("LocalizationTable") then child:GetTranslator(deps.locale) else nil
				end)
				if okTable and tr then
					table.insert(tables, tr)
				end
			end
			if #tables > 0 then
				local interim = {}
				function interim.FormatByKey(_: any, key: string, args: any): string
					for _, tr in tables do
						local ok, text = pcall(tr.FormatByKey, tr, key, args)
						-- A table without this language gives the English back: ask the next one.
						local entry = catalog.byKey[key]
						if
							ok
							and type(text) == "string"
							and (entry == nil or text ~= Localize.format(entry.source, args))
						then
							return text
						end
					end
					error("key not found")
				end
				function interim.Translate(_: any, ctx: any, text: string): string
					for _, tr in tables do
						local ok, out = pcall(tr.Translate, tr, ctx, text)
						if ok and type(out) == "string" and out ~= text then
							return out
						end
					end
					return text
				end
				roblox = interim
			end
			spawn(function()
				local ok, tr = pcall(deps.localization.GetTranslatorForLocaleAsync, deps.localization, deps.locale)
				if ok then
					use(tr)
				else
					warnFn("[RobloxTranslator] no translator for", deps.locale, tr)
				end
				settled = true
			end)
		elseif deps.player then
			local ok, tr = pcall(deps.localization.GetTranslatorForPlayer, deps.localization, deps.player)
			if ok then
				use(tr)
			end
			spawn(function()
				local okAsync, trAsync =
					pcall(deps.localization.GetTranslatorForPlayerAsync, deps.localization, deps.player)
				if okAsync then
					use(trAsync)
				else
					warnFn("[RobloxTranslator] cloud translations not loaded:", trAsync)
				end
				settled = true
			end)
		end
		-- Wait a short while for the async translator so the first screen is already translated. Not when the
		-- fetch failed, when the player plays in English (nothing is looked up), or when the place's own tables
		-- already answer a forced locale.
		local english = string.sub(string.lower(self.locale), 1, 2) == "en"
		local waited, limit = 0, deps.timeout or 8
		local start = roblox
		while
			roblox == start
			and not settled
			and waited < limit
			and not (english and start ~= nil)
			and not (deps.locale and start ~= nil)
		do
			wait(0.1)
			waited += 0.1
		end
	end

	local function find(entry: Localize.Entry): string?
		if self.locale == "pseudo" then
			return Localize.pseudo(entry.source)
		end
		if roblox == nil or string.sub(string.lower(self.locale), 1, 2) == "en" then
			return nil
		end
		local ok, byKey = pcall(roblox.FormatByKey, roblox, entry.key, placeholders(entry))
		if ok and type(byKey) == "string" and byKey ~= entry.source then
			return byKey
		end
		local okText, bySource = pcall(roblox.Translate, roblox, context, entry.source)
		if okText and type(bySource) == "string" and bySource ~= entry.source then
			return bySource
		end
		return nil
	end

	local function lookup(entry: Localize.Entry): string?
		local hit = cache[entry.key]
		if hit == nil then
			hit = find(entry) or false
			cache[entry.key] = hit
		end
		return if hit then hit else nil
	end

	self.lookup = lookup
	function self.text(value: Localize.Text): string
		return Localize.text(catalog, lookup, value)
	end
	function self.t(key: string, args: Localize.Args?): string
		return Localize.text(catalog, lookup, Localize.msg(key, args))
	end
	return self
end

-- A translator that only gives English (servers, Lune, tests).
function RobloxTranslator.english(catalog: Localize.Catalog): Translator
	local self = {} :: any
	self.locale = "en-us"
	self.catalog = catalog
	self.lookup = function()
		return nil
	end
	function self.text(value: Localize.Text): string
		return Localize.text(catalog, nil, value)
	end
	function self.t(key: string, args: Localize.Args?): string
		return Localize.text(catalog, nil, Localize.msg(key, args))
	end
	return self :: Translator
end

-- A translator for the pseudo-language (layout gates, Studio checks).
function RobloxTranslator.pseudo(catalog: Localize.Catalog): Translator
	local self = RobloxTranslator.english(catalog) :: any
	self.locale = "pseudo"
	self.lookup = function(entry: Localize.Entry): string?
		return Localize.pseudo(entry.source)
	end
	function self.text(value: Localize.Text): string
		return Localize.text(catalog, self.lookup, value)
	end
	function self.t(key: string, args: Localize.Args?): string
		return Localize.text(catalog, self.lookup, Localize.msg(key, args))
	end
	return self :: Translator
end

return table.freeze(RobloxTranslator)
