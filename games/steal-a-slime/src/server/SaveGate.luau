--!strict
--[[
	SaveGate (pure, DataService and clock injected)

	Counts the loads and saves in flight so a closing server can wait for all of them, and makes sure no
	session lock outlives the server:
	  * `load` takes the lock through DataService.load. A load that finishes after the player left, or after
	    `close`, releases the lock at once with a counted save and hands back no data.
	  * `track` runs one save and counts it in `pending` while it runs.
	  * `close` marks the server as closing; `wait` yields until no load or save is in flight or the timeout
	    passes.
]]

local Shared = if script then (game:GetService("ReplicatedStorage") :: any).Shared else nil
local DataService = if script then require(script.Parent.DataService) else require("./DataService")
local PlayerData = if Shared then require(Shared.PlayerData) else require("../shared/PlayerData")

export type Context = {
	clock: () -> number, -- seconds, for the shutdown timeout
	wait: (seconds: number) -> (),
}

export type Gate = {
	ctx: Context,
	pending: number, -- saves in flight
	loading: number, -- loads in flight
	closing: boolean,
}

local SaveGate = {}

local POLL = 0.1 -- seconds between checks while waiting

function SaveGate.new(ctx: Context): Gate
	return { ctx = ctx, pending = 0, loading = 0, closing = false }
end

-- Runs `save` (which may yield) counted in `pending`.
function SaveGate.track(gate: Gate, save: () -> ())
	gate.pending += 1
	local ok, err = pcall(save)
	gate.pending -= 1
	if not ok then
		error(err, 0)
	end
end

--[[
	Loads `userId`'s save. Returns (true, data) when the player may join, else (false, reason). `present()` says
	whether the player is still in the server; for one who left, or once the server is closing, the lock is
	released at once (reason "left" / "closing").
]]
function SaveGate.load(
	gate: Gate,
	service: DataService.DataService,
	userId: number,
	present: () -> boolean
): (boolean, PlayerData.Data | string)
	if gate.closing then
		return false, "closing"
	end
	gate.loading += 1
	local ok, result = DataService.load(service, userId)
	if ok and (gate.closing or not present()) then
		-- Counted before the load stops counting, so a waiting shutdown never sees zero in between.
		SaveGate.track(gate, function()
			gate.loading -= 1
			DataService.save(service, userId, result :: PlayerData.Data, true)
		end)
		return false, if gate.closing then "closing" else "left"
	end
	gate.loading -= 1
	return ok, result
end

-- From now on, loads that finish release their lock instead of joining.
function SaveGate.close(gate: Gate)
	gate.closing = true
end

-- True while a load or save is in flight.
function SaveGate.busy(gate: Gate): boolean
	return gate.pending > 0 or gate.loading > 0
end

-- Yields until no load or save is in flight or `timeout` seconds pass.
function SaveGate.wait(gate: Gate, timeout: number)
	local deadline = gate.ctx.clock() + timeout
	while SaveGate.busy(gate) and gate.ctx.clock() < deadline do
		gate.ctx.wait(POLL)
	end
end

return SaveGate
