--!strict
-- FEATURES.PvP hotbar + chips layout at the five gate viewports plus the landscape phone (844x332, 844x390):
-- on screen, touch-sized, clear of the HUD, nav, banner stack, toast column, carry card, SLAP!, the tutorial cards and
-- Roblox's touch controls. 11 slots (3 tools + 8 fun) with the stub at a rank that owns everything.
local Config = require("../../src/shared/Config")
local ItemIcons = require("../../src/ui/ItemIcons")
local Layout = require("../../src/ui/Layout")
local LayoutAssert = require("./LayoutAssert")
local PvpClient = require("../../src/ui/PvpClient")
local PvpHudLogic = require("../../src/ui/PvpHudLogic")
local TestRunner = require("../TestRunner")
local UiHarness = require("./UiHarness")
local fs = require("@lune/fs")

local describe, it, expect = TestRunner.describe, TestRunner.it, TestRunner.expect

local PvpHud = UiHarness.ui("PvpHud")
local registry = ItemIcons.build(Config)

local function viewports(): { { name: string, w: number, h: number } }
	local out = {}
	for _, vp in LayoutAssert.GATE_VIEWPORTS do
		table.insert(out, vp)
	end
	for _, vp in LayoutAssert.LANDSCAPE_VIEWPORTS do
		if vp.h == 332 then
			table.insert(out, vp)
		end
	end
	return out
end

local function touchControls(s: Layout.Screen): { Layout.Rect }
	-- Roblox's thumbstick / jump live in the bottom TOUCH_CONTROLS_HEIGHT screen px on phones.
	if not s.compact then
		return {}
	end
	local h = Layout.TOUCH_CONTROLS_HEIGHT / s.scale
	return { Layout.rect(0, s.height - h, s.width, h) }
end

describe("PvP hotbar placement", function()
	for _, vp in viewports() do
		for _, collapsed in { true, false } do
			it(
				`{vp.name} nav {if collapsed then "collapsed" else "expanded"}: 11 slots stay on screen, touch-sized and clear of the HUD cards`,
				function()
					local s = Layout.screen(vp.w, vp.h, { navCollapsed = collapsed })
					local check = LayoutAssert.new(`{vp.name} nav {collapsed}`, s)
					for _, count in { 1, 3, 9, 11, 40 } do
						local p = PvpHudLogic.hotbar(s, count)
						expect(p.visible >= math.min(count, 3)).toBe(true)
						expect(p.visible <= PvpHudLogic.MAX_VISIBLE).toBe(true)
						expect(p.scrolls).toBe(count > p.visible)
						expect(#p.slots).toBe(p.visible)
						check.onScreen(`Hotbar({count})`, p.box, Layout.MARGIN - 0.001)
						check.noOverlap(`Hotbar({count})`, p.box, "Hud", s.hud.rect)
						check.noOverlap(`Hotbar({count})`, p.box, "Nav", s.nav)
						check.noOverlap(`Hotbar({count})`, p.box, "Toasts", s.toasts)
						check.noOverlap(
							`Hotbar({count})`,
							p.box,
							"Banners(reserve)",
							Layout.rect(s.banners.x, s.banners.y, s.banners.w, PvpHudLogic.BANNER_RESERVE)
						)
						for name, rect in
							{
								Carry = s.carry,
								Slap = s.slap,
								Tutorial = s.tutorial,
								TutorialCarrying = s.tutorialCarrying,
							}
						do
							check.noOverlap(`Hotbar({count})`, p.box, name, rect)
						end
						for i, control in touchControls(s) do
							check.noOverlap(`Hotbar({count})`, p.box, `TouchControls[{i}]`, control)
						end
						for i, slot in p.slots do
							check.touch(`Hotbar({count}) slot {i}`, slot)
							check.inside(`Hotbar({count}) slot {i}`, slot, "box", p.box)
							if i > 1 then
								check.noOverlap(`slot {i}`, slot, `slot {i - 1}`, p.slots[i - 1])
							end
						end
					end
					expect(check.report()).toBe("")
				end
			)
		end
	end

	it("no slots, no strip", function()
		local p = PvpHudLogic.hotbar(Layout.screen(1920, 1080), 0)
		expect(p.visible).toBe(0)
		expect(p.box.w).toBe(0)
		expect(p.scrolls).toBe(false)
	end)

	it("a Roblox-sized phone fits at least the three tool slots, a desktop all nine keybinds", function()
		expect(PvpHudLogic.hotbar(Layout.screen(390, 844), 11).visible >= 4).toBe(true)
		expect(PvpHudLogic.hotbar(Layout.screen(1920, 1080), 11).visible).toBe(9)
		expect(PvpHudLogic.hotbar(Layout.screen(1920, 1080), 11).canvasW).toBe(11 * 56 + 10 * 6)
	end)
end)

describe("PvpHud mounted with the stub", function()
	local function mounted(vp: { w: number, h: number }, rank: number): (any, any, Layout.Screen, any)
		local root = UiHarness.root()
		local banners = UiHarness.Instance.new("Frame")
		banners.Name = "Banners"
		banners.Parent = root
		local client = PvpClient.new({
			now = function()
				return 100
			end,
			send = function() end,
			flag = true,
		})
		client.applyState({ pvp = PvpClient.stubState(rank) })
		local hud = PvpHud.new(root, registry, client, { banners = banners })
		local s = Layout.screen(vp.w, vp.h)
		hud.layout(s)
		return hud, root, s, client
	end

	for _, vp in viewports() do
		it(`{vp.name}: the strip, canvas and 11 slot buttons follow PvpHudLogic.hotbar`, function()
			local hud, _, s = mounted(vp, 30)
			local p = PvpHudLogic.hotbar(s, 11)
			expect(hud.frame.Visible).toBe(true)
			expect(hud.frame.Position.X.Offset).toBe(math.round(p.box.x))
			expect(hud.frame.Position.Y.Offset).toBe(math.round(p.box.y))
			expect(hud.frame.Size.X.Offset).toBe(p.box.w)
			expect(hud.frame.Size.Y.Offset).toBe(p.box.h)
			expect(hud.strip.CanvasSize.X.Offset).toBe(p.canvasW)
			expect(hud.strip.ScrollingEnabled).toBe(p.scrolls)
			local buttons = 0
			for _, child in hud.strip:GetChildren() do
				if child.ClassName == "TextButton" then
					buttons += 1
					expect(child.Size.X.Offset).toBe(PvpHudLogic.SLOT)
					expect(child.Size.Y.Offset * s.scale >= Layout.MIN_TOUCH).toBe(true)
				end
			end
			expect(buttons).toBe(11)
			hud.destroy()
		end)
		it(`{vp.name}: the shield and safe-zone chips fit the banner column`, function()
			local s = Layout.screen(vp.w, vp.h)
			local check = LayoutAssert.new(vp.name, s)
			local textW = s.banners.w - (PvpHudLogic.CHIP_HEIGHT + 6)
			check.text({
				name = "Shield chip",
				text = "Shield 59:59",
				size = 15,
				bold = true,
				w = textW,
				h = PvpHudLogic.CHIP_HEIGHT,
				wrapped = true,
			})
			check.text({
				name = "Zone chip",
				text = "Safe zone: Fountain",
				size = 15,
				bold = true,
				w = s.banners.w,
				h = PvpHudLogic.CHIP_HEIGHT,
				wrapped = true,
			})
			expect(check.report()).toBe("")
		end)
	end

	it("hides the strip with no slots and re-places it when slots appear", function()
		local hud, _, _, client = mounted({ w = 1920, h = 1080 }, 0)
		expect(#client.hotbarSlots()).toBe(1)
		client.applyState({})
		expect(hud.frame.Visible).toBe(false)
		client.applyState({ pvp = PvpClient.stubState(5) })
		expect(hud.frame.Visible).toBe(true)
		hud.destroy()
	end)

	it("marks the equipped slot and drops a slot the server took away", function()
		local hud, _, _, client = mounted({ w = 1920, h = 1080 }, 12)
		expect(hud.views.KnockGlove4.button:GetAttribute("Equipped")).toBe(true)
		expect(hud.views.GooTrap3.button:GetAttribute("Equipped")).toBe(false)
		local state = { pvp = PvpClient.stubState(12) }
		state.pvp.equipped = "GooTrap3"
		state.pvp.owned.FunBalloon = nil
		client.applyState(state)
		expect(hud.views.GooTrap3.button:GetAttribute("Equipped")).toBe(true)
		expect(hud.views.FunBalloon).toBeNil()
		expect(hud.views.KnockGlove4.key.Text).toBe("1")
		hud.destroy()
	end)

	it("draws the ring halves with a gradient and the Banners chips use free LayoutOrders", function()
		local hud, root = mounted({ w = 1920, h = 1080 }, 5)
		local slot = hud.views.KnockGlove2
		expect(slot.rightGradient.ClassName).toBe("UIGradient")
		expect(slot.rightHalf.ClipsDescendants).toBe(true)
		local shield = UiHarness.find(root, "PvpShield")
		local zone = UiHarness.find(root, "PvpSafeZone")
		expect(shield.LayoutOrder).toBe(PvpHudLogic.CHIP_ORDER_SHIELD)
		expect(zone.LayoutOrder).toBe(PvpHudLogic.CHIP_ORDER_ZONE)
		local hudSrc = fs.readFile("src/ui/Hud.luau")
		for order in string.gmatch(hudSrc, "LayoutOrder = (%d+)") do
			expect((tonumber(order) :: number) < PvpHudLogic.CHIP_ORDER_SHIELD).toBe(true)
		end
		for order in string.gmatch(hudSrc, 'banner%(banners, "%w+", [^,]+, (%d+)%)') do
			expect((tonumber(order) :: number) < PvpHudLogic.CHIP_ORDER_SHIELD).toBe(true)
		end
		hud.destroy()
	end)
end)

describe("PvP HUD sources", function()
	it("create GUI objects only: no Workspace access, no Parts, nothing built at require time", function()
		for _, file in { "PvpClient", "PvpHudLogic", "PvpHud", "PvpMount" } do
			local src = require("./GlyphCheck").stripComments(fs.readFile(`src/ui/{file}.luau`))
			expect(
				`{file}: {string.find(src, "workspace", 1, true) == nil and string.find(src, "Workspace", 1, true) == nil}`
			).toBe(`{file}: true`)
			expect(`{file}: {string.find(src, 'Instance.new("Part"', 1, true) == nil}`).toBe(`{file}: true`)
			expect(`{file}: {string.find(src, "GetService", 1, true) == nil or file == "PvpClient"}`).toBe(
				`{file}: true`
			)
		end
	end)
	it("the init hook is gated by Config.FEATURES.PvP and reads nothing PvP otherwise", function()
		local src = fs.readFile("src/ui/init.client.luau")
		expect(string.find(src, "local pvp = if Config.FEATURES.PvP == true", 1, true) ~= nil).toBe(true)
		expect(string.find(src, "\n\telse nil\n", 1, true) ~= nil).toBe(true)
	end)
end)
