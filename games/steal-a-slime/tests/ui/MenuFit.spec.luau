--!strict
-- Every scroll area of a menu stays inside its card body at every gate viewport. A list taller than the card
-- (its box sized for the card's full design height while a short phone screen cuts the card) runs past the
-- card's bottom: its last rows are off the card and, when the canvas only fills that over-tall box, the list
-- has nothing to scroll, so a phone can't reach them. Builds the real panels (tests/ui/UiHarness.luau) and lays
-- them out as init.client's layoutCards does: the card is as tall as its measured content, at most the backdrop.
local roblox = require("@lune/roblox") :: any

local Config = require("../../src/shared/Config")
local Constants = require("../../src/shared/Constants")
local Fixtures = require("../Fixtures")
local Genome = require("../../src/shared/Genome")
local Layout = require("../../src/ui/Layout")
local PlayerSettings = require("../../src/shared/PlayerSettings")
local Remotes = require("../../src/shared/Remotes")
local ServerFixtures = require("../ServerFixtures")
local Snapshot = require("../../src/server/Snapshot")
local TestRunner = require("../TestRunner")
local UiHarness = require("./UiHarness")

local describe, it, expect = TestRunner.describe, TestRunner.it, TestRunner.expect
local UDim2 = roblox.UDim2

-- The gate viewports plus the short landscape phones (each under the 58 px Roblox top bar too).
local VIEWPORTS = {
	{ 390, 844 },
	{ 844, 390 },
	{ 844, 332 },
	{ 667, 375 },
	{ 667, 317 },
	{ 740, 360 },
	{ 1024, 768 },
	{ 1366, 768 },
	{ 1920, 1080 },
}

-- Menus with a scroll area; a world shop card per shop.
local MENUS: { { key: string, shopId: string? } } = {
	{ key = "WorldShop", shopId = "ItemShop" },
	{ key = "WorldShop", shopId = "UpgradeShop" },
	{ key = "Skins" },
	{ key = "ExclusiveShop" },
	{ key = "Dex" },
	{ key = "Goals" },
	{ key = "Merge" },
	{ key = "Settings" },
	{ key = "Codes" },
	{ key = "Rebirth" },
	{ key = "Leaderboard" },
}

local function ctx(): any
	return {
		Config = Config,
		Constants = Constants,
		Genome = Genome,
		actions = Remotes.ACTIONS,
		send = function() end,
		serverNow = function()
			return ServerFixtures.T0
		end,
		playerName = function()
			return "Tester"
		end,
		toast = function() end,
		relayout = function() end,
		PlayerSettings = PlayerSettings,
		settings = {
			get = function(id: string)
				return PlayerSettings.defaults()[id]
			end,
			set = function() end,
			reset = function() end,
		},
		userId = 42,
		placeVersion = 1,
		request = function() end,
	}
end

local function state(): any
	local slimes = {}
	for i = 1, 6 do
		table.insert(slimes, Fixtures.slime(`s{i}`, 1 + (i % 3)))
	end
	local world = ServerFixtures.world()
	local session = ServerFixtures.join(world, 1, slimes, 5000)
	return Snapshot.build(world, session, ServerFixtures.T0)
end

type Box = { x: number, y: number, w: number, h: number }

-- `obj`'s box in card space (the card is 0,0 .. w,h), as Roblox places it: scale and offset of the parent box,
-- minus the anchor point. nil for anything inside a ScrollingFrame (canvas space).
local function box(obj: any, card: any, cardBox: Box): Box?
	if obj == card then
		return cardBox
	end
	local parent = obj.Parent
	if parent == nil or parent:IsA("ScrollingFrame") then
		return nil
	end
	local p = box(parent, card, cardBox)
	if p == nil then
		return nil
	end
	local w = obj.Size.X.Scale * p.w + obj.Size.X.Offset
	local h = obj.Size.Y.Scale * p.h + obj.Size.Y.Offset
	return {
		x = p.x + obj.Position.X.Scale * p.w + obj.Position.X.Offset - obj.AnchorPoint.X * w,
		y = p.y + obj.Position.Y.Scale * p.h + obj.Position.Y.Offset - obj.AnchorPoint.Y * h,
		w = w,
		h = h,
	}
end

local function shown(obj: any, card: any): boolean
	local o = obj
	while o and o ~= card do
		if o:IsA("GuiObject") and not o.Visible then
			return false
		end
		o = o.Parent
	end
	return true
end

-- Opens `key` the way setOpen and layoutCards do at w x h; returns every shown scroll area that leaves the body.
local function problems(menu: { key: string, shopId: string? }, w: number, h: number): { string }
	local Widgets = UiHarness.ui("Widgets")
	local module = UiHarness.ui(`Panels/{menu.key}`)
	local panel = module.new(UiHarness.root(), ctx())
	panel.frame.Visible = false
	if panel.setShop then
		panel.setShop(menu.shopId)
	end
	if panel.setOpen then
		panel.setOpen(true)
	end
	if panel.update then
		panel.update(state())
	end
	local screen = Layout.screen(w, h)
	local body = panel.frame:FindFirstChild("Body")
	local raw = Layout.panelFor(screen, menu.key, Widgets.contentHeight(body or panel.frame))
	local r = Layout.rect(math.floor(raw.x), math.floor(raw.y), math.floor(raw.w), math.floor(raw.h))
	panel.frame.Size = UDim2.fromOffset(r.w, r.h)
	if panel.layout then
		panel.layout(r, screen)
	end
	panel.frame.Visible = true

	local cardBox = { x = 0, y = 0, w = r.w, h = r.h }
	local bodyBox = box(body, panel.frame, cardBox) :: Box
	local out = {}
	for _, d in UiHarness.descendants(panel.frame) do
		if d:IsA("ScrollingFrame") and shown(d, panel.frame) then
			local b = box(d, panel.frame, cardBox)
			if b then
				local bottom, limit = b.y + b.h, bodyBox.y + bodyBox.h
				if bottom > limit + 1 then
					table.insert(out, `{d.Name} ends at {bottom}, body at {limit} (card {r.h})`)
				end
			end
		end
	end
	return out
end

describe("menu scroll areas fit their card", function()
	for _, menu in MENUS do
		for _, vp in VIEWPORTS do
			local label = if menu.shopId then `{menu.key}:{menu.shopId}` else menu.key
			it(`{label} at {vp[1]}x{vp[2]}: every scroll area ends inside the card body`, function()
				expect(table.concat(problems(menu, vp[1], vp[2]), "; ")).toBe("")
			end)
		end
	end
end)
