--!strict
--[[
	ServerLoop (Roblox adapter)

	The server's one Heartbeat: the kill plane (Rescue, with the PvP void guard) and GameLoop.step every frame;
	every VIEW_INTERVAL the day / night clock, the per-player step (lock enforcement, HomeZone deposits with one
	"plot full" toast per visit, WorldView.updatePlayer incl. the PvP ticks, the open world shop's range check,
	revenge plots, leaderstats), the co-op ritual, world attributes, the view refresh and the State pushes.
	Each stage runs through safeCall so one failing player or model never stops the pushes. Profiler
	(FEATURES.ServerProfiler) times the stages.
]]

local Lighting = game:GetService("Lighting")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Actions = require(script.Parent.Actions)
local Carry = require(script.Parent.Carry)
local Config = require(ReplicatedStorage.Shared.Config)
local Constants = require(ReplicatedStorage.Shared.Constants)
local DayNight = require(ReplicatedStorage.Shared.DayNight)
local GameLoop = require(script.Parent.GameLoop)
local LeaderboardView = require(script.Parent.LeaderboardView)
local PlayerAttributes = require(script.Parent.PlayerAttributes)
local Profiler = require(script.Parent.Profiler)
local PvpLaunch = require(script.Parent.PvpLaunch)
local PvpService = require(script.Parent.PvpService)
local Revenge = require(script.Parent.Revenge)
local Ritual = require(ReplicatedStorage.Shared.Ritual)
local RitualService = require(script.Parent.RitualService)
local RitualView = require(script.Parent.RitualView)
local SafeCall = require(script.Parent.SafeCall)
local Spawner = require(script.Parent.Spawner)
local World = require(script.Parent.World)
local WorldView = require(script.Parent.WorldView)

local VIEW_INTERVAL = 0.1 -- seconds between view / State ticks
local SHOP_CHECK_INTERVAL = 0.25 -- seconds between range / alive checks of an open world shop

export type Deps = {
	world: World.World,
	ctx: Actions.Context,
	ritual: Ritual.State,
	profiler: Profiler.Profiler,
	safeCall: SafeCall.Call,
	now: () -> number,
	refreshView: (t: number) -> (),
	flushStates: (t: number) -> (),
	pinClock: boolean, -- Studio + memory store only: Lighting attribute "PcwClock" pins the time of day
}

export type Loop = Deps & {
	homeZoneFull: { [number]: string }, -- userId -> slime id told "plot full" during this zone visit
	shopCheckedAt: { [number]: number },
	lastView: number,
	lastClock: number,
	wasRaining: boolean?,
}

local ServerLoop = {}

function ServerLoop.new(deps: Deps): Loop
	local loop: any = table.clone(deps)
	loop.homeZoneFull = {}
	loop.shopCheckedAt = {}
	loop.lastView = 0
	loop.lastClock = -math.huge
	loop.wasRaining = nil
	return loop
end

-- Drops a leaving player's per-player bookkeeping.
function ServerLoop.forget(loop: Loop, userId: number)
	loop.homeZoneFull[userId] = nil
	loop.shopCheckedAt[userId] = nil
end

local function stepPlayers(loop: Loop, t: number)
	local world, ctx = loop.world, loop.ctx
	for _, player in Players:GetPlayers() do
		WorldView.enforceLocks(world, player)
	end
	for userId, session in world.sessions do
		local player = Players:GetPlayerByUserId(userId)
		if player then
			local carryId = session.carry and session.carry.slimeId
			if carryId and WorldView.inHomeZone(player, session.plotIndex) then
				local ok, reason = Carry.deposit(world, userId, t)
				-- Toast once per zone visit, not every tick while standing in a full plot.
				if not ok and reason == "plot full" and loop.homeZoneFull[userId] ~= carryId then
					loop.homeZoneFull[userId] = carryId
					World.notify(world, userId, "Your plot is full! Sell or merge a slime.", "bad", nil)
				end
			else
				loop.homeZoneFull[userId] = nil
			end
			WorldView.updatePlayer(world, player, session, t, ctx)
			if session.openShop and t - (loop.shopCheckedAt[userId] or 0) >= SHOP_CHECK_INTERVAL then
				loop.shopCheckedAt[userId] = t
				Actions.shopTick(session, ctx) -- out of range / died / flag off closes the shop
			end
			PlayerAttributes.syncOpenShop(world, player)
			WorldView.setRevengePlots(player, Revenge.plotsFor(world, userId, t))
			LeaderboardView.updateStats(player, session)
		end
	end
	if Config.FEATURES.CoopRitual then
		loop.safeCall("ritual step", function()
			RitualService.step(loop.ritual, world, RitualView.positions(), t)
			RitualView.update(loop.ritual, t)
		end)
	end
	if
		Config.FEATURES.FountainTiers
		and workspace:GetAttribute(Constants.FOUNTAIN_TIER_ATTRIBUTE) ~= world.fountainTier
	then
		workspace:SetAttribute(Constants.FOUNTAIN_TIER_ATTRIBUTE, world.fountainTier)
	end
	if world.raining ~= loop.wasRaining then
		loop.wasRaining = world.raining
		WorldView.setRain(Spawner.rain(world, t))
	end
	WorldView.setBossNextAt(world.nextBossAt)
end

-- Kill plane: every player (loaded or not) who falls off the world goes back up.
local function rescueFallen(loop: Loop)
	local world = loop.world
	for _, player in Players:GetPlayers() do
		local session = World.session(world, player.UserId)
		local guard = false -- PvP void guard (FEATURES.PvP): armed while under control / just launched
		if Config.FEATURES.PvP == true and session then
			local state = PvpService.state(session)
			guard = PvpLaunch.guardActive(player.UserId, state and state.controlUntil, loop.now())
		end
		if WorldView.rescue(player, session and session.plotIndex, guard) then
			World.notify(world, player.UserId, "Whoa! Back to safety.", "info", nil)
		end
	end
end

-- One log line per PROFILER.LOG_INTERVAL plus budget warnings.
local function reportProfiler(profiler: Profiler.Profiler, frameStart: number)
	if not profiler.enabled then
		return
	end
	Profiler.record(profiler, "Heartbeat", (profiler.clock() - frameStart) * 1000)
	local line, warnings = Profiler.flush(profiler, function(): { [string]: number }
		return {
			instances = #workspace:GetDescendants(),
			players = #Players:GetPlayers(),
		}
	end)
	if line then
		print(line)
		workspace:SetAttribute("ProfilerSummary", line) -- read-only dump for admins / the Studio Properties panel
		if warnings then
			for _, w in warnings do
				warn(w)
			end
		end
	end
end

local function frame(loop: Loop)
	local profiler, safeCall = loop.profiler, loop.safeCall
	local frameStart = if profiler.enabled then profiler.clock() else 0
	local t = loop.now()
	Profiler.time(profiler, "Rescue", safeCall, "rescue", rescueFallen, loop)
	Profiler.time(profiler, "GameLoop", GameLoop.step, loop.world, t)
	if t - loop.lastView < VIEW_INTERVAL then
		reportProfiler(profiler, frameStart)
		return
	end
	loop.lastView = t
	if t - loop.lastClock >= 0.5 then
		loop.lastClock = t
		local pinned = if loop.pinClock then Lighting:GetAttribute("PcwClock") else nil
		Lighting.ClockTime = if type(pinned) == "number" then pinned else DayNight.clockTime(t - loop.world.startedAt)
	end
	Profiler.time(profiler, "Players", safeCall, "player step", stepPlayers, loop, t)
	Profiler.time(profiler, "View", safeCall, "view refresh", loop.refreshView, t)
	loop.flushStates(t)
	reportProfiler(profiler, frameStart)
end

function ServerLoop.start(loop: Loop): RBXScriptConnection
	return RunService.Heartbeat:Connect(function()
		frame(loop)
	end)
end

return ServerLoop
