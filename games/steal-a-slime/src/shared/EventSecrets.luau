--!strict
--[[
	EventSecrets (pure, CONTRACT.md §34)

	The weekly featured event Secret: one of SlimeRoster's "event" species per weekly-event week
	(WeeklyEvents.weekIndex, Monday 00:00 UTC), in roster order. A pure function of unix time `now`, so every
	server agrees and tests inject a fake clock. The featured entry joins the fountain's Secret pool through
	`extraSpecies` (Spawner.spawnOne -> Fountain.roll -> Genome.rollSpecies). Nothing is saved. No Roblox APIs.
]]

local SlimeRoster = if script then require(script.Parent.SlimeRoster) else require("./SlimeRoster")
local WeeklyEvents = if script then require(script.Parent.WeeklyEvents) else require("./WeeklyEvents")

export type Featured = { id: string, name: string, week: number, startsAt: number, endsAt: number }
export type View = { id: string, name: string, endsAt: number }

local WEEK = 7 * 86400

local ROTATION = SlimeRoster.ofKind("event")
assert(#ROTATION > 0, "EventSecrets: SlimeRoster has no event species")

local EventSecrets = { ROTATION = table.freeze(ROTATION) }

-- The roster entry featured in week `week`.
function EventSecrets.entryForWeek(week: number): SlimeRoster.Entry
	return ROTATION[week % #ROTATION + 1]
end

function EventSecrets.featured(now: number): Featured
	local week = WeeklyEvents.weekIndex(now)
	local entry = EventSecrets.entryForWeek(week)
	local startsAt = WeeklyEvents.weekStart(week)
	return { id = entry.id, name = entry.name, week = week, startsAt = startsAt, endsAt = startsAt + WEEK }
end

-- Unix start of the week `id` is featured: this week when it is featured now, else its next week.
-- nil for an id that is not in the rotation.
function EventSecrets.featuredWeek(id: string, now: number): number?
	local week = WeeklyEvents.weekIndex(now)
	for offset = 0, #ROTATION - 1 do
		if EventSecrets.entryForWeek(week + offset).id == id then
			return WeeklyEvents.weekStart(week + offset)
		end
	end
	return nil
end

-- The featured entry as a list for `extraSpecies` (Genome.rollSpecies only uses entries of the rolled tier).
function EventSecrets.extraSpecies(now: number): { SlimeRoster.Entry }
	return { EventSecrets.entryForWeek(WeeklyEvents.weekIndex(now)) }
end

-- State.featuredSecret.
function EventSecrets.view(now: number): View
	local featured = EventSecrets.featured(now)
	return { id = featured.id, name = featured.name, endsAt = featured.endsAt }
end

return table.freeze(EventSecrets)
