--!strict
--[[
	NextSpawn

	HUD chip text for the next scheduled event: the sooner of the next Slime
	Rain (workspace `RainNextAt`) and the next Boss Slime (workspace
	`BossNextAt`), both server times, so a late joiner sees the same countdown.
	Hidden while it is raining (the rain banner owns that) and while no time is
	known or both are over. Pure (tests/ui/NextSpawn.spec.luau).
]]

local Format = if script then require(script.Parent.Format) else require("./Format")

export type Kind = "rain" | "boss"
export type Info = { kind: Kind, seconds: number, text: string }

local NextSpawn = {}

NextSpawn.ATTRIBUTES = table.freeze({ "RainActive", "RainNextAt", "BossNextAt" })
NextSpawn.ICONS = table.freeze({ rain = "🌧", boss = "👑" })
NextSpawn.NAMES = table.freeze({ rain = "Slime Rain", boss = "Boss Slime" })

local function num(value: any): number?
	return if type(value) == "number" and value == value then value else nil
end

-- Soonest future event, or nil to hide the chip.
function NextSpawn.chip(rainActive: any, rainNextAt: any, bossNextAt: any, now: number): Info?
	if rainActive == true then
		return nil
	end
	local best: Kind? = nil
	local bestWait = math.huge
	for kind, at in { rain = num(rainNextAt), boss = num(bossNextAt) } do
		local wait = if at then Format.remainingSeconds(at, now) else 0
		if wait > 0 and wait < bestWait then
			best, bestWait = kind :: Kind, wait
		end
	end
	if best == nil then
		return nil
	end
	local text = `{NextSpawn.ICONS[best]} {NextSpawn.NAMES[best]} in {Format.formatDuration(bestWait)}`
	return { kind = best, seconds = bestWait, text = text }
end

-- The chip hides behind any open menu, like every banner (MenuState.bannersVisible).
function NextSpawn.visible(info: Info?, openKey: string?): boolean
	return info ~= nil and openKey == nil
end

return table.freeze(NextSpawn)
