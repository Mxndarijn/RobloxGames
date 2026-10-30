--!strict
--[[
	NameCache (pure)

	Resolves a userId to a name through an injected `fetch` (Players:GetNameFromUserIdAsync in Roblox).
	A name that was fetched is kept for good; a failed fetch answers `Player <id>` for this call only and is
	retried on the next one, so callers that refresh on a timer (a leaderboard) keep retries bounded.
]]

local NameCache = {}

export type Cache = { [number]: string }

function NameCache.resolve(cache: Cache, userId: number, fetch: (number) -> string): string
	local known = cache[userId]
	if known then
		return known
	end
	local ok, name = pcall(fetch, userId)
	if ok and type(name) == "string" then
		cache[userId] = name
		return name
	end
	return `Player {userId}`
end

return table.freeze(NameCache)
