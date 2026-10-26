--!strict
-- Nothing in the game wears Material.Glass. Roblox draws nothing partly see-through behind a Glass part, so a faded
-- slime, a sign's SurfaceGui or a billboard on the far side of any Glass part vanished.
local fs = require("@lune/fs")

local Config = require("../src/shared/Config")
local SlimeLooks = require("../src/shared/SlimeLooks")
local TestRunner = require("./TestRunner")
local WorldLayout = require("../src/visuals/shared/WorldLayout")

local describe, it, expect = TestRunner.describe, TestRunner.it, TestRunner.expect

local ENUM_GLASS = 1568 -- Enum.Material.Glass, as world/*.rbxmx stores it

local function luauFiles(dir: string, out: { string })
	for _, name in fs.readDir(dir) do
		local path = `{dir}/{name}`
		if fs.isDir(path) then
			luauFiles(path, out)
		elseif string.sub(name, -5) == ".luau" then
			table.insert(out, path)
		end
	end
	return out
end

local function walk(node: any, fn: (any) -> ())
	fn(node)
	for _, c in node.children or {} do
		walk(c, fn)
	end
end

describe("no Glass material", function()
	it("is on no part of the world layout, the jar floors or a slime look", function()
		local seen = 0
		local function visit(n: any)
			seen += 1
			expect(n.material ~= "Glass").toBe(true)
		end
		for _, root in WorldLayout.build() do
			walk(root, visit)
		end
		for f = 2, Config.PADS_MAX // Config.PADS_PER_FLOOR do
			for _, node in WorldLayout.floor(1, f) do
				walk(node, visit)
			end
		end
		expect(seen > 100).toBe(true)
		expect(SlimeLooks.isMaterial("Glass")).toBe(false)
	end)

	it("is in no source file", function()
		local files = luauFiles("src", {})
		expect(#files > 100).toBe(true)
		for _, path in files do
			local text = fs.readFile(path)
			expect(string.find(text, "Material.Glass", 1, true)).toBe(nil)
			expect(string.find(text, '[Mm]aterial%s*=%s*"Glass"')).toBe(nil)
		end
	end)

	it("is in no generated world file", function()
		for _, name in { "Map", "Plots", "HubSpawn" } do
			local text = fs.readFile(`world/{name}.rbxmx`)
			expect(string.find(text, `name="Material">{ENUM_GLASS}<`, 1, true)).toBe(nil)
		end
	end)
end)
