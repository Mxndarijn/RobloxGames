--!strict
--[[
	Sessions (pure)

	Player lifecycle on the World: `join` assigns the lowest free plot, locks
	it for JOIN_LOCK_SECONDS and pays capped offline income; `leave` ends any
	carry (a stolen slime bounces home), drops carries of the leaver's slimes
	and frees the plot. Loading and saving data is DataService's job.
]]

local Shared = if script then (game:GetService("ReplicatedStorage") :: any).Shared else nil
local PlayerData = if Shared then require(Shared.PlayerData) else require("../shared/PlayerData")
local Steal = if Shared then require(Shared.Steal) else require("../shared/Steal")
local Carry = if script then require(script.Parent.Carry) else require("./Carry")
local Income = if script then require(script.Parent.Income) else require("./Income")
local Milestones = if script then require(script.Parent.Milestones) else require("./Milestones")
local World = if script then require(script.Parent.World) else require("./World")

type World = World.World
type Session = World.Session

local Sessions = {}

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
	local plotIndex = World.freePlot(world, userId)
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
	world.claims[userId] = nil
	world.sessions[userId] = session
	Income.applyOffline(world, session, now)
	Milestones.check(world, session) -- old saves get past goal stages / dex milestones now
	return session, nil
end

-- Returns the leaving session (so the caller can save its data) or nil.
function Sessions.leave(world: World, userId: number, now: number): Session?
	world.claims[userId] = nil -- left before their data loaded
	local session = world.sessions[userId]
	if not session then
		return nil
	end
	Carry.release(world, userId, now, nil, "left")
	world.sessions[userId] = nil
	if world.plots[session.plotIndex] == userId then
		world.plots[session.plotIndex] = nil
	end
	for _, slime in session.data.slimes do
		world.escaping[slime.id] = nil
	end
	Carry.cancelMissing(world)
	return session
end

return Sessions
