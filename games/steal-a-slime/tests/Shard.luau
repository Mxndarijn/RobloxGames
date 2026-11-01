--!strict
-- Splits the spec list into n shards that take about as long (scripts/test-parallel runs one Lune
-- process per shard). Greedy: the heaviest spec goes to the lightest shard first. Weights are seconds
-- from tests/SpecWeights; a spec missing there counts as `default`. Pure, so the split is the same on
-- every machine for the same spec list.
local Shard = {}

-- The specs of shard k (1..n), in the order they came in.
function Shard.pick(
	specs: { string },
	weights: { [string]: number },
	k: number,
	n: number,
	default: number?
): { string }
	assert(n >= 1 and k >= 1 and k <= n, `shard {k}/{n} is out of range`)
	local fallback = default or 1
	local function weight(spec: string): number
		return weights[spec] or fallback
	end

	local order = table.clone(specs)
	table.sort(order, function(a, b)
		local wa, wb = weight(a), weight(b)
		if wa ~= wb then
			return wa > wb
		end
		return a < b
	end)

	local load = table.create(n, 0)
	local home: { [string]: number } = {}
	for _, spec in order do
		local best = 1
		for i = 2, n do
			if load[i] < load[best] then
				best = i
			end
		end
		load[best] += weight(spec)
		home[spec] = best
	end

	local out = {}
	for _, spec in specs do
		if home[spec] == k then
			table.insert(out, spec)
		end
	end
	return out
end

return Shard
