--!strict
--[[
	Goals

	Client-derived goals for the Goals panel. Pure (tests/ui/Goals.spec.luau).

	Two sources:
	  * `fromServer`: v13 server goals (`State.goals`, CONTRACT §8.2 / §8.8),
	    staged chains whose rewards the server pays automatically. Preferred.
	  * `derive`: LOCAL goals computed from the snapshot every time, never
	    saved and never rewarded; the fallback while a server doesn't send
	    `goals` yet (v12).
]]

local Format = if script then require(script.Parent.Format) else require("./Format")

export type Goal = {
	id: string,
	title: string,
	detail: string, -- one-line summary (Guide card)
	fraction: number,
	done: boolean,
	next: string?,
	reward: string?, -- server goals: the current stage's cash ("+$25M")
	meta: string?, -- server goals: progress and stage ("8/10 · Stage 4 of 5")
	nextShort: string?, -- server goals: the next stage's target ("Next: 20")
}

local Goals = {}

-- SlimeDex milestones in percent; the first one not yet reached is shown.
Goals.DEX_MILESTONES = table.freeze({ 5, 10, 25, 50, 75, 100 })

local function num(value: any): number
	return if type(value) == "number" and value == value then value else 0
end

local function goal(id: string, title: string, detail: string, have: number, need: number): Goal
	local fraction = if need > 0 then math.clamp(have / need, 0, 1) else 1
	return { id = id, title = title, detail = detail, fraction = fraction, done = have >= need }
end

-- rarityNames[i] is the name of tier i (Config.RARITIES).
function Goals.derive(state: any, rarityNames: { string }): { Goal }
	if type(state) ~= "table" then
		return {}
	end
	local out: { Goal } = {}
	local slimes = if type(state.slimes) == "table" then state.slimes else {}

	local padsUnlocked, padsMax = num(state.padsUnlocked), num(state.padsMax)
	table.insert(out, goal("FillPads", "Fill your pads", `{#slimes}/{padsUnlocked} pads used`, #slimes, padsUnlocked))

	local padDetail = if type(state.nextPadRebirths) == "number"
		then `{padsUnlocked}/{padsMax} · next at Rebirth {state.nextPadRebirths}`
		elseif type(state.nextPadCost) == "number" then `{padsUnlocked}/{padsMax} · next {Format.formatCash(
			state.nextPadCost
		)}`
		else `{padsUnlocked}/{padsMax}`
	table.insert(out, goal("AllPads", "Unlock every pad", padDetail, padsUnlocked, padsMax))

	local daily = state.daily
	if type(daily) == "table" then
		local available = daily.available == true
		table.insert(out, {
			id = "Daily",
			title = "Claim today's daily reward",
			detail = if available
				then `Day {num(daily.day)} pays {Format.formatCash(num(daily.amount))}`
				else `Claimed · streak {num(daily.streak)}`,
			fraction = if available then 0 else 1,
			done = not available,
		})
	end

	local best = 0
	for _, view in slimes do
		if type(view) == "table" and type(view.slime) == "table" then
			best = math.max(best, num(view.slime.tier))
		end
	end
	local topTier = #rarityNames
	if topTier > 0 then
		local target = math.min(topTier, best + 1)
		local name = rarityNames[target] or `Tier {target}`
		table.insert(out, goal("BestTier", `Own a {name} slime`, `Best now: tier {best}/{topTier}`, best, target))
	end

	local rebirths = num(state.rebirths)
	local cost = num(state.rebirthCost)
	table.insert(out, {
		id = "Rebirth",
		title = if rebirths == 0 then "Reach your first rebirth" else `Reach rebirth {rebirths + 1}`,
		detail = `{Format.formatCash(num(state.cash))} / {Format.formatCash(cost)}`,
		fraction = if state.canRebirth == true
			then 1
			elseif cost > 0 then math.clamp(num(state.cash) / cost, 0, 1)
			else 0,
		done = state.canRebirth == true,
	})

	local dex = if type(state.dex) == "table" then state.dex else {}
	local total = num(dex.total)
	if total > 0 then
		local found = num(dex.found)
		local pct = found / total * 100
		local target = Goals.DEX_MILESTONES[#Goals.DEX_MILESTONES]
		for _, milestone in Goals.DEX_MILESTONES do
			if pct < milestone then
				target = milestone
				break
			end
		end
		local need = math.ceil(total * target / 100)
		table.insert(
			out,
			goal(
				"Dex",
				`Discover {target}% of the SlimeDex`,
				`{found}/{need} species ({math.floor(pct)}%)`,
				found,
				need
			)
		)
	end

	local shop = state.shop
	if type(shop) == "table" then
		local coil = shop.SpeedCoil
		if type(coil) == "table" then
			local owned = coil.owned == true
			table.insert(out, {
				id = "SpeedCoil",
				title = "Get the Speed Coil",
				detail = if owned then "Owned" else `Shop · {Format.formatCash(num(coil.price))}`,
				fraction = if owned then 1 else 0,
				done = owned,
			})
		end
	end

	return out
end

-- v13 `State.goals` -> Goal rows; nil when the field is missing (v12 server). With `config` (Config) a row
-- also gets the next stage's target (`nextShort`).
function Goals.fromServer(goals: any, config: any?): { Goal }?
	if type(goals) ~= "table" then
		return nil
	end
	local defs: { [string]: any } = {}
	if type(config) == "table" and type(config.GOALS) == "table" then
		for _, def in config.GOALS do
			defs[def.id] = def
		end
	end
	local out: { Goal } = {}
	for _, g in goals do
		if type(g) == "table" and type(g.id) == "string" then
			local progress = num(g.progress)
			local stage, stages = num(g.stage), num(g.stages)
			local done = g.done == true
			local target = if type(g.target) == "number" then g.target else nil
			local detail, meta
			local reward: string? = nil
			local nextShort: string? = nil
			if done or target == nil then
				detail = `All {stages} stages done`
				meta = detail
			else
				local cash = if type(g.reward) == "number" then Format.formatCash(g.reward) else nil
				local count = `{Format.shortNumber(progress)}/{Format.shortNumber(target)}`
				detail = `{count}{if cash then ` · reward {cash}` else ""} · stage {stage + 1}/{stages}`
				meta = `{count} · {if stage + 1 >= stages then "Last stage" else `Stage {stage + 1} of {stages}`}`
				reward = if cash then `+{cash}` else nil
				local def = defs[g.id]
				local nextTarget = if def and type(def.targets) == "table" then def.targets[stage + 2] else nil
				if type(nextTarget) == "number" then
					local n = Format.shortNumber(nextTarget)
					nextShort = `Next: {if def.cash then "$" .. n else n}`
				end
			end
			table.insert(out, {
				id = g.id,
				title = if type(g.title) == "string" then g.title else g.id,
				detail = detail,
				fraction = if done then 1 elseif target and target > 0 then math.clamp(progress / target, 0, 1) else 0,
				done = done,
				next = if not done and type(g.nextTitle) == "string" then `Next: {g.nextTitle}` else nil,
				reward = reward,
				meta = meta,
				nextShort = nextShort,
			})
		end
	end
	return out
end

export type Quest = {
	id: string,
	index: number, -- slot for Request("ClaimQuest", index)
	title: string,
	icon: string,
	detail: string,
	fraction: number,
	done: boolean,
	claimed: boolean,
	reward: string,
	boost: boolean, -- a timed income boost, not cash
}

-- `State.dailyQuests` -> quest cards (empty when the server has none) and the reset line.
function Goals.quests(daily: any): ({ Quest }, string)
	local out: { Quest } = {}
	if type(daily) ~= "table" or type(daily.quests) ~= "table" then
		return out, ""
	end
	for i, q in daily.quests do
		if type(q) == "table" and type(q.id) == "string" then
			local target = math.max(1, num(q.target))
			local progress = math.min(num(q.progress), target)
			table.insert(out, {
				id = q.id,
				index = i,
				title = if type(q.title) == "string" then q.title else q.id,
				icon = if type(q.icon) == "string" then q.icon else q.id,
				detail = `{Format.shortNumber(progress)}/{Format.shortNumber(target)}`,
				fraction = math.clamp(progress / target, 0, 1),
				done = q.done == true,
				claimed = q.claimed == true,
				reward = if type(q.reward) == "string" then q.reward else "",
				boost = q.rewardKind == "boost",
			})
		end
	end
	return out, `Resets in {Format.formatDuration(math.max(0, num(daily.resetsIn)))}`
end

-- Quests in slot order, claimed ones last.
function Goals.sortedQuests(quests: { Quest }): { Quest }
	local copy = table.clone(quests)
	table.sort(copy, function(a, b)
		if a.claimed ~= b.claimed then
			return not a.claimed
		end
		return a.index < b.index
	end)
	return copy
end

-- Open goals first (closest to done on top), finished ones last; stable.
function Goals.sorted(goals: { Goal }): { Goal }
	local copy = table.clone(goals)
	local order: { [Goal]: number } = {}
	for i, g in goals do
		order[g] = i
	end
	table.sort(copy, function(a, b)
		if a.done ~= b.done then
			return not a.done
		end
		if a.fraction ~= b.fraction then
			return a.fraction > b.fraction
		end
		return order[a] < order[b]
	end)
	return copy
end

function Goals.summary(goals: { Goal }): string
	local done = 0
	for _, g in goals do
		if g.done then
			done += 1
		end
	end
	return `{done}/{#goals} done`
end

return table.freeze(Goals)
