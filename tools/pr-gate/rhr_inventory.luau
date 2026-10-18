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

-- The nav as init.client builds it (rounded tile with the item picture, label under it); init.client has no
-- module to mount, so the same widgets are drawn from Layout.screen's boxes.
local function drawNav(root: any, s: Layout.Screen, registry: any)
	local Widgets = UiHarness.ui("Widgets")
	local ItemIconView = UiHarness.ui("ItemIconView")
	local Nav = UiHarness.ui("Nav")
	local N = Layout.NAV
	local nav = Widgets.create("Frame", {
		Name = "Nav",
		BackgroundTransparency = 1,
		Position = UDim2.fromOffset(s.nav.x, s.nav.y),
		Size = UDim2.fromOffset(s.nav.w, s.nav.h),
		Parent = root,
	})
	local tileSize = if s.compact then N.ctile else N.tile
	local labelH = if s.compact then N.clabel else N.label
	for i, entry in Nav.ENTRIES do
		local b = s.navButtons[i]
		local button = Widgets.create("TextButton", {
			Name = entry.key,
			Text = "",
			BackgroundTransparency = 1,
			Position = UDim2.fromOffset(math.round(b.x - s.nav.x), math.round(b.y - s.nav.y)),
			Size = UDim2.fromOffset(math.round(b.w), math.round(b.h)),
			Parent = nav,
		})
		local tile = Widgets.create("Frame", {
			Name = "Tile",
			BackgroundColor3 = Color3.fromRGB(58, 36, 110),
			Position = UDim2.fromOffset(math.round(Layout.navTile(s.compact, b).x - b.x), 0),
			Size = UDim2.fromOffset(tileSize, tileSize),
			Parent = button,
		}, { Widgets.corner(16) })
		Widgets.stroke(Color3.fromRGB(10, 10, 20), 3).Parent = tile
		local iconSize = tileSize - N.iconInset * 2
		local icon = ItemIconView.new({
			Name = "Icon",
			Id = entry.item,
			Size = iconSize,
			AnchorPoint = roblox.Vector2.new(0.5, 0.5),
			Position = UDim2.fromScale(0.5, 0.5),
			Parent = tile,
		}, registry)
		icon.setActive(true)
		Widgets.label({
			Name = "Label",
			Text = entry.label,
			Font = Widgets.Theme.Font,
			TextSize = if s.compact then N.clabelSize else N.labelSize,
			TextStrokeTransparency = 0.2,
			Size = UDim2.fromOffset(math.round(b.w), labelH),
			Position = UDim2.fromOffset(0, tileSize + N.labelGap),
			Parent = button,
		})
	end
end

local Inventory = UiHarness.ui("Inventory")
local Widgets = UiHarness.ui("Widgets")

local PVP = { "KnockGlove1", "GooBlaster1", "FunConfetti" }

local cases = {
	{ name = "phone-portrait", w = 390, h = 844, panel = false },
	{ name = "phone-landscape", w = 844, h = 390, panel = false },
	{ name = "pc-1366x768", w = 1366, h = 768, panel = false },
	{ name = "pc-1920x1080", w = 1920, h = 1080, panel = false },
	{ name = "pc-1920x1080-tooltip", w = 1920, h = 1080, panel = false, tooltip = true },
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
	local registry = ItemIcons.build(Config)
	-- The real Hud (money, status, banners) with the shipped Config but both status features on, a running
	-- rain, a luck event and a friend boost, as in a live server.
	UiHarness.workspaceAttributes.RainActive = true
	UiHarness.workspaceAttributes.RainEndsAt = 1097
	local flagsOn = table.clone(Config) :: any
	flagsOn.FEATURES = table.clone(Config.FEATURES)
	flagsOn.FEATURES.CycleModifier = true
	flagsOn.FEATURES.FriendBonus = true
	local hud = UiHarness.ui("Hud").new(root, {
		Config = flagsOn,
		Constants = require("../../games/steal-a-slime/src/shared/Constants"),
		Genome = require("../../games/steal-a-slime/src/shared/Genome"),
		actions = require("../../games/steal-a-slime/src/shared/Remotes").ACTIONS,
		send = function() end,
		request = function() end,
		serverNow = function()
			return 1000
		end,
		playerName = function()
			return "Tester"
		end,
		itemIcons = registry,
	})
	hud.layout(s)
	hud.update({
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
		modifier = { name = "Admin_luck", label = "Luck Event", luck = 3, mutation = 1, endsAt = 1540, icon = "🍀" },
		friends = { count = 1, bonus = 0.1 },
	})
	if case.tooltip then
		hud.showTooltip("Event")
	end
	-- Phones: an open menu card spans the nav's width and init.client hides the tiles meanwhile.
	if not (case.panel and s.compact) then
		drawNav(root, s, registry)
	end

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
