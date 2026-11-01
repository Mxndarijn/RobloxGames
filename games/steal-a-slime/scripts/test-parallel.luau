--!strict
-- Runs the Lune suite (`lune run tests`) split over several Lune processes at once, one per shard
-- (SPEC_SHARD, tests/Shard, weights in tests/SpecWeights). Each shard gets its own TMPDIR, so specs that
-- write place files never collide. Prints each shard's output when it ends, then every FAIL line again
-- and one summary line in the same form as `lune run tests`. Exits 1 if any shard fails.
-- Usage (from games/steal-a-slime): lune run scripts/test-parallel [shards]   (TEST_PART=1/2 for one of two machines)
--   shards defaults to TEST_JOBS, else the CPU count capped at 8. SPEC_FILTER, SPEC_TIMINGS and
--   SLIME_FORCE_FEATURES pass through to every shard.
local DateTime = require("@lune/datetime")
local fs = require("@lune/fs")
local process = require("@lune/process")
local task = require("@lune/task")

local function cpuCount(): number
	local windows = tonumber(process.env.NUMBER_OF_PROCESSORS)
	if windows then
		return windows
	end
	local ok, result = pcall(process.exec, "nproc")
	if ok and result.ok then
		return tonumber((result.stdout:gsub("%s+", ""))) or 2
	end
	return 2
end

local shards = tonumber(process.args[1] or process.env.TEST_JOBS or "") or math.min(cpuCount(), 8)
shards = math.max(1, math.floor(shards))

-- TEST_PART=<i>/<m> splits the suite over m machines (CI matrix jobs): the suite is cut into
-- shards * m shards and this machine runs its own `shards` of them.
local part, parts = 1, 1
if process.env.TEST_PART and process.env.TEST_PART ~= "" then
	local i, m = string.match(process.env.TEST_PART, "^(%d+)/(%d+)$")
	assert(i and m, `TEST_PART must look like 1/2, got {process.env.TEST_PART}`)
	part, parts = tonumber(i) :: number, tonumber(m) :: number
	assert(part >= 1 and part <= parts, `TEST_PART {part}/{parts} is out of range`)
end
local shardCount = shards * parts

local base = process.env.TMPDIR or process.env.TEMP or "/tmp"
local root = `{base}/slime-tests-{os.time()}-{math.random(1, 1e9)}`
fs.writeDir(root)

local github = process.env.GITHUB_ACTIONS == "true"
local started = DateTime.now().unixTimestampMillis
local results = {}
local finished = 0

print(
	`running the Lune suite in {shards} parallel shards`
		.. if parts > 1
			then ` (part {part} of {parts}: shards {(part - 1) * shards + 1}-{part * shards} of {shardCount})`
			else ""
)

for k = 1, shards do
	task.spawn(function()
		local shard = (part - 1) * shards + k
		local tmp = `{root}/shard-{shard}`
		fs.writeDir(tmp)
		local t0 = DateTime.now().unixTimestampMillis
		local result = process.exec("lune", { "run", "tests" }, {
			env = { SPEC_SHARD = `{shard}/{shardCount}`, TMPDIR = tmp },
		})
		local seconds = (DateTime.now().unixTimestampMillis - t0) / 1000
		local output = result.stdout .. (if result.stderr ~= "" then `\n{result.stderr}` else "")
		results[k] = { ok = result.ok, output = output, seconds = seconds }

		local title =
			`shard {shard}/{shardCount}: {if result.ok then "ok" else "FAILED"} in {string.format("%.0f", seconds)} s`
		if github then
			print(`::group::{title}`)
		else
			print(`==== {title}`)
		end
		print(output)
		if github then
			print("::endgroup::")
		end
		finished += 1
	end)
end

while finished < shards do
	task.wait(0.1)
end
pcall(fs.removeDir, root)

local passed, failed, total, skipped = 0, 0, 0, 0
local failLines = {}
local allOk = true
for k = 1, shards do
	local result = results[k]
	allOk = allOk and result.ok
	local p, f, t = string.match(result.output, "\n(%d+) passed, (%d+) failed, (%d+) total")
	if p then
		passed += tonumber(p) :: number
		failed += tonumber(f) :: number
		total += tonumber(t) :: number
		skipped += tonumber(string.match(result.output, "total, (%d+) skipped") or "0") :: number
	else
		allOk = false
		table.insert(
			failLines,
			`  FAIL  shard {(part - 1) * shards + k}/{shardCount} ended without a summary (crashed?); its output is above`
		)
	end
	for line in string.gmatch(result.output, "[^\n]+") do
		if string.find(line, "^%s*FAIL ") then
			table.insert(failLines, line)
		end
	end
end

local wall = (DateTime.now().unixTimestampMillis - started) / 1000
local times = {}
for k = 1, shards do
	table.insert(times, string.format("%.0f", results[k].seconds))
end
print(`\nshard times (s): {table.concat(times, ", ")}; wall {string.format("%.0f", wall)} s`)
if #failLines > 0 then
	print("\nfailures:")
	for _, line in failLines do
		print(line)
	end
end
local forced = process.env.SLIME_FORCE_FEATURES
print(
	`\n{passed} passed, {failed} failed, {total} total`
		.. if skipped > 0
			then `, {skipped} skipped ({if forced then `forced {forced}` else "default FEATURES"})`
			else ""
)
process.exit(if allOk then 0 else 1)
