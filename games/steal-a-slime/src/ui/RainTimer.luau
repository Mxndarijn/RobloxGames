--!strict
--[[
	RainTimer

	Slime Rain banner text for the HUD. Prefers the workspace attributes
	`RainActive` / `RainEndsAt` / `RainNextAt` (CONTRACT §5.2, server time),
	falls back to `State.rain` (§5.1). Pure (tests/ui/RainTimer.spec.luau);
	Hud reads the attributes and passes them in.

	The attribute names aren't in Constants yet (docs/archive/UI-CONTRACT-GAPS.md), so
	they live here.
]]

local Format = if script then require(script.Parent.Format) else require("./Format")

export type Rain = { active: boolean, endsAt: number?, nextAt: number? }
export type Banner = { text: string, kind: "active" | "soon" }

local RainTimer = {}

RainTimer.ATTRIBUTES = table.freeze({ "RainActive", "RainEndsAt", "RainNextAt" })

-- Show "Slime Rain in m:ss" once the next rain is this close.
RainTimer.SOON_SECONDS = 600

local function num(value: any): number?
	return if type(value) == "number" then value else nil
end

-- nil when the server hasn't set `RainActive` (older server / not replicated yet).
function RainTimer.fromAttributes(active: any, endsAt: any, nextAt: any): Rain?
	if type(active) ~= "boolean" then
		return nil
	end
	return { active = active, endsAt = num(endsAt), nextAt = num(nextAt) }
end

function RainTimer.resolve(attributes: Rain?, stateRain: any): Rain?
	if attributes then
		return attributes
	end
	if type(stateRain) == "table" and type(stateRain.active) == "boolean" then
		return { active = stateRain.active, endsAt = num(stateRain.endsAt), nextAt = num(stateRain.nextAt) }
	end
	return nil
end

-- Banner for `rain` at server time `now`, or nil to hide it.
function RainTimer.banner(rain: Rain?, now: number, luck: number): Banner?
	if rain == nil then
		return nil
	end
	if rain.active then
		local left = if rain.endsAt
			then ` - {Format.formatDuration(Format.remainingSeconds(rain.endsAt, now))} left`
			else ""
		return { text = `SLIME RAIN! Luck x{luck}{left}`, kind = "active" }
	end
	if rain.nextAt then
		local wait = Format.remainingSeconds(rain.nextAt, now)
		if wait > 0 and wait <= RainTimer.SOON_SECONDS then
			return { text = `Slime Rain in {Format.formatDuration(wait)}`, kind = "soon" }
		end
	end
	return nil
end

return table.freeze(RainTimer)
