--!strict
--[[
	Profiler (pure, FEATURES.ServerProfiler, CONTRACT.md §25)

	Rolling per-system timings (os.clock deltas in ms) over the last Config.PROFILER.WINDOW samples,
	named counters (remote calls, ...) turned into per-second rates, and a compact one-line summary
	every Config.PROFILER.LOG_INTERVAL seconds. A system whose p95 is over its Config.PROFILER.BUDGET_MS
	entry is listed in the warnings. Disabled = every call is a no-op (no table writes, no clock reads).
]]

local Shared = if script then (game:GetService("ReplicatedStorage") :: any).Shared else nil
local Config = if Shared then require(Shared.Config) else require("../shared/Config")

export type Series = { samples: { number }, next: number, count: number, max: number }
export type Profiler = {
	enabled: boolean,
	window: number,
	interval: number,
	budgets: { [string]: number },
	clock: () -> number,
	series: { [string]: Series },
	counters: { [string]: number },
	order: { string },
	lastFlushAt: number,
}
export type Overrides = { window: number?, interval: number?, budgets: { [string]: number }? }
export type Stats = { avg: number, p95: number, max: number, count: number }

local Profiler = {}

function Profiler.new(enabled: boolean?, clock: (() -> number)?, overrides: Overrides?): Profiler
	local cfg = Config.PROFILER
	local o: Overrides = overrides or {}
	local clockFn = clock or os.clock
	return {
		enabled = if enabled == nil then Config.FEATURES.ServerProfiler == true else enabled,
		window = o.window or cfg.WINDOW,
		interval = o.interval or cfg.LOG_INTERVAL,
		budgets = o.budgets or cfg.BUDGET_MS,
		clock = clockFn,
		series = {},
		counters = {},
		order = {},
		lastFlushAt = clockFn(),
	}
end

-- Adds one sample (ms) to a system's ring buffer.
function Profiler.record(p: Profiler, name: string, ms: number)
	if not p.enabled then
		return
	end
	local s = p.series[name]
	if not s then
		s = { samples = {}, next = 1, count = 0, max = 0 }
		p.series[name] = s
		table.insert(p.order, name)
	end
	local series = s :: Series
	series.samples[series.next] = ms
	series.next = series.next % p.window + 1
	series.count = math.min(series.count + 1, p.window)
end

-- Runs fn(...) and records its duration under `name`; disabled = a plain call.
function Profiler.time(p: Profiler, name: string, fn: (...any) -> ...any, ...: any): ...any
	if not p.enabled then
		return fn(...)
	end
	local t0 = p.clock()
	local results = table.pack(fn(...))
	Profiler.record(p, name, (p.clock() - t0) * 1000)
	return table.unpack(results, 1, results.n)
end

-- Bumps a named counter (remote calls, ...); the summary reports it per second.
function Profiler.count(p: Profiler, key: string, n: number?)
	if not p.enabled then
		return
	end
	p.counters[key] = (p.counters[key] or 0) + (n or 1)
end

-- avg / p95 (nearest rank) / max over the current window; nil without samples.
function Profiler.stats(p: Profiler, name: string): Stats?
	local s = p.series[name]
	if not s or s.count == 0 then
		return nil
	end
	local sorted, sum, max = {}, 0, 0
	for i = 1, s.count do
		local v = s.samples[i]
		sorted[i] = v
		sum += v
		max = math.max(max, v)
	end
	table.sort(sorted)
	return {
		avg = sum / s.count,
		p95 = sorted[math.max(1, math.ceil(s.count * 0.95))],
		max = max,
		count = s.count,
	}
end

-- Systems whose p95 is above their budget, worst first: { { name, p95, budget } }.
function Profiler.overBudget(p: Profiler): { { name: string, p95: number, budget: number } }
	local out = {}
	for _, name in p.order do
		local budget = p.budgets[name]
		local st = Profiler.stats(p, name)
		if budget and st and st.p95 > budget then
			table.insert(out, { name = name, p95 = st.p95, budget = budget })
		end
	end
	table.sort(out, function(a, b)
		return a.p95 / a.budget > b.p95 / b.budget
	end)
	return out
end

-- One compact line: "[Profiler] | GameLoop 0.12/0.30ms | Heartbeat 0.8/1.9ms | inst=1234 | Request=3.2/s".
-- `gauges` are plain numbers (instance / part counts) printed as key=value.
function Profiler.summary(p: Profiler, elapsed: number, gauges: { [string]: number }?): string
	local parts = { "[Profiler]" }
	for _, name in p.order do
		local st = Profiler.stats(p, name)
		if st then
			table.insert(parts, string.format("%s %.2f/%.2fms", name, st.avg, st.p95))
		end
	end
	local gaugeKeys = {}
	if gauges then
		for key in gauges do
			table.insert(gaugeKeys, key)
		end
	end
	table.sort(gaugeKeys)
	for _, key in gaugeKeys do
		table.insert(parts, string.format("%s=%d", key, (gauges :: { [string]: number })[key]))
	end
	local counterKeys = {}
	for key in p.counters do
		table.insert(counterKeys, key)
	end
	table.sort(counterKeys)
	for _, key in counterKeys do
		table.insert(parts, string.format("%s=%.1f/s", key, p.counters[key] / math.max(elapsed, 1e-6)))
	end
	return table.concat(parts, " | ")
end

-- Called every frame (cheap). Once per interval returns (line, warnings) and resets the counters;
-- otherwise nil. `gauges` is a function so instance counts are only taken when a line is due.
function Profiler.flush(p: Profiler, gauges: (() -> { [string]: number })?): (string?, { string }?)
	if not p.enabled then
		return nil, nil
	end
	local t = p.clock()
	local elapsed = t - p.lastFlushAt
	if elapsed < p.interval then
		return nil, nil
	end
	p.lastFlushAt = t
	local line = Profiler.summary(p, elapsed, if gauges then gauges() else nil)
	local warnings = {}
	for _, o in Profiler.overBudget(p) do
		table.insert(warnings, string.format("[Profiler] %s p95 %.2fms over budget %.2fms", o.name, o.p95, o.budget))
	end
	table.clear(p.counters)
	return line, warnings
end

return Profiler
