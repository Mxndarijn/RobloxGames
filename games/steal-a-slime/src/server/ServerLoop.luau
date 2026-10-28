--!strict
--[[
	ServerLoop (Roblox adapter)

	The server's one Heartbeat: the kill plane (Rescue, with the PvP void guard) and GameLoop.step every frame;
	every VIEW_INTERVAL the day / night clock, the per-player step (lock enforcement, HomeZone deposits with one
	"plot full" toast per visit, WorldView.updatePlayer incl. the PvP ticks, the open world shop's range check,
	thief plots, leaderstats), the cash pads (FEATURES.CashPads), the co-op ritual, world attributes, the view refresh and the State pushes.
	Each stage runs through safeCall so one failing player or model never stops the pushes. Profiler
	(FEATURES.ServerProfiler) times the stages.
]]

local Lighting = game:GetService("Lighting")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Actions = require(script.Parent.Actions)
local Carry = require(script.Parent.Carry)
local CashPadView = require(script.Parent.CashPadView)
local Config = require(ReplicatedStorage.Shared.Config)
local Constants = require(ReplicatedStorage.Shared.Constants)
local DayNight = require(ReplicatedStorage.Shared.DayNight)
local GameLoop = require(script.Parent.GameLoop)
local LeaderboardView = require(script.Parent.LeaderboardView)
local LockPad = require(script.Parent.LockPad)
local LockPadView = require(script.Parent.LockPadView)
local MoveGuard = require(ReplicatedStorage.Shared.MoveGuard)
local MoveWatch = require(script.Parent.MoveWatch)
local PlayerAttributes = require(script.Parent.PlayerAttributes)
local PlotPadGuard = require(script.Parent.PlotPadGuard)
local Profiler = require(script.Parent.Profiler)
local PvpLaunch = require(script.Parent.PvpLaunch)
local PvpService = require(script.Parent.PvpService)
local Rescue = require(script.Parent.Rescue)
local Ritual = require(ReplicatedStorage.Shared.Ritual)
local RitualService = require(script.Parent.RitualService)
local RitualView = require(script.Parent.RitualView)
local SafeCall = require(script.Parent.SafeCall)
local Shop = require(ReplicatedStorage.Shared.Shop)
local SlimeGuard = require(script.Parent.SlimeGuard)
local SlimeGuardView = require(script.Parent.SlimeGuardView)
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
	cashPads: CashPadView.State, -- FEATURES.CashPads discs and visitor nag timers
	shopCheckedAt: { [number]: number },
	lastView: number,
	lastClock: number,
	wasRaining: boolean?,
}

local ServerLoop = {}

ServerLoop.VIEW_INTERVAL = VIEW_INTERVAL

function ServerLoop.new(deps: Deps): Loop
	local loop: any = table.clone(deps)
	loop.homeZoneFull = {}
	loop.cashPads = CashPadView.new()
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
	CashPadView.forget(loop.cashPads, userId)
	SlimeGuard.forget(loop.world, userId)
	SlimeGuardView.forget(userId)
end

-- FEATURES.MoveGuardLog: samples the root position (log only; nothing is moved, released or kicked).
local function sampleMovement(userId: number, player: Player, session: World.Session, t: number)
	local root = WorldView.rootPart(player)
	local book = MoveWatch.book()
	if not root then
		book.characters[userId] = nil -- the next character starts a fresh baseline
		return
	end
	local p = root.Position
	-- The fastest speed the SERVER allows (owned coil counted as held, carry / PvP slows ignored: a slower cap would
	-- only add false alarms).
	MoveGuard.step(book, userId, player.Character, { X = p.X, Y = p.Y, Z = p.Z }, t, Shop.walkSpeed(session.data, true))
end

-- The owner standing on their own lock pad for Config.LOCK_PAD.STAND_SECONDS runs the Lock action, with the same rules
-- (owner, range, rate limit) as the LockPrompt. A dead character on the pad doesn't count (no refusal toast every second).
local function stepLockPad(loop: Loop, player: Player, session: World.Session, t: number)
	local root = WorldView.rootPart(player)
	local plot = WorldView.plot(session.plotIndex)
	local button = WorldView.plotPromptPart(session.plotIndex, "Lock")
	local onPad = root ~= nil
		and plot ~= nil
		and button ~= nil
		and LockPadView.standing(plot, button, root)
		and (loop.ctx.plotPadAccess == nil or PlotPadGuard.check(loop.ctx.plotPadAccess(session.userId, "Lock")) == nil)
	if LockPad.step(session, onPad, t < session.lockUntil, t) then
		Actions.triggerPlotPrompt(loop.world, session.userId, session.plotIndex, "Lock", t, loop.ctx)
	end
end

-- State.plotFull: the carry card asks to sell or merge while you stand in your full plot with a slime.
local function setPlotFull(session: World.Session, full: boolean)
	if (session.plotFull == true) ~= full then
		session.plotFull = full
		World.markDirty(session)
	end
end

local function stepPlayers(loop: Loop, t: number)
	local world, ctx = loop.world, loop.ctx
	for _, player in Players:GetPlayers() do
		WorldView.enforceLocks(world, player)
	end
	for userId, session in world.sessions do
		local player = Players:GetPlayerByUserId(userId)
		if player then
			loop.safeCall("slime guard", SlimeGuardView.step, world, player, session, t) -- may end a stolen carry or send an intruder home
			local carryId = session.carry and session.carry.slimeId
			local home = WorldView.inHomeZone(player, session.plotIndex)
			session.home = home -- warms the owner's Mystery Eggs (MysteryEgg.step)
			if carryId and home and player.Parent and SlimeGuardView.depositAllowed(world, player, session, t) then
				local ok, reason = Carry.deposit(world, userId, t)
				-- Toast once per zone visit, not every tick while standing in a full plot.
				if not ok and reason == "plot full" and loop.homeZoneFull[userId] ~= carryId then
					loop.homeZoneFull[userId] = carryId
					World.notify(world, userId, "Your plot is full! Sell or merge a slime.", "bad", nil)
				end
				setPlotFull(session, not ok and reason == "plot full")
			else
				loop.homeZoneFull[userId] = nil
				setPlotFull(session, false)
			end
			if Config.FEATURES.MoveGuardLog then
				loop.safeCall("move guard", sampleMovement, userId, player, session, t)
			end
			loop.safeCall("lock pad", stepLockPad, loop, player, session, t)
			WorldView.updatePlayer(world, player, session, t, ctx)
			if session.openShop and t - (loop.shopCheckedAt[userId] or 0) >= SHOP_CHECK_INTERVAL then
				loop.shopCheckedAt[userId] = t
				Actions.shopTick(session, ctx) -- out of range / died closes the shop
			end
			PlayerAttributes.syncOpenShop(world, player)
			PlayerAttributes.syncCosmetics(world, player)
			LeaderboardView.updateStats(player, session)
		end
	end
	if Config.FEATURES.MoveGuardLog then
		local line = MoveGuard.summary(MoveWatch.book(), t)
		if line then
			print(line)
		end
	end
	if Config.FEATURES.CashPads then
		loop.safeCall("cash pads", function()
			CashPadView.sync(loop.cashPads, world, t)
			CashPadView.step(loop.cashPads, world, t)
		end)
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
			local carry = session and session.carry
			if carry and Rescue.dropsCarry(carry.kind, carry.boss) then
				Carry.release(world, player.UserId, loop.now(), nil, "drop")
			end
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
	Profiler.time(profiler, "GameLoop", GameLoop.step, loop.world, t, loop.ctx :: any)
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
