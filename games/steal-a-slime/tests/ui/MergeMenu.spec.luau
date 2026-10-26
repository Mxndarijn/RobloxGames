--!strict
-- The merge vat menu (Panels/Merge, CONTRACT.md §21) built through UiHarness and fed State: the vat's load in the
-- slots with an X each, the result preview, what the main button says in every vat state, the countdown while
-- brewing, the reveal after Collect, the slime previews and the layout at phone, landscape and desktop sizes.
local Config = require("../../src/shared/Config")
local Constants = require("../../src/shared/Constants")
local Fixtures = require("../Fixtures")
local Genome = require("../../src/shared/Genome")
local Layout = require("../../src/ui/Layout")
local MergeGate = require("../../src/shared/MergeGate")
local Remotes = require("../../src/shared/Remotes")
local TestRunner = require("../TestRunner")
local UiHarness = require("./UiHarness")

local describe, it, expect = TestRunner.describe, TestRunner.it, TestRunner.expect
local roblox = require("@lune/roblox") :: any
local Enum, Vector3 = roblox.Enum, roblox.Vector3

local NOW = 1000
local Merge = UiHarness.ui("Panels/Merge")

local function view(id: string, tier: number, extra: { [string]: any }?): any
	local s = Fixtures.slime(id, tier, extra)
	s.pad = extra and extra.pad or 1
	return { slime = s, income = 1, sellPrice = 1, stolenBy = nil }
end

local SLIMES = { view("a", 1, { pad = 1 }), view("b", 1, { pad = 2 }), view("c", 1, { pad = 3 }), view("d", 2) }

local function state(ids: { string }, vat: { [string]: any }?): any
	local v = { ids = ids, tier = if #ids > 0 then 1 else nil, seconds = Config.MERGE_BREW_SECONDS[1] }
	for k, value in vat or {} do
		v[k] = value
	end
	return { slimes = SLIMES, vat = v }
end

local function build(options: { buildSlime: ((any) -> any)? }?): (any, { { any } })
	local sent: { { any } } = {}
	local ctx = {
		Config = Config,
		Constants = Constants,
		Genome = Genome,
		actions = Remotes.ACTIONS,
		send = function(...)
			table.insert(sent, { ... })
		end,
		serverNow = function()
			return NOW
		end,
		buildSlime = if options then options.buildSlime else nil,
	}
	local panel = Merge.new(UiHarness.root(), ctx)
	panel.frame.Visible = true -- a hold only confirms while its panel is open
	return panel, sent
end

local function find(panel: any, name: string): any
	return UiHarness.find(panel.frame, name)
end

local function hold(button: any)
	UiHarness.virtualTime(true)
	UiHarness.fire(button, "InputBegan", { UserInputType = Enum.UserInputType.MouseButton1 })
	UiHarness.advance(Config.HOLD_CONFIRM_SECONDS + 0.1)
	UiHarness.renderStep()
	UiHarness.advance(1)
	UiHarness.virtualTime(false)
end

local function rarityOf(tier: number): any
	return Config.RARITIES[tier]
end

describe("Merge menu: describe", function()
	it("an empty vat says how to fill it", function()
		local v = Merge.describe(state({}), NOW, rarityOf, Genome.displayName)
		expect(v.main.kind).toBe("well")
		expect(v.main.text).toBe("Add 3 slimes of one rarity")
		expect(v.slots[1].name).toBe("Move a slime here")
		expect(v.preview).toBe(nil)
	end)

	it("a part load names what is missing and the rarity the empty spots take", function()
		local v = Merge.describe(state({ "a", "b" }), NOW, rarityOf, Genome.displayName)
		expect(v.main.text).toBe("Add 1 more Common")
		expect(v.countText).toBe("2/3 in")
		expect(v.slots[3].name).toBe("Move a Common here")
		expect(v.slots[1].canRemove).toBe(true)
		expect(v.preview.title).toBe("Random slime")
		expect(v.preview.rarity).toBe("Uncommon")
	end)

	it("a full load starts with the brew time on the button", function()
		local v = Merge.describe(state({ "a", "b", "c" }), NOW, rarityOf, Genome.displayName)
		expect(v.main.kind).toBe("start")
		local brew = Merge.brewText(Config.MERGE_BREW_SECONDS[1])
		expect(v.main.text).toBe(`Start merge · {brew}`)
		expect(v.brewText).toBe(`Brew time {brew}`)
	end)

	it("brewing locks the slots, counts down and offers the hold to cancel", function()
		local v = Merge.describe(
			state({ "a", "b", "c" }, { startedAt = NOW - 10, endsAt = NOW + 20 }),
			NOW,
			rarityOf,
			Genome.displayName
		)
		expect(v.main.kind).toBe("cancel")
		expect(v.countText).toBe("Brewing")
		expect(v.slots[1].locked).toBe(true)
		expect(v.slots[1].canRemove).toBe(false)
		expect(v.timeLeft).toBe(20)
		expect(math.abs((v.progress :: number) - 1 / 3) < 0.01).toBe(true)
	end)

	it("a finished brew is Ready with Collect", function()
		local v = Merge.describe(
			state({ "a", "b", "c" }, { startedAt = NOW - 40, endsAt = NOW - 10 }),
			NOW,
			rarityOf,
			Genome.displayName
		)
		expect(v.main.kind).toBe("collect")
		expect(v.countText).toBe("Ready")
	end)

	it("brew lengths and jump lines read like the design", function()
		expect(Merge.brewText(30)).toBe("30s")
		expect(Merge.brewText(60)).toBe("1m")
		expect(Merge.brewText(150)).toBe("2m 30s")
		expect(Merge.brewText(3900)).toBe("1h 5m")
		expect(Merge.jumpText(0.2, "Epic")).toBe("20% chance of an Epic")
		expect(Merge.jumpText(0.2, "Rare")).toBe("20% chance of a Rare")
		expect(Merge.describe(state({ "a" }), NOW, rarityOf, Genome.displayName).slots[2].name).toBe(
			"Move a Common here"
		)
		expect(Merge.withArticle("Uncommon")).toBe("an Uncommon")
	end)
end)

describe("Merge menu: the rank gate", function()
	local EPICS = { view("e1", 4, { pad = 1 }), view("e2", 4, { pad = 2 }), view("e3", 4, { pad = 3 }) }
	local RARES = { view("r1", 3, { pad = 1 }), view("r2", 3, { pad = 2 }), view("r3", 3, { pad = 3 }) }
	local RARE_AT = MergeGate.rebirthsFor(3) :: number
	local EPIC_AT = MergeGate.rebirthsFor(4) :: number
	local function gated(slimes: { any }, ids: { string }, rebirths: number): any
		local tier = slimes[1].slime.tier
		return {
			slimes = slimes,
			rebirths = rebirths,
			vat = { ids = ids, tier = tier, seconds = Config.MERGE_BREW_SECONDS[tier] },
		}
	end

	it("a full load the rank can't merge yet waits behind 'Rebirth N to unlock'", function()
		local v = Merge.describe(gated(EPICS, { "e1", "e2", "e3" }, EPIC_AT - 2), NOW, rarityOf, Genome.displayName)
		expect(v.main.kind).toBe("well")
		expect(v.main.text).toBe(`Rebirth {EPIC_AT} to unlock`)
		expect((v.gate :: any).chip).toBe(`Rebirth {EPIC_AT}`)
		expect((v.gate :: any).line).toBe(`Epic merges open at Rebirth {EPIC_AT}`)
		expect(v.reason).toBe("Rebirth 2 more times to merge Epics. Until you start, these still earn on their pads.")
	end)

	it("a part load shows the lock too, and says it can be filled now", function()
		local v = Merge.describe(gated(EPICS, { "e1" }, EPIC_AT - 1), NOW, rarityOf, Genome.displayName)
		expect(v.main.text).toBe(`Rebirth {EPIC_AT} to unlock`)
		expect(v.reason).toBe(`You can fill the vat now and start it once you reach Rebirth {EPIC_AT}.`)
		expect(v.slots[2].name).toBe("Move an Epic here")
	end)

	it("an open load starts as usual; the card shows the chip, padlock and Warn line only when locked", function()
		local open = Merge.describe(gated(EPICS, { "e1", "e2", "e3" }, EPIC_AT), NOW, rarityOf, Genome.displayName)
		expect(open.main.kind).toBe("start")
		expect(open.gate).toBe(nil)
		local panel = build()
		panel.update(gated(EPICS, { "e1", "e2", "e3" }, EPIC_AT - 1))
		expect(find(panel, "GateChip").Visible).toBe(true)
		expect(find(panel, "GateChip").Text).toBe(`🔒 Rebirth {EPIC_AT}`)
		expect(find(panel, "Odds").Text).toBe(`Epic merges open at Rebirth {EPIC_AT}`)
		expect(find(panel, "Mark").Text).toBe("🔒")
		expect(find(panel, "StartButton").Visible).toBe(false)
		expect(find(panel, "Missing").Text).toBe(`Rebirth {EPIC_AT} to unlock`)
		panel.update(gated(EPICS, { "e1", "e2", "e3" }, EPIC_AT))
		expect(find(panel, "GateChip").Visible).toBe(false)
		expect(find(panel, "StartButton").Visible).toBe(true)
	end)

	it("a jump the rank doesn't open yet says when it does", function()
		local panel = build()
		panel.update(gated(RARES, { "r1", "r2", "r3" }, RARE_AT))
		expect(find(panel, "Odds").Text).toBe(`No jump: Legendary opens at Rebirth {EPIC_AT}`)
		panel.update(gated(RARES, { "r1", "r2", "r3" }, EPIC_AT))
		expect(find(panel, "Odds").Text).toBe("20% chance of a Legendary")
	end)
end)

describe("Merge menu: the card", function()
	it("fills the slots and sends VatRemove from a slot's X", function()
		local panel, sent = build()
		panel.update(state({ "a", "b" }))
		expect(find(panel, "SlotName1").Text).toBe("Blorp")
		expect(find(panel, "Remove1").Visible).toBe(true)
		expect(find(panel, "Remove3").Visible).toBe(false)
		expect(find(panel, "Missing").Visible).toBe(true)
		expect(find(panel, "Missing").Text).toBe("Add 1 more Common")
		UiHarness.fire(find(panel, "Remove2"), "Activated")
		expect(sent[#sent][1]).toBe("VatRemove")
		expect(sent[#sent][2]).toBe("b")
	end)

	it("Start merge sends VatStart; while brewing the X turns into a padlock and the hold cancels", function()
		local panel, sent = build()
		panel.update(state({ "a", "b", "c" }))
		UiHarness.fire(find(panel, "StartButton"), "Activated")
		expect(sent[#sent][1]).toBe("VatStart")
		panel.update(state({ "a", "b", "c" }, { startedAt = NOW, endsAt = NOW + 30 }))
		expect(find(panel, "Remove1").Visible).toBe(false)
		expect(find(panel, "Lock1").Visible).toBe(true)
		expect(find(panel, "Timer").Visible).toBe(true)
		expect(find(panel, "TimeLeft").Text).toBe("0:30 left")
		hold(find(panel, "CancelButton"))
		expect(sent[#sent][1]).toBe("VatCancel")
	end)

	it("Collect sends VatCollect and the result card reveals the new slime from State", function()
		local panel, sent = build()
		panel.setOpen(true)
		panel.update(state({ "a", "b", "c" }, { startedAt = NOW - 40, endsAt = NOW - 1 }))
		UiHarness.fire(find(panel, "CollectButton"), "Activated")
		expect(sent[#sent][1]).toBe("VatCollect")
		local child = Fixtures.slime("new", 2, { name = "Pebble" })
		child.pad = 1
		panel.update({ slimes = { { slime = child, income = 3, sellPrice = 1 }, SLIMES[4] }, vat = { ids = {} } })
		expect(UiHarness.find(find(panel, "Result"), "Title").Text).toBe("Pebble")
		expect(UiHarness.find(find(panel, "Result"), "Odds").Text).toBe("On pad 1")
	end)

	it("a known recipe names the hybrid; a random one shows Random slime and the rarity", function()
		local panel = build()
		panel.update(state({ "a", "b" }))
		local result = find(panel, "Result")
		expect(UiHarness.find(result, "Title").Text).toBe("Random slime")
		expect(UiHarness.find(result, "RarityPill").Text).toBe("Uncommon")
		expect(UiHarness.find(result, "Odds").Text).toBe("20% chance of a Rare")
	end)
end)

describe("Merge menu: slime previews", function()
	local built: { string } = {}
	local function fakeBuild(genome: any): any
		local model = UiHarness.Instance.new("Model")
		model.Name = `Slime_{genome.id}`
		local body = UiHarness.Instance.new("Part")
		body.Name = "Body"
		body.Size = Vector3.new(4, 3, 4)
		body.Parent = model
		table.insert(built, genome.id)
		return model
	end

	it("an open card shows each slot's slime; a closed one mounts nothing", function()
		table.clear(built)
		local panel = build({ buildSlime = fakeBuild })
		panel.update(state({ "a", "b" }))
		expect(#built).toBe(0)
		panel.setOpen(true)
		expect(table.find(built, "a") ~= nil and table.find(built, "b") ~= nil).toBe(true)
		local preview = UiHarness.find(find(panel, "Slot1"), "Preview")
		expect(preview.Visible).toBe(true)
	end)
end)

describe("Merge menu: layout", function()
	-- A body child's box with its Y resolved against a body `h` tall (pinned buttons use Scale 1).
	local function resolved(box: any, h: number): any
		local p = box.Position
		return {
			Position = { X = { Offset = p.X.Offset }, Y = { Offset = p.Y.Scale * h + p.Y.Offset } },
			Size = box.Size,
		}
	end
	local function inside(box: any, w: number, h: number): boolean
		local p, s = box.Position, box.Size
		return p.X.Offset >= 0
			and p.Y.Offset >= 0
			and p.X.Offset + s.X.Offset <= w + 0.5
			and p.Y.Offset + s.Y.Offset <= h + 0.5
	end
	for _, size in { { 390, 844 }, { 844, 390 }, { 1920, 1080 } } do
		it(`{size[1]}x{size[2]}: the load and the main button fit the body and are thumb-sized`, function()
			local panel = build()
			panel.update(state({ "a", "b", "c" }))
			local screen = Layout.screen(size[1], size[2])
			local r = Layout.panelFor(screen, "Merge", 600)
			panel.layout(r)
			local b = Layout.panelBody(r)
			expect(inside(find(panel, "Load"), b.w, find(panel, "Content").CanvasSize.Y.Offset)).toBe(true)
			local btn = find(panel, "StartButton")
			expect(inside(resolved(btn, b.h), b.w, b.h)).toBe(true)
			expect(btn.Size.Y.Offset * screen.scale >= Layout.MIN_TOUCH_DESIGN * Layout.MIN_SCALE - 0.5).toBe(true)
		end)
	end
	for _, size in { { 800, 334 }, { 844, 332 } } do
		it(`{size[1]}x{size[2]} touch, brewing: Hold to cancel stays inside the clamped card`, function()
			local panel = build()
			panel.update(state({ "a", "b", "c" }, { startedAt = NOW, endsAt = NOW + 30 }))
			local screen = Layout.screen(size[1], size[2], { touch = true })
			local Widgets = UiHarness.ui("Widgets")
			local content = Widgets.contentHeight(find(panel, "Body"))
			local r = Layout.panelFor(screen, "Merge", content)
			panel.layout(r)
			expect(Layout.cardHeight(Widgets.contentHeight(find(panel, "Body"))) > r.h).toBe(true)
			local b = Layout.panelBody(r)
			local cancel = resolved(find(panel, "CancelButton"), b.h)
			expect(find(panel, "CancelButton").Visible).toBe(true)
			expect(inside(cancel, b.w, b.h)).toBe(true)
			local scroll = find(panel, "Content")
			local timer = find(panel, "Timer")
			expect(scroll.Size.Y.Scale * b.h + scroll.Size.Y.Offset <= cancel.Position.Y.Offset + 0.5).toBe(true)
			expect(scroll.CanvasSize.Y.Offset >= timer.Position.Y.Offset + timer.Size.Y.Offset).toBe(true)
		end)
	end
end)
