--!strict
--[[
	World shop panel (CONTRACT.md §27): the card of ONE in-world shop, "Item Shop" or
	"Upgrade Shop". The server opens it at the stand's ShopPrompt (ShopEvent Open / attribute OpenShop);
	init.client calls setShop(shopId) and shows the card like every other menu (setOpen("WorldShop"), X,
	backdrop, Esc / B). Rows come from WorldShopLogic.rows (Shared.Shops + the live State); a Buy hold calls
	Request("ShopBuy", shopId, itemId).

	Both shops wear the shared panel purple; the title, the corner icon and the tagline chip tell them apart.
	A row is the icon tile (a gold stock tag under it for restocking items), the name, a two-line description,
	level pips for leveled upgrades, and on the right WorldShopLogic.slot: the green hold-to-buy button, a
	sunken status well ("✅ Owned", "🔒 Rebirth 12 / to unlock") or the gold MAX stamp.
]]

local UI = script.Parent.Parent
local Format = require(UI.Format)
local ItemIconView = require(UI.ItemIconView)
local ItemIcons = require(UI.ItemIcons)
local Layout = require(UI.Layout)
local ShopCatalog = require(UI.ShopCatalog)
local Widgets = require(UI.Widgets)
local WorldShopLogic = require(UI.WorldShopLogic)

local Theme = Widgets.Theme
local KIT = Widgets.KIT
local create = Widgets.create

local WorldShop = {}

-- Row geometry (design px). BADGE / BUY_W / DESC_H and the text sizes match LayoutAssert.worldShopTexts.
WorldShop.ROW = 68
WorldShop.ROW_LEVELS = 80 -- a leveled upgrade: the pips sit under the two description lines
WorldShop.BADGE = 48
WorldShop.BUY_W = 170 -- fits "Need $987.6Qa more"; narrower than Layout.ROW_SLOT so a phone row keeps room for two lines of text
WorldShop.TOP_H = 32 -- the cash / tagline chips over the list
WorldShop.NAME_H = 22
WorldShop.DESC_H = 34
WorldShop.EDGE = 8 -- row edge to the icon and to the right slot
WorldShop.GAP = 10 -- icon to text, text to the right slot

WorldShop.SIZE = table.freeze({
	desc = Layout.MIN_TEXT,
	buy = 16,
	chipH = 26,
	softChip = Layout.MIN_TEXT, -- the muted tagline / restock chip
	tag = Layout.MIN_TEXT, -- the gold stock tag under the icon
	tagH = 18,
	tagPad = 6,
	pipH = 6,
	pipGap = 4,
	pipInset = 7, -- pips' bottom above the row's bottom
	status = 15,
	statusSub = Layout.MIN_TEXT, -- "to unlock" under a locked well's main line
	statusPad = 10, -- each side of a status well's widest line
	stamp = Layout.MIN_TEXT,
	stampH = 24,
	stampPad = 8,
	stampRadius = 8,
})

-- Per shop: the corner icon; the title and tagline come from WorldShopLogic.
WorldShop.ICON = table.freeze({
	ItemShop = "🛒",
	UpgradeShop = "⬆️",
})

local SIZE = WorldShop.SIZE

-- Width (design px) of a status well: at least the Buy button, wider when its text needs it ("Rebirth 120").
function WorldShop.statusWidth(slot: WorldShopLogic.Slot): number
	local w = Layout.lineWidth(slot.text, SIZE.status, true)
	if slot.sub then
		w = math.max(w, Layout.lineWidth(slot.sub, SIZE.statusSub))
	end
	return math.max(WorldShop.BUY_W, math.ceil(w) + SIZE.statusPad * 2)
end

-- The status well's text: one line, or the main line over a small body-font line.
function WorldShop.statusText(slot: WorldShopLogic.Slot): string
	if slot.sub then
		return `{slot.text}\n<font family="{Theme.FontBody.Family}" weight="bold" size="{SIZE.statusSub}">{slot.sub}</font>`
	end
	return slot.text
end

-- A small bright tag with ink text and outline (stock tag, MAX stamp), sized to its text.
function WorldShop.tag(props: { [string]: any }, size: number, height: number, pad: number, radius: number): TextLabel
	local base = {
		Font = Theme.Font,
		TextSize = size,
		TextColor3 = Theme.Ink,
		TextXAlignment = Enum.TextXAlignment.Center,
		TextTruncate = Enum.TextTruncate.None,
		BackgroundTransparency = 0,
		BackgroundColor3 = Theme.Gold,
		Size = UDim2.fromOffset(math.ceil(Layout.lineWidth(props.Text or "", size, true)) + pad * 2, height),
	}
	for k, v in props do
		base[k] = v
	end
	local label = Widgets.label(base)
	Widgets.corner(radius).Parent = label
	Widgets.stroke(Theme.Ink, KIT.rowStroke).Parent = label
	return label
end

-- One pip per level, filled gold up to `level`, placed by scale so they lay out while the card is hidden.
local function setPips(holder: Frame, level: number, maxLevel: number)
	local n = math.max(maxLevel, 0)
	if #holder:GetChildren() ~= n then
		holder:ClearAllChildren()
		for i = 1, n do
			create("Frame", {
				Name = `Pip{i}`,
				BorderSizePixel = 0,
				BackgroundColor3 = Theme.Ink,
				Position = UDim2.new((i - 1) / n, math.round((i - 1) * SIZE.pipGap / n), 0, 0),
				Size = UDim2.new(1 / n, -math.round(SIZE.pipGap * (n - 1) / n), 1, 0),
				Parent = holder,
			}, { create("UICorner", { CornerRadius = UDim.new(1, 0) }) })
		end
	end
	for i = 1, n do
		local pip = holder:FindFirstChild(`Pip{i}`) :: Frame?
		if pip then
			pip.BackgroundColor3 = if i <= level then Theme.Gold else Theme.Ink
			pip:SetAttribute("On", i <= level)
		end
	end
end

function WorldShop.new(parent: Instance, ctx: any)
	local panel = Widgets.panel(parent, "WorldShopPanel", "Shop", WorldShop.ICON.ItemShop)

	local cash = Widgets.chip({
		Name = "Cash",
		Size = UDim2.fromOffset(0, SIZE.chipH),
		Parent = panel.body,
	}, Theme.Gold)

	local function softChip(name: string, visible: boolean): TextLabel
		return Widgets.chip({
			Name = name,
			FontFace = Theme.FontBody,
			TextSize = SIZE.softChip,
			BackgroundColor3 = Theme.Row,
			AnchorPoint = Vector2.new(1, 0),
			Position = UDim2.fromScale(1, 0),
			Size = UDim2.fromOffset(0, SIZE.chipH),
			Visible = visible,
			Parent = panel.body,
		}, Theme.Muted)
	end
	-- Consumables restock countdown (Item Shop, FEATURES.Consumables); takes the tagline's spot while it shows.
	local restock = softChip("RestockTimer", false)
	-- What kind of shop this is.
	local tagline = softChip("Tagline", true)

	local list = Widgets.scrollList({
		Name = "List",
		Position = UDim2.fromOffset(0, WorldShop.TOP_H),
		Size = UDim2.new(1, 0, 1, -WorldShop.TOP_H),
		Parent = panel.body,
	}, 6)

	local textX = WorldShop.EDGE + WorldShop.BADGE + WorldShop.GAP
	local function textWidth(slotW: number): UDim
		return UDim.new(1, -(textX + slotW + WorldShop.EDGE + WorldShop.GAP))
	end

	local shopId: string? = nil
	local isOpen = false
	local icons: { [string]: any } = {}
	local rows = Widgets.keyedList(list, function(view: WorldShopLogic.Row)
		return `{view.shopId}_{view.id}`
	end, function(view: WorldShopLogic.Row)
		local leveled = view.maxLevel ~= nil
		local frame = Widgets.rowFrame({
			Name = view.id,
			Size = UDim2.new(1, -10, 0, if leveled then WorldShop.ROW_LEVELS else WorldShop.ROW),
		})
		local icon = ItemIconView.new({
			Name = "Icon",
			Id = view.icon,
			AnchorPoint = Vector2.new(0, 0.5),
			Position = UDim2.new(0, WorldShop.EDGE, 0.5, 0),
			Size = WorldShop.BADGE,
			Parent = frame,
		}, ItemIcons.of(ctx))
		icon.setActive(isOpen)
		icons[view.id] = icon
		-- Stock tag hanging off the icon's bottom edge, drawn over the tile.
		local stock = WorldShop.tag({
			Name = "Stock",
			Text = "",
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.new(0, WorldShop.EDGE + WorldShop.BADGE / 2, 0.5, WorldShop.BADGE / 2),
			ZIndex = icon.instance.ZIndex + 1,
			Visible = false,
			Parent = frame,
		}, SIZE.tag, SIZE.tagH, SIZE.tagPad, SIZE.tagH)
		local name = Widgets.label({
			Name = "ItemName",
			Font = Theme.Font,
			TextSize = WorldShopLogic.nameSize(view.name),
			Text = view.name,
			Size = UDim2.new(textWidth(WorldShop.BUY_W), UDim.new(0, WorldShop.NAME_H)),
			Position = UDim2.fromOffset(textX, 6),
			Parent = frame,
		})
		local desc = Widgets.label({
			Name = "Description",
			FontFace = Theme.FontBody,
			TextSize = SIZE.desc,
			TextColor3 = Theme.Muted,
			TextWrapped = true,
			TextTruncate = Enum.TextTruncate.None,
			TextYAlignment = Enum.TextYAlignment.Top,
			Size = UDim2.new(textWidth(WorldShop.BUY_W), UDim.new(0, WorldShop.DESC_H)), -- two lines on a phone
			Position = UDim2.fromOffset(textX, 6 + WorldShop.NAME_H + 2),
			Parent = frame,
		})
		local pips = if leveled
			then create("Frame", {
				Name = "Levels",
				BackgroundTransparency = 1,
				Position = UDim2.new(0, textX, 1, -(SIZE.pipH + SIZE.pipInset)),
				Size = UDim2.new(textWidth(WorldShop.BUY_W), UDim.new(0, SIZE.pipH)),
				Parent = frame,
			}) :: Frame
			else nil
		local current = view
		local buy = Widgets.holdButton(
			{
				Name = "Buy",
				AnchorPoint = Vector2.new(1, 0.5),
				Position = UDim2.new(1, -WorldShop.EDGE, 0.5, 0),
				Size = UDim2.fromOffset(WorldShop.BUY_W, Layout.BUTTON),
				TextSize = SIZE.buy,
			},
			Theme.Good,
			function()
				if current.enabled then
					ctx.send("ShopBuy", table.unpack(WorldShopLogic.buyArgs(current), 1, 2))
				end
			end,
			ctx.Config.HOLD_CONFIRM_SECONDS
		)
		buy.instance.Parent = frame
		local status = Widgets.status({
			AnchorPoint = Vector2.new(1, 0.5),
			Position = UDim2.new(1, -WorldShop.EDGE, 0.5, 0),
			Size = UDim2.fromOffset(WorldShop.BUY_W, Layout.BUTTON),
			TextSize = SIZE.status,
			TextWrapped = false,
			RichText = true,
			Visible = false,
			Parent = frame,
		})
		local stamp = WorldShop.tag({
			Name = "MaxStamp",
			Text = "Max",
			AnchorPoint = Vector2.new(1, 0.5),
			Position = UDim2.new(1, -WorldShop.EDGE, 0.5, 0),
			Visible = false,
			Parent = frame,
		}, SIZE.stamp, SIZE.stampH, SIZE.stampPad, SIZE.stampRadius)
		return {
			instance = frame,
			icon = icon,
			stock = stock,
			name = name,
			desc = desc,
			pips = pips,
			buy = buy,
			status = status,
			stamp = stamp,
			setView = function(v: WorldShopLogic.Row)
				current = v
			end,
		}
	end, function(row: any, view: WorldShopLogic.Row)
		row.setView(view)
		row.name.Text = view.name
		row.name.TextSize = WorldShopLogic.nameSize(view.name)
		row.desc.Text = view.description
		row.stock.Text = view.stockText or ""
		row.stock.Size =
			UDim2.fromOffset(math.ceil(Layout.lineWidth(row.stock.Text, SIZE.tag, true)) + SIZE.tagPad * 2, SIZE.tagH)
		row.stock.Visible = view.stockText ~= nil
		if row.pips then
			setPips(row.pips, view.level or 0, view.maxLevel or 0)
		end
		-- The one upgrade you can buy now stands out.
		row.instance.BackgroundColor3 = if row.pips
				and view.status == "buy"
				and view.enabled
			then Theme.BgLight
			else Theme.Row
		-- Icon frame: gold when maxed / owned, green when you can buy it.
		local done = view.status == "maxed" or view.status == "owned"
		row.icon.setFrame(if done then Theme.Gold elseif view.enabled then Theme.Good else nil)

		local slot = WorldShopLogic.slot(view)
		local slotW = WorldShop.BUY_W
		row.buy.instance.Visible = slot.kind == "buy"
		row.buy.setText(view.buttonText)
		row.buy.setEnabled(slot.kind == "buy" and view.enabled)
		row.stamp.Visible = slot.kind == "stamp"
		row.status.Visible = slot.kind == "status"
		if slot.kind == "status" then
			slotW = WorldShop.statusWidth(slot)
			row.status.Text = WorldShop.statusText(slot)
			row.status.TextColor3 = if slot.good then Theme.Good else Theme.Muted
			row.status.Size = UDim2.fromOffset(slotW, Layout.BUTTON)
		end
		local w = textWidth(slotW)
		row.name.Size = UDim2.new(w, UDim.new(0, WorldShop.NAME_H))
		row.desc.Size = UDim2.new(w, UDim.new(0, WorldShop.DESC_H))
		if row.pips then
			row.pips.Size = UDim2.new(w, UDim.new(0, SIZE.pipH))
		end
	end)

	local self = { frame = panel.frame, close = panel.close }

	-- The restock countdown follows the server clock; init.client's 10 Hz tick drives it while the card is open.
	local restockAt = nil :: number?
	local function showRestock()
		if restockAt then
			restock.Text = ShopCatalog.restockText(restockAt, ctx.serverNow())
		end
	end

	local lastState: any = nil
	local function refresh()
		local id = shopId
		if id == nil or lastState == nil then
			return
		end
		local state = lastState
		restockAt = WorldShopLogic.restockAt(id, state, ctx.Config.FEATURES)
		restock.Visible = restockAt ~= nil
		tagline.Visible = restockAt == nil
		showRestock()
		cash.Text = Format.formatCash(if type(state.cash) == "number" then state.cash else 0)
		rows.sync(WorldShopLogic.rows(id, state, ctx.actions, ctx.Config.FEATURES, ctx.Config))
	end

	-- Which shop the card shows (title, corner icon, tagline, rows). Called before the card opens.
	function self.setShop(id: string)
		shopId = id
		panel.title.Text = WorldShopLogic.title(id)
		panel.icon.Text = (WorldShop.ICON :: any)[id] or WorldShop.ICON.ItemShop
		tagline.Text = WorldShopLogic.tagline(id)
		refresh()
	end

	function self.shop(): string?
		return shopId
	end

	-- Model icons only render while the shop is open.
	function self.setOpen(open: boolean)
		isOpen = open
		for _, icon in icons do
			icon.setActive(open)
		end
		-- Hidden by anything (X, backdrop, Esc / B, another menu): the server still has the shop open.
		if not open and ctx.worldShop then
			ctx.worldShop.onHidden()
		end
	end

	function self.tick()
		if isOpen then
			showRestock()
		end
	end

	function self.update(state: any)
		lastState = state
		refresh()
	end

	return self
end

return WorldShop
