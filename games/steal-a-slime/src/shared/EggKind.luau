--!strict
--[[
	EggKind (pure, contract/mystery-egg.md)

	Mystery Egg kinds (Config.MYSTERY_EGG.KINDS) and what a slime record that
	is still an egg shows: its name, its rarity tier, its incubation progress
	and the masked copy clients get (the slime inside stays hidden until the
	hatch). Depends on Config only, so Genome and Economy can use it.
]]

local Config = if script then require(script.Parent.Config) else require("./Config")

export type Egg = { kind: string, hatchAt: number? }
export type Drop = { tier: number, weight: number }
export type Kind = {
	id: string,
	name: string,
	tier: number,
	weight: number,
	hatchSeconds: number,
	price: number,
	sell: number,
	announce: boolean,
	drops: { Drop },
}

local EggKind = {}

local byId: { [string]: Kind } = {}
for _, kind in Config.MYSTERY_EGG.KINDS :: { Kind } do
	byId[kind.id] = kind
end

function EggKind.list(): { Kind }
	return Config.MYSTERY_EGG.KINDS :: { Kind }
end

function EggKind.get(id: any): Kind?
	return if type(id) == "string" then byId[id] else nil
end

-- The kind of a slime record that is still an egg, or nil for a hatched slime.
function EggKind.of(slime: { egg: Egg? }): Kind?
	local egg = slime.egg
	return if egg then EggKind.get(egg.kind) else nil
end

function EggKind.isEgg(slime: { egg: Egg? }): boolean
	return EggKind.of(slime) ~= nil
end

-- The rarity tier a record shows: an egg's kind tier (label, lifetime, carry slowdown), else the slime's own.
function EggKind.shownTier(slime: { egg: Egg?, tier: number }): number
	local kind = EggKind.of(slime)
	return if kind then kind.tier else slime.tier
end

-- "Golden Mystery Egg".
function EggKind.displayName(kind: Kind): string
	return `{kind.name} Mystery Egg`
end

-- 0..1 incubation progress at `now` (0 while not incubating yet).
function EggKind.progress(slime: { egg: Egg? }, now: number): number
	local kind = EggKind.of(slime)
	local hatchAt = slime.egg and slime.egg.hatchAt
	if not kind or not hatchAt then
		return 0
	end
	return math.clamp(1 - (hatchAt - now) / kind.hatchSeconds, 0, 1)
end

-- Ready to hatch: incubating and its time has come.
function EggKind.isReady(slime: { egg: Egg? }, now: number): boolean
	local hatchAt = slime.egg and slime.egg.hatchAt
	return EggKind.of(slime) ~= nil and hatchAt ~= nil and hatchAt <= now
end

-- Weighted index into `kinds` for one roll in [0, 1).
local function pick(weights: { number }, roll: number): number
	local total = 0
	for _, w in weights do
		total += w
	end
	local target = roll * total
	for i, w in weights do
		target -= w
		if target < 0 then
			return i
		end
	end
	return #weights
end

-- The kind for one roll in [0, 1).
function EggKind.rollKind(roll: number): Kind
	local kinds = EggKind.list()
	local weights = {}
	for i, kind in kinds do
		weights[i] = kind.weight
	end
	return kinds[pick(weights, roll)]
end

-- The tier of the slime inside for one roll in [0, 1).
function EggKind.rollTier(kind: Kind, roll: number): number
	local weights = {}
	for i, drop in kind.drops do
		weights[i] = drop.weight
	end
	return kind.drops[pick(weights, roll)].tier
end

-- Chance of each inner tier: { [tier] = probability }; sums to 1.
function EggKind.probabilities(kind: Kind): { [number]: number }
	local total = 0
	for _, drop in kind.drops do
		total += drop.weight
	end
	local out = {}
	for _, drop in kind.drops do
		out[drop.tier] = (out[drop.tier] or 0) + drop.weight / total
	end
	return out
end

-- Cleans an untrusted `egg` field (saves): a known kind and a finite hatchAt, else nil.
function EggKind.sanitize(raw: any): Egg?
	if type(raw) ~= "table" or not EggKind.get(raw.kind) then
		return nil
	end
	local hatchAt = tonumber(raw.hatchAt)
	if hatchAt and (hatchAt ~= hatchAt or hatchAt == math.huge or hatchAt == -math.huge) then
		hatchAt = nil
	end
	return { kind = raw.kind, hatchAt = hatchAt }
end

--[[
	What a client may see of an egg record: the egg's name and tier, no species, the slime's look fields left as
	they are (the model is an egg, so they show nothing). A hatched slime is returned unchanged.
]]
function EggKind.mask(slime: any): any
	local kind = EggKind.of(slime)
	if not kind then
		return slime
	end
	local copy = table.clone(slime) :: any
	copy.name = EggKind.displayName(kind)
	copy.tier = kind.tier
	copy.species = nil
	copy.growth = nil
	local color = Config.RARITIES[kind.tier].color
	copy.color = { color[1], color[2], color[3] }
	copy.egg = table.clone(slime.egg :: Egg)
	return copy
end

return table.freeze(EggKind)
