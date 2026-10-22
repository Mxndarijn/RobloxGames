--!strict
--[[
	Merge

	Two slimes of the same tier go into the merge vat and one slime of the next
	tier comes out (both inputs are consumed; never a Secret from lower tiers). The child blends the parents'
	colours, averages their size plus a bonus, inherits pattern / eyes / mouth
	from either parent. Pure: no Roblox APIs.
]]

local Config = if script then require(script.Parent.Config) else require("./Config")
local Genome = if script then require(script.Parent.Genome) else require("./Genome")
local PlayerData = if script then require(script.Parent.PlayerData) else require("./PlayerData")
local Rng = if script then require(script.Parent.Rng) else require("./Rng")

type Slime = Genome.Slime

local Merge = {}

function Merge.canMerge(a: Slime?, b: Slime?): (boolean, string?)
	if not a or not b then
		return false, "missing slime"
	end
	if a.id == b.id then
		return false, "need two different slimes"
	end
	if a.egg or b.egg then
		return false, "eggs can't be merged"
	end
	if a.tier ~= b.tier then
		return false, "slimes must be the same rarity"
	end
	return true, nil
end

function Merge.merge(a: Slime, b: Slime, rng: Rng.Rng, id: string): Slime
	local maxed = a.tier >= Config.MAX_TIER
	local tier = if maxed then Config.MAX_TIER else math.min(a.tier + 1, Config.MERGE_MAX_TIER)

	local color = {}
	for i = 1, 3 do
		color[i] = math.floor((a.color[i] + b.color[i]) / 2 + 0.5)
	end
	local bonus = if maxed then Config.MERGE_SIZE_BONUS * 2 else Config.MERGE_SIZE_BONUS
	local size =
		math.clamp(math.floor(((a.size + b.size) / 2 + bonus) * 100 + 0.5) / 100, Config.MIN_SIZE, Config.MAX_SIZE)

	local function either<T>(x: T, y: T): T
		return if rng:float() < 0.5 then x else y
	end
	-- Name: first half of one parent + second half of the other.
	local nameA, nameB = a.name, b.name
	local name = string.sub(nameA, 1, math.ceil(#nameA / 2)) .. string.sub(nameB, math.ceil(#nameB / 2) + 1)
	if #name < 3 then
		name = nameA
	end

	local child: Slime = {
		id = id,
		name = name,
		tier = tier,
		color = color,
		size = size,
		pattern = either(a.pattern, b.pattern),
		eyes = either(a.eyes, b.eyes),
		mouth = either(a.mouth, b.mouth),
		pad = nil,
	}
	return child
end

--[[
	Picks the best mergeable pair on a plot: the highest tier that has two
	slimes not in `busy`, lowest incomes first (keep the good ones). Never
	picks the favourite while another candidate exists. Returns ids or nil.
]]
function Merge.findPair(slimes: { Slime }, busy: { [string]: boolean }?, favoriteId: string?): (string?, string?)
	local byTier: { [number]: { Slime } } = {}
	for _, s in slimes do
		if not (busy and busy[s.id]) and not s.egg then
			byTier[s.tier] = byTier[s.tier] or {}
			table.insert(byTier[s.tier], s)
		end
	end
	for tier = Config.MAX_TIER, 1, -1 do
		local list = byTier[tier]
		if list and #list >= 2 then
			table.sort(list, function(x, y)
				local fx, fy = x.id == favoriteId, y.id == favoriteId
				if fx ~= fy then
					return fy -- favourite sorts last
				end
				local ix, iy = Genome.baseIncome(x), Genome.baseIncome(y)
				if ix ~= iy then
					return ix < iy
				end
				return x.id < y.id
			end)
			return list[1].id, list[2].id
		end
	end
	return nil, nil
end

--[[
	Validated merge on a player's data: both slimes must be owned, not busy
	and the same tier. The child takes the first slime's pad.
	Returns (ok, childOrReason).
]]
function Merge.apply(
	data: PlayerData.Data,
	idA: string,
	idB: string,
	busy: { [string]: boolean }?,
	rng: Rng.Rng,
	newId: string
): (boolean, Slime | string)
	if busy and (busy[idA] or busy[idB]) then
		return false, "slime is busy"
	end
	local a = PlayerData.findSlime(data, idA)
	local b = PlayerData.findSlime(data, idB)
	if (a and a.keep) or (b and b.keep) then
		return false, "slime is kept"
	end
	local ok, reason = Merge.canMerge(a, b)
	if not ok or not a or not b then
		return false, reason or "cannot merge"
	end
	local pad = a.pad
	local wasFavorite = data.favoriteId == idA or data.favoriteId == idB
	local child = Merge.merge(a, b, rng, newId)
	PlayerData.removeSlime(data, idA)
	PlayerData.removeSlime(data, idB)
	PlayerData.addSlime(data, child, pad)
	if wasFavorite then
		data.favoriteId = child.id
	end
	return true, child
end

return Merge
