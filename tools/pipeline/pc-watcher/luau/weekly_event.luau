-- Client datamodel: reads the replicated workspace attribute "WeeklyEvent" (FEATURES.WeeklyEvents,
-- WeeklyEvents.encode: week|mutation|mutationEndsAt|activeTrait|traitEndsAt|nextKind|nextId|nextStartsAt)
-- and checks it is well formed: a known mutation, an end in the future (server time is within a day of
-- os.time), and a next event that starts after now. Read only.
local raw = workspace:GetAttribute("WeeklyEvent")
if type(raw) ~= "string" then
	return { found = false, ok = false, raw = tostring(raw) }
end
local week, mutation, mEnds, trait, tEnds, nextKind, nextId, nextAt =
	string.match(raw, "^(%-?%d+)|([%w_]+)|(%-?%d+)|([%w_%-]+)|(%d+)|(%a+)|([%w_]+)|(%-?%d+)$")
if not week then
	return { found = true, ok = false, raw = raw, error = "malformed" }
end
local now = os.time()
local ok = tonumber(mEnds) > now and tonumber(nextAt) > now and (nextKind == "trait" or nextKind == "mutation")
return {
	found = true,
	ok = ok,
	raw = raw,
	week = tonumber(week),
	mutation = mutation,
	mutation_left_s = tonumber(mEnds) - now,
	trait = if trait == "-" then nil else trait,
	next_kind = nextKind,
	next_id = nextId,
	next_in_s = tonumber(nextAt) - now,
}
