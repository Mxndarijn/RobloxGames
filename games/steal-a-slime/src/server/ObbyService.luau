--!strict
--[[
	ObbyService (pure, contract/obby.md)

	Server side of the Obby (the sky course). `world.obby` is the course standing now (ObbyCourse); `session.obbyRun`
	a player's run. `step` gets where every player stands (the adapter reads root positions) and returns the
	teleports the adapter must make:
	  * stepping into the portal circle starts a run (not while carrying a slime) and lifts the player to the start
	    pad; a course they already cleared lets them in again to beat their time (`cleared`: tracked as a retry)
	  * while running, the runner's base lock counts down at OBBY.LOCK_RATE (ObbyLock.step, every tick)
	  * the counted time is one try: its clock starts the first tick the runner is past the start pad's front edge (over
	    section 1 or on) and starts again from zero each time they leave the start pad after being back on it (a fall
	    puts them there). Standing on the start pad doesn't count. The total since the first try left the pad is shown
	    too (`firstAt`), but never counts
	  * there are no checkpoints: the server tracks the furthest section the runner has been over (ObbyCourse.sectionAt),
	    this try (`attempt`, in order) and this run (`section`), and the one they are over now (State.obby.run.at, the run
	    card's section). Skipping a section within a try, or a try faster than OBBY.MIN_RUN_SECONDS, marks the run
	    invalid (it still finishes, but earns nothing)
	  * a fall sends the runner back to the start pad: the try is over and the next one starts from zero; the run and
	    the sections it reached go on. The client puts its own runner back the moment its root drops OBBY.FALL_DEPTH under the lowest platform
	    it could still land on (visuals/client/ObbyFx); the server sees the jump back (`resets`: the adapter opens
	    the anti-cheat's server-move window) and counts the fall. Past FALL_DEPTH + SERVER_FALL_SLACK the server
	    moves the runner itself, as the backup. Wandering far off the course's ends or sides ends the run
	  * the Goo Ring behind the start pad (ObbyCourse.inHome) ends the run and sets the runner down by the portal
	  * the course stands in its own world (Place.zone): anyone there without a run is set down by the portal
	  * every section a run clears for the first time (reaching the next part of the course; the last one on the
	    finish pad) adds an equal share of the boost (ObbyRules.earn: OBBY.BONUS over the sections, BOOST_SECONDS
	    again from then): the first share when the boost is ready, the rest because this run started it. A section
	    counts once per run, so falls and retries of the same sections add nothing; an invalid run or a movement
	    flag since the portal stops the shares. Saved as data.obbyUntil / obbyReadyAt / obbyEarned
	  * the finish pad ends the run: the time and a best on this course; then the player is set down by the portal. A best that passes
	    ObbyBoard.eligible goes to the course's shared board (`world.obbyBoard`, server/ObbyBoard) with its rank
	  * a new rotation (ObbyCourse.slot) rebuilds the course once no one is running, or after OBBY.REBUILD_GRACE
	    seconds, sending the runners still on it back to the portal
	`refresh` keeps data.obbyBonus (read by Perks) in step with the saved boost, also across rejoins.
	The one thing a player sends is the vine rope they hang on (`holdVine`, Request ObbyVine): looks only, so other
	clients draw that rope carrying them (the Player's ObbyVine attribute, `heldVine`). Everything else the server reads.
]]

local Shared = if script then (game:GetService("ReplicatedStorage") :: any).Shared else nil
local Config = if Shared then require(Shared.Config) else require("../shared/Config")
local ObbyCourse = if Shared then require(Shared.ObbyCourse) else require("../shared/ObbyCourse")
local ObbyRules = if Shared then require(Shared.ObbyRules) else require("../shared/ObbyRules")
local ObbyBoard = if script then require(script.Parent.ObbyBoard) else require("./ObbyBoard")
local ObbyLock = if script then require(script.Parent.ObbyLock) else require("./ObbyLock")
local World = if script then require(script.Parent.World) else require("./World")

local OBBY = Config.OBBY

type World = World.World
type Session = World.Session
type Vec = ObbyCourse.Vec

-- Where the course and its portal stand in the world (the adapter fills it from WorldLayout.OBBY).
export type Place = {
	frame: ObbyCourse.Frame,
	portal: Vec, -- portal circle centre on the ground
	portalRadius: number,
	exit: Vec, -- where a player is set down after a run (in front of the portal)
	exitYaw: number, -- the way they face there (towards the plaza, their back to the portal)
	zone: { centre: Vec, radius: number }, -- the obby world (WorldLayout.inObbyWorld): no one stays there without a run
}

export type Move = { userId: number, pos: Vec, yaw: number }

-- `resets`: runners the client put back on the start pad after a fall this tick.
export type Result = { moves: { Move }, rebuilt: boolean, resets: { number } }

-- State.obby
export type View = {
	bonus: number, -- the boost's bonus while it runs, else what a full clear earns (OBBY.BONUS)
	endsAt: number?, -- boost end while boosted (server time)
	readyAt: number?, -- a finish earns the boost again (server time); nil = ready now
	sections: { string }, -- the current course's section names, in order
	rotatesAt: number, -- server time the next rotation starts
	-- the run in progress: `section` = the furthest section reached, `at` = the one the runner is over now (0 = the
	-- start pad, of + 1 = the finish pad), `startedAt` = when this try's clock started (nil = on the start pad),
	-- `firstAt` = when the first try's started (the total time, shown but never counted), `paid` = the sections that
	-- added to the boost this run, `lockRate` = how fast the runner's base lock counts down meanwhile (OBBY.LOCK_RATE)
	run: {
		section: number,
		at: number,
		of: number,
		startedAt: number?,
		firstAt: number?,
		paid: number,
		lockRate: number,
	}?,
	best: number?, -- best counted finish on the current course, seconds (whole tenths)
	rank: number?, -- that best's rank on the course board (OBBY.BOARD.RANK_DEPTH + 1 = deeper); nil = none yet
	course: number, -- the course number players see (ObbyRules.courseNumber)
}

local ObbyService = {}

ObbyService.OFF_COURSE = 40 -- studs past the course's ends or sides (course-local) that end a run
ObbyService.PORTAL_HEIGHT = 8 -- studs above the portal centre that still count as standing in it
ObbyService.RESET_JUMP = 20 -- studs back along the course in one tick, onto the start pad: the client put the runner back

-- A Move's `pos` is where a standard avatar's root goes: OBBY.RESPAWN_LIFT above the floor. `landing` shifts it by how
-- much higher this character's root stands (`rootHeight`: its HipHeight plus half its root part's height), so a
-- runner whose own body scales just came back (server/ObbyAvatar) lands on their feet at the exit, instead of in the
-- ground with the Humanoid pushing them (and the camera) up over the next frames.
function ObbyService.landing(pos: Vec, rootHeight: number): Vec
	return { pos[1], pos[2] + rootHeight - OBBY.RESPAWN_LIFT, pos[3] }
end

local function clock(seconds: number): string
	local s = math.max(0, math.ceil(seconds))
	return string.format("%d:%02d", s // 60, s % 60)
end

-- Builds the course for `now` (the adapter calls it once at start, then builds the Instances).
function ObbyService.setup(world: World, now: number): ObbyCourse.Course
	local course = ObbyCourse.build(ObbyCourse.slot(now))
	world.obby = course
	return course
end

local function worldMove(place: Place, userId: number, at: Vec): Move
	return { userId = userId, pos = ObbyCourse.toWorld(place.frame, at), yaw = place.frame.yaw }
end

local function exitMove(place: Place, userId: number): Move
	return { userId = userId, pos = table.clone(place.exit), yaw = place.exitYaw }
end

local function sectionName(course: ObbyCourse.Course, index: number): string
	local pick = course.picks[index]
	return if pick then ObbyCourse.nameOf(pick.id) else "?"
end

-- True when `session` finished the course of rotation `slot` with a run that counted (session.obbyBest, also read
-- back from the board after a rejoin): a new run on it is a retry for a better time.
function ObbyService.cleared(session: Session, slot: number): boolean
	local best = session.obbyBest
	return best ~= nil and best.slot == slot
end

-- Starts a run for `session`. Returns ok, a player-facing reason, and the move to the start pad.
function ObbyService.enter(world: World, session: Session, place: Place, now: number): (boolean, string?, Move?)
	local course = world.obby
	if not course then
		return false, "The Obby isn't open yet", nil
	end
	if session.obbyRun then
		return false, nil, nil
	end
	if session.carry then
		return false, "Put your slime down first", nil
	end
	if course.slot ~= ObbyCourse.slot(now) then
		return false, "A new course is on its way. Back in a moment!", nil
	end
	local retry = ObbyService.cleared(session, course.slot)
	session.obbyRun = {
		slot = course.slot,
		section = 0,
		attempt = 0,
		at = 0,
		cleared = 0,
		paid = 0,
		enteredAt = now,
		settleUntil = now + OBBY.MOVE_GRACE,
	}
	World.markDirty(session)
	World.track(world, session.userId, {
		op = "event",
		name = "ObbyStarted",
		fields = { if retry then "Run - Retry" else "Run - First try" },
	})
	local status = ObbyRules.phase(session.data, now)
	local hint = if status == "ready"
		then `Every section adds income, up to x{1 + OBBY.BONUS}!`
		else `Boost ready again in {clock(session.data.obbyReadyAt - now)}`
	World.notify(world, session.userId, `Obby! {hint}`, "info", nil)
	return true, nil, worldMove(place, session.userId, course.start)
end

-- Ends `session`'s run without a finish (left the course, died, rotation).
function ObbyService.cancel(session: Session)
	if session.obbyRun then
		session.obbyRun = nil
		World.markDirty(session)
	end
end

-- "x1.5" for a bonus of 0.5 (one decimal, no trailing zero).
function ObbyService.multText(bonus: number): string
	local text = string.format("%.1f", 1 + bonus)
	return "x" .. (string.gsub(text, "%.0$", ""))
end

-- Pays the sections a run has cleared up to `cleared` (in order, each once per run): each adds ObbyRules.share of
-- the boost while this run may still earn (not invalid, no movement flag since the portal).
local function reward(
	world: World,
	session: Session,
	run: World.ObbyRun,
	course: ObbyCourse.Course,
	cleared: number,
	now: number
)
	cleared = math.min(cleared, #course.spans)
	if cleared <= run.cleared then
		return
	end
	local guard = world.guard[session.userId]
	local flagged = guard ~= nil and guard.flaggedAt ~= nil and guard.flaggedAt >= run.enteredAt
	local share = ObbyRules.share(#course.spans)
	while run.cleared < cleared do
		run.cleared += 1
		if not run.invalid and not flagged and ObbyRules.earn(session.data, now, share, run.paid > 0) then
			run.paid += 1
		end
	end
	session.data.obbyBonus = ObbyRules.bonus(session.data, now)
	World.markDirty(session)
end

-- The ObbyNewBest field for a rank (RANK_DEPTH + 1 = deeper than the board reads).
function ObbyService.rankField(rank: number): string
	if rank <= 3 then
		return "Rank - Top 3"
	elseif rank <= 10 then
		return "Rank - Top 10"
	elseif rank <= OBBY.BOARD.RANK_DEPTH then
		return "Rank - Top 100"
	end
	return "Rank - Deeper"
end

-- The finish message's board part: "New best: #6 on this course" or "Your best: 0:44.9 (#6)"; nil without a best.
function ObbyService.bestText(newBest: boolean, best: number?, rank: number?): string?
	local rankText = ObbyRules.rankText(rank)
	if newBest then
		return if rankText then `New best: {rankText} on this course` else "New best on this course!"
	elseif best then
		local time = ObbyRules.timeText(ObbyRules.tenths(best))
		return if rankText then `Your best: {time} ({rankText})` else `Your best: {time}`
	end
	return nil
end

local function finish(world: World, session: Session, run: World.ObbyRun, course: ObbyCourse.Course, now: number)
	local seconds = now - (run.startedAt or now) -- this try: from when the runner last left the start pad
	if seconds < OBBY.MIN_RUN_SECONDS then
		run.invalid = true
	end
	session.obbyRun = nil
	World.markDirty(session)
	local tenths = ObbyRules.tenths(seconds)
	local time = ObbyRules.timeText(tenths)
	-- A best (and a board time) only from a run that counts, on a save this server may write, with no flag since.
	local counts = not run.invalid and ObbyBoard.eligible(world, session, run, now)
	local best = session.obbyBest
	local prior = if best and best.slot == course.slot then ObbyRules.tenths(best.seconds) else nil
	local newBest = counts and (prior == nil or tenths < prior)
	local board = world.obbyBoard :: ObbyBoard.State?
	local rank: number? = nil
	if newBest then
		session.obbyBest = { slot = course.slot, seconds = tenths / 10 }
		if board then
			local placed = ObbyBoard.record(board, course, session, tenths, now)
			rank = placed
			World.track(world, session.userId, {
				op = "event",
				name = "ObbyNewBest",
				value = if placed <= OBBY.BOARD.RANK_DEPTH then placed else 0,
				fields = { ObbyService.rankField(placed) },
			})
		end
	elseif board and counts then
		rank = ObbyBoard.rank(board, session, course.slot)
	end
	local mine = session.obbyBest
	local tail = if counts
		then ObbyService.bestText(newBest, if mine and mine.slot == course.slot then mine.seconds else nil, rank)
		else nil
	local earned = run.paid > 0
	if run.invalid then
		World.notify(world, session.userId, "That run didn't count. Try again!", "bad", nil)
	elseif earned then
		local boost =
			`{ObbyService.multText(session.data.obbyEarned)} income for {math.floor(OBBY.BOOST_SECONDS / 60 + 0.5)} min`
		World.notify(
			world,
			session.userId,
			if tail then `Cleared in {time}! {tail} · {boost}` else `Obby cleared in {time}! {boost}`,
			"good",
			"BossMvp"
		)
	else
		World.notify(
			world,
			session.userId,
			if newBest
				then `Cleared in {time}! {tail}`
				elseif tail then `Cleared in {time}. {tail}`
				else `Cleared in {time}! Boost ready again in {clock(session.data.obbyReadyAt - now)}`,
			"good",
			nil
		)
	end
	World.track(world, session.userId, {
		op = "event",
		name = "ObbyFinished",
		value = math.floor(seconds + 0.5),
		fields = { if earned then "Boost - Earned" elseif run.invalid then "Boost - Invalid" else "Boost - Cooling" },
	})
end

local function trackFall(world: World, session: Session, course: ObbyCourse.Course, at: number)
	local over = math.clamp(at, 1, #course.spans)
	World.track(world, session.userId, {
		op = "event",
		name = "ObbyFell",
		fields = { `Section - {sectionName(course, over)}` },
	})
end

-- Starts this try's clock the first tick the runner is past the start pad (`at` > 0), and the total with the first.
local function startClock(session: Session, run: World.ObbyRun, at: number, now: number)
	if run.startedAt == nil and at > 0 then
		run.startedAt = now
		run.firstAt = run.firstAt or now
		World.markDirty(session)
	end
end

-- Back on the start pad (a fall, or walking back): this try is over; the next starts from zero when they leave it.
local function newTry(session: Session, run: World.ObbyRun)
	if run.startedAt ~= nil or run.attempt ~= 0 then
		run.startedAt = nil
		run.attempt = 0
		World.markDirty(session)
	end
end

-- The part of the course the runner is over now (State.obby.run.at).
local function setAt(session: Session, run: World.ObbyRun, at: number)
	if run.at ~= at then
		run.at = at
		World.markDirty(session)
	end
end

-- One runner's tick. Returns the move the adapter must make, if any, and true when the client put the runner back
-- on the start pad after a fall.
local function progress(world: World, session: Session, place: Place, pos: Vec, now: number): (Move?, boolean)
	local run = session.obbyRun :: World.ObbyRun
	local course = world.obby
	if not course or run.slot ~= course.slot then
		ObbyService.cancel(session)
		return nil, false
	end
	local p = ObbyCourse.toLocal(place.frame, pos)
	if run.settleUntil and now < run.settleUntil then
		run.lastX = nil
		-- the lift or respawn may not have reached the client yet; a runner already off the pad's front (a quick
		-- start) still starts the clock, but not the stale position of a runner who just fell (under the floors)
		if
			run.startedAt == nil
			and p[1] <= course.length
			and math.abs(p[3]) <= ObbyCourse.WIDTH / 2
			and p[2] >= ObbyCourse.fallHeight(course, p, OBBY.FALL_DEPTH)
		then
			startClock(session, run, ObbyCourse.sectionAt(course, p), now)
		end
		return nil, false
	end
	local off = ObbyService.OFF_COURSE
	if p[1] < -off or p[1] > course.length + off or math.abs(p[3]) > off then
		ObbyService.cancel(session)
		World.notify(world, session.userId, "You left the Obby", "info", nil)
		return nil, false
	end
	if ObbyCourse.inHome(course, p) then
		ObbyService.cancel(session) -- the Goo Ring behind the start pad: back to the yard
		return exitMove(place, session.userId), false
	end
	local at = ObbyCourse.sectionAt(course, p)
	local lastX = run.lastX
	run.lastX = p[1]
	startClock(session, run, at, now)
	if p[2] < ObbyCourse.fallHeight(course, p, OBBY.FALL_DEPTH + OBBY.SERVER_FALL_SLACK) then
		trackFall(world, session, course, at)
		run.settleUntil = now + OBBY.MOVE_GRACE
		run.lastX = nil
		setAt(session, run, 0) -- back on the start pad
		newTry(session, run)
		return worldMove(place, session.userId, course.start), false
	end
	setAt(session, run, at)
	if at == 0 then
		newTry(session, run)
		if lastX and lastX - p[1] > ObbyService.RESET_JUMP then
			trackFall(world, session, course, ObbyCourse.sectionAt(course, { lastX, p[2], p[3] }))
			return nil, true
		end
	end
	if at > run.attempt then
		if at > run.attempt + 1 then
			run.invalid = true -- got past a section without being over it this try
		end
		run.attempt = math.min(at, #course.spans)
	end
	if at > run.section then
		run.section = math.min(at, #course.spans)
		World.markDirty(session)
	end
	if at > #course.spans and now - (run.startedAt or now) < OBBY.MIN_RUN_SECONDS then
		run.invalid = true -- on the finish pad too fast: the last section pays nothing either
	end
	reward(world, session, run, course, at - 1, now) -- over part `at`: every section before it is cleared
	if at > #course.spans and ObbyCourse.onFinish(course, p) then
		finish(world, session, run, course, now)
		return exitMove(place, session.userId), false
	end
	return nil, false
end

local function inZone(place: Place, pos: Vec): boolean
	local c = place.zone.centre
	return (pos[1] - c[1]) ^ 2 + (pos[3] - c[3]) ^ 2 < place.zone.radius ^ 2
end

local function inPortal(place: Place, pos: Vec): boolean
	local dx, dz = pos[1] - place.portal[1], pos[3] - place.portal[3]
	local dy = pos[2] - place.portal[2]
	return dx * dx + dz * dz <= place.portalRadius * place.portalRadius and dy >= -2 and dy <= ObbyService.PORTAL_HEIGHT
end

-- Rebuilds the course when the rotation turned and the runners are done (or out of time). Returns the moves for the
-- runners sent home and whether it rebuilt.
local function rotate(world: World, place: Place, now: number, moves: { Move }): boolean
	local course = world.obby
	local slot = ObbyCourse.slot(now)
	if not course or course.slot == slot then
		return false
	end
	local runners = {}
	for _, session in world.sessions do
		if session.obbyRun then
			table.insert(runners, session)
		end
	end
	if #runners > 0 and now - ObbyCourse.slotStart(slot) < OBBY.REBUILD_GRACE then
		return false
	end
	for _, session in runners do
		ObbyService.cancel(session)
		World.notify(world, session.userId, "The Obby changed! Try the new course.", "info", nil)
		table.insert(moves, exitMove(place, session.userId))
	end
	world.obby = ObbyCourse.build(slot)
	World.markAllDirty(world)
	return true
end

-- One server tick: rotation, portal, runs. `positions` = root position per userId (nil = no live character).
function ObbyService.step(world: World, place: Place, positions: { [number]: Vec }, now: number): Result
	local moves: { Move } = {}
	local resets: { number } = {}
	local rebuilt = rotate(world, place, now, moves)
	for userId, session in world.sessions do
		local pos = positions[userId]
		if not pos then
			ObbyService.cancel(session) -- died or no character: the run is over
			session.obbyOnPortal = nil
		elseif session.obbyRun then
			ObbyLock.step(session, now) -- the base lock runs at OBBY.LOCK_RATE while running
			local move, reset = progress(world, session, place, pos, now)
			if move then
				table.insert(moves, move)
			elseif reset then
				table.insert(resets, userId)
			end
		elseif inZone(place, pos) then
			table.insert(moves, exitMove(place, userId)) -- in the obby world without a run (left the course)
			session.obbyOnPortal = nil
		else
			local inside = inPortal(place, pos)
			if inside and not session.obbyOnPortal then
				local ok, reason, move = ObbyService.enter(world, session, place, now)
				if ok and move then
					table.insert(moves, move)
				elseif reason then
					World.notify(world, session.userId, reason, "bad", nil)
				end
			end
			session.obbyOnPortal = inside
		end
	end
	return { moves = moves, rebuilt = rebuilt, resets = resets }
end

-- Keeps data.obbyBonus in step with the saved timers; toasts when a boost runs out. Call every step (GameLoop).
function ObbyService.refresh(world: World, now: number)
	for _, session in world.sessions do
		local data = session.data
		local bonus = ObbyRules.bonus(data, now)
		if bonus ~= data.obbyBonus then
			local ended = bonus == nil and data.obbyBonus ~= nil
			data.obbyBonus = bonus
			World.markDirty(session)
			if ended then
				World.notify(
					world,
					session.userId,
					`Your obby boost ended. Run it again in {clock(data.obbyReadyAt - now)}`,
					"info",
					nil
				)
			end
		end
	end
end

-- State.obby for `session`; nil until the course is built.
function ObbyService.view(world: World, session: Session, now: number): View?
	local course = world.obby
	if not course then
		return nil
	end
	local boost = ObbyRules.view(session.data, now)
	local run = session.obbyRun
	local best = session.obbyBest
	local board = world.obbyBoard :: ObbyBoard.State?
	return {
		bonus = boost.bonus,
		endsAt = boost.endsAt,
		readyAt = boost.readyAt,
		sections = ObbyCourse.names(course.picks),
		rotatesAt = ObbyCourse.slotStart(ObbyCourse.slot(now) + 1),
		run = if run
			then {
				section = run.section,
				at = run.at,
				of = #course.spans,
				startedAt = run.startedAt,
				firstAt = run.firstAt,
				paid = run.paid,
				lockRate = ObbyLock.rate(),
			}
			else nil,
		best = if best and best.slot == course.slot then best.seconds else nil,
		rank = if board then ObbyBoard.rank(board, session, course.slot) else nil,
		course = ObbyRules.courseNumber(course.slot),
	}
end

-- The vine rope `id` (a course part's id, "" = let go) the runner says they hold now (Request ObbyVine). Looks only:
-- other clients draw that rope carrying them. Refused off a run, on another course or for a part that is no rope.
function ObbyService.holdVine(world: World, session: Session, id: string): (boolean, string?)
	local run = session.obbyRun
	if id == "" then
		if run then
			run.vine = nil
		end
		return true, nil
	end
	local course = world.obby
	if not run or not course or run.slot ~= course.slot then
		return false, "not on a run"
	end
	for _, part in course.parts do
		if part.id == id then
			if part.vine == nil then
				return false, "not a vine"
			end
			run.vine = id
			return true, nil
		end
	end
	return false, "not a vine"
end

-- The vine rope part id `session` holds now (the Player's ObbyVine attribute), nil = none or no run on this course.
function ObbyService.heldVine(world: World, session: Session): string?
	local run = session.obbyRun
	local course = world.obby
	if not run or not course or run.slot ~= course.slot then
		return nil
	end
	return run.vine
end

return ObbyService
