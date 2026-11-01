--!strict
--[[
	IdleRejoin (pure)

	Decides when an idle player is sent back into the game before Roblox's 20-minute idle kick. The adapter
	reports how long a player has been idle; `idled` answers true once that passes `rejoinAfter`, then waits
	`retryAfter` seconds before it answers true again, and stops after `maxTries` attempts. A report under
	`rejoinAfter` (the player was active again) or `forget` (they left) starts the count over.
]]

export type Options = {
	rejoinAfter: number?, -- idle seconds before the rejoin (default 18 minutes, Roblox kicks at 20)
	retryAfter: number?, -- seconds between attempts when a teleport did not happen (default 30)
	maxTries: number?, -- attempts per idle stretch (default 3)
}

type Attempt = { tries: number, last: number }

export type Tracker = {
	rejoinAfter: number,
	retryAfter: number,
	maxTries: number,
	attempts: { [any]: Attempt },
	idled: (self: Tracker, key: any, idleSeconds: number, now: number) -> boolean,
	forget: (self: Tracker, key: any) -> (),
}

local DEFAULTS = table.freeze({
	rejoinAfter = 18 * 60,
	retryAfter = 30,
	maxTries = 3,
})

local IdleRejoin = {}

-- True when `key` should be sent back into the game now. Counts the attempt.
local function idled(self: Tracker, key: any, idleSeconds: number, now: number): boolean
	if idleSeconds < self.rejoinAfter then
		self.attempts[key] = nil
		return false
	end
	local attempt = self.attempts[key]
	if attempt then
		if attempt.tries >= self.maxTries or now - attempt.last < self.retryAfter then
			return false
		end
		attempt.tries += 1
		attempt.last = now
	else
		self.attempts[key] = { tries = 1, last = now }
	end
	return true
end

local function forget(self: Tracker, key: any)
	self.attempts[key] = nil
end

function IdleRejoin.new(options: Options?): Tracker
	local o: Options = options or {}
	local rejoinAfter = o.rejoinAfter or DEFAULTS.rejoinAfter
	local retryAfter = o.retryAfter or DEFAULTS.retryAfter
	local maxTries = o.maxTries or DEFAULTS.maxTries
	if rejoinAfter <= 0 or retryAfter < 0 or maxTries < 1 then
		error("IdleRejoin.new: rejoinAfter > 0, retryAfter >= 0 and maxTries >= 1 are required", 2)
	end
	return {
		rejoinAfter = rejoinAfter,
		retryAfter = retryAfter,
		maxTries = maxTries,
		attempts = {},
		idled = idled,
		forget = forget,
	}
end

IdleRejoin.DEFAULTS = DEFAULTS

return table.freeze(IdleRejoin)
