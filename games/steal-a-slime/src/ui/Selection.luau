--!strict
--[[
	Selection

	Pure helpers for picking slimes in the UI (merge pair, sorting, slap
	target). Works on the `State.slimes` shape. Client-side checks only gate
	buttons; the server still validates every Request.
]]

export type SlimeLike = { id: string, tier: number }
export type SlimeViewLike = { slime: SlimeLike, income: number, stolenBy: number? }
export type SlapCandidate = { userId: number, distance: number }

local Selection = {}

function Selection.findSlime<T>(slimes: { T }, id: string?): T?
	if id == nil then
		return nil
	end
	for _, view in slimes do
		if (view :: any).slime.id == id then
			return view
		end
	end
	return nil
end

-- Whether ids `a` and `b` are a valid merge pair: two distinct owned slimes of
-- the same tier, neither currently being stolen. Returns a reason when not.
function Selection.canMergePair(slimes: { SlimeViewLike }, a: string?, b: string?): (boolean, string?)
	if a == nil or b == nil then
		return false, "Pick two slimes"
	end
	if a == b then
		return false, "Pick two different slimes"
	end
	local va = Selection.findSlime(slimes, a)
	local vb = Selection.findSlime(slimes, b)
	if va == nil or vb == nil then
		return false, "Slime no longer on your plot"
	end
	if va.stolenBy ~= nil or vb.stolenBy ~= nil then
		return false, "A slime is being stolen"
	end
	if va.slime.tier ~= vb.slime.tier then
		return false, "Slimes must be the same tier"
	end
	return true, nil
end

-- Toggles `id` in a selection of at most `max` ids (oldest dropped first).
-- Returns a new list; the input is not modified.
function Selection.toggle(selection: { string }, id: string, max: number?): { string }
	local limit = max or 2
	local result = {}
	local removed = false
	for _, existing in selection do
		if existing == id then
			removed = true
		else
			table.insert(result, existing)
		end
	end
	if not removed then
		table.insert(result, id)
		while #result > limit do
			table.remove(result, 1)
		end
	end
	return result
end

-- Drops ids that are no longer owned or are being stolen.
function Selection.prune(selection: { string }, slimes: { SlimeViewLike }): { string }
	local result = {}
	for _, id in selection do
		local view = Selection.findSlime(slimes, id)
		if view and view.stolenBy == nil then
			table.insert(result, id)
		end
	end
	return result
end

-- Display order: favourite first, then tier desc, income desc, id.
function Selection.sorted<T>(slimes: { T }, favoriteId: string?): { T }
	local list = table.clone(slimes)
	table.sort(list, function(x: any, y: any)
		local xf, yf = x.slime.id == favoriteId, y.slime.id == favoriteId
		if xf ~= yf then
			return xf
		end
		if x.slime.tier ~= y.slime.tier then
			return x.slime.tier > y.slime.tier
		end
		if x.income ~= y.income then
			return x.income > y.income
		end
		return x.slime.id < y.slime.id
	end)
	return list
end

-- Nearest carrier within `reach` (excluding `selfUserId`), or nil.
function Selection.pickSlapTarget(candidates: { SlapCandidate }, reach: number, selfUserId: number?): number?
	local best: SlapCandidate? = nil
	for _, c in candidates do
		if c.userId ~= selfUserId and c.distance <= reach and (best == nil or c.distance < best.distance) then
			best = c
		end
	end
	return if best then best.userId else nil
end

return table.freeze(Selection)
