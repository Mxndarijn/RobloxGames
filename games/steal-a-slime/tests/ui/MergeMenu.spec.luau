--!strict
-- The merge menu (Panels/Merge, CONTRACT.md §21.1) built through UiHarness and fed State: slots, the result
-- preview, reasons, Pick for me, kept slimes, the auto-merge confirm card, the reveal after a merge, the pair
-- vat with FEATURES.MergeVat3 off, the slime previews in rows and slots, and the layout at phone, landscape and
-- desktop sizes.
local Config = require("../../src/shared/Config")
local Constants = require("../../src/shared/Constants")
local Fixtures = require("../Fixtures")
local Genome = require("../../src/shared/Genome")
local Layout = require("../../src/ui/Layout")
local Remotes = require("../../src/shared/Remotes")
local TestRunner = require("../TestRunner")
local UiHarness = require("./UiHarness")

local describe, it, expect = TestRunner.describe, TestRunner.it, TestRunner.expect
local roblox = require("@lune/roblox") :: any
local Enum, Vector3 = roblox.Enum, roblox.Vector3

local function view(id: string, tier: number, income: number, extra: { [string]: any }?): any
	local s = Fixtures.slime(id, tier, extra)
	return { slime = s, income = income, sellPrice = 1, stolenBy = if extra then extra.stolenBy else nil }
end

local function build(options: { triple: boolean?, buildSlime: ((any) -> any)? }?): (any, { { any } }, any)
	local sent: { { any } } = {}
	local triple = not (options and options.triple == false)
	local config = setmetatable({ FEATURES = setmetatable({ MergeVat3 = triple }, { __index = Config.FEATURES }) }, {
		__index = Config,
	})
	local ctx = {
		Config = config,
		Constants = Constants,
		Genome = Genome,
		actions = Remotes.ACTIONS,
		send = function(...)
			table.insert(sent, { ... })
		end,
		serverNow = function()
			return 1000
		end,
		buildSlime = if options then options.buildSlime else nil,
	}
	local root = UiHarness.root()
	local panel = UiHarness.ui("Panels/Merge").new(root, ctx)
	return panel, sent, root
end

local function state(slimes: { any }, favoriteId: string?): any
	return { slimes = slimes, favoriteId = favoriteId }
end

local function find(panel: any, name: string): any
	return UiHarness.find(panel.frame, name)
end

-- `name` under a row / slot instance.
local function child(instance: any, name: string): any
	return UiHarness.find(instance, name)
end

local function tap(panel: any, name: string)
	UiHarness.fire(find(panel, name), "Activated")
end

-- Holds a Widgets.holdButton long enough to confirm.
local function hold(button: any)
	UiHarness.virtualTime(true)
	UiHarness.fire(button, "InputBegan", { UserInputType = Enum.UserInputType.MouseButton1 })
	UiHarness.advance(Config.HOLD_CONFIRM_SECONDS + 0.1)
	UiHarness.renderStep()
	UiHarness.advance(1)
	UiHarness.virtualTime(false)
end

local SLIMES = {
	view("c1", 1, 5),
	view("c2", 1, 1),
	view("c3", 1, 3),
	view("c4", 1, 2),
	view("u1", 2, 9),
	view("s1", 1, 0, { stolenBy = 42 }),
	view("k1", 1, 0, { keep = true }),
}

describe("Merge menu: picking", function()
	it("starts empty with the merge off and a reason", function()
		local panel = build()
		panel.update(state(SLIMES))
		expect(find(panel, "Slot3").Visible).toBe(true)
		expect(find(panel, "Reason").Text).toBe("Pick 3 slimes of the same rarity")
		expect(find(panel, "MergeButton").AutoButtonColor).toBe(false)
		expect(child(find(panel, "Result"), "Title").Text).toBe("Result")
	end)
	it("three same-rarity picks fill the slots, preview the result and enable Merge", function()
		local panel = build()
		panel.update(state(SLIMES))
		tap(panel, "c1")
		expect(find(panel, "Reason").Text).toBe(`Pick 2 more {Config.RARITIES[1].name} slimes`)
		tap(panel, "c2")
		tap(panel, "c3")
		expect(find(panel, "MergeButton").AutoButtonColor).toBe(true)
		expect(find(panel, "Reason").Text).toBe("Hold MERGE to brew!")
		local result = find(panel, "Result")
		expect(UiHarness.find(result, "Title").Text).toBe(`Random {Config.RARITIES[2].name} slime`)
		expect(string.find(UiHarness.find(result, "Odds").Text, "20%", 1, true) ~= nil).toBe(true)
		expect(child(find(panel, "c2"), "Tag").Text).toBe("IN SLOT 2")
		expect(child(find(panel, "Slot1"), "Swatch").Visible).toBe(true)
	end)
	it("tapping another rarity starts over; tapping a slot takes that slime out", function()
		local panel = build()
		panel.update(state(SLIMES))
		tap(panel, "c1")
		tap(panel, "c2")
		tap(panel, "u1")
		expect(child(find(panel, "Slot1"), "Swatch").Visible).toBe(true)
		expect(child(find(panel, "Slot2"), "Swatch").Visible).toBe(false)
		tap(panel, "Slot1")
		expect(child(find(panel, "Slot1"), "Swatch").Visible).toBe(false)
	end)
	it("a slime being stolen or kept can't go in, and says why", function()
		local panel = build()
		panel.update(state(SLIMES))
		tap(panel, "s1")
		expect(find(panel, "Reason").Text).toBe("Blorp is being stolen")
		expect(child(find(panel, "s1"), "Tag").Text).toBe("🏃 being stolen")
		tap(panel, "k1")
		expect(find(panel, "Reason").Text).toBe("Blorp is kept: tap 🔒 to free it")
		expect(child(find(panel, "Slot1"), "Swatch").Visible).toBe(false)
	end)
	it("the keep toggle asks the server; the row shows the kept state from State", function()
		local panel, sent = build()
		panel.update(state(SLIMES))
		UiHarness.fire(child(find(panel, "k1"), "Keep"), "Activated")
		UiHarness.fire(child(find(panel, "c1"), "Keep"), "Activated")
		expect(sent).toEqual({ { "KeepSlime", "k1", false }, { "KeepSlime", "c1", true } })
		expect(child(find(panel, "k1"), "Keep").Text).toBe("🔒")
		expect(child(find(panel, "c1"), "Keep").Text).toBe("🔓")
	end)
	it("a row's Add square picks it (gold tick), and is a sunken well for a kept or stolen slime", function()
		local Theme = UiHarness.ui("Widgets").Theme
		local panel = build()
		panel.update(state(SLIMES))
		local add = child(find(panel, "c1"), "Add")
		expect(add.Text).toBe("+")
		UiHarness.fire(add, "Activated")
		expect(child(find(panel, "c1"), "Tag").Text).toBe("IN SLOT 1")
		expect(add.Text).toBe("✅")
		expect(add.BackgroundColor3).toBe(Theme.Gold)
		local kept = child(find(panel, "k1"), "Add")
		expect(kept.Text).toBe("🔒")
		expect(kept.AutoButtonColor).toBe(false)
		expect(kept.BackgroundColor3).toBe(Theme.Ink)
		UiHarness.fire(kept, "Activated")
		expect(child(find(panel, "k1"), "Tag").Text).toBe("kept")
		expect(child(find(panel, "s1"), "Add").Text).toBe("🏃")
	end)
	it("Pick for me takes the cheapest group, never the favourite", function()
		local panel = build()
		panel.update(state(SLIMES, "c2"))
		tap(panel, "PickButton")
		expect(child(find(panel, "c4"), "Tag").Text).toBe("IN SLOT 1")
		expect(child(find(panel, "c3"), "Tag").Text).toBe("IN SLOT 2")
		expect(child(find(panel, "c1"), "Tag").Text).toBe("IN SLOT 3")
		expect(child(find(panel, "c2"), "Tag").Text).toBe("")
	end)
	it("groups the list by rarity with a header per rarity, and the chips filter it", function()
		local panel = build()
		panel.update(state(SLIMES))
		local header = find(panel, "~header1")
		expect(header ~= nil).toBe(true)
		expect(string.find(header.Text, "1 merge ready", 1, true) ~= nil).toBe(true)
		expect(child(header, "Count").Text).toBe("6 slimes")
		tap(panel, "Chip2")
		expect(find(panel, "c1")).toBeNil()
		expect(find(panel, "u1") ~= nil).toBe(true)
		tap(panel, "Chip0")
		expect(find(panel, "c1") ~= nil).toBe(true)
	end)
end)

describe("Merge menu: recipe preview", function()
	local RECIPE = {
		view("m1", 1, 1, { species = "mochi" }),
		view("b1", 1, 1, { species = "bubbles" }),
		view("g1", 1, 1, { species = "gummy" }),
	}
	local function pickRecipe(found: { [string]: boolean }?): any
		local panel = build()
		local entries = {}
		for id in found or {} do
			table.insert(entries, { id = id, found = true })
		end
		panel.update({ slimes = RECIPE, dex = { entries = entries } })
		tap(panel, "m1")
		tap(panel, "b1")
		tap(panel, "g1")
		return find(panel, "Result")
	end
	it("an undiscovered recipe hit previews as a random merge", function()
		local result = pickRecipe(nil)
		expect(UiHarness.find(result, "Title").Text).toBe(`Random {Config.RARITIES[2].name} slime`)
		expect(string.find(UiHarness.find(result, "Odds").Text, "20%", 1, true) ~= nil).toBe(true)
	end)
	it("a discovered recipe names the hybrid and drops the jump line", function()
		local result = pickRecipe({ soda = true })
		expect(UiHarness.find(result, "Title").Text).toBe("Soda Pop")
		expect(string.find(UiHarness.find(result, "Odds").Text, "chance:", 1, true)).toBeNil()
	end)
end)

describe("Merge menu: merging", function()
	it("a held Merge sends Merge3 with the slots, then reveals the new slime from State", function()
		local panel, sent = build()
		panel.update(state(SLIMES))
		tap(panel, "c1")
		tap(panel, "c2")
		tap(panel, "c3")
		hold(find(panel, "MergeButton"))
		expect(sent[1]).toEqual({ "Merge3", "c1", "c2", "c3" })
		local after = { SLIMES[4], SLIMES[5], SLIMES[6], SLIMES[7], view("new", 2, 6) }
		after[5].slime.name = "Gloop"
		panel.update(state(after))
		expect(string.find(child(find(panel, "Result"), "Title").Text, "Gloop", 1, true) ~= nil).toBe(true)
		expect(child(find(panel, "new"), "Tag").Text).toBe("✨ NEW")
	end)
	it("auto-merge confirms on a card with rarity toggles and a summary, then sends AutoMerge", function()
		local list = table.clone(SLIMES)
		for i = 1, 3 do
			table.insert(list, view(`u{i + 1}`, 2, i))
		end
		local panel, sent = build()
		panel.update(state(list))
		local card = find(panel, "AutoCard")
		expect(card.Visible).toBe(false)
		tap(panel, "AutoButton")
		expect(card.Visible).toBe(true)
		local summary = UiHarness.find(card, "Summary")
		expect(string.find(summary.Text, "Uses 6 slimes", 1, true) ~= nil).toBe(true)
		UiHarness.fire(UiHarness.find(card, "Tier2"), "Activated") -- untick Uncommon
		expect(string.find(summary.Text, "Uses 3 slimes", 1, true) ~= nil).toBe(true)
		hold(UiHarness.find(card, "AutoConfirm"))
		expect(sent[1]).toEqual({ "AutoMerge", 1 })
		expect(card.Visible).toBe(false)
	end)
	it("auto-merge says when there is nothing to merge", function()
		local panel, sent = build()
		panel.update(state({ view("a", 1, 1), view("b", 1, 1), view("f", 1, 1) }, "f"))
		expect(find(panel, "AutoButton").AutoButtonColor).toBe(false)
		find(panel, "AutoCard").Visible = true
		panel.update(state({ view("a", 1, 1), view("b", 1, 1), view("f", 1, 1) }, "f"))
		expect(find(panel, "AutoConfirm").Text).toBe("Nothing to merge")
		hold(find(panel, "AutoConfirm"))
		expect(#sent).toBe(0)
	end)
end)

describe("Merge menu: pair vat (FEATURES.MergeVat3 off)", function()
	it("has two slots, no auto-merge, and sends Merge", function()
		local panel, sent = build({ triple = false })
		panel.update(state(SLIMES))
		expect(find(panel, "Slot3").Visible).toBe(false)
		expect(find(panel, "AutoButton").Visible).toBe(false)
		tap(panel, "c1")
		tap(panel, "c2")
		hold(find(panel, "MergeButton"))
		expect(sent[1]).toEqual({ "Merge", "c1", "c2" })
	end)
end)

describe("Merge menu: layout", function()
	local function inside(box: any, w: number, h: number): boolean
		local p, s = box.Position, box.Size
		return p.X.Offset >= 0
			and p.Y.Offset >= 0
			and p.X.Offset + s.X.Offset <= w + 0.5
			and p.Y.Offset + s.Y.Offset <= h + 0.5
	end
	for _, size in { { 390, 844 }, { 844, 390 }, { 1920, 1080 } } do
		it(`{size[1]}x{size[2]}: the vat buttons fit the body and are thumb-sized`, function()
			local panel = build()
			panel.update(state(SLIMES))
			local screen = Layout.screen(size[1], size[2])
			local r = Layout.panelFor(screen, "Merge", 600)
			panel.layout(r)
			local b = Layout.panelBody(r)
			local vat = find(panel, "Vat")
			expect(inside(vat, b.w, math.max(b.h, vat.Size.Y.Offset))).toBe(true)
			for _, name in { "PickButton", "MergeButton", "AutoButton" } do
				local btn = find(panel, name)
				expect(inside(btn, vat.Size.X.Offset, vat.Size.Y.Offset)).toBe(true)
				expect(btn.Size.Y.Offset * screen.scale >= Layout.MIN_TOUCH_DESIGN * Layout.MIN_SCALE - 0.5).toBe(true)
			end
			local list = find(panel, "List")
			expect(list.Position.X.Offset + list.Size.X.Offset <= b.w + 0.5).toBe(true)
		end)
	end
end)

describe("Merge menu: slime previews", function()
	local SlimePreview = UiHarness.ui("SlimePreview")
	local Widgets = UiHarness.ui("Widgets")
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
	-- More slimes than SlimePreview.MAX_LIVE, cheapest first: p01 tops the list, the last ones sit past the cap.
	local function many(n: number): { any }
		local out = {}
		for i = 1, n do
			table.insert(out, view(string.format("p%02d", i), 1, i))
		end
		return out
	end
	local function preview(panel: any, id: string): any
		return child(child(find(panel, "List"), id), "Preview")
	end
	local function live(panel: any): number
		local n = 0
		for _, node in UiHarness.descendants(find(panel, "List")) do
			if node.Name == "Preview" and node:GetAttribute("Look") ~= nil then
				n += 1
			end
		end
		return n
	end
	local N = SlimePreview.MAX_LIVE + 6

	it("the first rows show their built model; rows past the cap keep the colour circle", function()
		table.clear(built)
		local panel = build({ buildSlime = fakeBuild })
		panel.setOpen(true)
		panel.update(state(many(N)))
		expect(live(panel)).toBe(SlimePreview.MAX_LIVE)
		expect(#built).toBe(SlimePreview.MAX_LIVE)
		local first = preview(panel, "p01")
		expect(first.Visible).toBe(true)
		expect(UiHarness.find(first, "Slime_p01") ~= nil).toBe(true)
		expect(first.CurrentCamera ~= nil).toBe(true)
		local well = Widgets.Theme.Row:Lerp(Widgets.Theme.Ink, SlimePreview.WELL_TINT)
		expect(first.Parent.BackgroundColor3).toBe(well)
		local last = preview(panel, string.format("p%02d", N))
		expect(last.Visible).toBe(false)
		expect(last:GetAttribute("Look")).toBe(nil)
		expect(last.Parent.BackgroundColor3).toBe(Widgets.color3(Fixtures.slime("x").color))
	end)

	it("a State push with the same slimes rebuilds nothing; a new look rebuilds only that row", function()
		table.clear(built)
		local panel = build({ buildSlime = fakeBuild })
		panel.setOpen(true)
		panel.update(state(many(N)))
		local before = #built
		panel.update(state(many(N)))
		expect(#built).toBe(before)
		local changed = many(N)
		changed[3] = view("p03", 1, 3, { color = { 10, 200, 30 } })
		panel.update(state(changed))
		expect(#built).toBe(before + 1)
		expect(built[#built]).toBe("p03")
	end)

	it("a closed card mounts nothing", function()
		table.clear(built)
		local panel = build({ buildSlime = fakeBuild })
		panel.update(state(many(N)))
		expect(live(panel)).toBe(0)
		expect(#built).toBe(0)
	end)

	it("without a builder (or when it fails) rows show the blob preview", function()
		local panel = build({
			buildSlime = function()
				error("no Visuals")
			end,
		})
		panel.setOpen(true)
		panel.update(state(many(3)))
		local p = preview(panel, "p01")
		expect(p.Visible).toBe(true)
		expect(UiHarness.find(p, "Body") ~= nil).toBe(true)
		local plain = build()
		plain.setOpen(true)
		plain.update(state(many(3)))
		expect(preview(plain, "p02").Visible).toBe(true)
	end)

	it("a filled vat slot shows the slime's preview; an emptied slot drops it", function()
		table.clear(built)
		local panel = build({ buildSlime = fakeBuild })
		panel.setOpen(true)
		panel.update(state(SLIMES))
		UiHarness.fire(child(child(find(panel, "List"), "c2"), "Add"), "Activated")
		local slot = child(find(panel, "Slot1"), "Preview")
		expect(slot.Visible).toBe(true)
		expect(UiHarness.find(slot, "Slime_c2") ~= nil).toBe(true)
		tap(panel, "Slot1")
		expect(slot.Visible).toBe(false)
		expect(slot:GetAttribute("Look")).toBe(nil)
	end)
end)
