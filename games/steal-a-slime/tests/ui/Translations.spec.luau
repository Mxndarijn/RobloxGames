--!strict
-- Translation gate: the menus built in the long-text pseudo-language (UiHarness.setLocale "pseudo",
-- Localize.pseudo: accented letters, about 40% longer). Every string must come from the Strings catalog (no
-- plain English left), and a label with a fixed pixel box must still fit the longer text (wrapped labels in
-- their height, one-line labels in their width). The real-engine version of the fit check (TextFits at the six
-- gate viewports) runs in Studio: docs/translations.md.
local Config = require("../../src/shared/Config")
local Constants = require("../../src/shared/Constants")
local Fixtures = require("../Fixtures")
local Genome = require("../../src/shared/Genome")
local LayoutAssert = require("./LayoutAssert")
local LocaleCheck = require("./LocaleCheck")
local PlayerSettings = require("../../src/shared/PlayerSettings")
local PlotSkins = require("../../src/shared/PlotSkins")
local Remotes = require("../../src/shared/Remotes")
local ServerFixtures = require("../ServerFixtures")
local Snapshot = require("../../src/server/Snapshot")
local TestRunner = require("../TestRunner")
local UiHarness = require("./UiHarness")

local describe, it, expect = TestRunner.describe, TestRunner.it, TestRunner.expect

local T0 = ServerFixtures.T0

-- Settings reads and writes through a controller; a plain table is enough here.
local function settings(): any
	local values = PlayerSettings.defaults()
	return {
		values = values,
		get = function(id: string)
			return values[id]
		end,
		set = function(id: string, v: any)
			values[id] = v
		end,
		reset = function() end,
	}
end

local function ctx(): any
	local function record() end
	return {
		PlayerSettings = PlayerSettings,
		settings = settings(),
		userId = 42,
		placeVersion = 19,
		Config = Config,
		Constants = Constants,
		Genome = Genome,
		TripleMerge = require("../../src/shared/TripleMerge"),
		vat3Forced = function()
			return false
		end,
		actions = Remotes.ACTIONS,
		itemIcons = UiHarness.ui("ItemIcons").build(Config),
		send = record,
		request = record,
		ask = record,
		serverNow = function()
			return T0 + 1
		end,
		playerName = function()
			return "Tester"
		end,
		togglePanel = function() end,
		toast = function() end,
	}
end

local function realState(): any
	local world = ServerFixtures.world()
	local session = ServerFixtures.join(world, 1, {
		Fixtures.slime("a", 1),
		Fixtures.slime("b", 2),
		Fixtures.slime("c", 3),
	}, 1240)
	local state = Snapshot.build(world, session, T0 + 1) :: any
	state.welcomeBack = { away = 19800, cash = 12400, grown = 3 }
	state.plotSkins = state.plotSkins or PlotSkins.view(session.data)
	return state
end

local function visible(node: any, root: any): boolean
	local p = node
	while p and p ~= root do
		if p.Visible == false or p.Name == "Art" then
			return false
		end
		p = p.Parent
	end
	return true
end

-- Long-text overflows the gate tolerates for now: fixing them changes a layout, which needs Merijn's pick
-- (docs/translations.md, "Layout decisions"). Matched against the start of a finding.
local KNOWN: { string } = {}

local function known(finding: string): boolean
	for _, prefix in KNOWN do
		if string.sub(finding, 1, #prefix) == prefix then
			return true
		end
	end
	return false
end

-- Visible labels with a fixed pixel box whose pseudo text does not fit it (KNOWN ones left out).
local function overflow(root: any): { string }
	local out = {}
	for _, node in UiHarness.descendants(root) do
		local class = node.ClassName
		local isText = class == "TextLabel" or class == "TextButton"
		-- Only translated text: icons and numbers have no pseudo brackets.
		if isText and string.find(node.Text, "[", 1, true) ~= nil and visible(node, root) then
			local size = node.Size
			-- Widgets.fitText labels shrink to fit, down to their MinTextSize: measure them there.
			local fit = node:FindFirstChild("FitText")
			local textSize = if node.TextScaled and fit then fit.MinTextSize else node.TextSize
			local fixed = size.X.Scale == 0
				and size.Y.Scale == 0
				and size.X.Offset > 0
				and node.AutomaticSize.Name == "None"
				and (not node.TextScaled or fit ~= nil)
				and not node.RichText
			if fixed then
				local bold = string.find(node.FontFace.Family, "Fredoka", 1, true) ~= nil
				local why = LayoutAssert.textFits({
					name = node.Name,
					text = node.Text,
					size = textSize,
					w = size.X.Offset,
					h = size.Y.Offset,
					wrapped = node.TextWrapped,
					bold = bold,
				} :: any)
				local finding = `{LocaleCheck.path(node, root)} {why}`
				if why and not known(finding) then
					table.insert(out, finding)
				end
			end
		end
	end
	table.sort(out)
	return out
end

local MENUS = { "Codes", "Dex", "Goals", "Guide", "Merge", "Rebirth", "Welcome", "Settings", "Skins", "Leaderboard" }

local function build(key: string): any
	local panel = UiHarness.ui(`Panels/{key}`).new(UiHarness.root(), ctx())
	if panel.update then
		panel.update(realState())
	end
	if panel.setOpen then
		panel.setOpen(true)
	end
	panel.frame.Visible = true
	return panel
end

-- The checks run after the describe bodies, so each one sets the language it needs and puts English back.
local function inPseudo(fn: () -> ()): () -> ()
	return function()
		UiHarness.setLocale("pseudo")
		local ok, err = pcall(fn)
		UiHarness.setLocale("en-us")
		if not ok then
			error(err, 0)
		end
	end
end

describe("Translations: menus in the pseudo-language", function()
	for _, key in MENUS do
		it(
			`{key}: every string comes from the catalog`,
			inPseudo(function()
				local panel = build(key)
				expect(table.concat(LocaleCheck.untranslated(panel.frame), "\n")).toBe("")
			end)
		)
		it(
			`{key}: fixed-size labels fit the longer text`,
			inPseudo(function()
				local panel = build(key)
				expect(table.concat(overflow(panel.frame), "\n")).toBe("")
			end)
		)
	end
	for _, shopId in { "ItemShop", "UpgradeShop" } do
		it(
			`{shopId}: every string comes from the catalog, and fixed-size labels fit`,
			inPseudo(function()
				local panel = UiHarness.ui("Panels/WorldShop").new(UiHarness.root(), ctx())
				panel.setShop(shopId)
				panel.update(realState())
				panel.setOpen(true)
				panel.frame.Visible = true
				expect(table.concat(LocaleCheck.untranslated(panel.frame), "\n")).toBe("")
				expect(table.concat(overflow(panel.frame), "\n")).toBe("")
			end)
		)
	end
	it("English stays English", function()
		local Text = UiHarness.ui("Text")
		expect(Text.t("common.slime", { rarity = "Rare", name = "Bo" })).toBe("Rare Bo")
	end)
end)

-- Labels sized by scale (list rows, day tiles): the width and height they get from their parents, resolved up to
-- the menu card at its design size. A scroll list's scroll bar and a UIPadding come off the parent's width.
local function resolvedSize(node: any, stop: any): (number?, number?)
	local size = node.Size
	if size.X.Scale == 0 and size.Y.Scale == 0 then
		return size.X.Offset, size.Y.Offset
	end
	local parent = node.Parent
	if node == stop or parent == nil then
		return nil, nil
	end
	local pw, ph = resolvedSize(parent, stop)
	if pw == nil or ph == nil then
		return nil, nil
	end
	if parent.ClassName == "ScrollingFrame" then
		pw -= parent.ScrollBarThickness
	end
	local pad = parent:FindFirstChildOfClass("UIPadding")
	if pad then
		pw -= pad.PaddingLeft.Offset + pad.PaddingRight.Offset
		ph -= pad.PaddingTop.Offset + pad.PaddingBottom.Offset
	end
	return pw * size.X.Scale + size.X.Offset, ph * size.Y.Scale + size.Y.Offset
end

-- A node's box inside its parent (x, y, w, h), or nil when its parent's size does not resolve.
local function boxIn(node: any, stop: any): { number }?
	local w, h = resolvedSize(node, stop)
	local pw, ph = resolvedSize(node.Parent, stop)
	if w == nil or h == nil or pw == nil or ph == nil then
		return nil
	end
	local pos, anchor = node.Position, node.AnchorPoint
	return {
		pw * pos.X.Scale + pos.X.Offset - anchor.X * w,
		ph * pos.Y.Scale + pos.Y.Offset - anchor.Y * h,
		w,
		h,
	}
end

-- Scale-width labels (the ones `overflow` skips) whose pseudo text does not fit the width their parents give them.
local function scaledOverflow(root: any): { string }
	local out = {}
	for _, node in UiHarness.descendants(root) do
		local class = node.ClassName
		local isText = class == "TextLabel" or class == "TextButton"
		if isText and string.find(node.Text, "[", 1, true) ~= nil and visible(node, root) then
			local size = node.Size
			local fit = node:FindFirstChildOfClass("UITextSizeConstraint")
			local scaledW = size.X.Scale ~= 0
				and size.Y.Scale == 0
				and size.Y.Offset > 0
				and node.AutomaticSize.Name == "None"
				and (not node.TextScaled or fit ~= nil)
				and not node.RichText
			local w = if scaledW then resolvedSize(node, root) else nil
			if w then
				local why = LayoutAssert.textFits({
					name = node.Name,
					text = node.Text,
					size = if node.TextScaled and fit then fit.MinTextSize else node.TextSize,
					w = w,
					h = size.Y.Offset,
					wrapped = node.TextWrapped,
					bold = string.find(node.FontFace.Family, "Fredoka", 1, true) ~= nil,
				} :: any)
				if why then
					table.insert(out, `{LocaleCheck.path(node, root)} {why}`)
				end
			end
		end
	end
	table.sort(out)
	return out
end

-- The long-text labels (two lines) and what sits under them: each one stays inside its row or tile, and no
-- visible sibling below its top starts before its bottom where the two share columns.
local STACKED = table.freeze({
	Title = true,
	GoalTitle = true,
	QuestTitle = true,
	DailyTitle = true,
	Detail = true,
	DayLabel = true,
	DayAmount = true,
})
local function stackProblems(root: any): { string }
	local out = {}
	for _, node in UiHarness.descendants(root) do
		local box = if STACKED[node.Name]
				and node:IsA("GuiObject")
				and visible(node, root)
			then boxIn(node, root)
			else nil
		local _, parentH = if box then resolvedSize(node.Parent, root) else nil, nil
		if box and parentH then
			local x, y, w, h = box[1], box[2], box[3], box[4]
			local where = LocaleCheck.path(node, root)
			if y < 0 or y + h > parentH + 0.5 then
				table.insert(out, string.format("%s spans y %.1f..%.1f in a %.1f px box", where, y, y + h, parentH))
			end
			for _, other in node.Parent:GetChildren() do
				local o = if other ~= node
						and other:IsA("GuiObject")
						and other.Visible
						and other.Name ~= "Claimed"
					then boxIn(other, root)
					else nil
				if o and o[2] >= y and o[2] < y + h - 0.5 and o[1] < x + w and x < o[1] + o[3] then
					table.insert(
						out,
						string.format("%s (bottom %.1f) overlaps %s at y %.1f", where, y + h, other.Name, o[2])
					)
				end
			end
		end
	end
	table.sort(out)
	return out
end

-- Builds `key` at its card size (the layout sets it in the game) and checks the long-text spots in it.
local function longTextProblems(panel: any, key: string): string
	local Layout = UiHarness.ui("Layout")
	panel.frame.Size = (require("@lune/roblox") :: any).UDim2.fromOffset(Layout.MENU_WIDTH, Layout.menuHeight(key))
	local found = scaledOverflow(panel.frame)
	for _, p in stackProblems(panel.frame) do
		table.insert(found, p)
	end
	return table.concat(found, "\n")
end

describe("Translations: long-text rows and tiles in the pseudo-language", function()
	for _, tabKey in { "base", "building", "cloud", "pet" } do
		it(
			`Skins {tabKey}: row titles get two lines and the row grows under them`,
			inPseudo(function()
				local panel = build("Skins")
				panel.setTab(tabKey)
				expect(longTextProblems(panel, "Skins")).toBe("")
			end)
		)
	end
	it(
		"Goals: titles and the detail line get two lines and the rows grow",
		inPseudo(function()
			local panel = build("Goals")
			expect(longTextProblems(panel, "Goals")).toBe("")
		end)
	)
	it(
		"Welcome: the day tiles' label and amount get two lines and the card follows",
		inPseudo(function()
			local panel = build("Welcome")
			expect(longTextProblems(panel, "Welcome")).toBe("")
			local content = UiHarness.find(panel.frame, "Content")
			local daily = UiHarness.find(panel.frame, "DailyRow")
			expect(content.CanvasSize.Y.Offset >= daily.Position.Y.Offset + daily.Size.Y.Offset).toBe(true)
		end)
	)
	it("English keeps one-line rows and tiles", function()
		local panel = build("Welcome")
		local label = UiHarness.find(panel.frame, "DayLabel")
		expect(label.TextWrapped).toBe(false)
		expect(label:FindFirstChild("FitText")).toBe(nil)
	end)
end)
