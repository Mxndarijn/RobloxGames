--!strict
--[[
	TestHooks (pure, test saves only; CONTRACT.md §8.12)

	Every cheat in the game: cash, time, progress, saves, slimes and items on a live `world`. Scripted test sessions
	(Luau Execution task, tools/livetest Lune session, unit tests) call it directly, so a stand-in player can run the
	whole loop up to rebirth 6+ in seconds; the admin menu reaches it through server/AdminService
	(contract/admin-menu.md).

	Guard, so it can never be used on a real save:
	  1. Its only caller in src/ is AdminService (tests/TestHooks.spec fails if any other src/ file mentions it).
	  2. `enable(world)` refuses unless the server runs on the in-memory
	     store (workspace attribute DataStoreMode = "Memory"), which the
	     publish checks forbid in a shipped place (scripts/check-place,
	     tests/PlaceSafety.spec). Plain Lune unit tests (no `game`) have no
	     DataStore at all and are allowed.
	  3. Every hook errors unless `enable` succeeded for that world.

	Hooks a player can ask for return (ok, message): a short line for the admin menu.
]]

local Shared = if script then (game:GetService("ReplicatedStorage") :: any).Shared else nil
local Config = if Shared then require(Shared.Config) else require("../shared/Config")
local Constants = if Shared then require(Shared.Constants) else require("../shared/Constants")
local Genome = if Shared then require(Shared.Genome) else require("../shared/Genome")
local PlayerData = if Shared then require(Shared.PlayerData) else require("../shared/PlayerData")
local PlotSkins = if Shared then require(Shared.PlotSkins) else require("../shared/PlotSkins")
local SlimeLooks = if Shared then require(Shared.SlimeLooks) else require("../shared/SlimeLooks")
local SlimeRoster = if Shared then require(Shared.SlimeRoster) else require("../shared/SlimeRoster")
local SpeciesDex = if Shared then require(Shared.SpeciesDex) else require("../shared/SpeciesDex")
local Income = if script then require(script.Parent.Income) else require("./Income")
local Purchases = if script then require(script.Parent.Purchases) else require("./Purchases")
local World = if script then require(script.Parent.World) else require("./World")

type World = World.World
type Session = World.Session

local TestHooks = {}

local enabled: { [World]: boolean } = setmetatable({}, { __mode = "k" }) :: any

-- True when no real DataStore can be written by this server.
function TestHooks.memoryMode(): boolean
	if not script then
		return true -- plain Lune: no DataStoreService exists
	end
	return (workspace :: any):GetAttribute(Constants.DATASTORE_MODE_ATTRIBUTE) == "Memory"
end

-- Turns the hooks on for `world`. Returns false (hooks stay off) on a real-DataStore server.
function TestHooks.enable(world: World): boolean
	if not TestHooks.memoryMode() then
		return false
	end
	enabled[world] = true
	return true
end

function TestHooks.isEnabled(world: World): boolean
	return enabled[world] == true
end

local function guard(world: World)
	if not enabled[world] then
		error("TestHooks are disabled (only test sessions on DataStoreMode = Memory may enable them)", 3)
	end
end

-- Adds cash without counting it as earned (goals stay honest).
function TestHooks.grantCash(world: World, userId: number, amount: number)
	guard(world)
	local session = assert(World.session(world, userId), "no session")
	session.data.cash += math.max(0, amount)
	World.markDirty(session)
end

--[[
	Skips `seconds` of play for every session: pays plot income as if that
	time passed (in Income.MAX_TICK chunks) and moves lock timers forward.
]]
function TestHooks.skipTime(world: World, seconds: number)
	guard(world)
	local left = math.max(0, seconds)
	while left > 0 do
		local dt = math.min(left, Income.MAX_TICK)
		Income.step(world, dt)
		left -= dt
	end
	for _, session in world.sessions do
		session.lockUntil -= seconds
	end
end

local function sessionOf(world: World, userId: number): Session
	guard(world)
	return assert(World.session(world, userId), "no session")
end

local function changed(session: Session, message: string): (boolean, string?)
	World.markDirty(session)
	return true, message
end

function TestHooks.setCash(world: World, userId: number, amount: number): (boolean, string?)
	local session = sessionOf(world, userId)
	session.data.cash = math.max(0, amount)
	return changed(session, "Cash set")
end

function TestHooks.setRebirths(world: World, userId: number, count: number): (boolean, string?)
	local session = sessionOf(world, userId)
	session.data.rebirths = math.clamp(math.floor(count), 0, Config.MAX_REBIRTHS)
	return changed(session, `Rebirths set to {session.data.rebirths}`)
end

function TestHooks.setPads(world: World, userId: number, count: number): (boolean, string?)
	local session = sessionOf(world, userId)
	session.data.padsUnlocked = math.clamp(math.floor(count), 1, Config.PADS_MAX)
	return changed(session, `{session.data.padsUnlocked} pads unlocked`)
end

-- Sets the growth of every slime on a pad (0..100 percent).
function TestHooks.setGrowth(world: World, userId: number, percent: number): (boolean, string?)
	local session = sessionOf(world, userId)
	local p = math.clamp(math.floor(percent), 0, 100)
	for _, slime: any in session.data.slimes do
		if slime.pad then
			slime.growth = p / 100
		end
	end
	return changed(session, `Pad slimes at {p}% growth`)
end

function TestHooks.fillDex(world: World, userId: number): (boolean, string?)
	local session = sessionOf(world, userId)
	for _, entry in SpeciesDex.ENTRIES do
		session.data.found[entry.id] = true
	end
	return changed(session, "SlimeDex complete")
end

-- Turns the save into a brand new player's. Refused while the player carries something or one of their slimes is
-- being carried or escaping, so no slime in flight loses its owner.
function TestHooks.resetSave(world: World, userId: number): (boolean, string?)
	local session = sessionOf(world, userId)
	if session.carry then
		return false, "drop what you're carrying first"
	end
	for _, slime in session.data.slimes do
		if World.isBusy(world, slime.id) then
			return false, "one of your slimes is being carried"
		end
	end
	local data: any = session.data
	for key in data do
		data[key] = nil
	end
	for key, value in PlayerData.new() :: any do
		data[key] = value
	end
	World.markAllDirty(world) -- other players see the emptied plot
	return true, "Save reset to a new player"
end

-- A new slime on the first free pad: `speciesId` (that species and its tier) or a random one of `tier`.
function TestHooks.spawnSlime(world: World, userId: number, speciesId: string?, tier: number): (boolean, string?)
	local session = sessionOf(world, userId)
	local entry = if speciesId then SlimeRoster.get(speciesId) else nil
	if speciesId and not entry then
		return false, "unknown species"
	end
	local pad = PlayerData.freePad(session.data)
	if not pad then
		return false, "no free pad"
	end
	local slime: any = Genome.generate(world.rng, {
		id = world.newId(),
		tier = if entry then entry.tier else math.clamp(math.floor(tier), 1, Config.MAX_TIER),
	})
	if entry then
		local look = SlimeLooks.get(entry.id)
		slime.species = entry.id
		slime.name = entry.name
		if look then
			slime.color = { look.color[1], look.color[2], look.color[3] }
		end
	end
	local ok, reason = PlayerData.addSlime(session.data, slime, pad)
	if not ok then
		return false, tostring(reason)
	end
	SpeciesDex.record(session.data :: any, slime)
	World.markAllDirty(world) -- the plot gains a model every player sees
	return true, `{slime.name} on pad {pad}`
end

-- Every incubating pad egg of the player is ready now.
function TestHooks.hatchEggs(world: World, userId: number, now: number): (boolean, string?)
	local session = sessionOf(world, userId)
	local count = 0
	for _, slime: any in session.data.slimes do
		local egg = slime.egg
		if egg and slime.pad and type(egg.hatchAt) == "number" and egg.hatchAt > now then
			egg.hatchAt = now
			count += 1
		end
	end
	if count == 0 then
		return false, "no egg is incubating"
	end
	return changed(session, `{count} egg{if count == 1 then "" else "s"} ready`)
end

-- Product keys the admin menu may grant: the cosmetics and the starter bundle, never a quick-buy or a gift.
function TestHooks.grantable(productKey: string): boolean
	if (Config.EXCLUSIVE_SHOP.products :: any)[productKey] == nil then
		return false
	end
	return productKey == "StarterBundle"
		or string.match(productKey, "^Seat_") ~= nil
		or string.match(productKey, "^Trail_") ~= nil
		or string.match(productKey, "^BatSkin_") ~= nil
end

-- The Exclusive Shop grant for `productKey`, as a receipt would give it (no receipt id, no Robux).
function TestHooks.grantProduct(world: World, userId: number, productKey: string, now: number): (boolean, string?)
	local session = sessionOf(world, userId)
	if not TestHooks.grantable(productKey) then
		return false, "not a grantable item"
	end
	local ok, reason = Purchases.grant(world, session, productKey, now, nil)
	if not ok then
		return false, reason
	end
	return changed(session, `Granted {productKey}`)
end

-- Every Exclusive seat, trail and bat skin.
function TestHooks.grantCosmetics(world: World, userId: number, now: number): (boolean, string?)
	local session = sessionOf(world, userId)
	local keys = {}
	for key in Config.EXCLUSIVE_SHOP.products :: any do
		if key ~= "StarterBundle" and TestHooks.grantable(key) then
			table.insert(keys, key)
		end
	end
	table.sort(keys)
	local count = 0
	for _, key in keys do
		if Purchases.grant(world, session, key, now, nil) then
			count += 1
		end
	end
	return changed(session, `Granted {count} cosmetics`)
end

-- Marks every plot skin's slimes found, so each skin's collection goal is met.
function TestHooks.unlockSkins(world: World, userId: number): (boolean, string?)
	local session = sessionOf(world, userId)
	for _, skin in Config.PLOT_SKINS do
		for _, id in PlotSkins.slimes(skin) do
			session.data.found[id] = true
		end
	end
	return changed(session, "Every plot skin unlocked")
end

-- Meets the goals of the free cloud seats (merges, a share of the SlimeDex); Exclusives come from grantProduct.
function TestHooks.unlockSeats(world: World, userId: number): (boolean, string?)
	local session = sessionOf(world, userId)
	local data = session.data
	for _, seat in Config.PET_SEATS do
		local unlock: any = seat.unlock
		if unlock.kind == "merges" then
			data.stats.merges = math.max(data.stats.merges, unlock.count or 0)
		elseif unlock.kind == "dex" then
			local need = math.ceil(SpeciesDex.TOTAL * (unlock.percent or 0) / 100)
			for i, entry in SpeciesDex.ENTRIES do
				if i <= need then
					data.found[entry.id] = true
				end
			end
		end
	end
	return changed(session, "Every free cloud seat unlocked")
end

-- Adds `count` of consumable `id` to the held stack, up to Config.CONSUMABLE_HELD_MAX.
function TestHooks.giveConsumable(world: World, userId: number, id: string, count: number): (boolean, string?)
	local session = sessionOf(world, userId)
	local def: any = nil
	for _, item: any in Config.CONSUMABLES do
		if item.id == id then
			def = item
		end
	end
	if not def then
		return false, "unknown item"
	end
	local held = session.data.consumables.held
	held[id] = math.clamp((held[id] or 0) + math.max(0, math.floor(count)), 0, Config.CONSUMABLE_HELD_MAX)
	return changed(session, `{held[id]} {def.name} held`)
end

return TestHooks
