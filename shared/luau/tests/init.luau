--!strict
-- Entry point for `lune run tests` (run from shared/luau): loads every *.spec.luau under tests/, runs them and
-- exits non-zero on failure. SPEC_FILTER=<substring> runs only the matching specs.

local fs = require("@lune/fs")
local process = require("@lune/process")

-- In an init.luau, "./" is the folder that contains tests/ (shared/luau).
local TestRunner = require("./testing/TestRunner")

local ROOT = "tests"

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

local filter = process.env.SPEC_FILTER
local loadFailures = 0
for _, module in specs do
	if filter == nil or filter == "" or string.find(module, filter, 1, true) then
		print(module)
		local ok, err = pcall(require, `@self/{module}`)
		if not ok then
			loadFailures += 1
			print(`  FAIL  {module} failed to load: {err}`)
		end
	end
end

local failures = TestRunner.run() + loadFailures
process.exit(if failures > 0 then 1 else 0)
