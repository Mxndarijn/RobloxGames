--!strict
--[[
	Server entry (owner: Phoenix) -> ServerScriptService.Server

	Wires the server modules together (CONTRACT.md §1-§3, ARCHITECTURE.md §1); no rules live here:
	  * boot: remotes, the world view, props and colliders (each step through safeCall; a failing one is
	    logged and the server keeps going), the yielding mesh swaps in the background;
	  * the World, Persistence (save backend + DataStoreStatus), the one ctx (ServerContext) and the PvP lines;
	  * `Request` -> Actions.handle, then a view refresh and the State pushes; plot and shop prompts;
	  * Outbox plays the World events (Effects, Notify, PvpEvent, badges, rare-drop attributes);
	  * friends, admin events, weather and weekly events;
	  * PlayerLifecycle (join / spawn / leave / shutdown / autosave), ServerLoop (Heartbeat), the leaderboard
	    refresh loop and the Studio-only review hooks.
	`world`, `ctx`, `refreshView`, `World`, `WorldView` and `Carry` stay top-level locals: the live-test tools
	append a line to this script that exports them.
]]

local BadgeService = game:GetService("BadgeService")
local HttpService = game:GetService("HttpService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))
local Constants = require(Shared:WaitForChild("Constants"))
local Remotes = require(Shared:WaitForChild("Remotes"))
local Ritual = require(Shared:WaitForChild("Ritual"))
local Types = require(Shared:WaitForChild("Types"))

local Actions = require(script.Actions)
local AdminEventsService = require(script.AdminEventsService)
local Badges = require(script.Badges)
local BaseFloors = require(script.BaseFloors)
local BorderTerrainView = require(script.BorderTerrainView)
local Carry = require(script.Carry)
local EffectsView = require(script.EffectsView)
local FountainColliders = require(script.FountainColliders)
local Friends = require(script.Friends)
local GroundTerrainView = require(script.GroundTerrainView)
local LeaderboardView = require(script.LeaderboardView)
local MeshSwap = require(script.MeshSwap)
local Outbox = require(script.Outbox)
local ParadeView = require(script.ParadeView)
local Persistence = require(script.Persistence)
local PlayerAttributes = require(script.PlayerAttributes)
local PlayerLifecycle = require(script.PlayerLifecycle)
local PlazaColliders = require(script.PlazaColliders)
local Profiler = require(script.Profiler)
local PvpBlaster = require(script.PvpBlaster)
local PvpFun = require(script.PvpFun)
local PvpKnockback = require(script.PvpKnockback)
local PvpTrap = require(script.PvpTrap)
local RitualView = require(script.RitualView)
local SafeCall = require(script.SafeCall)
local ServerContext = require(script.ServerContext)
local ServerLoop = require(script.ServerLoop)
local Snapshot = require(script.Snapshot)
local StudioHooks = require(script.StudioHooks)
local WeatherService = require(script.WeatherService)
local WeeklyEventService = require(script.WeeklyEventService)
local World = require(script.World)
local WorldProps = require(script.WorldProps)
local WorldView = require(script.WorldView)

local function now(): number
	return workspace:GetServerTimeNow()
end

local safeCall = SafeCall.new(warn)

---------------------------------------------------------------------------
-- Boot: remotes and the static world
---------------------------------------------------------------------------

Remotes.setup()
local worldBuilder = WorldView.setup()
-- Upper base floors (BaseFloors): only on the WorldLayout world, not on the greybox.
local floors: BaseFloors.Context? = if worldBuilder and worldBuilder.buildFloor
	then {
		build = worldBuilder.buildFloor,
		meshes = function(instances: { Instance })
			MeshSwap.applyUnder(instances)
		end,
	}
	else nil
safeCall("GroundTerrainView.place", GroundTerrainView.place) -- voxel ground first, before anything stands on it
safeCall("WorldProps.place", WorldProps.place)
local ritual = Ritual.new() -- co-op ritual circle in the plaza (CONTRACT.md §13)
safeCall("RitualView.setup", RitualView.setup)
safeCall("FountainColliders.place", FountainColliders.place) -- the low fountain slide blocks players
safeCall("PlazaColliders.place", PlazaColliders.place) -- landing ring and goo drain: solid, low step-overs
if Config.FEATURES.Parade then
	safeCall("ParadeView.place", ParadeView.place) -- the goo lane the wild slimes hop along
end
-- These yield (terrain tiles, mesh loads), so they run in the background and never block boot.
task.spawn(safeCall, "BorderTerrainView.place", BorderTerrainView.place) -- hills behind the world border
task.spawn(safeCall, "MeshSwap.applyAll", MeshSwap.applyAll) -- kit meshes, merge vats, then WorldMeshesReady
task.spawn(safeCall, "MeshSwap.publishSkinTemplates", MeshSwap.publishSkinTemplates) -- FEATURES.PlotSkins
task.spawn(safeCall, "MeshSwap.publishHabitatTemplates", MeshSwap.publishHabitatTemplates) -- FEATURES.Habitats
task.spawn(safeCall, "MeshSwap.publishPetCloudTemplate", MeshSwap.publishPetCloudTemplate) -- the follow pet's cloud
task.spawn(safeCall, "MeshSwap.publishPvpMarkerTemplates", MeshSwap.publishPvpMarkerTemplates) -- FEATURES.PvP placed traps

local request = Remotes.get(Constants.REQUEST) :: RemoteFunction
local stateEvent = Remotes.get(Constants.STATE) :: RemoteEvent
local notifyEvent = Remotes.get(Constants.NOTIFY) :: RemoteEvent
local pvpEvent = Remotes.get(Constants.PVP_EVENT) :: RemoteEvent
local shopEventRemote = Remotes.get(Constants.SHOP_EVENT) :: RemoteEvent
local leaderboardEvent = Remotes.get(Constants.LEADERBOARD) :: RemoteEvent

---------------------------------------------------------------------------
-- World, saves, ctx
---------------------------------------------------------------------------

local world = World.new({
	now = now(),
	seed = math.floor(os.clock() * 1e6) + os.time(),
	newId = function()
		return HttpService:GenerateGUID(false)
	end,
	plotCount = Config.PLOT_COUNT,
})
local persistence = Persistence.new()
local ctx = ServerContext.new(world, shopEventRemote, now)
local leaderboard = LeaderboardView.new(world, persistence.orderedStore, leaderboardEvent)
local profiler = Profiler.new() -- FEATURES.ServerProfiler (CONTRACT.md §25); off = every call is a no-op

-- Roblox badges (Badges): BadgeService behind pcall + retries, off the game loop (grant yields).
local badges = Badges.service({
	backend = {
		hasBadge = function(userId, badgeId)
			return BadgeService:UserHasBadgeAsync(userId, badgeId)
		end,
		award = function(userId, badgeId)
			return BadgeService:AwardBadge(userId, badgeId)
		end,
	},
	wait = task.wait,
	notify = function(userId, text)
		local player = Players:GetPlayerByUserId(userId)
		if player then
			notifyEvent:FireClient(player, text, "badge", "Goal")
		end
	end,
})

local effects = EffectsView.new()
local outbox: Outbox.Deps = {
	now = now,
	playerOf = function(userId: number): Player?
		return Players:GetPlayerByUserId(userId)
	end,
	notify = notifyEvent :: any,
	pvp = pvpEvent :: any,
	playEffect = effects.play,
	splash = effects.splash,
	grantBadge = badges.grant,
	setWorldAttribute = function(name: string, value: any)
		workspace:SetAttribute(name, value)
	end,
	safeCall = safeCall,
	spawn = task.spawn :: any,
}

-- PvP lines (FEATURES.PvP; CONTRACT.md §26): each reads the engine through ctx, the look is client FX from PvpEvent.
PvpTrap.register()
PvpKnockback.register()
PvpBlaster.register()
PvpFun.register()

---------------------------------------------------------------------------
-- Pushes and requests
---------------------------------------------------------------------------

local function flushStates(t: number)
	for userId, session in world.sessions do
		local player = Players:GetPlayerByUserId(userId)
		if player and Snapshot.due(session, t) then
			stateEvent:FireClient(player, Snapshot.build(world, session, t))
			Snapshot.pushed(session, t)
		end
	end
end

-- Makes workspace match the World (slimes, plots, carry attributes), then plays the queued events.
local function refreshView(t: number)
	WorldView.reconcile(world, t, function(player: Player, slimeId: string)
		local root = WorldView.rootPart(player)
		local position = WorldView.slimePosition(slimeId)
		local distance = if root and position then (root.Position - position).Magnitude else math.huge
		local ok, reason = Carry.grab(world, player.UserId, slimeId, distance, now())
		if not ok and reason then
			World.notify(world, player.UserId, reason, "info", nil)
		end
	end, function(player: Player, slimeId: string)
		Actions.triggerHatchPrompt(world, player.UserId, slimeId, now(), ctx)
	end)
	WorldView.updatePlots(world, t, floors)
	PlayerAttributes.syncCarrying(world)
	Outbox.flush(world, outbox)
end

request.OnServerInvoke = function(player: Player, action: any, ...: any): Types.RequestResult
	Profiler.count(profiler, "Request")
	local args = table.pack(...)
	local ok, res, ran = pcall(Actions.handle, world, player.UserId, action, args, now(), ctx)
	if not ok then
		return { ok = false, message = "server error" }
	end
	-- Refused before dispatch (unknown action, too fast, ...): nothing changed, so skip the world-wide refresh;
	-- a client spamming Request must not buy a WorldView.reconcile per call.
	if not ran then
		return res
	end
	PlayerAttributes.syncOpenShop(world, player)
	-- Never error to the client: a view hiccup must not turn a done action into a failure.
	local t = now()
	safeCall(`push after {action}`, function()
		refreshView(t)
		flushStates(t)
	end)
	return res
end

-- Owner-only plot prompts (CONTRACT.md §8.5): LockPrompt, BuyPadPrompt, MergePrompt.
WorldView.addPlotPrompts(function(player: Player, index: number, kind: string)
	Actions.triggerPlotPrompt(world, player.UserId, index, kind, now(), ctx)
	refreshView(now())
end)

-- The drop tube on every upper jar (BaseFloors adds the DropPrompt as each jar is built).
if floors then
	floors.drop = function(player: Player, index: number)
		Actions.useDropTube(world, player.UserId, index, ctx)
		refreshView(now())
	end
end

-- "Open Shop" (ShopStand) and "Talk" (TutorialNpc) prompts: the client opens
-- the Shop / Guide menu; purchases go through Request from the Shop menu.
WorldProps.addShopPrompts(function(player: Player, shopId: string)
	Actions.openFromPrompt(world, player.UserId, shopId, ctx)
	PlayerAttributes.syncOpenShop(world, player)
end)

---------------------------------------------------------------------------
-- Services
---------------------------------------------------------------------------

-- Friend income bonus (Friends): Player:IsFriendsWith yields and can throw, so the
-- cache wraps it; a refresh runs on every join and leave.
local friendCache = Friends.new(function(a: number, b: number): boolean
	local player, other = Players:GetPlayerByUserId(a), b
	if not player then
		player, other = Players:GetPlayerByUserId(b), a
	end
	if not player then
		error("player left")
	end
	return player:IsFriendsWith(other)
end)
ctx.areFriends = function(a: number, b: number, at: number): boolean -- Hat Launcher (FEATURES.PvP)
	return Friends.areFriends(friendCache, a, b, at)
end
local function refreshFriends()
	if Config.FEATURES.FriendBonus ~= true then
		return
	end
	Friends.refresh(friendCache, world, now())
end

-- Live admin events (CONTRACT.md §12): chat command from an admin, MessagingService between servers.
local creatorOk, creatorId = pcall(function()
	return if game.CreatorType == Enum.CreatorType.User then game.CreatorId else nil
end)
local adminEvents = AdminEventsService.new(world, if creatorOk then creatorId else nil, nil)
if Config.FEATURES.AdminEvents then
	AdminEventsService.start(adminEvents, now)
end
local function watchAdminChat(player: Player)
	if not Config.FEATURES.AdminEvents then
		return
	end
	pcall(function() -- the Lune live-boot Player stand-in has no Chatted
		player.Chatted:Connect(function(text)
			local reply = AdminEventsService.command(adminEvents, player.UserId, text, now())
			if reply then
				World.notify(world, player.UserId, reply, "info", nil)
			end
		end)
	end)
end

if Config.FEATURES.Weather then
	local weatherState = WeatherService.start(workspace, now)
	ctx.requestWeather = function(id: string): boolean -- Weather Totem
		return WeatherService.request(weatherState, id)
	end
end
WeeklyEventService.start(workspace, os.time)

---------------------------------------------------------------------------
-- Players and loops
---------------------------------------------------------------------------

local loop = ServerLoop.new({
	world = world,
	ctx = ctx,
	ritual = ritual,
	profiler = profiler,
	safeCall = safeCall,
	now = now,
	refreshView = refreshView,
	flushStates = flushStates,
	pinClock = StudioHooks.active(persistence.memoryMode),
})

PlayerLifecycle.start({
	world = world,
	ctx = ctx,
	persistence = persistence,
	leaderboard = leaderboard,
	loop = loop,
	friends = friendCache,
	badges = badges,
	ritual = ritual,
	safeCall = safeCall,
	now = now,
	refreshView = refreshView,
	refreshFriends = refreshFriends,
	onJoin = watchAdminChat,
})

StudioHooks.start(world, persistence.memoryMode, function()
	local t = now()
	refreshView(t)
	flushStates(t)
end)

ServerLoop.start(loop)

Players.PlayerAdded:Connect(function(player)
	LeaderboardView.sendLatest(leaderboard, player)
end)
task.spawn(function()
	while true do
		safeCall("leaderboard refresh", LeaderboardView.refresh, leaderboard)
		task.wait(Config.LEADERBOARD_INTERVAL)
	end
end)
