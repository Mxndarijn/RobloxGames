--!strict
-- PR gate budget step: client UI performance budget (games/steal-a-slime/ui-perf-budget.json).
-- Run from games/steal-a-slime (tools/pr-gate/budget.sh does):
--   lune run ../../tools/pr-gate/ui_perf_check.luau
-- Prints the measured numbers; exits 1 when one is over its budget, or under it (ratchet: lower the
-- budget in the same PR). Measurement and rules live in tests/ui/PerfMeasure.luau.
local fs = require("@lune/fs")
local process = require("@lune/process")
local serde = require("@lune/serde")

local PerfMeasure = require("../../games/steal-a-slime/tests/ui/PerfMeasure")

local budget = serde.decode("json", fs.readFile("ui-perf-budget.json")) :: any
local result = PerfMeasure.measure()
local keys = {}
for key in budget.limits do
	table.insert(keys, key)
end
table.sort(keys)
for _, key in keys do
	print(`  ui-perf {key}: {result[key]} / {budget.limits[key]}`)
end
local problems = PerfMeasure.compare(result, budget.limits)
for _, problem in problems do
	print(`  ui-perf FAIL {problem}`)
end
if #problems > 0 then
	process.exit(1)
end
