--!strict
--[[
	BossMeterLogic (pure, contract/boss-event.md)

	What the boss card shows for `State.boss` at server time `now`, in as few words as possible: a band with the
	title and the time left, and one row under it with the goo meter (or a name, when there is no meter to show) and
	one pill saying what matters right now: your hits, "Dodge!", "Hits x3", the guards left, that you got hit, who
	grabs or carries it, the result. Nil = no card. Panels/BossMeter renders it; tests/ui/BossMeter.spec checks it.
]]

local Format = if script then require(script.Parent.Format) else require("./Format")

-- Band and ring colour: pink while you fight it, gold when it is your moment (dazed, down, won), muted when it
-- got away.
export type Tone = "fight" | "gold" | "mute"

-- Pill text colour: plain, gold (a bonus), pink (danger), mint (a fact to act on), muted.
export type PillTone = "plain" | "gold" | "pink" | "mint" | "muted"

export type View = {
	icon: string, -- on the jelly tile
	title: string, -- in the band
	timer: string?, -- "1:05" left in the phase; nil = none
	tone: Tone,
	meter: number?, -- 0..1 goo meter; nil = show `who` instead
	who: string?, -- a name or a short line where the meter goes
	pill: string,
	pillTone: PillTone,
}

local BossMeterLogic = {}

BossMeterLogic.ICON = "👑"

function BossMeterLogic.percent(x: number): number
	return math.floor(math.clamp(x, 0, 1) * 100 + 0.5)
end

local function live(boss: any, now: number): boolean
	return type(boss.moveEndsAt) ~= "number" or now < boss.moveEndsAt
end

-- The fight's pill: what the boss is doing to you, else your hits.
local function fightPill(boss: any, now: number): (string, PillTone, Tone)
	if type(boss.stunnedUntil) == "number" and now < boss.stunnedUntil then
		return `Ouch! {math.max(1, math.ceil(boss.stunnedUntil - now))}s`, "pink", "fight"
	end
	if live(boss, now) then
		if boss.move == "dazed" then
			return `Hits x{boss.multiplier or 3}`, "gold", "gold"
		elseif boss.move == "rise" then
			local left = if type(boss.guardsLeft) == "number" then boss.guardsLeft else 0
			local total = if type(boss.guardsTotal) == "number" then boss.guardsTotal else left
			return `Guards {left}/{total}`, "plain", "fight"
		elseif boss.move == "windup" or boss.move == "attack" then
			return "Dodge!", "pink", "fight"
		end
	end
	local points = if type(boss.yourPoints) == "number" then boss.yourPoints else 0
	if points > 0 then
		return `You {points}`, "plain", "fight"
	end
	return "Hit it!", "mint", "fight"
end

--[[
	`badgesBefore`: the player's boss badge count before this fight (the panel remembers it), so a win can say how
	many badges it brought; nil = unknown.
]]
function BossMeterLogic.view(boss: any, now: number, badgesBefore: number?): View?
	if type(boss) ~= "table" or type(boss.phase) ~= "string" then
		return nil
	end
	local name = if type(boss.name) == "string" then boss.name else "The boss"
	local left = Format.remainingSeconds(boss.endsAt, now)
	local timer = if type(boss.endsAt) == "number" then Format.formatDuration(left) else nil
	local meter = if type(boss.meter) == "number" then boss.meter else 0
	local phase = boss.phase
	local icon = BossMeterLogic.ICON
	if phase == "warning" then
		local result: View = {
			icon = icon,
			title = "BOSS INCOMING",
			timer = timer,
			tone = "fight",
			who = name,
			pill = "To the plaza",
			pillTone = "mint",
		}
		return result
	elseif phase == "fight" then
		local pill, pillTone, tone = fightPill(boss, now)
		local result: View = {
			icon = icon,
			title = name,
			timer = timer,
			tone = tone,
			meter = meter,
			pill = pill,
			pillTone = pillTone,
		}
		return result
	elseif phase == "haul" then
		local view: View = {
			icon = icon,
			title = `{name} is down!`,
			timer = timer,
			tone = "gold",
			who = "Grab it!",
			pill = "Carry it home",
			pillTone = "mint",
		}
		if type(boss.carrierName) == "string" then
			view.who = `{boss.carrierName} has it`
			view.pill, view.pillTone = "Bonk!", "pink"
		elseif type(boss.priorityName) == "string" then
			view.who = `{boss.priorityName} grabs first`
			view.pill = Format.formatDuration(Format.remainingSeconds(boss.priorityUntil, now))
		end
		return view
	elseif phase == "won" then
		local who = if type(boss.winnerName) == "string" then `{boss.winnerName} + team` else "The team"
		local gained = if type(badgesBefore) == "number" and type(boss.badges) == "number"
			then boss.badges - badgesBefore
			else 0
		local result: View = {
			icon = icon,
			title = "Brought home!",
			timer = nil,
			tone = "gold",
			who = who,
			pill = if gained > 0 then `+{gained} badge{if gained == 1 then "" else "s"}` else "Shared win",
			pillTone = "gold",
		}
		return result
	elseif phase == "failed" then
		local nextLeft = Format.remainingSeconds(boss.nextAt, now)
		local result: View = {
			icon = icon,
			title = `{name} got away`,
			timer = nil,
			tone = "mute",
			meter = meter,
			pill = if type(boss.nextAt) == "number" then `Next {Format.formatDuration(nextLeft)}` else "Next time!",
			pillTone = "muted",
		}
		return result
	end
	return nil
end

return table.freeze(BossMeterLogic)
