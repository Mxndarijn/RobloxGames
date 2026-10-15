--!strict
-- Entry point for `lune run tests`: loads every *.spec.luau under tests/,
-- recursing into subfolders (tests/ui, ...), runs the collected tests and
-- exits non-zero on failure. Subfolder init.luau runners are skipped; their
-- specs are loaded directly and share this TestRunner.

local fs = require("@lune/fs")
local process = require("@lune/process")

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

for _, module in specs do
	print(`{module}`)
	require(`@self/{module}`)
end

local failures = TestRunner.run()
process.exit(if failures > 0 then 1 else 0)
