--!strict
-- Lune only (reads src/ as text). Luau parses `a = b` + newline + `(c)` as the call `b(c)`, which is how
-- #276 shipped `ctx.worldShop = worldShop(Remotes.get(...))` (calling the controller table) and killed
-- the whole HUD init. Guard: no statement line in src/ may start with `(` right after a line that
-- could continue into a call, and nothing may call the worldShop controller table.
local fs = require("@lune/fs")

local TestRunner = require("./TestRunner")

local describe, it, expect = TestRunner.describe, TestRunner.it, TestRunner.expect

local function collect(dir: string, out: { string })
	for _, name in fs.readDir(dir) do
		local path = `{dir}/{name}`
		if fs.isDir(path) then
			collect(path, out)
		elseif string.match(name, "%.luau?$") then
			table.insert(out, path)
		end
	end
end

-- Source with comments blanked (line structure kept) so doc blocks do not look like code.
local function stripComments(text: string): string
	local stripped = string.gsub(text, "(%-%-%[(=*)%[.-%]%2%])", function(whole: string)
		return (string.gsub(whole, "[^\n]", ""))
	end)
	return stripped
end

local function codeLines(text: string): { string }
	local lines = {}
	for line in string.gmatch(stripComments(text) .. "\n", "([^\n]*)\n") do
		table.insert(lines, (string.gsub(line, "%-%-.*$", "")))
	end
	return lines
end

-- Last words after which a leading ( starts a new expression (or a block), never a call.
local OPENERS: { [string]: boolean } = {
	["end"] = true,
	["then"] = true,
	["do"] = true,
	["else"] = true,
	["if"] = true,
	["elseif"] = true,
	["and"] = true,
	["or"] = true,
	["not"] = true,
	["return"] = true,
	["in"] = true,
	["while"] = true,
	["until"] = true,
	["repeat"] = true,
}

local files: { string } = {}
collect("src", files)

describe("Ambiguous call syntax", function()
	it("no line starts with ( straight after an expression-ending line", function()
		local bad = {}
		for _, path in files do
			local prev = ""
			for i, line in codeLines(fs.readFile(path)) do
				local trimmed = string.match(line, "^%s*(.-)%s*$") :: string
				if trimmed ~= "" then
					if string.sub(trimmed, 1, 1) == "(" and string.match(prev, "[%w_%)%]\"'}]$") then
						local keyword = string.match(prev, "([%a_]+)$")
						local header = string.find(prev, "function[%w_%.:]*%b()$") ~= nil -- a parameter list, not a call target
						if not header and not OPENERS[keyword or ""] then
							table.insert(bad, `{path}:{i}`)
						end
					end
					prev = trimmed
				end
			end
		end
		expect(table.concat(bad, ", ")).toBe("")
	end)

	it("the worldShop controller table is never called", function()
		local bad = {}
		for _, path in files do
			for i, line in codeLines(fs.readFile(path)) do
				if string.find(line, "%f[%w_]worldShop%(") then
					table.insert(bad, `{path}:{i}`)
				end
			end
		end
		expect(table.concat(bad, ", ")).toBe("")
	end)
end)
