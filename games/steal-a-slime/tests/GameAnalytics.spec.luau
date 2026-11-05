--!strict
local Actions = require("../src/server/Actions")
local Analytics = require("../../../shared/luau/src/analytics/Analytics")
local Carry = require("../src/server/Carry")
local Config = require("../src/shared/Config")
local Economy = require("../src/shared/Economy")
local Fixtures = require("./Fixtures")
local GameAnalytics = require("../src/server/GameAnalytics")
local GameLoop = require("../src/server/GameLoop")
local Milestones = require("../src/server/Milestones")
local PlayerData = require("../src/shared/PlayerData")
local SaveData = require("../src/shared/SaveData")
local ServerFixtures = require("./ServerFixtures")
local TestRunner = require("./TestRunner")
local TutorialProgress = require("../src/shared/TutorialProgress")
local World = require("../src/server/World")
local describe, it, expect = TestRunner.describe, TestRunner.it, TestRunner.expect

local T0 = ServerFixtures.T0
local FIRST = Config.REBIRTH_SLIMES[1][1]

local ctx: Actions.Context = {
	distanceBetween = function()
		return 2
	end,
	positionOf = function()
		return "pos"
	end,
	shopAccess = function()
		return { distance = 3, alive = true }
	end,
}

-- A real tracker over a recorder: names outside the catalog show up in `drops`.
local function harness()
	local rec = Analytics.recorder(1000)
	local drops: { string } = {}
	local clock = { t = 0 }
	local tracker = Analytics.new({
		sink = rec,
		catalog = GameAnalytics.CATALOG :: any,
		now = function()
			return clock.t
		end,
		playerCount = function()
			return 10
		end,
		onDrop = function(reason, kind, name)
			table.insert(drops, `{reason}:{kind}:{name}`)
		end,
	})
	local state = GameAnalytics.new(tracker :: any, function()
		return clock.t
	end)
	-- Plays what the systems queued, as the Outbox does (the key is the userId here).
	local function flush(world: World.World)
		for _, event in World.drain(world) do
			if event.type == "Analytics" and event.track and event.userId then
				GameAnalytics.play(state, event.userId, event.track)
			end
		end
	end
	local function find(kind: string, name: string): { any }?
		for _, e in rec.events do
			if e.kind == kind and (e.args[1] == name or e.args[2] == name or e.args[5] == name) then
				return e.args
			end
		end
		return nil
	end
	return { rec = rec, drops = drops, state = state, tracker = tracker, flush = flush, find = find, clock = clock }
end

local function call(world: any, userId: number, action: string, ...: any)
	return Actions.handle(world, userId, action, table.pack(...), T0 + 100, ctx)
end

describe("GameAnalytics catalog", function()
	it("fits Roblox's caps and starts the onboarding funnel with Joined, ends it with Done", function()
		local c = GameAnalytics.CATALOG
		expect(#c.events <= 100).toBe(true)
		expect(c.onboarding[1]).toBe("Joined")
		expect(c.onboarding[#c.onboarding]).toBe("Done")
		expect(#c.onboarding).toBe(#TutorialProgress.STEPS + 2)
		-- Economy transactions past 20 are grouped as "Other" on the dashboard.
		local transactions = {}
		for _, name in GameAnalytics.TRANSACTIONS do
			transactions[name] = true
		end
		for _, name in { "WildSlime", "Income", "Offline", "Goal", "DexMilestone", "Robux" } do
			transactions[name] = true
		end
		local n = 0
		for _ in transactions do
			n += 1
		end
		expect(n <= 20).toBe(true)
	end)

	it("names the tier and the rank in custom fields", function()
		expect(GameAnalytics.tierField(1)).toBe(`Tier - {Config.RARITIES[1].name}`)
		expect(GameAnalytics.tierField(99)).toBe("Tier - 99")
		expect(GameAnalytics.rankField(0)).toBe(`Rank - {Config.REBIRTH_TIERS[1].title}`)
	end)
end)

describe("GameAnalytics onboarding", function()
	it("puts a new player in the funnel and logs each tutorial step as it finishes", function()
		local h = harness()
		local world = ServerFixtures.world()
		local s = ServerFixtures.join(world, 1)
		s.data.tutorialStep = 1
		GameAnalytics.join(h.state, 1, s.data, 0)
		World.tutorial(world, s, "Grab")
		h.flush(world)
		expect(h.rec.events[1].args).toEqual(table.pack(1, "Joined", nil))
		expect(h.rec.events[2].args).toEqual(table.pack(2, "Grab", nil))
		expect(#h.drops).toBe(0)
	end)

	it("logs Done when the tutorial finishes", function()
		local h = harness()
		local world = ServerFixtures.world()
		local s = ServerFixtures.join(world, 1)
		s.data.tutorialStep = #TutorialProgress.STEPS
		GameAnalytics.join(h.state, 1, s.data, 0)
		World.tutorial(world, s, TutorialProgress.STEPS[#TutorialProgress.STEPS])
		h.flush(world)
		local last = h.rec.events[#h.rec.events].args
		expect(last[2]).toBe("Done")
		expect(last[1]).toBe(#TutorialProgress.STEPS + 2)
	end)

	it("leaves players who finished the tutorial out of the funnel", function()
		local h = harness()
		local world = ServerFixtures.world()
		local s = ServerFixtures.join(world, 1)
		s.data.tutorialStep = 0
		GameAnalytics.join(h.state, 1, s.data, 0)
		local ok, reason = GameAnalytics.play(h.state, 1, { op = "onboarding", name = "Grab" })
		expect(ok).toBe(false)
		expect(reason).toBe("NotOnboarding")
		expect(#h.rec.events).toBe(0)
	end)

	it("logs a skipped tutorial with the step it was on", function()
		local h = harness()
		local world = ServerFixtures.world()
		local s = ServerFixtures.join(world, 1)
		s.data.tutorialStep = 2
		expect(call(world, 1, "SkipTutorial").ok).toBe(true)
		h.flush(world)
		local args = h.find("custom", "TutorialSkipped")
		expect(args and args[3]).toEqual({ CustomField01 = `Step - {TutorialProgress.STEPS[2]}` })
	end)
end)

describe("GameAnalytics economy", function()
	it("logs a sale as a Cash source with the balance after it, plus SlimeSold with the tier", function()
		local h = harness()
		local world = ServerFixtures.world()
		local s = ServerFixtures.join(world, 1, { Fixtures.slime("a", 2) }, 0)
		ServerFixtures.clearEvents(world)
		expect(call(world, 1, "Sell", "a").ok).toBe(true)
		h.flush(world)
		local price = Economy.sellPrice(Fixtures.slime("a", 2), 0)
		expect(h.find("economy", "Sale")).toEqual(table.pack("Source", "Cash", price, s.data.cash, "Sale", nil, nil))
		local sold = h.find("custom", "SlimeSold")
		expect(sold and sold[3]).toEqual({ CustomField01 = GameAnalytics.tierField(2) })
		expect(#h.drops).toBe(0)
	end)

	it("logs nothing for a refused action", function()
		local h = harness()
		local world = ServerFixtures.world()
		ServerFixtures.join(world, 1, {}, 0)
		ServerFixtures.clearEvents(world)
		expect(call(world, 1, "Sell", "nope").ok).toBe(false)
		h.flush(world)
		expect(#h.rec.events).toBe(0)
	end)

	it("runs a shop visit through the Shop funnel and logs the cost as a sink with the item as sku", function()
		local h = harness()
		local world = ServerFixtures.world()
		local s = ServerFixtures.join(world, 1, {}, 1e9)
		ServerFixtures.clearEvents(world)
		expect(call(world, 1, "OpenShop", "ItemShop").ok).toBe(true)
		local before = s.data.cash
		expect(call(world, 1, "ShopBuy", "ItemShop", "SpeedCoil").ok).toBe(true)
		h.flush(world)
		local steps = {}
		for _, e in h.rec.events do
			if e.kind == "funnel" then
				table.insert(steps, e.args[4])
			end
		end
		expect(steps).toEqual({ "Opened", "Tried", "Bought" })
		local spend = h.find("economy", "Shop") :: { any }
		expect(spend[1]).toBe("Sink")
		expect(spend[3]).toBe(before - s.data.cash)
		expect(spend[6]).toBe("SpeedCoil")
		expect(#h.drops).toBe(0)
	end)

	it("counts a refused shop buy with its reason", function()
		local h = harness()
		local world = ServerFixtures.world()
		ServerFixtures.join(world, 1, {}, 0)
		ServerFixtures.clearEvents(world)
		call(world, 1, "OpenShop", "ItemShop")
		expect(call(world, 1, "ShopBuy", "ItemShop", "SpeedCoil").ok).toBe(false)
		h.flush(world)
		h.tracker:forget(1) -- batched counts go out on flush
		local denied = h.find("custom", "ShopDenied") :: { any }
		expect(denied[3].CustomField01).toBe("Shop - ItemShop")
		expect(string.find(denied[3].CustomField02, "^Reason %- ") ~= nil).toBe(true)
	end)
end)

describe("GameAnalytics play", function()
	it("logs steal start and delivery with the slime's tier", function()
		local h = harness()
		local world = ServerFixtures.world()
		local victim = ServerFixtures.join(world, 1, { Fixtures.slime("gem", 3) })
		local thief = ServerFixtures.join(world, 2)
		ServerFixtures.unlock(victim)
		ServerFixtures.clearEvents(world)
		expect(Carry.grab(world, 2, "gem", 1, T0)).toBe(true)
		expect(Carry.deposit(world, 2, T0 + 1)).toBe(true)
		h.flush(world)
		local started = h.find("custom", "StealStarted") :: { any }
		local done = h.find("custom", "StealDone") :: { any }
		expect(started[3]).toEqual({ CustomField01 = GameAnalytics.tierField(3) })
		expect(done[3]).toEqual({ CustomField01 = GameAnalytics.tierField(3) })
		expect(thief.data.slimes[1] ~= nil).toBe(true)
		expect(#h.drops).toBe(0)
	end)

	it("counts a steal refused by a locked base", function()
		local h = harness()
		local world = ServerFixtures.world()
		ServerFixtures.join(world, 1, { Fixtures.slime("gem", 3) }) -- the join lock is still on
		ServerFixtures.join(world, 2)
		ServerFixtures.clearEvents(world)
		expect(Carry.grab(world, 2, "gem", 1, T0)).toBe(false)
		h.flush(world)
		h.tracker:forget(2)
		local blocked = h.find("custom", "StealBlocked") :: { any }
		expect(blocked[2]).toBe(1)
		expect(blocked[3]).toEqual({ CustomField01 = "Reason - base is locked" })
	end)

	it("logs a rebirth as progression and the hours played until it", function()
		local h = harness()
		local world = ServerFixtures.world()
		local s = ServerFixtures.join(world, 1, { Fixtures.slime("a", 1) }, 1e6)
		PlayerData.addSlime(s.data, Fixtures.slime("need", 2, { species = FIRST }))
		s.data.stats.playSeconds = 5400
		ServerFixtures.clearEvents(world)
		expect(call(world, 1, "Rebirth").ok).toBe(true)
		h.flush(world)
		local progression = h.find("progression", "Rebirth") :: { any }
		expect(progression[2]).toBe("Complete")
		expect(progression[3]).toBe(1)
		local hours = h.find("custom", "RebirthHours") :: { any }
		expect(hours[2]).toBe(1.5)
		expect(hours[3]).toEqual({ CustomField01 = "Rebirth - 1" })
		expect(#h.drops).toBe(0)
	end)

	it("logs SpeciesFound only for species found after the session's first check", function()
		local h = harness()
		local world = ServerFixtures.world()
		local s = ServerFixtures.join(world, 1) -- the join check sets the baseline
		ServerFixtures.clearEvents(world)
		Milestones.check(world, s, T0)
		h.flush(world)
		expect(h.find("custom", "SpeciesFound")).toBeNil()
		PlayerData.addSlime(s.data, Fixtures.slime("new", 1, { species = FIRST }))
		Milestones.check(world, s, T0)
		h.flush(world)
		local found = h.find("custom", "SpeciesFound") :: { any }
		expect(found ~= nil).toBe(true)
		expect(found[2] >= 1).toBe(true)
	end)

	it("gives every player online one BossHits when a fight ends", function()
		local h = harness()
		local world = ServerFixtures.world()
		ServerFixtures.join(world, 1)
		ServerFixtures.join(world, 2)
		ServerFixtures.clearEvents(world)
		GameAnalytics.bossOver(world, { [1] = 7 }, "Won")
		h.flush(world)
		local byKey = {}
		for _, e in h.rec.events do
			if e.args[1] == "BossHits" then
				byKey[e.key] = e.args
			end
		end
		expect(byKey[1]).toEqual(
			table.pack("BossHits", 7, { CustomField01 = "Outcome - Won", CustomField02 = "Joined - yes" })
		)
		expect(byKey[2][2]).toBe(0)
		expect(byKey[2][3].CustomField02).toBe("Joined - no")
	end)

	it("logs SlimeLost for the owner of a stolen slime", function()
		local h = harness()
		local world = ServerFixtures.world()
		local victim = ServerFixtures.join(world, 1, { Fixtures.slime("gem", 3) })
		ServerFixtures.join(world, 2)
		ServerFixtures.unlock(victim)
		ServerFixtures.clearEvents(world)
		expect(Carry.grab(world, 2, "gem", 1, T0)).toBe(true)
		expect(Carry.deposit(world, 2, T0 + 1)).toBe(true)
		h.flush(world)
		local lost = nil
		for _, e in h.rec.events do
			if e.args[1] == "SlimeLost" then
				expect(e.key).toBe(1)
				lost = e.args
			end
		end
		expect(lost).toEqual(table.pack("SlimeLost", nil, { CustomField01 = GameAnalytics.tierField(3) }))
		expect(#h.drops).toBe(0)
	end)
end)

describe("GameAnalytics first times", function()
	local function firsts(h: any): { [any]: { string } }
		local out = {}
		for _, e in h.rec.events do
			if e.args[1] == "FirstTime" then
				out[e.key] = out[e.key] or {}
				table.insert(out[e.key], e.args[3].CustomField01)
			end
		end
		return out
	end

	it("logs the first steal for the thief and the first robbery for the owner, once each", function()
		local h = harness()
		local world = ServerFixtures.world()
		local victim = ServerFixtures.join(world, 1, { Fixtures.slime("a", 3), Fixtures.slime("b", 3) })
		local thief = ServerFixtures.join(world, 2)
		thief.data.stats.playSeconds = 750
		ServerFixtures.unlock(victim)
		ServerFixtures.clearEvents(world)
		expect(Carry.grab(world, 2, "a", 1, T0)).toBe(true)
		expect(Carry.deposit(world, 2, T0 + 1)).toBe(true)
		GameAnalytics.firstTime(world, thief, "Steal") -- a later steal logs nothing
		GameAnalytics.firstTime(world, victim, "Robbed")
		h.flush(world)
		local got = firsts(h)
		expect(got[2]).toEqual({ "First - Steal" })
		expect(got[1]).toEqual({ "First - Robbed" })
		local steal = h.find("custom", "FirstTime") :: { any }
		expect(steal[2]).toBe(12.5) -- minutes played until then
		expect(#h.drops).toBe(0)
	end)

	it("logs a first sale and a first rebirth", function()
		local h = harness()
		local world = ServerFixtures.world()
		local s = ServerFixtures.join(world, 1, { Fixtures.slime("a", 1), Fixtures.slime("b", 1) }, 1e6)
		PlayerData.addSlime(s.data, Fixtures.slime("need", 2, { species = FIRST }))
		ServerFixtures.clearEvents(world)
		expect(call(world, 1, "Sell", "b").ok).toBe(true)
		expect(call(world, 1, "Rebirth").ok).toBe(true)
		h.flush(world)
		expect(firsts(h)[1]).toEqual({ "First - Sell", "First - Rebirth" })
	end)

	it("logs the first boss fight only for players who hit", function()
		local h = harness()
		local world = ServerFixtures.world()
		ServerFixtures.join(world, 1)
		ServerFixtures.join(world, 2)
		ServerFixtures.clearEvents(world)
		GameAnalytics.bossOver(world, { [1] = 3 }, "Won")
		GameAnalytics.bossOver(world, { [1] = 3 }, "Won")
		h.flush(world)
		local got = firsts(h)
		expect(got[1]).toEqual({ "First - Boss" })
		expect(got[2]).toBeNil()
	end)

	it("remembers first times through a save and drops unknown ids", function()
		local data = PlayerData.new()
		data.firsts = { Steal = true, Nonsense = true }
		local saved = SaveData.serialize(data)
		expect(saved.firsts).toEqual({ "Steal" })
		expect(SaveData.deserialize(saved).firsts).toEqual({ Steal = true })
		expect(SaveData.serialize(PlayerData.new()).firsts).toBeNil()
		expect(SaveData.deserialize(SaveData.serialize(PlayerData.new())).firsts).toEqual({})
	end)
end)

describe("GameAnalytics sessions", function()
	it("logs the minutes played on leave and sends pending batches", function()
		local h = harness()
		local world = ServerFixtures.world()
		local s = ServerFixtures.join(world, 1)
		s.data.tutorialStep = 0
		GameAnalytics.join(h.state, 1, s.data, 100)
		h.tracker:count(1, "Merged")
		GameAnalytics.leave(h.state, 1, s.data, 100 + 150)
		local minutes = h.find("custom", "SessionMinutes") :: { any }
		expect(minutes[2]).toBe(2.5)
		expect(h.find("custom", "Merged") ~= nil).toBe(true)
	end)

	it("adds the average server size and first visit or not to SessionMinutes", function()
		local h = harness()
		local first = PlayerData.new()
		local veteran = PlayerData.new()
		veteran.stats.playSeconds = 3600
		-- Player 1 plays 0..600: alone for 300 s, then with player 2 for 300 s (average 1.5).
		GameAnalytics.join(h.state, 1, first, 0)
		GameAnalytics.join(h.state, 2, veteran, 300)
		GameAnalytics.leave(h.state, 1, first, 600)
		-- Player 2 plays 300..1200: with player 1 for 300 s, alone for 600 s (average 1.33).
		GameAnalytics.leave(h.state, 2, veteran, 1200)
		local byKey = {}
		for _, e in h.rec.events do
			if e.args[1] == "SessionMinutes" then
				byKey[e.key] = e.args[3]
			end
		end
		expect(byKey[1]).toEqual({
			CustomField01 = GameAnalytics.rankField(0),
			CustomField02 = "Server - 2-3",
			CustomField03 = "Visit - First",
		})
		expect(byKey[2].CustomField02).toBe("Server - Alone")
		expect(byKey[2].CustomField03).toBe("Visit - Later")
		expect(h.state.online).toBe(0)
	end)

	it("sorts average server sizes into brackets", function()
		expect(GameAnalytics.serverField(1)).toBe("Server - Alone")
		expect(GameAnalytics.serverField(3.4)).toBe("Server - 2-3")
		expect(GameAnalytics.serverField(4)).toBe("Server - 4-5")
		expect(GameAnalytics.serverField(Config.PLOT_COUNT)).toBe("Server - 6+")
	end)

	it("logs LeftAfterRobbed for a leave soon after losing slimes, not for a later one", function()
		local h = harness()
		local data = PlayerData.new()
		local function robbed(key: number, at: number)
			h.clock.t = at
			GameAnalytics.play(h.state, key, { op = "event", name = "SlimeLost" })
		end
		GameAnalytics.join(h.state, 1, data, 0)
		robbed(1, 100)
		robbed(1, 160)
		GameAnalytics.leave(h.state, 1, data, 220)
		local left = h.find("custom", "LeftAfterRobbed") :: { any }
		expect(left[2]).toBe(1)
		expect(left[3]).toEqual({ CustomField01 = "Lost - 2-3" })

		local h2 = harness()
		GameAnalytics.join(h2.state, 1, data, 0)
		h2.clock.t = 100
		GameAnalytics.play(h2.state, 1, { op = "event", name = "SlimeLost" })
		GameAnalytics.leave(h2.state, 1, data, 100 + GameAnalytics.ROBBED_LEAVE_SECONDS + 1)
		expect(h2.find("custom", "LeftAfterRobbed")).toBeNil()
		expect(#h.drops + #h2.drops).toBe(0)
	end)

	it("counts play time once a second and caps a long hitch", function()
		local world = ServerFixtures.world()
		local s = ServerFixtures.join(world, 1)
		s.data.stats.playSeconds = 0
		world.lastSecondAt = T0
		GameLoop.step(world, T0 + 1)
		expect(s.data.stats.playSeconds).toBe(1)
		GameLoop.step(world, T0 + 61)
		expect(s.data.stats.playSeconds).toBe(6)
	end)

	it("keeps play time through a save, and reads a save without it as 0", function()
		local data = PlayerData.new()
		data.stats.playSeconds = 1234
		expect(SaveData.deserialize(SaveData.serialize(data)).stats.playSeconds).toBe(1234)
		local old = SaveData.serialize(PlayerData.new())
		old.stats.playSeconds = nil
		expect(SaveData.deserialize(old).stats.playSeconds).toBe(0)
	end)
end)
