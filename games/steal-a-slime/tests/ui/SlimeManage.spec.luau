--!strict
-- The owner's Manage prompt on their pad slimes (src/ui/SlimeManage.luau), driven through mock instances.
local SlimeManage = require("../../src/ui/SlimeManage")
local TestRunner = require("../TestRunner")

local describe, it, expect = TestRunner.describe, TestRunner.it, TestRunner.expect

local ME = 111
local OTHER = 222

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

-- Instance stand-in: class, attributes with change signals, a parent / children tree, DescendantAdded on the root.
local function instance(className: string, name: string): any
	local attrs = {}
	local attrSignals = {}
	local data: any = {
		Name = name,
		ClassName = className,
		children = {},
		DescendantAdded = signal(),
		AncestryChanged = signal(),
		Triggered = signal(),
		destroyed = false,
	}
	-- Setting Parent moves the node between children lists, like the engine.
	local self: any = setmetatable({}, {
		__index = data,
		__newindex = function(_, key, value)
			if key == "Parent" then
				local old = data.Parent
				if old then
					local i = table.find(old.children, data.self)
					if i then
						table.remove(old.children, i)
					end
				end
				if value then
					table.insert(value.children, data.self)
				end
			end
			data[key] = value
		end,
	})
	data.self = self
	function self.IsA(_, cls)
		return cls == className or (cls == "BasePart" and className == "Part")
	end
	function self.GetAttribute(_, key)
		return attrs[key]
	end
	function self.GetAttributeChangedSignal(_, key)
		attrSignals[key] = attrSignals[key] or signal()
		return attrSignals[key]
	end
	function self.SetAttribute(_, key, value)
		if attrs[key] ~= value then
			attrs[key] = value
			if attrSignals[key] then
				attrSignals[key]:Fire()
			end
		end
	end
	function self.FindFirstChild(_, childName)
		for _, child in self.children do
			if child.Name == childName and not child.destroyed then
				return child
			end
		end
		return nil
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
	function self.IsDescendantOf(_, root)
		local node = self.Parent
		while node do
			if node == root then
				return true
			end
			node = node.Parent
		end
		return false
	end
	function self.Destroy()
		self.destroyed = true
		self.Parent = nil
	end
	return self
end

local function parent(root: any, node: any, under: any)
	node.Parent = under
	root.DescendantAdded:Fire(node)
	for _, child in node:GetDescendants() do
		root.DescendantAdded:Fire(child)
	end
end

-- A slime model with its Body and the server's GrabPrompt, not yet parented.
local function slime(id: string, owner: number?, state: string): (any, any)
	local model = instance("Model", `Slime_{id}`)
	model:SetAttribute("SlimeId", id)
	model:SetAttribute("OwnerUserId", owner)
	model:SetAttribute("State", state)
	local body = instance("Part", "Body")
	body.Parent = model
	local grab = instance("ProximityPrompt", "GrabPrompt")
	grab.ObjectText = "Blorp"
	grab.Parent = body
	return model, body
end

local function start(root: any, managed: { string }): () -> ()
	return SlimeManage.start({
		root = root,
		localUserId = ME,
		newPrompt = function(): any
			return instance("ProximityPrompt", "ProximityPrompt")
		end,
		keyCode = "E" :: any,
		distance = 10,
		onManage = function(id: string)
			table.insert(managed, id)
		end,
	})
end

local function manage(body: any): any
	return body:FindFirstChild(SlimeManage.PROMPT_NAME)
end

describe("SlimeManage", function()
	it("puts Manage on my pad slimes only, named after the slime", function()
		local root = instance("Workspace", "Workspace")
		local mineModel, mine = slime("a", ME, "Pad")
		local _, theirs = slime("b", OTHER, "Pad")
		local _, wild = slime("c", nil, "Wild")
		parent(root, mineModel, root)
		start(root, {})
		parent(root, theirs.Parent, root)
		parent(root, wild.Parent, root)
		local prompt = manage(mine)
		expect(prompt).toBeTruthy()
		expect(prompt.ActionText).toBe(SlimeManage.ACTION_TEXT)
		expect(prompt.ObjectText).toBe("Blorp")
		expect(prompt.HoldDuration).toBe(0)
		expect(prompt.MaxActivationDistance).toBe(10)
		expect(manage(theirs)).toBeNil()
		expect(manage(wild)).toBeNil()
	end)

	it("opens the card for that slime when triggered", function()
		local root = instance("Workspace", "Workspace")
		local managed = {}
		start(root, managed)
		local model, body = slime("a", ME, "Pad")
		parent(root, model, root)
		manage(body).Triggered:Fire()
		expect(table.concat(managed, ",")).toBe("a")
	end)

	it("drops the prompt while the slime is carried and brings it back on the pad", function()
		local root = instance("Workspace", "Workspace")
		local managed = {}
		start(root, managed)
		local model, body = slime("a", ME, "Pad")
		parent(root, model, root)
		local first = manage(body)
		model:SetAttribute("State", "Carried")
		expect(manage(body)).toBeNil()
		expect(first.destroyed).toBe(true)
		first.Triggered:Fire()
		expect(#managed).toBe(0)
		model:SetAttribute("State", "Pad")
		expect(manage(body)).toBeTruthy()
	end)

	it("follows ownership and cleans up on removal and stop", function()
		local root = instance("Workspace", "Workspace")
		local stop = start(root, {})
		local model, body = slime("a", OTHER, "Pad")
		parent(root, model, root)
		expect(manage(body)).toBeNil()
		model:SetAttribute("OwnerUserId", ME)
		local prompt = manage(body)
		expect(prompt).toBeTruthy()
		model:Destroy()
		body.AncestryChanged:Fire()
		expect(prompt.destroyed).toBe(true)

		local model2, body2 = slime("b", ME, "Pad")
		parent(root, model2, root)
		local prompt2 = manage(body2)
		stop()
		expect(prompt2.destroyed).toBe(true)
	end)
end)
