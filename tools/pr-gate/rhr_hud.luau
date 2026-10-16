--!strict
-- Writes one ScreenGui model per gate viewport and nav state for rhr, plus
-- manifest.json naming every button to assert on. Run from
-- games/steal-a-slime:  lune run ../../tools/pr-gate/rhr_hud.luau <outDir>
--
-- SlimeUI is built by code at runtime (src/ui/init.client.luau) and has no
-- stories, so rhr can't draw it from the place. This draws the same boxes the
-- way init.client applies them: ScreenGui with IgnoreGuiInset = false (so the
-- gui is the viewport minus rhr's 58 px top bar), a root UIScale of
-- Layout.uiScale, every rect from Layout.screen() as an offset Position /
-- Size, HUD items inside the bar and nav buttons inside the nav. rhr
-- 1.0.0rc1 applies a UIScale only to GuiObjects, not to a ScreenGui, so the
-- UIScale sits on a transparent "Root" frame of design size (scaled back to
-- the gui size): the same rects on screen. Overlays
-- that take clicks (menu panel, carry card, tutorial cards) are Active
-- frames at their Layout.ZINDEX; banners and toasts are plain labels, as in
-- the game.
local fs = require("@lune/fs")
local process = require("@lune/process")
local roblox = require("@lune/roblox") :: any
local serde = require("@lune/serde")

local Layout = require("../../games/steal-a-slime/src/ui/Layout")
local LayoutAssert = require("../../games/steal-a-slime/tests/ui/LayoutAssert")
local Nav = require("../../games/steal-a-slime/src/ui/Nav")

local Instance, UDim2, Color3, Enum = roblox.Instance, roblox.UDim2, roblox.Color3, roblox.Enum

local TOPBAR = 58 -- rhr's default top bar (= Layout.TOPBAR_INSET in the guides)
local outDir = process.args[1] or "rhr-out"
fs.writeDir(outDir)

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

local function frame(name: string, r: Layout.Rect, parent: any, z: number, active: boolean, origin: Layout.Rect?): any
	local f = make("Frame", {
		Name = name,
		Active = active,
		ZIndex = z,
		BorderSizePixel = 0,
		BackgroundColor3 = Color3.fromRGB(30, 34, 48),
	}, parent)
	place(f, r, origin)
	return f
end

local function button(name: string, r: Layout.Rect, parent: any, origin: Layout.Rect): any
	local b = make("TextButton", {
		Name = name,
		Text = name,
		TextSize = 14,
		AutoButtonColor = true,
		BorderSizePixel = 0,
		BackgroundColor3 = Color3.fromRGB(90, 200, 120),
	}, parent)
	place(b, r, origin)
	return b
end

local manifest = { topbar = TOPBAR, cases = {} }
local Z = Layout.ZINDEX

for _, vp in LayoutAssert.GATE_VIEWPORTS do
	local gw, gh = vp.w, vp.h - TOPBAR
	for _, collapsed in { true, false } do
		local s = Layout.screen(gw, gh, { navCollapsed = collapsed })
		local scale = Layout.uiScale(gw, gh)
		local case = `{vp.name}-{if collapsed then "collapsed" else "expanded"}`
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
		local function want(path: string, r: Layout.Rect, designW: number, designH: number)
			table.insert(buttons, { path = `SlimeUI/Root/{path}`, design = { designW, designH }, rect = r })
		end

		-- Menu panel first (Base, drawn under the nav / HUD siblings that follow).
		frame("MenuPanel", s.panel, root, Z.Base, true)

		local hud = frame("Hud", s.hud.rect, root, Z.Base, false)
		for name, r in s.hud.items do
			local item = (Layout.HUD_ITEMS :: any)[name]
			local dw = if s.compact then item.cw else item.w
			if item.button then
				button(name, r, hud, s.hud.rect)
				want(`Hud/{name}`, r, dw, item.h)
			else
				frame(name, r, hud, Z.Base, false, s.hud.rect)
			end
		end

		local nav = frame("Nav", s.nav, root, Z.Base, false)
		local cell = (if s.navCollapsed then Layout.NAV.collapsedWidth else Layout.NAV.expandedWidth)
			- Layout.NAV.padding * 2
		for i, r in s.navButtons do
			local name = if i == 1 then "NavToggle" else Nav.ENTRIES[i - 1].key
			button(name, r, nav, s.nav)
			want(`Nav/{name}`, r, cell, Layout.NAV.button)
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
		local toasts =
			make("TextLabel", { Name = "Toasts", Text = "", BackgroundTransparency = 1, ZIndex = Z.Banners }, root)
		place(toasts, s.toasts)
		frame("Tutorial", s.tutorial, root, Z.Tutorial, true)
		frame("TutorialCarrying", s.tutorialCarrying, root, Z.Tutorial, true)
		local carry = frame("Carry", s.carry, root, Z.Carry, true)
		button("Slap", s.slap, carry, s.carry)

		local file = `{outDir}/{case}.rbxmx`
		fs.writeFile(file, roblox.serializeModel({ gui }, true))
		table.insert(manifest.cases, {
			name = case,
			file = file,
			viewport = { vp.w, vp.h },
			scale = scale,
			buttons = buttons,
		})
	end
end

fs.writeFile(`{outDir}/manifest.json`, serde.encode("json", manifest, true))
print(`wrote {#manifest.cases} cases to {outDir}`)
