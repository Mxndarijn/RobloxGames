--!strict
--[[
	SettingsSchema: a list of player settings (toggles, sliders, choices) and the rules that keep their
	values clean. Pure: it never touches Roblox, so the server cleans saved and sent values with it and the
	client builds its menu from the same list.

		local schema = SettingsSchema.new({
			{ id = "muted", kind = "toggle", default = false },
			{ id = "music", kind = "slider", default = 0.5, min = 0, max = 1, step = 0.05 },
			{ id = "quality", kind = "choice", default = "full", choices = { "low", "full" } },
		})
		local values = schema:clean(saved)                     -- every id, junk -> default
		local changes = schema:parse(sentByClient)             -- only known ids with valid values, or nil
		local nextValues, changed = schema:apply(values, changes)

	Values are a plain `{ [id]: boolean | number | string }`. A slider value is clamped to min..max and
	snapped to its step; a choice must be one of its choices; a toggle must be a boolean. Anything else
	falls back to the default (`clean`) or is refused (`parse`).
]]

export type Kind = "toggle" | "slider" | "choice"
export type Value = boolean | number | string
export type Values = { [string]: Value }

export type Def = {
	id: string,
	kind: Kind,
	default: Value,
	min: number?, -- slider only
	max: number?, -- slider only
	step: number?, -- slider only; values snap to min + k * step
	choices: { string }?, -- choice only
}

export type Schema = {
	defs: { Def },
	byId: { [string]: Def },
	defaults: (self: Schema) -> Values,
	value: (self: Schema, id: string, raw: any) -> Value?,
	clean: (self: Schema, raw: any) -> Values,
	parse: (self: Schema, raw: any) -> Values?,
	apply: (self: Schema, current: Values, changes: Values) -> (Values, { string }),
	equal: (self: Schema, a: Values, b: Values) -> boolean,
}

local SettingsSchema = {}
SettingsSchema.__index = SettingsSchema

-- Longest id accepted from untrusted input (ids are short words).
SettingsSchema.MAX_ID_LENGTH = 32
-- Longest choice string accepted from untrusted input.
SettingsSchema.MAX_CHOICE_LENGTH = 32

local function finite(n: any): boolean
	return type(n) == "number" and n == n and math.abs(n) ~= math.huge
end

-- Snaps a finite number to the slider: clamp, then the nearest step, rounded to 1e-6 so 0.05 steps stay exact.
local function snap(def: Def, n: number): number
	local lo, hi = def.min :: number, def.max :: number
	local v = math.clamp(n, lo, hi)
	local step = def.step
	if step and step > 0 then
		v = lo + math.floor((v - lo) / step + 0.5) * step
		v = math.min(v, hi)
	end
	return math.floor(v * 1e6 + 0.5) / 1e6
end

local function has(list: { string }, s: string): boolean
	for _, c in list do
		if c == s then
			return true
		end
	end
	return false
end

-- The clean value of `raw` for `def`, or nil when `raw` is not a valid value of that setting.
local function valid(def: Def, raw: any): Value?
	if def.kind == "toggle" then
		return if type(raw) == "boolean" then raw else nil
	elseif def.kind == "slider" then
		return if finite(raw) then snap(def, raw) else nil
	else
		if type(raw) ~= "string" or #raw > SettingsSchema.MAX_CHOICE_LENGTH then
			return nil
		end
		return if has(def.choices :: { string }, raw) then raw else nil
	end
end

local function check(def: any, index: number)
	local where = `SettingsSchema.new: setting {index}`
	if type(def) ~= "table" or type(def.id) ~= "string" or #def.id == 0 then
		error(`{where} needs a string id`, 3)
	end
	if #def.id > SettingsSchema.MAX_ID_LENGTH then
		error(`{where} ({def.id}): id is longer than {SettingsSchema.MAX_ID_LENGTH}`, 3)
	end
	if def.kind == "slider" then
		if not finite(def.min) or not finite(def.max) or def.min > def.max then
			error(`{where} ({def.id}): a slider needs min <= max`, 3)
		end
		if def.step ~= nil and (not finite(def.step) or def.step <= 0) then
			error(`{where} ({def.id}): step must be a positive number`, 3)
		end
	elseif def.kind == "choice" then
		if type(def.choices) ~= "table" or #def.choices == 0 then
			error(`{where} ({def.id}): a choice needs choices`, 3)
		end
	elseif def.kind ~= "toggle" then
		error(`{where} ({def.id}): kind must be toggle, slider or choice`, 3)
	end
	if valid(def, def.default) == nil then
		error(`{where} ({def.id}): default is not a valid value`, 3)
	end
end

function SettingsSchema.new(defs: { Def }): Schema
	if type(defs) ~= "table" then
		error("SettingsSchema.new: defs must be a list", 2)
	end
	local list: { Def } = {}
	local byId: { [string]: Def } = {}
	for i, def in defs do
		check(def, i)
		if byId[def.id] then
			error(`SettingsSchema.new: duplicate id {def.id}`, 2)
		end
		local copy: Def = table.clone(def)
		if copy.choices then
			copy.choices = table.freeze(table.clone(copy.choices :: { string }))
		end
		if copy.kind == "slider" then
			copy.default = snap(copy, copy.default :: number)
		end
		table.freeze(copy)
		table.insert(list, copy)
		byId[copy.id] = copy
	end
	local self = setmetatable({ defs = table.freeze(list), byId = table.freeze(byId) }, SettingsSchema)
	return (self :: any) :: Schema
end

-- Every setting at its default.
function SettingsSchema.defaults(self: Schema): Values
	local out: Values = {}
	for _, def in self.defs do
		out[def.id] = def.default
	end
	return out
end

-- The clean value of one setting from an untrusted value: nil for an unknown id, the default for junk.
function SettingsSchema.value(self: Schema, id: string, raw: any): Value?
	local def = self.byId[id]
	if def == nil then
		return nil
	end
	local v = valid(def, raw)
	return if v == nil then def.default else v
end

-- Untrusted table (a save, a snapshot) -> every setting, each bad or missing value at its default.
-- Unknown keys are dropped.
function SettingsSchema.clean(self: Schema, raw: any): Values
	local out = self:defaults()
	if type(raw) ~= "table" then
		return out
	end
	for _, def in self.defs do
		local v = valid(def, raw[def.id])
		if v ~= nil then
			out[def.id] = v
		end
	end
	return out
end

-- Untrusted changes (sent by a client) -> the valid ones, or nil when `raw` is not a table or holds
-- anything else: an unknown id, a wrong type, a bad value, or more entries than there are settings.
function SettingsSchema.parse(self: Schema, raw: any): Values?
	if type(raw) ~= "table" then
		return nil
	end
	local out: Values = {}
	local count = 0
	for k, v in raw do
		count += 1
		if count > #self.defs or type(k) ~= "string" then
			return nil
		end
		local def = self.byId[k]
		if def == nil then
			return nil
		end
		local clean = valid(def, v)
		if clean == nil then
			return nil
		end
		out[k] = clean
	end
	return out
end

-- `current` with `changes` laid over it (both cleaned), plus the ids whose value changed, in schema order.
function SettingsSchema.apply(self: Schema, current: Values, changes: Values): (Values, { string })
	local out = self:clean(current)
	local changed: { string } = {}
	for _, def in self.defs do
		local v = valid(def, changes[def.id])
		if v ~= nil and v ~= out[def.id] then
			out[def.id] = v
			table.insert(changed, def.id)
		end
	end
	return out, changed
end

-- True when both hold the same clean value for every setting.
function SettingsSchema.equal(self: Schema, a: Values, b: Values): boolean
	local ca, cb = self:clean(a), self:clean(b)
	for _, def in self.defs do
		if ca[def.id] ~= cb[def.id] then
			return false
		end
	end
	return true
end

return table.freeze(SettingsSchema)
