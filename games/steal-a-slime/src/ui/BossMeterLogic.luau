--!strict
--[[
	BossMeterLogic (pure, contract/boss-event.md)

	What the boss card shows for `State.boss` at server time `now`: the heads-up while the boss is on its way, the goo
	meter with your hits during the fight (or what the boss is doing: winding up, dazed, out of reach, or that it got
	you), who may grab or carries it in the haul, and the result. Nil = no card.
	Panels/BossMeter renders it; tests/ui/BossMeter.spec checks it.
]]

local Format = if script then require(script.Parent.Format) else require("./Format")

export type Tone = "warn" | "fight" | "haul" | "good" | "bad"

export type View = {
	icon: string, -- emoji on the card's tile
	title: string,
	detail: string,
	meter: number, -- 0..1 bar fill
	timer: string?, -- "1:05" left in the phase; nil = none
	tone: Tone,
}

local BossMeterLogic = {}

local function percent(x: number): number
	return math.floor(math.clamp(x, 0, 1) * 100 + 0.5)
end

function BossMeterLogic.view(boss: any, now: number): View?
	if type(boss) ~= "table" or type(boss.phase) ~= "string" then
		return nil
	end
	local name = if type(boss.name) == "string" then boss.name else "The boss"
	local left = Format.remainingSeconds(boss.endsAt, now)
	local timer = if type(boss.endsAt) == "number" then Format.formatDuration(left) else nil
	local meter = if type(boss.meter) == "number" then boss.meter else 0
	local points = if type(boss.yourPoints) == "number" then boss.yourPoints else 0
	local phase = boss.phase
	if phase == "warning" then
		return {
			icon = "👑",
			title = `BOSS INCOMING: {name}`,
			detail = "Head to the plaza and grab your bat!",
			meter = 0,
			timer = timer,
			tone = "warn",
		}
	elseif phase == "fight" then
		local yours = if points > 0
			then `Your hits: {points} ({percent(boss.yourShare or 0)}% of the top helper)`
			else "Hit it with your bat to fill the goo meter!"
		-- What the boss is doing right now beats the running total: you were hit, it is open, or it is about to strike.
		local moveLive = type(boss.moveEndsAt) ~= "number" or now < boss.moveEndsAt
		if type(boss.stunnedUntil) == "number" and now < boss.stunnedUntil then
			yours = "You got hit! Your bat is back in a moment."
		elseif moveLive and boss.move == "dazed" then
			yours = `DAZED! Every hit counts x{boss.multiplier or 3}. Go go go!`
		elseif moveLive and boss.move == "rise" then
			local guards = if type(boss.guardsLeft) == "number" then boss.guardsLeft else 0
			yours = `It's out of reach! Bonk its guards: {guards} left.`
		elseif moveLive and (boss.move == "windup" or boss.move == "attack") then
			yours = "Watch out! Get out of the red!"
		end
		return {
			icon = "👑",
			title = `{name}: goo meter {percent(meter)}%`,
			detail = yours,
			meter = meter,
			timer = timer,
			tone = "fight",
		}
	elseif phase == "haul" then
		local detail = if type(boss.carrierName) == "string"
			then `{boss.carrierName} is carrying it! Bonk them to make them drop it!`
			elseif type(boss.priorityName) == "string" then `{boss.priorityName} grabs first, then anyone!`
			else "It's down! Grab it and carry it home!"
		return { icon = "👑", title = `{name} is down!`, detail = detail, meter = 1, timer = timer, tone = "haul" }
	elseif phase == "won" then
		local who = if type(boss.winnerName) == "string" then boss.winnerName else "Someone"
		return {
			icon = "🏆",
			title = `{who} brought {name} home!`,
			detail = "It's on their trophy stand now.",
			meter = 1,
			timer = nil,
			tone = "good",
		}
	elseif phase == "failed" then
		return {
			icon = "💨",
			title = `{name} got away!`,
			detail = "Better luck with the next one!",
			meter = meter,
			timer = nil,
			tone = "bad",
		}
	end
	return nil
end

return table.freeze(BossMeterLogic)
