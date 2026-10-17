--!strict
-- Entry point for `lune run tests`: loads every *.spec.luau under tests/,
-- recursing into subfolders (tests/ui, ...), runs the collected tests and
-- exits non-zero on failure. Subfolder init.luau runners are skipped; their
-- specs are loaded directly and share this TestRunner.

local fs = require("@lune/fs")
local process = require("@lune/process")

local ForcedFlags = require("@self/ForcedFlags")
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
		local ok, err = pcall(require, `@self/{module}`)
		if not ok then
			loadFailures += 1
			print(`  FAIL  {module} failed to load: {err}`)
		end
	end
end

local failures = TestRunner.run() + loadFailures
process.exit(if failures > 0 then 1 else 0)
