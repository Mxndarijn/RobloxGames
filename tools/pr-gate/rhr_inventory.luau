--!strict
-- Writes ScreenGui models of the S3 hotbar / inventory panel for rhr: the REAL src/ui/Inventory built under the
-- Lune UI harness (tests/ui/UiHarness), converted to real Instances, over plain plates for the money / status
-- clusters and the bottom cards so the placement can be judged. Run from games/steal-a-slime:
--   lune run ../../tools/pr-gate/rhr_inventory.luau <outDir>
-- then:  rhr ui <outDir>/<case>.rbxmx --viewport WxH --out <png>   (manifest.json lists the cases)
local fs = require("@lune/fs")
local process = require("@lune/process")
local roblox = require("@lune/roblox") :: any
local serde = require("@lune/serde")

local Config = require("../../games/steal-a-slime/src/shared/Config")
local ItemIcons = require("../../games/steal-a-slime/src/ui/ItemIcons")
local Layout = require("../../games/steal-a-slime/src/ui/Layout")
local UDim2, Color3, Enum = roblox.UDim2, roblox.Color3, roblox.Enum
local UiHarness = require("../../games/steal-a-slime/tests/ui/UiHarness")

local TOPBAR = 58
local outDir = process.args[1] or "rhr-out"
fs.writeDir(outDir)

-- Harness mock tree -> real Instances (the mock keeps every property it was given).
local function toReal(mock: any): any
	local real = roblox.Instance.new(rawget(mock, "_class"))
	for key, value in rawget(mock, "_props") do
		pcall(function()
			real[key] = value
		end)
	end
	for key, value in rawget(mock, "_attributes") do
		real:SetAttribute(key, value)
	end
	for _, child in rawget(mock, "_children") do
		toReal(child).Parent = real
	end
	return real
end

local function plate(parent: any, name: string, r: Layout.Rect, color: any, text: string)
	local f = UiHarness.ui("Widgets").create("Frame", {
		Name = name,
		Position = UDim2.fromOffset(math.round(r.x), math.round(r.y)),
		Size = UDim2.fromOffset(math.round(r.w), math.round(r.h)),
		BackgroundColor3 = color,
		BackgroundTransparency = 0.2,
		Parent = parent,
	})
	UiHarness.ui("Widgets").label({
		Name = "Text",
		Text = text,
		TextSize = 14,
		TextXAlignment = Enum.TextXAlignment.Center,
		Size = UDim2.fromScale(1, 1),
		Parent = f,
	})
end

local Inventory = UiHarness.ui("Inventory")
local Widgets = UiHarness.ui("Widgets")

local PVP = { "KnockGlove1", "GooBlaster1", "FunConfetti" }

local cases = {
	{ name = "phone-portrait", w = 390, h = 844, panel = false },
	{ name = "phone-landscape", w = 844, h = 390, panel = false },
	{ name = "pc-1920x1080", w = 1920, h = 1080, panel = false },
	{ name = "pc-1920x1080-panel", w = 1920, h = 1080, panel = true },
	{ name = "phone-portrait-panel", w = 390, h = 844, panel = true },
}

local manifest = { topbar = TOPBAR, cases = {} }
for _, case in cases do
	local gw, gh = case.w, case.h - TOPBAR
	local s = Layout.screen(gw, gh)
	local gui = UiHarness.root()
	gui.Name = "SlimeUI"
	local root = Widgets.create("Frame", {
		Name = "Root",
		BackgroundTransparency = 1,
		Size = UDim2.fromOffset(math.round(s.width), math.round(s.height)),
		Parent = gui,
	})
	Widgets.create("UIScale", { Name = "ViewportScale", Scale = s.scale, Parent = root })
	plate(root, "Money", s.money.rect, Color3.fromRGB(58, 36, 110), "$ 12.5K  (money)")
	plate(root, "Status", s.status.rect, Color3.fromRGB(40, 90, 70), "events")
	plate(root, "Hud", s.hud.rect, Color3.fromRGB(28, 30, 44), "HUD bar")
	plate(root, "Nav", s.nav, Color3.fromRGB(28, 30, 44), "nav")

	local tools = {
		items = { { name = "Bat", equipped = true }, { name = "SpeedCoil", equipped = false } },
	}
	function tools.list()
		return tools.items
	end
	function tools.setEquipped() end
	function tools.unequipAll() end
	function tools.onChanged() end
	local owned = {}
	for _, id in PVP do
		owned[id] = true
	end
	local inv = Inventory.new(root, {
		Config = Config,
		itemIcons = ItemIcons.build(Config),
		send = function() end,
		tools = tools,
		serverNow = function()
			return 100
		end,
		keyboard = case.w >= 1000,
	})
	inv.layout(s)
	inv.update({ pvp = { owned = owned, equipped = nil, cooldowns = {} } })
	if case.panel then
		inv.setPanelOpen(true)
	end

	local file = `{outDir}/{case.name}.rbxmx`
	fs.writeFile(file, roblox.serializeModel({ toReal(gui) }, true))
	table.insert(manifest.cases, { name = case.name, file = file, viewport = { case.w, case.h } })
end
fs.writeFile(`{outDir}/manifest.json`, serde.encode("json", manifest, true))
print(`wrote {#manifest.cases} cases to {outDir}`)
