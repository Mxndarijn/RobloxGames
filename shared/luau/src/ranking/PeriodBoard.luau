--!strict
--[[
	PeriodBoard: one best score per player on a board that lives for one period (a course, a round, a day) and is
	shared by every server, as pure functions over an injected store. Lower scores win (a fastest time); equal
	scores go to whoever set theirs first in the period (`at`).

		local entry = { score = 423, at = 61, name = "Mila", hidden = false } -- 42.3 s, set 61 s into the period
		local ok, reason = PeriodBoard.post(store, map, userId, entry, { expiration = 5400, wait = task.wait })
		local rows = PeriodBoard.read(store, map, 100) -- ranked rows, best first (nil + reason on a failed read)
		local rows2, rank = PeriodBoard.place(rows, userId, entry, 100) -- the same write on a local copy

	The store is anything with `update(map, key, transform, expiration)` (MemoryStoreSortedMap:UpdateAsync: the
	transform gets the old value and sort key and returns the new pair, or nil to keep the old one) and
	`range(map, count)` (GetRangeAsync ascending: { { key, value, sortKey } }). `memoryStore(clock)` is one in
	memory, shared by every "server" that holds it (Studio, tests); MemoryStoreBoard is the Roblox one.

	A write keeps the better entry (`transform`), so two servers posting for the same player can't overwrite a
	better time with a worse one. The same run posted again (equal score and `at`) only refreshes its name and
	hidden flag. Sort key = score * tieRange + at (at in 0 .. tieRange - 1), so the store itself orders ties.
]]

local Retry = if script then require(script.Parent.Parent.core.Retry) else require("../core/Retry")

export type Entry = { score: number, at: number, name: string, hidden: boolean }
export type Item = { key: string, value: any, sortKey: any? }
export type Row = { rank: number, userId: number, score: number, at: number, name: string, hidden: boolean }
export type Transform = (old: any, oldSortKey: any?) -> (any?, any?)
export type Store = {
	update: (map: string, key: string, transform: Transform, expiration: number) -> any?,
	range: (map: string, count: number) -> { Item },
}
export type PostOptions = {
	expiration: number, -- seconds the board lives on after this write (the store drops it then)
	delays: { number }?, -- waits between tries (default RETRY_DELAYS)
	wait: ((seconds: number) -> ())?, -- default: no wait (memory store, specs)
	tieRange: number?,
}

local PeriodBoard = {}

PeriodBoard.PREFIX = "u_"
PeriodBoard.TIE_RANGE = 100000 -- `at` values per score step: seconds into a period up to ~27 hours
PeriodBoard.MAX_NAME = 40 -- characters of a stored name
PeriodBoard.MAX_RANGE = 200 -- the most rows one read returns (GetRangeAsync's limit)
PeriodBoard.RETRY_DELAYS = table.freeze({ 1, 2, 4 }) -- seconds between the tries of a write

function PeriodBoard.key(userId: number): string
	return `{PeriodBoard.PREFIX}{math.floor(userId)}`
end

-- "u_123" -> 123 (nil for any other shape).
function PeriodBoard.userIdOf(key: any): number?
	if type(key) ~= "string" or string.sub(key, 1, #PeriodBoard.PREFIX) ~= PeriodBoard.PREFIX then
		return nil
	end
	local digits = string.match(string.sub(key, #PeriodBoard.PREFIX + 1), "^(%d+)$")
	return if digits then tonumber(digits) else nil
end

-- The store name of one period's board: "<base>_<period>", or "<base>_<period>_<tag>" (a content hash, a version).
function PeriodBoard.mapName(base: string, period: number, tag: string?): string
	local name = `{base}_{math.floor(period)}`
	return if tag and tag ~= "" then `{name}_{tag}` else name
end

local function whole(v: any, max: number): number?
	if type(v) ~= "number" or v ~= v or v < 0 or v > max then
		return nil
	end
	return math.floor(v)
end

-- A stored value as an Entry, or nil when it is junk. Scores and `at` are whole numbers, the name is capped.
function PeriodBoard.clean(value: any, tieRange: number?): Entry?
	if type(value) ~= "table" then
		return nil
	end
	local score = whole(value.score, 2 ^ 53 / (tieRange or PeriodBoard.TIE_RANGE) - 1)
	local at = whole(value.at, (tieRange or PeriodBoard.TIE_RANGE) - 1)
	if not score or not at then
		return nil
	end
	local name = if type(value.name) == "string" then string.sub(value.name, 1, PeriodBoard.MAX_NAME) else ""
	return { score = score, at = at, name = name, hidden = value.hidden == true }
end

function PeriodBoard.sortKey(entry: Entry, tieRange: number?): number
	return entry.score * (tieRange or PeriodBoard.TIE_RANGE) + entry.at
end

-- True when `entry` ranks above `old` (nil = nothing yet): a lower score, or the same score set earlier.
function PeriodBoard.beats(entry: Entry, old: Entry?): boolean
	if not old then
		return true
	end
	return entry.score < old.score or (entry.score == old.score and entry.at < old.at)
end

local function sameRun(a: Entry, b: Entry): boolean
	return a.score == b.score and a.at == b.at
end

-- The write's transform: the new entry when it beats the stored one (or is the same run with a new name or hidden
-- flag), else nil (the store keeps what it has).
function PeriodBoard.transform(entry: Entry, tieRange: number?): Transform
	local clean = PeriodBoard.clean(entry, tieRange)
	return function(old: any, _oldSortKey: any?): (any?, any?)
		if not clean then
			return nil, nil
		end
		local stored = PeriodBoard.clean(old, tieRange)
		if stored and not PeriodBoard.beats(clean, stored) then
			if not (sameRun(clean, stored) and (clean.name ~= stored.name or clean.hidden ~= stored.hidden)) then
				return nil, nil
			end
		end
		local value = { score = clean.score, at = clean.at, name = clean.name, hidden = clean.hidden }
		return value, PeriodBoard.sortKey(clean, tieRange)
	end
end

local function before(a: Row, b: Row): boolean
	if a.score ~= b.score then
		return a.score < b.score
	end
	if a.at ~= b.at then
		return a.at < b.at
	end
	return a.userId < b.userId
end

local function renumber(rows: { Row })
	for i, row in rows do
		row.rank = i
	end
end

-- Store items -> ranked rows, best first, at most `depth`. Junk items are skipped; a player listed twice keeps the
-- better row.
function PeriodBoard.rows(items: { any }, depth: number?, tieRange: number?): { Row }
	local best: { [number]: Row } = {}
	for _, item in items do
		local userId = if type(item) == "table" then PeriodBoard.userIdOf(item.key) else nil
		local entry = if userId then PeriodBoard.clean((item :: any).value, tieRange) else nil
		if userId and entry then
			local row: Row = {
				rank = 0,
				userId = userId,
				score = entry.score,
				at = entry.at,
				name = entry.name,
				hidden = entry.hidden,
			}
			local old = best[userId]
			if not old or before(row, old) then
				best[userId] = row
			end
		end
	end
	local out: { Row } = {}
	for _, row in best do
		table.insert(out, row)
	end
	table.sort(out, before)
	local cap = depth or #out
	while #out > cap do
		table.remove(out)
	end
	renumber(out)
	return out
end

function PeriodBoard.find(rows: { Row }, userId: number): Row?
	for _, row in rows do
		if row.userId == userId then
			return row
		end
	end
	return nil
end

function PeriodBoard.rankOf(rows: { Row }, userId: number): number?
	local row = PeriodBoard.find(rows, userId)
	return if row then row.rank else nil
end

--[[
	The same write on a local copy of the board: a new list with `userId`'s row replaced when `entry` beats it (or is
	the same run with a new name or hidden flag), re-ranked and cut to `depth`. Returns the list and the player's
	rank in it (nil when the entry falls past `depth`).
]]
function PeriodBoard.place(rows: { Row }, userId: number, entry: Entry, depth: number): ({ Row }, number?)
	local keep = false
	local old = PeriodBoard.find(rows, userId)
	if old then
		local stored: Entry = { score = old.score, at = old.at, name = old.name, hidden = old.hidden }
		local refresh = sameRun(entry, stored) and (entry.name ~= stored.name or entry.hidden ~= stored.hidden)
		keep = not PeriodBoard.beats(entry, stored) and not refresh
	end
	local out: { Row } = {}
	for _, row in rows do
		if row.userId ~= userId or keep then
			table.insert(out, table.clone(row))
		end
	end
	if not keep then
		table.insert(out, {
			rank = 0,
			userId = userId,
			score = entry.score,
			at = entry.at,
			name = entry.name,
			hidden = entry.hidden,
		})
	end
	table.sort(out, before)
	while #out > depth do
		table.remove(out)
	end
	renumber(out)
	return out, PeriodBoard.rankOf(out, userId)
end

--[[
	Writes `entry` for `userId` (keep-the-best), trying again after each of `delays`. Returns true when the store
	took the write or kept a better entry, else false and the last error.
]]
function PeriodBoard.post(
	store: Store,
	map: string,
	userId: number,
	entry: Entry,
	options: PostOptions
): (boolean, string?)
	local lastError: string? = nil
	local transform = PeriodBoard.transform(entry, options.tieRange)
	local done = Retry.run(function(): boolean?
		local ok, err = pcall(store.update, map, PeriodBoard.key(userId), transform, math.max(1, options.expiration))
		if ok then
			return true
		end
		lastError = tostring(err)
		return nil
	end, options.delays or PeriodBoard.RETRY_DELAYS, options.wait or function(_seconds: number) end)
	if done then
		return true, nil
	end
	return false, lastError or "failed"
end

-- The top `count` of `map` as ranked rows, or nil and the error.
function PeriodBoard.read(store: Store, map: string, count: number, tieRange: number?): ({ Row }?, string?)
	local n = math.clamp(math.floor(count), 1, PeriodBoard.MAX_RANGE)
	local ok, items = pcall(store.range, map, n)
	if not ok or type(items) ~= "table" then
		return nil, tostring(items)
	end
	return PeriodBoard.rows(items, n, tieRange), nil
end

export type MemoryStore = Store & {
	maps: { [string]: { [string]: { value: any, sortKey: any, expiresAt: number } } },
}

--[[
	A store in memory with the MemoryStore SortedMap's shape: entries expire `expiration` seconds after their last
	write (by `clock`, default os.clock). Every server that holds the same store shares one board (Studio, specs).
]]
function PeriodBoard.memoryStore(clock: (() -> number)?): MemoryStore
	local now = clock or os.clock
	local maps: { [string]: { [string]: { value: any, sortKey: any, expiresAt: number } } } = {}
	local function mapOf(name: string)
		local m = maps[name]
		if not m then
			m = {}
			maps[name] = m
		end
		return m
	end
	local store = {}
	store.maps = maps
	function store.update(map: string, key: string, transform: Transform, expiration: number): any?
		local m = mapOf(map)
		local slot = m[key]
		if slot and slot.expiresAt <= now() then
			m[key] = nil
			slot = nil
		end
		local value, sortKey = transform(if slot then slot.value else nil, if slot then slot.sortKey else nil)
		if value == nil then
			return nil
		end
		m[key] = { value = value, sortKey = sortKey, expiresAt = now() + expiration }
		return value
	end
	function store.range(map: string, count: number): { Item }
		local m = maps[map] or {}
		local items: { Item } = {}
		local t = now()
		for key, slot in m do
			if slot.expiresAt > t then
				table.insert(items, { key = key, value = slot.value, sortKey = slot.sortKey })
			end
		end
		table.sort(items, function(a, b)
			local ka, kb = tonumber(a.sortKey) or math.huge, tonumber(b.sortKey) or math.huge
			if ka ~= kb then
				return ka < kb
			end
			return a.key < b.key
		end)
		while #items > count do
			table.remove(items)
		end
		return items
	end
	return store :: any
end

return table.freeze(PeriodBoard)
