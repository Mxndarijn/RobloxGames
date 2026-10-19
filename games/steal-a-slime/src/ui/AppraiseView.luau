--!strict
--[[
	AppraiseView

	What the Appraise screen says about a size reroll (Panels/Plot). A reroll picks a new size evenly between
	Config.MIN_SIZE and Config.MAX_SIZE, rounded to Config.APPRAISE_SIZE_DECIMALS (shared Appraise.rollSize), and
	income follows size, so the screen shows where the slime sits on that range, how likely a reroll is to beat
	it, and after a reroll what changed (the server's Types.Appraisal).
	Pure: no Roblox APIs.
]]

local AppraiseView = {}

export type Odds = {
	chance: string, -- "2% chance", "<1% chance", "No chance"
	detail: string, -- the rest of the sentence
	warn: boolean, -- a reroll is more likely to shrink it than grow it
}

export type Result = {
	beforeSize: number,
	afterSize: number,
	incomeBefore: number,
	incomeAfter: number,
	better: boolean?, -- nil when the size did not change
}

-- Where `size` sits on the reroll range, 0 (smallest) .. 1 (biggest).
function AppraiseView.fraction(size: number, minSize: number, maxSize: number): number
	if maxSize <= minSize then
		return 1
	end
	return math.clamp((size - minSize) / (maxSize - minSize), 0, 1)
end

--[[
	Share of rerolls that end strictly bigger than `size`, 0..1, exactly as Appraise.rollSize rolls: a uniform
	roll rounded to `decimals`, so the sizes on that grid are equally likely except the two ends, which get half
	a step each.
]]
function AppraiseView.betterChance(size: number, minSize: number, maxSize: number, decimals: number): number
	local scale = 10 ^ decimals
	local steps = math.floor((maxSize - minSize) * scale + 0.5)
	if steps <= 0 then
		return 0
	end
	local at = math.floor((size - minSize) * scale + 1e-6) -- grid index of `size` (rounded down)
	if at < 0 then
		return 1
	end
	local above = steps - at -- grid sizes strictly bigger, the top end at half weight
	if above <= 0 then
		return 0
	end
	return (above - 0.5) / steps
end

-- "1.97"
function AppraiseView.sizeText(size: number): string
	return string.format("%.2f", size)
end

function AppraiseView.odds(size: number, minSize: number, maxSize: number, decimals: number): Odds
	local p = AppraiseView.betterChance(size, minSize, maxSize, decimals)
	if p <= 0 then
		return { chance = "No chance", detail = "to roll bigger: this is the biggest size.", warn = true }
	end
	local pct = math.floor(p * 100)
	local chance = if pct < 1 then "<1% chance" else `{pct}% chance`
	if p < 0.1 then
		return { chance = chance, detail = "to roll bigger. Almost any reroll makes it smaller.", warn = true }
	elseif p < 0.5 then
		return { chance = chance, detail = "to roll bigger. Most rerolls make it smaller.", warn = true }
	end
	return { chance = chance, detail = `to roll bigger than {AppraiseView.sizeText(size)}.`, warn = false }
end

-- A finished reroll from the server's answer (Types.Appraisal): was -> now and which way it went.
function AppraiseView.result(appraisal: {
	beforeSize: number,
	afterSize: number,
	incomeBefore: number,
	incomeAfter: number,
}): Result
	local beforeSize, afterSize = appraisal.beforeSize, appraisal.afterSize
	local better: boolean? = nil
	if afterSize > beforeSize then
		better = true
	elseif afterSize < beforeSize then
		better = false
	end
	return {
		beforeSize = beforeSize,
		afterSize = afterSize,
		incomeBefore = appraisal.incomeBefore,
		incomeAfter = appraisal.incomeAfter,
		better = better,
	}
end

-- Plain copy for a refused reroll (the server's RequestResult.message).
local REFUSALS = table.freeze({
	["not enough cash"] = "Not enough cash for this reroll.",
	["slime is busy"] = "This slime is busy right now.",
	["not your slime"] = "This slime isn't on your plot any more.",
	["too fast"] = "Slow down a little and try again.",
})

function AppraiseView.refusal(message: string?): string
	return if message and REFUSALS[message] then REFUSALS[message] else "The reroll didn't go through. Try again."
end

-- The labelled steps under the size tape: every 0.2 from the smallest to the biggest size.
function AppraiseView.ticks(minSize: number, maxSize: number): { number }
	local out = {}
	local step = 0.2
	local v = minSize
	while v <= maxSize + 1e-6 do
		table.insert(out, math.floor(v * 100 + 0.5) / 100)
		v += step
	end
	return out
end

return table.freeze(AppraiseView)
