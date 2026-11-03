--!strict
--[[
	ObbyBoard (pure, contract/obby.md §7)

	The fastest-time board of the course standing now, shared by every server: one board per course
	(`Obby_<slot>_<hash>`, ObbyCourse.hash), ranked by the shared PeriodBoard (time in tenths, then who set it
	first). `world.obbyBoard` holds this server's copy (`State`): the top OBBY.BOARD.RANK_DEPTH of the last read
	with this server's own new bests placed in at once, the last course's #1, and the writes still to send.

	  * `eligible`: the server-side rules a counted finish must pass to post (ObbyService checks the rest: started at
	    this portal on this slot, every section in order, at least MIN_RUN_SECONDS): it finished within its course's
	    window plus REBUILD_GRACE, no movement flag since the run started (SlimeGuard.report), and the session can save.
	  * `record`: a new best (ObbyService decides it beats the player's own): placed in the local copy and queued for
	    one keep-the-best write. Returns the rank (RANK_DEPTH + 1 = deeper than the board reads).
	  * `flush` sends the queued writes and `refresh` reads the board (both through the injected store: a
	    MemoryStore sorted map live, PeriodBoard.memoryStore in memory mode and in specs). A read brings back a
	    rejoined player's best (session.obbyBest), refreshes a "Show me on leaderboards" change, and marks the
	    sessions whose rank changed.
	  * `boardView`: the text of the world board by the portal (hidden players as PlayerSettings.HIDDEN_NAME; no user
	    id ever leaves the server). `rank`: a player's rank for State.obby.
	The client never sends a time. No Roblox APIs (the adapter is server/ObbyBoardView).
]]

local Shared = if script then (game:GetService("ReplicatedStorage") :: any).Shared else nil
local Lib = if script then (game:GetService("ReplicatedStorage") :: any).Lib else nil
local Config = if Shared then require(Shared.Config) else require("../shared/Config")
local ObbyCourse = if Shared then require(Shared.ObbyCourse) else require("../shared/ObbyCourse")
local ObbyRules = if Shared then require(Shared.ObbyRules) else require("../shared/ObbyRules")
local PlayerSettings = if Shared then require(Shared.PlayerSettings) else require("../shared/PlayerSettings")
local PeriodBoard = if Lib
	then require(Lib.ranking.PeriodBoard)
	else require("../../../../shared/luau/src/ranking/PeriodBoard")
local World = if script then require(script.Parent.World) else require("./World")

local OBBY = Config.OBBY
local BOARD = OBBY.BOARD

type World = World.World
type Session = World.Session

export type Mode = "Ok" | "Memory" -- the backend this server uses: the shared MemoryStore, or this server only
export type Status = "Ok" | "Memory" | "Error" -- workspace ObbyBoardStatus
export type Course = { slot: number, hash: string, map: string }
export type Post = { map: string, userId: number, entry: PeriodBoard.Entry, expiresAt: number }
export type Last = { name: string, score: number }

export type State = {
	mode: Mode,
	status: Status,
	nameOf: (userId: number) -> string, -- a display name (the adapter reads the Player)
	course: Course?, -- the board standing now
	previous: Course?, -- the course before it ("Last course" on the board)
	rows: { PeriodBoard.Row }, -- the top RANK_DEPTH, best first: the last read plus this server's new bests
	last: Last?, -- the previous course's #1
	lastFor: number?, -- the slot `last` was read for
	pending: { Post }, -- writes still to send (flush)
	ranks: { [number]: number }, -- rank per userId last put in State.obby (dirty tracking)
	readAt: number?, -- server time of the last good read
	version: number, -- bumps whenever the rows, the course or the last course change (the view repaints)
}

export type BoardRow = { rank: string, name: string, value: string }
export type BoardView = { sub: string, rows: { BoardRow }, footer: string? }

local ObbyBoard = {}

ObbyBoard.BASE = "Obby"
ObbyBoard.EMPTY_TEXT = "No times yet"
ObbyBoard.OFFLINE_TEXT = "Board offline"

function ObbyBoard.new(mode: Mode, nameOf: (userId: number) -> string): State
	return {
		mode = mode,
		status = mode,
		nameOf = nameOf,
		course = nil,
		previous = nil,
		rows = {},
		last = nil,
		lastFor = nil,
		pending = {},
		ranks = {},
		readAt = nil,
		version = 0,
	}
end

-- The board's store name: "Obby_<slot>_<hash>".
function ObbyBoard.name(slot: number, hash: string): string
	return PeriodBoard.mapName(ObbyBoard.BASE, slot, hash)
end

-- Points the board at `course` when it is a new one (hashes it once). Returns true when it changed.
function ObbyBoard.sync(state: State, course: ObbyCourse.Course): boolean
	local current = state.course
	if current and current.slot == course.slot then
		return false
	end
	if current then
		state.previous = current
		local top = state.rows[1]
		state.last = if top
			then { name = if top.hidden then PlayerSettings.HIDDEN_NAME else top.name, score = top.score }
			else nil
		state.lastFor = nil -- read the shared one on the next refresh
	end
	local hash = ObbyCourse.hash(course)
	state.course = { slot = course.slot, hash = hash, map = ObbyBoard.name(course.slot, hash) }
	state.rows = {}
	table.clear(state.ranks)
	state.version += 1
	return true
end

-- True when `session` turned "Show me on leaderboards" off.
function ObbyBoard.hidden(session: Session): boolean
	return not PlayerSettings.clean(session.data.settings).showOnBoards
end

--[[
	The rules a counted finish of `run` must also pass to post at `now`: within its course's window plus
	REBUILD_GRACE, no movement flag since the runner entered the portal, and a save this server may write. Returns ok and the
	reason ("late", "flagged", "unsaved").
]]
function ObbyBoard.eligible(world: World, session: Session, run: World.ObbyRun, now: number): (boolean, string?)
	if now > ObbyCourse.slotStart(run.slot + 1) + OBBY.REBUILD_GRACE then
		return false, "late"
	end
	local guard = world.guard[session.userId]
	if guard and guard.flaggedAt and guard.flaggedAt >= run.enteredAt then
		return false, "flagged"
	end
	if not World.canSave(world, session.userId) then
		return false, "unsaved"
	end
	return true, nil
end

local function entryFor(state: State, session: Session, slot: number, score: number, at: number): PeriodBoard.Entry
	local name = state.nameOf(session.userId)
	return {
		score = score,
		at = math.clamp(math.floor(at - ObbyCourse.slotStart(slot)), 0, PeriodBoard.TIE_RANGE - 1),
		name = string.sub(name, 1, PeriodBoard.MAX_NAME),
		hidden = ObbyBoard.hidden(session),
	}
end

local function queue(state: State, course: Course, userId: number, entry: PeriodBoard.Entry)
	table.insert(state.pending, {
		map = course.map,
		userId = userId,
		entry = entry,
		expiresAt = ObbyCourse.slotStart(course.slot + 1) + BOARD.EXPIRE_AFTER,
	})
end

--[[
	A new best of `tenths` for `session` on `course`, set at `now`: placed in the local copy and queued for one write.
	Returns the rank (RANK_DEPTH + 1 when deeper than the board reads).
]]
function ObbyBoard.record(
	state: State,
	course: ObbyCourse.Course,
	session: Session,
	tenths: number,
	now: number
): number
	ObbyBoard.sync(state, course)
	local current = state.course :: Course
	local entry = entryFor(state, session, current.slot, tenths, now)
	local rows, rank = PeriodBoard.place(state.rows, session.userId, entry, BOARD.RANK_DEPTH)
	state.rows = rows
	state.version += 1
	queue(state, current, session.userId, entry)
	local shown = rank or BOARD.RANK_DEPTH + 1
	state.ranks[session.userId] = shown
	return shown
end

-- `userId`'s rank on the board of `slot`: nil without a time there (or before the first read found it);
-- RANK_DEPTH + 1 when the player has a best on this course that the read board doesn't reach.
function ObbyBoard.rank(state: State, session: Session, slot: number): number?
	local course = state.course
	if not course or course.slot ~= slot then
		return nil
	end
	local rank = PeriodBoard.rankOf(state.rows, session.userId)
	if rank then
		return rank
	end
	local best = session.obbyBest
	if best and best.slot == slot and #state.rows >= BOARD.RANK_DEPTH then
		return BOARD.RANK_DEPTH + 1
	end
	return nil
end

--[[
	Sends the queued writes (yields on a live store). Writes for a board that has already expired are dropped.
	Returns the errors of the writes that failed (the status turns "Error"; they stay queued for the next flush and
	placed in this server's rows meanwhile).
]]
function ObbyBoard.flush(state: State, store: PeriodBoard.Store, now: number, wait: ((number) -> ())?): { string }
	local posts = state.pending
	state.pending = {}
	local errors: { string } = {}
	for _, post in posts do
		if post.expiresAt > now then
			local ok, reason = PeriodBoard.post(store, post.map, post.userId, post.entry, {
				expiration = post.expiresAt - now,
				wait = wait,
			})
			if ok then
				state.status = state.mode
			else
				state.status = "Error"
				table.insert(errors, `{post.map} {post.userId}: {reason}`)
				table.insert(state.pending, post) -- tried again on the next flush, until its board expires
			end
		end
	end
	return errors
end

-- Brings back a rejoined player's best, queues a hidden-flag change, and marks the sessions whose rank changed.
local function syncSessions(state: State, world: World)
	local course = state.course
	if not course then
		return
	end
	for userId, session in world.sessions do
		local row = PeriodBoard.find(state.rows, userId)
		local best = session.obbyBest
		if row then
			local mine = if best and best.slot == course.slot then ObbyRules.tenths(best.seconds) else nil
			if mine == nil or row.score < mine then
				session.obbyBest = { slot = course.slot, seconds = row.score / 10 }
				World.markDirty(session)
			end
			local hidden = ObbyBoard.hidden(session)
			if row.hidden ~= hidden then
				local entry = { score = row.score, at = row.at, name = row.name, hidden = hidden }
				state.rows = PeriodBoard.place(state.rows, userId, entry, BOARD.RANK_DEPTH)
				queue(state, course, userId, entry)
			end
		end
		local rank = ObbyBoard.rank(state, session, course.slot)
		if state.ranks[userId] ~= rank then
			state.ranks[userId] = rank :: any
			World.markDirty(session)
		end
	end
end

--[[
	Reads the current board's top RANK_DEPTH (yields on a live store) and, once per course, the last course's #1.
	Writes still queued stay placed in the rows. Returns ok and the read error.
]]
function ObbyBoard.refresh(state: State, store: PeriodBoard.Store, world: World, now: number): (boolean, string?)
	local course = state.course
	if not course then
		return true, nil
	end
	local rows, err = PeriodBoard.read(store, course.map, BOARD.RANK_DEPTH)
	if not rows then
		state.status = "Error"
		return false, err
	end
	for _, post in state.pending do
		if post.map == course.map then
			rows = PeriodBoard.place(rows, post.userId, post.entry, BOARD.RANK_DEPTH)
		end
	end
	state.rows = rows
	state.readAt = now
	state.status = state.mode
	state.version += 1
	local previous = state.previous
	if previous and state.lastFor ~= previous.slot then
		local top = PeriodBoard.read(store, previous.map, 1)
		if top then
			local first = top[1]
			state.last = if first
				then { name = if first.hidden then PlayerSettings.HIDDEN_NAME else first.name, score = first.score }
				else state.last
			state.lastFor = previous.slot
		end
	end
	syncSessions(state, world)
	return true, nil
end

local function clock(seconds: number): string
	local s = math.max(0, math.ceil(seconds))
	return string.format("%d:%02d", s // 60, s % 60)
end

-- "Course #1,204" for a rotation slot.
function ObbyBoard.courseLabel(slot: number): string
	return ObbyRules.courseLabel(ObbyRules.courseNumber(slot))
end

--[[
	The world board's text at `now`: the course line with the countdown, the top OBBY.BOARD.SIZE rows (this server's
	players shown or hidden by their setting now), and the footer (the last course's #1, or "Board offline").
]]
function ObbyBoard.boardView(state: State, world: World, now: number): BoardView
	local course = state.course
	local slot = if course then course.slot else ObbyCourse.slot(now)
	local sub = `{ObbyBoard.courseLabel(slot)} · new course in {clock(ObbyCourse.slotStart(slot + 1) - now)}`
	local rows: { BoardRow } = {}
	for _, row in state.rows do
		if #rows >= BOARD.SIZE then
			break
		end
		local session = world.sessions[row.userId]
		local hidden = if session then ObbyBoard.hidden(session) else row.hidden
		local name = if hidden then PlayerSettings.HIDDEN_NAME elseif row.name ~= "" then row.name else "?"
		table.insert(rows, { rank = `#{row.rank}`, name = name, value = ObbyRules.timeText(row.score) })
	end
	if #rows == 0 then
		table.insert(rows, { rank = "", name = ObbyBoard.EMPTY_TEXT, value = "" })
	end
	local footer: string? = nil
	if state.status == "Error" then
		footer = ObbyBoard.OFFLINE_TEXT
	elseif state.last then
		footer = `Last course: {state.last.name} {ObbyRules.timeText(state.last.score)}`
	end
	return { sub = sub, rows = rows, footer = footer }
end

return table.freeze(ObbyBoard)
