--!strict
--[[
	UI (owner: Jolt) -> StarterPlayerScripts.UI

	Code-built ScreenGui: HUD, plot / merge / shop / rebirth / goals /
	SlimeDex / leaderboard menus (v28: content-sized cards over a dimmed
	full-window backdrop) and the Guide card (opened by "Talk" at the
	TutorialNpc; "Open Shop" at the ShopStand opens the Shop), carry overlay, daily reward popup, tutorial
	overlay; plus in-world leaderboard SurfaceGuis (WorldLeaderboard). Renders the latest `State`
	snapshot (CONTRACT §5.1); every button calls
	`Request:InvokeServer(action, ...)` (§3). The client never decides outcomes.

	Every top-level box comes from Layout.screen (v18 mobile-first): the bottom money / status
	clusters and a 2-column grid of nav tiles (Oct 18: no top bar, no toasts). One modal at a
	time (PopupQueue: the tutorial holds the daily popup back) and a "tap here" hint for tutorial
	steps that need a menu button (Hint).
]]

local AssetService = game:GetService("AssetService")
local ContextActionService = game:GetService("ContextActionService")
local GuiService = game:GetService("GuiService")
local Players = game:GetService("Players")
local ProximityPromptService = game:GetService("ProximityPromptService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local SoundService = game:GetService("SoundService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))
local Constants = require(Shared:WaitForChild("Constants"))
local FriendBonus = require(Shared:WaitForChild("FriendBonus"))
local Genome = require(Shared:WaitForChild("Genome"))
local MeshAssets = require(Shared:WaitForChild("MeshAssets"))
local PlotSkins = require(Shared:WaitForChild("PlotSkins"))
local Remotes = require(Shared:WaitForChild("Remotes"))
local SlimeLooks = require(Shared:WaitForChild("SlimeLooks"))
local SlimeRoster = require(Shared:WaitForChild("SlimeRoster"))
local StealAlert = require(Shared:WaitForChild("StealAlert"))
local TripleMerge = require(Shared:WaitForChild("TripleMerge"))
local Types = require(Shared:WaitForChild("Types"))

local Format = require(script.Format)
local Hint = require(script.Hint)
local Hud = require(script.Hud)
local Icons = require(script.Icons)
local Inventory = require(script.Inventory)
local InventoryTools = require(script.InventoryTools)
local ItemIconView = require(script.ItemIconView)
local ItemIcons = require(script.ItemIcons)
local Layout = require(script.Layout)
local MenuClose = require(script.MenuClose)
local MenuState = require(script.MenuState)
local Nav = require(script.Nav)
local PopupQueue = require(script.PopupQueue)
local PvpAim = require(script.PvpAim)
local RareAnnounce = require(script.RareAnnounce)
local SlimeInfoCard = require(script.SlimeInfoCard)
local SoundController = require(script.SoundController)
local Sounds = require(script.Sounds)
local SpeciesModel = require(script.SpeciesModel)
local StealAlertFx = require(script.StealAlertFx)
local Widgets = require(script.Widgets)
local WorldLeaderboard = require(script.WorldLeaderboard)
local WorldShopLogic = require(script.WorldShopLogic)
local Panels = script.Panels
local BossMeterPanel = require(Panels.BossMeter)
local CarryPanel = require(Panels.Carry)
local CodesPanel = require(Panels.Codes)
local DailyPopup = require(Panels.DailyPopup)
local DexPanel = require(Panels.Dex)
local GoalsPanel = require(Panels.Goals)
local GuidePanel = require(Panels.Guide)
local HintOverlay = require(Panels.HintOverlay)
local LeaderboardPanel = require(Panels.Leaderboard)
local MergePanel = require(Panels.Merge)
local PlotPanel = require(Panels.Plot)
local RebirthPanel = require(Panels.Rebirth)
local ShopPanel = require(Panels.Shop)
local SoundPanel = require(Panels.Sound)
local TutorialOverlay = require(Panels.TutorialOverlay)
local WelcomePanel = require(Panels.Welcome)
local WorldShopPanel = require(Panels.WorldShop)

local Theme = Widgets.Theme

local player = Players.LocalPlayer
local request = Remotes.get(Constants.REQUEST) :: RemoteFunction
local stateEvent = Remotes.get(Constants.STATE) :: RemoteEvent
local notifyEvent = Remotes.get(Constants.NOTIFY) :: RemoteEvent
local leaderboardEvent = Remotes.get("Leaderboard") :: RemoteEvent
-- Hit / trap / blaster / fun FX + SFX and the victim-side launch from PvpEvent (CONTRACT.md §26.1). Always on: the live
-- default Bat's knockback (itemId "Bat") rides the same event; with FEATURES.PvP off nothing else ever fires it.
require(script.PvpEffects).start(Remotes.get(Constants.PVP_EVENT) :: RemoteEvent)

local gui = Widgets.create("ScreenGui", {
	Name = "SlimeUI",
	ResetOnSpawn = false,
	IgnoreGuiInset = false,
	ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
	Parent = player:WaitForChild("PlayerGui"),
})

-- Phones: shrink the whole UI (Layout.uiScale; 1 on desktop). Set with the
-- rest of the layout in applyLayout below.
local uiScale = Widgets.create("UIScale", { Name = "ViewportScale", Parent = gui }) :: UIScale

local latest: Types.State? = nil
local clockOffset: number? = nil

local function serverNow(): number
	if clockOffset then
		return Format.serverNow(clockOffset, os.clock())
	end
	return workspace:GetServerTimeNow()
end

-- One item icon registry for every item UI (ItemIcons); kit meshes render in viewports.
local itemIcons = ItemIcons.build(Config)
ItemIconView.builders.mesh = ItemIconView.meshBuilder(MeshAssets, AssetService)

-- B6 (Merijn, 2026-10-18): no top-right notifications. A Notify only plays its sound (the steal alarm, the
-- cash ring ...); nothing is drawn.
local function playNotifySound(sound: string?)
	if sound and SoundController.play(sound) then
		return
	end
	local id = Sounds.resolve(sound)
	if not id then
		return
	end
	local s = Instance.new("Sound")
	s.SoundId = id
	SoundService:PlayLocalSound(s)
	task.delay(5, function()
		s:Destroy()
	end)
end
local soundController = if Config.FEATURES.Audio == true
	then SoundController.new(Config, player, require(Shared:WaitForChild("DayNight")))
	else nil
if soundController then
	require(script.ButtonClicks).start(gui, SoundController.play)
end

-- Display names for UserIds (thieves, carriers). Async lookup for players who left.
local names: { [number]: string } = {}
local function playerName(userId: number): string
	local p = Players:GetPlayerByUserId(userId)
	if p then
		return p.DisplayName
	end
	if names[userId] == nil then
		names[userId] = "someone"
		task.spawn(function()
			local ok, name = pcall(Players.GetNameFromUserIdAsync, Players, userId)
			if ok and type(name) == "string" then
				names[userId] = name
			end
		end)
	end
	return names[userId]
end

-- One in-flight call per action; failures only warn (no toasts any more). `onResult`
-- (optional) gets the RequestResult of a call that reached the server.
local busy: { [string]: boolean } = {}
local worldShop: any = nil -- WorldShopLogic.controller, FEATURES.WorldShops only (made below, once setOpen exists)
-- `onFail` (optional) gets the { ok = false, message } of a call the server refused.
local function call(action: string, onResult: ((any) -> ())?, onFail: ((any) -> ())?, ...: any)
	assert(Remotes.ACTIONS[action], `unknown action {action}`)
	if busy[action] then
		return
	end
	busy[action] = true
	local args = table.pack(...)
	task.spawn(function()
		local ok, result = pcall(function()
			return request:InvokeServer(action, table.unpack(args, 1, args.n))
		end)
		busy[action] = nil
		if not ok then
			warn(`[UI] {action} failed - try again`)
		elseif type(result) == "table" and result.ok == false then
			-- A world-shop denial (result.code) is told to the shop controller, which has no toast to show.
			if onFail then
				onFail(result)
			elseif not (worldShop and worldShop.failed(result)) then
				warn(`[UI] {action}: {if type(result.message) == "string" then result.message else "failed"}`)
			end
		elseif onResult then
			onResult(result)
		end
	end)
end
local function invoke(action: string, onResult: ((any) -> ())?, ...: any)
	call(action, onResult, nil, ...)
end
local function send(action: string, ...: any)
	invoke(action, nil, ...)
end

-- SlimeDex pictures: the real slime model from Archer's
-- Visuals.ModelFactory (same builder as the in-world slimes), untagged so
-- no slime-tag listener picks up the viewport copy. nil = no Visuals.
local modelFactory: any = nil
do
	local visuals = ReplicatedStorage:FindFirstChild("Visuals")
	local module = visuals and visuals:FindFirstChild("ModelFactory")
	if module and module:IsA("ModuleScript") then
		local ok, result = pcall(require, module)
		if ok then
			modelFactory = result
		else
			warn("[UI] Visuals.ModelFactory failed to load:", result)
		end
	end
end
local function buildSlime(genome: any): Model?
	if modelFactory == nil then
		return nil
	end
	local model = modelFactory.build(genome) :: Model
	for _, tag in model:GetTags() do
		model:RemoveTag(tag)
	end
	return model
end

-- togglePanel is filled in below, once the panels exist.
local ctx: { [string]: any } = {
	Config = Config,
	Constants = Constants,
	Genome = Genome,
	TripleMerge = TripleMerge,
	-- Studio only: SlimeUI.PcwMergeVat = true shows the 3-slime vat panel with FEATURES.MergeVat3 off (pc-watcher shot).
	vat3Forced = function(): boolean
		return game:GetService("RunService"):IsStudio() and gui:GetAttribute("PcwMergeVat") == true
	end,
	actions = Remotes.ACTIONS,
	send = send,
	request = invoke,
	-- Like request, but `done` also gets a refusal ({ ok = false, message }) for the panel to show.
	ask = function(action: string, done: (any) -> (), ...: any)
		call(action, done, done, ...)
	end,
	serverNow = serverNow,
	playerName = playerName,
	itemIcons = itemIcons,
	buildSlime = if modelFactory then buildSlime else nil,
	-- SlimeDex cards: species names / colours and the species mesh preview.
	SlimeRoster = SlimeRoster,
	SlimeLooks = SlimeLooks,
	buildSpecies = SpeciesModel.builder(function()
		return ReplicatedStorage:FindFirstChild(Constants.SLIME_KITS_FOLDER)
	end, MeshAssets.IMPORT_YAW),
}

local hud = Hud.new(gui, ctx)
-- S3 hotbar + inventory panel (replaces the default Roblox backpack bar).
InventoryTools.hideDefaultBackpack()
local inventory = Inventory.new(gui, {
	Config = Config,
	itemIcons = itemIcons,
	send = send,
	request = function(action: string, done: (any) -> (), ...: any)
		call(action, done, done, ...)
	end,
	aim = function(screen: Vector2 | Vector3): any
		return PvpAim.sample(screen, Constants.CARRYING_ATTRIBUTE)
	end,
	tools = InventoryTools.new(player),
	serverNow = serverNow,
	keyboard = game:GetService("UserInputService").KeyboardEnabled,
	input = game:GetService("UserInputService"),
})
InventoryTools.bindKeys(inventory.keyCodeToSlot, inventory.pressKey)
InventoryTools.bindBag(inventory.isBagKey, inventory.toggleBag)
InventoryTools.bindUse(inventory.useHeld)
local stealFx = StealAlertFx.new(gui, {
	Config = Config,
	Constants = Constants,
	StealAlert = StealAlert,
	serverNow = serverNow,
})
local carry = CarryPanel.new(gui, ctx)
local bossMeter = BossMeterPanel.new(gui, ctx)
local leaderboard = LeaderboardPanel.new(gui, ctx)
local dailyPopup = DailyPopup.new(gui, ctx)
local tutorial = TutorialOverlay.new(gui, ctx)
local hintOverlay = HintOverlay.new(gui)
local popups = PopupQueue.new()
local worldBoards = WorldLeaderboard.start(workspace, player.UserId)
-- One label per slime, a tag above it or a sign on its pad (contract/slime-labels.md): event-driven, no frame work.
SlimeInfoCard.start({ collection = game:GetService("CollectionService"), tag = Constants.SLIME_TAG })

-- The dimmed full-window backdrop (Layout.backdrop: the whole viewport, top bar included, square) behind an open menu card (screen.panel).
-- Made before the panels so their cards draw over it; a tap on it closes
-- the menu, like the X.
local backdrop = Widgets.create("TextButton", {
	Name = "MenuBackdrop",
	Text = "",
	AutoButtonColor = false,
	BackgroundColor3 = Color3.new(0, 0, 0),
	BackgroundTransparency = 0.45,
	Visible = false,
	Parent = gui,
}) :: TextButton

-- Menu cards: one open at a time, toggled from the left nav (Nav.ENTRIES
-- order: Plot, Rebirth, Goals, SlimeDex, Codes) or a world prompt, closed with their X, the backdrop, Esc or
-- gamepad B.
local panelByKey: { [string]: any } = {
	Plot = PlotPanel.new(gui, ctx),
	Merge = MergePanel.new(gui, ctx),
	Shop = ShopPanel.new(gui, ctx),
	WorldShop = if Config.FEATURES.WorldShops == true then WorldShopPanel.new(gui, ctx) else nil,
	Rebirth = RebirthPanel.new(gui, ctx),
	Goals = GoalsPanel.new(gui, ctx),
	Dex = DexPanel.new(gui, ctx),
	Leaders = leaderboard,
	Codes = CodesPanel.new(gui, ctx),
}
type PanelEntry = { key: string, nav: Nav.Entry?, panel: any }
local panels: { PanelEntry } = {}
for _, navEntry in Nav.ENTRIES do
	local panel = panelByKey[navEntry.key]
	if panel then
		table.insert(panels, { key = navEntry.key, nav = navEntry, panel = panel })
	end
end
-- Every menu: the nav ones plus the cards without a nav button: Merge, Shop (opened by the ShopStand prompt;
-- the in-world shops reuse it) and Top (H1 HUD: Merijn removed their buttons), the Guide and Welcome cards.
local allPanels: { PanelEntry } = table.clone(panels)
for _, key in { "Merge", "Shop", "Leaders" } do
	table.insert(allPanels, { key = key, nav = nil, panel = panelByKey[key] })
end
if panelByKey.WorldShop then
	table.insert(allPanels, { key = "WorldShop", nav = nil, panel = panelByKey.WorldShop })
end
table.insert(allPanels, { key = "Guide", nav = nil, panel = GuidePanel.new(gui, ctx) })
table.insert(allPanels, { key = "Welcome", nav = nil, panel = WelcomePanel.new(gui, ctx) })
-- FEATURES.Audio: the Sound card (no nav button) opens from a speaker icon in the top-right slot.
local soundPanel = if soundController then SoundPanel.new(gui, soundController) else nil
if soundPanel then
	table.insert(allPanels, { key = "Sound", nav = nil, panel = soundPanel })
	for _, attr in { "AudioMuted", "AudioSfxVolume", "AudioMusicVolume" } do
		player:GetAttributeChangedSignal(attr):Connect(soundPanel.refresh)
	end
end

local allKeys: { string } = {}
for _, entry in allPanels do
	table.insert(allKeys, entry.key)
end

-- B5: the nav is a bare grid of rounded tiles (no panel behind it), the icon on the tile, the label under it.
local nav = Widgets.create("Frame", {
	Name = "Nav",
	BackgroundTransparency = 1,
	Parent = gui,
})

type NavButton = {
	button: TextButton,
	tile: Frame,
	label: TextLabel,
	icon: any, -- ItemIconView handle
	stroke: UIStroke,
	badge: TextLabel,
}

local NAV_TILE_COLOR = Color3.fromRGB(58, 36, 110) -- the money plate's purple, like the reference tiles

local openKey: string? = nil
local soundButton: any = nil -- FEATURES.Audio only
local navButtons: { [string]: NavButton } = {}
local screen: Layout.Screen? = nil
local applyLayout: () -> ()
local refreshHint: () -> ()
local pumpPopups: (state: Types.State) -> ()
local layoutCards: () -> ()
-- Panels that change their own height (Plot's Appraise screen) ask for a card relayout.
ctx.relayout = function()
	layoutCards()
end

local function styleNav(btn: NavButton, selected: boolean)
	btn.tile.BackgroundColor3 = if selected then Theme.Accent else NAV_TILE_COLOR
	btn.label.TextColor3 = if selected then Theme.Accent else Theme.Text
	btn.stroke.Color = if selected then Color3.new(1, 1, 1) else Color3.fromRGB(10, 10, 20)
	btn.stroke.Thickness = if selected then 4 else 3
end

-- Open state is derived from the cards' own Visible: the backdrop, nav
-- highlight and hint follow it, so a card shown or hidden any other way than
-- setOpen (Esc, a script, a debug tool) can never strand a dim overlay.
local wasOpen: { [string]: boolean } = {}
local wasPumped = false -- the Welcome card was open at the last syncMenus: pump the queue when it closes

-- Studio-only PC watcher hook: the SlimeUI attribute "PcwRebirthSlime" ("owned" / "missing")
-- forces the Rebirth panel's required-slime state so both shots can be taken without a real
-- slime. Live servers (not Studio) always get the server's State untouched.
local isStudio = game:GetService("RunService"):IsStudio()
-- Studio-only: the SlimeUI attribute "PcwFriendBonus" (a friend count) fakes State.friends
-- so the friend badge and income line can be shot on a solo server.
local function forceFriends(state: any): any
	local count = if isStudio then gui:GetAttribute("PcwFriendBonus") else nil
	if type(count) ~= "number" or count < 1 then
		return state
	end
	local view = table.clone(state)
	view.friends = { count = count, bonus = FriendBonus.bonus(count) }
	return view
end

-- Studio-only: the SlimeUI attribute "PcwAdminEvent" ("luck") fakes a live admin event
-- in State.modifier so the banner can be shot without a second admin account.
local function forceAdminEvent(state: any): any
	local id = if isStudio then gui:GetAttribute("PcwAdminEvent") else nil
	local def = nil
	for _, candidate in Config.ADMIN_EVENTS do
		if candidate.id == id then
			def = candidate
		end
	end
	if not def or type(state.serverTime) ~= "number" then
		return state
	end
	local view = table.clone(state)
	view.modifier = {
		name = "Admin_" .. def.id,
		label = def.label,
		luck = def.luck,
		endsAt = state.serverTime + 540,
		icon = def.icon,
	}
	return view
end

-- Studio-only: the SlimeUI attribute "PcwRain" = true fakes a running Slime Rain (97 s left from the first read)
-- for the bottom-right status slot, whatever the workspace RainActive attributes say.
local forcedRainEndsAt: number? = nil
local function forcedRain(now: number): { active: boolean, endsAt: number?, nextAt: number? }?
	if not isStudio or gui:GetAttribute("PcwRain") ~= true then
		forcedRainEndsAt = nil
		return nil
	end
	if forcedRainEndsAt == nil or forcedRainEndsAt < now then
		forcedRainEndsAt = now + 97
	end
	return { active = true, endsAt = forcedRainEndsAt, nextAt = nil }
end
ctx.forcedRain = forcedRain

-- Studio-only: the SlimeUI attribute "PcwStealAlert" = true fakes the join notice (State.stealAway);
-- StealAlertFx fakes the flash and arrow itself.
local function forceStealAlert(state: any): any
	if not isStudio or gui:GetAttribute("PcwStealAlert") ~= true then
		return state
	end
	local view = table.clone(state)
	view.stealAway = StealAlert.summary({
		{ thief = "Rex", slime = "Blob", at = 0 },
		{ thief = "Mia", slime = "Pip", at = 0 },
		{ thief = "Rex", slime = "Gus", at = 0 },
	})
	return view
end

-- Studio-only: the SlimeUI attribute "PcwWelcome" = true fakes State.welcomeBack (5 h 30 m away) for the welcome-back card.
local function forceWelcome(state: any): any
	if not isStudio or gui:GetAttribute("PcwWelcome") ~= true or state.welcomeBack ~= nil then
		return state
	end
	local view = table.clone(state)
	view.welcomeBack = { away = 19800, cash = 12400, grown = 3 }
	return view
end

-- Studio-only: the SlimeUI attribute "PcwWeekend" = true fakes a live x2 Weekend window (State.weekend).
local function forceWeekend(state: any): any
	if not isStudio or gui:GetAttribute("PcwWeekend") ~= true or type(state.serverTime) ~= "number" then
		return state
	end
	local view = table.clone(state)
	view.weekend = { active = true, multiplier = Config.WEEKEND.multiplier, endsAt = state.serverTime + 100800 }
	return view
end

-- Studio-only: the SlimeUI attribute "PcwBlessed" = true fakes the ritual's Blessed boost (State.blessed, 179 s
-- left from the first read) for the bottom-right status slot.
local forcedBlessedEndsAt: number? = nil
local function forceBlessed(state: any): any
	if not isStudio or gui:GetAttribute("PcwBlessed") ~= true or type(state.serverTime) ~= "number" then
		forcedBlessedEndsAt = nil
		return state
	end
	if forcedBlessedEndsAt == nil or forcedBlessedEndsAt < state.serverTime then
		forcedBlessedEndsAt = state.serverTime + 179
	end
	local view = table.clone(state)
	view.blessed = { bonus = Config.RITUAL.BONUS[Config.RITUAL.MIN_PLAYERS], endsAt = forcedBlessedEndsAt }
	return view
end

-- Studio-only: the SlimeUI attribute "PcwDexRows" = N marks the first N State.dex entries found (named)
-- so the Dex grid can be shot with found cards and silhouettes side by side.
local function forceDex(state: any): any
	local count = if isStudio then gui:GetAttribute("PcwDexRows") else nil
	if type(count) ~= "number" or count <= 0 or type(state.dex) ~= "table" then
		return state
	end
	local dex = table.clone(state.dex)
	local entries = {}
	for i, entry in dex.entries or {} do
		local e = table.clone(entry)
		if i <= count then
			local roster = SlimeRoster.get(e.id)
			e.found = true
			e.name = if roster then roster.name else e.id
		end
		entries[i] = e
	end
	dex.entries = entries
	dex.found = math.min(count, dex.total or count)
	local view = table.clone(state)
	view.dex = dex
	return view
end

-- Studio-only: the SlimeUI attribute "PcwPlotSkin" (a skin id) fakes State.plotSkins with that skin
-- unlocked and equipped (every other skin locked at 0 owned), so the picker can be shot with
-- FEATURES.PlotSkins off. Live servers (not Studio) always get the server's State untouched.
local function forcePlotSkins(state: any): any
	local id = if isStudio then gui:GetAttribute("PcwPlotSkin") else nil
	if type(id) ~= "string" or id == "" or state.plotSkins ~= nil then
		return state
	end
	local total = PlotSkins.setSize()
	local view = table.clone(state)
	view.plotSkin = id
	view.plotSkins = {}
	for _, skin in Config.PLOT_SKINS do
		local rarity = if skin.set then Config.RARITIES[skin.set] else nil
		local on = skin.id == id
		table.insert(view.plotSkins, {
			id = skin.id,
			name = skin.name,
			setName = if rarity then rarity.name else nil,
			tier = skin.set,
			owned = if on or skin.set == nil then total else 0,
			total = total,
			needed = if skin.set then PlotSkins.needed(skin) else 0,
			fraction = if on or skin.set == nil then 1 else 0,
			unlocked = on or skin.set == nil,
			equipped = on,
		})
	end
	return view
end

local function panelState(key: string, realState: any): any
	local state = forceWelcome(forcePlotSkins(forceFriends(realState)))
	if isStudio and key == "Plot" and gui:GetAttribute("PcwPlotSlime") == true and #state.slimes == 0 then
		-- Studio-only: one fake owned slime so the My Plot row shows its Appraise button.
		local view = table.clone(state)
		view.slimes = {
			{
				slime = {
					id = "pcw-plot",
					name = "Blorp",
					tier = 3,
					color = { 90, 200, 120 },
					size = 1.2,
					pattern = "None",
					eyes = "Round",
					mouth = "Smile",
					pad = 1,
				},
				income = 12,
				sellPrice = 450,
				appraiseCost = 135,
			},
		}
		view.padsUnlocked = math.max(1, state.padsUnlocked or 1)
		-- ... which is also the favourite, so its row shows the follow-pet perk chip.
		view.favoriteId = "pcw-plot"
		view.petPerk = { kind = "luck", value = 0.03, icon = "🍀", text = "+3% luck" }
		return view
	end
	local force = if isStudio and key == "Rebirth" then gui:GetAttribute("PcwRebirthSlime") else nil
	local need = state.rebirthSlime
	if (force ~= "owned" and force ~= "missing") or type(need) ~= "table" then
		return state
	end
	local view = table.clone(state)
	view.rebirthSlime = table.clone(need)
	view.rebirthSlime.owned = force == "owned"
	view.canRebirth = view.rebirthSlime.owned and state.cash >= state.rebirthCost
	return view
end

local function syncMenus()
	local visibleKey: string? = nil
	for _, entry in allPanels do
		local isOpen = entry.panel.frame.Visible
		if isOpen and visibleKey == nil then
			visibleKey = entry.key
		end
		if wasOpen[entry.key] ~= isOpen then
			wasOpen[entry.key] = isOpen
			if entry.panel.setOpen then
				entry.panel.setOpen(isOpen)
			end
			if isOpen and latest and entry.panel.update then
				entry.panel.update(panelState(entry.key, latest))
				layoutCards()
			end
		end
		if navButtons[entry.key] then
			styleNav(navButtons[entry.key], isOpen)
		end
	end
	openKey = visibleKey
	if latest and wasPumped ~= (visibleKey == "Welcome") then
		wasPumped = visibleKey == "Welcome"
		if not wasPumped then
			pumpPopups(latest)
		end
	end
	hud.setMenuOpen(not MenuState.bannersVisible(visibleKey))
	inventory.setMenuOpen(visibleKey ~= nil)
	tutorial.setMenuOpen(not MenuState.tutorialVisible(visibleKey))
	backdrop.Visible = visibleKey ~= nil
	-- Phones: the open menu card spans the nav's width (Layout.screen columnX), so the tiles step aside.
	nav.Visible = not (screen ~= nil and screen.compact and visibleKey ~= nil)
	if soundButton then
		soundButton.instance.Visible = visibleKey == nil
	end
	refreshHint()
end

local function setOpen(key: string?)
	local view = MenuState.view(key, allKeys)
	for _, entry in allPanels do
		entry.panel.frame.Visible = view.cards[entry.key]
	end
	syncMenus()
end

for _, entry in allPanels do
	entry.panel.frame:GetPropertyChangedSignal("Visible"):Connect(syncMenus)
end

-- Sound button (FEATURES.Audio): icon only, shown with no menu open; the open card has its own X.
if soundPanel then
	soundButton = Widgets.button(
		{
			Name = "SoundButton",
			Text = Icons.SOUND_ON,
			TextSize = 28,
			Visible = false,
		},
		Theme.BgLight,
		function()
			setOpen("Sound")
		end
	)
	soundButton.instance.Parent = gui
	local function refreshIcon()
		soundButton.setText(if soundController.settings().muted then Icons.SOUND_OFF else Icons.SOUND_ON)
	end
	refreshIcon()
	player:GetAttributeChangedSignal("AudioMuted"):Connect(refreshIcon)
end

for _, entry in panels do
	local navEntry = entry.nav :: Nav.Entry
	local button = Widgets.create("TextButton", {
		Name = entry.key,
		Text = "",
		AutoButtonColor = false,
		BackgroundTransparency = 1,
		Size = UDim2.fromOffset(Layout.NAV.cell, Layout.NAV.tile + Layout.NAV.labelGap + Layout.NAV.label),
		Parent = nav,
	}) :: TextButton
	local tile = Widgets.create("Frame", {
		Name = "Tile",
		BackgroundColor3 = NAV_TILE_COLOR,
		Size = UDim2.fromOffset(Layout.NAV.tile, Layout.NAV.tile),
		Position = UDim2.fromOffset((Layout.NAV.cell - Layout.NAV.tile) // 2, 0),
		Parent = button,
	}, { Widgets.corner(16) })
	local stroke = Widgets.stroke(Color3.fromRGB(10, 10, 20), 3)
	stroke.Parent = tile
	local icon = ItemIconView.new({
		Name = "Icon",
		Id = navEntry.item,
		Size = Layout.NAV.tile - Layout.NAV.iconInset * 2,
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Parent = tile,
	}, itemIcons)
	icon.setActive(true)
	local label = Widgets.label({
		Name = "Label",
		Text = navEntry.label,
		Font = Theme.Font,
		TextSize = Layout.NAV.labelSize,
		TextXAlignment = Enum.TextXAlignment.Center,
		TextStrokeTransparency = 0.2,
		TextTruncate = Enum.TextTruncate.None,
		Size = UDim2.fromOffset(Layout.NAV.cell, Layout.NAV.label),
		Position = UDim2.fromOffset(0, Layout.NAV.tile + Layout.NAV.labelGap),
		Parent = button,
	})
	local badge = Widgets.label({
		Name = "Badge",
		Visible = false,
		Font = Theme.Font,
		TextSize = Layout.NAV_BADGE.textSize,
		TextXAlignment = Enum.TextXAlignment.Center,
		TextTruncate = Enum.TextTruncate.None,
		BackgroundTransparency = 0,
		BackgroundColor3 = Theme.Bad,
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.new(1, -Layout.NAV_BADGE.inset, 0, Layout.NAV_BADGE.inset),
		Size = UDim2.fromOffset(Layout.NAV_BADGE.minWidth, Layout.NAV_BADGE.height),
		AutomaticSize = Enum.AutomaticSize.X,
		ZIndex = 3,
		Parent = button,
	})
	Widgets.corner(Layout.NAV_BADGE.height // 2).Parent = badge
	Widgets.create("UIPadding", {
		PaddingLeft = UDim.new(0, Layout.NAV_BADGE.padding),
		PaddingRight = UDim.new(0, Layout.NAV_BADGE.padding),
		Parent = badge,
	})
	button.Activated:Connect(function()
		setOpen(if openKey == entry.key then nil else entry.key)
	end)
	navButtons[entry.key] = {
		button = button,
		tile = tile,
		label = label,
		icon = icon,
		stroke = stroke,
		badge = badge,
	}
end

for _, entry in allPanels do
	entry.panel.close.Activated:Connect(function()
		setOpen(nil)
	end)
end
backdrop.Activated:Connect(function()
	setOpen(nil)
end)

-- "Open Shop" at the ShopStand and "Talk" at the Guide NPC (CONTRACT.md
-- §5.3): the server only places the prompts; this client opens the menu.
local PROMPT_MENUS =
	MenuClose.promptMenus(Constants.SHOP_PROMPT_NAME, Constants.GUIDE_PROMPT_NAME, Config.FEATURES.WorldShops == true)
-- The 3-slime vat prompt (owner only) opens the merge menu (CONTRACT.md §21.1).
if Config.FEATURES.MergeVat3 then
	PROMPT_MENUS[Constants.MERGE_PROMPT_NAME] = "Merge"
end
ProximityPromptService.PromptTriggered:Connect(function(prompt: ProximityPrompt, who: Player)
	local key = PROMPT_MENUS[prompt.Name]
	if key and who == player then
		setOpen(key)
	end
end)

-- World shops (FEATURES.WorldShops, CONTRACT.md §27): the server opens a shop at the stand's ShopPrompt and tells
-- this client with ShopEvent and the OpenShop attribute; the card closes on ShopEvent Close / attribute nil, and
-- a close from this side (X, backdrop, Esc / B, another menu) sends Request("CloseShop").
if panelByKey.WorldShop then
	worldShop = WorldShopLogic.controller({
		open = function(shopId: string)
			panelByKey.WorldShop.setShop(shopId)
			setOpen("WorldShop")
		end,
		close = function()
			if openKey == "WorldShop" then
				setOpen(nil)
			end
		end,
		toast = function() end, -- B6: no toasts; the shop card shows its own state
		send = send,
		clock = os.clock,
	})
	ctx.worldShop = worldShop
	local shopEvent = Remotes.get(Constants.SHOP_EVENT) :: RemoteEvent
	shopEvent.OnClientEvent:Connect(worldShop.onEvent)
	player:GetAttributeChangedSignal(Constants.OPEN_SHOP_ATTRIBUTE):Connect(function()
		worldShop.onAttribute(player:GetAttribute(Constants.OPEN_SHOP_ATTRIBUTE))
	end)
end

-- Nav tiles from Layout.screen: every button box holds its rounded tile and the label under it.
local function layoutNav(s: Layout.Screen)
	local r = s.nav
	nav.Position = UDim2.fromOffset(r.x, r.y)
	nav.Size = UDim2.fromOffset(r.w, r.h)
	local N = Layout.NAV
	local tileSize = if s.compact then N.ctile else N.tile
	local labelH = if s.compact then N.clabel else N.label
	for i, entry in panels do
		local btn = navButtons[entry.key]
		local b = s.navButtons[i]
		btn.button.Position = UDim2.fromOffset(math.round(b.x - r.x), math.round(b.y - r.y))
		btn.button.Size = UDim2.fromOffset(math.round(b.w), math.round(b.h))
		local tile = Layout.navTile(s.compact, b)
		btn.tile.Position = UDim2.fromOffset(math.round(tile.x - b.x), 0)
		btn.tile.Size = UDim2.fromOffset(tileSize, tileSize)
		local iconSize = tileSize - N.iconInset * 2
		btn.icon.instance.Size = UDim2.fromOffset(iconSize, iconSize)
		btn.label.Position = UDim2.fromOffset(0, tileSize + N.labelGap)
		btn.label.Size = UDim2.fromOffset(math.round(b.w), labelH)
		btn.label.TextSize = if s.compact then N.clabelSize else N.labelSize
	end
end

local lastHint: Hint.View? = nil

function refreshHint()
	lastHint = if latest then Hint.fromState(latest, openKey) else nil
	if lastHint == nil or screen == nil or not nav.Visible then
		hintOverlay.set(nil)
		return
	end
	hintOverlay.set(Hint.place(screen, lastHint), lastHint.text)
end

-- Sizes every menu card to its measured body content (Widgets.contentHeight),
-- clamped to the backdrop. Runs on resize and again whenever an open panel's
-- content changes (setOpen, state updates).
function layoutCards()
	local s = screen
	if s == nil then
		return
	end
	for _, entry in allPanels do
		local body = entry.panel.frame:FindFirstChild("Body")
		local r = if entry.key == "Sound"
			then (SoundPanel.place(s))
			else Layout.panelFor(s, entry.key, Widgets.contentHeight(body or entry.panel.frame))
		local frame = entry.panel.frame
		frame.AnchorPoint = Vector2.zero
		frame.Position = UDim2.fromOffset(r.x, r.y)
		frame.Size = UDim2.fromOffset(r.w, r.h)
		if entry.panel.layout then
			entry.panel.layout(r, s)
		end
	end
end

-- Every top-level box for the current ScreenGui size (and nav choice).
function applyLayout()
	local size = gui.AbsoluteSize
	if size.X <= 0 or size.Y <= 0 then
		return
	end
	uiScale.Scale = Layout.uiScale(size.X, size.Y)
	local s = Layout.screen(size.X, size.Y)
	screen = s
	hud.layout(s)
	inventory.layout(s)
	stealFx.layout(s, hud.bannerHeight)
	bossMeter.layout(s, hud.bannerHeight)
	carry.layout(s)
	tutorial.layout(s)
	dailyPopup.layout(s)
	layoutNav(s)
	syncMenus() -- the nav's phone / desktop visibility follows the new size
	if soundButton then
		soundButton.instance.Position = UDim2.fromOffset(s.sound.x, s.sound.y)
		soundButton.instance.Size = UDim2.fromOffset(s.sound.w, s.sound.h)
	end
	local guiInset = GuiService:GetGuiInset()
	local back = Layout.backdrop(s, guiInset.X, guiInset.Y)
	backdrop.Position = UDim2.fromOffset(back.x, back.y)
	backdrop.Size = UDim2.fromOffset(back.w, back.h)
	layoutCards()
	refreshHint()
end

gui:GetPropertyChangedSignal("AbsoluteSize"):Connect(applyLayout)
applyLayout()
setOpen(nil)

-- Studio-only test hook for the PC watcher (tools/pipeline/pc-watcher): setting the
-- SlimeUI attribute "PcwOpen" to a panel key opens it through the normal setOpen path
-- (contents rendered), "" closes it. Never active in live servers.
if game:GetService("RunService"):IsStudio() then
	gui:GetAttributeChangedSignal("PcwOpen"):Connect(function()
		local key = gui:GetAttribute("PcwOpen")
		if worldShop and key == "WorldShop" then
			-- the world shop card as the stand's prompt opens it; the shop comes from the PcwWorldShop attribute
			local shopId = gui:GetAttribute("PcwWorldShop")
			worldShop.onEvent({ kind = "Open", shopId = if type(shopId) == "string" then shopId else "ItemShop" })
			return
		end
		setOpen(if type(key) == "string" and key ~= "" then key else nil)
	end)
	gui:GetAttributeChangedSignal("PcwPlotSlime"):Connect(function()
		for _, entry in allPanels do
			if entry.key == "Plot" and latest and entry.panel.frame.Visible then
				entry.panel.update(panelState(entry.key, latest))
			end
		end
	end)
	gui:GetAttributeChangedSignal("PcwRebirthSlime"):Connect(function()
		for _, entry in allPanels do
			if entry.key == "Rebirth" and latest and entry.panel.frame.Visible then
				entry.panel.update(panelState(entry.key, latest))
			end
		end
	end)
end

-- Gamepad B always closes the open menu or the bag (same as its X), and Esc too while
-- Layout.CLOSE_WITH_ESCAPE is true (v27 default); see MenuClose.
local closeMenuAction = MenuClose.bind(ContextActionService, Layout.CLOSE_WITH_ESCAPE, function()
	return MenuClose.topKey(openKey, dailyPopup.isOpen(), inventory.panelOpen())
end, function()
	local top = MenuClose.topKey(openKey, dailyPopup.isOpen(), inventory.panelOpen())
	if top == "Daily" then
		dailyPopup.close()
	elseif top == MenuClose.BAG then
		inventory.setPanelOpen(false)
	else
		setOpen(nil)
	end
end)

-- Studio-only test hook for the PC watcher: setting the SlimeUI attribute "PcwPress" to
-- "Escape" runs the same CloseMenu action handler as the CAS binding (execute_luau cannot
-- call ContextActionService:CallFunction: lacking capability RobloxScript). It tests the
-- close logic, not real key routing. The hook clears "PcwPress" and writes "PcwPressResult":
-- "closed" / "pass" (no menu open), or "not_bound" when Esc is not bound (CLOSE_WITH_ESCAPE off).
if game:GetService("RunService"):IsStudio() then
	gui:GetAttributeChangedSignal("PcwPress"):Connect(function()
		if gui:GetAttribute("PcwPress") ~= "Escape" then
			return
		end
		if not Layout.CLOSE_WITH_ESCAPE then
			gui:SetAttribute("PcwPressResult", "not_bound")
		else
			local result = closeMenuAction("CloseMenu", Enum.UserInputState.Begin)
			gui:SetAttribute("PcwPressResult", if result == Enum.ContextActionResult.Sink then "closed" else "pass")
		end
		gui:SetAttribute("PcwPress", nil)
	end)
end

local function updateBadges(state: Types.State)
	local badges = Nav.badges(state)
	for key, btn in navButtons do
		local text = badges[key]
		btn.badge.Visible = text ~= nil
		if text then
			btn.badge.Text = text
			btn.badge.BackgroundColor3 = if text == "!" then Theme.Bad else Theme.Info
		end
	end
end

function ctx.togglePanel(key: string)
	setOpen(if openKey == key then nil else key)
end

-- Queued popups (welcome-back card, then the daily popup) wait for the tutorial and for each other.
function pumpPopups(state: Types.State)
	local next = popups.update(state, openKey == "Welcome")
	if next == "Welcome" then
		setOpen("Welcome")
	elseif next == "Daily" and not dailyPopup.isOpen() then
		dailyPopup.open()
	end
end

local function render(realState: Types.State)
	local state: Types.State =
		forceWelcome(forceStealAlert(forceDex(forceWeekend(forceBlessed(forceAdminEvent(forceFriends(realState)))))))
	hud.update(state)
	inventory.update(state)
	stealFx.update(state)
	carry.update(state)
	bossMeter.update(state)
	dailyPopup.update(state)
	tutorial.update(state)
	updateBadges(state)
	pumpPopups(state)
	refreshHint()
	for _, entry in allPanels do
		if entry.key == openKey and entry.panel.update then
			entry.panel.update(panelState(entry.key, state))
			layoutCards()
		end
	end
end

if isStudio then
	for _, attribute in
		{
			"PcwFriendBonus",
			"PcwAdminEvent",
			"PcwWeekend",
			"PcwPlotSkin",
			"PcwDexRows",
			"PcwStealAlert",
			"PcwMergeVat",
			"PcwWelcome",
			"PcwRain",
			"PcwBlessed",
		}
	do
		gui:GetAttributeChangedSignal(attribute):Connect(function()
			if latest then
				pcall(render, latest)
			end
		end)
	end
end

-- FEATURES.Audio: the saved Sound card values are applied once on join; later slider / mute changes
-- go back to the server after SETTINGS_SEND_DELAY (> the 0.5 s rate limit) without a new change.
local SETTINGS_SEND_DELAY = 0.6
local settingsLoaded = false
local settingsSent = nil
local settingsToken = 0
local function currentSettings(): any
	local s = soundController.settings()
	return { musicVolume = s.music, sfxVolume = s.sfx, muted = s.muted }
end
local function sameSettings(a: any, b: any): boolean
	return a ~= nil
		and b ~= nil
		and a.musicVolume == b.musicVolume
		and a.sfxVolume == b.sfxVolume
		and a.muted == b.muted
end
local function queueSettingsSend()
	settingsToken += 1
	local token = settingsToken
	task.delay(SETTINGS_SEND_DELAY, function()
		local now = currentSettings()
		if token ~= settingsToken or sameSettings(now, settingsSent) then
			return
		end
		settingsSent = now
		send("SetAudioSettings", now.musicVolume, now.sfxVolume, now.muted)
	end)
end
if soundController then
	for _, attr in { "AudioMuted", "AudioSfxVolume", "AudioMusicVolume" } do
		player:GetAttributeChangedSignal(attr):Connect(function()
			if settingsLoaded then
				queueSettingsSend()
			end
		end)
	end
end

stateEvent.OnClientEvent:Connect(function(state: Types.State)
	if type(state) ~= "table" then
		return
	end
	if soundController and not settingsLoaded and type(state.settings) == "table" then
		soundController.load(state.settings)
		settingsSent = currentSettings()
		task.defer(function()
			settingsLoaded = true
		end)
	end
	latest = state
	if type(state.serverTime) == "number" then
		clockOffset = Format.clockOffset(state.serverTime, os.clock())
	end
	local ok, err = pcall(render, state)
	if not ok then
		warn("[UI] render failed:", err)
	end
end)

notifyEvent.OnClientEvent:Connect(function(text: string, _kind: Types.NotifyKind, sound: string?, _itemId: string?)
	local message = tostring(text)
	-- H1 HUD (Merijn): no specific-slime notifications. Legendary+ drop news (RareAnnounce.classify) is
	-- dropped here; every other Notify only plays its sound (B6: no toasts). The boss event shows in BossMeter.
	if RareAnnounce.classify(message, sound) then
		return
	end
	playNotifySound(sound)
end)

-- Studio-only PC watcher hook: the SlimeUI attribute "PcwTooltip" ("Rain" | "Event" | "Friend") opens that
-- status icon's tooltip (B8); "" closes it.
if isStudio then
	gui:GetAttributeChangedSignal("PcwTooltip"):Connect(function()
		local id = gui:GetAttribute("PcwTooltip")
		hud.showTooltip(if type(id) == "string" and id ~= "" then id else nil)
	end)
end

leaderboardEvent.OnClientEvent:Connect(function(board: Types.Leaderboard)
	leaderboard.setBoard(board)
	worldBoards.setBoard(board)
end)

-- Local countdowns (lock, rain, escape) between State pushes.
task.spawn(function()
	while true do
		task.wait(0.1)
		if latest then
			local now = serverNow()
			hud.tick(now)
			inventory.tick()
			carry.tick(now)
			bossMeter.tick(now)
			panelByKey.Codes.tick(now)
			if panelByKey.WorldShop then
				panelByKey.WorldShop.tick()
			end
			hintOverlay.tick(now, tutorial.shown() and MenuState.tutorialVisible(openKey))
		end
	end
end)

send("Sync")
