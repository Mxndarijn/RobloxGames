--!strict
--[[
	Toasts: stacked messages from the `Notify` RemoteEvent (and failed
	Request messages). Kinds info / good / bad, plus the UI's own "rare"
	(Boss Slime news: gold, bigger, stays longer), "away" (steal join notice: red, stays 9 s) and "badge" (Roblox badge unlocked:
	gold star icon + text, stays longer). What shows (merged bursts, priority,
	cap, staleness, hidden behind menus) is decided by ToastQueue.
]]

local SoundService = game:GetService("SoundService")

local ItemIconView = require(script.Parent.ItemIconView)
local ItemIcons = require(script.Parent.ItemIcons)
local Layout = require(script.Parent.Layout)
local SoundController = require(script.Parent.SoundController)
local Sounds = require(script.Parent.Sounds)
local ToastQueue = require(script.Parent.ToastQueue)
local Widgets = require(script.Parent.Widgets)

local Theme = Widgets.Theme
local create = Widgets.create

local MAX = ToastQueue.MAX

local COLORS = {
	info = Theme.Info,
	good = Theme.Good,
	bad = Theme.Bad,
	rare = Theme.Gold,
	badge = Theme.Gold,
	away = Theme.Bad, -- StealAlert join notice (FEATURES.StealAlerts): long text, stays longer
}

local Toasts = {}

Toasts.ICON = 36

-- Registry id of the badge named in "Badge unlocked: <name>" (the generic medal when unknown).
function Toasts.badgeId(registry: any, text: any): string
	local name = string.gsub(tostring(text), "^Badge unlocked: ", "")
	for _, id in registry.order do
		local spec = registry.byId[id]
		if spec.group == "badge" and spec.name == name then
			return id
		end
	end
	return "Badge_FirstSlime"
end

function Toasts.new(parent: Instance, registry: any, config: any?)
	local holder = create("Frame", {
		Name = "Toasts",
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.new(1, -12, 0, 90),
		Size = UDim2.fromOffset(320, 300),
		BackgroundTransparency = 1,
		Parent = parent,
	})
	local layout = Widgets.list(Enum.FillDirection.Vertical, 6, Enum.HorizontalAlignment.Right)
	layout.VerticalAlignment = Enum.VerticalAlignment.Top
	layout.Parent = holder

	local queue = ToastQueue.new(MAX)
	local frames: { [number]: Frame } = {}
	local menuOpen = false

	local self = {}

	-- Box from Layout.screen().toasts (right edge, under the HUD), moved below
	-- the HUD banner stack (`bannerHeight`) where the two share columns.
	local screen: Layout.Screen? = nil
	local bannerHeight: (() -> number)? = nil
	local function place()
		if screen then
			local rect = Layout.toastBox(screen, if bannerHeight then bannerHeight() else 0)
			holder.Position = UDim2.fromOffset(rect.x + rect.w, rect.y)
			holder.Size = UDim2.fromOffset(rect.w, rect.h)
		end
	end
	function self.layout(s: Layout.Screen, banners: (() -> number)?)
		screen, bannerHeight = s, banners
		place()
	end

	-- Height a toast takes (frame padding 8 + 8, text wrapped beside the icon, icon-high at least).
	local TOAST_GAP = 6
	local function toastHeight(entry: any): number
		local iconWidth = Toasts.ICON + 8
		local size = if entry.kind == "rare" then 20 else 16
		local textH = Layout.wrappedHeight(entry.text, size, holder.Size.X.Offset - 16 - iconWidth, true)
		return math.max(textH, Toasts.ICON) + 16
	end
	local fit: ToastQueue.Fit = {
		room = 0,
		gap = TOAST_GAP,
		height = toastHeight,
	}

	local function playSound(sound: string?)
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

	-- `entry.itemId`: the server's ItemIcons id for this toast; unknown / absent ids fall back to the text heuristic.
	local function build(entry: any): Frame
		local text, kind, itemId = entry.text, entry.kind, entry.itemId
		local color = COLORS[kind] or Theme.Info
		local frame = create("Frame", {
			Name = `Toast{entry.id}`,
			LayoutOrder = -entry.priority * 1000 + entry.id, -- steal alerts / rare above routine
			Size = UDim2.fromScale(1, 0), -- holder width (Layout: narrower on phones)
			AutomaticSize = Enum.AutomaticSize.Y,
			BackgroundColor3 = Theme.Bg,
			BackgroundTransparency = 0.05,
			Parent = holder,
		}, { Widgets.corner(8), Widgets.stroke(color, if kind == "rare" then 3 else 2), Widgets.padding(8) })
		local isBadge = kind == "badge"
		local iconWidth = 0
		-- Item icon: a badge toast shows its badge's medal, other toasts the item their text is about.
		local icon = if isBadge
			then Toasts.badgeId(registry, text)
			elseif type(itemId) == "string" and registry.byId[itemId] then itemId
			else ItemIcons.forToast(text, config)
		if icon then
			iconWidth = Toasts.ICON + 8
			ItemIconView.new({
				Name = if isBadge then "BadgeIcon" else "ItemIcon",
				Id = icon,
				Size = Toasts.ICON,
				Parent = frame,
			}, registry).setActive(true)
		end
		local label = Widgets.label({
			Name = "Text",
			Text = tostring(text),
			TextWrapped = true,
			TextTruncate = Enum.TextTruncate.None,
			TextColor3 = color:Lerp(Color3.new(1, 1, 1), 0.6),
			Font = Theme.Font,
			TextSize = if kind == "rare" then 20 else 16,
			Position = UDim2.fromOffset(iconWidth, 0),
			Size = UDim2.new(1, -iconWidth, 0, 0),
			AutomaticSize = Enum.AutomaticSize.Y,
			Parent = frame,
		})
		if icon then
			label.TextXAlignment = Enum.TextXAlignment.Left
			create("UISizeConstraint", { MinSize = Vector2.new(0, Toasts.ICON), Parent = label })
		end
		return frame
	end

	local function labelText(entry: any): string
		if entry.kind == "badge" then
			local name = string.gsub(entry.text, "^Badge unlocked: ", "")
			return `Badge unlocked!\n{name}`
		end
		return entry.text
	end

	-- Draw exactly the entries the queue says are visible.
	local function sync()
		place()
		fit.room = holder.Size.Y.Offset
		local visible = queue.step(os.clock(), menuOpen, fit)
		local live: { [number]: boolean } = {}
		for _, entry in visible do
			live[entry.id] = true
			local frame = frames[entry.id]
			if not frame then
				frame = build(entry)
				frames[entry.id] = frame
			end
			local label = frame:FindFirstChild("Text") :: TextLabel
			label.Text = labelText(entry)
		end
		for id, frame in frames do
			if not live[id] then
				frames[id] = nil
				frame:Destroy()
			end
		end
		holder.Visible = not menuOpen
	end

	function self.push(text: string, kind: string?, sound: string?, itemId: string?)
		local _, merged = queue.push(text, kind, os.clock(), itemId)
		if not merged then
			playSound(sound)
		end
		sync()
	end

	-- A menu open hides the stack (MenuState.bannersVisible); toasts wait, unaged.
	function self.setMenuOpen(open: boolean)
		menuOpen = open
		sync()
	end

	task.spawn(function()
		while holder.Parent do
			task.wait(0.25)
			sync()
		end
	end)

	return self
end

return Toasts
