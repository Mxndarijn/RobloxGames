--!strict
--[[
	DespawnTelegraph (pure, FEATURES.DespawnTelegraph)

	Timing for the wild slime despawn warning. A wild slime still lives until
	`expiresAt` (WILD_LIFETIME / BOSS_LIFETIME after it spawned); for the last
	DESPAWN_TELEGRAPH_SECONDS before that its model carries the attribute
	DespawnAt (Constants.DESPAWN_AT_ATTRIBUTE) = expiresAt, in server time.

	The client shows the countdown from
	  DespawnTelegraph.countdownSeconds(workspace:GetServerTimeNow(), DespawnAt)
	and plays the blink / shrink / poof. The server never removes early: it
	removes only once shouldRemove(now, expiresAt) is true.

	No Roblox APIs at load time.
]]

local DespawnTelegraph = {}

-- Server time the warning begins.
function DespawnTelegraph.warnStartsAt(expiresAt: number, warnSeconds: number): number
	return expiresAt - warnSeconds
end

-- True from warnStartsAt (inclusive) up to expiresAt (exclusive).
function DespawnTelegraph.inWarnWindow(now: number, expiresAt: number, warnSeconds: number): boolean
	return now >= DespawnTelegraph.warnStartsAt(expiresAt, warnSeconds) and now < expiresAt
end

-- Value of the DespawnAt model attribute: expiresAt inside the warn window
-- when enabled, else nil (attribute cleared).
function DespawnTelegraph.attributeValue(now: number, expiresAt: number, warnSeconds: number, enabled: boolean): number?
	if enabled and DespawnTelegraph.inWarnWindow(now, expiresAt, warnSeconds) then
		return expiresAt
	end
	return nil
end

-- The server removes the wild slime only at expiresAt.
function DespawnTelegraph.shouldRemove(now: number, expiresAt: number): boolean
	return now >= expiresAt
end

-- Whole seconds to show on the countdown ("5", "4", ... "1"), 0 once due.
function DespawnTelegraph.countdownSeconds(now: number, despawnAt: number): number
	return math.max(0, math.ceil(despawnAt - now))
end

-- 0 at the start of the window, 1 at despawnAt (drives blink rate / shrink).
function DespawnTelegraph.progress(now: number, despawnAt: number, warnSeconds: number): number
	if warnSeconds <= 0 then
		return 1
	end
	return math.clamp(1 - (despawnAt - now) / warnSeconds, 0, 1)
end

return DespawnTelegraph
