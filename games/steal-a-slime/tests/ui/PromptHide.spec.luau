--!strict
-- Owner-hidden GrabPrompt client rule (src/ui/PromptHide.luau, CONTRACT §5.2),
-- driven through minimal mock instances.
local Constants = require("../../src/shared/Constants")
local PromptHide = require("../../src/ui/PromptHide")
local TestRunner = require("../TestRunner")

local describe, it, expect = TestRunner.describe, TestRunner.it, TestRunner.expect

local ME = 111
local OTHER = 222
local ATTR = Constants.PROMPT_HIDE_ATTRIBUTE

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

-- Instance stand-in: Name/ClassName, attributes, Enabled with change signals,
-- children, DescendantAdded on the root.
local function instance(className: string, name: string): any
	local props = { Enabled = true }
	local attrs = {}
	local attrSignals = {}
	local propSignals = {}
	local children = {}
	local self = {
		Name = name,
		ClassName = className,
		DescendantAdded = signal(),
		writes = 0,
	}
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
	self.children = children
	return setmetatable(self, {
		__index = props,
		__newindex = function(_, key, value)
			if props[key] ~= nil then
				self.writes += 1
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

local function add(root: any, parent: any, child: any): any
	table.insert(parent.children, child)
	root.DescendantAdded:Fire(child)
	return child
end

local function prompt(name: string?, hideFrom: number?): any
	local p = instance("ProximityPrompt", name or "GrabPrompt")
	p:SetAttribute(ATTR, hideFrom)
	return p
end

local function start(root: any)
	return PromptHide.start({ root = root, localUserId = ME, attribute = ATTR })
end

describe("PromptHide", function()
	it("hides existing GrabPrompts whose attribute is the local UserId", function()
		local root = instance("Workspace", "Workspace")
		local body = instance("Part", "Body")
		table.insert(root.children, body)
		local mine = prompt(nil, ME)
		local theirs = prompt(nil, OTHER)
		local wild = prompt(nil, nil)
		table.insert(body.children, mine)
		table.insert(body.children, theirs)
		table.insert(body.children, wild)
		start(root)
		expect(mine.Enabled).toBe(false)
		expect(theirs.Enabled).toBe(true)
		expect(wild.Enabled).toBe(true)
	end)

	it("ignores prompts with other names and non-prompts named GrabPrompt", function()
		local root = instance("Workspace", "Workspace")
		local other = prompt("BuyPrompt", ME)
		local fake = instance("Part", "GrabPrompt")
		fake:SetAttribute(ATTR, ME)
		table.insert(root.children, other)
		table.insert(root.children, fake)
		start(root)
		add(root, root, prompt("DepositPrompt", ME))
		expect(other.Enabled).toBe(true)
		expect(fake.Enabled).toBe(true)
		expect(other.writes).toBe(0)
	end)

	it("hides and watches prompts added after start (DescendantAdded)", function()
		local root = instance("Workspace", "Workspace")
		start(root)
		local p = add(root, root, prompt(nil, ME))
		expect(p.Enabled).toBe(false)
		local q = add(root, root, prompt(nil, nil))
		expect(q.Enabled).toBe(true)
		q:SetAttribute(ATTR, ME)
		expect(q.Enabled).toBe(false)
	end)

	it("re-enables a prompt it hid when the attribute changes away", function()
		local root = instance("Workspace", "Workspace")
		start(root)
		local p = add(root, root, prompt(nil, ME))
		expect(p.Enabled).toBe(false)
		p:SetAttribute(ATTR, nil)
		expect(p.Enabled).toBe(true)
		p:SetAttribute(ATTR, ME)
		expect(p.Enabled).toBe(false)
		p:SetAttribute(ATTR, OTHER)
		expect(p.Enabled).toBe(true)
	end)

	it("leaves a server-disabled prompt alone when it never hid it", function()
		local root = instance("Workspace", "Workspace")
		start(root)
		local p = add(root, root, prompt(nil, OTHER))
		p.Enabled = false -- server lock
		p:SetAttribute(ATTR, nil)
		expect(p.Enabled).toBe(false)
	end)

	it("re-hides when a server Enabled flip lands while still the hide target", function()
		local root = instance("Workspace", "Workspace")
		start(root)
		local p = add(root, root, prompt(nil, ME))
		expect(p.Enabled).toBe(false)
		p.Enabled = true -- replicated unlock
		expect(p.Enabled).toBe(false)
	end)

	it("binds each prompt once and stops reacting after stop()", function()
		local root = instance("Workspace", "Workspace")
		local p = prompt(nil, nil)
		table.insert(root.children, p)
		local stop = start(root)
		root.DescendantAdded:Fire(p) -- reparent: no second binding
		p:SetAttribute(ATTR, ME)
		expect(p.writes).toBe(1)
		stop()
		p:SetAttribute(ATTR, nil)
		expect(p.Enabled).toBe(false)
		local late = add(root, root, prompt(nil, ME))
		expect(late.Enabled).toBe(true)
	end)
end)

describe("PromptHide owner-only prompts (CONTRACT §8.4)", function()
	local OWNER = Constants.PROMPT_OWNER_ATTRIBUTE
	local function startOwner(root: any)
		return PromptHide.start({ root = root, localUserId = ME, attribute = ATTR, ownerAttribute = OWNER })
	end
	local function ownerPrompt(name: string, owner: number?): any
		local p = instance("ProximityPrompt", name)
		p:SetAttribute(OWNER, owner)
		return p
	end

	it("shows owner prompts only to their owner", function()
		local root = instance("Workspace", "Workspace")
		local mine = ownerPrompt(Constants.LOCK_PROMPT_NAME, ME)
		local theirs = ownerPrompt(Constants.BUY_PAD_PROMPT_NAME, OTHER)
		table.insert(root.children, mine)
		table.insert(root.children, theirs)
		startOwner(root)
		expect(mine.Enabled).toBe(true)
		expect(theirs.Enabled).toBe(false)
		local late = add(root, root, ownerPrompt(Constants.MERGE_PROMPT_NAME, OTHER))
		expect(late.Enabled).toBe(false)
	end)

	it("re-shows when the plot becomes mine, not when it becomes free", function()
		local root = instance("Workspace", "Workspace")
		startOwner(root)
		local p = add(root, root, ownerPrompt(Constants.LOCK_PROMPT_NAME, OTHER))
		expect(p.Enabled).toBe(false)
		p:SetAttribute(OWNER, nil) -- owner left: server disables it
		expect(p.Enabled).toBe(false)
		p:SetAttribute(OWNER, OTHER)
		p:SetAttribute(OWNER, ME)
		expect(p.Enabled).toBe(true)
	end)

	it("re-hides a replicated Enabled flip and leaves other prompts alone", function()
		local root = instance("Workspace", "Workspace")
		startOwner(root)
		local p = add(root, root, ownerPrompt(Constants.LOCK_PROMPT_NAME, OTHER))
		p.Enabled = true
		expect(p.Enabled).toBe(false)
		local plain = add(root, root, ownerPrompt("ShopPrompt_SpeedCoil", nil))
		expect(plain.Enabled).toBe(true)
		expect(plain.writes).toBe(0)
		-- HideFromUserId still only applies to GrabPrompt
		local other = add(root, root, prompt("BuyPrompt", ME))
		expect(other.Enabled).toBe(true)
	end)
end)
