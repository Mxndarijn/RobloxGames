--!strict
--[[
	When a bot plays: a list of { start, stop } sessions (unix seconds),
	sorted and never overlapping, from its profile and a seeded Rng.
	Sessions start between 08:00 and 23:00 of each day, from `startDay` on.
]]

local Profiles = require("./Profiles")
local Rng = require("../../../src/shared/Rng")

export type Session = { start: number, stop: number }

local Schedule = {}

local DAY = 86400
local WAKE, SLEEP = 8 * 3600, 23 * 3600

function Schedule.build(
	profile: Profiles.Profile,
	rng: Rng.Rng,
	t0: number,
	days: number,
	startDay: number
): { Session }
	local out: { Session } = {}
	for day = startDay, days - 1 do
		-- The first day always plays: that is when the player shows up.
		if day == startDay or rng:float() < profile.playChance then
			local count = rng:int(profile.sessions[1], profile.sessions[2])
			local starts = {}
			for _ = 1, count do
				table.insert(starts, t0 + day * DAY + rng:int(WAKE, SLEEP))
			end
			table.sort(starts)
			for _, start in starts do
				local length = rng:int(profile.minutes[1] * 60, profile.minutes[2] * 60)
				local last = out[#out]
				if last and start < last.stop + 600 then
					start = last.stop + 600 -- at least 10 minutes away between sessions
				end
				table.insert(out, { start = start, stop = start + length })
			end
		end
	end
	return out
end

-- Played seconds over a list of sessions.
function Schedule.total(sessions: { Session }): number
	local n = 0
	for _, s in sessions do
		n += s.stop - s.start
	end
	return n
end

return Schedule
