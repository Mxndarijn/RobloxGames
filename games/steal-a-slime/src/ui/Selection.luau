--!strict
--[[
	Selection

	Pure helpers for picking slimes in the UI (the merge vat load, sorting).
	Works on the `State.slimes` shape. Client-side checks only gate
	buttons; the server still validates every Request.
]]

export type SlimeLike = { id: string, tier: number }
export type SlimeViewLike = { slime: SlimeLike, income: number, stolenBy: number? }

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

export type VatSlime = SlimeLike & { name: string?, keep: boolean? }
export type VatView = { slime: VatSlime, income: number, stolenBy: number? }

-- Why `view` can't go in the vat right now, or nil when it can.
function Selection.blocked(view: VatView): string?
	local name = view.slime.name or "This slime"
	if view.stolenBy ~= nil then
		return `{name} is being stolen`
	elseif view.slime.keep then
		return `{name} is kept: tap 🔒 to free it`
	end
	return nil
end

--[[
	Whether ids are a valid vat load of `count` slimes (3 for the 3-slime vat, 2 for the pair vat): distinct
	owned slimes of one rarity, none being stolen or kept. Returns a player-facing reason when not.
	`rarityName(tier)` names a rarity for the "pick N more" hint.
]]
function Selection.vatLoad(
	slimes: { VatView },
	ids: { string },
	count: number,
	rarityName: ((number) -> string)?
): (boolean, string?)
	local views: { VatView } = {}
	for _, id in ids do
		local view = Selection.findSlime(slimes, id)
		if view == nil then
			return false, "A slime left your plot"
		end
		if table.find(views, view) then
			return false, `Pick {count} different slimes`
		end
		table.insert(views, view)
	end
	for _, view in views do
		local reason = Selection.blocked(view)
		if reason then
			return false, reason
		end
	end
	for _, view in views do
		if view.slime.tier ~= views[1].slime.tier then
			return false, `All {count} must be the same rarity`
		end
	end
	if #views == 0 then
		return false, `Pick {count} slimes of the same rarity`
	end
	if #views < count then
		local left = count - #views
		local rarity = if rarityName then `{rarityName(views[1].slime.tier)} ` else ""
		return false, `Pick {left} more {rarity}slime{if left == 1 then "" else "s"}`
	end
	if #views > count then
		return false, `Only {count} slimes fit in the vat`
	end
	return true, nil
end

-- Taps `id` in the vat selection: picked -> removed; another rarity than the picks -> a fresh selection
-- with only `id`; otherwise added (oldest dropped past `count`). Returns a new list.
function Selection.pick(selection: { string }, id: string, slimes: { VatView }, count: number): { string }
	if table.find(selection, id) then
		return Selection.toggle(selection, id, count)
	end
	local view = Selection.findSlime(slimes, id)
	local first = Selection.findSlime(slimes, selection[1])
	if view and first and first.slime.tier ~= view.slime.tier then
		return { id }
	end
	return Selection.toggle(selection, id, count)
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

return table.freeze(Selection)
