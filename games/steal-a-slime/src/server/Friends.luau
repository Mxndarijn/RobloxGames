--!strict
--[[
	Friends (pure)

	Counts, per session, the friends who are in the same server and turns the
	count into data.friendBonus (FriendBonus; Perks.bonusMultiplier applies it).
	`check(a, b)` is Player:IsFriendsWith behind a pcall boundary: it yields and
	may throw. Answers are cached per pair (FRIEND_CACHE_SECONDS); a failed check
	keeps the last known answer (false when none) and isn't retried for
	FRIEND_RETRY_SECONDS, so a Roblox friends outage never blocks or spams.
	`refresh` runs on join and leave. Not saved.
]]

local Shared = if script then (game:GetService("ReplicatedStorage") :: any).Shared else nil
local Config = if Shared then require(Shared.Config) else require("../shared/Config")
local FriendBonus = if Shared then require(Shared.FriendBonus) else require("../shared/FriendBonus")
local World = if script then require(script.Parent.World) else require("./World")

type World = World.World

export type Check = (a: number, b: number) -> boolean

type Entry = { value: boolean, expires: number }
export type Cache = { check: Check, pairs: { [string]: Entry } }

local Friends = {}

function Friends.new(check: Check): Cache
	return { check = check, pairs = {} }
end

local function key(a: number, b: number): string
	return if a < b then `{a}:{b}` else `{b}:{a}`
end

-- The cached answer for a pair (false when unknown), without asking.
function Friends.cached(cache: Cache, a: number, b: number): boolean
	local entry = cache.pairs[key(a, b)]
	return entry ~= nil and entry.value
end

-- Asks once per pair per cache window. Never throws; a failure falls back to the old answer.
function Friends.areFriends(cache: Cache, a: number, b: number, now: number): boolean
	local k = key(a, b)
	local entry = cache.pairs[k]
	if entry and now < entry.expires then
		return entry.value
	end
	local ok, result = pcall(cache.check, a, b)
	if ok then
		local value = result == true
		cache.pairs[k] = { value = value, expires = now + Config.FRIEND_CACHE_SECONDS }
		return value
	end
	local old = entry ~= nil and entry.value
	cache.pairs[k] = { value = old, expires = now + Config.FRIEND_RETRY_SECONDS }
	return old
end

-- Forgets every pair with `userId` (they left).
function Friends.forget(cache: Cache, userId: number)
	local a, b = `{userId}:`, `:{userId}`
	for k in cache.pairs do
		if string.sub(k, 1, #a) == a or string.sub(k, -#b) == b then
			cache.pairs[k] = nil
		end
	end
end

-- Friends of `userId` among the sessions now in the world, from the cache only.
function Friends.count(cache: Cache, world: World, userId: number): number
	local n = 0
	for otherId in world.sessions do
		if otherId ~= userId and Friends.cached(cache, userId, otherId) then
			n += 1
		end
	end
	return n
end

-- Recomputes every session's friend count and bonus. Phase 1 asks about the
-- pairs that aren't cached yet (may yield; sessions can come and go meanwhile);
-- phase 2 reads the cache for the sessions present *now* in one go, so the
-- last refresh to finish always leaves a consistent result. Returns the
-- sessions whose bonus changed.
function Friends.refresh(cache: Cache, world: World, now: number): { World.Session }
	local ids = {}
	for userId in world.sessions do
		table.insert(ids, userId)
	end
	table.sort(ids)
	for i = 1, #ids do
		for j = i + 1, #ids do
			if world.sessions[ids[i]] and world.sessions[ids[j]] then
				Friends.areFriends(cache, ids[i], ids[j], now)
			end
		end
	end
	local changed = {}
	for userId, session in world.sessions do
		local n = Friends.count(cache, world, userId)
		local bonus = FriendBonus.bonus(n)
		session.friends = n
		if (session.data.friendBonus or 0) ~= bonus then
			session.data.friendBonus = if bonus > 0 then bonus else nil
			World.markDirty(session)
			table.insert(changed, session)
		end
	end
	return changed
end

return Friends
