--!strict
-- Tiny test framework: describe / it / expect. Collects results; `run`
-- prints a summary and returns the number of failures.

type Test = { name: string, fn: () -> () }

local TestRunner = {}

local tests: { Test } = {}
local prefix: { string } = {}

function TestRunner.describe(name: string, body: () -> ())
	table.insert(prefix, name)
	body()
	table.remove(prefix)
end

function TestRunner.it(name: string, fn: () -> ())
	local path = table.clone(prefix)
	table.insert(path, name)
	table.insert(tests, { name = table.concat(path, " > "), fn = fn })
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
	print(`\n{passed} passed, {failed} failed, {passed + failed} total`)
	table.clear(tests)
	return failed
end

return TestRunner
