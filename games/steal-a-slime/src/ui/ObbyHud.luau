--!strict
--[[
	ObbyHud (UI module, contract/obby.md)

	The Obby on this player's screen, from State.obby:
	  * a run card at the top of the screen while a run is on (Layout.OBBY_CARD, under the banner stack):
	      - "Section x/6": the section the runner is over now (run.at), "Start" on the start pad, "Finish" on the
	        finish pad, and this try's clock (0:00.0 until they leave the start pad: run.startedAt). The board counts
	        one try; a fall back to the start pad starts the next from zero
	      - a small line under the pips: the boost this run has earned so far in mint ("x1.3 income"; before the
	        first section, while the boost is ready: "+17% a section", `boostText`) and, once a fall started a new
	        try, "Total 2:14" in muted text: all tries since the first left the pad (run.firstAt, `totalText`)
	      - one pip per section, from where they are now: behind them (a check), the one they are on (a mint ring
	        on a light fill), the furthest reached this run when a fall put them behind it (a mint ring on the dark
	        well), still to come (an Ink well)
	      - "Best 0:51.4" and the rank chip "#23" once this player has a time on this course (`bestText`)
	      - the base lock's time left (State.lockUntil) with a note that it runs slower meanwhile (run.lockRate);
	        "Base open" when no lock runs. The server pushes lockUntil out every obby tick but sends it only now and
	        then, so the card counts down at lockRate from the last value it saw (`lockLeft`)
	  * the sign board's two lines (workspace.Obby.SignBoard, server/ObbyBoardView.buildSign), filled locally for this player: their
	    boost status ("Step in: up to x2 income!", "x1.5 income · 3:12 left", "Boost ready in 1:40") and the course with its time
	    left ("Course #1,204 · 12:34 left")
	  * the course board's own line (workspace.Obby.Board, server/ObbyBoardView): this player's row tinted when they
	    are in the top 10, else "You #23  0:51.4" under it (`boardYou`)
	The boost itself shows in the HUD's status row (HudClusters.obby). Text comes from the pure functions below
	(tested in tests/ui/ObbyHud.spec); `new` only draws them.
]]

local Shared = if script then (game:GetService("ReplicatedStorage") :: any).Shared else nil
local Config = if Shared then require(Shared.Config) else require("../shared/Config")
local Constants = if Shared then require(Shared.Constants) else require("../shared/Constants")
local ObbyRules = if Shared then require(Shared.ObbyRules) else require("../shared/ObbyRules")
local Format = if script then require(script.Parent.Format) else require("./Format")
local Layout = if script then require(script.Parent.Layout) else require("./Layout")
local Text = if script then require(script.Parent.Text) else require("./Text")
local WorldLeaderboard = if script then require(script.Parent.WorldLeaderboard) else require("./WorldLeaderboard")
-- Drawing only runs in Roblox (the specs use the pure functions).
local Widgets: any = if script then require(script.Parent.Widgets) else nil

export type Run = {
	section: number,
	at: number?,
	of: number,
	startedAt: number?,
	firstAt: number?,
	paid: number?, -- sections that added to the boost this run
	lockRate: number?,
}

export type View = {
	bonus: number,
	endsAt: number?,
	readyAt: number?,
	sections: { string },
	rotatesAt: number,
	run: Run?,
	best: number?, -- best counted finish on this course, seconds
	rank: number?, -- that best's rank on the course board (RANK_DEPTH + 1 = deeper)
	course: number?, -- the course number ("Course #1,204")
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
		return Text.t("hud.obby.step_in")
	end
	local v = view :: View
	local mult = Format.formatMultiplier(1 + v.bonus)
	if v.endsAt and v.endsAt > now then
		return Text.t("hud.obby.boost_left", { income = mult, time = clock(v.endsAt - now) })
	elseif v.readyAt and v.readyAt > now then
		return Text.t("hud.obby.boost_ready_in", { time = clock(v.readyAt - now) })
	end
	return Text.t("hud.obby.step_in_up_to", { income = mult })
end

-- The sign's course line: the course and its time left.
function ObbyHud.courseText(view: View?, now: number): string
	if not valid(view) then
		return Text.t("hud.obby.course_every", { minutes = math.floor(Config.OBBY.ROTATION_SECONDS / 60 + 0.5) })
	end
	local v = view :: View
	local left = clock(v.rotatesAt - now)
	if type(v.course) ~= "number" then
		return Text.t("hud.obby.new_course_in", { time = left })
	end
	-- ObbyRules.courseLabel writes "Course #1,204"; the number part goes into the sentence.
	local number = string.match(ObbyRules.courseLabel(v.course), "#(.+)$") or tostring(v.course)
	return Text.t("hud.obby.course_left", { course = number, time = left })
end

-- The run card's best row: "Best 0:51.4" and the rank chip ("#23", nil before the board has a rank); nil without a
-- time on this course.
function ObbyHud.bestText(view: View?): (string?, string?)
	if not valid(view) then
		return nil, nil
	end
	local v = view :: View
	if type(v.best) ~= "number" then
		return nil, nil
	end
	return Text.t("hud.obby.best", { time = ObbyRules.timeText(ObbyRules.tenths(v.best)) }), ObbyRules.rankText(v.rank)
end

--[[
	This player on the course board: `row` = their rank when they are one of the board's `size` rows (that row gets
	the viewer's tint), else `name` / `value` for the "You" line under it ("You #23", "0:51.4"); all nil without a time.
]]
function ObbyHud.boardYou(view: View?, size: number): { row: number?, name: string?, value: string? }
	if not valid(view) then
		return {}
	end
	local v = view :: View
	if type(v.best) ~= "number" then
		return {}
	end
	if type(v.rank) == "number" and v.rank >= 1 and v.rank <= size then
		return { row = v.rank }
	end
	local rank = ObbyRules.rankText(v.rank)
	return {
		name = if rank then Text.t("hud.obby.you_rank", { rank = rank }) else Text.t("hud.obby.you"),
		value = ObbyRules.timeText(ObbyRules.tenths(v.best)),
	}
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
	local title = if at <= 0
		then Text.t("hud.obby.start")
		elseif at > run.of then Text.t("hud.obby.finish")
		else Text.t("hud.obby.section", { at = at, of = run.of })
	local m = math.floor(elapsed / 60)
	return title, string.format("%d:%04.1f", m, elapsed - m * 60)
end

-- The run card's boost part: "x1.3 income" once this run cleared a section that added to the boost (one share per
-- section, a full clear = 1 + bonus), "+17% a section" while the boost is ready and none has yet; nil otherwise.
function ObbyHud.boostText(view: View?, now: number): string?
	local run = runOf(view)
	if not run or run.of < 1 then
		return nil
	end
	local v = view :: View
	local paid = if type(run.paid) == "number" then run.paid else 0
	if paid > 0 then
		-- while boosted, bonus = what this run earned
		return Text.t("hud.obby.income", { income = Format.formatMultiplier(1 + v.bonus) })
	elseif v.endsAt == nil and (v.readyAt == nil or v.readyAt <= now) then
		-- while ready, bonus = a full clear's
		return Text.t("hud.obby.per_section", { percent = `+{math.floor(v.bonus / run.of * 100 + 0.5)}%` })
	end
	return nil
end

-- The run card's total row: "Total 2:14", every try since the first left the start pad. Only once a fall started
-- a new try (before that it is the same as the clock); nil otherwise.
function ObbyHud.totalText(view: View?, now: number): string?
	local run = runOf(view)
	if not run or type(run.firstAt) ~= "number" or run.firstAt == run.startedAt then
		return nil
	end
	local s = math.max(0, math.floor(now - run.firstAt))
	return Text.t("hud.obby.total", { time = string.format("%d:%02d", s // 60, s % 60) })
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
		return "🔓 " .. Text.t("hud.obby.base_open"), nil
	end
	local slower = math.floor((1 - rate) * 100 + 0.5)
	return `🔒 {clock(left)}`, if slower > 0 then Text.t("hud.obby.slower_locks", { percent = `{slower}%` }) else nil
end

-- Whether the lock row needs two lines on a card `width` design px wide: true when the longest lock time and the
-- note ("🔒 m:ss" + "50% slower locks") don't fit side by side; then the note sits under the time.
function ObbyHud.lockSplit(width: number): boolean
	local C = Layout.OBBY_CARD
	local time, note = ObbyHud.lockText(Config.LOCK_MAX_SECONDS, Config.OBBY.LOCK_RATE)
	if not note then
		return false
	end
	local need = Layout.lineWidth(time, C.lockSize, true)
		+ Layout.lineWidth(note, C.noteSize, true)
		+ C.chipPad * 4
		+ C.gap
	return need > width - C.pad * 2
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
		extraRow: Frame,
		boostLabel: TextLabel,
		totalLabel: TextLabel,
		bestRow: Frame,
		bestLabel: TextLabel,
		rankChip: TextLabel,
		lockRow: Frame,
		lockList: UIListLayout,
		lockChip: TextLabel,
		noteChip: TextLabel,
	}
	local cardParts: Card? = nil
	local box = { x = 0, y = 0, w = C.w, split = false }
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
		local extraRow = holder("Extra", C.pad + C.headH + C.gap + C.pip + C.gap, C.extraH, card)
		Widgets.list(Enum.FillDirection.Horizontal, C.gap, Enum.HorizontalAlignment.Center).Parent = extraRow
		extraRow.Visible = false
		local function extraLabel(name: string, color: Color3, order: number): TextLabel
			return Widgets.label({
				Name = name,
				Font = Theme.Font,
				TextSize = C.extraSize,
				TextColor3 = color,
				AutomaticSize = Enum.AutomaticSize.X,
				Size = UDim2.fromOffset(0, C.extraH),
				LayoutOrder = order,
				Visible = false,
				ZIndex = Z,
				Text = "",
				Parent = extraRow,
			})
		end
		local boostLabel = extraLabel("BoostEarned", Theme.Accent, 1)
		local totalLabel = extraLabel("TotalTime", Theme.Muted, 2)
		local bestRow = holder("Best", C.pad + C.headH + C.gap + C.pip + C.gap, C.bestH, card)
		Widgets.list(Enum.FillDirection.Horizontal, C.gap, Enum.HorizontalAlignment.Center).Parent = bestRow
		bestRow.Visible = false
		local lockRow = holder("Lock", C.pad + C.headH + C.gap + C.pip + C.gap, C.lockH, card)
		local lockList = Widgets.list(Enum.FillDirection.Horizontal, C.gap, Enum.HorizontalAlignment.Center)
		lockList.Parent = lockRow
		local made = {
			frame = card,
			title = headLabel("Title", C.titleSize, Theme.Text, Enum.TextXAlignment.Left),
			clock = headLabel("Clock", C.clockSize, Theme.Muted, Enum.TextXAlignment.Right),
			pipRow = pipRow,
			pips = {},
			extraRow = extraRow,
			boostLabel = boostLabel,
			totalLabel = totalLabel,
			bestRow = bestRow,
			bestLabel = Widgets.label({
				Name = "BestTime",
				Font = Theme.Font,
				TextSize = C.bestSize,
				TextColor3 = Theme.Text,
				AutomaticSize = Enum.AutomaticSize.X,
				Size = UDim2.fromOffset(0, C.bestH),
				LayoutOrder = 1,
				ZIndex = Z,
				Text = "",
				Parent = bestRow,
			}),
			rankChip = Widgets.chip({
				Name = "BestRank",
				TextSize = C.bestSize,
				Size = UDim2.fromOffset(0, C.bestH),
				LayoutOrder = 2,
				ZIndex = Z,
				Parent = bestRow,
			}, Theme.Gold),
			lockRow = lockRow,
			lockList = lockList,
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
	-- The sign board's labels.
	local signStatus: { TextLabel } = {}
	local signCourse: { TextLabel } = {}
	-- The course board's face (workspace.Obby.Board) and the row this client tinted last.
	local boardContent: Instance? = nil
	local tinted: Frame? = nil

	local function findSign()
		if signStatus[1] and signStatus[1].Parent then
			return
		end
		table.clear(signStatus)
		table.clear(signCourse)
		local folder = workspace:FindFirstChild(Constants.OBBY_FOLDER)
		local sign = folder and folder:FindFirstChild(Constants.OBBY_SIGN)
		for _, inst in if sign then sign:GetDescendants() else {} do
			if inst:IsA("TextLabel") then
				if inst.Name == Constants.OBBY_SIGN_STATUS then
					table.insert(signStatus, inst)
				elseif inst.Name == Constants.OBBY_SIGN_COURSE then
					table.insert(signCourse, inst)
				end
			end
		end
	end

	local function findBoard(): Instance?
		if boardContent and boardContent.Parent then
			return boardContent
		end
		local folder = workspace:FindFirstChild(Constants.OBBY_FOLDER)
		local board = folder and folder:FindFirstChild(Constants.OBBY_BOARD)
		boardContent = board and board:FindFirstChild("Content", true)
		return boardContent
	end

	-- This player's row on the board: their top-10 row in the viewer's tint, or the "You" line under the rows.
	local function drawBoard(view: View?)
		local content = findBoard()
		if not content then
			return
		end
		local mine = ObbyHud.boardYou(view, Config.OBBY.BOARD.SIZE)
		local rows = content:FindFirstChild("Rows")
		local row = if mine.row and rows then rows:FindFirstChild(`Row_{mine.row}`) :: Frame? else nil
		if tinted and tinted ~= row then
			local base = tinted:GetAttribute("BaseFill")
			if typeof(base) == "Color3" then
				tinted.BackgroundColor3 = base -- the server's medal or plain card
			end
			tinted = nil
		end
		if row and row.Visible then
			local fill = WorldLeaderboard.rowStyle(mine.row :: number, true)
			local color = Color3.fromRGB(fill[1], fill[2], fill[3])
			if row.BackgroundColor3 ~= color then
				row.BackgroundColor3 = color
			end
			tinted = row
		end
		local you = content:FindFirstChild("You")
		if you and you:IsA("GuiObject") then
			you.Visible = mine.name ~= nil
			local name, value = you:FindFirstChild("Name"), you:FindFirstChild("Value")
			if name and name:IsA("TextLabel") and name.Text ~= (mine.name or "") then
				name.Text = mine.name or ""
			end
			if value and value:IsA("TextLabel") and value.Text ~= (mine.value or "") then
				value.Text = mine.value or ""
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
		local y = C.pad + C.headH + C.gap + C.pip + C.gap
		local boost = ObbyHud.boostText(view, now)
		local total = ObbyHud.totalText(view, now)
		local extra = boost ~= nil or total ~= nil
		card.boostLabel.Visible = boost ~= nil
		card.boostLabel.Text = boost or ""
		card.totalLabel.Visible = total ~= nil
		card.totalLabel.Text = total or ""
		card.extraRow.Visible = extra
		if extra then
			y += C.extraH + C.gap
		end
		local best, rank = ObbyHud.bestText(view)
		card.bestRow.Visible = best ~= nil
		card.bestRow.Position = UDim2.fromOffset(C.pad, y)
		card.bestLabel.Text = best or ""
		card.rankChip.Visible = rank ~= nil
		card.rankChip.Text = rank or ""
		local lockY = y + (if best then C.bestH + C.gap else 0)
		card.lockRow.Position = UDim2.fromOffset(C.pad, lockY)
		card.lockRow.Size = UDim2.new(1, -C.pad * 2, 0, if box.split then C.lockH * 2 + C.gap else C.lockH)
		card.lockList.FillDirection = if box.split then Enum.FillDirection.Vertical else Enum.FillDirection.Horizontal
		card.frame.Size = UDim2.fromOffset(box.w, Layout.obbyCardHeight(best ~= nil, box.split, extra))
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
		box.split = ObbyHud.lockSplit(r.w)
		heightOfBanners = bannerHeight or heightOfBanners
		if cardParts then
			cardParts.frame.Size = UDim2.fromOffset(
				box.w,
				Layout.obbyCardHeight(cardParts.bestRow.Visible, box.split, cardParts.extraRow.Visible)
			)
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
		drawBoard(current)
	end

	return self
end

return ObbyHud
