--!strict
--[[
	WeeklyEvents (pure, FEATURES.WeeklyEvents, CONTRACT.md §17)

	The weekly schedule: one mutation boost per ISO week (Monday 00:00 - next Monday 00:00 UTC) and one
	timed trait event on that week's Saturday. Everything is a pure function of `now` (unix seconds,
	os.time() on the server), so every server agrees and tests inject a fake clock. Nothing is saved.
	All intervals are half-open [startsAt, endsAt); events of one kind never overlap, and the trait event
	always sits inside its own week. Multipliers are clamped to Config.WEEKLY.MAX_* whatever the config says.
	The events board reads `current` / `next` / `state` and the workspace attribute from `encode`.
	No Roblox APIs.
]]

local Config = if script then require(script.Parent.Config) else require("./Config")

export type Event = {
	kind: string, -- "mutation" | "trait"
	id: string, -- mutation name, or the trait id
	label: string,
	icon: string,
	week: number, -- weekIndex
	startsAt: number,
	endsAt: number,
	mutation: string?, -- kind "mutation": the boosted Config.MUTATIONS name
	chanceBonus: number, -- extra wild mutation chance for `mutation` (0 for traits)
	luck: number, -- rarity luck multiplier (1 = none)
	mutationMult: number, -- mutation chance multiplier (1 = none)
}
export type State = { current: { Event }, next: Event }
export type Decoded = {
	week: number,
	mutation: string,
	mutationEndsAt: number,
	trait: string?, -- active trait id
	traitEndsAt: number?,
	nextKind: string,
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

local function mutationEvent(week: number): Event
	local cfg = Config.WEEKLY
	local rotation = cfg.MUTATION_ROTATION
	local name = rotation[week % #rotation + 1]
	local start = weekStart(week)
	return {
		kind = "mutation",
		id = name,
		label = `{name} Week`,
		icon = "🧬",
		week = week,
		startsAt = start,
		endsAt = start + 7 * DAY,
		mutation = name,
		chanceBonus = cap(cfg.MUTATION_CHANCE_BONUS, cfg.MAX_CHANCE_BONUS, 0),
		luck = 1,
		mutationMult = 1,
	}
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
		kind = "trait",
		id = trait.id,
		label = trait.label,
		icon = trait.icon,
		week = week,
		startsAt = start,
		endsAt = endsAt,
		mutation = nil,
		chanceBonus = 0,
		luck = cap(trait.luck, cfg.MAX_MULTIPLIER, 1),
		mutationMult = cap(trait.mutation, cfg.MAX_MULTIPLIER, 1),
	}
end

-- The mutation event of the week containing `now` (always exactly one).
function WeeklyEvents.mutationEvent(now: number): Event
	return mutationEvent(WeeklyEvents.weekIndex(now))
end

-- Events active at `now`: the weekly mutation first, then the Saturday trait event when it is on.
function WeeklyEvents.current(now: number): { Event }
	local week = WeeklyEvents.weekIndex(now)
	local out = { mutationEvent(week) }
	local trait = traitEvent(week)
	if now >= trait.startsAt and now < trait.endsAt then
		table.insert(out, trait)
	end
	return out
end

-- The event that starts first strictly after `now` (this week's trait, else next week's mutation week).
function WeeklyEvents.next(now: number): Event
	local week = WeeklyEvents.weekIndex(now)
	local best: Event? = nil
	for w = week, week + 1 do
		for _, event in { mutationEvent(w), traitEvent(w) } do
			if event.startsAt > now and (best == nil or event.startsAt < best.startsAt) then
				best = event
			end
		end
	end
	return best :: Event
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

-- (mutation, extra chance) the week adds to wild drop rolls; nil, 0 when the feature is off.
function WeeklyEvents.mutationBoost(now: number): (string?, number)
	if not WeeklyEvents.enabled() then
		return nil, 0
	end
	local event = WeeklyEvents.mutationEvent(now)
	return event.mutation, event.chanceBonus
end

-- (luck, mutation) multipliers of the active trait event; 1, 1 when none or the feature is off.
function WeeklyEvents.multipliers(now: number): (number, number)
	if not WeeklyEvents.enabled() then
		return 1, 1
	end
	local luck, mutation = 1, 1
	for _, event in WeeklyEvents.current(now) do
		luck *= event.luck
		mutation *= event.mutationMult
	end
	return luck, mutation
end

-- The workspace attribute value (Constants.WEEKLY_EVENT_ATTRIBUTE), "|"-separated:
-- week|mutation|mutationEndsAt|activeTraitId ("-" none)|traitEndsAt (0 none)|nextKind|nextId|nextStartsAt
function WeeklyEvents.encode(now: number): string
	local current = WeeklyEvents.current(now)
	local mutation = current[1]
	local trait = current[2]
	local nextEvent = WeeklyEvents.next(now)
	return table.concat({
		tostring(mutation.week),
		mutation.id,
		tostring(mutation.endsAt),
		if trait then trait.id else "-",
		tostring(if trait then trait.endsAt else 0),
		nextEvent.kind,
		nextEvent.id,
		tostring(nextEvent.startsAt),
	}, "|")
end

function WeeklyEvents.decode(text: any): Decoded?
	if type(text) ~= "string" then
		return nil
	end
	local week, mutation, mEnds, trait, tEnds, nextKind, nextId, nextAt =
		string.match(text, "^(%-?%d+)|([%w_]+)|(%-?%d+)|([%w_%-]+)|(%d+)|(%a+)|([%w_]+)|(%-?%d+)$")
	if not week or not mutation or not mEnds or not trait or not nextKind or not nextId then
		return nil
	end
	return {
		week = tonumber(week) :: number,
		mutation = mutation,
		mutationEndsAt = tonumber(mEnds) :: number,
		trait = if trait == "-" then nil else trait,
		traitEndsAt = if trait == "-" then nil else tonumber(tEnds),
		nextKind = nextKind,
		nextId = nextId,
		nextStartsAt = tonumber(nextAt) :: number,
	}
end

return table.freeze(WeeklyEvents)
