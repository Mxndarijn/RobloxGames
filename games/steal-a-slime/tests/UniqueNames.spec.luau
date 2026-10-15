--!nocheck
-- No two siblings anywhere in the built place may share a Name. Every
-- `script.Parent.X` / `:WaitForChild("X")` picks one of them arbitrarily:
-- StarterPlayerScripts.UI had a LocalScript (PromptHide.client.luau) and a
-- ModuleScript (PromptHide.luau) both named PromptHide, so the runner's
-- require hit the LocalScript and errored.
-- `rojo build`s the real place and walks the whole DataModel.
local fs = require("@lune/fs")
local process = require("@lune/process")
local roblox = require("@lune/roblox")

local TestRunner = require("./TestRunner")

local describe, it, expect = TestRunner.describe, TestRunner.it, TestRunner.expect

local path = `{process.env.TMPDIR or "/tmp"}/steal-a-slime-uniquenames-{os.time()}.rbxl`
local built = process.exec("rojo", { "build", "-o", path })
assert(built.ok, `rojo build failed: {built.stderr}`)
local game = roblox.deserializePlace(fs.readFile(path))
fs.removeFile(path)

local function duplicates(root: any): { string }
	local out = {}
	local function walk(inst: any, at: string)
		local classes: { [string]: { string } } = {}
		for _, child in inst:GetChildren() do
			classes[child.Name] = classes[child.Name] or {}
			table.insert(classes[child.Name], child.ClassName)
		end
		for name, list in classes do
			if #list > 1 then
				table.insert(out, `{at}.{name} ({table.concat(list, ", ")})`)
			end
		end
		for _, child in inst:GetChildren() do
			walk(child, `{at}.{child.Name}`)
		end
	end
	walk(root, "game")
	table.sort(out)
	return out
end

describe("UniqueNames", function()
	it("has no duplicate sibling names anywhere in the built place", function()
		local found = duplicates(game)
		expect(table.concat(found, " | ")).toBe("")
	end)

	it("keeps the PromptHide module and its runner apart", function()
		local ui = game:GetService("StarterPlayer").StarterPlayerScripts.UI
		expect(ui:FindFirstChild("PromptHide").ClassName).toBe("ModuleScript")
		expect(ui:FindFirstChild("PromptHideRunner").ClassName).toBe("LocalScript")
	end)
end)
