--!strict
--[[
	Progression

	Rebirth, daily reward and Slime Rain schedule. Pure: no Roblox APIs.

	Rebirth: costs Economy.rebirthCost(rebirths) cash and needs the
	Config.REBIRTH_SLIMES species of that level on the player's pads. Those
	slimes are used up and cash goes back to STARTING_CASH; every other slime
	stays on its pad. Pads stay unlocked. Gives the income multiplier step of
	that rebirth (Economy.rebirthStep) and a longer lock (Steal.lockDuration).
]]

local Config = if script then require(script.Parent.Config) else require("./Config")
local Economy = if script then require(script.Parent.Economy) else require("./Economy")
local Genome = if script then require(script.Parent.Genome) else require("./Genome")
local SlimeLooks = if script then require(script.Parent.SlimeLooks) else require("./SlimeLooks")
local SlimeRoster = if script then require(script.Parent.SlimeRoster) else require("./SlimeRoster")
local PlayerData = if script then require(script.Parent.PlayerData) else require("./PlayerData")

type Slime = Genome.Slime

export type Requirement = { id: string, name: string, tier: number, color: { number }, owned: boolean }

local Progression = {}

---------------------------------------------------------------------------
-- Rebirth
---------------------------------------------------------------------------

-- SlimeRoster species ids the next rebirth (data.rebirths + 1) needs, one per slime (empty at max).
function Progression.requiredSpecies(rebirths: number): { string }
	return Config.REBIRTH_SLIMES[rebirths + 1] or {}
end

local function isSpecies(slime: Slime, species: string): boolean
	return slime.species == species and not slime.egg
end

--[[
	The slimes the next rebirth uses up: for each required species the matching slime
	that is cheapest to lose (not the favourite, then the lowest income). Returns the
	picked slimes (in requirement order, nil where nothing matches) and whether every
	requirement found one.
]]
function Progression.payment(data: PlayerData.Data): ({ [number]: Slime }, boolean)
	local picked: { [number]: Slime } = {}
	local used: { [string]: boolean } = {}
	local complete = true
	for i, species in Progression.requiredSpecies(data.rebirths) do
		local best: Slime? = nil
		local bestCost = math.huge
		for _, s in data.slimes do
			if not used[s.id] and isSpecies(s, species) then
				-- The favourite only when nothing else matches; otherwise the lowest income.
				local cost = Genome.baseIncome(s) + (if s.id == data.favoriteId then 1e300 else 0)
				if not best or cost < bestCost then
					best, bestCost = s, cost
				end
			end
		end
		if best then
			picked[i] = best
			used[best.id] = true
		else
			complete = false
		end
	end
	return picked, complete
end

-- One { id, name, tier, color, owned } row per slime the next rebirth needs; empty at max.
function Progression.requiredSlimes(data: PlayerData.Data): { Requirement }
	local out: { Requirement } = {}
	if data.rebirths >= Config.MAX_REBIRTHS then
		return out
	end
	local picked = Progression.payment(data)
	for i, id in Progression.requiredSpecies(data.rebirths) do
		local entry = SlimeRoster.get(id)
		if entry then
			local look = SlimeLooks.get(entry.id)
			table.insert(out, {
				id = entry.id,
				name = entry.name,
				tier = entry.tier,
				color = if look then { look.color[1], look.color[2], look.color[3] } else { 170, 220, 170 },
				owned = picked[i] ~= nil,
			})
		end
	end
	return out
end

function Progression.canRebirth(data: PlayerData.Data): (boolean, string?)
	if data.rebirths >= Config.MAX_REBIRTHS then
		return false, "max rebirths reached"
	end
	if data.cash < Economy.rebirthCost(data.rebirths) then
		return false, "not enough cash"
	end
	for _, need in Progression.requiredSlimes(data) do
		if not need.owned then
			return false, `need a {need.name}`
		end
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
		if
			not (exclude and exclude[s.id])
			and not s.egg
			and (not best or Genome.baseIncome(s) > Genome.baseIncome(best))
		then
			best = s
		end
	end
	return best
end

--[[
	Applies a rebirth in place: the required slimes (Progression.payment) are
	used up, cash goes back to STARTING_CASH (uncollected cash pad piles stay) and every other slime stays where
	it is. The favourite is cleared only when it was used up.
	Returns (ok, reason).
]]
function Progression.rebirth(data: PlayerData.Data): (boolean, string?)
	local ok, reason = Progression.canRebirth(data)
	if not ok then
		return false, reason
	end
	local used: { [string]: boolean } = {}
	for _, slime in Progression.payment(data) do
		used[slime.id] = true
	end
	local kept: { Slime } = {}
	for _, slime in data.slimes do
		if not used[slime.id] then
			table.insert(kept, slime)
		end
	end
	data.slimes = kept
	if data.favoriteId and used[data.favoriteId] then
		data.favoriteId = nil
	end
	data.rebirths += 1
	data.cash = Config.STARTING_CASH -- cash pad piles stay on their pads (CashPads)
	return true, nil
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
