--!strict
--[[
	BossBadges (pure, contract/boss-event.md)

	The boss record in the save (`data.boss`: hits, wins per boss species, hauls, MVPs) and the boss badges it earns
	(`Config.BOSS_BADGES`, stamped in `data.boss.badges` with the unix time they were earned). These are save-only
	badges, separate from the Roblox badges in server/Badges. `record` counts one boss event, `grant` stamps every badge
	the record has reached and returns the new ones, `clean` sanitizes a stored record. No Roblox APIs.
]]

local Config = if script then require(script.Parent.Config) else require("./Config")
local SlimeRoster = if script then require(script.Parent.SlimeRoster) else require("./SlimeRoster")

export type Record = {
	hits: number, -- counted Bat hits on any boss
	wins: { [string]: number }, -- boss species id -> wins helped
	hauls: number, -- bosses carried home
	mvps: number, -- won bosses as the top contributor
	badges: { [string]: number }, -- Config.BOSS_BADGES key -> unix seconds it was earned
}

-- One thing that happened in a boss event. "win" needs `species` and the player's `share` of the top hits (0..1).
export type Event = {
	kind: "hit" | "win" | "haul" | "mvp",
	species: string?,
	share: number?,
}

export type Badge = {
	key: string,
	name: string,
	description: string,
	trigger: string,
	value: number,
	species: string?,
}

export type View = { key: string, earnedAt: number }

type Holder = { boss: Record }

local MAX_COUNT = 1e9
local MAX_TIME = 1e11

local BossBadges = {}

function BossBadges.new(): Record
	return { hits = 0, wins = {}, hauls = 0, mvps = 0, badges = {} }
end

-- The Config.BOSS_BADGES entry for `key`, or nil.
function BossBadges.get(key: string): Badge?
	for _, badge in Config.BOSS_BADGES do
		if badge.key == key then
			return badge :: Badge
		end
	end
	return nil
end

local function isBoss(species: any): boolean
	if type(species) ~= "string" then
		return false
	end
	local entry = SlimeRoster.get(species)
	return entry ~= nil and entry.kind == "boss"
end

local function whole(value: any, max: number): number
	local n = tonumber(value)
	if not n or n ~= n then
		return 0
	end
	return math.clamp(math.floor(n), 0, max)
end

-- Wins of every species summed.
function BossBadges.totalWins(record: Record): number
	local total = 0
	for _, n in record.wins do
		total += n
	end
	return total
end

local function progress(record: Record, badge: Badge): number
	local trigger = badge.trigger
	if trigger == "hits" then
		return record.hits
	elseif trigger == "hauls" then
		return record.hauls
	elseif trigger == "mvps" then
		return record.mvps
	elseif trigger == "win" then
		return if badge.species then record.wins[badge.species] or 0 else 0
	elseif trigger == "wins" then
		return BossBadges.totalWins(record)
	end
	return 0
end

-- Config.BOSS_BADGES keys whose trigger `data.boss` has reached (earned or not), in Config order.
function BossBadges.reached(data: Holder): { string }
	local out = {}
	for _, badge in Config.BOSS_BADGES do
		if progress(data.boss, badge :: Badge) >= badge.value then
			table.insert(out, badge.key)
		end
	end
	return out
end

-- Counts one event in `data.boss`. Returns whether it counted: a "win" needs a boss species and a share of at
-- least Config.BOSS.WIN_SHARE.
function BossBadges.record(data: Holder, event: Event): boolean
	local record = data.boss
	local kind = event.kind
	if kind == "hit" then
		record.hits = math.min(record.hits + 1, MAX_COUNT)
	elseif kind == "haul" then
		record.hauls = math.min(record.hauls + 1, MAX_COUNT)
	elseif kind == "mvp" then
		record.mvps = math.min(record.mvps + 1, MAX_COUNT)
	elseif kind == "win" then
		local species = event.species
		if not species or not isBoss(species) or (event.share or 0) < Config.BOSS.WIN_SHARE then
			return false
		end
		record.wins[species] = math.min((record.wins[species] or 0) + 1, MAX_COUNT)
	else
		return false
	end
	return true
end

-- Stamps every reached, unearned badge with `now` (unix seconds). Returns the newly earned keys, in Config order.
function BossBadges.grant(data: Holder, now: number): { string }
	local fresh = {}
	local badges = data.boss.badges
	for _, key in BossBadges.reached(data) do
		if badges[key] == nil then
			badges[key] = whole(now, MAX_TIME)
			table.insert(fresh, key)
		end
	end
	return fresh
end

-- Earned badges in Config order, for State.bossBadges.
function BossBadges.view(data: Holder): { View }
	local out = {}
	for _, badge in Config.BOSS_BADGES do
		local at = data.boss.badges[badge.key]
		if at then
			table.insert(out, { key = badge.key, earnedAt = at })
		end
	end
	return out
end

-- Earned boss badges.
function BossBadges.count(data: Holder): number
	return #BossBadges.view(data)
end

-- A stored record (read) or the live one (write), sanitized: whole numbers clamped, unknown species and badge keys
-- dropped. Missing / junk -> a fresh record.
function BossBadges.clean(raw: any): Record
	local out = BossBadges.new()
	if type(raw) ~= "table" then
		return out
	end
	out.hits = whole(raw.hits, MAX_COUNT)
	out.hauls = whole(raw.hauls, MAX_COUNT)
	out.mvps = whole(raw.mvps, MAX_COUNT)
	if type(raw.wins) == "table" then
		for species, n in raw.wins do
			local wins = whole(n, MAX_COUNT)
			if isBoss(species) and wins > 0 then
				out.wins[species] = wins
			end
		end
	end
	if type(raw.badges) == "table" then
		for key, at in raw.badges do
			if type(key) == "string" and BossBadges.get(key) then
				out.badges[key] = whole(at, MAX_TIME)
			end
		end
	end
	return out
end

return table.freeze(BossBadges)
