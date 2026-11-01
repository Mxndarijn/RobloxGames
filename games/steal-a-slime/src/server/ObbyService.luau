--!strict
--[[
	ObbyService (pure, contract/obby.md)

	Server side of the Obby (the sky course). `world.obby` is the course standing now (ObbyCourse); `session.obbyRun`
	a player's run. `step` gets where every player stands (the adapter reads root positions) and returns the
	teleports the adapter must make:
	  * stepping into the portal circle starts a run (not while carrying a slime) and lifts the player to the start pad
	  * there are no checkpoints: the server tracks the furthest section the runner has been over (ObbyCourse.sectionAt),
	    in order. Skipping a section, or finishing faster than OBBY.MIN_RUN_SECONDS, marks the run invalid (it still
	    finishes, but earns nothing)
	  * a fall sends the runner back to the start pad; the clock keeps running and the sections already done stay
	    done. The client puts its own runner back the moment its root drops OBBY.FALL_DEPTH under the lowest platform
	    it could still land on (visuals/client/ObbyFx); the server sees the jump back (`resets`: the adapter opens
	    the anti-cheat's server-move window) and counts the fall. Past FALL_DEPTH + SERVER_FALL_SLACK the server
	    moves the runner itself, as the backup. Wandering far off the course's ends or sides ends the run
	  * the Goo Ring behind the start pad (ObbyCourse.inHome) ends the run and sets the runner down by the portal
	  * the course stands in its own world (Place.zone): anyone there without a run is set down by the portal
	  * the finish pad ends the run: the time, a best on this course, and the boost when ObbyRules says it is ready
	    (data.obbyUntil / obbyReadyAt, saved); then the player is set down by the portal
	  * a new rotation (ObbyCourse.slot) rebuilds the course once no one is running, or after OBBY.REBUILD_GRACE
	    seconds, sending the runners still on it back to the portal
	`refresh` keeps data.obbyBonus (read by Perks) in step with the saved timers, also across rejoins.
	Players never send anything; there is no remote.
]]

local Shared = if script then (game:GetService("ReplicatedStorage") :: any).Shared else nil
local Config = if Shared then require(Shared.Config) else require("../shared/Config")
local ObbyCourse = if Shared then require(Shared.ObbyCourse) else require("../shared/ObbyCourse")
local ObbyRules = if Shared then require(Shared.ObbyRules) else require("../shared/ObbyRules")
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
	bonus: number,
	endsAt: number?, -- boost end while boosted (server time)
	readyAt: number?, -- a finish earns the boost again (server time); nil = ready now
	sections: { string }, -- the current course's section names, in order
	rotatesAt: number, -- server time the next rotation starts
	run: { section: number, of: number, startedAt: number }?, -- the run in progress
	best: number?, -- best finish on the current course, seconds
}

local ObbyService = {}

ObbyService.OFF_COURSE = 40 -- studs past the course's ends or sides (course-local) that end a run
ObbyService.PORTAL_HEIGHT = 8 -- studs above the portal centre that still count as standing in it
ObbyService.RESET_JUMP = 20 -- studs back along the course in one tick, onto the start pad: the client put the runner back

local function clock(seconds: number): string
	local s = math.max(0, math.ceil(seconds))
	return string.format("%d:%02d", s // 60, s % 60)
end

local function runTime(seconds: number): string
	return string.format("%.1f s", seconds)
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
	session.obbyRun = { slot = course.slot, section = 0, startedAt = now, settleUntil = now + OBBY.MOVE_GRACE }
	World.markDirty(session)
	World.track(world, session.userId, { op = "event", name = "ObbyStarted" })
	local status = ObbyRules.phase(session.data, now)
	local hint = if status == "ready"
		then "Reach the finish for x1.5 income!"
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

local function finish(world: World, session: Session, run: World.ObbyRun, course: ObbyCourse.Course, now: number)
	local seconds = now - run.startedAt
	if seconds < OBBY.MIN_RUN_SECONDS then
		run.invalid = true
	end
	session.obbyRun = nil
	World.markDirty(session)
	local best = session.obbyBest
	local newBest = not run.invalid and (best == nil or best.slot ~= course.slot or seconds < best.seconds)
	if newBest then
		session.obbyBest = { slot = course.slot, seconds = seconds }
	end
	local earned = false
	if run.invalid then
		World.notify(world, session.userId, "That run didn't count. Try again!", "bad", nil)
	elseif ObbyRules.grant(session.data, now) then
		earned = true
		session.data.obbyBonus = OBBY.BONUS
		World.notify(
			world,
			session.userId,
			`Obby cleared in {runTime(seconds)}! x{1 + OBBY.BONUS} income for {math.floor(OBBY.BOOST_SECONDS / 60 + 0.5)} min`,
			"good",
			"BossMvp"
		)
	else
		local tail = if newBest then " New best!" else ""
		World.notify(
			world,
			session.userId,
			`Cleared in {runTime(seconds)}!{tail} Boost ready again in {clock(session.data.obbyReadyAt - now)}`,
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

-- One runner's tick. Returns the move the adapter must make, if any, and true when the client put the runner back
-- on the start pad after a fall.
local function progress(world: World, session: Session, place: Place, pos: Vec, now: number): (Move?, boolean)
	local run = session.obbyRun :: World.ObbyRun
	local course = world.obby
	if not course or run.slot ~= course.slot then
		ObbyService.cancel(session)
		return nil, false
	end
	if run.settleUntil and now < run.settleUntil then
		run.lastX = nil
		return nil, false -- the lift or respawn may not have reached the client yet
	end
	local p = ObbyCourse.toLocal(place.frame, pos)
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
	if p[2] < ObbyCourse.fallHeight(course, p, OBBY.FALL_DEPTH + OBBY.SERVER_FALL_SLACK) then
		trackFall(world, session, course, at)
		run.settleUntil = now + OBBY.MOVE_GRACE
		run.lastX = nil
		return worldMove(place, session.userId, course.start), false
	end
	if at == 0 and lastX and lastX - p[1] > ObbyService.RESET_JUMP then
		trackFall(world, session, course, ObbyCourse.sectionAt(course, { lastX, p[2], p[3] }))
		return nil, true
	end
	if at > run.section then
		if at > run.section + 1 then
			run.invalid = true -- got past a section without being over it
		end
		run.section = math.min(at, #course.spans)
		World.markDirty(session)
	end
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
	return {
		bonus = boost.bonus,
		endsAt = boost.endsAt,
		readyAt = boost.readyAt,
		sections = ObbyCourse.names(course.picks),
		rotatesAt = ObbyCourse.slotStart(ObbyCourse.slot(now) + 1),
		run = if run then { section = run.section, of = #course.spans, startedAt = run.startedAt } else nil,
		best = if best and best.slot == course.slot then best.seconds else nil,
	}
end

return ObbyService
