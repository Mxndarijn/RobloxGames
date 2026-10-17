--!strict
-- Tiny test framework: describe / it / expect. Collects results; `run`
-- prints a summary and returns the number of failures.

type Test = { name: string, fn: () -> () }

local ForcedFlags = require("./ForcedFlags")

local TestRunner = {}

local tests: { Test } = {}
local prefix: { string } = {}

-- scripts/test-flags forces every Config.FEATURES flag ("on" / "off") via SLIME_FORCE_FEATURES; tests/init (Lune only)
-- reads the env var and calls setForced before any spec loads. No @lune require here: stage-specs ships this module to cloud tests.
local forced: string? = nil
local skips: { [string]: string } = ForcedFlags.needOff -- default mode; setForced replaces it
local skipped = 0

function TestRunner.setForced(mode: string?)
	forced = mode
	if mode == "off" then
		skips = ForcedFlags.off
	else
		skips = table.clone(ForcedFlags.needOff)
		if mode == "on" then
			for name, why in ForcedFlags.on do
				skips[name] = why
			end
		end
	end
end

-- Tests listed in tests/ForcedFlags for the forced mode are not run (counted and printed as SKIP).
local function skipReason(name: string): string?
	return skips[name] or skips[string.match(name, "^(.-) > ") or name]
end

function TestRunner.describe(name: string, body: () -> ())
	table.insert(prefix, name)
	body()
	table.remove(prefix)
end

function TestRunner.it(name: string, fn: () -> ())
	local path = table.clone(prefix)
	table.insert(path, name)
	local full = table.concat(path, " > ")
	local reason = skipReason(full)
	if reason then
		skipped += 1
		print(`  SKIP  {full} ({if forced then `FEATURES forced {forced}` else "default FEATURES"}; needs {reason})`)
		return
	end
	table.insert(tests, { name = full, fn = fn })
end

local function fmt(value: any): string
	if type(value) == "string" then
		return string.format("%q", value)
	end
	return tostring(value)
end

function TestRunner.expect(actual: any)
	local matchers = {}

	function matchers.toBe(expected: any)
		if actual ~= expected then
			error(`expected {fmt(expected)}, got {fmt(actual)}`, 2)
		end
	end

	function matchers.toBeCloseTo(expected: number, epsilon: number?)
		local eps = epsilon or 1e-6
		if type(actual) ~= "number" or math.abs(actual - expected) > eps then
			error(`expected {fmt(actual)} to be within {eps} of {expected}`, 2)
		end
	end

	function matchers.toBeNil()
		if actual ~= nil then
			error(`expected nil, got {fmt(actual)}`, 2)
		end
	end

	function matchers.toBeTruthy()
		if not actual then
			error(`expected truthy, got {fmt(actual)}`, 2)
		end
	end

	function matchers.toBeFalsy()
		if actual then
			error(`expected falsy, got {fmt(actual)}`, 2)
		end
	end

	function matchers.toEqual(expected: any)
		local function deepEqual(a: any, b: any): boolean
			if type(a) ~= "table" or type(b) ~= "table" then
				return a == b
			end
			for k, v in a do
				if not deepEqual(v, b[k]) then
					return false
				end
			end
			for k in b do
				if a[k] == nil then
					return false
				end
			end
			return true
		end
		if not deepEqual(actual, expected) then
			error(`tables differ: expected {fmt(expected)}, got {fmt(actual)}`, 2)
		end
	end

	function matchers.toThrow()
		local ok = pcall(actual)
		if ok then
			error("expected function to throw", 2)
		end
	end

	return matchers
end

function TestRunner.run(): number
	local passed, failed = 0, 0
	for _, test in tests do
		local ok, err = pcall(test.fn)
		if ok then
			passed += 1
			print(`  PASS  {test.name}`)
		else
			failed += 1
			print(`  FAIL  {test.name}\n        {err}`)
		end
	end
	print(
		`\n{passed} passed, {failed} failed, {passed + failed} total`
			.. if skipped > 0 then `, {skipped} skipped (forced {forced})` else ""
	)
	table.clear(tests)
	return failed
end

return TestRunner
