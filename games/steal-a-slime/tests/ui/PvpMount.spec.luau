--!strict
-- FEATURES.PvP mount (src/ui/PvpMount): flag off = nothing built, nothing connected, no remote looked up; flag on =
-- hotbar + chips, PvpEvent / attribute / number-key wiring, equip / use through the injected send.
local Config = require("../../src/shared/Config")
local TestRunner = require("../TestRunner")
local UiHarness = require("./UiHarness")
local roblox = require("@lune/roblox") :: any

local describe, it, expect = TestRunner.describe, TestRunner.it, TestRunner.expect

local PvpMount = UiHarness.ui("PvpMount")
local PvpFixtures = require("./PvpFixtures")
local ItemIcons = UiHarness.ui("ItemIcons")
local Layout = UiHarness.ui("Layout")
local registry = ItemIcons.build(Config)

local signal, folder = PvpFixtures.signal, PvpFixtures.folder

local function player(): any
	local self: any = { attrs = {}, changed = signal(), reads = 0 }
	function self.GetAttribute(_self: any, name: string)
		self.reads += 1
		return self.attrs[name]
	end
	function self.GetAttributeChangedSignal(_self: any, _name: string)
		return self.changed
	end
	return self
end

local function env(enabled: boolean, extra: { [string]: any }?): any
	local gui = UiHarness.root()
	local banners = UiHarness.Instance.new("Frame")
	banners.Name = "Banners"
	banners.Parent = gui
	local e: any = {
		enabled = enabled,
		gui = gui,
		banners = banners,
		itemIcons = registry,
		clock = { t = 100 },
		sent = {},
		player = player(),
		input = { InputBegan = signal(), typing = false },
		remotes = folder(),
	}
	e.now = function()
		return e.clock.t
	end
	e.send = function(...: any)
		table.insert(e.sent, table.pack(...))
		return nil, nil
	end
	function e.input.GetFocusedTextBox(self: any)
		return if self.typing then {} else nil
	end
	for k, v in extra or {} do
		e[k] = v
	end
	return e
end

local function key(name: string): any
	return { UserInputType = roblox.Enum.UserInputType.Keyboard, KeyCode = roblox.Enum.KeyCode[name] }
end

describe("PvpMount with the flag off", function()
	it("returns nil and builds nothing, connects nothing, reads no remote and no attribute", function()
		local e = env(false, {
			root = folder(),
		})
		local before = #UiHarness.descendants(e.gui)
		expect(PvpMount.mount(e)).toBeNil()
		expect(#UiHarness.descendants(e.gui)).toBe(before)
		expect(e.gui:FindFirstChild("PvpHotbar")).toBeNil()
		expect(e.banners:FindFirstChild("PvpShield")).toBeNil()
		expect(e.player.changed.total).toBe(0)
		expect(e.player.reads).toBe(0)
		expect(e.input.InputBegan.total).toBe(0)
		expect(e.remotes.lookups).toBe(0)
		expect(e.remotes.ChildAdded.total).toBe(0)
		expect(e.root.lookups).toBe(0)
		expect(#e.sent).toBe(0)
	end)
	it("treats anything but true as off", function()
		for _, v in { false, "true", 1 } do
			local e = env(false)
			e.enabled = v
			expect(PvpMount.mount(e)).toBeNil()
			expect(#UiHarness.descendants(e.gui)).toBe(1) -- the Banners frame only
		end
	end)
end)

describe("PvpMount with the flag on", function()
	it("mounts the hotbar and chips, and shows exactly the state.pvp the server sent", function()
		local e = env(true)
		local m = PvpMount.mount(e)
		expect(m ~= nil).toBe(true)
		expect(e.gui:FindFirstChild("PvpHotbar") ~= nil).toBe(true)
		expect(e.banners:FindFirstChild("PvpShield") ~= nil and e.banners:FindFirstChild("PvpSafeZone") ~= nil).toBe(
			true
		)
		expect(#m.client.hotbarSlots()).toBe(0)
		m.applyState({ cash = 5 }) -- no state.pvp: nothing, never invented data
		expect(#m.client.hotbarSlots()).toBe(0)
		m.applyState({ pvp = PvpFixtures.pvp(30) })
		expect(#m.client.hotbarSlots()).toBe(11)
		local n = 0
		for _ in m.hud.views do
			n += 1
		end
		expect(n).toBe(11)
		m.applyState({ pvp = { rank = 1, owned = { KnockGlove1 = true }, best = { Knockback = "KnockGlove1" } } })
		expect(#m.client.hotbarSlots()).toBe(1)
		m.applyState({ cash = 5 })
		expect(#m.client.hotbarSlots()).toBe(0)
		m.destroy()
	end)

	it("a PvpEvent Cooldown draws the ring and the seconds; the Shield and SafeZone chips follow the server", function()
		local e = env(true)
		local m = PvpMount.mount(e)
		m.applyState({ pvp = PvpFixtures.pvp(6) })
		local slot = UiHarness.find(e.gui, "Slot_KnockGlove2")
		expect(slot ~= nil).toBe(true)
		expect(UiHarness.find(slot, "RightHalf").Visible).toBe(false)
		-- The event arrives after the Remotes folder gets it (ChildAdded path, never WaitForChild).
		expect(e.remotes.ChildAdded.live).toBe(1)
		local remote: any = { OnClientEvent = signal() }
		e.remotes:add("PvpEvent", remote)
		expect(remote.OnClientEvent.live).toBe(1)
		remote.OnClientEvent:Fire({ kind = "Cooldown", itemId = "KnockGlove2", startedAt = 100, duration = 8 })
		m.tick()
		expect(UiHarness.find(slot, "RightHalf").Visible).toBe(true)
		expect(UiHarness.find(slot, "LeftHalf").Visible).toBe(true)
		expect(UiHarness.find(slot, "Seconds").Visible).toBe(true)
		expect(UiHarness.find(slot, "Seconds").Text).toBe("8")
		e.clock.t = 106
		m.tick()
		expect(UiHarness.find(slot, "Seconds").Text).toBe("2")
		expect(UiHarness.find(slot, "LeftHalf").Visible).toBe(false) -- a quarter left
		e.clock.t = 109
		m.tick()
		expect(UiHarness.find(slot, "RightHalf").Visible).toBe(false)
		expect(UiHarness.find(slot, "Seconds").Visible).toBe(false)

		local shield = e.banners:FindFirstChild("PvpShield")
		local zone = e.banners:FindFirstChild("PvpSafeZone")
		expect(shield.Visible or zone.Visible).toBe(false)
		remote.OnClientEvent:Fire({ kind = "Shield", endsAt = 109 + 272.4 })
		remote.OnClientEvent:Fire({ kind = "SafeZone", zone = "Spawn", inside = true })
		expect(shield.Visible).toBe(true)
		expect(shield.Text).toBe("Shield 4:33")
		expect(zone.Visible).toBe(true)
		expect(zone.Text).toBe("Safe zone: Spawn")
		remote.OnClientEvent:Fire({ kind = "Shield" })
		remote.OnClientEvent:Fire({ kind = "SafeZone", zone = "Spawn", inside = false })
		expect(shield.Visible or zone.Visible).toBe(false)
		m.destroy()
	end)

	it("finds a PvpEvent that is already there, and waits for the Remotes folder when it is not", function()
		local e = env(true)
		local remote: any = { OnClientEvent = signal(), Name = "PvpEvent" }
		e.remotes.children.PvpEvent = remote
		local m = PvpMount.mount(e)
		expect(remote.OnClientEvent.live).toBe(1)
		expect(e.remotes.ChildAdded.total).toBe(0)
		m.destroy()
		expect(remote.OnClientEvent.live).toBe(0)

		local root = folder()
		local late = env(true, { remotes = false, root = root, remotesName = "Remotes", eventName = "PvpEvent" })
		late.remotes = nil
		local m2 = PvpMount.mount(late)
		expect(root.ChildAdded.live).toBe(1)
		local remotes = folder()
		remotes.children.PvpEvent = { OnClientEvent = signal() }
		root:add("Remotes", remotes)
		expect(remotes.children.PvpEvent.OnClientEvent.live).toBe(1)
		m2.destroy()
		expect(remotes.children.PvpEvent.OnClientEvent.live).toBe(0)
	end)

	it("reads the PvpShieldUntil attribute now and when it changes", function()
		local e = env(true)
		e.player.attrs.PvpShieldUntil = 160
		local m = PvpMount.mount(e)
		local active, left = m.client.shield()
		expect(active).toBe(true)
		expect(left).toBe(60)
		e.player.attrs.PvpShieldUntil = nil
		e.player.changed:Fire()
		expect(m.client.shield()).toBe(false)
		m.destroy()
		expect(e.player.changed.live).toBe(0)
	end)

	it("number keys equip the slot through EquipPvpItem; typing and processed input are ignored", function()
		local e = env(true)
		local m = PvpMount.mount(e)
		m.applyState({ pvp = PvpFixtures.pvp(6) }) -- KnockGlove2, GooTrap2, ...
		local input = e.input.InputBegan
		input:Fire(key("Two"), false)
		expect(#e.sent).toBe(1)
		expect(e.sent[1][1]).toBe("EquipPvpItem")
		expect(e.sent[1][2]).toBe("GooTrap2")
		input:Fire(key("Two"), true) -- the game already used the key
		e.input.typing = true
		input:Fire(key("One"), false)
		e.input.typing = false
		input:Fire(key("Nine"), false) -- no ninth slot
		input:Fire(key("W"), false)
		input:Fire({ UserInputType = roblox.Enum.UserInputType.MouseButton1, KeyCode = roblox.Enum.KeyCode.A }, false)
		expect(#e.sent).toBe(1)
		m.destroy()
		expect(input.live).toBe(0)
	end)

	it("a slot tap equips it and a second tap uses it; the instances go away on destroy", function()
		local e = env(true)
		local m = PvpMount.mount(e)
		m.applyState({ pvp = PvpFixtures.pvp(6) })
		expect(m.hud.views.GooTrap2 ~= nil).toBe(true)
		m.client.activate("GooTrap2")
		expect(e.sent[1][1]).toBe("EquipPvpItem")
		m.client.activate("KnockGlove2") -- the equipped one
		expect(e.sent[2][1]).toBe("UsePvpItem")
		m.layout(Layout.screen(1920, 1080))
		expect(e.gui:FindFirstChild("PvpHotbar").Visible).toBe(true)
		m.destroy()
		expect(e.gui:FindFirstChild("PvpHotbar")).toBeNil()
		expect(e.banners:FindFirstChild("PvpShield")).toBeNil()
		expect(#e.banners:GetChildren()).toBe(0)
	end)
end)
