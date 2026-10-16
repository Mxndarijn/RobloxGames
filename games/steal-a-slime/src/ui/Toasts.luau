--!strict
--[[
	Toasts: stacked messages from the `Notify` RemoteEvent (and failed
	Request messages). Kinds info / good / bad, plus the UI's own "rare"
	(Boss Slime news: gold, bigger, stays longer) and "badge" (Roblox badge unlocked:
	gold star icon + text, stays longer); each hides after LIFETIME
	(per kind) s; at most MAX visible (oldest dropped).
]]

local SoundService = game:GetService("SoundService")
local TweenService = game:GetService("TweenService")

local Icons = require(script.Parent.Icons)
local Sounds = require(script.Parent.Sounds)
local Widgets = require(script.Parent.Widgets)

local Theme = Widgets.Theme
local create = Widgets.create

local MAX = 4
local LIFETIME = 3
local LIFETIMES = { rare = 7, badge = 6 }

local COLORS = {
	info = Theme.Info,
	good = Theme.Good,
	bad = Theme.Bad,
	rare = Theme.Gold,
	badge = Theme.Gold,
}

local Toasts = {}

function Toasts.new(parent: Instance)
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

	local active: { Frame } = {}
	local counter = 0

	local self = {}

	-- Box from Layout.screen().toasts (right edge, under the HUD).
	function self.layout(rect: { x: number, y: number, w: number, h: number })
		holder.Position = UDim2.fromOffset(rect.x + rect.w, rect.y)
		holder.Size = UDim2.fromOffset(rect.w, rect.h)
	end

	local function remove(frame: Frame)
		local index = table.find(active, frame)
		if index then
			table.remove(active, index)
		end
		frame:Destroy()
	end

	local function playSound(sound: string?)
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

	function self.push(text: string, kind: string?, sound: string?)
		counter += 1
		local color = COLORS[kind or "info"] or Theme.Info
		local frame = create("Frame", {
			Name = `Toast{counter}`,
			LayoutOrder = counter,
			Size = UDim2.fromScale(1, 0), -- holder width (Layout: narrower on phones)
			AutomaticSize = Enum.AutomaticSize.Y,
			BackgroundColor3 = Theme.Bg,
			BackgroundTransparency = 0.05,
			Parent = holder,
		}, { Widgets.corner(8), Widgets.stroke(color, if kind == "rare" then 3 else 2), Widgets.padding(8) })
		local isBadge = kind == "badge"
		local iconWidth = 0
		if isBadge then
			iconWidth = 40
			local icon = create("Frame", {
				Name = "BadgeIcon",
				Size = UDim2.fromOffset(32, 32),
				Position = UDim2.fromOffset(0, 0),
				BackgroundColor3 = color,
				Parent = frame,
			}, { Widgets.corner(16), Widgets.stroke(Color3.new(1, 1, 1), 2) })
			Widgets.label({
				Text = Icons.FAV_ON,
				TextColor3 = Color3.new(1, 1, 1),
				Font = Theme.Font,
				TextSize = 20,
				TextXAlignment = Enum.TextXAlignment.Center,
				Size = UDim2.fromScale(1, 1),
				Parent = icon,
			})
		end
		local label = Widgets.label({
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
		if isBadge then
			label.TextXAlignment = Enum.TextXAlignment.Left
			local name = string.gsub(label.Text, "^Badge unlocked: ", "")
			label.Text = `Badge unlocked!\n{name}`
			create("UISizeConstraint", { MinSize = Vector2.new(0, 32), Parent = label })
		end
		table.insert(active, frame)
		while #active > MAX do
			remove(active[1])
		end
		playSound(sound)

		task.delay(LIFETIMES[kind or "info"] or LIFETIME, function()
			if frame.Parent == nil then
				return
			end
			local info = TweenInfo.new(0.3)
			TweenService:Create(frame, info, { BackgroundTransparency = 1 }):Play()
			TweenService:Create(label, info, { TextTransparency = 1 }):Play()
			task.wait(0.3)
			remove(frame)
		end)
	end

	return self
end

return Toasts
