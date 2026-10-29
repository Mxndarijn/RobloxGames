--!strict
-- The owner's key prompts on their pad slimes (src/ui/SlimeKeys.luau): R Favorite, X hold Sell (none on a Mystery Egg),
-- through mock instances.
local SlimeKeys = require("../../src/ui/SlimeKeys")
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
		ChildAdded = signal(),
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
local function slime(id: string, owner: number?, state: string, egg: boolean?): (any, any)
	local model = instance("Model", `Slime_{id}`)
	if egg then
		model:SetAttribute("EggKind", "Golden")
	end
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

local function cash(n: number): string
	return `${n}`
end

local function start(root: any, sent: { string }, moved: { string }?): SlimeKeys.Handle
	return SlimeKeys.start({
		root = root,
		localUserId = ME,
		newPrompt = function(): any
			return instance("ProximityPrompt", "ProximityPrompt")
		end,
		favoriteKey = { keyboard = "R" :: any, gamepad = "DPadUp" :: any },
		sellKey = { keyboard = "X" :: any, gamepad = "DPadDown" :: any },
		distance = 10,
		holdSeconds = 0.8,
		formatCash = cash,
		send = function(action: string, id: string?)
			table.insert(sent, `{action}:{id or "nil"}`)
		end,
		moveKey = if moved then { keyboard = "E" :: any, gamepad = "ButtonX" :: any } else nil,
		onMove = if moved
			then function(id: string, model: any)
				table.insert(moved, `{id}:{model.Name}`)
			end
			else nil,
	})
end

local function fav(body: any): any
	return body:FindFirstChild(SlimeKeys.FAVORITE_PROMPT)
end

local function sell(body: any): any
	return body:FindFirstChild(SlimeKeys.SELL_PROMPT)
end

local function state(favoriteId: string?, perk: any?): any
	return {
		slimes = {
			{ slime = { id = "a" }, sellPrice = 450 },
			{ slime = { id = "e" }, sellPrice = 90 },
		},
		favoriteId = favoriteId,
		petPerk = perk,
	}
end

describe("SlimeKeys", function()
	it("puts R Favorite (tap) and X Sell (hold) on my pad slimes only", function()
		local root = instance("Workspace", "Workspace")
		local mineModel, mine = slime("a", ME, "Pad")
		local _, theirs = slime("b", OTHER, "Pad")
		local _, wild = slime("c", nil, "Wild")
		parent(root, mineModel, root)
		start(root, {})
		parent(root, theirs.Parent, root)
		parent(root, wild.Parent, root)
		local f, s = fav(mine), sell(mine)
		expect(f.KeyboardKeyCode).toBe("R")
		expect(f.GamepadKeyCode).toBe("DPadUp")
		expect(f.HoldDuration).toBe(0)
		expect(f.ActionText).toBe("Favorite")
		expect(f.ObjectText).toBe("Blorp")
		expect(s.KeyboardKeyCode).toBe("X")
		expect(s.GamepadKeyCode).toBe("DPadDown")
		expect(s.HoldDuration).toBe(0.8)
		expect(s.ActionText).toBe("Sell")
		expect(s.MaxActivationDistance).toBe(10)
		expect(fav(theirs)).toBeNil()
		expect(sell(theirs)).toBeNil()
		expect(fav(wild)).toBeNil()
		expect(sell(wild)).toBeNil()
		expect(mine:FindFirstChild("ManagePrompt")).toBeNil()
	end)

	it("shows the sell price and the favourite's perk from State", function()
		local root = instance("Workspace", "Workspace")
		local keys = start(root, {})
		local model, body = slime("a", ME, "Pad")
		parent(root, model, root)
		keys.update(state(nil))
		expect(sell(body).ActionText).toBe("Sell $450")
		expect(fav(body).ActionText).toBe("Favorite")
		keys.update(state("a", { icon = "*", text = "+3% luck" }))
		expect(fav(body).ActionText).toBe("Unfavorite")
		expect(fav(body).ObjectText).toBe("* +3% luck")
		keys.update(state("a"))
		expect(fav(body).ObjectText).toBe("Blorp")
	end)

	it("Favorite toggles through Request; Sell sends the slime", function()
		local root = instance("Workspace", "Workspace")
		local sent = {}
		local keys = start(root, sent)
		local model, body = slime("a", ME, "Pad")
		parent(root, model, root)
		keys.update(state(nil))
		fav(body).Triggered:Fire()
		keys.update(state("a"))
		fav(body).Triggered:Fire()
		sell(body).Triggered:Fire()
		expect(table.concat(sent, ",")).toBe("Favorite:a,Favorite:nil,Sell:a")
	end)

	it("gives a Mystery Egg neither Sell nor Favorite, and both once it hatches", function()
		local root = instance("Workspace", "Workspace")
		local keys = start(root, {})
		local model, body = slime("e", ME, "Pad", true)
		parent(root, model, root)
		keys.update(state(nil))
		expect(fav(body)).toBeNil()
		expect(sell(body)).toBeNil()
		model:SetAttribute("EggKind", nil)
		expect(fav(body)).toBeTruthy()
		expect(sell(body).ActionText).toBe("Sell $90")
	end)

	it("never sends Sell for a Mystery Egg", function()
		local root = instance("Workspace", "Workspace")
		local sent = {}
		local keys = start(root, sent)
		local model, body = slime("a", ME, "Pad")
		parent(root, model, root)
		keys.update(state(nil))
		local prompt = sell(body)
		model:SetAttribute("EggKind", "Golden")
		expect(sell(body)).toBeNil()
		prompt.Triggered:Fire()
		expect(#sent).toBe(0)
	end)

	it("drops the prompts while the slime is carried and brings them back on the pad", function()
		local root = instance("Workspace", "Workspace")
		local sent = {}
		start(root, sent)
		local model, body = slime("a", ME, "Pad")
		parent(root, model, root)
		local first = sell(body)
		model:SetAttribute("State", "Carried")
		expect(fav(body)).toBeNil()
		expect(sell(body)).toBeNil()
		expect(first.destroyed).toBe(true)
		first.Triggered:Fire()
		expect(#sent).toBe(0)
		model:SetAttribute("State", "Pad")
		expect(fav(body)).toBeTruthy()
		expect(sell(body)).toBeTruthy()
	end)

	it("follows ownership and cleans up on removal and destroy", function()
		local root = instance("Workspace", "Workspace")
		local keys = start(root, {})
		local model, body = slime("a", OTHER, "Pad")
		parent(root, model, root)
		expect(sell(body)).toBeNil()
		model:SetAttribute("OwnerUserId", ME)
		local prompt = sell(body)
		expect(prompt).toBeTruthy()
		model:Destroy()
		body.AncestryChanged:Fire()
		expect(prompt.destroyed).toBe(true)

		local model2, body2 = slime("b", ME, "Pad")
		parent(root, model2, root)
		local f2, s2 = fav(body2), sell(body2)
		keys.destroy()
		expect(f2.destroyed).toBe(true)
		expect(s2.destroyed).toBe(true)
	end)

	it("adds E Move only with FEATURES.MoveSlime's keys, and Move starts move mode for that slime", function()
		local root = instance("Workspace", "Workspace")
		local model, body = slime("a", ME, "Pad")
		parent(root, model, root)
		start(root, {})
		expect(body:FindFirstChild(SlimeKeys.MOVE_PROMPT)).toBeNil()

		local root2 = instance("Workspace", "Workspace")
		local moved = {}
		local model2, body2 = slime("a", ME, "Pad")
		parent(root2, model2, root2)
		local keys = start(root2, {}, moved)
		local move = body2:FindFirstChild(SlimeKeys.MOVE_PROMPT)
		expect(move.ActionText).toBe("Move")
		expect(move.KeyboardKeyCode).toBe("E")
		expect(move.GamepadKeyCode).toBe("ButtonX")
		expect(move.HoldDuration).toBe(0)
		move.Triggered:Fire()
		expect(table.concat(moved, ",")).toBe("a:Slime_a")
		model2:SetAttribute("State", "Carried")
		expect(move.destroyed).toBe(true)
		model2:SetAttribute("State", "Pad")
		local again = body2:FindFirstChild(SlimeKeys.MOVE_PROMPT)
		expect(again ~= nil).toBe(true)
		keys.destroy()
		expect(again.destroyed).toBe(true)
	end)

	it("gives the server's HatchPrompt the card style, so a ready egg's Hatch joins the card", function()
		local root = instance("Workspace", "Workspace")
		local model, body = slime("e", ME, "Pad", true)
		local hatch = instance("ProximityPrompt", "HatchPrompt")
		hatch.Style = "Default"
		hatch.Parent = body
		parent(root, model, root)
		local plainModel, plain = slime("a", ME, "Pad")
		parent(root, plainModel, root)
		SlimeKeys.start({
			root = root,
			localUserId = ME,
			newPrompt = function(): any
				return instance("ProximityPrompt", "ProximityPrompt")
			end,
			favoriteKey = { keyboard = "R" :: any, gamepad = "DPadUp" :: any },
			sellKey = { keyboard = "X" :: any, gamepad = "DPadDown" :: any },
			distance = 10,
			holdSeconds = 0.8,
			formatCash = cash,
			send = function() end,
			style = "Custom" :: any,
		})
		expect(hatch.Style).toBe("Custom")
		expect(sell(plain).Style).toBe("Custom")
	end)
end)

describe("Hatch now on an incubating egg", function()
	local function startHatch(root: any, quick: any, triggered: { string }): SlimeKeys.Handle
		return SlimeKeys.start({
			root = root,
			localUserId = ME,
			newPrompt = function(): any
				return instance("ProximityPrompt", "ProximityPrompt")
			end,
			favoriteKey = { keyboard = "R" :: any, gamepad = "DPadUp" :: any },
			sellKey = { keyboard = "X" :: any, gamepad = "DPadDown" :: any },
			distance = 10,
			holdSeconds = 0.8,
			formatCash = cash,
			send = function() end,
			hatchNow = {
				key = { keyboard = "F" :: any, gamepad = "ButtonX" :: any },
				quick = quick,
				trigger = function(id: string)
					table.insert(triggered, id)
				end,
			},
		})
	end
	it("a slime that is no egg gets the prompt when `quick` offers something for it (the Growth snack)", function()
		local root = instance("Folder", "Workspace")
		local plainModel, plain = slime("s1", ME, "Pad")
		parent(root, plainModel, root)
		local handle = startHatch(root, function(id: string): any
			return { text = `Growth snack · R$19 {id}`, enabled = true }
		end, {})
		handle.update({})
		local prompt = plain:FindFirstChild(SlimeKeys.HATCH_NOW_PROMPT)
		expect(prompt ~= nil).toBe(true)
		expect(prompt.ActionText).toBe("Growth snack · R$19 s1")
	end)
	it(
		"shows what `quick` says on my waiting egg and calls trigger; none where quick offers nothing or others' eggs",
		function()
			local root = instance("Folder", "Workspace")
			local eggModel, egg = slime("e1", ME, "Pad", true)
			local plainModel, plain = slime("s1", ME, "Pad")
			local otherModel, other = slime("e2", OTHER, "Pad", true)
			parent(root, eggModel, root)
			parent(root, plainModel, root)
			parent(root, otherModel, root)
			local waiting = true
			local triggered = {}
			local handle = startHatch(root, function(id: string): any
				return if waiting and id ~= "s1" then { text = `Hatch now · R$25 {id}`, enabled = true } else nil
			end, triggered)
			handle.update({})
			local prompt = egg:FindFirstChild(SlimeKeys.HATCH_NOW_PROMPT)
			expect(prompt ~= nil).toBe(true)
			expect(prompt.ActionText).toBe("Hatch now · R$25 e1")
			expect(prompt.KeyboardKeyCode).toBe("F")
			expect(plain:FindFirstChild(SlimeKeys.HATCH_NOW_PROMPT)).toBeNil()
			expect(other:FindFirstChild(SlimeKeys.HATCH_NOW_PROMPT)).toBeNil()
			prompt.Triggered:Fire()
			expect(triggered[1]).toBe("e1")
			-- the egg turns ready: the next tick drops the prompt (the server's Hatch takes over)
			waiting = false
			handle.tick()
			expect(egg:FindFirstChild(SlimeKeys.HATCH_NOW_PROMPT)).toBeNil()
		end
	)
	it("a disabled quick-buy (not on sale yet) shows but does not trigger", function()
		local root = instance("Folder", "Workspace")
		local eggModel, egg = slime("e1", ME, "Pad", true)
		parent(root, eggModel, root)
		local triggered = {}
		startHatch(root, function(): any
			return { text = "Not on sale yet", enabled = false }
		end, triggered)
		local prompt = egg:FindFirstChild(SlimeKeys.HATCH_NOW_PROMPT)
		prompt.Triggered:Fire()
		expect(#triggered).toBe(0)
	end)
end)
