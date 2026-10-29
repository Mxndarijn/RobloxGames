--!strict
-- Every world label (BillboardGui / SurfaceGui) built in code sets MaxDistance on purpose: the engine defaults
-- draw a BillboardGui across the whole map and a SurfaceGui up to 1000 studs (guides/roblox-world-labels.md).
-- A label counts as set when "MaxDistance" appears within WINDOW lines after the line that creates it.
local TestRunner = require("./TestRunner")
local fs = require("@lune/fs")

local describe, it, expect = TestRunner.describe, TestRunner.it, TestRunner.expect

local ROOTS = { "src", "../../shared/luau/src" }
local WINDOW = 40
local CREATE =
	{ 'Instance%.new%("BillboardGui"%)', 'Instance%.new%("SurfaceGui"%)', '%("BillboardGui",', '%("SurfaceGui",' }

local function walk(dir: string, out: { string })
	for _, name in fs.readDir(dir) do
		local path = `{dir}/{name}`
		if fs.isDir(path) then
			walk(path, out)
		elseif string.match(name, "%.luau$") then
			table.insert(out, path)
		end
	end
end

local function creates(line: string): boolean
	for _, pattern in CREATE do
		if string.find(line, pattern) then
			return true
		end
	end
	return false
end

-- "path:line" for every label created without a MaxDistance close after it.
local function unset(): { string }
	local files: { string } = {}
	for _, root in ROOTS do
		walk(root, files)
	end
	table.sort(files)
	local out: { string } = {}
	for _, path in files do
		local lines = string.split(fs.readFile(path), "\n")
		for i, line in lines do
			if creates(line) and not string.find(line, "^%s*%-%-") then
				local found = false
				for j = i, math.min(i + WINDOW, #lines) do
					if string.find(lines[j], "MaxDistance", 1, true) then
						found = true
						break
					end
				end
				if not found then
					table.insert(out, `{path}:{i}`)
				end
			end
		end
	end
	return out
end

describe("World labels", function()
	it("every BillboardGui / SurfaceGui built in code sets MaxDistance", function()
		local missing = unset()
		if #missing > 0 then
			print(
				"  labels without MaxDistance (guides/roblox-world-labels.md):\n    " .. table.concat(missing, "\n    ")
			)
		end
		expect(#missing).toBe(0)
	end)
end)
