--!strict
-- Runs the whole Lune suite with EVERY Config.FEATURES flag forced on (or off), without touching
-- the checked-in defaults. Config.FEATURES is frozen at load, so this copies the game into a temp
-- dir, rewrites the flag lines of that copy's Config and runs `lune run tests` there.
-- The child run sees SLIME_FORCE_FEATURES=on|off (tests/Fixtures.forcedFeatures) so specs that pin the
-- shipped defaults can tell. SPEC_FILTER=<substring> limits the specs, as with a plain `lune run tests`.
-- Usage (from games/steal-a-slime): lune run scripts/test-flags <on|off>
local fs = require("@lune/fs")
local process = require("@lune/process")

local mode = process.args[1]
if mode ~= "on" and mode ~= "off" then
	print("usage: lune run scripts/test-flags <on|off>")
	process.exit(2)
end
local value = if mode == "on" then "true" else "false"

local SKIP = { [".cache"] = true, [".git"] = true, ["build.rbxlx"] = true }

local function copyDir(from: string, to: string)
	fs.writeDir(to)
	for _, name in fs.readDir(from) do
		if not SKIP[name] then
			local source, target = `{from}/{name}`, `{to}/{name}`
			if fs.isDir(source) then
				copyDir(source, target)
			else
				fs.writeFile(target, fs.readFile(source))
			end
		end
	end
end

-- Same depth as in the repo (games/steal-a-slime) so specs that read ../../shared or ../../tools still
-- resolve; those trees are large, so the repo-root siblings are symlinked rather than copied.
local tmp = `{process.env.TMPDIR or "/tmp"}/steal-a-slime-flags-{mode}-{os.time()}-{math.floor(os.clock() * 1e6)}`
local root = `{tmp}/games/steal-a-slime`
copyDir(".", root)
local repo = process.exec("realpath", { "../.." }).stdout:gsub("%s+$", "")
local links = {}
for _, name in fs.readDir("../..") do
	if name ~= "games" and name ~= ".git" then
		local link = process.exec("ln", { "-s", `{repo}/{name}`, `{tmp}/{name}` })
		assert(link.ok, link.stderr)
		table.insert(links, `{tmp}/{name}`)
	end
end

local configPath = `{root}/src/shared/Config.luau`
local config = fs.readFile(configPath)
local first, last = string.find(config, "\n\tFEATURES = table.freeze({\n", 1, true)
assert(first and last, "Config.FEATURES block not found")
local close = string.find(config, "\n\t}),", last, true)
assert(close, "Config.FEATURES block not closed")
local body, count = string.gsub(string.sub(config, last, close), "(\n\t\t[%w_]+ = )%a+(,)", `%1{value}%2`)
assert(count > 0, "no FEATURES flags rewritten")
fs.writeFile(configPath, string.sub(config, 1, last - 1) .. body .. string.sub(config, close + 1))
print(`FEATURES forced {value} ({count} flags) in {root}`)

-- Own TMPDIR: parallel runs never share spec temp files.
local result = process.exec(
	"lune",
	{ "run", "tests" },
	{ cwd = root, stdio = "inherit", env = { SLIME_FORCE_FEATURES = mode, TMPDIR = tmp } }
)
for _, link in links do -- unlink first: removeDir must never follow a link into the repo
	process.exec("rm", { link })
end
fs.removeDir(tmp)
process.exit(if result.ok then 0 else 1)
