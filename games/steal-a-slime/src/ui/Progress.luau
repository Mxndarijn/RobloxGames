--!strict
--[[
	Progress

	Rebirth ladder and SlimeDex completion for the Rebirth / SlimeDex panels.
	Pure (tests/ui/Progress.spec.luau). Reads CONTRACT §5.1 fields, State.dex
	(§36.4), plus the optional v13 fields (§8.2: rebirthTitle, nextRebirthTier,
	dexRewards, dexBonus) when a server sends them;
	future rebirth costs and multipliers come from the caller's `costOf(rebirths)`
	and `multOf(rebirths)` (Shared.Economy.rebirthCost / rebirthMultiplier), and
	the next one from State.nextRebirthMultiplier, so the formulas live in one place.
]]

local Format = if script then require(script.Parent.Format) else require("./Format")

export type Tier = {
	rebirth: number, -- rebirth count once reached
	multiplier: number,
	lockSeconds: number, -- lock bought at this tier (at most LOCK_MAX_SECONDS)
	cost: number?, -- nil for the current tier
	current: boolean,
}
export type RebirthStatus = { ready: boolean, maxed: boolean, fraction: number, text: string }
export type TierCount = { name: string, count: number, total: number? }
export type DexProgress = { count: number, total: number, fraction: number, percent: string, byTier: { TierCount } }

-- Config fields this module needs (Shared.Config satisfies it).
export type Cfg = {
	LOCK_SECONDS_PER_REBIRTH: number,
	LOCK_MAX_SECONDS: number,
	MAX_REBIRTHS: number,
}

local Progress = {}

local function num(value: any): number
	return if type(value) == "number" and value == value then value else 0
end

-- The current tier plus up to `ahead` next ones (stops at MAX_REBIRTHS).
function Progress.rebirthTiers(
	state: any,
	cfg: Cfg,
	costOf: (number) -> number,
	multOf: (number) -> number,
	ahead: number
): { Tier }
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
			multiplier = multOf(r + k),
			lockSeconds = math.min(lock + k * cfg.LOCK_SECONDS_PER_REBIRTH, cfg.LOCK_MAX_SECONDS),
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

export type SlimeNeed = { id: string, name: string, tier: number, color: { number }, owned: boolean }
export type NextRebirth = {
	maxed: boolean,
	ready: boolean,
	rebirth: number, -- the rebirth this unlocks (rebirths + 1)
	cost: number,
	have: number,
	fraction: number, -- cash / cost, 0..1
	need: string, -- "$3.7K more" / "Ready!" / "Max rebirths"
	progress: string, -- "$1.2K / $5K"
	multiplier: number, -- income multiplier after it
	lockGain: number, -- extra lock seconds it adds (0 once locks are at LOCK_MAX_SECONDS)
	slimes: { SlimeNeed }, -- the slimes this rebirth needs and uses up (empty at max)
	missing: { SlimeNeed }, -- the ones of `slimes` the player doesn't have yet
}

-- v28 Rebirth panel: only what the NEXT rebirth needs (its cash cost and
-- how far along the player is) and what it gives.
function Progress.nextRebirth(state: any, cfg: Cfg): NextRebirth
	local r = num(state.rebirths)
	local cost = num(state.rebirthCost)
	local have = num(state.cash)
	local maxed = r >= cfg.MAX_REBIRTHS
	local ready = not maxed and state.canRebirth == true
	local slimes: { SlimeNeed } = {}
	local missing: { SlimeNeed } = {}
	local list = if not maxed and type(state.rebirthSlimes) == "table" then state.rebirthSlimes else {}
	for _, raw in list do
		if type(raw) == "table" and type(raw.name) == "string" then
			local need: SlimeNeed = {
				id = tostring(raw.id),
				name = raw.name,
				tier = num(raw.tier),
				color = if type(raw.color) == "table" then raw.color else { 170, 220, 170 },
				owned = raw.owned == true,
			}
			table.insert(slimes, need)
			if not need.owned then
				table.insert(missing, need)
			end
		end
	end
	local lock = num(state.lockDuration)
	local fraction = if maxed or ready then 1 elseif cost > 0 then math.clamp(have / cost, 0, 1) else 1
	return {
		maxed = maxed,
		ready = ready,
		rebirth = r + 1,
		cost = cost,
		have = have,
		fraction = fraction,
		need = if maxed
			then "Max rebirths"
			elseif ready then "Ready!"
			else `{Format.formatCash(math.max(0, cost - have))} more`,
		progress = `{Format.formatCash(have)} / {Format.formatCash(cost)}`,
		multiplier = num(state.nextRebirthMultiplier),
		lockGain = math.max(0, math.min(lock + cfg.LOCK_SECONDS_PER_REBIRTH, cfg.LOCK_MAX_SECONDS) - lock),
		slimes = slimes,
		missing = missing,
	}
end

-- "a Flan", "an Imp".
local function withArticle(name: string): string
	return (if string.match(name, "^[AEIOUaeiou]") then "an " else "a ") .. name
end

-- "x", "x and y", "x, y and z".
local function joinAnd(items: { string }): string
	if #items <= 1 then
		return items[1] or ""
	end
	return `{table.concat(items, ", ", 1, #items - 1)} and {items[#items]}`
end

-- What the disabled Rebirth well says is missing: "Need $178.8K more" (cash only), "Need a Flan" (slimes
-- only), "Need $15.5M and a Flan" or "Need $15.5M, a Flan and an Imp" (both), "All rebirths done" at the top. "" once it is ready.
function Progress.rebirthReason(nextUp: NextRebirth): string
	if nextUp.maxed then
		return "All rebirths done"
	end
	if nextUp.ready then
		return ""
	end
	local short = math.max(0, nextUp.cost - nextUp.have)
	local items = {}
	for _, need in nextUp.missing do
		table.insert(items, withArticle(need.name))
	end
	if #items > 0 then
		if short > 0 then
			table.insert(items, 1, Format.formatCash(short))
		end
		return `Need {joinAnd(items)}`
	elseif short > 0 then
		return `Need {Format.formatCash(short)} more`
	end
	return "Not ready yet" -- every need met but the server has not said so yet
end

-- State.dex (CONTRACT.md §36.4): species found over the 50 entries, and per rarity (event Secrets are bonus
-- entries and count nowhere here).
function Progress.dex(dex: any, tierNames: { string }): DexProgress
	local d = if type(dex) == "table" then dex else {}
	local count, all = num(d.found), num(d.total)
	local counts: { number } = {}
	local totals: { number } = {}
	for _, e in (if type(d.entries) == "table" then d.entries else {}) :: { any } do
		local tier = if type(e) == "table" and e.kind ~= "event" then tonumber(e.tier) else nil
		if tier then
			totals[tier] = (totals[tier] or 0) + 1
			if e.found == true then
				counts[tier] = (counts[tier] or 0) + 1
			end
		end
	end
	local byTier: { TierCount } = {}
	for i, name in tierNames do
		byTier[i] = { name = name, count = counts[i] or 0, total = totals[i] }
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

-- SlimeDex rewards (State.dexRewards): the next unclaimed milestone as one line
-- ("Next: 15 species +$5K, +3% income"), and the bonus. All nil on a server without them.
function Progress.dexRewards(state: any): { next: string?, bonus: string?, dexPercent: string? }
	local rewards = state.dexRewards
	if type(rewards) ~= "table" then
		return { next = nil, bonus = nil, dexPercent = nil }
	end
	local nextText = "All SlimeDex rewards collected!"
	for _, r in rewards do
		if type(r) == "table" and r.claimed ~= true then
			nextText = `Next: {num(r.count)} species +{Format.formatCash(num(r.reward))}, +{pct(num(r.bonus))} income`
			break
		end
	end
	local bonus = num(state.dexBonus)
	return {
		next = nextText,
		bonus = if bonus > 0 then `SlimeDex bonus: +{pct(bonus)} income` else nil,
		dexPercent = if bonus > 0 then `+{pct(bonus)}` else nil,
	}
end

-- Progress bar toward the next unclaimed species milestone (state.dexRewards;
-- the count is state.dex.found): `icon` is its ItemIcons id, `label` "12 / 15", `ticks` one entry per
-- species milestone with a claimed mark. nil on a server without dex rewards; `next` is nil once every
-- species milestone is claimed (bar full).
export type DexTick = { text: string, claimed: boolean }
export type DexMilestoneBar = {
	icon: string,
	label: string,
	fraction: number,
	next: number?,
	ticks: { DexTick },
	ticksText: string,
}

function Progress.dexMilestones(state: any): DexMilestoneBar?
	local rewards = state.dexRewards
	if type(rewards) ~= "table" or #rewards == 0 then
		return nil
	end
	local count = if type(state.dex) == "table" then num(state.dex.found) else 0
	local ticks: { DexTick } = {}
	local parts: { string } = {}
	local target: number? = nil
	local last = 0
	for _, r in rewards do
		if type(r) == "table" then
			local n = num(r.count)
			last = n
			local claimed = r.claimed == true
			if not claimed and target == nil then
				target = n
			end
			local text = if claimed then `✅{n}` else tostring(n)
			table.insert(ticks, { text = text, claimed = claimed })
			table.insert(parts, text)
		end
	end
	if #ticks == 0 then
		return nil
	end
	local shown = target or last
	return {
		icon = `Dex_{shown}`,
		label = if target then `{math.min(count, shown)} / {shown}` else "All claimed",
		fraction = if target and shown > 0 then math.clamp(count / shown, 0, 1) else 1,
		next = target,
		ticks = ticks,
		ticksText = table.concat(parts, "  "),
	}
end

-- One income-breakdown line from the SlimeDex bonus ("+5%") and the friend line
-- ("Friends +20% income"): "SlimeDex +5% · Friends +20% income"; either may be nil.
function Progress.incomeLine(dexPercent: string?, friends: string?): string?
	if dexPercent and friends then
		return `SlimeDex {dexPercent} · {friends}`
	elseif dexPercent then
		return `SlimeDex bonus: {dexPercent} income`
	end
	return friends
end

return table.freeze(Progress)
