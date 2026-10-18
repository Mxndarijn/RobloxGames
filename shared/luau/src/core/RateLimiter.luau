--!strict
--[[
	RateLimiter: minimum gap between calls of one action by one key (usually a player id).

		local limiter = RateLimiter.new({ Buy = 0.25, Sync = 1 }, 0.1)
		if limiter:allow(userId, "Buy", now) then ... end
		limiter:forget(userId) -- on leave

	`gaps[action]` is the minimum number of seconds between two allowed calls; actions without an entry use
	`default` (no limit when it is nil). A refused call does not reset the gap. The clock is passed in as `now`.
]]

export type RateLimiter = {
	gaps: { [string]: number },
	default: number?,
	last: { [any]: { [string]: number } },
	allow: (self: RateLimiter, key: any, action: string, now: number) -> boolean,
	forget: (self: RateLimiter, key: any) -> (),
	reset: (self: RateLimiter) -> (),
}

local RateLimiter = {}
RateLimiter.__index = RateLimiter

function RateLimiter.new(gaps: { [string]: number }?, default: number?): RateLimiter
	local copy: { [string]: number } = {}
	local source: { [string]: number } = gaps or {}
	for action, gap in source do
		if type(action) ~= "string" or type(gap) ~= "number" or gap ~= gap then
			error(`RateLimiter.new: gap for {tostring(action)} must be a number`, 2)
		end
		copy[action] = gap
	end
	if default ~= nil and (type(default) ~= "number" or default ~= default) then
		error("RateLimiter.new: default must be a number or nil", 2)
	end
	local self = setmetatable({ gaps = table.freeze(copy), default = default, last = {} }, RateLimiter)
	return (self :: any) :: RateLimiter
end

-- True (and records the call) when at least the action's gap has passed since this key's last allowed call.
function RateLimiter.allow(self: RateLimiter, key: any, action: string, now: number): boolean
	local gap = self.gaps[action] or self.default
	if gap == nil or gap <= 0 then
		return true
	end
	local perKey = self.last[key]
	if perKey == nil then
		perKey = {}
		self.last[key] = perKey
	end
	local last = perKey[action]
	if last ~= nil and now - last < gap then
		return false
	end
	perKey[action] = now
	return true
end

-- Drops everything remembered for `key`.
function RateLimiter.forget(self: RateLimiter, key: any)
	self.last[key] = nil
end

-- Drops everything remembered for every key.
function RateLimiter.reset(self: RateLimiter)
	table.clear(self.last)
end

return table.freeze(RateLimiter)
