--!strict
-- Writes one ScreenGui model per gate viewport for rhr, plus manifest.json naming every button and box to
-- assert on. Run from games/steal-a-slime:  lune run ../../tools/pr-gate/rhr_hud.luau <outDir>
-- The same models draw to PNG with `rhr ui <case>.rbxmx --viewport WxH --background <sand>` (the renders
-- in /workspace/roblox/bugs-oct18/renders).
--
-- SlimeUI is built by code at runtime (src/ui/init.client.luau) and has no
-- stories, so rhr can't draw it from the place. This draws the same boxes the
-- way init.client applies them: ScreenGui with IgnoreGuiInset = false (so the
-- gui is the viewport minus rhr's 58 px top bar), a root UIScale of
-- Layout.uiScale, every rect from Layout.screen() as an offset Position /
-- Size: the nav tiles (rounded tile + label under it, B5), the money cluster and the status icons (B4), and
-- per viewport a second case with the status tooltip open (B8). rhr
-- 1.0.0rc1 applies a UIScale only to GuiObjects, not to a ScreenGui, so the
-- UIScale sits on a transparent "Root" frame of design size (scaled back to
-- the gui size): the same rects on screen. Overlays
-- that take clicks (menu panel, carry card, tutorial cards) are Active
-- frames at their Layout.ZINDEX, drawn invisible; banners are plain labels, as in the game.
-- The pictures are the ItemIcons placeholder tiles (colour + glyph), the same a player sees until the
-- uploaded image loads.
local fs = require("@lune/fs")
local process = require("@lune/process")
local roblox = require("@lune/roblox") :: any
local serde = require("@lune/serde")

local Config = require("../../games/steal-a-slime/src/shared/Config")
local HudClusters = require("../../games/steal-a-slime/src/ui/HudClusters")
local ItemIcons = require("../../games/steal-a-slime/src/ui/ItemIcons")
local Layout = require("../../games/steal-a-slime/src/ui/Layout")
local LayoutAssert = require("../../games/steal-a-slime/tests/ui/LayoutAssert")
local Nav = require("../../games/steal-a-slime/src/ui/Nav")

local Instance, UDim2, UDim, Color3, Enum, Vector2 =
	roblox.Instance, roblox.UDim2, roblox.UDim, roblox.Color3, roblox.Enum, roblox.Vector2

local TOPBAR = 58 -- rhr's default top bar (= Layout.TOPBAR_INSET in the guides)
local outDir = process.args[1] or "rhr-out"
fs.writeDir(outDir)

local registry = ItemIcons.build(Config)

local function make(class: string, props: { [string]: any }, parent: any): any
	local inst = Instance.new(class)
	for k, v in props do
		inst[k] = v
	end
	inst.Parent = parent
	return inst
end

-- UDim offsets are whole pixels (int32) in Roblox, so fractional design px
-- round, as they do when init.client sets them.
local function place(inst: any, r: Layout.Rect, origin: Layout.Rect?)
	local ox, oy = if origin then origin.x else 0, if origin then origin.y else 0
	inst.Position = UDim2.fromOffset(math.round(r.x - ox), math.round(r.y - oy))
	inst.Size = UDim2.fromOffset(math.round(r.w), math.round(r.h))
end

-- An invisible Active frame: what the game's overlays are for hit testing.
local function frame(name: string, r: Layout.Rect, parent: any, z: number, active: boolean, origin: Layout.Rect?): any
	local f = make("Frame", {
		Name = name,
		Active = active,
		ZIndex = z,
		BorderSizePixel = 0,
		BackgroundTransparency = 1,
	}, parent)
	place(f, r, origin)
	return f
end

local function rounded(inst: any, radius: number, strokeColor: Color3?, thickness: number?)
	make("UICorner", { CornerRadius = UDim.new(0, radius) }, inst)
	if strokeColor then
		make("UIStroke", { Color = strokeColor, Thickness = thickness or 2 }, inst)
	end
end

local function text(name: string, parent: any, props: { [string]: any }): any
	local base = {
		Name = name,
		BackgroundTransparency = 1,
		Font = Enum.Font.GothamBold,
		TextColor3 = Color3.fromRGB(240, 242, 255),
		TextStrokeTransparency = 0.3,
		TextStrokeColor3 = Color3.fromRGB(10, 10, 20),
	}
	for k, v in props do
		base[k] = v
	end
	return make("TextLabel", base, parent)
end

local function rgb(c: { number }): any
	return Color3.fromRGB(c[1], c[2], c[3])
end

-- An ItemIcons placeholder tile (colour + glyph) at `size` px.
local function icon(parent: any, id: string, size: number, pos: any, anchor: any?)
	local spec = registry.byId[id] or registry.byId.Unknown
	local tile = make("Frame", {
		Name = "Icon",
		BackgroundColor3 = rgb(spec.color),
		BorderSizePixel = 0,
		Size = UDim2.fromOffset(size, size),
		Position = pos,
		AnchorPoint = anchor or Vector2.zero,
		ZIndex = Layout.ZINDEX.Base + 1,
	}, parent)
	rounded(tile, math.max(4, math.floor(size * 0.22)), rgb(spec.color):Lerp(Color3.new(0, 0, 0), 0.55), 2)
	text("Glyph", tile, {
		Text = spec.glyph,
		TextSize = math.floor(size * 0.52),
		Size = UDim2.fromScale(1, 1),
		ZIndex = Layout.ZINDEX.Base + 2,
	})
	return tile
end

local function chip(
	parent: any,
	name: string,
	r: Layout.Rect,
	origin: Layout.Rect,
	iconId: string,
	label: string,
	color: any,
	size: number
)
	local f = make("Frame", { Name = name, BackgroundColor3 = color, BorderSizePixel = 0 }, parent)
	place(f, r, origin)
	rounded(f, 12, Color3.fromRGB(10, 10, 20), 2)
	icon(f, iconId, r.h - 6, UDim2.fromOffset(3, 3))
	local left, width = Layout.moneyTextBox(r, false, size < 14)
	text("Value", f, {
		Text = label,
		TextSize = size,
		Size = UDim2.fromOffset(width, r.h),
		Position = UDim2.fromOffset(left, 0),
		TextTruncate = Enum.TextTruncate.None,
	})
end

local manifest = { topbar = TOPBAR, cases = {} }
local Z = Layout.ZINDEX

-- The three status slots as a running game shows them (rain, luck event, friend boost).
local NOW = 1000
local SLOTS = HudClusters.status({
	rain = { active = true, endsAt = NOW + 97 },
	modifier = { name = "Admin_luck", label = "Luck Event", luck = 3, mutation = 1, endsAt = NOW + 540, icon = "🍀" },
	modifierEnabled = true,
	friends = { count = 1, bonus = 0.1 },
	friendsEnabled = true,
}, NOW)

local function buildCase(vp: { name: string, w: number, h: number }, tooltipSlot: number?)
	local gw, gh = vp.w, vp.h - TOPBAR
	local s = Layout.screen(gw, gh)
	local scale = Layout.uiScale(gw, gh)
	local case = if tooltipSlot then `{vp.name}-tooltip` else vp.name
	local gui = make("ScreenGui", {
		Name = "SlimeUI",
		IgnoreGuiInset = false,
		ResetOnSpawn = false,
		ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
	}, nil)
	local root = make("Frame", {
		Name = "Root",
		BackgroundTransparency = 1,
		Size = UDim2.fromOffset(math.round(s.width), math.round(s.height)),
	}, gui)
	make("UIScale", { Name = "ViewportScale", Scale = scale }, root)

	local buttons = {}
	local boxes = {}
	local function want(path: string, r: Layout.Rect, designW: number, designH: number)
		table.insert(buttons, { path = `SlimeUI/Root/{path}`, design = { designW, designH }, rect = r })
	end

	-- Menu panel first (Base, drawn under the siblings that follow): invisible, but it takes clicks.
	frame("MenuPanel", s.panel, root, Z.Base, true)

	-- Nav: rounded tiles with the picture on them and the label under them (B5).
	local nav = frame("Nav", s.nav, root, Z.Base, false)
	local cellW, cellH = Layout.navCellSize(s.compact)
	local N = Layout.NAV
	local badges = { Dex = "5%" }
	for i, entry in Nav.ENTRIES do
		local r = s.navButtons[i]
		local b = make(
			"TextButton",
			{ Name = entry.key, Text = "", AutoButtonColor = false, BackgroundTransparency = 1 },
			nav
		)
		place(b, r, s.nav)
		local tileR = Layout.navTile(s.compact, r)
		local tile =
			make("Frame", { Name = "Tile", BackgroundColor3 = Color3.fromRGB(58, 36, 110), BorderSizePixel = 0 }, b)
		place(tile, tileR, r)
		rounded(tile, 16, Color3.fromRGB(10, 10, 20), 3)
		local inset = N.iconInset
		icon(tile, entry.item, tileR.w - inset * 2, UDim2.fromOffset(inset, inset))
		text("Label", b, {
			Text = entry.label,
			TextSize = if s.compact then N.clabelSize else N.labelSize,
			Size = UDim2.fromOffset(math.round(r.w), if s.compact then N.clabel else N.label),
			Position = UDim2.fromOffset(0, tileR.h + N.labelGap),
		})
		if badges[entry.key] then
			local br = Layout.navBadge(r, badges[entry.key])
			local badge = text("Badge", b, {
				Text = badges[entry.key],
				TextSize = Layout.NAV_BADGE.textSize,
				BackgroundTransparency = 0,
				BackgroundColor3 = Color3.fromRGB(80, 150, 240),
				ZIndex = 3,
				TextStrokeTransparency = 1,
			})
			place(badge, br, r)
			rounded(badge, 8)
		end
		want(`Nav/{entry.key}`, r, cellW, cellH)
	end

	-- Money cluster (bottom left): the coin plate with the big amount, the income / rebirth chips under it.
	local m = s.money
	-- Active here so a nav tile under the cluster counts as covered in the gate (a layout bug either way).
	local moneyRoot = frame("Money", m.rect, root, Z.Base, true)
	local cash =
		make("Frame", { Name = "Cash", BackgroundColor3 = Color3.fromRGB(58, 36, 110), BorderSizePixel = 0 }, moneyRoot)
	place(cash, m.cash, m.rect)
	rounded(cash, 16, Color3.fromRGB(10, 10, 20), 3)
	local coin = if s.compact then Layout.MONEY.cicon else Layout.MONEY.icon
	icon(cash, "Cash", coin, UDim2.new(0, 6, 0.5, 0), Vector2.new(0, 0.5))
	local cashLeft, cashWidth = Layout.moneyTextBox(m.cash, true, s.compact)
	text("Value", cash, {
		Text = "$2.37B",
		TextSize = if s.compact then Layout.MONEY.camountSize else Layout.MONEY.amountSize,
		Size = UDim2.fromOffset(cashWidth, m.cash.h),
		Position = UDim2.fromOffset(cashLeft, 0),
	})
	local chipSize = if s.compact then Layout.MONEY.cchipSize else Layout.MONEY.chipSize
	chip(moneyRoot, "Income", m.income, m.rect, "Income", "+$5.93M/s", Color3.fromRGB(40, 120, 70), chipSize)
	chip(moneyRoot, "Rebirths", m.rebirths, m.rect, "Rebirth", "8 x5", Color3.fromRGB(70, 50, 140), chipSize)
	table.insert(boxes, { path = "Money", rect = m.rect })

	-- Status cluster (bottom right): an icon with its timer under it per running thing.
	local statusRoot = frame("Status", s.status.rect, root, Z.Base, true)
	local S = Layout.STATUS
	local iconSize = if s.compact then S.cicon else S.icon
	local slotW, slotH = Layout.statusSlotWidth(s.compact), Layout.statusHeight(s.compact)
	local slotRects = {}
	for i, slot in SLOTS do
		local r = Layout.statusSlot(s.status, i, #SLOTS)
		slotRects[i] = r
		local b = make(
			"TextButton",
			{ Name = slot.id, Text = "", AutoButtonColor = false, BackgroundTransparency = 1 },
			statusRoot
		)
		place(b, r, s.status.rect)
		icon(b, slot.icon, iconSize, UDim2.new(0.5, 0, 0, 0), Vector2.new(0.5, 0))
		text("Timer", b, {
			Text = slot.text,
			TextSize = if s.compact then S.clabelSize else S.labelSize,
			Size = UDim2.new(1, 0, 0, if s.compact then S.clabel else S.label),
			Position = UDim2.fromOffset(0, iconSize + S.labelGap),
			TextStrokeTransparency = 0.2,
		})
		want(`Status/{slot.id}`, r, slotW, slotH)
	end

	-- B8: the open tooltip over `tooltipSlot` (the luck event), where Layout puts it.
	if tooltipSlot then
		local slot = SLOTS[tooltipSlot]
		local card = HudClusters.tooltip(slot)
		local w, h, lines = Layout.tooltipBox(s.compact, card.title, card.body, card.time)
		local r = Layout.tooltipRect(s, slotRects[tooltipSlot], w, h)
		local tip = make(
			"Frame",
			{ Name = "Tooltip", BackgroundColor3 = Color3.fromRGB(28, 30, 44), BorderSizePixel = 0, ZIndex = Z.Banners },
			root
		)
		place(tip, r)
		rounded(tip, 10, Color3.fromRGB(255, 205, 70), 2)
		local T = Layout.TOOLTIP
		local y = T.pad
		for _, entry in
			{
				{ "Title", card.title, lines.titleH, T.titleSize, Color3.fromRGB(255, 205, 70), Enum.Font.GothamBold },
				{
					"Body",
					card.body,
					lines.bodyH,
					if s.compact then T.cbodySize else T.bodySize,
					Color3.fromRGB(240, 242, 255),
					Enum.Font.Gotham,
				},
				{ "Time", card.time, lines.timeH, T.timeSize, Color3.fromRGB(110, 230, 140), Enum.Font.GothamBold },
			}
		do
			text(entry[1] :: string, tip, {
				Text = entry[2],
				TextSize = entry[4],
				TextColor3 = entry[5],
				Font = entry[6],
				TextWrapped = true,
				TextStrokeTransparency = 1,
				TextXAlignment = Enum.TextXAlignment.Left,
				TextYAlignment = Enum.TextYAlignment.Top,
				Size = UDim2.fromOffset(math.round(r.w) - T.pad * 2, entry[3]),
				Position = UDim2.fromOffset(T.pad, y),
				ZIndex = Z.Banners,
			})
			y += (entry[3] :: number) + T.line
		end
		table.insert(boxes, { path = "Tooltip", rect = r })
	end

	-- Overlays above the base layer.
	local b = s.banners
	make("TextLabel", {
		Name = "Banners",
		Text = "",
		BackgroundTransparency = 1,
		ZIndex = Z.Banners,
		Position = UDim2.fromOffset(math.round(b.x), math.round(b.y)),
		Size = UDim2.fromOffset(math.round(b.w), 160), -- four stacked banners
	}, root)
	frame("Tutorial", s.tutorial, root, Z.Tutorial, true)
	frame("TutorialCarrying", s.tutorialCarrying, root, Z.Tutorial, true)
	frame("Carry", s.carry, root, Z.Carry, true)

	local file = `{outDir}/{case}.rbxmx`
	fs.writeFile(file, roblox.serializeModel({ gui }, true))
	table.insert(manifest.cases, {
		name = case,
		file = file,
		viewport = { vp.w, vp.h },
		scale = scale,
		buttons = buttons,
		boxes = boxes,
	})
end

for _, vp in LayoutAssert.GATE_VIEWPORTS do
	buildCase(vp, nil)
	buildCase(vp, 2) -- the luck event's tooltip open
end
fs.writeFile(`{outDir}/manifest.json`, serde.encode("json", manifest, true))
print(`wrote {#manifest.cases} cases to {outDir}`)
