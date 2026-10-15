--!strict
--[[
	Progression

	Rebirth, daily reward and Slime Rain schedule. Pure: no Roblox APIs.

	Rebirth: costs Economy.rebirthCost(rebirths) cash. Wipes cash (back to
	STARTING_CASH) and every slime except one keeper: the favourite, or the
	highest-income slime if no favourite is set. Pads stay unlocked. Gives
	+REBIRTH_MULTIPLIER_STEP income multiplier and +10 s lock duration.
]]

local Config = if script then require(script.Parent.Config) else require("./Config")
local Economy = if script then require(script.Parent.Economy) else require("./Economy")
local Genome = if script then require(script.Parent.Genome) else require("./Genome")
local Perks = if script then require(script.Parent.Perks) else require("./Perks")
local PlayerData = if script then require(script.Parent.PlayerData) else require("./PlayerData")

type Slime = Genome.Slime

local Progression = {}

---------------------------------------------------------------------------
-- Rebirth
---------------------------------------------------------------------------

function Progression.canRebirth(data: PlayerData.Data): (boolean, string?)
	if data.rebirths >= Config.MAX_REBIRTHS then
		return false, "max rebirths reached"
	end
	if data.cash < Economy.rebirthCost(data.rebirths) then
		return false, "not enough cash"
	end
	return true, nil
end

function Progression.keeper(data: PlayerData.Data, exclude: { [string]: boolean }?): Slime?
	if data.favoriteId and not (exclude and exclude[data.favoriteId]) then
		local fav = PlayerData.findSlime(data, data.favoriteId)
		if fav then
			return fav
		end
	end
	local best: Slime? = nil
	for _, s in data.slimes do
		if not (exclude and exclude[s.id]) and (not best or Genome.baseIncome(s) > Genome.baseIncome(best)) then
			best = s
		end
	end
	return best
end

-- Up to `count` keepers: the favourite first, then the best by income (none of `exclude`).
function Progression.keepers(data: PlayerData.Data, count: number, exclude: { [string]: boolean }?): { Slime }
	local kept: { Slime } = {}
	local skip = table.clone(exclude or {})
	for _ = 1, count do
		local keep = Progression.keeper(data, skip)
		if not keep then
			break
		end
		table.insert(kept, keep)
		skip[keep.id] = true
	end
	return kept
end

--[[
	Applies a rebirth in place. `exclude` lists slime ids that can't be kept
	(e.g. currently being stolen). The rank's Perks.keepCount slimes stay
	(favourite first). Returns (ok, firstKeptSlimeOrReason).
]]
function Progression.rebirth(data: PlayerData.Data, exclude: { [string]: boolean }?): (boolean, Slime? | string)
	local ok, reason = Progression.canRebirth(data)
	if not ok then
		return false, reason
	end
	local kept = Progression.keepers(data, Perks.keepCount(data.rebirths), exclude)
	data.rebirths += 1
	data.cash = Config.STARTING_CASH
	data.slimes = {}
	data.favoriteId = nil
	for i, slime in kept do
		slime.pad = i
		table.insert(data.slimes, slime)
	end
	if kept[1] then
		data.favoriteId = kept[1].id
	end
	return true, kept[1]
end

---------------------------------------------------------------------------
-- Daily reward
---------------------------------------------------------------------------

function Progression.dayNumber(unixTime: number): number
	return math.floor(unixTime / 86400)
end

function Progression.dailyAvailable(daily: PlayerData.Daily, now: number): boolean
	return Progression.dayNumber(now) > daily.lastDay
end

function Progression.dailyAmount(streak: number, rebirths: number): number
	local s = math.clamp(streak, 1, Config.DAILY_STREAK_CAP)
	return math.floor(Config.DAILY_BASE * s * Economy.rebirthMultiplier(rebirths))
end

--[[
	Claims today's reward. Consecutive days grow the streak (reward capped at
	DAILY_STREAK_CAP days), a missed day resets it to 1.
	Returns (ok, amountOrReason).
]]
function Progression.claimDaily(data: PlayerData.Data, now: number): (boolean, number | string)
	local today = Progression.dayNumber(now)
	if today <= data.daily.lastDay then
		return false, "already claimed today"
	end
	local streak = if data.daily.lastDay == today - 1 then data.daily.streak + 1 else 1
	local amount = Progression.dailyAmount(streak, data.rebirths)
	data.daily = { lastDay = today, streak = streak }
	PlayerData.earn(data, amount)
	return true, amount
end

---------------------------------------------------------------------------
-- Slime Rain
---------------------------------------------------------------------------

--[[
	Slime Rain schedule from seconds since server start. The first rain starts
	at RAIN_FIRST_AT, then every RAIN_INTERVAL, each lasting RAIN_DURATION.
	`forcedUntil` (server-elapsed seconds) lets the server trigger one early.
	Returns (active, secondsLeftIfActive or secondsUntilNext).
]]
function Progression.rainStatus(elapsed: number, forcedUntil: number?): (boolean, number)
	if forcedUntil and elapsed < forcedUntil then
		return true, forcedUntil - elapsed
	end
	if elapsed < Config.RAIN_FIRST_AT then
		return false, Config.RAIN_FIRST_AT - elapsed
	end
	local since = (elapsed - Config.RAIN_FIRST_AT) % Config.RAIN_INTERVAL
	if since < Config.RAIN_DURATION then
		return true, Config.RAIN_DURATION - since
	end
	return false, Config.RAIN_INTERVAL - since
end

return Progression
