--!strict
--[[
	Admin panel (contract/admin-menu.md §5): the admin menu card. Tabs Me, Items, Spawn and World; each row is one
	AdminCommands command with its buttons, and every button sends `Admin`. The server decides: the reply line under
	the tabs shows its answer. On a server with real saves the cheat rows are sunken wells that say why
	(AdminCommands.lockedReason). Built only for players State.admin names (ui/AdminMenu).
]]

local UI = script.Parent.Parent
local ExclusiveShopView = require(UI.ExclusiveShopView)
local Layout = require(UI.Layout)
local Widgets = require(UI.Widgets)

local Theme = Widgets.Theme
local create = Widgets.create

local Admin = {}

Admin.STYLE = table.freeze({
	tabH = 40,
	tabGap = 6,
	tabSize = 18,
	factH = 26,
	replyY = 48,
	replyH = 22,
	listY = 76,
	rowH = 52,
	headH = 30,
	nameSize = 18,
	btnH = 36,
	btnSize = 16,
	btnPad = 14, -- side padding inside a button
	btnGap = 6,
	charW = 9, -- design px per character of button text, for button widths
	rowPad = 10,
	lockSize = Layout.MIN_TEXT,
	headSize = Layout.MIN_TEXT,
})

Admin.COPY = table.freeze({
	title = "Admin",
	cheatsOn = "Test save: cheats on",
	cheatsOff = "Real saves: admin tools only",
	ready = "Pick a command.",
})

export type Button = {
	text: string,
	arg: string?, -- the id argument
	amount: ((state: any) -> number?)?, -- the number argument from the current State
	color: Color3?,
	hold: boolean?, -- hold to confirm (irreversible)
}
export type Row = {
	key: string,
	head: string?, -- a section heading instead of a command row
	command: string?, -- AdminCommands id
	label: string?, -- row title (defaults to the command's label)
	color: Color3?, -- title colour (rarity rows)
	buttons: { Button }?,
}

local function fixed(n: number): (any) -> number
	return function()
		return n
	end
end

local function head(key: string, text: string): Row
	return { key = key, head = text }
end

-- The rows of each tab, from Config and the rosters. Pure: tests read it.
function Admin.rows(ctx: any): { [string]: { Row } }
	local Config = ctx.Config
	local tabs: { [string]: { Row } } = {}

	tabs.Me = {
		head("hMoney", "Money and time"),
		{
			key = "cashAdd",
			command = "cashAdd",
			buttons = {
				{ text = "+1K", amount = fixed(1e3), color = Theme.Gold },
				{ text = "+1M", amount = fixed(1e6), color = Theme.Gold },
				{ text = "+1B", amount = fixed(1e9), color = Theme.Gold },
			},
		},
		{
			key = "cashSet",
			command = "cashSet",
			label = "Set cash to $0",
			buttons = { { text = "Set $0", amount = fixed(0) } },
		},
		{
			key = "skipTime",
			command = "skipTime",
			buttons = {
				{ text = "1m", amount = fixed(60) },
				{ text = "10m", amount = fixed(600) },
				{ text = "1h", amount = fixed(3600) },
				{ text = "8h", amount = fixed(28800) },
			},
		},
		head("hProgress", "Progress"),
		{
			key = "setRebirths",
			command = "setRebirths",
			buttons = {
				{
					text = "-1",
					amount = function(s)
						return (s.rebirths or 0) - 1
					end,
				},
				{
					text = "+1",
					amount = function(s)
						return (s.rebirths or 0) + 1
					end,
				},
				{ text = "Max", amount = fixed(Config.MAX_REBIRTHS) },
			},
		},
		{
			key = "setPads",
			command = "setPads",
			buttons = {
				{
					text = "-1",
					amount = function(s)
						return (s.padsUnlocked or 1) - 1
					end,
				},
				{
					text = "+1",
					amount = function(s)
						return (s.padsUnlocked or 1) + 1
					end,
				},
				{ text = "Max", amount = fixed(Config.PADS_MAX) },
			},
		},
		{
			key = "setGrowth",
			command = "setGrowth",
			buttons = {
				{ text = "0%", amount = fixed(0) },
				{ text = "50%", amount = fixed(50) },
				{ text = "100%", amount = fixed(100) },
			},
		},
		{ key = "fillDex", command = "fillDex", buttons = { { text = "Fill" } } },
		{ key = "skipTutorial", command = "skipTutorial", buttons = { { text = "Skip" } } },
		{
			key = "resetSave",
			command = "resetSave",
			buttons = { { text = "Hold to reset", color = Theme.Bad, hold = true } },
		},
		head("hMove", "Move"),
		{ key = "goHome", command = "goHome", buttons = { { text = "Go", color = Theme.Info } } },
		{ key = "goHub", command = "goHub", buttons = { { text = "Go", color = Theme.Info } } },
	}

	local items: { Row } = {
		head("hAll", "Unlock everything"),
		{
			key = "grantCosmetics",
			command = "grantCosmetics",
			buttons = { { text = "Grant all", color = Theme.Gold } },
		},
		{ key = "unlockSkins", command = "unlockSkins", buttons = { { text = "Unlock", color = Theme.Gold } } },
		{ key = "unlockSeats", command = "unlockSeats", buttons = { { text = "Unlock", color = Theme.Gold } } },
		head("hConsumables", "Item shop"),
	}
	for _, def in Config.CONSUMABLES do
		table.insert(items, {
			key = `consumable_{def.id}`,
			command = "giveConsumable",
			label = def.name,
			buttons = {
				{ text = "+1", arg = def.id, amount = fixed(1) },
				{ text = "+5", arg = def.id, amount = fixed(5) },
			},
		})
	end
	local shop = Config.EXCLUSIVE_SHOP
	local function product(key: string, name: string)
		if shop.products[key] ~= nil then
			table.insert(items, {
				key = `product_{key}`,
				command = "grantProduct",
				label = name,
				buttons = { { text = "Grant", arg = key } },
			})
		end
	end
	-- On / Off for a pass, the Slime Club or the paid random items policy (amount 1 = on).
	local function toggle(key: string, command: string, label: string, arg: string?)
		table.insert(items, {
			key = key,
			command = command,
			label = label,
			buttons = {
				{ text = "On", arg = arg, amount = fixed(1), color = Theme.Gold },
				{ text = "Off", arg = arg, amount = fixed(0), color = Theme.Info },
			},
		})
	end
	-- "VIP", "Fast brew": the shop's own names; a season's name ("Halloween") for a seasonal item.
	local function shopName(key: string): string
		local t = (ExclusiveShopView.TEXTS :: any)[key]
		return if t then t.title else key
	end
	local function seasonName(id: string?): string?
		local def = if id and shop.seasons then shop.seasons[id] else nil
		return if def then def.name else id
	end
	local function sortedKeys(t: { [string]: any }, order: ((string) -> number)?): { string }
		local keys = {}
		for key in t do
			table.insert(keys, key)
		end
		table.sort(keys, function(a: string, b: string): boolean
			local oa, ob = if order then order(a) else 0, if order then order(b) else 0
			if oa ~= ob then
				return oa < ob
			end
			return a < b
		end)
		return keys
	end

	table.insert(items, head("hPasses", "Exclusive shop: passes"))
	toggle("paidRandom", "setPaidRandom", "Paid random items allowed")
	for _, key in
		sortedKeys(shop.passes, function(k: string): number
			return shop.passes[k].order or math.huge
		end)
	do
		toggle(`pass_{key}`, "setPass", shopName(key), key)
	end
	for _, key in sortedKeys(shop.subscriptions or {}) do
		toggle(`sub_{key}`, "setSubscription", shopName(key), key)
	end

	table.insert(items, head("hBundles", "Exclusive shop: bundles"))
	product("StarterBundle", "Starter bundle")
	product("BoutiqueBundle", "Boutique bundle")
	product("SkyBundle", "Sky bundle")

	table.insert(items, head("hClouds", "Exclusive shop: clouds"))
	for _, seat in Config.PET_SEATS do
		if seat.unlock.kind == "exclusive" then
			local season = (seat :: any).season
			product(`Seat_{seat.id}`, if season then `{seat.name} seat ({seasonName(season)})` else `{seat.name} seat`)
		end
	end

	table.insert(items, head("hBase", "Exclusive shop: base"))
	for _, skin in Config.PLOT_SKINS do
		if skin.exclusive then
			product(
				`Skin_{skin.id}`,
				if skin.season then `{skin.name} skin ({seasonName(skin.season)})` else `{skin.name} skin`
			)
		end
	end
	for _, base in Config.PLOT_BASES do
		if (base :: any).exclusive then
			product(`Base_{base.id}`, `{base.name} base`)
		end
	end
	for _, def in shop.lockStyles or {} do
		product(`LockStyle_{def.id}`, `{def.name} lock`)
	end

	table.insert(items, head("hStyle", "Exclusive shop: style"))
	for _, trail in shop.trails do
		product(`Trail_{trail.id}`, `{trail.name} trail`)
	end
	for _, def in shop.fanfares or {} do
		product(`Fanfare_{def.id}`, `{def.name} fanfare`)
	end
	for _, def in shop.hats or {} do
		product(`Hat_{def.id}`, if def.season then `{def.name} ({seasonName(def.season)})` else def.name)
	end
	for _, skin in shop.batSkins do
		product(`BatSkin_{skin.id}`, `{skin.name} bat skin`)
	end

	table.insert(items, head("hBoosts", "Exclusive shop: boosts"))
	for _, entry in
		{
			{ "ServerLuckPotion", "Server Luck Potion" },
			{ "SlimeRain", "Slime Rain now" },
			{ "SummonBoss", "Summon the boss" },
			{ "WeatherTotem", "Weather Totem" },
			{ "IncomeBoost15", "x2 income, 15 min" },
			{ "IncomeBoost60", "x2 income, 1 hour" },
			{ "DoubleOffline", "Double offline cash" },
			{ "KeepStreak", "Keep my streak" },
			{ "GrowthSnack", "Growth snack" },
			{ "FinishBrew_4", "Finish brew now" },
			{ "LockBreak", "Lock break (credit)" },
		}
	do
		product(entry[1], entry[2])
	end
	tabs.Items = items

	local spawn: { Row } = {
		head("hWorld", "In the world"),
		{
			key = "spawnWave",
			command = "spawnWave",
			buttons = {
				{ text = "+8", amount = fixed(8), color = Theme.Info },
				{ text = "+20", amount = fixed(20), color = Theme.Info },
			},
		},
		{ key = "dropEgg", command = "dropEgg", buttons = { { text = "Drop", color = Theme.Info } } },
		{ key = "hatchEggs", command = "hatchEggs", buttons = { { text = "Hatch", color = Theme.Gold } } },
		head("hRandom", "Random slime on a pad"),
	}
	for tier, rarity in Config.RARITIES do
		table.insert(spawn, {
			key = `tier_{tier}`,
			command = "spawnSlime",
			label = rarity.name,
			color = Widgets.color3(rarity.color),
			buttons = { { text = "Spawn", amount = fixed(tier) } },
		})
	end
	table.insert(spawn, head("hSpecies", "Species on a pad"))
	local roster: { any } = table.clone(ctx.SlimeRoster.ROSTER)
	table.sort(roster, function(a: any, b: any): boolean
		if a.tier ~= b.tier then
			return a.tier < b.tier
		end
		return a.name < b.name
	end)
	for _, entry in roster do
		local rarity = Config.RARITIES[entry.tier]
		table.insert(spawn, {
			key = `species_{entry.id}`,
			command = "spawnSlime",
			label = entry.name,
			color = if rarity then Widgets.color3(rarity.color) else nil,
			buttons = { { text = "Spawn", arg = entry.id, amount = fixed(entry.tier) } },
		})
	end
	tabs.Spawn = spawn

	local weather: { Button } = {}
	for _, id in Config.WEATHER_ORDER do
		table.insert(weather, { text = id, arg = id, color = Theme.Info })
	end
	tabs.World = {
		head("hEvents", "Events in every server"),
		{
			key = "luckEvent",
			command = "luckEvent",
			buttons = { { text = "10 min", amount = fixed(10) }, { text = "30 min", amount = fixed(30) } },
		},
		{ key = "slimeRain", command = "slimeRain", buttons = { { text = "Start" } } },
		head("hServer", "This server"),
		{ key = "nextWeather", command = "nextWeather", buttons = weather },
		{ key = "startBoss", command = "startBoss", buttons = { { text = "Start", color = Theme.Bad } } },
	}
	return tabs
end

local function buttonWidth(text: string): number
	local s = Admin.STYLE
	return s.btnPad * 2 + math.ceil(#text * s.charW)
end

function Admin.new(parent: Instance, ctx: any)
	local S = Admin.STYLE
	local AdminCommands = ctx.AdminCommands
	local panel = Widgets.panel(parent, "AdminPanel", Admin.COPY.title, "🛠")
	local c = Layout.PANEL_CHROME
	local fullH = Layout.menuHeight("Admin") - c.header - c.pad
	-- As tall as a full menu body, so init.client (Widgets.contentHeight) sizes this list menu to fill the window.
	local content = create("Frame", {
		Name = "Content",
		BackgroundTransparency = 1,
		Size = UDim2.new(1, 0, 0, fullH),
		Parent = panel.body,
	})

	local mode = Widgets.chip({
		Name = "Mode",
		Text = Admin.COPY.cheatsOff,
		AnchorPoint = Vector2.new(1, 0.5),
		Position = UDim2.new(1, -(c.close + c.closeInset * 2), 0, c.closeInset + c.close // 2),
		Size = UDim2.fromOffset(0, S.factH),
		ZIndex = 2,
		Parent = panel.frame,
	}, Theme.Text)

	local reply = Widgets.label({
		Name = "Reply",
		Text = Admin.COPY.ready,
		TextSize = Layout.MIN_TEXT,
		TextColor3 = Theme.Muted,
		Position = UDim2.fromOffset(0, S.replyY),
		Size = UDim2.new(1, 0, 0, S.replyH),
		Parent = content,
	})

	local list = Widgets.scrollList({
		Name = "List",
		Position = UDim2.fromOffset(0, S.listY),
		Size = UDim2.new(1, 0, 0, fullH - S.listY),
		Parent = content,
	}, 6)

	local self: any = { frame = panel.frame, close = panel.close }
	local tabRows = Admin.rows(ctx)
	local tab = "Me"
	local cheats = false
	local latest: any = {}
	local tabButtons: { [string]: any } = {}
	local built: { Instance } = {}

	local function showReply(ok: boolean, message: string?)
		reply.Text = message or (if ok then "Done." else "That didn't work.")
		reply.TextColor3 = if ok then Theme.Good else Theme.Bad
	end

	local function send(command: string, button: Button)
		local amount = if button.amount then button.amount(latest) else nil
		local function done(result: any)
			if type(result) == "table" then
				showReply(result.ok == true, result.message)
			end
		end
		if ctx.ask then
			ctx.ask("Admin", done, command, button.arg, amount)
		else
			ctx.send("Admin", command, button.arg, amount)
		end
	end

	local function buildRow(row: Row, order: number): Frame
		if row.head then
			local label = Widgets.label({
				Name = row.key,
				Text = row.head,
				TextSize = S.headSize,
				TextColor3 = Theme.Muted,
				LayoutOrder = order,
				Size = UDim2.new(1, 0, 0, S.headH),
				Parent = list,
			})
			return label :: any
		end
		local command = AdminCommands.get(row.command)
		local frame = Widgets.rowFrame({
			Name = row.key,
			LayoutOrder = order,
			Size = UDim2.new(1, 0, 0, S.rowH),
			Parent = list,
		})
		local locked = if command then AdminCommands.lockedReason(command, cheats) else "unknown command"
		local right = S.rowPad
		if locked then
			local well = Widgets.status({
				Name = "Locked",
				Text = locked,
				TextSize = S.lockSize,
				AnchorPoint = Vector2.new(1, 0.5),
				Position = UDim2.new(1, -S.rowPad, 0.5, 0),
				Size = UDim2.fromOffset(buttonWidth(locked) - 10, S.btnH),
				Parent = frame,
			})
			right += well.Size.X.Offset + S.btnGap
		else
			local buttons = row.buttons or {}
			for i = #buttons, 1, -1 do
				local spec = buttons[i]
				local w = buttonWidth(spec.text)
				local props = {
					Name = `Button{i}`,
					Text = spec.text,
					TextSize = S.btnSize,
					AnchorPoint = Vector2.new(1, 0.5),
					Position = UDim2.new(1, -right, 0.5, 0),
					Size = UDim2.fromOffset(w, S.btnH),
				}
				local onClick = function()
					send(row.command :: string, spec)
				end
				local btn = if spec.hold
					then Widgets.holdButton(props, spec.color or Theme.Accent, onClick, ctx.Config.HOLD_CONFIRM_SECONDS)
					else Widgets.button(props, spec.color or Theme.Accent, onClick)
				btn.instance.Parent = frame
				right += w + S.btnGap
			end
		end
		Widgets.label({
			Name = "Name",
			Text = row.label or (if command then command.label else row.key),
			TextSize = S.nameSize,
			TextColor3 = row.color or Theme.Text,
			TextTruncate = Enum.TextTruncate.AtEnd,
			Position = UDim2.fromOffset(S.rowPad + 4, 0),
			Size = UDim2.new(1, -(S.rowPad + 4 + right), 1, 0),
			Parent = frame,
		})
		return frame
	end

	local function rebuild()
		for _, inst in built do
			inst:Destroy()
		end
		table.clear(built)
		local rows: { Row } = tabRows[tab] or {}
		for i, row in rows do
			table.insert(built, buildRow(row, i))
		end
		Widgets.restack(list)
		list.CanvasPosition = Vector2.zero
	end

	local function selectTab(name: string)
		if tabButtons[name] == nil or tab == name then
			return
		end
		tab = name
		for key, b in tabButtons do
			b.setColor(if key == tab then Theme.Accent else Theme.Row)
		end
		rebuild()
	end

	-- Equal tabs across the body width `w`, `tabGap` apart; the last one takes the rounding remainder.
	local function placeTabs(w: number)
		local n = #AdminCommands.TABS
		local tabW = math.floor((w - S.tabGap * (n - 1)) / n)
		for i, name in AdminCommands.TABS do
			local b = tabButtons[name].instance
			local x = (i - 1) * (tabW + S.tabGap)
			b.Position = UDim2.fromOffset(x, 0)
			b.Size = UDim2.fromOffset(if i == n then w - x else tabW, S.tabH)
		end
	end

	for _, name in AdminCommands.TABS do
		local btn = Widgets.button(
			{
				Name = `Tab{name}`,
				Text = name,
				TextSize = S.tabSize,
			},
			Theme.Row,
			function()
				selectTab(name)
			end
		)
		btn.instance.Parent = content
		tabButtons[name] = btn
	end
	placeTabs(Layout.MENU_WIDTH - c.pad * 2)
	tabButtons[tab].setColor(Theme.Accent)
	rebuild()

	function self.update(state: any)
		latest = state
		local view = state.admin
		local nowCheats = type(view) == "table" and view.cheats == true
		mode.Text = if nowCheats then Admin.COPY.cheatsOn else Admin.COPY.cheatsOff
		mode.TextColor3 = if nowCheats then Theme.Good else Theme.Warn
		if nowCheats ~= cheats then
			cheats = nowCheats
			rebuild()
		end
	end

	function self.layout(r: Layout.Rect)
		local body = Layout.panelBody(r)
		placeTabs(math.floor(body.w))
		Widgets.place(
			list,
			UDim2.fromOffset(0, S.listY),
			UDim2.new(1, 0, 0, math.max(S.rowH, math.floor(body.h) - S.listY))
		)
	end

	-- The open tab (tests), and switching to one.
	function self.tab(): string
		return tab
	end
	function self.showTab(name: string)
		selectTab(name)
	end

	return self
end

return Admin
