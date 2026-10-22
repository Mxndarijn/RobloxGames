--!strict
-- Lune only (copies the tree, spawns lune): Config.FEATURES is frozen, so the flag-flipped mode of
-- the Consumables / StealAlerts hardening specs runs in a temp copy of src/ + tests/ (+ shared/luau/src) whose
-- Config has that one flag inverted. The hardening specs assert both modes, so each must pass flipped.
local fs = require("@lune/fs")
local process = require("@lune/process")

local TestRunner = require("./TestRunner")

local describe, it, expect = TestRunner.describe, TestRunner.it, TestRunner.expect

local FEATURES = {
	{ flag = "Consumables", spec = "ConsumablesHardening" },
	{ flag = "StealAlerts", spec = "StealAlertHardening" },
}
local SUPPORT = { "TestRunner.luau", "ForcedFlags.luau", "Fixtures.luau", "ServerFixtures.luau" }

local function copyDir(from: string, to: string)
	fs.writeDir(to)
	for _, name in fs.readDir(from) do
		local source, target = `{from}/{name}`, `{to}/{name}`
		if fs.isDir(source) then
			copyDir(source, target)
		else
			fs.writeFile(target, fs.readFile(source))
		end
	end
end

local function flipped(flag: string, spec: string): (boolean, string)
	-- The copy keeps the repo layout so `Lib` requires (../../../../shared/luau/src) still resolve.
	local base = `{process.env.TMPDIR or "/tmp"}/steal-a-slime-flags-{flag}-{os.time()}-{math.floor(os.clock() * 1e6)}`
	local root = `{base}/games/steal-a-slime`
	fs.writeDir(`{base}/games`)
	fs.writeDir(`{base}/shared/luau`)
	copyDir("../../shared/luau/src", `{base}/shared/luau/src`)
	copyDir("src", `{root}/src`)
	fs.writeDir(`{root}/tests`)
	for _, name in SUPPORT do
		fs.writeFile(`{root}/tests/{name}`, fs.readFile(`tests/{name}`))
	end
	fs.writeFile(`{root}/tests/{spec}.spec.luau`, fs.readFile(`tests/{spec}.spec.luau`))
	local configPath = `{root}/src/shared/Config.luau`
	local config = fs.readFile(configPath)
	local now = string.match(config, `\n\t\t{flag} = (%a+),`)
	assert(now == "true" or now == "false", `Config.FEATURES.{flag} not found`)
	local swapped, count =
		string.gsub(config, `(\n\t\t{flag} = )%a+(,)`, `%1{if now == "true" then "false" else "true"}%2`, 1)
	assert(count == 1, `could not flip {flag}`)
	fs.writeFile(configPath, swapped)
	fs.writeFile(
		`{root}/tests/run.luau`,
		`local TestRunner = require("./TestRunner")\nrequire("./{spec}.spec")\nlocal failures = TestRunner.run()\nrequire("@lune/process").exit(if failures > 0 then 1 else 0)\n`
	)
	-- rokit resolves `lune` from the nearest manifest; the temp copy needs one too.
	fs.writeFile(`{root}/rokit.toml`, fs.readFile("rokit.toml"))
	local result = process.exec("lune", { "run", "tests/run" }, { cwd = root })
	fs.removeDir(base)
	return result.ok, result.stdout .. result.stderr
end

describe("Feature flags flipped", function()
	for _, feature in FEATURES do
		it(`{feature.spec} passes with FEATURES.{feature.flag} inverted`, function()
			local ok, output = flipped(feature.flag, feature.spec)
			if not ok then
				print(output)
			end
			expect(ok).toBe(true)
		end)
	end
end)
