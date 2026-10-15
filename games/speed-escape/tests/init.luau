--!strict
-- Entry point for `lune run tests`: loads every *.spec.luau in this
-- directory, runs the collected tests and exits non-zero on failure.

local fs = require("@lune/fs")
local process = require("@lune/process")

local TestRunner = require("@self/TestRunner")

local specs = {}
for _, name in fs.readDir("tests") do
	local module = string.match(name, "^(.+%.spec)%.luau$")
	if module then
		table.insert(specs, module)
	end
end
table.sort(specs)

for _, module in specs do
	print(`{module}`)
	require(`@self/{module}`)
end

local failures = TestRunner.run()
process.exit(if failures > 0 then 1 else 0)
