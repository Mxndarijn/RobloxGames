--!strict
-- H1 HUD layout (Merijn, 2026-10-17, hud_design_ref.png): left column = Rebirth, Goals, SlimeDex, Codes (slimes are managed at their pads)
-- (Oct 18: a 2-column grid of rounded tiles, B5); bottom-left = Money / Income / Rebirths; bottom-right = status
-- icons with timers (events, friend boost), never the weekend boost, with a tooltip on hover / tap (B8); both
-- clusters bigger (B4); no top bar (B7), no toasts (B6), no boss / specific-slime notifications.
local Enum = require("@lune/roblox").Enum

local Config = require("../../src/shared/Config")
local Constants = require("../../src/shared/Constants")
local Genome = require("../../src/shared/Genome")
local HudClusters = require("../../src/ui/HudClusters")
local Layout = require("../../src/ui/Layout")
local LayoutAssert = require("./LayoutAssert")
local Nav = require("../../src/ui/Nav")
local Remotes = require("../../src/shared/Remotes")
local TestRunner = require("../TestRunner")
local UiHarness = require("./UiHarness")

local describe, it, expect = TestRunner.describe, TestRunner.it, TestRunner.expect

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
	it("lays out the four nav buttons at every gate and landscape viewport", function()
		local viewports = {}
		for _, vp in LayoutAssert.GATE_VIEWPORTS do
			table.insert(viewports, vp)
		end
		for _, vp in LayoutAssert.LANDSCAPE_VIEWPORTS do
			table.insert(viewports, vp)
		end
		for _, vp in viewports do
			expect(`{vp.name}: {#Layout.screen(vp.w, vp.h).navButtons}`).toBe(`{vp.name}: 4`)
		end
	end)
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
		local mod = { name = "Admin_luck", label = "Luck Event", luck = 3, endsAt = 1540, icon = "🍀" }
		local event = HudClusters.event(mod, 1000, true) :: HudClusters.Slot
		expect(event.text).toBe("9:00")
		expect(event.icon).toBe("Event_luck")
		expect(HudClusters.event(mod, 1000, false)).toBeNil()
		expect(HudClusters.event({ name = "None", label = "", luck = 1 }, 1000, true)).toBeNil()
		local friend = HudClusters.friend({ count = 1, bonus = 0.1 }, true) :: HudClusters.Slot
		expect(friend.text).toBe("+10%")
		expect(friend.icon).toBe("FriendBoost")
		expect(HudClusters.friend({ count = 0, bonus = 0 }, true)).toBeNil()
	end)
	it("lists the slots left to right and never the weekend boost", function()
		local slots = HudClusters.status(
			{
				rain = { active = true, endsAt = 1097 },
				modifier = { name = "Admin_luck", label = "Luck", luck = 3, endsAt = 1540 },
				modifierEnabled = true,
				friends = { count = 1, bonus = 0.1 },
				friendsEnabled = true,
				blessed = { bonus = 0.3, endsAt = 1179 },
				weekend = { active = true, multiplier = 2, endsAt = 90000 },
			} :: any,
			1000,
			Layout.STATUS.count
		)
		local ids = {}
		for _, slot in slots do
			table.insert(ids, slot.id)
		end
		expect(table.concat(ids, ",")).toBe("Rain,Event,Friend,Blessed")
		expect(#slots <= Layout.STATUS.count).toBe(true)
		for _, id in HudClusters.STATUS_IDS do
			expect(string.lower(id) ~= "weekend").toBe(true)
		end
		expect(table.concat(HudClusters.STATUS_IDS, ",")).toBe(table.concat(Layout.STATUS_SLOTS, ","))
	end)
	it("five things running still show four: the featured Secret makes way", function()
		local slots = HudClusters.status(
			{
				rain = { active = true, endsAt = 1030 },
				modifier = { label = "Dawn", luck = 2, endsAt = 1100 },
				modifierEnabled = true,
				friends = { count = 1, bonus = 0.1 },
				friendsEnabled = true,
				blessed = { bonus = 0.3, endsAt = 1179 },
				featuredSecret = { id = "x", name = "Glim", endsAt = 1000 + 3600 },
			} :: any,
			1000,
			Layout.STATUS.count
		)
		expect(#slots).toBe(Layout.STATUS.count)
		local ids = {}
		for _, slot in slots do
			table.insert(ids, slot.id)
		end
		expect(table.concat(ids, ",")).toBe("Rain,Event,Friend,Blessed")
	end)
end)

describe("H1 HUD: bottom-left cluster (mounted Hud)", function()
	it("shows money, income/s and rebirths from State, with their icons", function()
		setAttributes()
		local hud, gui = mount(1920, 1080)
		hud.update(state())
		-- The coin carries the "$", so the amount shows without it; the income chip reads "+5.93M/s".
		expect(UiHarness.find(UiHarness.find(gui, "Money"), "Value").Text).toBe("2.37B")
		local money = UiHarness.find(gui, "Money")
		expect(UiHarness.find(UiHarness.find(money, "Income"), "Value").Text).toBe("+5.93M/s")
		local rebirths = UiHarness.find(money, "Rebirths")
		expect(UiHarness.find(rebirths, "Value").Text).toBe("8")
		expect(UiHarness.find(UiHarness.find(rebirths, "Multiplier"), "Value").Text).toBe("x5")
		-- the coin is drawn (the Cash icon is a pile): a face with a "$" sign
		local coin = UiHarness.find(UiHarness.find(money, "Cash"), "Icon")
		expect(UiHarness.find(coin, "Sign").Text).toBe("$")
		expect(UiHarness.find(rebirths, "Icon"):GetAttribute("ItemId")).toBe("Rebirth")
		hud.update(state({ cash = 12, incomePerSec = 0, rebirths = 1, rebirthMultiplier = 1.5 }))
		expect(UiHarness.find(UiHarness.find(gui, "Money"), "Value").Text).toBe("12")
		expect(UiHarness.find(UiHarness.find(money, "Rebirths"), "Value").Text).toBe("1")
		expect(UiHarness.find(UiHarness.find(UiHarness.find(money, "Rebirths"), "Multiplier"), "Value").Text).toBe(
			"x1.5"
		)
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
		expect(xs[3] + Layout.statusSlotWidth(false)).toBe(screen.status.rect.w)
		setAttributes()
	end)
	it("shows only what is running and packs it to the right", function()
		setAttributes()
		local hud, gui, screen = mount(1920, 1080)
		hud.update(state({ friends = { count = 2, bonus = 0.2 } }))
		expect(slot(gui, "Rain").Visible).toBe(false)
		expect(slot(gui, "Event").Visible).toBe(false)
		expect(slot(gui, "Friend").Visible).toBe(true)
		expect(slot(gui, "Friend").Position.X.Offset + Layout.statusSlotWidth(false)).toBe(screen.status.rect.w)
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
	end)
end)

-- The featured event Secret is a status slot (rightmost) with the time until it rotates, not a top banner.
describe("H1 HUD: featured Secret status slot", function()
	local FEATURED = { id = "origami", name = "Origami", endsAt = 1000 + 4 * 3600 + 6 * 60 }
	local function slot(gui: any, id: string): any
		return UiHarness.find(UiHarness.find(gui, "Status"), id)
	end

	it("words the slot and its tooltip: time until it rotates, can spawn as a Secret this week", function()
		local secret = HudClusters.secret(FEATURED, 1000) :: HudClusters.Slot
		expect(secret.id).toBe("Secret")
		expect(secret.text).toBe("4h 6m")
		expect(secret.icon).toBe(HudClusters.ICONS.Secret)
		local tip = HudClusters.tooltip(secret)
		expect(tip.title).toBe("Featured Secret: Origami")
		expect(tip.body).toBe("Can spawn as a Secret this week.")
		expect(tip.time).toBe("Ends in 4h 6m")
		expect((HudClusters.secret({ id = "o", name = "O", endsAt = 1000 + 3 * 86400 + 4 * 3600 }, 1000) :: any).text).toBe(
			"3d 4h"
		)
		expect((HudClusters.secret({ id = "o", name = "O", endsAt = 1125 }, 1000) :: any).text).toBe("2:05")
	end)

	it("no slot when the featured Secret is absent, malformed or over", function()
		expect(HudClusters.secret(nil, 1000)).toBeNil()
		expect(HudClusters.secret({ id = "o", name = "", endsAt = 2000 } :: any, 1000)).toBeNil()
		expect(HudClusters.secret({ id = "o", name = "O", endsAt = 0 / 0 } :: any, 1000)).toBeNil()
		expect(HudClusters.secret({ id = "o", name = "O", endsAt = 1000 }, 1000)).toBeNil()
	end)

	it("the mounted slot shows the icon and the rotate timer, rightmost, next to the other events", function()
		setAttributes({ RainActive = true, RainEndsAt = 1097 })
		local hud, gui, screen = mount(1920, 1080)
		hud.update(state({ featuredSecret = FEATURED, friends = { count = 1, bonus = 0.1 } }))
		local secret = slot(gui, "Secret")
		expect(secret.Visible).toBe(true)
		expect(UiHarness.find(secret, "Timer").Text).toBe("4h 6m")
		expect(UiHarness.find(secret, "Icon"):GetAttribute("ItemId")).toBe(HudClusters.ICONS.Secret)
		expect(secret.Position.X.Offset + Layout.statusSlotWidth(false)).toBe(screen.status.rect.w)
		expect(slot(gui, "Friend").Position.X.Offset < secret.Position.X.Offset).toBe(true)
		expect(slot(gui, "Rain").Position.X.Offset < slot(gui, "Friend").Position.X.Offset).toBe(true)
		hud.update(state({ friends = { count = 1, bonus = 0.1 } }))
		expect(secret.Visible).toBe(false)
		setAttributes()
	end)

	it("shows the ritual's Blessed boost with its time left, and nothing once it ends", function()
		local blessed = HudClusters.blessed({ bonus = 0.3, endsAt = 1179 }, 1000) :: HudClusters.Slot
		expect(blessed.text).toBe("2:59")
		expect(blessed.icon).toBe("Boost_Blessed")
		expect(blessed.kind).toBe("active")
		local tip = HudClusters.tooltip(blessed)
		expect(tip.title).toBe("Blessed")
		expect(tip.body).toBe("+30% income from the Slime Ritual.")
		expect(tip.time).toBe("Time left: 2:59")
		expect(HudClusters.blessed(nil, 1000)).toBeNil()
		expect(HudClusters.blessed({ bonus = 0.3, endsAt = 1000 }, 1000)).toBeNil()
		expect(HudClusters.blessed({ bonus = 0, endsAt = 2000 }, 1000)).toBeNil()
		expect(HudClusters.blessed({ bonus = 0.3, endsAt = 0 / 0 } :: any, 1000)).toBeNil()
	end)

	it("with all five events running, the featured Secret makes way for the row's four places", function()
		local all = {
			rain = { active = true, endsAt = 1097 },
			modifier = { name = "Admin_luck", label = "Luck", luck = 3, endsAt = 1540 },
			modifierEnabled = true,
			friends = { count = 1, bonus = 0.1 },
			friendsEnabled = true,
			blessed = { bonus = 0.3, endsAt = 1179 },
			featuredSecret = FEATURED,
		}
		local function ids(input: any): string
			local out = {}
			for _, s in HudClusters.status(input, 1000, Layout.STATUS.count) do
				table.insert(out, s.id)
			end
			return table.concat(out, ",")
		end
		expect(ids(all)).toBe("Rain,Event,Friend,Blessed")
		all.blessed = nil
		expect(ids(all)).toBe("Rain,Event,Friend,Secret")
	end)

	it("shows the follow pet's perk as an untimed Pet slot with its own icon and tooltip", function()
		local luck = HudClusters.pet({ kind = "luck", value = 0.03, icon = "x", text = "+3% luck" }) :: HudClusters.Slot
		expect(luck.id).toBe("Pet")
		expect(luck.text).toBe("+3%")
		expect(luck.icon).toBe(HudClusters.ICONS.Pet)
		local tip = HudClusters.tooltip(luck)
		expect(tip.title).toBe("Pet bonus")
		expect(string.find(tip.body, "+3% luck", 1, true) ~= nil).toBe(true)
		expect(tip.time).toBe("Active while your pet follows you")
		local income = HudClusters.pet({ kind = "income", value = 0.08, icon = "x", text = "+8% income" }) :: any
		expect(income.text).toBe("+8%")
		expect(string.find(income.effect, "+8% income", 1, true) ~= nil).toBe(true)
		expect(HudClusters.pet(nil)).toBeNil()
		expect(HudClusters.pet({ kind = "luck", value = 0, icon = "x", text = "" })).toBeNil()
		expect(HudClusters.pet({ kind = "luck", value = 0 / 0, icon = "x", text = "" } :: any)).toBeNil()
		expect(HudClusters.pet({ kind = "speed", value = 0.03, icon = "x", text = "" })).toBeNil()
	end)

	it("the Pet slot makes way after the featured Secret when the row is full", function()
		local all: any = {
			rain = { active = true, endsAt = 1097 },
			modifier = { name = "Admin_luck", label = "Luck", luck = 3, endsAt = 1540 },
			modifierEnabled = true,
			friends = { count = 1, bonus = 0.1 },
			friendsEnabled = true,
			blessed = { bonus = 0.3, endsAt = 1179 },
			petPerk = { kind = "luck", value = 0.03, icon = "x", text = "+3% luck" },
			featuredSecret = FEATURED,
		}
		local function ids(): string
			local out = {}
			for _, s in HudClusters.status(all, 1000, Layout.STATUS.count) do
				table.insert(out, s.id)
			end
			return table.concat(out, ",")
		end
		expect(ids()).toBe("Rain,Event,Friend,Blessed")
		all.blessed = nil
		expect(ids()).toBe("Rain,Event,Friend,Pet")
		all.rain = nil
		expect(ids()).toBe("Event,Friend,Pet,Secret")
	end)

	it("the mounted Pet slot sits between Blessed and the featured Secret", function()
		local hud, gui = mount(1920, 1080)
		hud.update(state({
			blessed = { bonus = 0.3, endsAt = 1179 },
			petPerk = { kind = "income", value = 0.05, icon = "x", text = "+5% income" },
			featuredSecret = FEATURED,
		}))
		local pet = slot(gui, "Pet")
		expect(pet.Visible).toBe(true)
		expect(UiHarness.find(pet, "Timer").Text).toBe("+5%")
		expect(UiHarness.find(pet, "Icon"):GetAttribute("ItemId")).toBe(HudClusters.ICONS.Pet)
		expect(slot(gui, "Blessed").Position.X.Offset < pet.Position.X.Offset).toBe(true)
		expect(pet.Position.X.Offset < slot(gui, "Secret").Position.X.Offset).toBe(true)
		hud.update(state({ featuredSecret = FEATURED }))
		expect(pet.Visible).toBe(false)
	end)

	it("the mounted Blessed slot sits between the friend boost and the featured Secret", function()
		local hud, gui = mount(1920, 1080)
		hud.update(state({
			blessed = { bonus = 0.3, endsAt = 1179 },
			featuredSecret = FEATURED,
			friends = { count = 1, bonus = 0.1 },
		}))
		local blessed = slot(gui, "Blessed")
		expect(blessed.Visible).toBe(true)
		expect(UiHarness.find(blessed, "Timer").Text).toBe("2:59")
		expect(UiHarness.find(blessed, "Icon"):GetAttribute("ItemId")).toBe(HudClusters.ICONS.Blessed)
		expect(slot(gui, "Friend").Position.X.Offset < blessed.Position.X.Offset).toBe(true)
		expect(blessed.Position.X.Offset < slot(gui, "Secret").Position.X.Offset).toBe(true)
		hud.update(state({ featuredSecret = FEATURED }))
		expect(blessed.Visible).toBe(false)
	end)

	it("hover shows the featured Secret tooltip", function()
		UiHarness.lastInputType = Enum.UserInputType.MouseMovement
		local hud, gui = mount(1920, 1080)
		hud.update(state({ featuredSecret = FEATURED }))
		UiHarness.fire(slot(gui, "Secret"), "MouseEnter")
		local tip = UiHarness.find(gui, "Tooltip")
		expect(tip.Visible).toBe(true)
		expect(UiHarness.find(tip, "Title").Text).toBe("Featured Secret: Origami")
		expect(UiHarness.find(tip, "Body").Text).toBe("Can spawn as a Secret this week.")
		expect(UiHarness.find(tip, "Time").Text).toBe("Ends in 4h 6m")
		UiHarness.fire(slot(gui, "Secret"), "MouseLeave")
	end)

	for _, vp in LayoutAssert.GATE_VIEWPORTS do
		it(
			`{vp.name}: each timer is a pill centred on its icon's bottom edge, inside the slot, its text fitting`,
			function()
				setAttributes({ RainActive = true, RainEndsAt = 1000 + 3725 })
				local hud, gui, screen = mount(vp.w, vp.h)
				hud.update(state({
					featuredSecret = { id = "o", name = "Origami", endsAt = 1000 + 6 * 86400 + 23 * 3600 },
					friends = { count = 20, bonus = 1 },
					blessed = { bonus = 0.3, endsAt = 1000 + 179 },
				}))
				local sm = Layout.statusMetrics(screen.compact, screen.tight)
				local check = LayoutAssert.new(vp.name, screen)
				for _, id in { "Rain", "Friend", "Blessed", "Secret" } do
					local frame = slot(gui, id)
					local pill = UiHarness.find(frame, "Timer")
					expect(`{id} anchor {pill.AnchorPoint.X} at {pill.Position.X.Scale}`).toBe(`{id} anchor 0.5 at 0.5`)
					expect(pill.Position.Y.Offset).toBe(sm.icon - sm.overlap)
					expect(pill.Position.Y.Offset + pill.Size.Y.Offset).toBe(frame.Size.Y.Offset)
					expect(pill.Size.X.Offset <= frame.Size.X.Offset).toBe(true)
					expect(pill.TextSize).toBe(sm.textSize)
					check.text({
						name = `{id} pill`,
						text = pill.Text,
						size = pill.TextSize,
						bold = true,
						w = pill.Size.X.Offset,
						h = pill.Size.Y.Offset,
					})
				end
				expect(check.report()).toBe("")
				setAttributes()
			end
		)
	end

	it("the event buttons are big enough to tap on a phone and bigger than the money chips on PC", function()
		for _, vp in LayoutAssert.GATE_VIEWPORTS do
			local s = Layout.screen(vp.w, vp.h)
			local sm = Layout.statusMetrics(s.compact, s.tight)
			expect(`{vp.name} slot {sm.slot * s.scale >= Layout.MIN_TOUCH - 10}`).toBe(`{vp.name} slot true`)
		end
		expect(Layout.statusMetrics(false).icon > Layout.MONEY.chip).toBe(true)
	end)

	it("a full row of events fits at every gate size: inside the row, none overlapping", function()
		for _, vp in LayoutAssert.GATE_VIEWPORTS do
			local s = Layout.screen(vp.w, vp.h)
			expect(#s.status.slots).toBe(Layout.STATUS.count)
			local check = LayoutAssert.new(vp.name, s)
			LayoutAssert.clusterChecks(check)
			expect(check.report()).toBe("")
		end
	end)
end)

describe("H1 HUD: nothing new top-right / top-middle", function()
	local KEPT_BANNERS = "StealAlert" -- top centre; the featured Secret is a status slot
	it("the top banner stack holds only the kept (no-slot) notices", function()
		local _, gui = mount(1920, 1080)
		expect(table.concat(names(UiHarness.find(gui, "Banners")), ",")).toBe(`{KEPT_BANNERS}`)
	end)
	it("both clusters sit on the bottom line (the touch-controls floor), the desktop events row above it", function()
		local viewports = {}
		for _, vp in LayoutAssert.GATE_VIEWPORTS do
			table.insert(viewports, vp)
		end
		for _, vp in LayoutAssert.LANDSCAPE_VIEWPORTS do
			table.insert(viewports, vp)
		end
		for _, vp in viewports do
			local s = Layout.screen(vp.w, vp.h)
			local rise = Layout.rowRise(s)
			local floor = s.height - s.bottomInset - rise
			expect(`{vp.name} money: {s.money.rect.y + s.money.rect.h == floor}`).toBe(`{vp.name} money: true`)
			-- off phones the events row stands STATUS.raise above that line (0: level with it)
			local statusFloor = floor - (if s.phone then 0 else Layout.STATUS.raise)
			expect(`{vp.name} status: {s.status.rect.y + s.status.rect.h == statusFloor}`).toBe(
				`{vp.name} status: true`
			)
			expect(s.money.rect.x).toBe(Layout.MARGIN)
			expect(s.status.rect.x + s.status.rect.w).toBe(s.width - Layout.MARGIN)
			-- the corner the sound slot uses (top-right) stays its
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
		do
			local label = vp.name
			it(
				`{label}: on screen, above the touch controls, clear of nav, left column, cards, carry, tutorial; text fits`,
				function()
					local s = Layout.screen(vp.w, vp.h)
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
						check.noOverlap(name, r, "Tutorial", s.tutorial)
						check.noOverlap(name, r, "TutorialCarrying", s.tutorialCarrying)
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

-- B8: a status icon explains itself: mouse hover on PC, a tap on touch (a second tap or a tap elsewhere closes it).
describe("H1 HUD: status icon tooltip (B8)", function()
	local EVENT = { name = "Admin_luck", label = "Luck Event", luck = 3, endsAt = 1540, icon = "🍀" }

	local function running(w: number, h: number): (any, any, Layout.Screen)
		setAttributes({ RainActive = true, RainEndsAt = 1097 })
		local hud, gui, screen = mount(w, h)
		hud.update(state({ modifier = EVENT, friends = { count = 1, bonus = 0.1 } }))
		return hud, gui, screen
	end
	local function slot(gui: any, id: string): any
		return UiHarness.find(UiHarness.find(gui, "Status"), id)
	end
	local function tip(gui: any): any
		return UiHarness.find(gui, "Tooltip")
	end

	it("words name, effect and time left for each kind of slot", function()
		local rain = HudClusters.tooltip(HudClusters.rain({ active = true, endsAt = 1097 }, 1000) :: HudClusters.Slot)
		expect(rain.title).toBe("Slime Rain")
		expect(rain.body).toBe(HudClusters.RAIN_EFFECT)
		expect(rain.time).toBe("Time left: 1:37")
		local soon = HudClusters.tooltip(HudClusters.rain({ active = false, nextAt = 1100 }, 1000) :: HudClusters.Slot)
		expect(soon.time).toBe("Starts in 1:40")
		local luck = HudClusters.tooltip(HudClusters.event(EVENT, 1000, true) :: HudClusters.Slot)
		expect(luck.title).toBe("Luck Event")
		expect(luck.body).toBe("x3 luck: rarer slimes show up more often.")
		expect(luck.time).toBe("Time left: 9:00")
		local untimed = { name = "Dusk", label = "Dusk", luck = 2 }
		expect(HudClusters.tooltip(HudClusters.event(untimed, 1000, true) :: HudClusters.Slot).time).toBe("Active now")
		local friend = HudClusters.tooltip(HudClusters.friend({ count = 1, bonus = 0.1 }, true) :: HudClusters.Slot)
		expect(friend.title).toBe("Friend boost")
		expect(friend.body).toBe("+10% income while your friends play on this server.")
	end)

	it("the open / close rule: hover on PC, tap toggles on touch, a press elsewhere closes", function()
		local next = HudClusters.nextTooltip
		expect(next(nil, "hover", "Rain", false)).toBe("Rain")
		expect(next("Rain", "leave", "Rain", false)).toBeNil()
		expect(next("Rain", "hover", "Event", false)).toBe("Event")
		expect(next(nil, "hover", "Rain", true)).toBeNil() -- a touch fires MouseEnter too: ignored
		expect(next("Rain", "leave", "Rain", true)).toBe("Rain")
		expect(next(nil, "tap", "Rain", true)).toBe("Rain")
		expect(next("Rain", "tap", "Rain", true)).toBeNil() -- the second tap closes
		expect(next("Rain", "tap", "Event", true)).toBe("Event")
		expect(next("Rain", "tap", "Rain", false)).toBe("Rain") -- a mouse click keeps the hover card
		expect(next("Rain", "press", nil, true)).toBeNil() -- a tap elsewhere
		expect(next("Rain", "press", "Rain", true)).toBe("Rain") -- on the icon itself: its own tap decides
		expect(next("Rain", "press", "Event", false)).toBeNil()
	end)

	it("hover opens the tooltip over the icon and leaving closes it (mouse)", function()
		UiHarness.lastInputType = Enum.UserInputType.MouseMovement
		local _, gui = running(1920, 1080)
		expect(tip(gui).Visible).toBe(false)
		UiHarness.fire(slot(gui, "Event"), "MouseEnter")
		expect(tip(gui).Visible).toBe(true)
		expect(UiHarness.find(tip(gui), "Title").Text).toBe("Luck Event")
		expect(UiHarness.find(tip(gui), "Body").Text).toBe("x3 luck: rarer slimes show up more often.")
		expect(UiHarness.find(tip(gui), "Time").Text).toBe("Time left: 9:00")
		UiHarness.fire(slot(gui, "Event"), "MouseLeave")
		expect(tip(gui).Visible).toBe(false)
		setAttributes()
	end)

	it("a tap opens it, a second tap closes it, a tap elsewhere closes it (touch)", function()
		UiHarness.lastInputType = Enum.UserInputType.Touch
		local _, gui, screen = running(390, 844)
		UiHarness.fire(slot(gui, "Rain"), "MouseEnter") -- touch also fires hover: ignored
		expect(tip(gui).Visible).toBe(false)
		UiHarness.fire(slot(gui, "Rain"), "Activated")
		expect(tip(gui).Visible).toBe(true)
		expect(UiHarness.find(tip(gui), "Title").Text).toBe("Slime Rain")
		-- a press on the open icon leaves it to its own tap; the second tap closes
		local r = Layout.statusSlot(screen.status, 1, 3)
		UiHarness.press("Touch", (r.x + r.w / 2) * screen.scale, (r.y + r.h / 2) * screen.scale)
		expect(tip(gui).Visible).toBe(true)
		UiHarness.fire(slot(gui, "Rain"), "Activated")
		expect(tip(gui).Visible).toBe(false)
		-- open again, then tap on the empty world
		UiHarness.fire(slot(gui, "Rain"), "Activated")
		expect(tip(gui).Visible).toBe(true)
		UiHarness.press("Touch", 20, 20)
		expect(tip(gui).Visible).toBe(false)
		UiHarness.lastInputType = Enum.UserInputType.MouseMovement
		setAttributes()
	end)

	it("opening one icon's tooltip replaces another's, and the time left follows the clock", function()
		UiHarness.lastInputType = Enum.UserInputType.Touch
		local hud, gui = running(1920, 1080)
		UiHarness.fire(slot(gui, "Rain"), "Activated")
		UiHarness.fire(slot(gui, "Friend"), "Activated")
		expect(UiHarness.find(tip(gui), "Title").Text).toBe("Friend boost")
		UiHarness.fire(slot(gui, "Rain"), "Activated")
		expect(UiHarness.find(tip(gui), "Time").Text).toBe("Time left: 1:37")
		setAttributes({ RainActive = true, RainEndsAt = 1060 })
		hud.tick(1000)
		expect(UiHarness.find(tip(gui), "Time").Text).toBe("Time left: 1:00")
		UiHarness.lastInputType = Enum.UserInputType.MouseMovement
		setAttributes()
	end)

	it("closes when its slot goes away or a menu opens", function()
		UiHarness.lastInputType = Enum.UserInputType.Touch
		local hud, gui = running(1920, 1080)
		UiHarness.fire(slot(gui, "Rain"), "Activated")
		setAttributes() -- the rain is over
		hud.tick(1000)
		expect(tip(gui).Visible).toBe(false)
		setAttributes({ RainActive = true, RainEndsAt = 1097 })
		hud.tick(1000)
		expect(tip(gui).Visible).toBe(false) -- stays closed
		UiHarness.fire(slot(gui, "Rain"), "Activated")
		expect(tip(gui).Visible).toBe(true)
		hud.setMenuOpen(true)
		expect(tip(gui).Visible).toBe(false)
		hud.setMenuOpen(false)
		expect(tip(gui).Visible).toBe(false)
		UiHarness.lastInputType = Enum.UserInputType.MouseMovement
		setAttributes()
	end)

	it("stays on screen for every card over every slot at all LayoutAssert sizes, and is placed by Layout", function()
		local viewports = {}
		for _, vp in LayoutAssert.GATE_VIEWPORTS do
			table.insert(viewports, vp)
		end
		for _, vp in LayoutAssert.LANDSCAPE_VIEWPORTS do
			table.insert(viewports, vp)
		end
		for _, vp in viewports do
			local s = Layout.screen(vp.w, vp.h)
			for i, slotRect in s.status.slots do
				for k, card in LayoutAssert.tooltipCards() do
					local w, h = Layout.tooltipBox(s.compact, card.title, card.body, card.time)
					local r = Layout.tooltipRect(s, slotRect, w, h)
					expect(`{vp.name} slot{i} card{k}: {Layout.fitsInViewport(r, s.width, s.height, Layout.MARGIN)}`).toBe(
						`{vp.name} slot{i} card{k}: true`
					)
					expect(Layout.overlaps(r, slotRect)).toBe(false)
				end
			end
		end
		-- the mounted card sits where Layout puts it
		UiHarness.lastInputType = Enum.UserInputType.Touch
		local _, gui, screen = running(390, 844)
		UiHarness.fire(slot(gui, "Event"), "Activated")
		local card = HudClusters.tooltip(HudClusters.event(EVENT, 1000, true) :: HudClusters.Slot)
		local w, h = Layout.tooltipBox(screen.compact, card.title, card.body, card.time)
		local want = Layout.tooltipRect(screen, Layout.statusSlot(screen.status, 2, 3), w, h)
		expect(tip(gui).Position.X.Offset).toBe(math.round(want.x))
		expect(tip(gui).Position.Y.Offset).toBe(math.round(want.y))
		expect(tip(gui).Size.X.Offset).toBe(math.round(w))
		UiHarness.lastInputType = Enum.UserInputType.MouseMovement
		setAttributes()
	end)
end)

-- B4 / B5: the bigger clusters and the tile nav as built.
describe("H1 HUD: bigger clusters and the nav tile grid (B4, B5)", function()
	it("the mounted money plate and status slots use the bigger Layout sizes", function()
		setAttributes({ RainActive = true, RainEndsAt = 1097 })
		local hud, gui, screen = mount(1920, 1080)
		hud.update(state({ friends = { count = 1, bonus = 0.1 } }))
		local cash = UiHarness.find(UiHarness.find(gui, "Money"), "Cash")
		expect(cash.Size.X.Offset).toBe(Layout.MONEY.w)
		expect(cash.Size.Y.Offset).toBe(Layout.MONEY.plate)
		expect(UiHarness.find(cash, "Value").TextSize).toBe(Layout.MONEY.amountSize)
		local icon = UiHarness.find(cash, "Icon")
		expect(icon.Size.X.Offset).toBe(Layout.MONEY.icon)
		local rain = UiHarness.find(UiHarness.find(gui, "Status"), "Rain")
		expect(rain.Size.X.Offset).toBe(Layout.STATUS.slot)
		expect(rain.Size.Y.Offset).toBe(screen.status.rect.h)
		expect(UiHarness.find(UiHarness.find(rain, "Icon"), "Tile").Parent.Size.X.Offset).toBe(Layout.STATUS.icon)
		expect(UiHarness.find(rain, "Timer").TextSize).toBe(Layout.STATUS.labelSize)
		setAttributes()
	end)
	it("on a phone the plate and slots use the compact sizes, still bigger than the H1 ones", function()
		setAttributes({ RainActive = true, RainEndsAt = 1097 })
		local hud, gui = mount(844, 390)
		hud.update(state())
		local cash = UiHarness.find(UiHarness.find(gui, "Money"), "Cash")
		expect(cash.Size.Y.Offset).toBe(Layout.MONEY.cplate)
		expect(UiHarness.find(cash, "Value").TextSize).toBe(Layout.MONEY.camountSize)
		expect(Layout.MONEY.cplate > 40 and Layout.MONEY.camountSize > 22).toBe(true) -- H1 phone: 40 px, size 22
		setAttributes()
	end)
	it("every nav tile's item has an icon", function()
		for _, entry in Nav.ENTRIES do
			expect(UiHarness.ui("ItemIcons").build(Config).byId[entry.item] ~= nil).toBe(true)
		end
	end)
end)
