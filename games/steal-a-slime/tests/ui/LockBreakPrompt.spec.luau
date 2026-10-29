--!strict
-- Open locked door (contract/exclusive-shop.md §11) on the client: ExclusiveShopView.lockBreakQuickBuy's rules (own,
-- free, open, locked, guest, a running break, flag off), the LockBreakPrompt door prompts through mock plots (aim
-- first, then Roblox's prompt; a credit; a refusal on the prompt), the HUD's "Lock break" timer slot, and GiftPlayers.
local Config = require("./UnsoldConfig") -- every Exclusive id cleared: the specs start from "not on sale yet"
local ExclusiveShopView = require("../../src/ui/ExclusiveShopView")
local Format = require("../../src/ui/Format")
local GiftPlayers = require("../../src/ui/GiftPlayers")
local HudClusters = require("../../src/ui/HudClusters")
local Layout = require("../../src/ui/Layout")
local LockBreakPrompt = require("../../src/ui/LockBreakPrompt")
local TestRunner = require("../TestRunner")

local describe, it, expect = TestRunner.describe, TestRunner.it, TestRunner.expect

local ME = 111
local OWNER = 222
local NOW = 1000

-- Config with a Roblox id on LockBreak.
local function sellingConfig(): any
	local shop = table.clone(Config.EXCLUSIVE_SHOP)
	local products = table.clone(shop.products)
	local def = table.clone(products.LockBreak)
	def.productId = 4242
	products.LockBreak = def
	shop.products = products
	local config = table.clone(Config)
	config.EXCLUSIVE_SHOP = shop
	return config
end

local function shopState(fields: { [string]: any }?): any
	local shop: any = {
		owned = {},
		passes = {},
		starterClaimed = true,
		credits = { brew = 0, hatch = 0 },
		paidRandomAllowed = true,
		featured = {},
		trails = {},
		batSkins = {},
		lockBreakCredits = 0,
		giftCredits = {},
	}
	for k, v in fields or {} do
		shop[k] = v
	end
	return { exclusiveShop = shop }
end

local function door(fields: { [string]: any }?): ExclusiveShopView.Door
	local d: any = { index = 3, owner = OWNER, locked = true, lockUntil = NOW + 60 }
	for k, v in fields or {} do
		d[k] = v
	end
	return d
end

describe("lockBreakQuickBuy", function()
	local config = sellingConfig()
	local function q(state: any, d: ExclusiveShopView.Door, canAim: boolean?, canCredit: boolean?): any
		return ExclusiveShopView.lockBreakQuickBuy(
			state,
			d,
			ME,
			NOW,
			config,
			if canAim == nil then true else canAim,
			if canCredit == nil then true else canCredit
		)
	end
	it("someone else's locked base: Open locked door with the price, prompting LockBreak", function()
		local buy = q(shopState(), door())
		expect(buy.mode).toBe("buy")
		expect(buy.text).toBe(`Open locked door · {Format.robux(Config.EXCLUSIVE_SHOP.products.LockBreak.robux)}`)
		expect(buy.text).toBe("Open locked door · R$499")
		expect(buy.purchase.id).toBe(4242)
	end)
	it("hidden on your own base, a free base, an open door and a lock that already ran out", function()
		expect(q(shopState(), door({ owner = ME }))).toBeNil()
		expect(q(shopState(), door({ owner = 0 }))).toBeNil()
		expect(q(shopState(), door({ locked = false }))).toBeNil()
		expect(q(shopState(), door({ lockUntil = NOW - 1 }))).toBeNil()
	end)
	it("hidden with the shop off (no State.exclusiveShop) or without AimLockBreak", function()
		expect(q({}, door())).toBeNil()
		expect(q(shopState(), door(), false, false)).toBeNil()
	end)
	it("hidden where the door already lets you through: a friend guest, your running lock break", function()
		expect(q(shopState(), door({ guests = `,{ME},` }))).toBeNil()
		expect(q(shopState(), door({ guests = ",999," })).mode).toBe("buy")
		local running = shopState({ lockBreak = { plot = 3, untilTime = NOW + 30 } })
		expect(q(running, door())).toBeNil()
		expect(q(running, door({ index = 4 })).mode).toBe("buy") -- another base still offers it
		local over = shopState({ lockBreak = { plot = 3, untilTime = NOW - 1 } })
		expect(q(over, door()).mode).toBe("buy")
	end)
	it("a saved lock break reads Use lock break (needs UseCredit)", function()
		local state = shopState({ lockBreakCredits = 2 })
		expect(q(state, door()).mode).toBe("credit")
		expect(q(state, door()).text).toBe("Use lock break")
		expect(q(state, door(), true, false).mode).toBe("buy")
	end)
	it("id 0: Not on sale yet", function()
		local off =
			ExclusiveShopView.lockBreakQuickBuy(shopState(), door(), ME, NOW, Config, true, true) :: ExclusiveShopView.QuickBuy
		expect(off.mode).toBe("offsale")
		expect(off.text).toBe("Not on sale yet")
	end)
	it("creditArg sends the plot index as UseCredit's target", function()
		expect(LockBreakPrompt.creditArg("target?", 5)).toBe(5)
		expect(LockBreakPrompt.creditArg("number?", 5)).toBe(5)
		expect(LockBreakPrompt.creditArg("string?", 5)).toBe("5")
	end)
end)

------------------------------------------------------------------ mock world
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

local function instance(className: string, name: string): any
	local attrs = {}
	local attrSignals = {}
	local data: any = {
		Name = name,
		ClassName = className,
		children = {},
		ChildAdded = signal(),
		ChildRemoved = signal(),
		Triggered = signal(),
		Enabled = true,
		ActionText = "",
		ObjectText = "",
		destroyed = false,
	}
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
	function self.GetChildren()
		return table.clone(self.children)
	end
	function self.FindFirstChild(_, childName)
		for _, child in self.children do
			if child.Name == childName and not child.destroyed then
				return child
			end
		end
		return nil
	end
	function self.Destroy()
		self.destroyed = true
		self.Parent = nil
	end
	return self
end

-- Plot_<i> with its LockBarrier.Stopper, owned by `owner`, locked or not.
local function plot(index: number, owner: number, locked: boolean): (any, any)
	local model = instance("Model", `Plot_{index}`)
	model:SetAttribute("PlotIndex", index)
	model:SetAttribute("OwnerUserId", owner)
	model:SetAttribute("Locked", locked)
	model:SetAttribute("LockUntil", if locked then NOW + 60 else 0)
	local barrier = instance("Model", "LockBarrier")
	barrier.Parent = model
	local stopper = instance("Part", "Stopper")
	stopper.Parent = barrier
	return model, stopper
end

local function world(opts: { [string]: any }?): any
	local o = opts or {}
	local plots = instance("Folder", "Plots")
	local asks = {}
	local prompted = {}
	local clockNow = 0
	local answer: any = o.answer or { ok = true }
	local w: any = { plots = plots, asks = asks, prompted = prompted }
	function w.tickClock(s: number)
		clockNow += s
	end
	function w.setAnswer(a: any)
		answer = a
	end
	w.handle = LockBreakPrompt.start({
		plots = plots,
		localUserId = ME,
		newPrompt = function(): any
			return instance("ProximityPrompt", "ProximityPrompt")
		end,
		config = o.config or sellingConfig(),
		serverNow = function()
			return NOW
		end,
		clock = function()
			return clockNow
		end,
		holdSeconds = Config.HOLD_CONFIRM_SECONDS,
		canAim = if o.canAim == nil then true else o.canAim,
		canUseCredit = true,
		creditArg = function(i: number): any
			return i
		end,
		ask = function(action: string, done: (any) -> (), ...: any)
			table.insert(asks, { action, ... })
			done(answer)
		end,
		purchase = {
			prompt = function(p: any): boolean
				table.insert(prompted, p)
				return true
			end,
		},
		attributes = {
			owner = "OwnerUserId",
			locked = "Locked",
			lockUntil = "LockUntil",
			guests = "Guests",
			index = "PlotIndex",
		},
	})
	return w
end

local function add(w: any, model: any)
	model.Parent = w.plots
	w.plots.ChildAdded:Fire(model)
end

describe("LockBreakPrompt (door prompts)", function()
	it("a locked base of someone else gets the prompt on its stopper; your own and open bases none", function()
		local w = world()
		w.handle.update(shopState())
		local other, stopper = plot(3, OWNER, true)
		local mine, myStopper = plot(1, ME, true)
		local open, openStopper = plot(2, OWNER, false)
		add(w, other)
		add(w, mine)
		add(w, open)
		local prompt = stopper:FindFirstChild(LockBreakPrompt.PROMPT)
		expect(prompt ~= nil).toBe(true)
		expect(prompt.Enabled).toBe(true)
		expect(prompt.ActionText).toBe("Open locked door · R$499")
		expect(prompt.HoldDuration).toBe(Config.HOLD_CONFIRM_SECONDS)
		expect(myStopper:FindFirstChild(LockBreakPrompt.PROMPT)).toBeNil()
		expect(openStopper:FindFirstChild(LockBreakPrompt.PROMPT)).toBeNil()
	end)
	it("follows the lock: unlocking disables it, locking again shows it", function()
		local w = world()
		w.handle.update(shopState())
		local model, stopper = plot(3, OWNER, true)
		add(w, model)
		local prompt = stopper:FindFirstChild(LockBreakPrompt.PROMPT)
		model:SetAttribute("Locked", false)
		expect(prompt.Enabled).toBe(false)
		model:SetAttribute("Locked", true)
		expect(prompt.Enabled).toBe(true)
	end)
	it("flag off (no State.exclusiveShop): no prompt at all", function()
		local w = world()
		w.handle.update({})
		local model, stopper = plot(3, OWNER, true)
		add(w, model)
		expect(stopper:FindFirstChild(LockBreakPrompt.PROMPT)).toBeNil()
		-- turns on with the shop, and off again
		w.handle.update(shopState())
		local prompt = stopper:FindFirstChild(LockBreakPrompt.PROMPT)
		expect(prompt.Enabled).toBe(true)
		w.handle.update({})
		expect(prompt.Enabled).toBe(false)
	end)
	it("a press aims at that plot first, then opens Roblox's prompt for LockBreak", function()
		local w = world()
		w.handle.update(shopState())
		local model, stopper = plot(3, OWNER, true)
		add(w, model)
		stopper:FindFirstChild(LockBreakPrompt.PROMPT).Triggered:Fire()
		expect(#w.asks).toBe(1)
		expect(w.asks[1][1]).toBe("AimLockBreak")
		expect(w.asks[1][2]).toBe(3)
		expect(#w.prompted).toBe(1)
		expect(w.prompted[1].id).toBe(4242)
	end)
	it("a refused aim opens no purchase and shows the server's reason for a while", function()
		local w = world({ answer = { ok = false, message = "That base just got robbed. Try again soon." } })
		w.handle.update(shopState())
		local model, stopper = plot(3, OWNER, true)
		add(w, model)
		local prompt = stopper:FindFirstChild(LockBreakPrompt.PROMPT)
		prompt.Triggered:Fire()
		expect(#w.prompted).toBe(0)
		expect(prompt.ObjectText).toBe("That base just got robbed. Try again soon.")
		w.tickClock(LockBreakPrompt.STYLE.refusalSeconds + 0.1)
		w.handle.tick()
		expect(prompt.ObjectText).toBe("")
		expect(prompt.ActionText).toBe("Open locked door · R$499")
	end)
	it("with a saved lock break it reads Use lock break and spends it with UseCredit, no purchase", function()
		local w = world()
		w.handle.update(shopState({ lockBreakCredits = 1 }))
		local model, stopper = plot(5, OWNER, true)
		add(w, model)
		local prompt = stopper:FindFirstChild(LockBreakPrompt.PROMPT)
		expect(prompt.ActionText).toBe("Use lock break")
		prompt.Triggered:Fire()
		expect(w.asks[1][1]).toBe("UseCredit")
		expect(w.asks[1][2]).toBe("lockBreak")
		expect(w.asks[1][3]).toBe(5)
		expect(#w.prompted).toBe(0)
	end)
	it("id 0: Not on sale yet, and a press does nothing", function()
		local w = world({ config = Config })
		w.handle.update(shopState())
		local model, stopper = plot(3, OWNER, true)
		add(w, model)
		local prompt = stopper:FindFirstChild(LockBreakPrompt.PROMPT)
		expect(prompt.ActionText).toBe("Not on sale yet")
		expect(prompt.ObjectText).toBe("Open locked door")
		prompt.Triggered:Fire()
		expect(#w.asks).toBe(0)
	end)
	it("a running lock break hides that door's prompt; destroy removes every prompt", function()
		local w = world()
		local model, stopper = plot(3, OWNER, true)
		add(w, model)
		w.handle.update(shopState())
		local prompt = stopper:FindFirstChild(LockBreakPrompt.PROMPT)
		w.handle.update(shopState({ lockBreak = { plot = 3, untilTime = NOW + 42 } }))
		expect(prompt.Enabled).toBe(false)
		w.handle.destroy()
		expect(stopper:FindFirstChild(LockBreakPrompt.PROMPT)).toBeNil()
	end)
end)

describe("HUD lock break timer", function()
	it("shows the time left as a status slot while the lock break runs", function()
		local slot = HudClusters.lockBreak({ plot = 3, untilTime = NOW + 42 }, NOW) :: HudClusters.Slot
		expect(slot.id).toBe("LockBreak")
		expect(slot.text).toBe("0:42")
		expect(slot.name).toBe("Lock break")
		expect(HudClusters.tooltip(slot).time).toBe("Time left: 0:42")
		expect(HudClusters.lockBreak({ plot = 3, untilTime = NOW - 1 }, NOW)).toBeNil()
		expect(HudClusters.lockBreak(nil, NOW)).toBeNil()
	end)
	it("is first in the status row, so a busy row never drops it", function()
		local slots = HudClusters.status(
			{
				rain = { active = true, endsAt = NOW + 30 },
				modifier = { label = "Dawn", luck = 2, endsAt = NOW + 100 },
				modifierEnabled = true,
				friends = { count = 1, bonus = 0.1 },
				friendsEnabled = true,
				blessed = { bonus = 0.3, endsAt = NOW + 179 },
				lockBreak = { plot = 3, untilTime = NOW + 42 },
			} :: any,
			NOW,
			Layout.STATUS.count
		)
		expect(slots[1].id).toBe("LockBreak")
		expect(#slots).toBe(Layout.STATUS.count)
		expect(table.concat(HudClusters.STATUS_IDS, ",")).toBe(table.concat(Layout.STATUS_SLOTS, ","))
	end)
	it("the HUD draws it: a LockBreak slot shows 0:42 while State has a running lock break", function()
		local UiHarness = require("./UiHarness")
		local gui = UiHarness.root()
		local hud = UiHarness.ui("Hud").new(gui, {
			Config = Config,
			Constants = require("../../src/shared/Constants"),
			Genome = require("../../src/shared/Genome"),
			actions = require("../../src/shared/Remotes").ACTIONS,
			send = function() end,
			request = function() end,
			serverNow = function()
				return NOW
			end,
			playerName = function()
				return "Tester"
			end,
			itemIcons = UiHarness.ui("ItemIcons").build(Config),
		})
		hud.layout(Layout.screen(1920, 1080))
		local function state(shop: any): any
			return {
				cash = 100,
				incomePerSec = 1,
				rebirths = 0,
				rebirthMultiplier = 1,
				padsUnlocked = 3,
				padsMax = 8,
				lockUntil = 0,
				lockStartedAt = 0,
				slimes = {},
				daily = {},
				rain = {},
				exclusiveShop = shop,
			}
		end
		hud.update(state(shopState({ lockBreak = { plot = 3, untilTime = NOW + 42 } }).exclusiveShop))
		local slot = UiHarness.find(UiHarness.find(gui, "Status"), "LockBreak")
		expect(slot.Visible).toBe(true)
		expect(UiHarness.find(slot, "Timer").Text).toBe("0:42")
		expect(UiHarness.find(slot, "Icon"):GetAttribute("ItemId")).toBe("Lock")
		hud.update(state(shopState().exclusiveShop))
		expect(slot.Visible).toBe(false)
	end)
end)

describe("GiftPlayers", function()
	local function fakePlayers(list: { any }): any
		return {
			PlayerAdded = signal(),
			PlayerRemoving = signal(),
			GetPlayers = function()
				return list
			end,
		}
	end
	it("lists everyone with their name; friends are looked up once and marked", function()
		local me: any = { UserId = ME, DisplayName = "Me" }
		local asked = {}
		function me.IsFriendsWith(_, id: number): boolean
			table.insert(asked, id)
			return id == 5
		end
		local roster = { me, { UserId = 5, DisplayName = "Pal" }, { UserId = 6, DisplayName = "Zed" } }
		local players = fakePlayers(roster)
		local handle = GiftPlayers.start(players, me, function(fn: () -> ())
			fn()
		end)
		local list = handle.list()
		expect(#list).toBe(3)
		local byId = {}
		for _, t in list do
			byId[t.userId] = t
		end
		expect(byId[5].friend).toBe(true)
		expect(byId[6].friend).toBe(false)
		expect(byId[5].name).toBe("Pal")
		expect(#asked).toBe(2) -- never asks about yourself
		-- ordered for the picker: you dropped, friends first
		local targets = ExclusiveShopView.giftTargets(list, ME)
		expect(#targets).toBe(2)
		expect(targets[1].userId).toBe(5)
		handle.stop()
	end)
end)
