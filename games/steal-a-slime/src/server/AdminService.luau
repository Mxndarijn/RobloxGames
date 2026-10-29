--!strict
--[[
	AdminService (pure, contract/admin-menu.md)

	Runs the admin menu's `Admin` request. `setup` records once at boot who the place owner is and whether this
	server is on a test save (`world.admin`); `view` says whether a player gets the menu; `run` checks the player
	and the command's level, then runs it. Cheats all live in TestHooks, which keeps its own test-save guard, so a
	cheat can never touch a real save even if a check here were wrong. Admin tools (events, weather, boss, waves,
	teleports) run here and change no save.
]]

local Shared = if script then (game:GetService("ReplicatedStorage") :: any).Shared else nil
local AdminCommands = if Shared then require(Shared.AdminCommands) else require("../shared/AdminCommands")
local AdminEvents = if Shared then require(Shared.AdminEvents) else require("../shared/AdminEvents")
local Config = if Shared then require(Shared.Config) else require("../shared/Config")
local NumberFormat = if Shared then require(Shared.NumberFormat) else require("../shared/NumberFormat")
local Types = if Shared then require(Shared.Types) else require("../shared/Types")
local AdminEventsService = if script then require(script.Parent.AdminEventsService) else require("./AdminEventsService")
local SlimeGuard = if script then require(script.Parent.SlimeGuard) else require("./SlimeGuard")
local Spawner = if script then require(script.Parent.Spawner) else require("./Spawner")
local TestHooks = if script then require(script.Parent.TestHooks) else require("./TestHooks")
local TutorialService = if script then require(script.Parent.TutorialService) else require("./TutorialService")
local World = if script then require(script.Parent.World) else require("./World")

type World = World.World
type Session = World.Session

-- The engine access admin tools use (fields of Actions.Context; nil = can't).
export type Context = {
	features: { [string]: boolean }?,
	adminEvents: AdminEventsService.Service?, -- luck event and slime rain, sent to every server
	requestWeather: ((id: string) -> boolean)?,
	dropDown: ((userId: number, plotIndex: number) -> boolean)?, -- moves the character home (the plot's splash pool)
	toHub: ((userId: number) -> boolean)?, -- moves the character onto the hub spawn
}

local AdminService = {}

-- Records the owner and turns cheats on when this server is on a test save (TestHooks.enable decides).
function AdminService.setup(world: World, creatorId: number?)
	world.admin = { creatorId = creatorId, cheats = TestHooks.enable(world) }
end

-- True when `userId` gets the menu: everyone on a test save, else the owner and Config.ADMIN_USER_IDS.
function AdminService.isAdmin(world: World, userId: number): boolean
	local admin = world.admin
	if not admin then
		return false
	end
	return admin.cheats or AdminEvents.listed(userId, admin.creatorId)
end

-- State.admin for `userId`, nil for a player without the menu.
function AdminService.view(world: World, userId: number): Types.AdminView?
	if not AdminService.isAdmin(world, userId) then
		return nil
	end
	return { cheats = (world.admin :: World.AdminConfig).cheats }
end

local function feature(ctx: Context, name: string): boolean
	local override = if ctx.features then ctx.features[name] else nil
	if override ~= nil then
		return override
	end
	return (Config.FEATURES :: any)[name] == true
end

local function cheat(
	world: World,
	session: Session,
	id: string,
	text: string?,
	n: number?,
	now: number
): (boolean, string?)
	local userId = session.userId
	local amount = n or 0
	if id == "cashAdd" then
		TestHooks.grantCash(world, userId, amount)
		return true, `Added {NumberFormat.cash(amount)}`
	elseif id == "cashSet" then
		return TestHooks.setCash(world, userId, amount)
	elseif id == "skipTime" then
		TestHooks.skipTime(world, amount)
		return true, `Skipped {NumberFormat.short(amount)} s`
	elseif id == "setRebirths" then
		return TestHooks.setRebirths(world, userId, amount)
	elseif id == "setPads" then
		return TestHooks.setPads(world, userId, amount)
	elseif id == "setGrowth" then
		return TestHooks.setGrowth(world, userId, amount)
	elseif id == "fillDex" then
		return TestHooks.fillDex(world, userId)
	elseif id == "skipTutorial" then
		local ok, reason = TutorialService.skip(world, session)
		return ok, if ok then "Tutorial skipped" else reason
	elseif id == "resetSave" then
		return TestHooks.resetSave(world, userId)
	elseif id == "grantProduct" then
		if not text then
			return false, "pick an item"
		end
		return TestHooks.grantProduct(world, userId, text, now)
	elseif id == "grantCosmetics" then
		return TestHooks.grantCosmetics(world, userId, now)
	elseif id == "setPass" or id == "setSubscription" then
		if not text then
			return false, "pick an item"
		end
		if id == "setPass" then
			return TestHooks.setPass(world, userId, text, amount == 1)
		end
		return TestHooks.setSubscription(world, userId, text, amount == 1, now)
	elseif id == "setPaidRandom" then
		return TestHooks.setPaidRandom(world, userId, amount == 1)
	elseif id == "unlockSkins" then
		return TestHooks.unlockSkins(world, userId)
	elseif id == "unlockSeats" then
		return TestHooks.unlockSeats(world, userId)
	elseif id == "giveConsumable" then
		if not text then
			return false, "pick an item"
		end
		return TestHooks.giveConsumable(world, userId, text, amount)
	elseif id == "spawnSlime" then
		return TestHooks.spawnSlime(world, userId, text, amount)
	elseif id == "hatchEggs" then
		return TestHooks.hatchEggs(world, userId, now)
	end
	return false, "unknown command"
end

local function tool(
	world: World,
	session: Session,
	id: string,
	text: string?,
	n: number?,
	now: number,
	ctx: Context
): (boolean, string?)
	local userId = session.userId
	if id == "goHome" or id == "goHub" then
		local ok = if id == "goHome"
			then ctx.dropDown ~= nil and ctx.dropDown(userId, session.plotIndex)
			else ctx.toHub ~= nil and ctx.toHub(userId)
		if not ok then
			return false, "no character"
		end
		SlimeGuard.serverMoved(world, userId, now) -- the anti-cheat must not read the jump as a teleport hack
		return true, if id == "goHome" then "Home" else "At the hub"
	elseif id == "spawnWave" then
		local ids = Spawner.spawnBonus(world, now, n or 1, 1)
		World.markAllDirty(world)
		return true, `{#ids} wild slimes spawned`
	elseif id == "dropEgg" then
		if not feature(ctx, "MysteryEggs") then
			return false, "Mystery Eggs are off"
		end
		Spawner.spawnEgg(world, now)
		World.markAllDirty(world)
		return true, "Mystery Egg dropped"
	elseif id == "luckEvent" or id == "slimeRain" then
		local events = ctx.adminEvents
		if not events or not feature(ctx, "AdminEvents") then
			return false, "admin events are off"
		end
		local event = if id == "luckEvent" then "luck" else "rain"
		local seconds = if id == "luckEvent" then (n or 0) * 60 else Config.ADMIN_EVENT_DEFAULT_SECONDS
		return true, AdminEventsService.trigger(events, userId, event, seconds, now)
	elseif id == "nextWeather" then
		if not text then
			return false, "pick a weather"
		end
		if not ctx.requestWeather or not feature(ctx, "Weather") then
			return false, "weather is off"
		end
		local ok = ctx.requestWeather(text)
		return ok, if ok then `Next weather: {text}` else "can't call that weather"
	elseif id == "startBoss" then
		if world.boss then
			return false, "a boss is already here"
		end
		world.nextBossAt = now + Config.BOSS.WARNING_SECONDS
		return true, "Boss warning starts now"
	end
	return false, "unknown command"
end

-- Runs command `id` for `session`. Returns ok and a short line for the menu; never errors.
function AdminService.run(
	world: World,
	session: Session,
	id: string,
	text: string?,
	amount: number?,
	now: number,
	ctx: Context
): (boolean, string?)
	local command = AdminCommands.get(id)
	if not command then
		return false, "unknown command"
	end
	if not AdminService.isAdmin(world, session.userId) then
		return false, "not an admin"
	end
	local admin = world.admin :: World.AdminConfig
	local locked = AdminCommands.lockedReason(command, admin.cheats)
	if locked then
		return false, locked
	end
	local n = AdminCommands.clamp(command, amount)
	if command.level == "cheat" then
		if not TestHooks.isEnabled(world) then
			return false, "cheats only work on a test save"
		end
		return cheat(world, session, id, text, n, now)
	end
	return tool(world, session, id, text, n, now, ctx)
end

return AdminService
