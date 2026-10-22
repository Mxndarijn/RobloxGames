--!strict
--[[
	Sessions (pure)

	Player lifecycle on the World: `join` assigns the lowest free plot, locks
	it for JOIN_LOCK_SECONDS and pays capped offline income; `leave` ends any
	carry (a stolen slime bounces home), drops carries of the leaver's slimes
	and frees the plot. Each of those steps runs through `safeCall`: one that
	throws is logged and the session still leaves the World, so its save lock
	is released and not kept fresh by autosave. Loading and saving data is
	DataService's job.
]]

local Shared = if script then (game:GetService("ReplicatedStorage") :: any).Shared else nil
local Codes = if Shared then require(Shared.Codes) else require("../shared/Codes")
local Config = if Shared then require(Shared.Config) else require("../shared/Config")
local PlayerData = if Shared then require(Shared.PlayerData) else require("../shared/PlayerData")
local Steal = if Shared then require(Shared.Steal) else require("../shared/Steal")
local Carry = if script then require(script.Parent.Carry) else require("./Carry")
local SafeCall = if script then require(script.Parent.SafeCall) else require("./SafeCall")
local PvpService = if script then require(script.Parent.PvpService) else require("./PvpService")
local Income = if script then require(script.Parent.Income) else require("./Income")
local Milestones = if script then require(script.Parent.Milestones) else require("./Milestones")
local World = if script then require(script.Parent.World) else require("./World")

type World = World.World
type Session = World.Session

local Sessions = {}

local printCall = SafeCall.new(print)

function Sessions.join(
	world: World,
	userId: number,
	name: string,
	data: PlayerData.Data,
	now: number
): (Session?, string?)
	if world.sessions[userId] then
		return world.sessions[userId], nil
	end
	local plotIndex = World.freePlot(world)
	if not plotIndex then
		return nil, "server is full"
	end
	local session: Session = {
		userId = userId,
		name = name,
		plotIndex = plotIndex,
		data = data,
		lockUntil = Steal.joinLockUntil(now),
		lockStartedAt = now,
		locked = true,
		limiter = {},
		carry = nil,
		lastSlapAt = -math.huge,
		incomeRemainder = 0,
		dirty = true,
		lastPushAt = -math.huge,
	}
	world.plots[plotIndex] = userId
	world.sessions[userId] = session
	if Config.FEATURES.StealAlerts then
		-- Thefts saved since the last visit become this join's notice; the saved log starts empty again.
		session.awayLog = data.stealLog
		data.stealLog = {}
	end
	PvpService.join(world, session, now)
	Codes.expireBoost(session.data, now) -- a boost never pays for time spent offline
	Income.applyOffline(world, session, now)
	Milestones.check(world, session, now) -- old saves get past goal stages / dex milestones now
	return session, nil
end

-- Returns the leaving session (so the caller can save its data) or nil. `safeCall` (default: log with print)
-- isolates each leave step, so a step that throws never keeps the session in the World.
function Sessions.leave(world: World, userId: number, now: number, safeCall: SafeCall.Call?): Session?
	local session = world.sessions[userId]
	if not session then
		return nil
	end
	local call = safeCall or printCall
	call("Carry.release on leave", Carry.release, world, userId, now, nil, "left")
	call("PvpService.leave", PvpService.leave, world, session, now)
	world.sessions[userId] = nil
	if world.plots[session.plotIndex] == userId then
		world.plots[session.plotIndex] = nil
	end
	for _, slime in session.data.slimes do
		world.escaping[slime.id] = nil
	end
	call("Carry.cancelMissing on leave", Carry.cancelMissing, world)
	return session
end

return Sessions
