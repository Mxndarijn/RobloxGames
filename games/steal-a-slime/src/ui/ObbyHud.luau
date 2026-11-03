--!strict
--[[
	ObbyHud (UI module, contract/obby.md)

	The Obby on this player's screen, from State.obby:
	  * a run card at the top of the screen while a run is on (Layout.OBBY_CARD, under the banner stack):
	      - "Section x/6": the section the runner is over now (run.at), "Start" on the start pad, "Finish" on the
	        finish pad, and the run clock (0:00.0 until they leave the start pad: run.startedAt)
	      - one pip per section, from where they are now: behind them (a check), the one they are on (a mint ring
	        on a light fill), the furthest reached this run when a fall put them behind it (a mint ring on the dark
	        well), still to come (an Ink well)
	      - the base lock's time left (State.lockUntil) with a note that it runs slower meanwhile (run.lockRate);
	        "Base open" when no lock runs. The server pushes lockUntil out every obby tick but sends it only now and
	        then, so the card counts down at lockRate from the last value it saw (`lockLeft`)
	  * the portal sign's two lines (workspace.Obby.Portal, server/ObbyView), filled locally for this player: their
	    boost status ("Step in: x1.5 income!", "Boost 3:12", "Boost ready in 1:40"; "Cleared! Next course soon" once
	    they cleared this course, which the portal then refuses) and when the course changes
	The boost itself shows in the HUD's status row (HudClusters.obby). Text comes from the pure functions below
	(tested in tests/ui/ObbyHud.spec); `new` only draws them.
]]

local Shared = if script then (game:GetService("ReplicatedStorage") :: any).Shared else nil
local Constants = if Shared then require(Shared.Constants) else require("../shared/Constants")
local Format = if script then require(script.Parent.Format) else require("./Format")
local Layout = if script then require(script.Parent.Layout) else require("./Layout")
-- Drawing only runs in Roblox (the specs use the pure functions).
local Widgets: any = if script then require(script.Parent.Widgets) else nil

export type Run = { section: number, at: number?, of: number, startedAt: number?, lockRate: number? }

export type View = {
	bonus: number,
	endsAt: number?,
	readyAt: number?,
	sections: { string },
	rotatesAt: number,
	run: Run?,
	best: number?, -- set = cleared this course
}

export type Pip = "done" | "here" | "best" | "ahead"

local ObbyHud = {}

-- A rise of the lock countdown smaller than this (seconds) between two ticks is the client's estimate catching up
-- with a fresh lockUntil, not a new lock: the card keeps the lower time, so it never steps back up.
ObbyHud.LOCK_JITTER = 2

local function clock(seconds: number): string
	local s = math.max(0, math.ceil(seconds))
	return string.format("%d:%02d", s // 60, s % 60)
end

local function valid(view: any): boolean
	return type(view) == "table" and type(view.bonus) == "number" and type(view.rotatesAt) == "number"
end

local function runOf(view: View?): Run?
	if not valid(view) then
		return nil
	end
	return (view :: View).run
end

-- The sign's status line for this player.
function ObbyHud.statusText(view: View?, now: number): string
	if not valid(view) then
		return "Step in to start!"
	end
	local v = view :: View
	local mult = Format.formatMultiplier(1 + v.bonus)
	if v.best then
		return "Cleared! Next course soon" -- the portal waits for the next course (the line below says when)
	elseif v.endsAt and v.endsAt > now then
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

-- The section the runner is over now (0 = the start pad, of + 1 = the finish pad).
local function hereOf(run: Run): number
	local at = if type(run.at) == "number" then run.at else run.section
	return math.clamp(at, 0, run.of + 1)
end

-- The run card's head row while a run is on: the section the runner is over now and the run clock (standing still at
-- 0:00.0 until they leave the start pad); nil when not running.
function ObbyHud.runText(view: View?, now: number): (string?, string?)
	local run = runOf(view)
	if not run then
		return nil, nil
	end
	local elapsed = if type(run.startedAt) == "number" then math.max(0, now - run.startedAt) else 0
	local at = hereOf(run)
	local title = if at <= 0 then "Start" elseif at > run.of then "Finish" else `Section {at}/{run.of}`
	local m = math.floor(elapsed / 60)
	return title, string.format("%d:%04.1f", m, elapsed - m * 60)
end

-- One pip per section of the run, from where the runner is now: behind them, the one they are on, the furthest they
-- reached this run (when a fall put them behind it), or still to come. Empty when not running.
function ObbyHud.pips(view: View?): { Pip }
	local run = runOf(view)
	local out: { Pip } = {}
	if not run then
		return out
	end
	local at = hereOf(run)
	local furthest = math.clamp(math.max(run.section, at), 0, run.of + 1)
	for i = 1, run.of do
		local kind: Pip = if i < at then "done" elseif i == at then "here" elseif i == furthest then "best" else "ahead"
		table.insert(out, kind)
	end
	return out
end

-- How fast the run's base lock counts down (lock seconds per real second), held within 0..1.
function ObbyHud.lockRate(view: View?): number
	local run = runOf(view)
	local rate = if run then run.lockRate else nil
	if type(rate) ~= "number" or rate ~= rate then
		return 1
	end
	return math.clamp(rate, 0, 1)
end

--[[
	Lock seconds left at `now`: the lock ended at `lockUntil` as last seen at `seenAt`, counting down at `rate` since.
	`prev` = the time shown last tick: a rise under LOCK_JITTER keeps it, so the countdown only goes down. 0 = no lock.
]]
function ObbyHud.lockLeft(lockUntil: number?, seenAt: number, now: number, rate: number, prev: number?): number
	if type(lockUntil) ~= "number" or lockUntil <= seenAt then
		return 0
	end
	local left = math.max(0, (lockUntil - seenAt) - rate * math.max(0, now - seenAt))
	if prev and left > prev and left - prev < ObbyHud.LOCK_JITTER then
		return prev
	end
	return left
end

-- The card's lock row: the time chip and the note chip (nil = no note: no lock, or the lock runs at full speed).
function ObbyHud.lockText(left: number, rate: number): (string, string?)
	if left <= 0 then
		return "🔓 Base open", nil
	end
	local slower = math.floor((1 - rate) * 100 + 0.5)
	return `🔒 {clock(left)}`, if slower > 0 then `{slower}% slower` else nil
end

function ObbyHud.new(gui: Instance)
	local Theme = Widgets.Theme
	local C = Layout.OBBY_CARD
	local Z = Layout.ZINDEX.Banners

	-- The run card is built on the first run (most players never open the obby: no idle UI cost).
	type Card = {
		frame: Frame,
		title: TextLabel,
		clock: TextLabel,
		pipRow: Frame,
		pips: { TextLabel },
		lockChip: TextLabel,
		noteChip: TextLabel,
	}
	local cardParts: Card? = nil
	local box = { x = 0, y = 0, w = C.w }
	local heightOfBanners: () -> number = function()
		return 0
	end

	local function holder(name: string, y: number, h: number, parent: Instance): Frame
		return Widgets.create("Frame", {
			Name = name,
			BackgroundTransparency = 1,
			Position = UDim2.fromOffset(C.pad, y),
			Size = UDim2.new(1, -C.pad * 2, 0, h),
			ZIndex = Z,
			Parent = parent,
		})
	end

	local function makeCard(): Card
		local card = Widgets.create("Frame", {
			Name = "ObbyRunCard",
			Position = UDim2.fromOffset(box.x, box.y),
			Size = UDim2.fromOffset(box.w, Layout.obbyCardHeight()),
			BackgroundColor3 = Theme.Bg,
			BackgroundTransparency = C.transparency,
			ZIndex = Z,
		}, { Widgets.corner(C.corner), Widgets.stroke(Theme.Ink, C.stroke) })
		local head = holder("Head", C.pad, C.headH, card)
		local function headLabel(name: string, size: number, color: Color3, align: Enum.TextXAlignment): TextLabel
			return Widgets.label({
				Name = name,
				Font = Theme.Font,
				TextSize = size,
				TextColor3 = color,
				TextXAlignment = align,
				Size = UDim2.fromScale(1, 1),
				ZIndex = Z,
				Text = "",
				Parent = head,
			})
		end
		local pipRow = holder("Pips", C.pad + C.headH + C.gap, C.pip, card)
		Widgets.list(Enum.FillDirection.Horizontal, C.pipGap, Enum.HorizontalAlignment.Center).Parent = pipRow
		local lockRow = holder("Lock", C.pad + C.headH + C.gap + C.pip + C.gap, C.lockH, card)
		Widgets.list(Enum.FillDirection.Horizontal, C.gap, Enum.HorizontalAlignment.Center).Parent = lockRow
		local made = {
			frame = card,
			title = headLabel("Title", C.titleSize, Theme.Text, Enum.TextXAlignment.Left),
			clock = headLabel("Clock", C.clockSize, Theme.Muted, Enum.TextXAlignment.Right),
			pipRow = pipRow,
			pips = {},
			lockChip = Widgets.chip({
				Name = "LockTime",
				TextSize = C.lockSize,
				Size = UDim2.fromOffset(0, C.lockH),
				LayoutOrder = 1,
				ZIndex = Z,
				Parent = lockRow,
			}, Theme.Warn),
			noteChip = Widgets.chip({
				Name = "LockNote",
				TextSize = C.noteSize,
				Size = UDim2.fromOffset(0, C.lockH),
				LayoutOrder = 2,
				ZIndex = Z,
				Parent = lockRow,
			}, Theme.Muted),
		}
		card.Parent = gui
		return made
	end

	-- One Ink well per section; rebuilt only when the course length changes.
	local function setPipCount(card: Card, count: number)
		if #card.pips == count then
			return
		end
		for _, pip in card.pips do
			pip:Destroy()
		end
		table.clear(card.pips)
		for i = 1, count do
			table.insert(
				card.pips,
				Widgets.status({
					Name = `Pip{i}`,
					Text = tostring(i),
					TextSize = C.pipText,
					TextWrapped = false,
					Size = UDim2.fromOffset(C.pip, C.pip),
					LayoutOrder = i,
					ZIndex = Z,
					Parent = card.pipRow,
				})
			)
		end
	end

	local function paintPip(pip: TextLabel, i: number, kind: Pip)
		local stroke = pip:FindFirstChildOfClass("UIStroke") :: UIStroke
		local here = kind == "here"
		pip.BackgroundColor3 = if here then Theme.BgLight else Theme.Ink
		pip.TextColor3 = if here then Theme.Text else Theme.Muted
		pip.Text = if kind == "done" then "" else tostring(i)
		-- the furthest reached keeps the mint ring on its dark well; the one the runner is on also gets a light fill
		stroke.Color = if here or kind == "best" then Theme.Accent else Theme.Ink
		stroke.Thickness = if here then C.ring else Widgets.KIT.stroke
		Widgets.showCheck(pip, kind == "done", C.pip, { ZIndex = Z })
	end

	local current: View? = nil
	local lockUntil: number? = nil
	-- The lock end time the card counts from, when it first saw it, and the time it showed last tick.
	local lockSeen: { untilAt: number?, at: number } = { untilAt = nil, at = 0 }
	local lockShown: number? = nil
	-- The portal sign's labels, one of each per face.
	local signStatus: { TextLabel } = {}
	local signCourse: { TextLabel } = {}

	local function findSign()
		if signStatus[1] and signStatus[1].Parent then
			return
		end
		table.clear(signStatus)
		table.clear(signCourse)
		local folder = workspace:FindFirstChild(Constants.OBBY_FOLDER)
		local portal = folder and folder:FindFirstChild(Constants.OBBY_PORTAL)
		for _, inst in if portal then portal:GetDescendants() else {} do
			if inst:IsA("TextLabel") then
				if inst.Name == Constants.OBBY_SIGN_STATUS then
					table.insert(signStatus, inst)
				elseif inst.Name == Constants.OBBY_SIGN_COURSE then
					table.insert(signCourse, inst)
				end
			end
		end
	end

	local function drawCard(card: Card, view: View, title: string, clockText: string?, now: number)
		card.title.Text = title
		card.clock.Text = clockText or ""
		local kinds = ObbyHud.pips(view)
		setPipCount(card, #kinds)
		for i, kind in kinds do
			paintPip(card.pips[i], i, kind :: Pip)
		end
		if lockUntil ~= lockSeen.untilAt then
			lockSeen.untilAt = lockUntil
			lockSeen.at = now
		end
		local rate = ObbyHud.lockRate(view)
		local left = ObbyHud.lockLeft(lockSeen.untilAt, lockSeen.at, now, rate, lockShown)
		lockShown = left
		local time, note = ObbyHud.lockText(left, rate)
		card.lockChip.Text = time
		card.lockChip.TextColor3 = if left > 0 then Theme.Warn else Theme.Muted
		card.noteChip.Visible = note ~= nil
		card.noteChip.Text = note or ""
	end

	local self = {}

	-- The card's box: centred in the banner strip, under the banner stack (`bannerHeight`, design px).
	function self.layout(screen: Layout.Screen, bannerHeight: (() -> number)?)
		local r = Layout.obbyCard(screen)
		box.x, box.y, box.w = r.x, r.y, r.w
		heightOfBanners = bannerHeight or heightOfBanners
		if cardParts then
			cardParts.frame.Size = UDim2.fromOffset(box.w, Layout.obbyCardHeight())
		end
	end

	function self.update(state: any)
		current = if type(state) == "table" and valid(state.obby) then state.obby else nil
		local lock = if type(state) == "table" then state.lockUntil else nil
		lockUntil = if type(lock) == "number" then lock else nil
	end

	function self.tick(now: number)
		local head, clockText = ObbyHud.runText(current, now)
		if head and not cardParts then
			cardParts = makeCard()
		end
		if cardParts then
			local card = cardParts :: Card
			card.frame.Visible = head ~= nil
			if head then
				local banners = heightOfBanners()
				card.frame.Position = UDim2.fromOffset(box.x, box.y + (if banners > 0 then banners + Layout.GAP else 0))
				drawCard(card, current :: View, head, clockText, now)
			else
				lockShown = nil
			end
		end
		findSign()
		if signStatus[1] then
			local text = ObbyHud.statusText(current, now)
			for _, label in signStatus do
				if label.Text ~= text then
					label.Text = text
				end
			end
		end
		if signCourse[1] then
			local text = ObbyHud.courseText(current, now)
			for _, label in signCourse do
				if label.Text ~= text then
					label.Text = text
				end
			end
		end
	end

	return self
end

return ObbyHud
