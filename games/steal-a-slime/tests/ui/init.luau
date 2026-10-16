--!strict
-- UI-only entry point for `lune run tests/ui`: runs every tests/ui/*.spec.luau
-- (pure UI helpers). These specs also run under `lune run tests`, which
-- recurses into subfolders (and skips this runner).
-- `lune run tests/ui Layout ScrollLists` runs only the specs whose name
-- contains one of the arguments (tools/pr-gate/layout.sh).

local fs = require("@lune/fs")
local process = require("@lune/process")

local TestRunner = require("./TestRunner")

local function wanted(module: string): boolean
	if #process.args == 0 then
		return true
	end
	for _, arg in process.args do
		if string.find(module, arg, 1, true) then
			return true
		end
	end
	return false
end

local specs = {}
for _, name in fs.readDir("tests/ui") do
	local module = string.match(name, "^(.+%.spec)%.luau$")
	if module and wanted(module) then
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
