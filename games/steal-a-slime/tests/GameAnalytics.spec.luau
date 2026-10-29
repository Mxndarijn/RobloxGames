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
	local state = GameAnalytics.new(tracker :: any)
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
			byKey[e.key] = e.args
		end
		expect(byKey[1]).toEqual(
			table.pack("BossHits", 7, { CustomField01 = "Outcome - Won", CustomField02 = "Joined - yes" })
		)
		expect(byKey[2][2]).toBe(0)
		expect(byKey[2][3].CustomField02).toBe("Joined - no")
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
