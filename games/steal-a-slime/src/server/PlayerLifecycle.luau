--!strict
--[[
	PlayerLifecycle (Roblox adapter)

	Join, spawn, leave and shutdown for every player:
	  * join: Persistence.load (session-locked; a Studio fallback profile when it fails there, else a kick),
	    Sessions.join (plot, join lock, offline income), leaderstats, the read-only save warning, character
	    hooks, a view refresh, the friend bonus refresh and (memory mode) a leaderboard refresh;
	  * spawn: the character goes to its plot spawn, gets exactly one Bat (the server picks the target, the
	    client sends none), gets its walk speed at once and drops a carried slime on death;
	  * leave: PlayerLeave.run (Sessions.leave, per-player caches forgotten, save + release; a step that throws
	    is logged and never skips the save);
	  * shutdown (BindToClose): every session leaves and saves, and a load still in flight releases its lock
	    when it finishes; waits up to SHUTDOWN_TIMEOUT seconds for all of them;
	  * autosave every Config.AUTOSAVE_INTERVAL.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Actions = require(script.Parent.Actions)
local BatTool = require(script.Parent.BatTool)
local Carry = require(script.Parent.Carry)
local Config = require(ReplicatedStorage.Shared.Config)
local Constants = require(ReplicatedStorage.Shared.Constants)
local Friends = require(script.Parent.Friends)
local LeaderboardView = require(script.Parent.LeaderboardView)
local MoveWatch = require(script.Parent.MoveWatch)
local Persistence = require(script.Parent.Persistence)
local PlayerLeave = require(script.Parent.PlayerLeave)
local Purchases = require(script.Parent.Purchases)
local RitualService = require(script.Parent.RitualService)
local SafeCall = require(ReplicatedStorage.Lib.core.SafeCall)
local ServerLoop = require(script.Parent.ServerLoop)
local Sessions = require(script.Parent.Sessions)
local World = require(script.Parent.World)
local WorldView = require(script.Parent.WorldView)

local SHUTDOWN_TIMEOUT = 25 -- seconds BindToClose waits for the last saves

export type Deps = {
	world: World.World,
	ctx: Actions.Context,
	persistence: Persistence.Persistence,
	leaderboard: LeaderboardView.LeaderboardView,
	loop: ServerLoop.Loop,
	friends: Friends.Cache,
	badges: { release: (userId: number) -> () },
	ritual: any,
	safeCall: SafeCall.Call,
	now: () -> number,
	refreshView: (t: number) -> (),
	refreshFriends: () -> (),
	onJoin: (player: Player) -> (), -- extra per-player hooks (admin chat)
	onSession: ((player: Player, session: World.Session) -> ())?, -- the session is live (analytics join)
	onLeave: ((player: Player, session: World.Session?) -> ())?, -- after the leave ran (analytics leave)
}

local PlayerLifecycle = {}

-- Gives `player` their Bat wearing the equipped Bat skin (Purchases.worn).
local function giveBat(deps: Deps, player: Player)
	local world, now = deps.world, deps.now
	local session = World.session(world, player.UserId)
	local skin = if session then select(2, Purchases.worn(session)) else nil
	BatTool.give(player, function()
		local current = World.session(world, player.UserId)
		if current then
			local _, reason = BatTool.swing(world, current, now(), deps.ctx)
			-- A swing refused for being too fast did nothing: no world-wide refresh for a spammed Activated.
			if reason ~= "too fast" then
				deps.refreshView(now())
			end
		end
	end, skin)
end

local function onCharacter(deps: Deps, player: Player, character: Model)
	local world, now = deps.world, deps.now
	local session = World.session(world, player.UserId)
	local spawn = session and WorldView.plotSpawn(session.plotIndex)
	if spawn then
		task.defer(function()
			if character.Parent then
				MoveWatch.allow(player.UserId, Config.MOVE_GUARD.RESPAWN_ALLOW)
				character:PivotTo(spawn)
				WorldView.markServerMove(player.UserId)
			end
		end)
	end
	giveBat(deps, player)
	local humanoid = character:WaitForChild("Humanoid", 10)
	if humanoid and humanoid:IsA("Humanoid") then
		-- Speed Coil etc. right away, not on the next view tick (CONTRACT.md §8.10).
		local current = World.session(world, player.UserId)
		if current then
			WorldView.updatePlayer(world, player, current, now(), deps.ctx)
		end
		humanoid.Died:Connect(function()
			Carry.release(world, player.UserId, now(), deps.ctx.positionOf(player.UserId), "drop")
			deps.refreshView(now())
		end)
	end
end

local function onPlayerAdded(deps: Deps, player: Player)
	local world, now = deps.world, deps.now
	local userId = player.UserId
	deps.onJoin(player)
	local playerData, kick = Persistence.load(deps.persistence, userId, function(): boolean
		return player.Parent ~= nil
	end)
	if not playerData then
		if kick then
			player:Kick(kick)
		end
		return
	end

	local session, reason = Sessions.join(world, userId, player.DisplayName, playerData, now())
	if not session then
		Persistence.save(deps.persistence, userId, playerData, true)
		player:Kick(reason or "Server is full")
		return
	end
	LeaderboardView.createStats(player)
	LeaderboardView.updateStats(player, session)
	if deps.onSession then
		deps.safeCall("onSession", deps.onSession, player, session)
	end
	if Persistence.readOnly(deps.persistence, userId) then
		World.notify(
			world,
			userId,
			"Your save couldn't be read on this server: progress here won't be saved",
			"bad",
			nil
		)
	end

	player.CharacterAdded:Connect(function(character)
		onCharacter(deps, player, character)
	end)
	-- A Bat skin put on or taken off (PlayerAttributes.syncCosmetics) swaps the Bat at once.
	player:GetAttributeChangedSignal(Constants.BAT_SKIN_ATTRIBUTE):Connect(function()
		if player.Character then
			giveBat(deps, player)
		end
	end)
	player.CharacterRemoving:Connect(function()
		Carry.release(world, userId, now(), deps.ctx.positionOf(userId), "drop")
		deps.refreshView(now())
	end)
	if player.Character then
		onCharacter(deps, player, player.Character)
	end
	deps.refreshView(now())
	task.spawn(deps.refreshFriends)
	if not deps.persistence.boardStore then
		task.spawn(LeaderboardView.refresh, deps.leaderboard) -- memory mode: rank the newcomer now, not in a minute
	end
end

local function onPlayerRemoving(deps: Deps, player: Player)
	local userId = player.UserId
	local session = PlayerLeave.run(deps.world, userId, deps.now(), {
		safeCall = deps.safeCall,
		cleanup = {
			{
				name = "BatTool.forget",
				run = function()
					BatTool.forget(userId)
				end,
			},
			{
				name = "WorldView.setCarrying on leave",
				run = function()
					WorldView.setCarrying(player, nil)
				end,
			},
			{
				name = "WorldView.forgetKits",
				run = function()
					WorldView.forgetKits(userId)
				end,
			},
			{
				name = "ServerLoop.forget",
				run = function()
					ServerLoop.forget(deps.loop, userId)
				end,
			},
			{
				name = "MoveWatch.forget",
				run = function()
					MoveWatch.forget(userId)
				end,
			},
			{
				name = "badges.release",
				run = function()
					deps.badges.release(userId)
				end,
			},
			{
				name = "Friends.forget",
				run = function()
					Friends.forget(deps.friends, userId)
				end,
			},
			{
				name = "RitualService.leave",
				run = function()
					RitualService.leave(deps.ritual, userId)
				end,
			},
			{
				name = "refreshFriends on leave",
				run = function()
					task.spawn(deps.refreshFriends)
				end,
			},
		},
		refreshView = deps.refreshView,
		save = function(leaving)
			task.spawn(Persistence.save, deps.persistence, userId, leaving.data, true)
		end,
	})
	if deps.onLeave then
		deps.safeCall("onLeave", deps.onLeave, player, session)
	end
end

-- Connects join / leave (and runs join for players already in), shutdown and the autosave loop.
function PlayerLifecycle.start(deps: Deps)
	Players.PlayerAdded:Connect(function(player)
		onPlayerAdded(deps, player)
	end)
	Players.PlayerRemoving:Connect(function(player)
		onPlayerRemoving(deps, player)
	end)
	for _, player in Players:GetPlayers() do
		task.spawn(onPlayerAdded, deps, player)
	end

	game:BindToClose(function()
		local world, persistence = deps.world, deps.persistence
		Persistence.close(persistence)
		for userId in world.sessions do
			local session = Sessions.leave(world, userId, deps.now(), deps.safeCall)
			if session then
				task.spawn(Persistence.save, persistence, userId, session.data, true)
			end
		end
		Persistence.waitForSaves(persistence, SHUTDOWN_TIMEOUT)
	end)

	task.spawn(function()
		while true do
			task.wait(Config.AUTOSAVE_INTERVAL)
			Persistence.saveAll(deps.persistence, deps.world, false)
		end
	end)
end

return PlayerLifecycle
