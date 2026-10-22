--!strict
--[[
	Turns the bot Records of every seed into Markdown tables, per profile:
	where players are after N played hours, after N calendar days, how long
	each milestone takes, and where their cash came from.

	Numbers are medians; brackets hold the 10th-90th percentile. A row only
	counts the bots that got that far ("players"), so late rows are biased
	toward the bots that played most.
]]

local Bot = require("./Bot")
local Config = require("../../../src/shared/Config")
local Economy = require("../../../src/shared/Economy")
local Profiles = require("./Profiles")
local Server = require("./Server")

type Record = Server.Record
type Snap = Server.Snap

local Report = {}

-- Nearest-rank percentile of an unsorted list (p in 0..1); nil when empty.
function Report.percentile(values: { number }, p: number): number?
	if #values == 0 then
		return nil
	end
	local sorted = table.clone(values)
	table.sort(sorted)
	local rank = math.clamp(math.ceil(p * #sorted), 1, #sorted)
	return sorted[rank]
end

local function money(n: number): string
	return "$" .. Economy.formatNumber(math.floor(n))
end

local function hours(seconds: number): string
	local h = seconds / 3600
	if h < 1 then
		return string.format("%dm", math.floor(seconds / 60 + 0.5))
	end
	return string.format("%.1fh", h)
end

local function plain(n: number): string
	if n == math.floor(n) then
		return tostring(n)
	end
	return string.format("%.1f", n)
end

-- "median (p10-p90)" of `values` shown with `fmt`; "-" when empty.
function Report.spread(values: { number }, fmt: ((number) -> string)?): string
	local f = fmt or plain
	local mid = Report.percentile(values, 0.5)
	if not mid then
		return "-"
	end
	local lo = Report.percentile(values, 0.1) :: number
	local hi = Report.percentile(values, 0.9) :: number
	if lo == hi then
		return f(mid)
	end
	return `{f(mid)} ({f(lo)}-{f(hi)})`
end

local function field(snaps: { Snap }, key: string): { number }
	local out = {}
	for _, s in snaps do
		table.insert(out, (s :: any)[key])
	end
	return out
end

local function byProfile(records: { Record }): { [string]: { Record } }
	local out = {}
	for _, r in records do
		out[r.profile] = out[r.profile] or {}
		table.insert(out[r.profile], r)
	end
	return out
end

-- Profiles in the order of Profiles.LIST, then the late joiners ("late-<profile>") by name.
local function profilesIn(groups: { [string]: { Record } }): { string }
	local out = {}
	for _, name in Profiles.names() do
		if groups[name] then
			table.insert(out, name)
		end
	end
	local extra = {}
	for name in groups do
		if not table.find(out, name) then
			table.insert(extra, name)
		end
	end
	table.sort(extra)
	table.move(extra, 1, #extra, #out + 1, out)
	return out
end

local function snapTable(lines: { string }, label: string, rows: { { name: string, key: string, snaps: { Snap } } })
	table.insert(
		lines,
		`| Profile | {label} | Players | Rebirths | Income/s | Cash | Pads | SlimeDex | Played | Calendar days |`
	)
	table.insert(lines, "|---|---|---|---|---|---|---|---|---|---|")
	for _, row in rows do
		local s = row.snaps
		table.insert(
			lines,
			`| {row.name} | {row.key} | {#s} | {Report.spread(field(s, "rebirths"))} | {Report.spread(
				field(s, "income"),
				money
			)} | {Report.spread(field(s, "cash"), money)} | {Report.spread(field(s, "pads"))} | {Report.spread(
				field(s, "dex")
			)} | {Report.spread(field(s, "played"), hours)} | {Report.spread(field(s, "days"), function(d)
				return string.format("%.1f", d)
			end)} |`
		)
	end
end

export type Meta = {
	seeds: { number },
	days: number,
	mix: { [string]: number },
	stagger: number,
	checkpoints: { number },
	late: { Server.Late }?,
}

local function botCount(meta: Meta, name: string): number
	for _, late in meta.late or {} do
		if `late-{late.profile}` == name then
			return late.count
		end
	end
	return meta.mix[name] or 0
end

local function ratio(a: number, b: number): number
	return if b > 0 then a / b else 0
end

local MILESTONES = {
	"Rare",
	"Epic",
	"Legendary",
	"Mythic",
	"Secret",
	"firstSteal",
	"firstLock",
	"firstEgg",
}

-- Time to the milestones that are not a rebirth: the first slime of each rarity on a pad, pad floors, SlimeDex counts.
local function milestoneTable(lines: { string }, groups: { [string]: { Record } }, names: { string })
	local keys = table.clone(MILESTONES)
	for floor = 1, #Config.BASE_FLOORS do
		table.insert(keys, `pads{floor * Config.PADS_PER_FLOOR}`)
	end
	for _, m in Config.DEX_MILESTONES.species do
		table.insert(keys, `dex{m.count}`)
	end
	local header, rule = { "| First |" }, { "|---|" }
	for _, name in names do
		table.insert(header, ` {name} |`)
		table.insert(rule, "---|")
	end
	table.insert(lines, table.concat(header))
	table.insert(lines, table.concat(rule))
	for _, key in keys do
		local cells = { `| {key} |` }
		local anyone = false
		for _, name in names do
			local snaps = {}
			for _, r in groups[name] do
				if r.milestones[key] then
					table.insert(snaps, r.milestones[key])
				end
			end
			anyone = anyone or #snaps > 0
			if #snaps == 0 then
				table.insert(cells, " - |")
			else
				local days = Report.percentile(field(snaps, "days"), 0.5) :: number
				local share = math.floor(#snaps / #groups[name] * 100 + 0.5)
				table.insert(
					cells,
					` {Report.spread(field(snaps, "played"), hours)} / day {string.format("%.1f", days)}, {share}% |`
				)
			end
		end
		if anyone then
			table.insert(lines, table.concat(cells))
		end
	end
end

local SOURCES = { "active", "offline", "sell", "goal", "dex", "quest", "daily", "code", "other" }
local SINKS = { "wild", "pad", "upgrade", "coil", "lock", "consumable", "rebirth", "pvp", "other" }

-- Share of all cash earned / spent by source: the sum over the profile's bots, so the rich bots weigh more.
local function ledgerTable(lines: { string }, groups: { [string]: { Record } }, names: { string })
	for _, kind in { "earned", "spent" } do
		local keys = if kind == "earned" then SOURCES else SINKS
		local header = { `| Profile ({kind}) | Total |` }
		local rule = { "|---|---|" }
		for _, key in keys do
			table.insert(header, ` {key} |`)
			table.insert(rule, "---|")
		end
		table.insert(lines, table.concat(header))
		table.insert(lines, table.concat(rule))
		for _, name in names do
			local totals: { [string]: number } = {}
			local all = 0
			for _, r in groups[name] do
				for key, v in (if kind == "earned" then r.earnedBy else r.spentBy) do
					totals[key] = (totals[key] or 0) + v
					all += v
				end
			end
			local cells = { `| {name} | {money(all)} |` }
			for _, key in keys do
				table.insert(cells, string.format(" %.1f%% |", ratio(totals[key] or 0, all) * 100))
			end
			table.insert(lines, table.concat(cells))
		end
		table.insert(lines, "")
	end
end

-- Cash/s added per minute of trips, wild against steal, summed over the profile's bots.
local function tripTable(lines: { string }, groups: { [string]: { Record } }, names: { string })
	table.insert(
		lines,
		"| Profile | Trip | Tries | Worked | Sec/try | Slime income/s per worked trip | Sell value per worked trip | Paid per try | Income/s gained per trip-minute |"
	)
	table.insert(lines, "|---|---|---|---|---|---|---|---|---|")
	for _, name in names do
		for _, kind in { "wild", "steal" } do
			local tries, ok, secs, gain, sell, paid = 0, 0, 0, 0, 0, 0
			for _, r in groups[name] do
				local a = (r.stats :: any)[kind] :: Bot.Agg
				tries += a.tries
				ok += a.ok
				secs += a.secs
				gain += a.gainIncome
				sell += a.gainSell
				paid += a.paid
			end
			if tries > 0 then
				table.insert(
					lines,
					`| {name} | {kind} | {tries} | {string.format("%.0f%%", ratio(ok, tries) * 100)} | {string.format(
						"%.0f",
						ratio(secs, tries)
					)} | {money(ratio(gain, ok))} | {money(ratio(sell, ok))} | {money(ratio(paid, tries))} | {money(
						ratio(gain, secs / 60)
					)} |`
				)
			end
		end
	end
end

-- Flips (wild slime bought and sold at once) by rebirth level: what they earn per hour against the plot's income.
local function flipTable(lines: { string }, groups: { [string]: { Record } }, names: { string })
	local any = false
	for _, name in names do
		for _, r in groups[name] do
			any = any or r.stats.flip.tries > 0
		end
	end
	if not any then
		return
	end
	table.insert(lines, "## Flips by rebirth level")
	table.insert(lines, "")
	table.insert(
		lines,
		"| Profile | Level | Bots | Online h | Flips | Sec/try | Profit/flip | Flip profit per trip-hour | Flip profit per online hour | Plot income per online hour | Flip / plot | Pad sales |"
	)
	table.insert(lines, "|---|---|---|---|---|---|---|---|---|---|---|---|")
	for _, name in names do
		local byLevel: { [number]: { bots: number, l: Bot.LevelStats } } = {}
		for _, r in groups[name] do
			for key, l in r.stats.levels do
				local level = tonumber(key) :: number
				local row = byLevel[level]
				if not row then
					row = {
						bots = 0,
						l = {
							secs = 0,
							incomeSum = 0,
							samples = 0,
							flips = 0,
							flipTries = 0,
							flipSecs = 0,
							revenue = 0,
							paid = 0,
							padSales = 0,
						},
					}
					byLevel[level] = row
				end
				row.bots += 1
				for field, v in l do
					(row.l :: any)[field] += v
				end
			end
		end
		local levels = {}
		for level, row in byLevel do
			if row.l.flipTries > 0 then
				table.insert(levels, level)
			end
		end
		table.sort(levels)
		for _, level in levels do
			local row = byLevel[level]
			local l = row.l
			local profit = l.revenue - l.paid
			local perTrip = ratio(profit, l.flipSecs / 3600)
			local perOnline = ratio(profit, l.secs / 3600)
			local plot = ratio(l.incomeSum, l.samples) * 3600
			table.insert(
				lines,
				`| {name} | r{level} | {row.bots} | {string.format("%.0f", l.secs / 3600)} | {l.flips} | {string.format(
					"%.0f",
					ratio(l.flipSecs, l.flipTries)
				)} | {money(ratio(profit, l.flips))} | {money(perTrip)} | {money(perOnline)} | {money(plot)} | {string.format(
					"%.0f%%",
					ratio(perOnline, plot) * 100
				)} | {l.padSales} |`
			)
		end
	end
	table.insert(lines, "")
end

-- What stealing costs the victims and what locks cost and save them.
local function victimTable(lines: { string }, groups: { [string]: { Record } }, names: { string })
	table.insert(
		lines,
		"| Profile | Bots | Targeted per bot | Stolen from per bot | Lost income/s per theft | Lost sell value per bot | Locks bought per bot | Lock spend per bot | Lock spend / earned | Locked share of online time | Est. loss a lock prevents (per bot) |"
	)
	table.insert(lines, "|---|---|---|---|---|---|---|---|---|---|---|")
	for _, name in names do
		local rs = groups[name]
		local n = #rs
		local function total(pick: (Record) -> number): number
			local t = 0
			for _, r in rs do
				t += pick(r)
			end
			return t
		end
		local targeted = total(function(r)
			return r.stats.targeted
		end)
		local stolen = total(function(r)
			return r.stats.stolenFrom
		end)
		local lossIncome = total(function(r)
			return r.stats.stolenIncome
		end)
		local lossSell = total(function(r)
			return r.stats.stolenSell
		end)
		local locks = total(function(r)
			return r.stats.lockBuys
		end)
		local spent = total(function(r)
			return r.stats.lockSpent
		end)
		local earned = total(function(r)
			return r.final.earned
		end)
		local locked = total(function(r)
			return r.stats.lockedSeconds
		end)
		local unlocked = total(function(r)
			return r.stats.unlockedSeconds
		end)
		-- Thefts per unlocked online second, applied to the seconds the base was locked: what the locks held back.
		local prevented = ratio(lossSell, unlocked) * locked
		table.insert(
			lines,
			`| {name} | {n} | {string.format("%.1f", targeted / n)} | {string.format("%.1f", stolen / n)} | {money(
				ratio(lossIncome, stolen)
			)} | {money(lossSell / n)} | {string.format("%.1f", locks / n)} | {money(spent / n)} | {string.format(
				"%.2f%%",
				ratio(spent, earned) * 100
			)} | {string.format("%.0f%%", ratio(locked, locked + unlocked) * 100)} | {money(prevented / n)} |`
		)
	end
end

function Report.markdown(records: { Record }, meta: Meta): string
	local groups = byProfile(records)
	local names = profilesIn(groups)
	local lines: { string } = {}
	local mixText = {}
	for _, name in names do
		table.insert(mixText, `{botCount(meta, name)} {name}`)
	end
	table.insert(lines, "# Steal a Slime pacing")
	table.insert(lines, "")
	table.insert(
		lines,
		`{#meta.seeds} seeds x one server of {table.concat(mixText, ", ")} bots, {meta.days} days, players show up over the first {meta.stagger} days. `
			.. "Median (10th-90th percentile). A row only counts players who got that far."
	)

	table.insert(lines, "")
	table.insert(lines, "## After N hours of play")
	table.insert(lines, "")
	local rows = {}
	for _, name in names do
		for i, h in meta.checkpoints do
			local snaps = {}
			for _, r in groups[name] do
				if r.hours[i] then
					table.insert(snaps, r.hours[i])
				end
			end
			if #snaps > 0 then
				table.insert(rows, { name = name, key = `{plain(h)}h`, snaps = snaps })
			end
		end
	end
	snapTable(lines, "After", rows)

	table.insert(lines, "")
	table.insert(lines, "## After N calendar days (offline income included)")
	table.insert(lines, "")
	rows = {}
	for _, name in names do
		for d = 1, meta.days do
			local snaps = {}
			for _, r in groups[name] do
				if r.days[d] then
					table.insert(snaps, r.days[d])
				end
			end
			if #snaps > 0 then
				table.insert(rows, { name = name, key = `day {d}`, snaps = snaps })
			end
		end
	end
	snapTable(lines, "After", rows)

	table.insert(lines, "")
	table.insert(lines, "## Time to reach (played hours / calendar days, share of players who got there)")
	table.insert(lines, "")
	local header = { "| Milestone |" }
	local rule = { "|---|" }
	for _, name in names do
		table.insert(header, ` {name} |`)
		table.insert(rule, "---|")
	end
	table.insert(lines, table.concat(header))
	table.insert(lines, table.concat(rule))
	local function milestoneRow(label: string, pick: (Record) -> Snap?)
		local cells = { `| {label} |` }
		local anyone = false
		for _, name in names do
			local snaps = {}
			for _, r in groups[name] do
				local s = pick(r)
				if s then
					table.insert(snaps, s)
				end
			end
			anyone = anyone or #snaps > 0
			local share = math.floor(#snaps / #groups[name] * 100 + 0.5)
			if #snaps == 0 then
				table.insert(cells, " - |")
			else
				local days = Report.percentile(field(snaps, "days"), 0.5) :: number
				table.insert(
					cells,
					` {Report.spread(field(snaps, "played"), hours)} / day {string.format("%.1f", days)}, {share}% |`
				)
			end
		end
		if anyone then
			table.insert(lines, table.concat(cells))
		end
		return anyone
	end
	milestoneRow("Tutorial done", function(r)
		return r.tutorialAt
	end)
	for level = 1, Config.MAX_REBIRTHS do
		if not milestoneRow(`Rebirth {level}`, function(r)
			return r.rebirthAt[level]
		end) then
			break
		end
	end

	table.insert(lines, "")
	table.insert(lines, "## Totals per player at the end")
	table.insert(lines, "")
	table.insert(
		lines,
		"| Profile | Players | Played | Rebirths | Total earned | Offline share | Steal tries | Steals | Slapped back | Stolen from | Slaps given | Blocked joins |"
	)
	table.insert(lines, "|---|---|---|---|---|---|---|---|---|---|---|---|")
	for _, name in names do
		local rs = groups[name]
		local function stat(key: string): { number }
			local out = {}
			for _, r in rs do
				table.insert(out, (r.stats :: any)[key])
			end
			return out
		end
		local finals = {}
		local offlineShare = {}
		for _, r in rs do
			table.insert(finals, r.final)
			table.insert(offlineShare, if r.final.earned > 0 then r.stats.offlineCash / r.final.earned * 100 else 0)
		end
		table.insert(
			lines,
			`| {name} | {#rs} | {Report.spread(field(finals, "played"), hours)} | {Report.spread(
				field(finals, "rebirths")
			)} | {Report.spread(field(finals, "earned"), money)} | {Report.spread(offlineShare, function(p)
				return string.format("%.0f%%", p)
			end)} | {Report.spread(stat("stealTries"))} | {Report.spread(stat("steals"))} | {Report.spread(
				stat("slapped")
			)} | {Report.spread(stat("stolenFrom"))} | {Report.spread(stat("slaps"))} | {Report.spread(
				stat("blockedJoins")
			)} |`
		)
	end
	table.insert(lines, "")
	table.insert(lines, "## Other milestones (played hours / calendar days, share of players who got there)")
	table.insert(lines, "")
	milestoneTable(lines, groups, names)
	table.insert(lines, "")
	table.insert(lines, "## Where the cash came from and went (share of the profile's total)")
	table.insert(lines, "")
	ledgerTable(lines, groups, names)
	table.insert(lines, "## Trips: farming against stealing")
	table.insert(lines, "")
	tripTable(lines, groups, names)
	table.insert(lines, "")
	flipTable(lines, groups, names)
	table.insert(lines, "## Victims and locks")
	table.insert(lines, "")
	victimTable(lines, groups, names)
	table.insert(lines, "")
	return table.concat(lines, "\n")
end

-- NaN and infinity have no JSON form: they are left out.
local function clean(value: any): any
	if type(value) == "number" then
		return if value ~= value or value == math.huge or value == -math.huge then nil else value
	elseif type(value) == "table" then
		local out = {}
		for k, v in value do
			out[k] = clean(v)
		end
		return out
	end
	return value
end

local function snaps(map: { [number]: Snap }, keyName: string): { any }
	local keys = {}
	for k in map do
		table.insert(keys, k)
	end
	table.sort(keys)
	local out = {}
	for _, k in keys do
		local row = table.clone(map[k]) :: any
		row[keyName] = k
		table.insert(out, row)
	end
	return out
end

-- Everything per bot as plain tables for net.jsonEncode: time series, milestones, ledger, steal events.
function Report.json(records: { Record }, meta: Meta): any
	local bots = {}
	for _, r in records do
		table.insert(bots, {
			seed = r.seed,
			id = r.id,
			profile = r.profile,
			joinDay = r.joinDay,
			plannedSeconds = r.planned,
			final = r.final,
			tutorial = r.tutorialAt,
			milestones = r.milestones,
			rebirths = snaps(r.rebirthAt, "level"),
			rebirthLog = r.rebirthLog,
			checkpoints = snaps(r.hours, "index"),
			days = snaps(r.days, "day"),
			series = r.series,
			earnedBy = r.earnedBy,
			spentBy = r.spentBy,
			stats = r.stats,
			stealEvents = r.events,
		})
	end
	return clean({
		meta = {
			seeds = meta.seeds,
			days = meta.days,
			mix = meta.mix,
			late = meta.late,
			stagger = meta.stagger,
			checkpoints = meta.checkpoints,
		},
		bots = bots,
	})
end

return Report
