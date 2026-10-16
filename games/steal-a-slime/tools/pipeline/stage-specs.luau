--!strict
-- lune run tools/pipeline/stage-specs <outDir>   (from the game root)
--
-- Copies tests/*.luau into <outDir> for the cloud test place
-- (tools/pipeline/cloud-test.sh mounts it at ServerStorage.CloudTests).
-- The specs use Lune string requires ("../src/shared/Config", "./Fixtures").
-- Those paths don't exist in the place, so each one is rewritten to the
-- instance the place really has, the same mapping as default.project.json:
--
--   ../src/shared/X         -> ReplicatedStorage.Shared.X
--   ../src/server/X         -> ServerScriptService.Server.X
--   ../src/visuals/shared/X -> ReplicatedStorage.Visuals.X
--   ../src/visuals/client/X -> StarterPlayer.StarterPlayerScripts.VisualsClient.X
--   ../src/ui/X             -> StarterPlayer.StarterPlayerScripts.UI.X
--   ./X                     -> script.Parent.X
--
-- The specs then test the modules the place ships, not copies.
-- A file is left out if it needs Lune (@lune/*, ../tools, ../scripts, any
-- other path) or names a DataStore API (CLAUDE.md hard rule). So is any spec
-- that requires a left-out helper. Writes <outDir>/../skipped.json:
-- [{ spec, reason }].
--
-- TestRunner gets one extra line, `TestRunner._tests = tests`, so
-- tools/pipeline/cloud-tests.luau can run the tests itself and report each
-- failure by name.
--
-- A ModuleScript must return exactly one value, but specs are side-effect
-- scripts that fall off the end. Each staged *.spec without a top-level
-- return gets `return true` appended, so require() doesn't fail after the
-- tests have registered.

local fs = require("@lune/fs")
local process = require("@lune/process")
local serde = require("@lune/serde")

local outDir = process.args[1]
assert(outDir, "usage: lune run tools/pipeline/stage-specs <outDir>")

local ROOTS = {
	{ "../src/shared/", `game:GetService("ReplicatedStorage").Shared` },
	{ "../src/server/", `game:GetService("ServerScriptService").Server` },
	{ "../src/visuals/shared/", `game:GetService("ReplicatedStorage").Visuals` },
	{ "../src/visuals/client/", `game:GetService("StarterPlayer").StarterPlayerScripts.VisualsClient` },
	{ "../src/ui/", `game:GetService("StarterPlayer").StarterPlayerScripts.UI` },
	{ "./", "script.Parent" },
}

local FORBIDDEN =
	{ "DataStoreService", "GetDataStore", "GetOrderedDataStore", "UpdateAsync", "SetAsync", "RemoveAsync" }

local function instancePath(path: string): string?
	for _, root in ROOTS do
		local prefix, base = root[1], root[2]
		if string.sub(path, 1, #prefix) == prefix then
			local rest = string.sub(path, #prefix + 1)
			if rest == "" or string.find(rest, "%.%.") then
				return nil
			end
			local expr = base
			for _, part in string.split(rest, "/") do
				expr ..= `[{string.format("%q", part)}]`
			end
			return expr
		end
	end
	return nil
end

-- Returns the rewritten source, or nil + reason.
local function rewrite(source: string): (string?, string?)
	for _, word in FORBIDDEN do
		if string.find(source, word, 1, true) then
			return nil, `mentions {word}`
		end
	end
	local bad: string? = nil
	local out = string.gsub(source, 'require%(%s*"([^"]*)"%s*%)', function(path: string)
		local expr = instancePath(path)
		if not expr then
			bad = bad or path
			return `require("{path}")`
		end
		return `require({expr})`
	end)
	if bad then
		return nil, `requires "{bad}" (Lune only)`
	end
	return out, nil
end

-- Local helper modules a file requires ("./X").
local function localDeps(source: string): { string }
	local deps = {}
	for name in string.gmatch(source, 'require%(%s*"%./([^"/]+)"%s*%)') do
		table.insert(deps, name)
	end
	return deps
end

local files: { [string]: string } = {}
for _, name in fs.readDir("tests") do
	local module = string.match(name, "^(.+)%.luau$")
	if module and module ~= "init" and fs.isFile(`tests/{name}`) then
		files[module] = fs.readFile(`tests/{name}`)
	end
end

local staged: { [string]: string } = {}
local reasons: { [string]: string } = {}
for module, source in files do
	local out, reason = rewrite(source)
	if out then
		staged[module] = out
	else
		reasons[module] = reason :: string
	end
end

-- Drop files whose local helpers were dropped, until nothing changes.
local changed = true
while changed do
	changed = false
	for module in staged do
		for _, dep in localDeps(files[module]) do
			if not staged[dep] then
				staged[module] = nil
				reasons[module] = `needs ./{dep} ({reasons[dep] or "missing"})`
				changed = true
				break
			end
		end
	end
end

local runner = staged.TestRunner
assert(runner, `TestRunner can't be staged: {reasons.TestRunner}`)
local patched, count =
	string.gsub(runner, "\nreturn TestRunner%s*$", "\nTestRunner._tests = tests\nreturn TestRunner\n")
assert(count == 1, "tests/TestRunner.luau no longer ends with `return TestRunner`")
staged.TestRunner = patched

-- True if the last code line (skipping blanks and -- comments) is a return.
local function endsWithReturn(source: string): boolean
	local lines = string.split(source, "\n")
	for i = #lines, 1, -1 do
		local line = string.gsub(string.gsub(lines[i], "%-%-.*$", ""), "^%s+", "")
		if string.match(line, "%S") then
			return string.match(line, "^return%f[%W]") ~= nil
		end
	end
	return false
end

for module, source in staged do
	if string.match(module, "%.spec$") and not endsWithReturn(source) then
		staged[module] = string.gsub(source, "%s*$", "") .. "\n\nreturn true\n"
	end
end

if fs.isDir(outDir) then
	fs.removeDir(outDir)
end
fs.writeDir(outDir)
local specs = 0
for module, source in staged do
	fs.writeFile(`{outDir}/{module}.luau`, source)
	if string.match(module, "%.spec$") then
		specs += 1
	end
end

local skipped = {}
for module, reason in reasons do
	if string.match(module, "%.spec$") then
		table.insert(skipped, { spec = module, reason = reason })
	end
end
table.sort(skipped, function(a, b)
	return a.spec < b.spec
end)
local parent = string.match(outDir, "^(.*)/[^/]+/?$") or "."
fs.writeFile(`{parent}/skipped.json`, serde.encode("json", skipped, true))
print(`staged {specs} specs into {outDir}, skipped {#skipped} (Lune only)`)
