--!strict
--[[
	Badges

	Roblox badges for milestones (Config.BADGES, v29-BADGES-NEEDED.md).

	* `check` (pure): emits one World "Badge" event per reached milestone, once
	  per session. It reads the save (stats, rebirths, dex, earned), so old saves
	  qualify retroactively. GameLoop reaches it through Milestones.step.
	* `service` (backend injected): `grant(userId, key)` asks BadgeService.
	  Entries without a badgeId are skipped with no call. Ownership is cached per
	  player (UserHasBadgeAsync once), a badge is awarded once, and a failing
	  call is retried with backoff. grant yields, so callers task.spawn it and
	  gameplay never waits on BadgeService. A toast is sent only for a badge the
	  player did not own yet.
]]

local Shared = if script then (game:GetService("ReplicatedStorage") :: any).Shared else nil
local Config = if Shared then require(Shared.Config) else require("../shared/Config")
local PlayerData = if Shared then require(Shared.PlayerData) else require("../shared/PlayerData")
local SpeciesDex = if Shared then require(Shared.SpeciesDex) else require("../shared/SpeciesDex")
local World = if script then require(script.Parent.World) else require("./World")

type Data = PlayerData.Data
export type Badge = { key: string, name: string, trigger: string, value: number, badgeId: number? }

export type Backend = {
	hasBadge: (userId: number, badgeId: number) -> boolean, -- may error
	award: (userId: number, badgeId: number) -> boolean, -- may error
}

export type Options = {
	backend: Backend,
	wait: (seconds: number) -> (),
	notify: (userId: number, text: string) -> (),
	attempts: number?,
	list: { Badge }?, -- tests: replaces Config.BADGES (which ships with nil ids)
}

local Badges = {}

local function reachedBy(data: Data, trigger: string, value: number): boolean
	if trigger == "caught" then
		return data.stats.caught >= value or #data.slimes >= value
	elseif trigger == "stolen" then
		return data.totalStolen >= value
	elseif trigger == "rebirths" then
		return data.rebirths >= value
	elseif trigger == "dexPercent" then
		return SpeciesDex.count(data) * 100 >= value * SpeciesDex.TOTAL
	elseif trigger == "tier" then
		return bit32.btest(SpeciesDex.tierMask(data), bit32.lshift(1, value - 1))
	elseif trigger == "earned" then
		return data.totalEarned >= value
	end
	return false
end

-- Config.BADGES keys whose milestone this save has reached.
function Badges.reached(data: Data): { string }
	local out = {}
	for _, badge in Config.BADGES do
		if reachedBy(data, badge.trigger, badge.value) then
			table.insert(out, badge.key)
		end
	end
	return out
end

local emitted: { [any]: { [string]: boolean } } = setmetatable({}, { __mode = "k" }) :: any

-- Emits a "Badge" event for each newly reached milestone of the session; returns how many.
function Badges.check(world: World.World, session: World.Session): number
	local seen = emitted[session]
	if not seen then
		seen = {}
		emitted[session] = seen
	end
	local n = 0
	for _, key in Badges.reached(session.data) do
		if not seen[key] then
			seen[key] = true
			n += 1
			World.emit(world, { type = "Badge", userId = session.userId, badge = key })
		end
	end
	return n
end

function Badges.find(key: string, list: { Badge }?): Badge?
	local entries: { Badge } = list or (Config.BADGES :: any)
	for _, badge in entries do
		if badge.key == key then
			return badge
		end
	end
	return nil
end

function Badges.service(options: Options)
	local attempts = options.attempts or Config.BADGE_RETRIES
	local owned: { [number]: { [number]: boolean } } = {} -- userId -> badgeId -> known owned
	local busy: { [number]: { [number]: boolean } } = {}
	local self = {}

	-- Runs `fn` up to `attempts` times, backing off 2, 4, 8 s; nil if every try errored.
	local function try(fn: () -> boolean): boolean?
		local delay = 2
		for i = 1, attempts do
			local ok, result = pcall(fn)
			if ok then
				return result
			end
			if i < attempts then
				options.wait(delay)
				delay *= 2
			end
		end
		return nil
	end

	-- Returns true when the player gets the badge from this call (a toast was sent).
	function self.grant(userId: number, key: string): boolean
		local badge = Badges.find(key, options.list)
		local badgeId = badge and badge.badgeId
		if not badge or not badgeId then
			return false -- placeholder: no call at all
		end
		local mine = owned[userId]
		if not mine then
			mine = {}
			owned[userId] = mine
		end
		local working = busy[userId]
		if not working then
			working = {}
			busy[userId] = working
		end
		if mine[badgeId] or working[badgeId] then
			return false
		end
		working[badgeId] = true
		local has = try(function()
			return options.backend.hasBadge(userId, badgeId)
		end)
		local awarded = false
		if has == true then
			mine[badgeId] = true
		elseif has == false then
			local ok = try(function()
				options.backend.award(userId, badgeId)
				return true
			end)
			if ok then
				mine[badgeId] = true
				awarded = true
				options.notify(userId, `Badge unlocked: {badge.name}`)
			end
		end
		working[badgeId] = nil
		return awarded
	end

	function self.release(userId: number)
		owned[userId] = nil
		busy[userId] = nil
	end

	return self
end

return Badges
