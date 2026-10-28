--!strict
--[[
	StealAlert (pure, FEATURES.StealAlerts, CONTRACT.md §17)

	The maths and text behind the v21 full steal alerts. No Roblox APIs; the
	client adapter is ui/StealAlertFx.

	* Direction: `bearing` turns two ground positions and the camera's look
	  vector into an angle (0 = ahead, clockwise positive) and a distance.
	  The on-screen arrow itself is shared/EdgeArrow.
	* Flash: `flashAlpha` is the red edge flash's opacity over time (pulses).
	* Alarm: `alarmDue` says when the toast's first Alarm should sound again.
	* Log: `record` appends a completed theft to the owner's saved `stealLog`
	  (capped); `clean` sanitizes a loaded one; `summary` is the join notice.
]]

local Config = if script then require(script.Parent.Config) else require("./Config")

export type Entry = { thief: string, slime: string, at: number }
export type Vec2 = { x: number, z: number }

local StealAlert = {}

function StealAlert.enabled(): boolean
	return Config.FEATURES.StealAlerts == true
end

---------------------------------------------------------------------------
-- Direction
---------------------------------------------------------------------------

-- Angle (radians) from the camera's look direction to `target` on the XZ plane, 0 = straight
-- ahead and positive = to the right (clockwise seen from above), in (-pi, pi]; plus the distance.
-- A look vector with no horizontal part (straight up / down) counts as +Z-ahead.
function StealAlert.bearing(origin: Vec2, target: Vec2, look: Vec2): (number, number)
	local dx, dz = target.x - origin.x, target.z - origin.z
	local distance = math.sqrt(dx * dx + dz * dz)
	local lx, lz = look.x, look.z
	local flat = math.sqrt(lx * lx + lz * lz)
	if flat < 1e-4 then
		lx, lz = 0, -1
	else
		lx, lz = lx / flat, lz / flat
	end
	if distance < 1e-4 then
		return 0, 0
	end
	-- Roblox: camera right = look x up = (-lz, lx) on the XZ plane.
	local forward = dx * lx + dz * lz
	local right = dx * -lz + dz * lx
	-- right is the sine side of the angle: atan2(right, forward) is clockwise-positive from above.
	return math.atan2(right, forward), distance
end

---------------------------------------------------------------------------
-- Flash and alarm
---------------------------------------------------------------------------

-- Opacity 0..1 of the red edge flash `t` seconds after the theft began: FLASH_PULSES half-sine
-- pulses over FLASH_SECONDS, then nothing. Peaks at 0.55 so the screen stays readable.
function StealAlert.flashAlpha(t: number): number
	local cfg = Config.STEAL_ALERT
	if t ~= t or t < 0 or t >= cfg.FLASH_SECONDS then
		return 0
	end
	local pulse = math.abs(math.sin(math.pi * cfg.FLASH_PULSES * t / cfg.FLASH_SECONDS))
	return 0.55 * pulse
end

-- How many repeat alarms are owed `t` seconds into a theft (0 .. ALARM_REPEATS); the first
-- Alarm comes with the server's toast, so repeat k sounds at k * ALARM_REPEAT.
function StealAlert.alarmDue(t: number): number
	local cfg = Config.STEAL_ALERT
	if t ~= t or t < 0 then
		return 0
	end
	return math.min(cfg.ALARM_REPEATS, math.floor(t / cfg.ALARM_REPEAT))
end

-- Everyone carrying one of my slimes away (State `slimes[i].stolenBy`), each once, in slime order. The
-- owner's client outlines each of them in red until they are done (ui/StealAlertFx).
function StealAlert.thieves(slimes: { any }?): { number }
	local out: { number } = {}
	local seen: { [number]: boolean } = {}
	if slimes == nil then
		return out
	end
	for _, view in slimes do
		local id = if type(view) == "table" then view.stolenBy else nil
		if type(id) == "number" and not seen[id] then
			seen[id] = true
			table.insert(out, id)
		end
	end
	return out
end

---------------------------------------------------------------------------
-- Saved steal log and the join notice
---------------------------------------------------------------------------

local function cleanName(value: any, fallback: string): string
	if type(value) ~= "string" then
		return fallback
	end
	local text = string.gsub(value, "[%c]", "")
	text = string.sub(text, 1, Config.STEAL_ALERT.NAME_MAX)
	if text == "" then
		return fallback
	end
	return text
end

-- Untrusted saved value -> a clean, capped list (oldest first). Never errors.
function StealAlert.clean(raw: any): { Entry }
	local out: { Entry } = {}
	if type(raw) ~= "table" then
		return out
	end
	for _, item in raw do
		if type(item) == "table" then
			local at = tonumber(item.at)
			table.insert(out, {
				thief = cleanName(item.thief, "someone"),
				slime = cleanName(item.slime, "slime"),
				at = if at and at == at then math.clamp(math.floor(at), 0, 1e11) else 0,
			})
		end
	end
	local cap = Config.STEAL_ALERT.LOG_CAP
	while #out > cap do
		table.remove(out, 1)
	end
	return out
end

-- Appends a finished theft to `log` (mutates), dropping the oldest past LOG_CAP.
function StealAlert.record(log: { Entry }, thief: string, slime: string, at: number)
	table.insert(log, { thief = cleanName(thief, "someone"), slime = cleanName(slime, "slime"), at = math.floor(at) })
	while #log > Config.STEAL_ALERT.LOG_CAP do
		table.remove(log, 1)
	end
end

-- The join notice for the thefts saved since the last visit, nil when there are none.
-- "While you were away 3 slimes were stolen by Ann, Bob and 1 more." (thieves by most
-- recent first, each once; SUMMARY_NAMES shown).
function StealAlert.summary(log: { Entry }?): string?
	if log == nil or #log == 0 then
		return nil
	end
	local seen: { [string]: boolean } = {}
	local names: { string } = {}
	for i = #log, 1, -1 do
		local thief = log[i].thief
		if not seen[thief] then
			seen[thief] = true
			table.insert(names, thief)
		end
	end
	local shown = math.min(#names, Config.STEAL_ALERT.SUMMARY_NAMES)
	local list = table.concat(names, ", ", 1, shown)
	local rest = #names - shown
	if rest > 0 then
		list = `{list} and {rest} more`
	elseif shown > 1 then
		list = `{table.concat(names, ", ", 1, shown - 1)} and {names[shown]}`
	end
	local count = #log
	return `While you were away {count} {if count == 1 then "slime was" else "slimes were"} stolen by {list}.`
end

return StealAlert
