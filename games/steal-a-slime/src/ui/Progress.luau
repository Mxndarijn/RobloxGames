--!strict
--[[
	Progress

	Rebirth ladder and Slimedex completion for the Rebirth / Dex panels.
	Pure (tests/ui/Progress.spec.luau). Reads CONTRACT §5.1 fields, plus the
	optional v13 fields (§8.2: rebirthTitle, nextRebirthTier, dexRewards,
	dexBonus) when a server sends them;
	future rebirth costs come from the caller's `costOf(rebirths)` (the panel
	passes Shared.Economy.rebirthCost) so the formula lives in one place.
]]

local Format = if script then require(script.Parent.Format) else require("./Format")

export type Tier = {
	rebirth: number, -- rebirth count once reached
	multiplier: number,
	lockSeconds: number, -- lock bought at this tier (incl. current lock upgrades)
	cost: number?, -- nil for the current tier
	current: boolean,
}
export type RebirthStatus = { ready: boolean, maxed: boolean, fraction: number, text: string }
export type TierCount = { name: string, count: number, total: number? }
export type DexProgress = { count: number, total: number, fraction: number, percent: string, byTier: { TierCount } }

-- Config fields this module needs (Shared.Config satisfies it).
export type Cfg = {
	REBIRTH_MULTIPLIER_STEP: number,
	LOCK_SECONDS_PER_REBIRTH: number,
	MAX_REBIRTHS: number,
}

local Progress = {}

local function num(value: any): number
	return if type(value) == "number" and value == value then value else 0
end

-- The current tier plus up to `ahead` next ones (stops at MAX_REBIRTHS).
function Progress.rebirthTiers(state: any, cfg: Cfg, costOf: (number) -> number, ahead: number): { Tier }
	local r = num(state.rebirths)
	local mult = num(state.rebirthMultiplier)
	local lock = num(state.lockDuration)
	local out: { Tier } = {
		{ rebirth = r, multiplier = mult, lockSeconds = lock, cost = nil, current = true },
	}
	for k = 1, ahead do
		if r + k > cfg.MAX_REBIRTHS then
			break
		end
		table.insert(out, {
			rebirth = r + k,
			multiplier = mult + k * cfg.REBIRTH_MULTIPLIER_STEP,
			lockSeconds = lock + k * cfg.LOCK_SECONDS_PER_REBIRTH,
			cost = if k == 1 then num(state.rebirthCost) else costOf(r + k - 1),
			current = false,
		})
	end
	return out
end

function Progress.tierText(tier: Tier): string
	local head = if tier.current then `Now · rebirth {tier.rebirth}` else `Rebirth {tier.rebirth}`
	local cost = if tier.cost then ` · {Format.formatCash(tier.cost)}` else ""
	return `{head}: {Format.formatMultiplier(tier.multiplier)} income · {math.floor(tier.lockSeconds)}s lock{cost}`
end

function Progress.rebirthStatus(state: any, maxRebirths: number): RebirthStatus
	if num(state.rebirths) >= maxRebirths then
		return { ready = false, maxed = true, fraction = 1, text = "Max rebirths reached" }
	end
	local cost = num(state.rebirthCost)
	local cash = num(state.cash)
	local fraction = if cost > 0 then math.clamp(cash / cost, 0, 1) else 1
	if state.canRebirth == true then
		return { ready = true, maxed = false, fraction = 1, text = "READY! Rebirth now" }
	end
	local pct = math.floor(fraction * 100)
	return {
		ready = false,
		maxed = false,
		fraction = fraction,
		text = `{Format.formatCash(math.max(0, cost - cash))} more needed ({pct}%)`,
	}
end

-- Dex keys are "tier:mutation:pattern:eyes" (Genome.dexKey); every tier has
-- the same number of combinations, so the per-tier total is total / #tiers.
function Progress.dex(dex: any, total: any, tierNames: { string }): DexProgress
	local keys = if type(dex) == "table" then dex else {}
	local count = #keys
	local all = num(total)
	local perTier = if #tierNames > 0 and all % #tierNames == 0 then all // #tierNames else nil
	local counts: { number } = {}
	for _, key in keys do
		local tier = tonumber(string.match(tostring(key), "^(%d+):"))
		if tier then
			counts[tier] = (counts[tier] or 0) + 1
		end
	end
	local byTier: { TierCount } = {}
	for i, name in tierNames do
		byTier[i] = { name = name, count = counts[i] or 0, total = perTier }
	end
	local fraction = if all > 0 then math.clamp(count / all, 0, 1) else 0
	return {
		count = count,
		total = all,
		fraction = fraction,
		percent = `{math.floor(fraction * 100)}%`,
		byTier = byTier,
	}
end

local function pct(fraction: number): string
	return `{math.floor(fraction * 100 + 0.5)}%`
end

-- v13 rank lines; both nil on a server without ranks.
function Progress.rank(state: any): { title: string?, next: string? }
	local title = if type(state.rebirthTitle) == "string" then state.rebirthTitle else nil
	if title == nil then
		return { title = nil, next = nil }
	end
	local nextTier = state.nextRebirthTier
	local nextText = "Top rank reached!"
	if type(nextTier) == "table" then
		local perk = if type(nextTier.text) == "string" and #nextTier.text > 0 then ` - {nextTier.text}` else ""
		nextText = `Next: {nextTier.title} at {num(nextTier.rebirths)} rebirths{perk}`
	end
	return { title = `Rank: {title}`, next = nextText }
end

-- v13 Slimedex rewards; both nil on a server without them.
function Progress.dexRewards(state: any): { next: string?, bonus: string? }
	local rewards = state.dexRewards
	if type(rewards) ~= "table" then
		return { next = nil, bonus = nil }
	end
	local nextText = "All Slimedex rewards collected!"
	for _, r in rewards do
		if type(r) == "table" and r.claimed ~= true then
			nextText =
				`Next reward at {num(r.count)}: +{Format.formatCash(num(r.reward))} and +{pct(num(r.bonus))} income`
			break
		end
	end
	local bonus = num(state.dexBonus)
	return { next = nextText, bonus = if bonus > 0 then `Dex bonus: +{pct(bonus)} income` else nil }
end

return table.freeze(Progress)
