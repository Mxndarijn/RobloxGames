--!strict
--[[
	ObbyRules (pure, contract/obby.md)

	The Obby boost over three saved values on PlayerData: `obbyUntil` (the boost ends), `obbyReadyAt` (a run earns
	the boost again: the end of the boost plus Config.OBBY.COOLDOWN_SECONDS; both 0 = never earned) and `obbyEarned`
	(the income bonus the boost gives). Each section a run clears adds an equal share (`share`: OBBY.BONUS over the
	course's sections, so a full clear gives +OBBY.BONUS) and starts BOOST_SECONDS again (`earn`). A run that starts
	while the boost is on or cooling down earns nothing, but still counts as a run (time, best). Also the course
	board's shared text: run times in tenths (`tenths`, `timeText`), the course number and ranks.
]]

local Config = if script then require(script.Parent.Config) else require("./Config")
local Lib = if script then (game:GetService("ReplicatedStorage") :: any).Lib else nil
local Localize = if Lib then require(Lib.locale.Localize) else require("../../../../shared/luau/src/locale/Localize")

local OBBY = Config.OBBY

-- The fields ObbyRules reads and writes (a PlayerData.Data satisfies it).
export type Timers = { obbyUntil: number, obbyReadyAt: number, obbyEarned: number }

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
	return if now < data.obbyUntil and data.obbyEarned > 0 then data.obbyEarned else nil
end

-- One section's share of the full clear's bonus on a course of `sections` sections.
function ObbyRules.share(sections: number): number
	return OBBY.BONUS / math.max(1, sections)
end

--[[
	The best run counts. `total` is what this run's cleared sections are worth so far (its shares added up); returns
	true when the boost changed. While the boost is ready the run's total starts it; while it runs the total raises
	it only when it beats what the boost gives already (a run that clears fewer sections adds nothing, so re-entering
	can't farm it, and finishing the whole course always ends on the full bonus); while it cools down nothing. When it
	lands, the boost runs BOOST_SECONDS from now and the cooldown after it; the bonus never passes OBBY.BONUS.
]]
function ObbyRules.earn(data: Timers, now: number, total: number): boolean
	local phase = ObbyRules.phase(data, now)
	if phase == "cooling" then
		return false
	end
	local bonus = if total > OBBY.BONUS - 1e-9 then OBBY.BONUS else math.max(0, total) -- the last share lands on the full bonus
	if bonus <= 0 or (phase == "boosted" and bonus <= data.obbyEarned + 1e-9) then
		return false
	end
	data.obbyEarned = bonus
	data.obbyUntil = now + OBBY.BOOST_SECONDS
	data.obbyReadyAt = data.obbyUntil + OBBY.COOLDOWN_SECONDS
	return true
end

-- A full clear in one go (every share at once): returns true when the boost changed.
function ObbyRules.grant(data: Timers, now: number): boolean
	return ObbyRules.earn(data, now, OBBY.BONUS)
end

-- State.obby's boost part: `bonus` = the bonus running now while boosted, else what a full clear earns.
function ObbyRules.view(data: Timers, now: number): View
	local phase = ObbyRules.phase(data, now)
	return {
		bonus = if phase == "boosted" then data.obbyEarned else OBBY.BONUS,
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

-- "Course #1,204" for a course number (courseNumber), as a Localize message.
function ObbyRules.courseMessage(number: number): Localize.Message
	local text = tostring(math.max(0, math.floor(number)))
	local count
	repeat
		text, count = string.gsub(text, "^(%d+)(%d%d%d)", "%1,%2")
	until count == 0
	return Localize.msg("world.obby.course", { number = text })
end

-- The English of ObbyRules.courseMessage.
function ObbyRules.courseLabel(number: number): string
	local TaggedText = if script then require(script.Parent.TaggedText) :: any else require("./TaggedText") :: any
	return TaggedText.english(ObbyRules.courseMessage(number))
end

-- "#23"; past OBBY.BOARD.RANK_DEPTH "#100+"; nil without a rank.
function ObbyRules.rankText(rank: number?): string?
	if type(rank) ~= "number" or rank < 1 then
		return nil
	end
	local depth = OBBY.BOARD.RANK_DEPTH
	return if rank > depth then `#{depth}+` else `#{math.floor(rank)}`
end

-- Cleans saved timers: numbers in a sane range, the ready time never before the boost end, the bonus within
-- 0..OBBY.BONUS; junk -> 0. A boost saved without its bonus counts as a full clear.
function ObbyRules.clean(raw: any): Timers
	local function num(v: any): number
		return if type(v) == "number" and v == v and v >= 0 and v <= 1e11 then v else 0
	end
	local t = if type(raw) == "table" then raw else {}
	local untilAt = num(t.untilAt)
	local earned = if t.bonus == nil and untilAt > 0 then OBBY.BONUS else math.min(num(t.bonus), OBBY.BONUS)
	return { obbyUntil = untilAt, obbyReadyAt = math.max(num(t.readyAt), untilAt), obbyEarned = earned }
end

return table.freeze(ObbyRules)
