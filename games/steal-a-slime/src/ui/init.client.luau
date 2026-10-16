--!strict
--[[
	UI (owner: Jolt) -> StarterPlayerScripts.UI

	Code-built ScreenGui: HUD, plot / merge / shop / rebirth / goals /
	SlimeDex / leaderboard menus (v28: content-sized cards over a dimmed
	full-window backdrop) and the Guide card (opened by "Talk" at the
	TutorialNpc; "Open Shop" at the ShopStand opens the Shop), carry overlay (+ Slap), daily reward popup, tutorial
	overlay, toasts; plus in-world leaderboard SurfaceGuis (WorldLeaderboard). Renders the latest `State`
	snapshot (CONTRACT §5.1); every button calls
	`Request:InvokeServer(action, ...)` (§3). The client never decides outcomes.

	Every top-level box comes from Layout.screen (v18 mobile-first): two HUD
	rows and an icon-only nav on phones, one row and a labelled nav on
	desktop; the nav's toggle switches between them. One modal at a time
	(PopupQueue: the tutorial holds the daily popup back) and a "tap here"
	hint for tutorial steps that need a HUD / menu button (Hint).
]]

local ContextActionService = game:GetService("ContextActionService")
local GuiService = game:GetService("GuiService")
local Players = game:GetService("Players")
local ProximityPromptService = game:GetService("ProximityPromptService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))
local Constants = require(Shared:WaitForChild("Constants"))
local FriendBonus = require(Shared:WaitForChild("FriendBonus"))
local Genome = require(Shared:WaitForChild("Genome"))
local Remotes = require(Shared:WaitForChild("Remotes"))
local Types = require(Shared:WaitForChild("Types"))

local Format = require(script.Format)
local Hint = require(script.Hint)
local Hud = require(script.Hud)
local Icons = require(script.Icons)
local Layout = require(script.Layout)
local MenuClose = require(script.MenuClose)
local MenuState = require(script.MenuState)
local Nav = require(script.Nav)
local PopupQueue = require(script.PopupQueue)
local RareAnnounce = require(script.RareAnnounce)
local Toasts = require(script.Toasts)
local Widgets = require(script.Widgets)
local WorldLeaderboard = require(script.WorldLeaderboard)
local Panels = script.Panels
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
local TutorialOverlay = require(Panels.TutorialOverlay)

local Theme = Widgets.Theme

local player = Players.LocalPlayer
local request = Remotes.get(Constants.REQUEST) :: RemoteFunction
local stateEvent = Remotes.get(Constants.STATE) :: RemoteEvent
local notifyEvent = Remotes.get(Constants.NOTIFY) :: RemoteEvent
local leaderboardEvent = Remotes.get("Leaderboard") :: RemoteEvent

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

local toasts = Toasts.new(gui)

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

-- One in-flight call per action; failures surface as a "bad" toast. `onResult`
-- (optional) gets the RequestResult of a call that reached the server.
local busy: { [string]: boolean } = {}
local function invoke(action: string, onResult: ((any) -> ())?, ...: any)
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
			toasts.push(`{action} failed - try again`, "bad")
		elseif type(result) == "table" and result.ok == false then
			toasts.push(if type(result.message) == "string" then result.message else `{action} failed`, "bad")
		elseif onResult then
			onResult(result)
		end
	end)
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

-- togglePanel / openDaily are filled in below, once the panels exist.
local ctx: { [string]: any } = {
	Config = Config,
	Constants = Constants,
	Genome = Genome,
	actions = Remotes.ACTIONS,
	send = send,
	request = invoke,
	serverNow = serverNow,
	playerName = playerName,
	toast = toasts.push,
	buildSlime = if modelFactory then buildSlime else nil,
}

local hud = Hud.new(gui, ctx)
local carry = CarryPanel.new(gui, ctx)
local leaderboard = LeaderboardPanel.new(gui, ctx)
local dailyPopup = DailyPopup.new(gui, ctx)
local tutorial = TutorialOverlay.new(gui, ctx)
local hintOverlay = HintOverlay.new(gui)
local popups = PopupQueue.new()
local worldBoards = WorldLeaderboard.start(workspace, player.UserId)

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
-- order) or a world prompt, closed with their X, the backdrop, Esc or
-- gamepad B.
local panelByKey: { [string]: any } = {
	Plot = PlotPanel.new(gui, ctx),
	Merge = MergePanel.new(gui, ctx),
	Shop = ShopPanel.new(gui, ctx),
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
-- Every menu: the nav ones plus the Guide card (no nav button).
local allPanels: { PanelEntry } = table.clone(panels)
table.insert(allPanels, { key = "Guide", nav = nil, panel = GuidePanel.new(gui, ctx) })

local allKeys: { string } = {}
for _, entry in allPanels do
	table.insert(allKeys, entry.key)
end

local nav = Widgets.create("Frame", {
	Name = "Nav",
	BackgroundColor3 = Theme.Bg,
	BackgroundTransparency = 0.05,
	Parent = gui,
}, {
	Widgets.corner(14),
	Widgets.stroke(Color3.fromRGB(10, 10, 20), 2),
})

type NavButton = {
	button: TextButton,
	label: TextLabel,
	icon: TextLabel,
	stroke: UIStroke,
	marker: Frame,
	badge: TextLabel,
}

local openKey: string? = nil
local navButtons: { [string]: NavButton } = {}
-- nil until the player taps the toggle: follow Layout.navDefaultCollapsed.
local navChoice: boolean? = nil
local screen: Layout.Screen? = nil
local applyLayout: () -> ()
local refreshHint: () -> ()

local function styleNav(btn: NavButton, selected: boolean)
	btn.button.BackgroundColor3 = if selected then Theme.Accent else Theme.BgLight
	btn.label.TextColor3 = if selected then Color3.fromRGB(16, 40, 24) else Theme.Text
	btn.stroke.Color = if selected then Color3.new(1, 1, 1) else Color3.fromRGB(70, 75, 100)
	btn.stroke.Thickness = if selected then 3 else 1
	btn.marker.Visible = selected
end

-- Open state is derived from the cards' own Visible: the backdrop, nav
-- highlight and hint follow it, so a card shown or hidden any other way than
-- setOpen (Esc, a script, a debug tool) can never strand a dim overlay.
local wasOpen: { [string]: boolean } = {}

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

-- Studio-only: the SlimeUI attribute "PcwAdminEvent" ("luck" | "mutation") fakes a live admin event
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
		mutation = def.mutation,
		endsAt = state.serverTime + 540,
		icon = def.icon,
	}
	return view
end

local function panelState(key: string, realState: any): any
	local state = forceFriends(realState)
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
					mutation = "None",
					pad = 1,
				},
				income = 12,
				sellPrice = 450,
				appraiseCost = 135,
			},
		}
		view.padsUnlocked = math.max(1, state.padsUnlocked or 1)
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
			end
		end
		if navButtons[entry.key] then
			styleNav(navButtons[entry.key], isOpen)
		end
	end
	openKey = visibleKey
	hud.setMenuOpen(not MenuState.bannersVisible(visibleKey))
	tutorial.setMenuOpen(not MenuState.tutorialVisible(visibleKey))
	backdrop.Visible = visibleKey ~= nil
	refreshHint()
end

local function setOpen(key: string?)
	-- Phones: an open panel gets the width the nav labels took.
	if key and screen and screen.compact and not screen.navCollapsed then
		navChoice = true
		applyLayout()
	end
	local view = MenuState.view(key, allKeys)
	for _, entry in allPanels do
		entry.panel.frame.Visible = view.cards[entry.key]
	end
	syncMenus()
end

for _, entry in allPanels do
	entry.panel.frame:GetPropertyChangedSignal("Visible"):Connect(syncMenus)
end

-- Collapse / expand toggle: navButtons rect [1].
local navToggle = Widgets.button(
	{ Name = "NavToggle", Text = Icons.NAV_COLLAPSED, TextSize = 13 },
	Theme.BgLight,
	function()
		local collapsed = if screen then screen.navCollapsed else true
		navChoice = not collapsed
		applyLayout()
	end
)
navToggle.instance.TextColor3 = Theme.Muted
navToggle.instance.Parent = nav

for _, entry in panels do
	local button = Widgets.create("TextButton", {
		Name = entry.key,
		Text = "",
		AutoButtonColor = true,
		Size = UDim2.fromOffset(Layout.NAV.button, Layout.NAV.button),
		BackgroundColor3 = Theme.BgLight,
		Parent = nav,
	}, { Widgets.corner(10) }) :: TextButton
	local stroke = Widgets.stroke(Color3.fromRGB(70, 75, 100), 1)
	stroke.Parent = button
	local marker = Widgets.create("Frame", {
		Name = "Selected",
		Visible = false,
		BorderSizePixel = 0,
		BackgroundColor3 = Color3.new(1, 1, 1),
		AnchorPoint = Vector2.new(0, 0.5),
		Position = UDim2.new(0, -6, 0.5, 0),
		Size = UDim2.fromOffset(4, 36),
		Parent = button,
	}, { Widgets.corner(2) })
	local navEntry = entry.nav :: Nav.Entry
	local icon = Widgets.label({
		Name = "Icon",
		Text = navEntry.icon,
		TextSize = 26,
		TextXAlignment = Enum.TextXAlignment.Center,
		TextTruncate = Enum.TextTruncate.None,
		Size = UDim2.new(0, 36, 1, 0),
		Position = UDim2.fromOffset(4, 0),
		Parent = button,
	})
	local label = Widgets.label({
		Name = "Label",
		Text = navEntry.label,
		Font = Theme.Font,
		TextSize = 18,
		TextStrokeTransparency = 0.6,
		Size = UDim2.new(1, -46, 1, 0),
		Position = UDim2.fromOffset(42, 0),
		Parent = button,
	})
	local badge = Widgets.label({
		Name = "Badge",
		Visible = false,
		Font = Theme.Font,
		TextSize = 12,
		TextXAlignment = Enum.TextXAlignment.Center,
		TextTruncate = Enum.TextTruncate.None,
		BackgroundTransparency = 0,
		BackgroundColor3 = Theme.Bad,
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.new(1, 4, 0, -4),
		Size = UDim2.fromOffset(20, 20),
		AutomaticSize = Enum.AutomaticSize.X,
		ZIndex = 3,
		Parent = button,
	})
	Widgets.corner(10).Parent = badge
	Widgets.create("UIPadding", {
		PaddingLeft = UDim.new(0, 4),
		PaddingRight = UDim.new(0, 4),
		Parent = badge,
	})
	button.Activated:Connect(function()
		setOpen(if openKey == entry.key then nil else entry.key)
	end)
	navButtons[entry.key] = {
		button = button,
		label = label,
		icon = icon,
		stroke = stroke,
		marker = marker,
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
local PROMPT_MENUS = MenuClose.promptMenus(Constants.SHOP_PROMPT_NAME, Constants.GUIDE_PROMPT_NAME)
ProximityPromptService.PromptTriggered:Connect(function(prompt: ProximityPrompt, who: Player)
	local key = PROMPT_MENUS[prompt.Name]
	if key and who == player then
		setOpen(key)
	end
end)

-- Nav, toggle and buttons from Layout.screen; collapsed = icons only.
local function layoutNav(s: Layout.Screen)
	local r = s.nav
	nav.Position = UDim2.fromOffset(r.x, r.y)
	nav.Size = UDim2.fromOffset(r.w, r.h)
	local function place(inst: GuiObject, b: Layout.Rect)
		inst.Position = UDim2.fromOffset(b.x - r.x, b.y - r.y)
		inst.Size = UDim2.fromOffset(b.w, b.h)
	end
	place(navToggle.instance, s.navButtons[1])
	navToggle.setText(if s.navCollapsed then Icons.NAV_COLLAPSED else Icons.NAV_EXPANDED)
	navToggle.instance.TextSize = if s.navCollapsed then 13 else 16
	for i, entry in panels do
		local btn = navButtons[entry.key]
		place(btn.button, s.navButtons[i + 1])
		btn.label.Visible = not s.navCollapsed
		btn.icon.Size = if s.navCollapsed then UDim2.fromScale(1, 1) else UDim2.new(0, 36, 1, 0)
		btn.icon.Position = if s.navCollapsed then UDim2.new() else UDim2.fromOffset(4, 0)
	end
end

local lastHint: Hint.View? = nil

function refreshHint()
	lastHint = if latest then Hint.fromState(latest, openKey) else nil
	local hudBoxes = hud.hudLayout()
	if lastHint == nil or screen == nil or hudBoxes == nil then
		hintOverlay.set(nil)
		return
	end
	hintOverlay.set(Hint.place(screen, hudBoxes, lastHint), lastHint.text)
end

-- Every top-level box for the current ScreenGui size (and nav choice).
function applyLayout()
	local size = gui.AbsoluteSize
	if size.X <= 0 or size.Y <= 0 then
		return
	end
	uiScale.Scale = Layout.uiScale(size.X, size.Y)
	local s = Layout.screen(size.X, size.Y, { navCollapsed = navChoice })
	screen = s
	hud.layout(s)
	toasts.layout(s.toasts)
	carry.layout(s)
	tutorial.layout(s)
	dailyPopup.layout(s)
	layoutNav(s)
	local guiInset = GuiService:GetGuiInset()
	local back = Layout.backdrop(s, guiInset.X, guiInset.Y)
	backdrop.Position = UDim2.fromOffset(back.x, back.y)
	backdrop.Size = UDim2.fromOffset(back.w, back.h)
	for _, entry in allPanels do
		local r = Layout.panelFor(s, entry.key)
		local frame = entry.panel.frame
		frame.AnchorPoint = Vector2.zero
		frame.Position = UDim2.fromOffset(r.x, r.y)
		frame.Size = UDim2.fromOffset(r.w, r.h)
		if entry.panel.layout then
			entry.panel.layout(r)
		end
	end
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

-- Gamepad B always closes the open menu (same as its X), and Esc too while
-- Layout.CLOSE_WITH_ESCAPE is true (v27 default); see MenuClose.
local closeMenuAction = MenuClose.bind(ContextActionService, Layout.CLOSE_WITH_ESCAPE, function()
	return openKey
end, function()
	setOpen(nil)
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

function ctx.openDaily()
	if latest then
		dailyPopup.update(latest)
	end
	dailyPopup.open()
end

local function render(realState: Types.State)
	local state: Types.State = forceAdminEvent(forceFriends(realState))
	hud.update(state)
	carry.update(state)
	dailyPopup.update(state)
	tutorial.update(state)
	updateBadges(state)
	-- The daily popup waits in the queue until the tutorial is finished.
	if popups.update(state) == "Daily" and not dailyPopup.isOpen() then
		dailyPopup.open()
	end
	refreshHint()
	for _, entry in allPanels do
		if entry.key == openKey and entry.panel.update then
			entry.panel.update(panelState(entry.key, state))
		end
	end
end

if isStudio then
	for _, attribute in { "PcwFriendBonus", "PcwAdminEvent" } do
		gui:GetAttributeChangedSignal(attribute):Connect(function()
			if latest then
				pcall(render, latest)
			end
		end)
	end
end

stateEvent.OnClientEvent:Connect(function(state: Types.State)
	if type(state) ~= "table" then
		return
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

notifyEvent.OnClientEvent:Connect(function(text: string, kind: Types.NotifyKind, sound: string?)
	local message = tostring(text)
	-- Boss Slime / Legendary+ news gets the long gold "rare" toast and the HUD banner.
	toasts.push(message, if RareAnnounce.classify(message, sound) then "rare" else kind, sound)
	hud.onNotify(message, sound)
end)

-- Studio-only PC watcher hook: the SlimeUI attribute "PcwBadgeToast" (a badge name) shows the unlock toast.
if isStudio then
	gui:GetAttributeChangedSignal("PcwBadgeToast"):Connect(function()
		local name = gui:GetAttribute("PcwBadgeToast")
		if type(name) == "string" and name ~= "" then
			toasts.push(`Badge unlocked: {name}`, "badge", nil)
		end
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
			carry.tick(now)
			panelByKey.Codes.tick(now)
			hintOverlay.tick(now, tutorial.shown() and MenuState.tutorialVisible(openKey))
		end
	end
end)

send("Sync")
