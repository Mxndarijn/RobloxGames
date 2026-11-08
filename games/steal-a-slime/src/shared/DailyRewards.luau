--!strict
--[[
	DailyRewards

	The 30-day daily streak (contract/daily-streak.md): which reward a streak day gives (Config.DAILY_REWARDS), what
	it becomes when it can't be given (an owned skin is a Mystery Egg; an egg or item that can't be given is
	fallback cash), the claim, and the State.daily view. A missed day starts the streak again; the days repeat after
	DAILY_STREAK_CAP. Pure: no Roblox APIs. `features` overrides Config.FEATURES (tests).
]]

local Codes = if script then require(script.Parent.Codes) else require("./Codes")
local Config = if script then require(script.Parent.Config) else require("./Config")
local Consumables = if script then require(script.Parent.Consumables) else require("./Consumables")
local Economy = if script then require(script.Parent.Economy) else require("./Economy")
local MysteryEgg = if script then require(script.Parent.MysteryEgg) else require("./MysteryEgg")
local PetSeats = if script then require(script.Parent.PetSeats) else require("./PetSeats")
local PlayerData = if script then require(script.Parent.PlayerData) else require("./PlayerData")
local Progression = if script then require(script.Parent.Progression) else require("./Progression")
local Rng = if script then require(script.Parent.Rng) else require("./Rng")
local Types = if script then require(script.Parent.Types) else require("./Types")
local Lib = if script then (game:GetService("ReplicatedStorage") :: any).Lib else nil
local Localize = if Lib then require(Lib.locale.Localize) else require("../../../../shared/luau/src/locale/Localize")

-- shared/TaggedText, loaded on first use (it reads the Strings catalog).
local function tagged(): any
	return if script then require(script.Parent.TaggedText) :: any else require("./TaggedText") :: any
end

type Data = PlayerData.Data
type Features = { [string]: boolean }?

export type Kind = "cash" | "egg" | "boost" | "consumable" | "trail" | "seat"

-- One day's reward as given (after the swaps) and as State.daily shows it (Types.DailyReward): kind is a Kind,
-- `short` the label on a narrow track tile ("$1K", "Egg", "2x", "Luck", "x2", "Golden"). Both are Localize messages
-- where they hold words (ui/Text.text draws either); DailyRewards.english gives the English.
export type Reward = Types.DailyReward
export type View = Types.DailyView

-- What the claim needs to make an egg: the Rng the egg is rolled on and a new slime id.
export type EggSource = { rng: Rng.Rng, newId: () -> string }

local DailyRewards = {}

DailyRewards.TRACK = 7 -- days shown at once

local function feature(features: Features, name: string): boolean
	local override = if features then features[name] else nil
	if override ~= nil then
		return override
	end
	return (Config.FEATURES :: any)[name] == true
end

local function cap(): number
	return Config.DAILY_STREAK_CAP
end

-- The streak day (1..DAILY_STREAK_CAP) a streak count lands on; the days repeat after the cap.
function DailyRewards.dayOf(streak: number): number
	return ((math.max(math.floor(streak), 1) - 1) % cap()) + 1
end

-- The streak count a claim at `now` would store: one more than the last claim's if that was yesterday, else 1.
function DailyRewards.nextStreak(data: Data, now: number): number
	return if data.daily.lastDay == Progression.dayNumber(now) - 1 then data.daily.streak + 1 else 1
end

local function trailDef(id: string?): any
	for _, def in Config.EXCLUSIVE_SHOP.trails do
		if def.id == id then
			return def
		end
	end
	return nil
end

local function ownsSkin(data: Data, kind: string, id: string?): boolean
	if id == nil then
		return false
	end
	return table.find(if kind == "trail" then data.ownedTrails else data.ownedSeats, id) ~= nil
end

local function cashReward(day: number, base: number, rebirths: number): Reward
	local amount = math.floor(base * Economy.rebirthMultiplier(rebirths))
	return {
		day = day,
		kind = "cash",
		label = `${Economy.formatNumber(amount)}`,
		short = `${Economy.formatNumber(amount)}`,
		icon = "Cash",
		amount = amount,
		skin = false,
	}
end

local function fallback(day: number, data: Data): Reward
	return cashReward(day, Config.DAILY_FALLBACK_CASH, data.rebirths)
end

-- "Luck Potion" -> "Luck", "Golden Cloud" -> "Golden": what fits on a narrow tile, as the Strings entry
-- world.daily_short.<kind>.<id> (Strings/World makes it with this function).
function DailyRewards.firstWord(name: string): string
	return string.match(name, "^%s*(%S+)") or name
end
local function short(kind: string, id: string, name: string): Localize.Text
	return tagged().known(`world.daily_short.{kind}.{id}`, DailyRewards.firstWord(name))
end

local function dataName(kind: string, id: string, name: string): Localize.Text
	return tagged().known(`data.{kind}.{id}.name`, name)
end

-- The English of a reward's label or short.
function DailyRewards.english(text: Localize.Text): string
	return tagged().english(text)
end

local function eggReward(day: number, data: Data, features: Features): Reward
	if not feature(features, "MysteryEggs") or PlayerData.freePad(data) == nil then
		return fallback(day, data)
	end
	return {
		day = day,
		kind = "egg",
		label = Localize.msg("world.daily.egg"),
		short = Localize.msg("world.daily.egg_short"),
		icon = "MysteryEgg",
		skin = false,
	}
end

-- What streak `day` gives this player now: the listed reward, or what replaces it (contract/daily-streak.md).
function DailyRewards.resolve(data: Data, day: number, features: Features): Reward
	local entry: any = Config.DAILY_REWARDS[day]
	local kind = entry.kind
	if kind == "cash" then
		return cashReward(day, entry.amount, data.rebirths)
	elseif kind == "egg" then
		return eggReward(day, data, features)
	elseif kind == "boost" then
		return {
			day = day,
			kind = "boost",
			label = Localize.msg("world.daily.boost", { mult = entry.mult, minutes = entry.minutes }),
			short = `{entry.mult}x`,
			icon = "Boost_Code",
			skin = false,
			mult = entry.mult,
			minutes = entry.minutes,
		}
	elseif kind == "consumable" then
		local def = Consumables.def(entry.id)
		local count = entry.count or 1
		local off = not feature(features, "Consumables")
		if not def or off or Consumables.held(data, entry.id) + count > Config.CONSUMABLE_HELD_MAX then
			return fallback(day, data)
		end
		return {
			day = day,
			kind = "consumable",
			label = if count == 1
				then dataName("consumable", def.id, def.name)
				else Localize.msg(
					"world.daily.consumables",
					{ count = count, name = dataName("consumable", def.id, def.name) }
				),
			short = if count == 1 then short("consumable", def.id, def.name) else `x{count}`,
			icon = `Consumable_{def.id}`,
			skin = false,
			id = def.id,
			count = count,
		}
	end
	-- A daily skin: a trail or a seat. One the player owns already gives an egg.
	if ownsSkin(data, kind, entry.id) then
		return eggReward(day, data, features)
	end
	if kind == "trail" then
		local def = trailDef(entry.id)
		return {
			day = day,
			kind = "trail",
			label = Localize.msg("world.daily.trail", {
				name = if def then dataName("carryTrail", def.id, def.name) else entry.id,
			}),
			short = if def then short("trail", def.id, def.name) else entry.id,
			icon = `Trail_{entry.id}`,
			skin = true,
			id = entry.id,
		}
	end
	local seat = PetSeats.get(entry.id)
	return {
		day = day,
		kind = "seat",
		label = Localize.msg(
			"world.daily.seat",
			{ name = if seat then dataName("petSeat", seat.id, seat.name) else entry.id }
		),
		short = if seat then short("seat", seat.id, seat.name) else entry.id,
		icon = `PetSeat_{entry.id}`,
		skin = true,
		id = entry.id,
	}
end

-- The first day of the track that shows `day`: its week (1, 8, 15), else the last seven days.
function DailyRewards.trackStart(day: number): number
	local week = math.floor((day - 1) / DailyRewards.TRACK) * DailyRewards.TRACK + 1
	return math.clamp(week, 1, math.max(cap() - DailyRewards.TRACK + 1, 1))
end

-- The next skin day after `day` (up to the end of the 30 days) whose skin the player doesn't own yet.
function DailyRewards.nextSkin(data: Data, day: number, features: Features): Reward?
	for d = day + 1, cap() do
		local entry: any = Config.DAILY_REWARDS[d]
		if (entry.kind == "trail" or entry.kind == "seat") and not ownsSkin(data, entry.kind, entry.id) then
			return DailyRewards.resolve(data, d, features)
		end
	end
	return nil
end

-- State.daily.
function DailyRewards.view(data: Data, now: number, features: Features): View
	local available = Progression.dailyAvailable(data.daily, now)
	local day = DailyRewards.dayOf(if available then DailyRewards.nextStreak(data, now) else data.daily.streak)
	local reward = DailyRewards.resolve(data, day, features)
	local track: { Reward } = {}
	local start = DailyRewards.trackStart(day)
	for d = start, math.min(start + DailyRewards.TRACK - 1, cap()) do
		table.insert(track, if d == day then reward else DailyRewards.resolve(data, d, features))
	end
	return {
		available = available,
		streak = data.daily.streak,
		day = day,
		amount = reward.amount or 0,
		reward = reward,
		track = track,
		nextSkin = DailyRewards.nextSkin(data, day, features),
	}
end

-- Gives a resolved reward. An egg goes on the first free pad and starts incubating.
function DailyRewards.give(data: Data, reward: Reward, now: number, eggs: EggSource)
	local kind = reward.kind
	if kind == "cash" then
		PlayerData.earn(data, reward.amount or 0)
	elseif kind == "egg" then
		local egg = MysteryEgg.rollFor(eggs.rng, eggs.newId(), data.rebirths)
		MysteryEgg.startIncubating(egg, now, eggs.rng:int(1, Rng.SEED_MAX))
		PlayerData.addSlime(data, egg)
	elseif kind == "boost" then
		Codes.addBoost(data, reward.mult or 1, reward.minutes or 0, now)
	elseif kind == "consumable" then
		for _ = 1, reward.count or 1 do
			Consumables.addHeld(data, reward.id :: string)
		end
	elseif kind == "trail" then
		table.insert(data.ownedTrails, reward.id :: string)
	elseif kind == "seat" then
		table.insert(data.ownedSeats, reward.id :: string)
	end
end

--[[
	Claims today's reward: (true, reward) or (false, reason). Grows the streak (a missed day starts it at 1) and gives
	what the day resolves to.
]]
function DailyRewards.claim(data: Data, now: number, eggs: EggSource, features: Features): (boolean, Reward | string)
	if not Progression.dailyAvailable(data.daily, now) then
		return false, "already claimed today"
	end
	local streak = DailyRewards.nextStreak(data, now)
	local reward = DailyRewards.resolve(data, DailyRewards.dayOf(streak), features)
	data.daily = { lastDay = Progression.dayNumber(now), streak = streak }
	DailyRewards.give(data, reward, now, eggs)
	return true, reward
end

return table.freeze(DailyRewards)
