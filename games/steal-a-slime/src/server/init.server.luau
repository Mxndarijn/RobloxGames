--!strict
--[[
	Server entry (owner: Phoenix) -> ServerScriptService.Server

	Thin Roblox adapter around the pure gameplay modules next to this file
	(World, Spawner, Carry, StealService, Income, MergeVat, Rebirth, Actions,
	Snapshot, Scene, Sessions, DataService, Leaderboard; see CONTRACT.md §1-§3):
	  * creates the remotes and routes `Request` to Actions.handle;
	  * player lifecycle: DataService load (session-locked, retried), plot +
	    join lock + offline income (Sessions.join), save on leave, autosave
	    and BindToClose;
	  * Heartbeat: GameLoop.step, HomeZone deposits, WorldView reconcile,
	    Notify / State / leaderstats pushes; global leaderboard refresh;
	    kill plane (fallen characters go back to their plot, WorldView.rescue).
	  * Instance attributes: Player `Carrying`, workspace `SlimeRain` (§5.2).
	  * World props (WorldProps: ShopStand prompts, LeaderboardBoard rows,
	    TutorialNpc) and Effects.play bursts from World "Effect" events (§5.3-5.4).
]]

local DataStoreService = game:GetService("DataStoreService")
local HttpService = game:GetService("HttpService")
local Lighting = game:GetService("Lighting")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))
local Constants = require(Shared:WaitForChild("Constants"))
local DayNight = require(Shared:WaitForChild("DayNight"))
local Genome = require(Shared:WaitForChild("Genome"))
local Merge = require(Shared:WaitForChild("Merge"))
local PlayerData = require(Shared:WaitForChild("PlayerData"))
local Remotes = require(Shared:WaitForChild("Remotes"))
local Ritual = require(Shared:WaitForChild("Ritual"))
local Rng = require(Shared:WaitForChild("Rng"))
local Types = require(Shared:WaitForChild("Types"))

local Actions = require(script.Actions)
local AdminEventsService = require(script.AdminEventsService)
local Badges = require(script.Badges)
local BatTool = require(script.BatTool)
local BorderTerrainView = require(script.BorderTerrainView)
local Carry = require(script.Carry)
local DataService = require(script.DataService)
local FountainColliders = require(script.FountainColliders)
local Friends = require(script.Friends)
local GameLoop = require(script.GameLoop)
local GroundTerrainView = require(script.GroundTerrainView)
local Leaderboard = require(script.Leaderboard)
local MeshSwap = require(script.MeshSwap)
local ParadeView = require(script.ParadeView)
local PlotPadGuard = require(script.PlotPadGuard)
local PodiumAvatars = require(script.PodiumAvatars)
local PodiumRigs = require(script.PodiumRigs)
local Profiler = require(script.Profiler)
local PvpBlaster = require(script.PvpBlaster)
local PvpFun = require(script.PvpFun)
local PvpKnockback = require(script.PvpKnockback)
local PvpLaunch = require(script.PvpLaunch)
local PvpService = require(script.PvpService)
local PvpTrap = require(script.PvpTrap)
local Revenge = require(script.Revenge)
local RitualService = require(script.RitualService)
local RitualView = require(script.RitualView)
local Sessions = require(script.Sessions)
local ShopGuard = require(script.ShopGuard)
local SlideTopWatch = require(script.SlideTopWatch)
local Snapshot = require(script.Snapshot)
local Spawner = require(script.Spawner)
local WeatherService = require(script.WeatherService)
local WeeklyEventService = require(script.WeeklyEventService)
local World = require(script.World)
local WorldProps = require(script.WorldProps)
local WorldView = require(script.WorldView)

local VIEW_INTERVAL = 0.1
local SHUTDOWN_TIMEOUT = 25

local function now(): number
	return workspace:GetServerTimeNow()
end

Remotes.setup()
WorldView.setup()
-- The inner ground (dirt path, grass, plaza sand) is voxel terrain: first, before anything stands on it.
do
	local ok, err = pcall(GroundTerrainView.place)
	if not ok then
		warn(`[Server] GroundTerrainView.place failed: {err}`)
	end
end
do
	local ok, err = pcall(WorldProps.place)
	if not ok then
		warn(`[Server] WorldProps.place failed: {err}`)
	end
end
-- Co-op ritual circle in the plaza (CONTRACT.md §13).
local ritual = Ritual.new()
do
	local ok, err = pcall(RitualView.setup)
	if not ok then
		warn(`[Server] RitualView.setup failed: {err}`)
	end
end
-- The low fountain slide blocks players (its trough and posts were walk-through).
do
	local ok, err = pcall(FountainColliders.place)
	if not ok then
		warn(`[Server] FountainColliders.place failed: {err}`)
	end
end
-- The goo parade lane the wild slimes hop along (FEATURES.Parade).
if Config.FEATURES.Parade then
	local ok, err = pcall(ParadeView.place)
	if not ok then
		warn(`[Server] ParadeView.place failed: {err}`)
	end
end
-- Hills behind the world border: voxel terrain (no parts, no mesh slots); yields between tiles.
task.spawn(function()
	local ok, err = pcall(BorderTerrainView.place)
	if not ok then
		warn(`[Server] BorderTerrainView.place failed: {err}`)
	end
end)
-- Slime Ranch kit meshes over the MeshAsset placeholders (yields; never blocks boot).
task.spawn(function()
	local ok, err = pcall(MeshSwap.apply)
	if not ok then
		warn(`[Server] MeshSwap.apply failed: {err}`)
	end
end)

-- FEATURES.PlotSkins: decor templates for the clients (no world slots; no-op while the flag is off).
task.spawn(function()
	local ok, err = pcall(MeshSwap.publishSkinTemplates)
	if not ok then
		warn(`[Server] MeshSwap.publishSkinTemplates failed: {err}`)
	end
end)

-- FEATURES.FountainTiers: ring / crest templates for the clients (no world slots; no-op while the flag is off).
task.spawn(function()
	local ok, err = pcall(MeshSwap.publishFountainTierTemplates)
	if not ok then
		warn(`[Server] MeshSwap.publishFountainTierTemplates failed: {err}`)
	end
end)

-- Every plot's MergeVat disc wears the merge_vat model (bug #16; no world slot, independent of FEATURES.MergeVat3).
task.spawn(function()
	local ok, err = pcall(MeshSwap.swapPlotVats)
	if not ok then
		warn(`[Server] MeshSwap.swapPlotVats failed: {err}`)
	end
end)

-- FEATURES.RainMagnet: the magnet template for the clients (no world slot; no-op while the flag is off outside Studio).
task.spawn(function()
	local ok, err = pcall(MeshSwap.publishRainMagnetTemplates)
	if not ok then
		warn(`[Server] MeshSwap.publishRainMagnetTemplates failed: {err}`)
	end
end)

-- Archer's Effects (nil without Visuals): bursts are pcall'd and never block gameplay.
local Effects: any = nil
do
	local visuals = ReplicatedStorage:FindFirstChild("Visuals")
	local module = visuals and visuals:FindFirstChild("Effects")
	if module and module:IsA("ModuleScript") then
		local ok, result = pcall(require, module)
		Effects = if ok then result else nil
	end
end

local request = Remotes.get(Constants.REQUEST) :: RemoteFunction
local stateEvent = Remotes.get(Constants.STATE) :: RemoteEvent
local notifyEvent = Remotes.get(Constants.NOTIFY) :: RemoteEvent
local pvpEvent = Remotes.get(Constants.PVP_EVENT) :: RemoteEvent
local shopEventRemote = Remotes.get(Constants.SHOP_EVENT) :: RemoteEvent

-- Roblox badges (Badges): BadgeService behind pcall + retries, off the game loop (grant yields).
local BadgeService = game:GetService("BadgeService")
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
local leaderboardEvent = Remotes.get(Constants.LEADERBOARD) :: RemoteEvent

local world = World.new({
	now = now(),
	seed = math.floor(os.clock() * 1e6) + os.time(),
	newId = function()
		return HttpService:GenerateGUID(false)
	end,
	plotCount = Config.PLOT_COUNT,
})

---------------------------------------------------------------------------
-- Persistence backends
---------------------------------------------------------------------------

-- workspace.DataStoreStatus: "Ok" | "Memory" (DataStoreMode set) | "Unavailable"
-- (no DataStore, nothing saves) | "Error" (last load / save failed). Warns on each change.
local function setStoreStatus(status: string, reason: string?)
	if workspace:GetAttribute(Constants.DATASTORE_STATUS_ATTRIBUTE) == status then
		return
	end
	workspace:SetAttribute(Constants.DATASTORE_STATUS_ATTRIBUTE, status)
	if status ~= "Ok" and status ~= "Memory" then
		warn(`[Server] DataStoreStatus = {status}: {reason or "?"}`)
	end
end

local memoryMode = workspace:GetAttribute(Constants.DATASTORE_MODE_ATTRIBUTE) == "Memory"
local storeOk, dataStore = pcall(function()
	return DataStoreService:GetDataStore(Constants.DATASTORE_NAME)
end)
if memoryMode then
	setStoreStatus("Memory")
elseif not storeOk then
	setStoreStatus("Unavailable", `{dataStore}; using the in-memory store, progress will NOT save`)
	memoryMode = true
else
	setStoreStatus("Ok")
end
local backend: DataService.Backend
local orderedStore: OrderedDataStore? = nil
if memoryMode then
	backend = DataService.memoryBackend()
else
	backend = {
		update = function(key: string, transform: (any) -> any?): any
			return dataStore:UpdateAsync(key, function(old: any)
				return transform(old)
			end)
		end,
	}
	orderedStore = DataStoreService:GetOrderedDataStore(Constants.LEADERBOARD_STORE)
end

local data = DataService.new({
	backend = backend,
	jobId = if game.JobId ~= "" then game.JobId else `studio-{HttpService:GenerateGUID(false)}`,
	now = os.time,
	wait = function(seconds: number)
		task.wait(seconds)
	end,
})

local SHOP_CHECK_INTERVAL = 0.25 -- seconds between range / alive checks of an open world shop
local shopCheckedAt: { [number]: number } = {}
local homeZoneFull: { [number]: string } = {} -- userId -> slime id told "plot full" during this zone visit
local unsaved: { [number]: boolean } = {} -- Studio fallback profiles: never written
local pendingSaves = 0

local function save(userId: number, playerData: PlayerData.Data, release: boolean)
	if unsaved[userId] then
		if release then
			unsaved[userId] = nil
		end
		return
	end
	pendingSaves += 1
	local ok, reason = DataService.save(data, userId, playerData, release)
	if not ok then
		warn(`[Server] save failed for {userId}: {reason}`)
		if reason == "DataStore error" then
			setStoreStatus("Error", `save failed for {userId}`)
		end
	elseif not memoryMode then
		setStoreStatus("Ok")
	end
	if orderedStore then
		local store = orderedStore
		pcall(function()
			store:SetAsync(DataService.key(userId), Leaderboard.storeValue(playerData))
		end)
	end
	pendingSaves -= 1
end

---------------------------------------------------------------------------
-- Pushes
---------------------------------------------------------------------------

local function effectTarget(event: World.Event): Instance?
	if event.slimeId then
		local body = WorldView.slimeBody(event.slimeId)
		if body then
			return body
		end
	end
	if event.plotIndex then
		local plot = WorldView.plot(event.plotIndex)
		local vat = plot and plot:FindFirstChild("MergeVat")
		if vat and vat:IsA("BasePart") then
			return vat
		end
	end
	return if event.userId then WorldView.rootPart(Players:GetPlayerByUserId(event.userId)) else nil
end

-- Never errors: a failed burst must not drop the rest of the drained events.
local function playEffect(event: World.Event)
	if not Effects or not event.effect then
		return
	end
	local ok, err = pcall(function()
		local target = effectTarget(event)
		if target then
			Effects.play(event.effect, target)
		end
	end)
	if not ok then
		warn(`[Server] Effects.play {event.effect} failed: {err}`)
	end
end

local function flushEvents()
	for _, event in World.drain(world) do
		if event.type == "Effect" then
			playEffect(event)
		end
		if
			event.type == "Escaped"
			and event.reason == "slap"
			and Config.FEATURES.StealAlerts
			and event.carrierUserId
		then
			local victim = Players:GetPlayerByUserId(event.carrierUserId)
			if victim then
				victim:SetAttribute(Constants.SLAP_HIT_ATTRIBUTE, now())
			end
		end
		if event.type == "Drained" then
			local ok, err = pcall(ParadeView.splash, Effects)
			if not ok then
				warn(`[Server] drain splash failed: {err}`)
			end
		end
		if event.type == "Rare" then
			-- Latest Legendary+ drop for client effects (CONTRACT.md §8.4); At changes on every one.
			workspace:SetAttribute(Constants.RARE_SPAWN_ID_ATTRIBUTE, event.slimeId)
			workspace:SetAttribute(Constants.RARE_SPAWN_TIER_ATTRIBUTE, event.tier)
			workspace:SetAttribute(Constants.RARE_SPAWN_AT_ATTRIBUTE, now())
		end
		if event.type == "Badge" and event.userId and event.badge then
			task.spawn(badges.grant, event.userId, event.badge)
		end
		if event.type == "Notify" and event.text then
			if event.userId then
				local player = Players:GetPlayerByUserId(event.userId)
				if player then
					notifyEvent:FireClient(player, event.text, event.kind or "info", event.sound, event.itemId)
				end
			else
				notifyEvent:FireAllClients(event.text, event.kind or "info", event.sound, event.itemId)
			end
		end
	end
end

local function flushStates(t: number)
	for userId, session in world.sessions do
		local player = Players:GetPlayerByUserId(userId)
		if player and Snapshot.due(session, t) then
			stateEvent:FireClient(player, Snapshot.build(world, session, t))
			Snapshot.pushed(session, t)
		end
	end
end

local function updateLeaderstats(player: Player, session: World.Session)
	local folder = player:FindFirstChild("leaderstats")
	if not folder then
		return
	end
	for name, value in Leaderboard.stats(session.data) do
		local stat = folder:FindFirstChild(name)
		if stat and stat:IsA("IntValue") and stat.Value ~= value then
			stat.Value = value
		end
	end
end

local function createLeaderstats(player: Player)
	local folder = Instance.new("Folder")
	folder.Name = "leaderstats"
	for _, name in Leaderboard.STATS do
		local stat = Instance.new("IntValue")
		stat.Name = name
		stat.Parent = folder
	end
	folder.Parent = player
end

local names: { [number]: string } = {}
local function nameOf(userId: number): string
	local player = Players:GetPlayerByUserId(userId)
	if player then
		return player.DisplayName
	end
	if not names[userId] then
		local ok, name = pcall(function()
			return Players:GetNameFromUserIdAsync(userId)
		end)
		names[userId] = if ok and type(name) == "string" then name else `Player {userId}`
	end
	return names[userId]
end

local latestBoard: Types.Leaderboard? = nil
local podiums = PodiumAvatars.new(PodiumRigs.adapter())

-- Fetches the global board (this server's players in memory mode) and pushes it to everyone.
local function refreshLeaderboard()
	local ok, page
	if orderedStore then
		local store = orderedStore
		ok, page = pcall(function()
			return store:GetSortedAsync(false, Config.LEADERBOARD_SIZE):GetCurrentPage()
		end)
	else
		ok, page = true, Leaderboard.pageFromSessions(world.sessions :: any) -- memory mode: this server only
	end
	if ok and type(page) == "table" then
		latestBoard = Leaderboard.fromPage(page, nameOf)
		-- Fill the world board first so clients re-render (own-row highlight) after it replicates.
		local filled, err = pcall(WorldProps.fillBoard :: any, latestBoard)
		if not filled then
			warn(`[Server] leaderboard board fill failed: {err}`)
		end
		leaderboardEvent:FireAllClients(latestBoard)
		podiums:request(latestBoard)
	end
end

---------------------------------------------------------------------------
-- World queries for Actions / prompts
---------------------------------------------------------------------------

local function distanceBetween(a: number, b: number): number
	local ra = WorldView.rootPart(Players:GetPlayerByUserId(a))
	local rb = WorldView.rootPart(Players:GetPlayerByUserId(b))
	if not ra or not rb then
		return math.huge
	end
	return (ra.Position - rb.Position).Magnitude
end

local function positionOf(userId: number): Vector3?
	local root = WorldView.rootPart(Players:GetPlayerByUserId(userId))
	return root and root.Position
end

-- World shops (CONTRACT.md §27): the character's distance to the stand's Counter (HumanoidRootPart, 3D) and whether
-- it is alive, measured fresh for every OpenShop / purchase. distance nil = no character or no stand.
local function shopAccess(userId: number, shopId: string): ShopGuard.Access
	local player = Players:GetPlayerByUserId(userId)
	local root = WorldView.rootPart(player)
	local counter = WorldProps.shopCounter(shopId)
	local character = player and player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	local alive = humanoid ~= nil and humanoid.Health > 0
	if not root or not counter then
		return { distance = nil, alive = alive }
	end
	return { distance = (root.Position - counter.Position).Magnitude, alive = alive }
end

-- Owner-only plot prompts: the character's distance to the part the owner's prompt `kind` sits on (their own plot, not a
-- shop stand) and whether it is alive. distance nil = no character or no such prompt part.
local function plotPadAccess(userId: number, kind: string): PlotPadGuard.Access
	local player = Players:GetPlayerByUserId(userId)
	local root = WorldView.rootPart(player)
	local session = World.session(world, userId)
	local part = session and session.plotIndex and WorldView.plotPromptPart(session.plotIndex, kind)
	local character = player and player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	local alive = humanoid ~= nil and humanoid.Health > 0
	if not root or not part then
		return { distance = nil, alive = alive }
	end
	return { distance = (root.Position - part.Position).Magnitude, alive = alive }
end

local ctx: Actions.Context = {
	distanceBetween = distanceBetween,
	positionOf = positionOf,
	shopAccess = shopAccess,
	plotPadAccess = plotPadAccess,
	shopEvent = function(userId: number, payload: { [string]: any })
		local player = Players:GetPlayerByUserId(userId)
		if player then
			payload.serverTime = now()
			shopEventRemote:FireClient(player, payload)
		end
	end,
	rng = Rng.new(Random.new():NextInteger(1, 2147483646)),
	onOwnPlot = function(session: World.Session, userId: number): boolean
		local player = Players:GetPlayerByUserId(userId)
		return player ~= nil and WorldView.inHomeZone(player, session.plotIndex)
	end,
}
-- Player attribute `OpenShop` follows the session's open shop (FEATURES.WorldShops only; nil = closed).
local function syncOpenShop(player: Player)
	if not Config.FEATURES.WorldShops then
		return
	end
	local session = World.session(world, player.UserId)
	local value = session and session.openShop
	if player:GetAttribute(Constants.OPEN_SHOP_ATTRIBUTE) ~= value then
		player:SetAttribute(Constants.OPEN_SHOP_ATTRIBUTE, value)
	end
end

-- PvpEvent (FEATURES.PvP only ever fires it): one user, or every client when target is nil.
PvpService.setSink(function(target: number?, payload: { [string]: any })
	if target == nil then
		pvpEvent:FireAllClients(payload)
		return
	end
	local player = Players:GetPlayerByUserId(target)
	if player then
		pvpEvent:FireClient(player, payload)
	end
end, now)
-- Goo Traps (FEATURES.PvP): server-side zones on the owner's own plot, no Instance; the look is client FX from PvpEvent.
PvpTrap.setPlotCheck(function(session: World.Session, aim: any): boolean
	return WorldView.pointInHomeZone(Vector3.new(aim.X, aim.Y, aim.Z), session.plotIndex)
end)
PvpTrap.register()

-- Knockback gloves (FEATURES.PvP): the server only launches the target; the look is client FX from PvpEvent.
PvpKnockback.setMover(function(userId: number, push, _landing): boolean
	return PvpLaunch.launch(userId, push, now())
end)
PvpKnockback.register()

-- Goo Blaster line (CONTRACT.md §26): server hitscan, slow through Carry.targetWalkSpeed, no Instances.
PvpBlaster.setEnv({
	positionOf = positionOf,
	onOwnPlot = ctx.onOwnPlot :: any,
	toVector3 = function(position)
		return Vector3.new(position.X, position.Y, position.Z)
	end,
})
PvpBlaster.register()

-- Player attribute `Carrying` follows the World right away (pickup, drop, deposit, escape, death).
local function syncCarrying()
	for _, player in Players:GetPlayers() do
		WorldView.setCarrying(player, Carry.carryingId(world, player.UserId))
		if Config.FEATURES.StealAlerts then
			local session = World.session(world, player.UserId)
			local stealing = session ~= nil and session.carry ~= nil and session.carry.kind == "stolen"
			local value = if stealing then true else nil
			if player:GetAttribute(Constants.STEALING_ATTRIBUTE) ~= value then
				player:SetAttribute(Constants.STEALING_ATTRIBUTE, value)
			end
		end
	end
end

-- FEATURES.ServerProfiler (CONTRACT.md §25); off = every Profiler call is a no-op.
local profiler = Profiler.new()

local function refreshView(t: number)
	WorldView.reconcile(world, t, function(player: Player, slimeId: string)
		local root = WorldView.rootPart(player)
		local position = WorldView.slimePosition(slimeId)
		local distance = if root and position then (root.Position - position).Magnitude else math.huge
		local ok, reason = Carry.grab(world, player.UserId, slimeId, distance, now())
		if not ok and reason then
			World.notify(world, player.UserId, reason, "info", nil)
		end
	end)
	WorldView.updatePlots(world, t)
	syncCarrying()
	flushEvents()
end

request.OnServerInvoke = function(player: Player, action: any, ...: any): Types.RequestResult
	Profiler.count(profiler, "Request")
	local args = table.pack(...)
	local ok, res = pcall(Actions.handle, world, player.UserId, action, args, now(), ctx)
	if not ok then
		return { ok = false, message = "server error" }
	end
	syncOpenShop(player)
	-- Never error to the client: a view hiccup must not turn a done action into a failure.
	local t = now()
	local pushed, err = pcall(function()
		refreshView(t)
		flushStates(t)
	end)
	if not pushed then
		warn(`[Server] push after {action} failed: {err}`)
	end
	return res
end

---------------------------------------------------------------------------
-- Plot props: lock button and merge vat prompts (owner only)
---------------------------------------------------------------------------

local function ownerOfPlot(player: Player, plotIndex: number): World.Session?
	local session = World.session(world, player.UserId)
	if session and session.plotIndex == plotIndex then
		return session
	end
	return nil
end

-- Owner-only plot prompts (CONTRACT.md §8.5): LockPrompt, BuyPadPrompt, MergePrompt.
WorldView.addPlotPrompts(function(player: Player, index: number, kind: string)
	local session = ownerOfPlot(player, index)
	if not session then
		local ownerId = world.plots[index]
		local owner = ownerId and world.sessions[ownerId]
		World.notify(
			world,
			player.UserId,
			if owner then `This is {owner.name}'s base` else "Nobody owns this plot",
			"info",
			nil
		)
		refreshView(now())
		return
	end
	local action, args = kind, {}
	if kind == "Merge" then
		local a, b = Merge.findPair(session.data.slimes, World.busySet(world), session.data.favoriteId)
		if not a or not b then
			World.notify(world, player.UserId, "Need two slimes of the same rarity", "info", nil)
			refreshView(now())
			return
		end
		args = { a, b }
	end
	local res = Actions.handlePlotPad(world, player.UserId, action, args, now(), ctx)
	if not res.ok and res.message then
		World.notify(world, player.UserId, res.message, "info", nil)
	end
	refreshView(now())
end)

-- "Open Shop" (ShopStand) and "Talk" (TutorialNpc) prompts: the client opens
-- the Shop / Guide menu; purchases go through Request from the Shop menu.
WorldProps.addShopPrompts(function(player: Player, shopId: string)
	Actions.openFromPrompt(world, player.UserId, shopId, ctx)
	syncOpenShop(player)
end)
pcall(WorldProps.fillBoard, nil) -- "No entries yet" until the first refresh

---------------------------------------------------------------------------
-- Player lifecycle
---------------------------------------------------------------------------

local function onCharacter(player: Player, character: Model)
	local session = World.session(world, player.UserId)
	local spawn = session and WorldView.plotSpawn(session.plotIndex)
	if spawn then
		task.defer(function()
			if character.Parent then
				character:PivotTo(spawn)
			end
		end)
	end
	-- Every spawn gets exactly one Bat (CanBeDropped = false); the server picks the target, the client sends none.
	BatTool.give(player, function()
		local current = World.session(world, player.UserId)
		if current then
			BatTool.swing(world, current, now())
			refreshView(now())
		end
	end)
	local humanoid = character:WaitForChild("Humanoid", 10)
	if humanoid and humanoid:IsA("Humanoid") then
		-- Speed Coil etc. right away, not on the next 0.1 s tick (CONTRACT.md §8.10).
		local current = World.session(world, player.UserId)
		if current then
			WorldView.updatePlayer(player, current, now())
		end
		humanoid.Died:Connect(function()
			Carry.release(world, player.UserId, now(), positionOf(player.UserId), "drop")
			refreshView(now())
		end)
	end
end

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

-- Fun items (FEATURES.PvP): the server only launches / checks; the look is client FX from PvpEvent.
PvpFun.setEnv({
	launcher = function(userId: number, push): boolean
		return PvpLaunch.launch(userId, push, now())
	end,
	onOwnPlot = function(session: World.Session, position): boolean
		return WorldView.pointInHomeZone(Vector3.new(position.X, position.Y, position.Z), session.plotIndex)
	end,
	areFriends = function(a: number, b: number, at: number): boolean
		return Friends.areFriends(friendCache, a, b, at)
	end,
})
PvpFun.register()

-- The default Bat Tool (live for everyone, NOT behind FEATURES.PvP): the server picks the target from the swinger's pose.
BatTool.setEnv({
	pose = function(userId: number)
		local root = WorldView.rootPart(Players:GetPlayerByUserId(userId))
		if not root then
			return nil, nil
		end
		local look = root.CFrame.LookVector
		local p = root.Position
		return { X = p.X, Y = p.Y, Z = p.Z }, { X = look.X, Y = 0, Z = look.Z }
	end,
	mover = function(userId: number, push, _landing): boolean
		return PvpLaunch.launch(userId, push, now())
	end,
	onOwnPlot = function(session: World.Session, position): boolean
		return WorldView.pointInHomeZone(Vector3.new(position.X, position.Y, position.Z), session.plotIndex)
	end,
})

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

local function onPlayerAdded(player: Player)
	local userId = player.UserId
	watchAdminChat(player)
	local ok, result = DataService.load(data, userId)
	if not player.Parent then
		if ok then
			DataService.save(data, userId, result :: PlayerData.Data, true) -- left while loading: release
		end
		return
	end
	if not memoryMode then
		if ok then
			setStoreStatus("Ok")
		elseif result == "DataStore error" then
			setStoreStatus("Error", `load failed for {userId}`)
		end
	end
	local playerData: PlayerData.Data
	if ok then
		playerData = result :: PlayerData.Data
	elseif RunService:IsStudio() then
		warn(`[Server] DataStore unavailable ({result}); using an unsaved profile`)
		playerData = PlayerData.new()
		unsaved[userId] = true
	else
		player:Kick(`Couldn't load your slimes: {result}. Please rejoin.`)
		return
	end

	local session, reason = Sessions.join(world, userId, player.DisplayName, playerData, now())
	if not session then
		save(userId, playerData, true)
		player:Kick(reason or "Server is full")
		return
	end
	createLeaderstats(player)
	updateLeaderstats(player, session)

	player.CharacterAdded:Connect(function(character)
		onCharacter(player, character)
	end)
	player.CharacterRemoving:Connect(function()
		Carry.release(world, userId, now(), positionOf(userId), "drop")
		refreshView(now())
	end)
	if player.Character then
		onCharacter(player, player.Character)
	end
	refreshView(now())
	task.spawn(refreshFriends)
	if not orderedStore then
		task.spawn(refreshLeaderboard) -- memory mode: rank the newcomer now, not in a minute
	end
end

local function onPlayerRemoving(player: Player)
	BatTool.forget(player.UserId)
	local session = Sessions.leave(world, player.UserId, now())
	WorldView.setCarrying(player, nil)
	homeZoneFull[player.UserId] = nil
	shopCheckedAt[player.UserId] = nil
	badges.release(player.UserId)
	Friends.forget(friendCache, player.UserId)
	RitualService.leave(ritual, player.UserId)
	task.spawn(refreshFriends)
	if session then
		refreshView(now()) -- a stolen slime in their arms bounces home
		save(player.UserId, session.data, true)
	end
end

Players.PlayerAdded:Connect(onPlayerAdded)
Players.PlayerRemoving:Connect(onPlayerRemoving)
for _, player in Players:GetPlayers() do
	task.spawn(onPlayerAdded, player)
end

-- Studio-only PC watcher hooks: the Player attributes "PcwGrowth" (percent) and "PcwDexWeather" (true)
-- change the player's real session data (growth of the pad 1 slime; Wet / Frozen discovered in the Dex),
-- so WorldView and the Dex panel draw the result with their own code. Studio and the in-memory store only:
-- never active in live servers, never writes a real DataStore.
if RunService:IsStudio() and memoryMode then
	local function applyPcw(player: Player)
		local session = World.session(world, player.UserId)
		if not session then
			return
		end
		local profile = session.data
		local percent = player:GetAttribute("PcwGrowth")
		if type(percent) == "number" then
			local slime: any = PlayerData.slimeOnPad(profile, 1)
			if slime == nil then
				local fresh: any = Genome.generate(world.rng, { id = HttpService:GenerateGUID(false), tier = 1 })
				PlayerData.addSlime(profile, fresh, 1)
				slime = fresh
			end
			slime.growth = math.clamp(percent, 0, 100) / 100
		end
		if player:GetAttribute("PcwDexWeather") == true then
			for _, mutation in { "Wet", "Frozen" } do
				local slime = Genome.generate(world.rng, { id = "pcw-dex", tier = 1 })
				slime.pattern, slime.eyes = "Plain", "Round"
				Genome.setMutations(slime, { mutation })
				PlayerData.discover(profile, slime)
			end
		end
		World.markDirty(session)
		local t = now()
		refreshView(t)
		flushStates(t)
	end
	local function watchPcw(player: Player)
		for _, attribute in { "PcwGrowth", "PcwDexWeather" } do
			player:GetAttributeChangedSignal(attribute):Connect(function()
				pcall(applyPcw, player)
			end)
		end
	end
	Players.PlayerAdded:Connect(watchPcw)
	for _, player in Players:GetPlayers() do
		watchPcw(player)
	end
end

game:BindToClose(function()
	for userId in world.sessions do
		local session = Sessions.leave(world, userId, now())
		if session then
			task.spawn(save, userId, session.data, true)
		end
	end
	local deadline = os.clock() + SHUTDOWN_TIMEOUT
	while pendingSaves > 0 and os.clock() < deadline do
		task.wait(0.1)
	end
end)

---------------------------------------------------------------------------
-- Loops
---------------------------------------------------------------------------

local lastView = 0
local lastClock = -math.huge
local wasRaining: boolean? = nil
local function stepPlayers(t: number)
	for _, player in Players:GetPlayers() do
		WorldView.enforceLocks(world, player)
	end
	SlideTopWatch.stepStrays(os.clock()) -- bug #9: NPC / dummy Humanoids do not stay on the slide roof either
	for userId, session in world.sessions do
		local player = Players:GetPlayerByUserId(userId)
		if player then
			local carryId = session.carry and session.carry.slimeId
			if carryId and WorldView.inHomeZone(player, session.plotIndex) then
				local ok, reason = Carry.deposit(world, userId, t)
				-- Toast once per zone visit, not every tick while standing in a full plot.
				if not ok and reason == "plot full" and homeZoneFull[userId] ~= carryId then
					homeZoneFull[userId] = carryId
					World.notify(world, userId, "Your plot is full! Sell or merge a slime.", "bad", nil)
				end
			else
				homeZoneFull[userId] = nil
			end
			WorldView.updatePlayer(player, session, t)
			if session.openShop and t - (shopCheckedAt[userId] or 0) >= SHOP_CHECK_INTERVAL then
				shopCheckedAt[userId] = t
				Actions.shopTick(session, ctx) -- out of range / died / flag off closes the shop
			end
			syncOpenShop(player)
			WorldView.setRevengePlots(player, Revenge.plotsFor(world, userId, t))
			updateLeaderstats(player, session)
		end
	end
	if Config.FEATURES.CoopRitual then
		local ok, err = pcall(function()
			RitualService.step(ritual, world, RitualView.positions(), t)
			RitualView.update(ritual, t)
		end)
		if not ok then
			warn(`[Server] ritual step failed: {err}`)
		end
	end
	if
		Config.FEATURES.FountainTiers
		and workspace:GetAttribute(Constants.FOUNTAIN_TIER_ATTRIBUTE) ~= world.fountainTier
	then
		workspace:SetAttribute(Constants.FOUNTAIN_TIER_ATTRIBUTE, world.fountainTier)
	end
	if world.raining ~= wasRaining then
		wasRaining = world.raining
		WorldView.setRain(Spawner.rain(world, t))
	end
	WorldView.setBossNextAt(if Config.FEATURES.BossSlime then world.nextBossAt else nil)
end

-- Kill plane: every player (loaded or not) who falls off the world goes back up.
local function rescueFallen()
	for _, player in Players:GetPlayers() do
		local session = World.session(world, player.UserId)
		local guard = false -- PvP void guard (FEATURES.PvP): armed while under control / just launched
		if Config.FEATURES.PvP == true and session then
			local state = PvpService.state(session)
			guard = PvpLaunch.guardActive(player.UserId, state and state.controlUntil, now())
		end
		if WorldView.rescue(player, session and session.plotIndex, guard) then
			World.notify(world, player.UserId, "Whoa! Back to safety.", "info", nil)
		end
	end
end

if Config.FEATURES.Weather then
	local weatherState = WeatherService.start(workspace, now)
	ctx.requestWeather = function(id: string): boolean
		return WeatherService.request(weatherState, id)
	end
end

WeeklyEventService.start(workspace, os.time)

-- One log line per PROFILER.LOG_INTERVAL plus budget warnings.
local function profilerGauges(): { [string]: number }
	return {
		instances = #workspace:GetDescendants(),
		players = #Players:GetPlayers(),
	}
end
local function reportProfiler(frameStart: number)
	if not profiler.enabled then
		return
	end
	Profiler.record(profiler, "Heartbeat", (profiler.clock() - frameStart) * 1000)
	local line, warnings = Profiler.flush(profiler, profilerGauges)
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

RunService.Heartbeat:Connect(function()
	local frameStart = if profiler.enabled then profiler.clock() else 0
	local t = now()
	local rescued, rescueErr = Profiler.time(profiler, "Rescue", pcall, rescueFallen :: any)
	if not rescued then
		warn(`[Server] rescue failed: {rescueErr}`)
	end
	Profiler.time(profiler, "GameLoop", GameLoop.step, world, t)
	if t - lastView < VIEW_INTERVAL then
		reportProfiler(frameStart)
		return
	end
	lastView = t
	if Config.FEATURES.DayNight and t - lastClock >= 0.5 then
		lastClock = t
		-- Studio-only PC watcher hook: Lighting attribute "PcwClock" pins the time of day (daytime border shots)
		local pinned = if RunService:IsStudio() and memoryMode then Lighting:GetAttribute("PcwClock") else nil
		Lighting.ClockTime = if type(pinned) == "number" then pinned else DayNight.clockTime(t - world.startedAt)
	end
	-- Each stage is isolated so one failing player or model never stops the State / Notify pushes.
	local ok, err = Profiler.time(profiler, "Players", pcall, stepPlayers :: any, t)
	if not ok then
		warn(`[Server] player step failed: {err}`)
	end
	ok, err = Profiler.time(profiler, "View", pcall, refreshView, t)
	if not ok then
		warn(`[Server] view refresh failed: {err}`)
	end
	flushStates(t)
	reportProfiler(frameStart)
end)

task.spawn(function()
	while true do
		task.wait(Config.AUTOSAVE_INTERVAL)
		for userId, session in world.sessions do
			task.spawn(save, userId, session.data, false)
		end
	end
end)

Players.PlayerAdded:Connect(function(player)
	if latestBoard then
		leaderboardEvent:FireClient(player, latestBoard)
	end
end)

task.spawn(function()
	while true do
		local ok, err = pcall(refreshLeaderboard :: any)
		if not ok then
			warn(`[Server] leaderboard refresh failed: {err}`)
		end
		task.wait(Config.LEADERBOARD_INTERVAL)
	end
end)
