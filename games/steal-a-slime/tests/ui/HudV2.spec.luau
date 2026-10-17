--!strict
-- H1 HUD layout (Merijn, 2026-10-17, hud_design_ref.png): left column = Plot, Rebirth, Goals, SlimeDex, Codes;
-- bottom-left = Money / Income / Rebirths; bottom-right = status icons with timers (events, friend boost),
-- never the weekend boost; no boss / specific-slime notifications; nothing of ours new top-right / top-middle.
local fs = require("@lune/fs")

local Config = require("../../src/shared/Config")
local Constants = require("../../src/shared/Constants")
local Genome = require("../../src/shared/Genome")
local HudClusters = require("../../src/ui/HudClusters")
local Layout = require("../../src/ui/Layout")
local LayoutAssert = require("./LayoutAssert")
local MenuClose = require("../../src/ui/MenuClose")
local Nav = require("../../src/ui/Nav")
local Remotes = require("../../src/shared/Remotes")
local TestRunner = require("../TestRunner")
local UiHarness = require("./UiHarness")

local describe, it, expect = TestRunner.describe, TestRunner.it, TestRunner.expect

local function read(path: string): string
	return fs.readFile(path)
end

local function has(text: string, needle: string): boolean
	return string.find(text, needle, 1, true) ~= nil
end

-- Config with the two features behind the status slots on, whatever the flag defaults / the flags-off run say.
local flagsOn = table.clone(Config) :: any
flagsOn.FEATURES = table.clone(Config.FEATURES)
flagsOn.FEATURES.CycleModifier = true
flagsOn.FEATURES.FriendBonus = true

local function ctx(): any
	return {
		Config = flagsOn,
		Constants = Constants,
		Genome = Genome,
		actions = Remotes.ACTIONS,
		send = function() end,
		request = function() end,
		serverNow = function()
			return 1000
		end,
		playerName = function()
			return "Tester"
		end,
		toast = function() end,
		itemIcons = UiHarness.ui("ItemIcons").build(Config),
	}
end

local function state(extra: { [string]: any }?): any
	local s: { [string]: any } = {
		cash = 2.37e9,
		incomePerSec = 5.93e6,
		rebirths = 8,
		rebirthMultiplier = 5,
		padsUnlocked = 3,
		padsMax = 8,
		lockUntil = 0,
		lockStartedAt = 0,
		slimes = {},
		daily = {},
		rain = {},
	}
	for k, v in extra or {} do
		s[k] = v
	end
	return s
end

-- A mounted Hud (with its Layout.screen applied) plus the root it lives in.
local function mount(w: number, h: number): (any, any, Layout.Screen)
	local gui = UiHarness.root()
	local hud = UiHarness.ui("Hud").new(gui, ctx())
	local screen = Layout.screen(w, h)
	hud.layout(screen)
	return hud, gui, screen
end

local function names(parent: any): { string }
	local out = {}
	for _, child in parent:GetChildren() do
		if not string.match(child.Name, "^UI") then -- UICorner, UIListLayout ...
			table.insert(out, child.Name)
		end
	end
	table.sort(out)
	return out
end

local function setAttributes(attrs: { [string]: any }?)
	for _, name in { "RainActive", "RainEndsAt", "RainNextAt" } do
		UiHarness.workspaceAttributes[name] = (attrs or {})[name]
	end
end

describe("H1 HUD: left button column", function()
	it("has exactly Plot, Rebirth, Goals, SlimeDex, Codes", function()
		local labels = {}
		for _, entry in Nav.ENTRIES do
			table.insert(labels, entry.label)
		end
		expect(table.concat(labels, ",")).toBe("Plot,Rebirth,Goals,SlimeDex,Codes")
	end)
	it("lays out the toggle plus those five buttons at every gate and landscape viewport", function()
		local viewports = {}
		for _, vp in LayoutAssert.GATE_VIEWPORTS do
			table.insert(viewports, vp)
		end
		for _, vp in LayoutAssert.LANDSCAPE_VIEWPORTS do
			table.insert(viewports, vp)
		end
		for _, vp in viewports do
			expect(`{vp.name}: {#Layout.screen(vp.w, vp.h).navButtons}`).toBe(`{vp.name}: 6`)
		end
	end)
	it("has no Merge / Shop / Top badges and no HUD Shop button", function()
		local badges = Nav.badges({
			cash = 1e9,
			slimes = { { slime = { id = "a", tier = 1 } }, { slime = { id = "b", tier = 1 } } },
			upgrades = { { id = "Income", price = 1, unlocked = true } },
		})
		expect(next(badges)).toBeNil()
		expect(Layout.HUD_ITEMS.Shop).toBeNil()
		expect(has(read("src/ui/Hud.luau"), '"Shop"')).toBe(false)
	end)
	it(
		"keeps the Merge, Shop and Top menus as panels without a nav button; the Shop still opens from its prompt",
		function()
			local init = read("src/ui/init.client.luau")
			expect(has(init, 'for _, key in { "Merge", "Shop", "Leaders" } do')).toBe(true)
			expect(has(init, "nav = nil, panel = panelByKey[key]")).toBe(true)
			expect(
				MenuClose.promptMenus(Constants.SHOP_PROMPT_NAME, Constants.GUIDE_PROMPT_NAME)[Constants.SHOP_PROMPT_NAME]
			).toBe("Shop")
			expect(has(read("src/ui/Panels/Shop.luau"), "setOpen")).toBe(true)
			expect(has(read("src/ui/Panels/Merge.luau"), "function Merge.new")).toBe(true)
			expect(has(read("src/ui/Panels/Leaderboard.luau"), "setBoard")).toBe(true)
		end
	)
end)

describe("H1 HUD: HudClusters (pure)", function()
	it("money shows cash, income/s and rebirths with the multiplier from State", function()
		local m = HudClusters.money(state())
		expect(m.cash).toBe("$2.37B")
		expect(m.income).toBe("$5.93M/s")
		expect(m.rebirths).toBe("8 x5")
		local empty = HudClusters.money({})
		expect(empty.rebirths).toBe("0 x1")
	end)
	it("shows Slime Rain with the time left, or a countdown for the last minutes", function()
		local active = HudClusters.rain({ active = true, endsAt = 1097 }, 1000) :: HudClusters.Slot
		expect(active.text).toBe("1:37")
		expect(active.icon).toBe("Event_rain")
		expect(active.kind).toBe("active")
		local soon = HudClusters.rain({ active = false, nextAt = 1100 }, 1000) :: HudClusters.Slot
		expect(soon.text).toBe("1:40")
		expect(soon.kind).toBe("soon")
		expect(HudClusters.rain({ active = false, nextAt = 5000 }, 1000)).toBeNil()
		expect(HudClusters.rain(nil, 1000)).toBeNil()
	end)
	it("shows the live modifier with its timer, and the friend boost without one", function()
		local mod = { name = "Admin_luck", label = "Luck Event", luck = 3, mutation = 1, endsAt = 1540, icon = "🍀" }
		local event = HudClusters.event(mod, 1000, true) :: HudClusters.Slot
		expect(event.text).toBe("9:00")
		expect(event.icon).toBe("Event_luck")
		expect(HudClusters.event(mod, 1000, false)).toBeNil()
		expect(HudClusters.event({ name = "None", label = "", luck = 1, mutation = 1 }, 1000, true)).toBeNil()
		local friend = HudClusters.friend({ count = 1, bonus = 0.1 }, true) :: HudClusters.Slot
		expect(friend.text).toBe("+10%")
		expect(friend.icon).toBe("FriendBoost")
		expect(HudClusters.friend({ count = 0, bonus = 0 }, true)).toBeNil()
	end)
	it("lists the slots left to right and never the weekend boost", function()
		local slots = HudClusters.status(
			{
				rain = { active = true, endsAt = 1097 },
				modifier = { name = "Admin_luck", label = "Luck", luck = 3, mutation = 1, endsAt = 1540 },
				modifierEnabled = true,
				friends = { count = 1, bonus = 0.1 },
				friendsEnabled = true,
				weekend = { active = true, multiplier = 2, endsAt = 90000 },
			} :: any,
			1000
		)
		local ids = {}
		for _, slot in slots do
			table.insert(ids, slot.id)
		end
		expect(table.concat(ids, ",")).toBe("Rain,Event,Friend")
		expect(#slots <= Layout.STATUS.count).toBe(true)
		for _, id in HudClusters.STATUS_IDS do
			expect(string.lower(id) ~= "weekend").toBe(true)
		end
		expect(table.concat(HudClusters.STATUS_IDS, ",")).toBe(table.concat(Layout.STATUS_SLOTS, ","))
	end)
end)

describe("H1 HUD: bottom-left cluster (mounted Hud)", function()
	it("shows money, income/s and rebirths from State, with their icons", function()
		setAttributes()
		local hud, gui = mount(1920, 1080)
		hud.update(state())
		expect(UiHarness.find(UiHarness.find(gui, "Money"), "Value").Text).toBe("$2.37B")
		local money = UiHarness.find(gui, "Money")
		expect(UiHarness.find(UiHarness.find(money, "Income"), "Value").Text).toBe("$5.93M/s")
		expect(UiHarness.find(UiHarness.find(money, "Rebirths"), "Value").Text).toBe("8 x5")
		expect(UiHarness.find(money, "Icon"):GetAttribute("ItemId")).toBe("Cash")
		expect(UiHarness.find(UiHarness.find(money, "Income"), "Icon"):GetAttribute("ItemId")).toBe("Income")
		expect(UiHarness.find(UiHarness.find(money, "Rebirths"), "Icon"):GetAttribute("ItemId")).toBe("Rebirth")
		hud.update(state({ cash = 12, incomePerSec = 0, rebirths = 1, rebirthMultiplier = 1.5 }))
		expect(UiHarness.find(UiHarness.find(gui, "Money"), "Value").Text).toBe("$12")
		expect(UiHarness.find(UiHarness.find(money, "Rebirths"), "Value").Text).toBe("1 x1.5")
	end)
	it("is not drawn in the top bar any more: no Cash / Income / Rebirths / Pads / Shop there", function()
		local _, gui = mount(1920, 1080)
		local bar = UiHarness.find(gui, "Hud")
		for _, name in { "Cash", "Income", "Rebirths", "Pads", "Shop" } do
			expect(UiHarness.find(bar, name)).toBeNil()
		end
		expect(UiHarness.find(bar, "Lock") ~= nil).toBe(true)
	end)
	it("sits in the bottom-left corner box of Layout.screen", function()
		local hud, gui, screen = mount(1920, 1080)
		hud.update(state())
		local root = UiHarness.find(gui, "Money")
		expect(root.Position.X.Offset).toBe(screen.money.rect.x)
		expect(root.Position.Y.Offset).toBe(screen.money.rect.y)
		expect(screen.money.rect.x).toBe(Layout.MARGIN)
		expect(screen.money.rect.y + screen.money.rect.h).toBe(screen.height - screen.bottomInset)
	end)
end)

describe("H1 HUD: bottom-right cluster (mounted Hud)", function()
	local function slot(gui: any, id: string): any
		return UiHarness.find(UiHarness.find(gui, "Status"), id)
	end
	it("shows Slime Rain with the countdown (cloud icon + m:ss), the live event and the friend boost", function()
		setAttributes({ RainActive = true, RainEndsAt = 1097 })
		local hud, gui, screen = mount(1920, 1080)
		hud.update(state({
			modifier = {
				name = "Admin_luck",
				label = "Luck Event",
				luck = 3,
				mutation = 1,
				endsAt = 1540,
				icon = "🍀",
			},
			friends = { count = 1, bonus = 0.1 },
		}))
		local rain = slot(gui, "Rain")
		expect(rain.Visible).toBe(true)
		expect(UiHarness.find(rain, "Timer").Text).toBe("1:37")
		expect(UiHarness.find(rain, "Icon"):GetAttribute("ItemId")).toBe("Event_rain")
		local event = slot(gui, "Event")
		expect(event.Visible).toBe(true)
		expect(UiHarness.find(event, "Timer").Text).toBe("9:00")
		local friend = slot(gui, "Friend")
		expect(friend.Visible).toBe(true)
		expect(UiHarness.find(friend, "Timer").Text).toBe("+10%")
		-- packed to the right edge, in the Layout.statusCluster slots, left to right
		local xs = {}
		for _, id in { "Rain", "Event", "Friend" } do
			table.insert(xs, slot(gui, id).Position.X.Offset)
		end
		expect(xs[1] < xs[2] and xs[2] < xs[3]).toBe(true)
		expect(xs[3] + Layout.STATUS.slot).toBe(screen.status.rect.w)
		setAttributes()
	end)
	it("shows only what is running and packs it to the right", function()
		setAttributes()
		local hud, gui, screen = mount(1920, 1080)
		hud.update(state({ friends = { count = 2, bonus = 0.2 } }))
		expect(slot(gui, "Rain").Visible).toBe(false)
		expect(slot(gui, "Event").Visible).toBe(false)
		expect(slot(gui, "Friend").Visible).toBe(true)
		expect(slot(gui, "Friend").Position.X.Offset + Layout.STATUS.slot).toBe(screen.status.rect.w)
		expect(UiHarness.find(slot(gui, "Friend"), "Timer").Text).toBe("+20%")
	end)
	it("never shows the weekend boost, whatever State.weekend says", function()
		setAttributes()
		local hud, gui = mount(1024, 768)
		hud.update(state({ weekend = { active = true, multiplier = 2, endsAt = 1000 + 90000 } }))
		for _, id in { "Rain", "Event", "Friend" } do
			expect(slot(gui, id).Visible).toBe(false)
		end
		for _, node in UiHarness.descendants(gui) do
			expect(string.find(string.lower(node.Name), "weekend", 1, true)).toBeNil()
		end
		expect(has(read("src/ui/Hud.luau"), "WeekendBadge")).toBe(false)
	end)
	it("an event shown here is gone from the old top banners", function()
		setAttributes({ RainActive = true, RainEndsAt = 1097 })
		local hud, gui = mount(1920, 1080)
		hud.update(state({ friends = { count = 1, bonus = 0.1 } }))
		local banners = UiHarness.find(gui, "Banners")
		for _, name in { "RainBanner", "ModifierBadge", "FriendBadge", "WeekendChip", "NextSpawnChip", "RareBanner" } do
			expect(UiHarness.find(banners, name)).toBeNil()
		end
		setAttributes()
	end)
end)

describe("H1 HUD: nothing new top-right / top-middle", function()
	local KEPT_BANNERS = "EggReveal,EventsBoard,PadHint,StealAlert" -- NO PLACE, see glitch-hud-inventory.md
	local KEPT_BAR = "BuyPad,Daily,Lock,LockStatus"
	it("the top banner stack holds only the kept (no-slot) notices", function()
		local _, gui = mount(1920, 1080)
		expect(table.concat(names(UiHarness.find(gui, "Banners")), ",")).toBe(`{KEPT_BANNERS}`)
	end)
	it("the top bar holds only the lock block, Lock, Buy pad and Daily", function()
		local _, gui = mount(1920, 1080)
		local bar = names(UiHarness.find(gui, "Hud"))
		local filtered = {}
		for _, name in bar do
			if name ~= "UICorner" then
				table.insert(filtered, name)
			end
		end
		expect(table.concat(filtered, ",")).toBe(KEPT_BAR)
	end)
	it("boss / specific-slime notices are gone: no Hud.onNotify, the Notify handler drops RareAnnounce news", function()
		local hud = mount(1920, 1080)
		expect(hud.onNotify).toBeNil()
		local init = read("src/ui/init.client.luau")
		expect(has(init, "if RareAnnounce.classify(message, sound) then\n\t\treturn\n\tend")).toBe(true)
		expect(has(init, "hud.onNotify")).toBe(false)
		local hudSrc = read("src/ui/Hud.luau")
		for _, needle in { "RareAnnounce", "BOSS_ATTRIBUTE", "NextSpawn", "RARE_SPAWN" } do
			expect(`{needle}: {has(hudSrc, needle)}`).toBe(`{needle}: false`)
		end
	end)
	it("both clusters sit on the bottom line (the touch-controls floor), below the HUD, at every viewport", function()
		local viewports = {}
		for _, vp in LayoutAssert.GATE_VIEWPORTS do
			table.insert(viewports, vp)
		end
		for _, vp in LayoutAssert.LANDSCAPE_VIEWPORTS do
			table.insert(viewports, vp)
		end
		for _, vp in viewports do
			local s = Layout.screen(vp.w, vp.h)
			local rise = if s.compact then math.ceil(Layout.TOUCH_RISE / s.scale) else 0
			local floor = s.height - s.bottomInset - rise
			expect(`{vp.name} money: {s.money.rect.y + s.money.rect.h == floor}`).toBe(`{vp.name} money: true`)
			expect(`{vp.name} status: {s.status.rect.y + s.status.rect.h == floor}`).toBe(`{vp.name} status: true`)
			expect(s.money.rect.x).toBe(Layout.MARGIN)
			expect(s.status.rect.x + s.status.rect.w).toBe(s.width - Layout.MARGIN)
			expect(s.money.rect.y >= s.hud.rect.y + s.hud.rect.h).toBe(true)
			expect(s.status.rect.y >= s.hud.rect.y + s.hud.rect.h).toBe(true)
			-- the corner the toasts / the sound slot use (top-right) stays theirs
			expect(Layout.overlaps(s.status.rect, s.sound)).toBe(false)
		end
	end)
end)

describe("H1 HUD: layout rules for the new clusters", function()
	local viewports = {}
	for _, vp in LayoutAssert.GATE_VIEWPORTS do
		table.insert(viewports, vp)
	end
	for _, vp in LayoutAssert.LANDSCAPE_VIEWPORTS do
		table.insert(viewports, vp)
	end
	for _, vp in viewports do
		for _, collapsed in { true, false } do
			local label = `{vp.name} nav {if collapsed then "collapsed" else "expanded"}`
			it(
				`{label}: on screen, above the touch controls, clear of nav, left column, cards, carry / SLAP!, tutorial; text fits`,
				function()
					local s = Layout.screen(vp.w, vp.h, { navCollapsed = collapsed })
					local check = LayoutAssert.new(label, s)
					LayoutAssert.clusterChecks(check)
					for _, list in { LayoutAssert.moneyTexts(s), LayoutAssert.statusTexts(s) } do
						for _, desc in list do
							check.text(desc)
						end
					end
					-- the left column (nav) and every bottom card, explicitly
					for _, cluster in { { "Money", s.money.rect }, { "Status", s.status.rect } } do
						local name, r = cluster[1] :: string, cluster[2] :: Layout.Rect
						check.noOverlap(name, r, "Nav", s.nav)
						for i, b in s.navButtons do
							check.noOverlap(name, r, `NavButton{i}`, b)
						end
						check.noOverlap(name, r, "Carry", s.carry)
						check.noOverlap(name, r, "Slap", s.slap)
						check.noOverlap(name, r, "Tutorial", s.tutorial)
						check.noOverlap(name, r, "TutorialCarrying", s.tutorialCarrying)
						check.noOverlap(name, r, "Hud", s.hud.rect)
					end
					expect(check.report()).toBe("")
				end
			)
		end
	end
	it("a phone's clusters clear the touch-controls strip plus the rise; desktop sits on the inset line", function()
		local phone = Layout.screen(390, 844)
		local rise = math.ceil(Layout.TOUCH_RISE / phone.scale)
		expect(phone.money.rect.y + phone.money.rect.h <= phone.height - phone.bottomInset - rise).toBe(true)
		local desktop = Layout.screen(1920, 1080)
		expect(desktop.money.rect.y + desktop.money.rect.h).toBe(desktop.height - desktop.bottomInset)
	end)
end)

describe("H1 HUD: Studio hooks keep working", function()
	it("the Pcw attributes that drive the HUD are still handled (and PcwRain fakes the rain slot)", function()
		local init = read("src/ui/init.client.luau")
		for _, attr in
			{ "PcwFriendBonus", "PcwAdminEvent", "PcwWeekend", "PcwStealAlert", "PcwWelcome", "PcwRain", "PcwOpen" }
		do
			expect(`{attr}: {has(init, `"{attr}"`)}`).toBe(`{attr}: true`)
		end
		expect(has(init, "ctx.forcedRain = forcedRain")).toBe(true)
	end)
	it("a forced rain wins over the workspace attributes", function()
		setAttributes({ RainActive = false })
		local c = ctx()
		c.forcedRain = function(): any
			return { active = true, endsAt = 1097 }
		end
		local gui = UiHarness.root()
		local hud = UiHarness.ui("Hud").new(gui, c)
		hud.update(state())
		expect(UiHarness.find(UiHarness.find(UiHarness.find(gui, "Status"), "Rain"), "Timer").Text).toBe("1:37")
		setAttributes()
	end)
end)
