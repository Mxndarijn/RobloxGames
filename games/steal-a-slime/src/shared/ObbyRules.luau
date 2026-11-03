--!strict
--[[
	ObbyRules (pure, contract/obby.md)

	The Obby boost over two saved server times on PlayerData: `obbyUntil` (the boost ends) and
	`obbyReadyAt` (a finish earns the boost again: the end of the boost plus Config.OBBY.COOLDOWN_SECONDS). Both 0 =
	never earned. A finish while not ready still counts as a run (time, best) but earns nothing. Also the course
	board's shared text: run times in tenths (`tenths`, `timeText`), the course number and ranks.
]]

local Config = if script then require(script.Parent.Config) else require("./Config")

local OBBY = Config.OBBY

-- The fields ObbyRules reads and writes (a PlayerData.Data satisfies it).
export type Timers = { obbyUntil: number, obbyReadyAt: number }

export type Phase = "ready" | "boosted" | "cooling"

-- State.obby's boost part: `endsAt` while boosted, `readyAt` while boosted or cooling down (server time).
export type View = { bonus: number, endsAt: number?, readyAt: number? }

local ObbyRules = {}

function ObbyRules.phase(data: Timers, now: number): Phase
	if now < data.obbyUntil then
		return "boosted"
	elseif now < data.obbyReadyAt then
		return "cooling"
	end
	return "ready"
end

function ObbyRules.ready(data: Timers, now: number): boolean
	return ObbyRules.phase(data, now) == "ready"
end

-- The income bonus right now (Perks reads it as data.obbyBonus); nil when not boosted.
function ObbyRules.bonus(data: Timers, now: number): number?
	return if now < data.obbyUntil then OBBY.BONUS else nil
end

-- A finish earns the boost: returns true when it did (the player was ready).
function ObbyRules.grant(data: Timers, now: number): boolean
	if not ObbyRules.ready(data, now) then
		return false
	end
	data.obbyUntil = now + OBBY.BOOST_SECONDS
	data.obbyReadyAt = data.obbyUntil + OBBY.COOLDOWN_SECONDS
	return true
end

function ObbyRules.view(data: Timers, now: number): View
	local phase = ObbyRules.phase(data, now)
	return {
		bonus = OBBY.BONUS,
		endsAt = if phase == "boosted" then data.obbyUntil else nil,
		readyAt = if phase ~= "ready" then data.obbyReadyAt else nil,
	}
end

-- A run's seconds as the board keeps them: whole tenths (the server times runs at its 0.1 s tick).
function ObbyRules.tenths(seconds: number): number
	if type(seconds) ~= "number" or seconds ~= seconds or seconds < 0 then
		return 0
	end
	return math.floor(seconds * 10 + 0.5)
end

-- Tenths as the board and the run card show them: "0:42.3".
function ObbyRules.timeText(tenths: number): string
	local t = math.max(0, math.floor(tenths))
	return string.format("%d:%02d.%d", t // 600, (t // 10) % 60, t % 10)
end

-- The course number players see ("Course #1,204"): rotations since OBBY.COURSE_EPOCH, from 1.
function ObbyRules.courseNumber(slot: number): number
	return math.max(1, slot - OBBY.COURSE_EPOCH + 1)
end

-- "Course #1,204" for a course number (courseNumber).
function ObbyRules.courseLabel(number: number): string
	local text = tostring(math.max(0, math.floor(number)))
	local count
	repeat
		text, count = string.gsub(text, "^(%d+)(%d%d%d)", "%1,%2")
	until count == 0
	return `Course #{text}`
end

-- "#23"; past OBBY.BOARD.RANK_DEPTH "#100+"; nil without a rank.
function ObbyRules.rankText(rank: number?): string?
	if type(rank) ~= "number" or rank < 1 then
		return nil
	end
	local depth = OBBY.BOARD.RANK_DEPTH
	return if rank > depth then `#{depth}+` else `#{math.floor(rank)}`
end

-- Cleans saved timers: numbers in a sane range, the ready time never before the boost end; junk -> 0.
function ObbyRules.clean(raw: any): Timers
	local function num(v: any): number
		return if type(v) == "number" and v == v and v >= 0 and v <= 1e11 then v else 0
	end
	local t = if type(raw) == "table" then raw else {}
	local untilAt = num(t.untilAt)
	return { obbyUntil = untilAt, obbyReadyAt = math.max(num(t.readyAt), untilAt) }
end

return table.freeze(ObbyRules)
