--!strict
--[[
	ObbyHud (UI module, contract/obby.md)

	The Goo Gauntlet on this player's screen, from State.obby:
	  * a run card at the top of the screen while a run is on: the checkpoint reached and the run clock
	  * the portal sign's two lines (workspace.Obby.Portal, server/ObbyView), filled locally for this player: their
	    boost status ("Step in: x1.5 income!", "Boost 3:12", "Boost ready in 1:40") and when the course changes
	The boost itself shows in the HUD's status row (HudClusters.obby). Text comes from the pure functions below
	(tested in tests/ui/ObbyHud.spec); `new` only draws them.
]]

local Shared = if script then (game:GetService("ReplicatedStorage") :: any).Shared else nil
local Constants = if Shared then require(Shared.Constants) else require("../shared/Constants")
local Format = if script then require(script.Parent.Format) else require("./Format")
-- Drawing only runs in Roblox (the specs use the pure text functions).
local Layout = if script then require(script.Parent.Layout) else require("./Layout")
local Widgets: any = if script then require(script.Parent.Widgets) else nil

export type View = {
	bonus: number,
	endsAt: number?,
	readyAt: number?,
	sections: { string },
	rotatesAt: number,
	run: { reached: number, of: number, startedAt: number }?,
	best: number?,
}

local ObbyHud = {}

-- The run card: design px (the root ScreenGui's UIScale shrinks it on phones).
local CARD = table.freeze({
	width = 240,
	height = 52,
	top = 74, -- below the top bar and the banners' first row
	titleSize = 14,
	lineSize = 22,
	corner = 14,
	stroke = 2,
	transparency = 0.15,
})

local function clock(seconds: number): string
	local s = math.max(0, math.ceil(seconds))
	return string.format("%d:%02d", s // 60, s % 60)
end

local function valid(view: any): boolean
	return type(view) == "table" and type(view.bonus) == "number" and type(view.rotatesAt) == "number"
end

-- The sign's status line for this player.
function ObbyHud.statusText(view: View?, now: number): string
	if not valid(view) then
		return "Step in to start!"
	end
	local v = view :: View
	local mult = Format.formatMultiplier(1 + v.bonus)
	if v.endsAt and v.endsAt > now then
		return `{mult} income · {clock(v.endsAt - now)} left`
	elseif v.readyAt and v.readyAt > now then
		return `Boost ready in {clock(v.readyAt - now)}`
	end
	return `Step in: {mult} income!`
end

-- The sign's course line: when this course changes.
function ObbyHud.courseText(view: View?, now: number): string
	if not valid(view) then
		return "A new course every 10 min"
	end
	return `New course in {clock((view :: View).rotatesAt - now)}`
end

-- The run card's two lines while a run is on; nil when not running.
function ObbyHud.runText(view: View?, now: number): (string?, string?)
	if not valid(view) or (view :: View).run == nil then
		return nil, nil
	end
	local run = (view :: View).run :: { reached: number, of: number, startedAt: number }
	local elapsed = math.max(0, now - run.startedAt)
	local title = if run.reached <= 0 then "GOO GAUNTLET" else `CHECKPOINT {run.reached}/{run.of}`
	local m = math.floor(elapsed / 60)
	return title, string.format("%d:%04.1f", m, elapsed - m * 60)
end

function ObbyHud.new(gui: Instance)
	local Theme = Widgets.Theme

	-- The run card is built on the first run (most players never open the obby: no idle UI cost).
	type Card = { frame: Frame, title: TextLabel, line: TextLabel }
	local cardParts: Card? = nil
	local function makeCard(): Card
		local card = Instance.new("Frame")
		card.Name = "ObbyRunCard"
		card.AnchorPoint = Vector2.new(0.5, 0)
		card.Position = UDim2.new(0.5, 0, 0, CARD.top)
		card.Size = UDim2.fromOffset(CARD.width, CARD.height)
		card.BackgroundColor3 = Theme.Bg
		card.BackgroundTransparency = CARD.transparency
		card.ZIndex = Layout.ZINDEX.Banners
		local corner = Instance.new("UICorner")
		corner.CornerRadius = UDim.new(0, CARD.corner)
		corner.Parent = card
		local stroke = Instance.new("UIStroke")
		stroke.Color = Theme.Ink
		stroke.Thickness = CARD.stroke
		stroke.Parent = card
		local function label(name: string, y: number, h: number, size: number, color: Color3): TextLabel
			local l = Instance.new("TextLabel")
			l.Name = name
			l.BackgroundTransparency = 1
			l.Position = UDim2.fromScale(0, y)
			l.Size = UDim2.fromScale(1, h)
			l.Font = Theme.Font
			l.TextSize = size
			l.TextColor3 = color
			l.ZIndex = Layout.ZINDEX.Banners
			l.Text = ""
			l.Parent = card
			return l
		end
		local made = {
			frame = card,
			title = label("Title", 0.04, 0.38, CARD.titleSize, Theme.Accent),
			line = label("Clock", 0.4, 0.56, CARD.lineSize, Theme.Text),
		}
		card.Parent = gui
		return made
	end

	local current: View? = nil
	local signStatus: TextLabel? = nil
	local signCourse: TextLabel? = nil

	local function findSign()
		if signStatus and signStatus.Parent then
			return
		end
		local folder = workspace:FindFirstChild(Constants.OBBY_FOLDER)
		local portal = folder and folder:FindFirstChild(Constants.OBBY_PORTAL)
		local status = portal and portal:FindFirstChild(Constants.OBBY_SIGN_STATUS, true)
		local course = portal and portal:FindFirstChild(Constants.OBBY_SIGN_COURSE, true)
		signStatus = if status and status:IsA("TextLabel") then status else nil
		signCourse = if course and course:IsA("TextLabel") then course else nil
	end

	local self = {}

	function self.update(state: any)
		current = if type(state) == "table" and valid(state.obby) then state.obby else nil
	end

	function self.tick(now: number)
		local head, clockText = ObbyHud.runText(current, now)
		if head and not cardParts then
			cardParts = makeCard()
		end
		if cardParts then
			cardParts.frame.Visible = head ~= nil
			if head then
				cardParts.title.Text = head
				cardParts.line.Text = clockText or ""
			end
		end
		findSign()
		if signStatus then
			local text = ObbyHud.statusText(current, now)
			if signStatus.Text ~= text then
				signStatus.Text = text
			end
		end
		if signCourse then
			local text = ObbyHud.courseText(current, now)
			if signCourse.Text ~= text then
				signCourse.Text = text
			end
		end
	end

	return self
end

return ObbyHud
