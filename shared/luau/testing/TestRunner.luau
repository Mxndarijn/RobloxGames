--!strict
--[[
	TestRunner: describe / it / expect for Lune specs. Collects tests while specs load; `run` executes them,
	prints one line per test and a summary, and returns the number of failures.

	Games can reuse it: `setSkips` takes a map of full test names (or describe prefixes) to a reason, for runs
	where some tests cannot apply (for example a forced feature-flag mode).
]]

type Test = { name: string, fn: () -> () }

local TestRunner = {}

local tests: { Test } = {}
local prefix: { string } = {}
local skips: { [string]: string } = {}
local skipped = 0

function TestRunner.setSkips(map: { [string]: string }?)
	skips = map or {}
end

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
		print(`  SKIP  {full} ({reason})`)
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
			.. if skipped > 0 then `, {skipped} skipped` else ""
	)
	table.clear(tests)
	skipped = 0
	return failed
end

return TestRunner
