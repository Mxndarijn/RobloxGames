--!strict
-- UI-only entry point for `lune run tests/ui`: runs every tests/ui/*.spec.luau
-- (pure UI helpers). These specs also run under `lune run tests`, which
-- recurses into subfolders (and skips this runner).

local fs = require("@lune/fs")
local process = require("@lune/process")

local TestRunner = require("./TestRunner")

local specs = {}
for _, name in fs.readDir("tests/ui") do
	local module = string.match(name, "^(.+%.spec)%.luau$")
	if module then
		table.insert(specs, module)
	end
end
table.sort(specs)

for _, module in specs do
	print(`ui/{module}`)
	require(`@self/{module}`)
end

local failures = TestRunner.run()
process.exit(if failures > 0 then 1 else 0)
