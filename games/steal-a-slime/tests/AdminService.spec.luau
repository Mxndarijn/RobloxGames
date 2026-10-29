--!strict
-- The admin menu (contract/admin-menu.md): who gets it, cheats only on a test save, each command through Actions.handle.
local Actions = require("../src/server/Actions")
local AdminCommands = require("../src/shared/AdminCommands")
local AdminEventsService = require("../src/server/AdminEventsService")
local AdminService = require("../src/server/AdminService")
local Config = require("../src/shared/Config")
local Fixtures = require("./Fixtures")
local PlayerData = require("../src/shared/PlayerData")
local ServerFixtures = require("./ServerFixtures")
local Snapshot = require("../src/server/Snapshot")
local TestRunner = require("./TestRunner")
local Validate = require("../src/shared/Validate")

local describe, it, expect = TestRunner.describe, TestRunner.it, TestRunner.expect
local T0 = ServerFixtures.T0
local OWNER, STRANGER = 1000, 2000

local baseCtx: any = {
	distanceBetween = function()
		return 2
	end,
	positionOf = function()
		return "pos"
	end,
}

-- A world on a test save (plain Lune counts as one) or on real saves owned by OWNER.
local function world(testSave: boolean)
	local w = ServerFixtures.world()
	if testSave then
		AdminService.setup(w, OWNER)
	else
		w.admin = { creatorId = OWNER, cheats = false }
	end
	return w
end

-- One Admin request at `t` (spaced past the rate limit by default).
local clock = T0
local function admin(w: any, userId: number, command: string, text: string?, amount: number?, ctx: any?)
	clock += 1
	local res = Actions.handle(w, userId, "Admin", { command, text, amount }, clock, ctx or baseCtx)
	return res
end

describe("AdminCommands", function()
	it("lists each command once, on a known tab, as a cheat or an admin tool", function()
		local seen = {}
		for _, command in AdminCommands.LIST do
			expect(seen[command.id]).toBe(nil)
			seen[command.id] = true
			expect(table.find(AdminCommands.TABS, command.tab) ~= nil).toBe(true)
			expect(command.level == "cheat" or command.level == "admin").toBe(true)
		end
	end)
	it("bounds the number argument and falls back to the default", function()
		local cash = AdminCommands.get("cashAdd") :: AdminCommands.Command
		expect(AdminCommands.clamp(cash, 1e30)).toBe(AdminCommands.MAX_CASH)
		expect(AdminCommands.clamp(cash, -5)).toBe(1)
		expect(AdminCommands.clamp(cash, nil)).toBe(1e6)
		expect(AdminCommands.clamp(cash, 0 / 0)).toBe(1e6)
		expect(AdminCommands.clamp(AdminCommands.get("fillDex") :: AdminCommands.Command, 3)).toBe(nil)
	end)
	it("locks cheats without a test save and never locks admin tools", function()
		local cheat = AdminCommands.get("cashAdd") :: AdminCommands.Command
		local tool = AdminCommands.get("slimeRain") :: AdminCommands.Command
		expect(AdminCommands.lockedReason(cheat, false)).toBe("cheats only work on a test save")
		expect(AdminCommands.lockedReason(cheat, true)).toBe(nil)
		expect(AdminCommands.lockedReason(tool, false)).toBe(nil)
	end)
	it("has a rate limit and an action entry", function()
		expect(Validate.ACTIONS.Admin ~= nil).toBe(true)
	end)
end)

describe("AdminService on real saves", function()
	it("gives the owner the menu without cheats, and nobody else anything", function()
		local w = world(false)
		local owner = ServerFixtures.join(w, OWNER, {}, 50)
		local stranger = ServerFixtures.join(w, STRANGER, {}, 50)
		expect(Snapshot.build(w, owner, T0).admin).toEqual({ cheats = false })
		expect(Snapshot.build(w, stranger, T0).admin).toBe(nil)
		local res = admin(w, STRANGER, "spawnWave", nil, 3)
		expect(res.ok).toBe(false)
		expect(res.message).toBe("not an admin")
	end)
	it("refuses every cheat, even for the owner, and changes nothing", function()
		local w = world(false)
		local owner = ServerFixtures.join(w, OWNER, {}, 50)
		for _, command in AdminCommands.LIST do
			if command.level == "cheat" then
				local res = admin(w, OWNER, command.id, "Seat_ufo", 5)
				expect(res.ok).toBe(false)
				expect(res.message).toBe("cheats only work on a test save")
			end
		end
		expect(owner.data.cash).toBe(50)
	end)
	it("runs admin tools for the owner", function()
		local w = world(false)
		ServerFixtures.join(w, OWNER, {}, 50)
		local before = 0
		for _ in w.wild do
			before += 1
		end
		local res = admin(w, OWNER, "spawnWave", nil, 3)
		expect(res.ok).toBe(true)
		expect(res.message).toBe("3 wild slimes spawned")
		local after = 0
		for _ in w.wild do
			after += 1
		end
		expect(after - before).toBe(3)
	end)
	it("refuses everything when no admin service was set up", function()
		local w = ServerFixtures.world()
		ServerFixtures.join(w, OWNER, {}, 50)
		expect(admin(w, OWNER, "spawnWave", nil, 3).message).toBe("not an admin")
	end)
end)

describe("AdminService on a test save", function()
	it("gives everyone the menu with cheats", function()
		local w = world(true)
		local s = ServerFixtures.join(w, STRANGER, {}, 0)
		expect(Snapshot.build(w, s, T0).admin).toEqual({ cheats = true })
	end)
	it("adds, sets and clamps cash", function()
		local w = world(true)
		local s = ServerFixtures.join(w, STRANGER, {}, 0)
		expect(admin(w, STRANGER, "cashAdd", nil, 1000).ok).toBe(true)
		expect(s.data.cash).toBe(1000)
		expect(s.data.totalEarned).toBe(0)
		admin(w, STRANGER, "cashSet", nil, 1e40)
		expect(s.data.cash).toBe(AdminCommands.MAX_CASH)
	end)
	it("sets rebirths and pads inside their limits", function()
		local w = world(true)
		local s = ServerFixtures.join(w, STRANGER, {}, 0)
		admin(w, STRANGER, "setRebirths", nil, 999)
		expect(s.data.rebirths).toBe(Config.MAX_REBIRTHS)
		admin(w, STRANGER, "setPads", nil, 0)
		expect(s.data.padsUnlocked).toBe(1)
	end)
	it("spawns a chosen species, or a random slime of a tier, on a free pad", function()
		local w = world(true)
		local s = ServerFixtures.join(w, STRANGER, {}, 0)
		s.data.padsUnlocked = 4
		local res = admin(w, STRANGER, "spawnSlime", "mochi", 7)
		expect(res.ok).toBe(true)
		local slime = s.data.slimes[#s.data.slimes]
		expect(slime.species).toBe("mochi")
		expect(slime.tier).toBe(1)
		expect(slime.pad ~= nil).toBe(true)
		admin(w, STRANGER, "spawnSlime", nil, 5)
		expect(s.data.slimes[#s.data.slimes].tier).toBe(5)
		expect(admin(w, STRANGER, "spawnSlime", "nope", 1).message).toBe("unknown species")
	end)
	it("refuses a spawn with every pad taken", function()
		local w = world(true)
		local s = ServerFixtures.join(w, STRANGER, { Fixtures.slime("a", 1) }, 0)
		s.data.padsUnlocked = 1
		expect(admin(w, STRANGER, "spawnSlime", nil, 1).message).toBe("no free pad")
	end)
	it("grants an Exclusive seat, base skin, hat and boost; refuses gifts and unknown keys", function()
		local w = world(true)
		local s = ServerFixtures.join(w, STRANGER, {}, 0)
		expect(admin(w, STRANGER, "grantProduct", "Seat_ufo").ok).toBe(true)
		expect(table.find(s.data.ownedSeats, "ufo") ~= nil).toBe(true)
		expect(admin(w, STRANGER, "grantProduct", "Skin_space").ok).toBe(true)
		expect(table.find(s.data.ownedStyles.plotSkin, "space") ~= nil).toBe(true)
		expect(admin(w, STRANGER, "grantProduct", "Hat_witch").ok).toBe(true) -- seasonal: granted any day
		expect(table.find(s.data.ownedStyles.hat, "witch") ~= nil).toBe(true)
		expect(admin(w, STRANGER, "grantProduct", "IncomeBoost15").ok).toBe(true)
		expect(s.data.boostMult >= 2).toBe(true)
		expect(admin(w, STRANGER, "grantProduct", "Gift_Seat_ufo").message).toBe("not a grantable item")
		expect(admin(w, STRANGER, "grantProduct", "Nope").message).toBe("not a grantable item")
		expect(admin(w, STRANGER, "grantProduct").message).toBe("pick an item")
	end)
	it("grants every Exclusive cosmetic at once", function()
		local w = world(true)
		local s = ServerFixtures.join(w, STRANGER, {}, 0)
		expect(admin(w, STRANGER, "grantCosmetics").ok).toBe(true)
		local exclusive = 0
		for _, seat in Config.PET_SEATS do
			if seat.unlock.kind == "exclusive" then
				exclusive += 1
				expect(table.find(s.data.ownedSeats, seat.id) ~= nil).toBe(true)
			end
		end
		expect(exclusive > 0).toBe(true)
		for _, kind in { "plotSkin", "lockStyle", "fanfare", "hat" } do
			expect(`{kind}: {#(s.data.ownedStyles[kind] or {}) > 0}`).toBe(`{kind}: true`)
		end
		expect(#s.data.ownedTrails).toBe(#Config.EXCLUSIVE_SHOP.trails)
		expect(s.data.boostMult).toBe(1) -- cosmetics only: no boosts
	end)
	it("turns Game Passes, the Slime Club and the paid random items policy on and off", function()
		local w = world(true)
		local s = ServerFixtures.join(w, STRANGER, {}, 0)
		expect(admin(w, STRANGER, "setPass", "VIP", 1).ok).toBe(true)
		expect(s.passes.VIP).toBe(true)
		expect((s.data.passIncomeMult :: number) > 1).toBe(true)
		expect(admin(w, STRANGER, "setPass", "FastBrew", 1).ok).toBe(true)
		expect(s.passes.VIP).toBe(true) -- the other passes stay
		expect(admin(w, STRANGER, "setPass", "VIP", 0).ok).toBe(true)
		expect(s.passes.VIP).toBe(false)
		expect(admin(w, STRANGER, "setPass", "Nope", 1).message).toBe("not a pass")
		expect(admin(w, STRANGER, "setSubscription", "SlimeClub", 1).ok).toBe(true)
		expect(s.subscriptions.SlimeClub).toBe(true)
		expect(s.data.credits.brew).toBe(1) -- today's Club credit
		expect(admin(w, STRANGER, "setPaidRandom", nil, 0).ok).toBe(true)
		expect(s.paidRandomAllowed).toBe(false)
		expect(admin(w, STRANGER, "setPass", nil, 1).message).toBe("pick an item")
	end)
	it("gives consumables up to the held cap", function()
		local w = world(true)
		local s = ServerFixtures.join(w, STRANGER, {}, 0)
		admin(w, STRANGER, "giveConsumable", "LuckPotion", 5)
		expect(s.data.consumables.held.LuckPotion).toBe(5)
		s.data.consumables.held.LuckPotion = Config.CONSUMABLE_HELD_MAX - 1
		admin(w, STRANGER, "giveConsumable", "LuckPotion", 5)
		expect(s.data.consumables.held.LuckPotion).toBe(Config.CONSUMABLE_HELD_MAX)
		expect(admin(w, STRANGER, "giveConsumable", "Nope", 1).message).toBe("unknown item")
	end)
	it("fills the SlimeDex and resets the save to a new player's", function()
		local w = world(true)
		local s = ServerFixtures.join(w, STRANGER, { Fixtures.slime("a", 1) }, 500)
		local data = s.data
		admin(w, STRANGER, "fillDex")
		expect(next(data.found) ~= nil).toBe(true)
		expect(admin(w, STRANGER, "resetSave").ok).toBe(true)
		expect(s.data).toBe(data) -- the same table, emptied in place
		expect(#s.data.slimes).toBe(0)
		expect(s.data.cash).toBe(PlayerData.new().cash)
	end)
	it("won't reset a save while one of its slimes is being carried", function()
		local w = world(true)
		local s = ServerFixtures.join(w, STRANGER, { Fixtures.slime("a", 1) }, 500)
		w.carriedBy.a = OWNER
		expect(admin(w, STRANGER, "resetSave").message).toBe("one of your slimes is being carried")
		expect(#s.data.slimes).toBe(1)
	end)
	it("makes incubating eggs ready now", function()
		local w = world(true)
		local egg = Fixtures.slime("egg", 1)
		local s = ServerFixtures.join(w, STRANGER, { egg }, 0);
		(s.data.slimes[1] :: any).egg = { kind = "speckled", hatchAt = clock + 500 }
		expect(admin(w, STRANGER, "hatchEggs").ok).toBe(true)
		expect((s.data.slimes[1] :: any).egg.hatchAt <= clock).toBe(true)
		expect(admin(w, STRANGER, "hatchEggs").message).toBe("no egg is incubating")
	end)
	it("starts the boss warning now, once", function()
		local w = world(true)
		ServerFixtures.join(w, STRANGER, {}, 0)
		expect(admin(w, STRANGER, "startBoss").ok).toBe(true)
		expect(w.nextBossAt).toBe(clock + Config.BOSS.WARNING_SECONDS)
	end)
	it("starts a luck event through the admin events service", function()
		local w = world(true)
		ServerFixtures.join(w, STRANGER, {}, 0)
		local ctx = table.clone(baseCtx)
		ctx.adminEvents = AdminEventsService.new(w, OWNER, nil)
		ctx.features = { AdminEvents = true }
		local res = admin(w, STRANGER, "luckEvent", nil, 10, ctx)
		expect(res.ok).toBe(true)
		expect(w.adminEvent ~= nil).toBe(true)
		expect((w.adminEvent :: any).endsAt).toBe(clock + 600)
		expect(admin(w, STRANGER, "slimeRain").message).toBe("admin events are off")
	end)
	it("calls the next weather through ctx and reports a refusal", function()
		local w = world(true)
		ServerFixtures.join(w, STRANGER, {}, 0)
		local asked = {}
		local ctx = table.clone(baseCtx)
		ctx.features = { Weather = true }
		ctx.requestWeather = function(id: string): boolean
			table.insert(asked, id)
			return id ~= "Clear"
		end
		expect(admin(w, STRANGER, "nextWeather", "Snow", nil, ctx).ok).toBe(true)
		expect(admin(w, STRANGER, "nextWeather", "Clear", nil, ctx).message).toBe("can't call that weather")
		expect(asked).toEqual({ "Snow", "Clear" })
	end)
	it("moves the character and tells the anti-cheat it was the server", function()
		local w = world(true)
		ServerFixtures.join(w, STRANGER, {}, 0)
		local moved = {}
		local ctx = table.clone(baseCtx)
		ctx.toHub = function(userId: number): boolean
			table.insert(moved, userId)
			return true
		end
		expect(admin(w, STRANGER, "goHub", nil, nil, ctx).message).toBe("At the hub")
		expect(moved).toEqual({ STRANGER })
		expect(w.guard ~= nil and (w.guard :: any)[STRANGER] ~= nil).toBe(true)
		expect(admin(w, STRANGER, "goHome").message).toBe("no character")
	end)
	it("refuses an unknown command and bad arguments", function()
		local w = world(true)
		ServerFixtures.join(w, STRANGER, {}, 0)
		expect(admin(w, STRANGER, "nope").message).toBe("unknown command")
		clock += 1
		local res = Actions.handle(w, STRANGER, "Admin", { "cashAdd", "bad id!", 5 }, clock, baseCtx)
		expect(res.ok).toBe(false)
		expect(res.message).toBe("bad argument")
	end)
end)
