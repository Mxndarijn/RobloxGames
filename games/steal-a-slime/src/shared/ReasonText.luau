--!strict
--[[
	ReasonText (pure): refusal reasons as Localize messages, so a client shows them in the player's language.

	Systems refuse with short English reasons ("not enough cash", "need $80"); server code and specs compare
	them as they are. Where a reason is shown it becomes a Localize message, drawn with ui/Text.text: the server
	converts what leaves it (server/ReasonText: the Request result, a ShopEvent Denied), and client code that
	computes a reason itself (VatState.checkLoad in Move mode, say) converts it with ReasonText.message.

	  ReasonText.message("need $80")   --> Localize.msg("world.reason.need_cash", { price = "$80" })
	  ReasonText.result(res)           --> a copy of `res` whose message is that message; `reason` keeps the
	                                         English (a stable value for client logic such as a retry on "too fast")

	The reasons are the catalog's "world.reason.*" entries (Strings/World): a reason matches an entry's English
	exactly, or its pattern with each `{param}` standing for any text. A param named in DATA_PARAMS is a data
	name (a rarity, a shop) and is sent as that name's data message, so it is translated too. A reason with no
	entry stays the English string.
]]

local Lib = if script then (game:GetService("ReplicatedStorage") :: any).Lib else nil
local Localize = if Lib then require(Lib.locale.Localize) else require("../../../../shared/luau/src/locale/Localize")
local Strings = if script then require(script.Parent.Strings) else require("./Strings")
local Shops = if script then require(script.Parent.Shops) else require("./Shops")
local Config = if script then require(script.Parent.Config) else require("./Config")

local ReasonText = {}

ReasonText.PREFIX = "world.reason."

-- Params that carry a data name: the name's English -> its data key (nil = no key, the name stays as it is).
local function rarityKey(name: string): string?
	return Strings.dataKey("rarity", name, "name")
end
local function shopKey(name: string): string?
	for _, id in Shops.ORDER do
		local shop = Shops.shop(id)
		if shop and shop.name == name then
			return Strings.dataKey("shops", id, "name")
		end
	end
	return nil
end
local function rankKey(title: string): string?
	return Strings.dataKey("rebirthTier", title, "title")
end
local function eggKey(name: string): string?
	for _, kind in Config.MYSTERY_EGG.KINDS do
		if kind.name == name then
			return Strings.dataKey("eggKind", kind.id, "name")
		end
	end
	return nil
end
ReasonText.DATA_PARAMS = table.freeze({
	rarity = rarityKey, -- a Config.RARITIES name
	shop = shopKey, -- a Shops name
	rank = rankKey, -- a Config.REBIRTH_TIERS title
	kind = eggKey, -- a Mystery Egg kind's name
} :: { [string]: (string) -> string? })

type Rule = { key: string, pattern: string, params: { string }, length: number }

local exact: { [string]: string } = {}
local rules: { Rule } = {}

-- `source` as an anchored Lua pattern: magic characters escaped, each `{param}` a capture.
local function toPattern(source: string): (string, { string })
	local params: { string } = {}
	local out = { "^" }
	local i = 1
	while i <= #source do
		local s, e, name = string.find(source, "{([%a_][%w_]*)}", i)
		local stop = if s then s - 1 else #source
		local literal = string.sub(source, i, stop)
		table.insert(out, (string.gsub(literal, "[%^%$%(%)%%%.%[%]%*%+%-%?]", "%%%0")))
		if not s then
			break
		end
		table.insert(out, "(.+)")
		table.insert(params, name :: string)
		i = (e :: number) + 1
	end
	table.insert(out, "$")
	return table.concat(out), params
end

for _, entry in Strings.catalog.entries do
	if string.sub(entry.key, 1, #ReasonText.PREFIX) == ReasonText.PREFIX then
		if #entry.params == 0 then
			exact[entry.source] = entry.key
		else
			local pattern, params = toPattern(entry.source)
			table.insert(rules, { key = entry.key, pattern = pattern, params = params, length = #entry.source })
		end
	end
end
-- The longest source first, so a specific pattern wins over a looser one.
table.sort(rules, function(a: Rule, b: Rule): boolean
	if a.length ~= b.length then
		return a.length > b.length
	end
	return a.key < b.key
end)

local function arg(name: string, value: string): any
	local keyOf = ReasonText.DATA_PARAMS[name]
	local key = if keyOf then keyOf(value) else nil
	if key and Localize.has(Strings.catalog, key) then
		return Localize.msg(key)
	end
	return value
end

-- The message for reason `text`, or `text` itself when no reason entry matches (a message passes through).
function ReasonText.message(text: any): any
	if type(text) ~= "string" or text == "" then
		return text
	end
	local key = exact[text]
	if key then
		return Localize.msg(key)
	end
	for _, rule in rules do
		local captures = { string.match(text, rule.pattern) }
		if #captures == #rule.params and #captures > 0 then
			local args = {}
			for i, name in rule.params do
				args[name] = arg(name, captures[i])
			end
			return Localize.msg(rule.key, args)
		end
	end
	return text
end

-- `res` ready for the client: a copy with a refusal's message as a Localize message and `reason` = the English.
-- A result without a string message comes back as it is.
function ReasonText.result(res: any): any
	if type(res) ~= "table" or type(res.message) ~= "string" then
		return res
	end
	local message = ReasonText.message(res.message)
	if message == res.message then
		return res
	end
	local out = table.clone(res)
	out.reason = res.message
	out.message = message
	return out
end

return table.freeze(ReasonText)
