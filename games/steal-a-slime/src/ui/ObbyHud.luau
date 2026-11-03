--!strict
--[[
	ObbyHud (UI module, contract/obby.md)

	The Obby on this player's screen, from State.obby:
	  * a run card at the top of the screen while a run is on (Layout.OBBY_CARD, under the banner stack):
	      - "Section x/6": the furthest section reached this run (a fall keeps it), "Start" on the start pad,
	        and the run clock
	      - one pip per section: passed (a check), the furthest one (a mint ring), still to come (an Ink well)
	      - "Best 0:51.4" and the rank chip "#23" once this player has a time on this course (`bestText`)
	      - the base lock's time left (State.lockUntil) with a note that it runs slower meanwhile (run.lockRate);
	        "Base open" when no lock runs. The server pushes lockUntil out every obby tick but sends it only now and
	        then, so the card counts down at lockRate from the last value it saw (`lockLeft`)
	  * the portal sign's two lines (workspace.Obby.Portal, server/ObbyView), filled locally for this player: their
	    boost status ("Step in: x1.5 income!", "Boost 3:12", "Boost ready in 1:40") and the course with its time
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
local WorldLeaderboard = if script then require(script.Parent.WorldLeaderboard) else require("./WorldLeaderboard")
-- Drawing only runs in Roblox (the specs use the pure functions).
local Widgets: any = if script then require(script.Parent.Widgets) else nil

export type Run = { section: number, of: number, startedAt: number, lockRate: number? }

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

export type Pip = "done" | "here" | "ahead"

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
	if v.endsAt and v.endsAt > now then
		return `{mult} income · {clock(v.endsAt - now)} left`
	elseif v.readyAt and v.readyAt > now then
		return `Boost ready in {clock(v.readyAt - now)}`
	end
	return `Step in: {mult} income!`
end

-- The sign's course line: the course and its time left.
function ObbyHud.courseText(view: View?, now: number): string
	if not valid(view) then
		return `A new course every {math.floor(Config.OBBY.ROTATION_SECONDS / 60 + 0.5)} min`
	end
	local v = view :: View
	local left = clock(v.rotatesAt - now)
	if type(v.course) ~= "number" then
		return `New course in {left}`
	end
	return `{ObbyRules.courseLabel(v.course)} · {left} left`
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
	return `Best {ObbyRules.timeText(ObbyRules.tenths(v.best))}`, ObbyRules.rankText(v.rank)
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
		name = if rank then `You {rank}` else "You",
		value = ObbyRules.timeText(ObbyRules.tenths(v.best)),
	}
end

-- The run card's head row while a run is on: the furthest section and the run clock; nil when not running.
function ObbyHud.runText(view: View?, now: number): (string?, string?)
	local run = runOf(view)
	if not run then
		return nil, nil
	end
	local elapsed = math.max(0, now - run.startedAt)
	local title = if run.section <= 0 then "Start" else `Section {math.min(run.section, run.of)}/{run.of}`
	local m = math.floor(elapsed / 60)
	return title, string.format("%d:%04.1f", m, elapsed - m * 60)
end

-- One pip per section of the run: passed, the furthest reached, or still to come. Empty when not running.
function ObbyHud.pips(view: View?): { Pip }
	local run = runOf(view)
	local out: { Pip } = {}
	if not run then
		return out
	end
	local at = math.clamp(run.section, 0, run.of)
	for i = 1, run.of do
		local kind: Pip = if i < at then "done" elseif i == at then "here" else "ahead"
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
		bestRow: Frame,
		bestLabel: TextLabel,
		rankChip: TextLabel,
		lockRow: Frame,
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
		local bestRow = holder("Best", C.pad + C.headH + C.gap + C.pip + C.gap, C.bestH, card)
		Widgets.list(Enum.FillDirection.Horizontal, C.gap, Enum.HorizontalAlignment.Center).Parent = bestRow
		bestRow.Visible = false
		local lockRow = holder("Lock", C.pad + C.headH + C.gap + C.pip + C.gap, C.lockH, card)
		Widgets.list(Enum.FillDirection.Horizontal, C.gap, Enum.HorizontalAlignment.Center).Parent = lockRow
		local made = {
			frame = card,
			title = headLabel("Title", C.titleSize, Theme.Text, Enum.TextXAlignment.Left),
			clock = headLabel("Clock", C.clockSize, Theme.Muted, Enum.TextXAlignment.Right),
			pipRow = pipRow,
			pips = {},
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
		stroke.Color = if here then Theme.Accent else Theme.Ink
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
		local best, rank = ObbyHud.bestText(view)
		card.bestRow.Visible = best ~= nil
		card.bestLabel.Text = best or ""
		card.rankChip.Visible = rank ~= nil
		card.rankChip.Text = rank or ""
		local lockY = C.pad + C.headH + C.gap + C.pip + C.gap + (if best then C.bestH + C.gap else 0)
		card.lockRow.Position = UDim2.fromOffset(C.pad, lockY)
		card.frame.Size = UDim2.fromOffset(box.w, Layout.obbyCardHeight(best ~= nil))
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
			cardParts.frame.Size = UDim2.fromOffset(box.w, Layout.obbyCardHeight(cardParts.bestRow.Visible))
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
