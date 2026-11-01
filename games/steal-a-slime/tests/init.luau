--!strict
-- Entry point for `lune run tests`: loads every *.spec.luau under tests/,
-- recursing into subfolders (tests/ui, ...), runs the collected tests and
-- exits non-zero on failure. Subfolder init.luau runners are skipped; their
-- specs are loaded directly and share this TestRunner.

local DateTime = require("@lune/datetime")
local fs = require("@lune/fs")
local process = require("@lune/process")

local ForcedFlags = require("@self/ForcedFlags")
local Shard = require("@self/Shard")
local SpecWeights = require("@self/SpecWeights")
local TestRunner = require("@self/TestRunner")

local ROOT = "tests"

-- Spec module paths relative to tests/, e.g. "Carry.spec", "ui/Format.spec".
local function collect(dir: string, prefix: string, out: { string })
	for _, name in fs.readDir(dir) do
		local path = `{dir}/{name}`
		if fs.isDir(path) then
			collect(path, `{prefix}{name}/`, out)
		else
			local module = string.match(name, "^(.+%.spec)%.luau$")
			if module then
				table.insert(out, prefix .. module)
			end
		end
	end
end

local specs = {}
collect(ROOT, "", specs)
table.sort(specs)

-- SPEC_SHARD=<k>/<n> runs only shard k of n (scripts/test-parallel starts one Lune process per shard).
local shard = process.env.SPEC_SHARD
if shard and shard ~= "" then
	local k, n = string.match(shard, "^(%d+)/(%d+)$")
	assert(k and n, `SPEC_SHARD must look like 2/4, got {shard}`)
	specs = Shard.pick(specs, SpecWeights.seconds, tonumber(k) :: number, tonumber(n) :: number, SpecWeights.default)
end

-- SPEC_TIMINGS=1 runs each spec's tests right after it loads and prints `TIME <seconds> <spec>` (the
-- numbers for tests/SpecWeights). The normal run loads every spec first and then runs all tests.
local timings = process.env.SPEC_TIMINGS == "1"

-- SPEC_FILTER=<substring> runs only the matching specs (handy with scripts/test-flags).
local filter = process.env.SPEC_FILTER
local forced = process.env.SLIME_FORCE_FEATURES
TestRunner.setForced(forced)

-- A spec that throws while loading (a top-level assert) fails the run but does not hide the others.
local loadFailures = 0
for _, module in specs do
	if forced == "off" and ForcedFlags.offModules[module] then
		print(`{module} (skipped: FEATURES forced off; needs {ForcedFlags.offModules[module]})`)
	elseif filter == nil or filter == "" or string.find(module, filter, 1, true) then
		print(`{module}`)
		local wall = DateTime.now().unixTimestampMillis
		local ok, err = pcall(require, `@self/{module}`)
		if not ok then
			loadFailures += 1
			print(`  FAIL  {module} failed to load: {err}`)
		end
		if timings then
			TestRunner.flush()
			local seconds = (DateTime.now().unixTimestampMillis - wall) / 1000
			print(`TIME {string.format("%.2f", seconds)} {module}`)
		end
	end
end

local failures = TestRunner.run() + loadFailures
process.exit(if failures > 0 then 1 else 0)
