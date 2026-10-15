--!strict
-- Static guard for the untested Roblox adapters: every `Module.member` used in
-- src/server, src/shared and src/visuals (where Module is a required local named
-- like a module file) must be defined by that module (function, field or type).
local fs = require("@lune/fs")

local TestRunner = require("./TestRunner")

local describe, it, expect = TestRunner.describe, TestRunner.it, TestRunner.expect

local ROOTS = { "src/server", "src/shared", "src/visuals/shared", "src/visuals/client" }

local function files(dir: string, out: { string })
	for _, name in fs.readDir(dir) do
		local path = `{dir}/{name}`
		if fs.isDir(path) then
			files(path, out)
		elseif string.sub(name, -5) == ".luau" then
			table.insert(out, path)
		end
	end
end

local all: { string } = {}
for _, root in ROOTS do
	files(root, all)
end

-- module name -> defined members
local defined: { [string]: { [string]: boolean } } = {}
for _, path in all do
	local name = string.match(path, "([%w_]+)%.luau$") :: string
	if not string.find(name, "^init") then
		local source = fs.readFile(path)
		local members = {}
		for member in string.gmatch(source, "\nfunction " .. name .. "[%.:]([%w_]+)") do
			members[member] = true
		end
		for member in string.gmatch(source, "\n%s*" .. name .. "%.([%w_]+)%s*=") do
			members[member] = true
		end
		for member in string.gmatch(source, "export type ([%w_]+)") do
			members[member] = true
		end
		for member in string.gmatch(source, "\n\t([%w_]+)%s*=") do -- table-literal modules (Config, Constants)
			members[member] = true
		end
		defined[name] = members
	end
end

describe("Module members (static)", function()
	it("only uses members that the required module defines", function()
		local missing = {}
		for _, path in all do
			local source = fs.readFile(path)
			for alias in string.gmatch(source, "\nlocal ([%w_]+)%s*=[^\n]*require") do
				local members = defined[alias]
				if members then
					for member in string.gmatch(source, "%f[%w_]" .. alias .. "[%.:]([%w_]+)") do
						if not members[member] then
							table.insert(missing, `{path}: {alias}.{member}`)
						end
					end
				end
			end
		end
		for _, line in missing do
			print(`    {line}`)
		end
		expect(#missing).toBe(0)
	end)
end)
