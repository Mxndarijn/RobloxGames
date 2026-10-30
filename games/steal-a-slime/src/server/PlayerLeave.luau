--!strict
--[[
	PlayerLeave (pure)

	A leaving player's teardown, in order: Sessions.leave (a stolen slime bounces home, the plot frees), the
	final save that releases the session lock, then the per-player cleanup steps and a view refresh. The save
	starts before anything that can fail, and every other step runs through `safeCall`, so one that throws is
	logged and the rest still run: the session always leaves the World and the save always runs. A session
	left behind would have its lock refreshed by autosave and keep the player out of every other server.
	PlayerLifecycle passes the Roblox side (caches, views, Persistence.save) as `Hooks`.
]]

local Lib = if script then (game:GetService("ReplicatedStorage") :: any).Lib else nil
local SafeCall = if Lib then require(Lib.core.SafeCall) else require("../../../../shared/luau/src/core/SafeCall")
local Sessions = if script then require(script.Parent.Sessions) else require("./Sessions")
local World = if script then require(script.Parent.World) else require("./World")

type Session = World.Session

export type Step = { name: string, run: () -> () }

export type Hooks = {
	safeCall: SafeCall.Call,
	cleanup: { Step }, -- per-player caches and views, run in order after Sessions.leave
	refreshView: (now: number) -> (),
	save: (session: Session) -> (), -- the final save; releases the session lock (must not yield the caller)
}

local PlayerLeave = {}

-- Returns the session that left, or nil when `userId` had none (cleanup still runs, nothing is saved).
function PlayerLeave.run(world: World.World, userId: number, now: number, hooks: Hooks): Session?
	local safeCall = hooks.safeCall
	local session = Sessions.leave(world, userId, now, safeCall)
	if session then
		hooks.save(session) -- first: the save must not depend on any step below
	end
	for _, step in hooks.cleanup do
		safeCall(step.name, step.run)
	end
	if session then
		safeCall("refreshView after leave", hooks.refreshView, now) -- a stolen slime in their arms bounces home
	end
	return session
end

return PlayerLeave
