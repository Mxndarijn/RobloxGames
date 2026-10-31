--!strict
-- The goo tube's DropPrompt shows only when it can be used (src/ui/GooTubePrompt.luau, CONTRACT.md §5.3), driven
-- through minimal mock instances.
local Constants = require("../../src/shared/Constants")
local GooTubePrompt = require("../../src/ui/GooTubePrompt")
local TestRunner = require("../TestRunner")

local describe, it, expect = TestRunner.describe, TestRunner.it, TestRunner.expect

local ME = 111
local OTHER = 222
local OPEN = Constants.DROP_PROMPT_OPEN_ATTRIBUTE
local OWNER = Constants.DROP_PROMPT_OWNER_ATTRIBUTE
local CARRYING = Constants.CARRYING_ATTRIBUTE

local function signal()
	local handlers = {}
	return {
		Connect = function(_, fn)
			table.insert(handlers, fn)
			return {
				Disconnect = function()
					local i = table.find(handlers, fn)
					if i then
						table.remove(handlers, i)
					end
				end,
			}
		end,
		Fire = function(_, ...)
			for _, fn in table.clone(handlers) do
				fn(...)
			end
		end,
	}
end

-- Instance stand-in: Name/ClassName, attributes, Enabled with change signals, children, DescendantAdded.
local function instance(className: string, name: string): any
	local props = { Enabled = true }
	local attrs = {}
	local attrSignals = {}
	local propSignals = {}
	local self = { Name = name, ClassName = className, DescendantAdded = signal(), children = {} }
	function self.IsA(_, cls)
		return cls == className
	end
	function self.GetAttribute(_, key)
		return attrs[key]
	end
	function self.GetAttributeChangedSignal(_, key)
		attrSignals[key] = attrSignals[key] or signal()
		return attrSignals[key]
	end
	function self.GetPropertyChangedSignal(_, key)
		propSignals[key] = propSignals[key] or signal()
		return propSignals[key]
	end
	function self.SetAttribute(_, key, value)
		if attrs[key] ~= value then
			attrs[key] = value
			if attrSignals[key] then
				attrSignals[key]:Fire()
			end
		end
	end
	function self.GetDescendants()
		local out = {}
		local function walk(node)
			for _, child in node.children do
				table.insert(out, child)
				walk(child)
			end
		end
		walk(self)
		return out
	end
	return setmetatable(self, {
		__index = props,
		__newindex = function(_, key, value)
			if props[key] ~= nil then
				if props[key] ~= value then
					props[key] = value
					if propSignals[key] then
						propSignals[key]:Fire()
					end
				end
			else
				rawset(self, key, value)
			end
		end,
	})
end

local function tube(open: boolean, owner: number?): any
	local p = instance("ProximityPrompt", Constants.DROP_PROMPT_NAME)
	p:SetAttribute(OPEN, open)
	p:SetAttribute(OWNER, owner)
	return p
end

local function setup(...: any): (any, any, () -> ())
	local root = instance("Folder", "Plots")
	for _, p in { ... } do
		table.insert(root.children, p)
	end
	local player = instance("Player", "Me")
	local stop = GooTubePrompt.start({ root = root, player = player, localUserId = ME })
	return root, player, stop
end

describe("GooTubePrompt", function()
	it("shows the open tube only to its owner", function()
		local mine, theirs, free = tube(true, ME), tube(true, OTHER), tube(true, nil)
		setup(mine, theirs, free)
		expect(mine.Enabled).toBe(true)
		expect(theirs.Enabled).toBe(false)
		expect(free.Enabled).toBe(false)
	end)

	it("keeps a closed tube (a lower jar) hidden, also for the owner", function()
		local lower = tube(false, ME)
		setup(lower)
		expect(lower.Enabled).toBe(false)
	end)

	it("hides the owner's tube while they carry a slime and brings it back after", function()
		local mine, lower = tube(true, ME), tube(false, ME)
		local _, player = setup(mine, lower)
		player:SetAttribute(CARRYING, "slime-1")
		expect(mine.Enabled).toBe(false)
		player:SetAttribute(CARRYING, nil)
		expect(mine.Enabled).toBe(true)
		expect(lower.Enabled).toBe(false) -- never turned on by the carry ending
	end)

	it("follows the open hatch and the owner as they change", function()
		local p = tube(false, ME)
		setup(p)
		p:SetAttribute(OPEN, true)
		expect(p.Enabled).toBe(true)
		p:SetAttribute(OWNER, OTHER)
		expect(p.Enabled).toBe(false)
	end)

	it("hides a server Enabled write that would show it to someone else", function()
		local theirs = tube(true, OTHER)
		setup(theirs)
		theirs.Enabled = true -- the server's value replicating over the local one
		expect(theirs.Enabled).toBe(false)
	end)

	it("handles prompts added later and ignores other prompts", function()
		local root = setup()
		local other = instance("ProximityPrompt", "LockPrompt")
		local late = tube(true, OTHER)
		table.insert(root.children, other)
		root.DescendantAdded:Fire(other)
		table.insert(root.children, late)
		root.DescendantAdded:Fire(late)
		expect(other.Enabled).toBe(true)
		expect(late.Enabled).toBe(false)
	end)

	it("stops following changes after stop", function()
		local mine = tube(true, ME)
		local _, player, stop = setup(mine)
		stop()
		player:SetAttribute(CARRYING, "slime-1")
		expect(mine.Enabled).toBe(true)
	end)
end)
