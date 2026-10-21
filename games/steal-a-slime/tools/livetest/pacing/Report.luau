--!strict
--[[
	Turns the bot Records of every seed into Markdown tables, per profile:
	where players are after N played hours, after N calendar days, how long
	each milestone takes, and where their cash came from.

	Numbers are medians; brackets hold the 10th-90th percentile. A row only
	counts the bots that got that far ("players"), so late rows are biased
	toward the bots that played most.
]]

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

local function profilesIn(groups: { [string]: { Record } }): { string }
	local out = {}
	for _, name in Profiles.names() do
		if groups[name] then
			table.insert(out, name)
		end
	end
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
}

function Report.markdown(records: { Record }, meta: Meta): string
	local groups = byProfile(records)
	local names = profilesIn(groups)
	local lines: { string } = {}
	local mixText = {}
	for _, name in names do
		table.insert(mixText, `{meta.mix[name]} {name}`)
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
	return table.concat(lines, "\n")
end

return Report
