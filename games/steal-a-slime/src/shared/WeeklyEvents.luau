--!strict
--[[
	WeeklyEvents (pure, FEATURES.WeeklyEvents, CONTRACT.md §17)

	The weekly schedule: one timed trait event on each ISO week's Saturday (weeks run Monday 00:00 - next Monday 00:00 UTC). Everything is a pure function of `now` (unix seconds,
	os.time() on the server), so every server agrees and tests inject a fake clock. Nothing is saved.
	All intervals are half-open [startsAt, endsAt); trait events never overlap and each
	always sits inside its own week. The multiplier is clamped to Config.WEEKLY.MAX_MULTIPLIER whatever the config says.
	The events board reads `current` / `next` / `state` and the workspace attribute from `encode`.
	No Roblox APIs.
]]

local Config = if script then require(script.Parent.Config) else require("./Config")

export type Event = {
	id: string, -- the trait id
	label: string,
	icon: string,
	week: number, -- weekIndex
	startsAt: number,
	endsAt: number,
	luck: number, -- rarity luck multiplier (1 = none)
}
export type State = { current: { Event }, next: Event }
export type Decoded = {
	week: number,
	trait: string?, -- active trait id
	traitEndsAt: number?,
	nextId: string,
	nextStartsAt: number,
}

local WeeklyEvents = {}
local forced: boolean? = nil -- test override of FEATURES.WeeklyEvents (Config.FEATURES is frozen)

local DAY = 86400
local HOUR = 3600

-- 1970-01-01 was a Thursday, so Monday-based week 0 starts on day -3.
local function weekStart(week: number): number
	return (week * 7 - 3) * DAY
end
-- Unix second the week `week` starts (Monday 00:00 UTC).
WeeklyEvents.weekStart = weekStart

-- The Monday-based week number of `now`; weeks switch at Monday 00:00 UTC.
function WeeklyEvents.weekIndex(now: number): number
	return math.floor((math.floor(now / DAY) + 3) / 7)
end

-- ISO-8601 (year, week 1..53) of week `week`: the year and week of its Thursday.
function WeeklyEvents.isoWeek(week: number): (number, number)
	local thursday = (week * 7) * DAY
	local year = tonumber(os.date("!%Y", thursday)) :: number
	local yday = tonumber(os.date("!%j", thursday)) :: number
	return year, math.floor((yday - 1) / 7) + 1
end

local function cap(value: number, max: number, floor: number): number
	return math.clamp(value, floor, max)
end

local function traitEvent(week: number): Event
	local cfg = Config.WEEKLY
	local trait = cfg.TRAITS[week % #cfg.TRAITS + 1]
	-- Monday = 0 ... Sunday = 6 within the week; clamped so the window always ends inside the week.
	local offset = (cfg.TRAIT_WEEKDAY - 1) % 7
	local start = weekStart(week) + offset * DAY + cfg.TRAIT_START_HOUR * HOUR
	local length = math.clamp(cfg.TRAIT_SECONDS, 1, DAY)
	local weekEnd = weekStart(week) + 7 * DAY
	local endsAt = math.min(start + length, weekEnd)
	return {
		id = trait.id,
		label = trait.label,
		icon = trait.icon,
		week = week,
		startsAt = start,
		endsAt = endsAt,
		luck = cap(trait.luck, cfg.MAX_MULTIPLIER, 1),
	}
end

-- Events active at `now`: this week's Saturday trait event when it is on, else none.
function WeeklyEvents.current(now: number): { Event }
	local out = {}
	local trait = traitEvent(WeeklyEvents.weekIndex(now))
	if now >= trait.startsAt and now < trait.endsAt then
		table.insert(out, trait)
	end
	return out
end

-- The trait event that starts first strictly after `now` (this week's, else next week's).
function WeeklyEvents.next(now: number): Event
	local week = WeeklyEvents.weekIndex(now)
	local event = traitEvent(week)
	if event.startsAt > now then
		return event
	end
	return traitEvent(week + 1)
end

function WeeklyEvents.state(now: number): State
	return { current = WeeklyEvents.current(now), next = WeeklyEvents.next(now) }
end

function WeeklyEvents.setForced(value: boolean?)
	forced = value
end

function WeeklyEvents.enabled(): boolean
	if forced ~= nil then
		return forced
	end
	return Config.FEATURES.WeeklyEvents
end

-- Rarity luck multiplier of the active trait event; 1 when none or the feature is off.
function WeeklyEvents.multiplier(now: number): number
	if not WeeklyEvents.enabled() then
		return 1
	end
	local luck = 1
	for _, event in WeeklyEvents.current(now) do
		luck *= event.luck
	end
	return luck
end

-- The workspace attribute value (Constants.WEEKLY_EVENT_ATTRIBUTE), "|"-separated:
-- week|activeTraitId ("-" none)|traitEndsAt (0 none)|nextId|nextStartsAt
function WeeklyEvents.encode(now: number): string
	local trait = WeeklyEvents.current(now)[1]
	local nextEvent = WeeklyEvents.next(now)
	return table.concat({
		tostring(WeeklyEvents.weekIndex(now)),
		if trait then trait.id else "-",
		tostring(if trait then trait.endsAt else 0),
		nextEvent.id,
		tostring(nextEvent.startsAt),
	}, "|")
end

function WeeklyEvents.decode(text: any): Decoded?
	if type(text) ~= "string" then
		return nil
	end
	local week, trait, tEnds, nextId, nextAt = string.match(text, "^(%-?%d+)|([%w_%-]+)|(%d+)|([%w_]+)|(%-?%d+)$")
	if not week or not trait or not tEnds or not nextId or not nextAt then
		return nil
	end
	return {
		week = tonumber(week) :: number,
		trait = if trait == "-" then nil else trait,
		traitEndsAt = if trait == "-" then nil else tonumber(tEnds),
		nextId = nextId,
		nextStartsAt = tonumber(nextAt) :: number,
	}
end

return table.freeze(WeeklyEvents)
