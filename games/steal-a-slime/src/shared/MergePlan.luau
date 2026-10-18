--!strict
--[[
	MergePlan (pure, CONTRACT.md §21.1)

	Picks groups of three slimes for the merge vat. Used by the server's `AutoMerge` action on the player's
	data, and by the merge menu on `State.slimes` for "Pick for me" and the auto-merge summary (a suggestion
	only: the server plans again and validates every group).

	Candidates: owned slimes that are not busy, not kept (`slime.keep`) and not the favourite. Per chosen
	rarity (lowest first) they are ordered by income (lowest first), then size (smallest first), then id, and
	taken in groups of three; leftovers stay. Only rarities 1 .. MAX_TIER - 1 can be auto-merged.
]]

local Config = if script then require(script.Parent.Config) else require("./Config")
local PlayerData = if script then require(script.Parent.PlayerData) else require("./PlayerData")
local TripleMerge = if script then require(script.Parent.TripleMerge) else require("./TripleMerge")

export type Candidate = {
	id: string,
	tier: number,
	income: number,
	size: number,
	keep: boolean?,
	favorite: boolean?,
	busy: boolean?,
}
export type Group = { tier: number, ids: { string } }
export type Options = { tiers: { [number]: boolean }, limit: number? }

local MergePlan = {}

-- The highest rarity auto-merge may use (Secret slimes are never auto-merged).
MergePlan.MAX_AUTO_TIER = Config.MAX_TIER - 1

-- Rarity set -> bit mask (bit t - 1 = rarity t) and back. Unknown or out-of-range tiers are dropped.
function MergePlan.maskOf(tiers: { [number]: boolean }): number
	local mask = 0
	for tier = 1, MergePlan.MAX_AUTO_TIER do
		if tiers[tier] then
			mask += 2 ^ (tier - 1)
		end
	end
	return mask
end

function MergePlan.tiersOf(mask: number): { [number]: boolean }
	local tiers = {}
	if type(mask) ~= "number" or mask ~= mask or mask < 0 or mask == math.huge then
		return tiers
	end
	local m = math.floor(mask)
	for tier = 1, MergePlan.MAX_AUTO_TIER do
		if math.floor(m / 2 ^ (tier - 1)) % 2 == 1 then
			tiers[tier] = true
		end
	end
	return tiers
end

-- Why `c` can't be auto-merged, or nil when it can.
function MergePlan.excluded(c: Candidate): string?
	if c.busy then
		return "busy"
	elseif c.keep then
		return "kept"
	elseif c.favorite then
		return "favourite"
	end
	return nil
end

local function cheaperFirst(x: Candidate, y: Candidate): boolean
	if x.income ~= y.income then
		return x.income < y.income
	end
	if x.size ~= y.size then
		return x.size < y.size
	end
	return x.id < y.id
end

-- The eligible candidates of `tier`, cheapest first.
function MergePlan.pool(candidates: { Candidate }, tier: number): { Candidate }
	local pool = {}
	for _, c in candidates do
		if c.tier == tier and MergePlan.excluded(c) == nil then
			table.insert(pool, c)
		end
	end
	table.sort(pool, cheaperFirst)
	return pool
end

-- Every group of three in the chosen rarities, lowest rarity and cheapest slimes first, at most `limit`
-- groups (default Config.AUTO_MERGE_MAX).
function MergePlan.plan(candidates: { Candidate }, options: Options): { Group }
	local limit = options.limit or Config.AUTO_MERGE_MAX
	local groups: { Group } = {}
	for tier = 1, MergePlan.MAX_AUTO_TIER do
		if options.tiers[tier] then
			local pool = MergePlan.pool(candidates, tier)
			local i = 1
			while i + TripleMerge.COUNT - 1 <= #pool and #groups < limit do
				local ids = {}
				for k = 0, TripleMerge.COUNT - 1 do
					table.insert(ids, pool[i + k].id)
				end
				table.insert(groups, { tier = tier, ids = ids })
				i += TripleMerge.COUNT
			end
		end
	end
	return groups
end

-- The cheapest group of `count` slimes of `tier` (any rarity up to Secret, since the player confirms it
-- by hand), or of the lowest rarity that has one when `tier` is nil. nil when there is none.
function MergePlan.suggest(candidates: { Candidate }, tier: number?, count: number?): Group?
	local n = count or TripleMerge.COUNT
	for t = tier or 1, tier or Config.MAX_TIER do
		local pool = MergePlan.pool(candidates, t)
		if #pool >= n then
			local ids = {}
			for k = 1, n do
				table.insert(ids, pool[k].id)
			end
			return { tier = t, ids = ids }
		end
	end
	return nil
end

-- Groups per rarity: { [tier] = count }.
function MergePlan.countByTier(groups: { Group }): { [number]: number }
	local counts = {}
	for _, g in groups do
		counts[g.tier] = (counts[g.tier] or 0) + 1
	end
	return counts
end

-- Candidates from a player's saved data (server): income from PlayerData.slimeIncome.
function MergePlan.fromData(data: PlayerData.Data, busy: { [string]: boolean }?): { Candidate }
	local list = {}
	for _, slime in data.slimes do
		table.insert(list, {
			id = slime.id,
			tier = slime.tier,
			income = PlayerData.slimeIncome(data, slime),
			size = slime.size,
			keep = slime.keep == true,
			favorite = data.favoriteId == slime.id,
			busy = busy ~= nil and busy[slime.id] == true,
		})
	end
	return list
end

-- Candidates from `State.slimes` (client): a slime being stolen counts as busy.
function MergePlan.fromViews(views: { any }, favoriteId: string?): { Candidate }
	local list = {}
	for _, view in views do
		local slime = view.slime
		table.insert(list, {
			id = slime.id,
			tier = slime.tier,
			income = view.income or 0,
			size = slime.size or 1,
			keep = slime.keep == true,
			favorite = favoriteId ~= nil and favoriteId == slime.id,
			busy = view.stolenBy ~= nil,
		})
	end
	return list
end

return table.freeze(MergePlan)
