--!nocheck
-- Every `require(script.Parent...X.Y)` in the built place must resolve in the
-- Rojo layout. Under Lune `script` is nil, so the pure specs only take the
-- `else require("../...")` branch; v9/v10 shipped SlimeMesh requiring
-- script.Parent.Parent.Shared (that is ServerScriptService, Shared lives in
-- ReplicatedStorage) and the whole server Script died at boot.
-- `rojo build`s the real place and walks each chain from the script instance.
local fs = require("@lune/fs")
local process = require("@lune/process")
local roblox = require("@lune/roblox")

local TestRunner = require("./TestRunner")

local describe, it, expect = TestRunner.describe, TestRunner.it, TestRunner.expect

local path = `{process.env.TMPDIR or "/tmp"}/steal-a-slime-requirepaths-{os.time()}.rbxlx`
local built = process.exec("rojo", { "build", "-o", path })
assert(built.ok, `rojo build failed: {built.stderr}`)
local game = roblox.deserializePlace(fs.readFile(path))
fs.removeFile(path)

-- Each `script.A.B...` chain inside a require( ... ) call; returns the names after `script`.
local function chains(source: string): { { string } }
	local out = {}
	for chain in string.gmatch(source, "require%(%s*script([%.%w_]*)%s*%)") do
		local names = {}
		for name in string.gmatch(chain, "[%w_]+") do
			table.insert(names, name)
		end
		table.insert(out, names)
	end
	return out
end

local function resolve(from, names: { string }): (boolean, string)
	local node = from
	for _, name in names do
		local nextNode = if name == "Parent" then node.Parent else node:FindFirstChild(name)
		if not nextNode then
			return false, `{name} is not a valid member of {node:GetFullName()}`
		end
		node = nextNode
	end
	return node:IsA("ModuleScript"), `{node:GetFullName()} is a {node.ClassName}`
end

describe("require(script...) paths in the built place", function()
	it("finds the scripts to check", function()
		local server = game:GetService("ServerScriptService"):FindFirstChild("Server")
		expect(server ~= nil).toBe(true)
		expect(server:FindFirstChild("SlimeMesh") ~= nil).toBe(true)
	end)
	it("resolves every chain to a ModuleScript", function()
		local bad = {}
		for _, d in game:GetDescendants() do
			-- Wally packages resolve their own _Index links (with [] indexing).
			if d:IsA("LuaSourceContainer") and not d:FindFirstAncestor("Packages") then
				for _, names in chains(d.Source) do
					local ok, why = resolve(d, names)
					if not ok then
						table.insert(bad, `{d:GetFullName()}: script.{table.concat(names, ".")} ({why})`)
					end
				end
			end
		end
		for _, line in bad do
			print(`    {line}`)
		end
		expect(#bad).toBe(0)
	end)
end)
