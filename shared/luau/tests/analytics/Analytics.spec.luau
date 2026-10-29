--!strict
local Analytics = require("../../src/analytics/Analytics")
local T = require("../../testing/TestRunner")
local describe, it, expect = T.describe, T.it, T.expect

local CATALOG = {
	onboarding = { "Joined", "ClaimedPlot", "FirstBuy" },
	funnels = { Shop = { "Opened", "Viewed", "Bought" } },
	events = { "Stole", "Merged" },
	currencies = { "Coins" },
	progressions = { "Rebirth" },
}

local function make(overrides: { [string]: any }?)
	local clock = { t = 0 }
	local rec = Analytics.recorder()
	local drops = {}
	local options: any = {
		sink = rec,
		catalog = CATALOG,
		now = function()
			return clock.t
		end,
		onDrop = function(reason, kind, name)
			table.insert(drops, `{reason}:{kind}:{name}`)
		end,
	}
	for k, v in overrides or {} do
		options[k] = v
	end
	return Analytics.new(options), rec, clock, drops
end

describe("Analytics.fields", function()
	it("maps up to three strings to the custom field keys", function()
		expect(Analytics.fields({ "a", "b", "c", "d" })).toEqual({
			CustomField01 = "a",
			CustomField02 = "b",
			CustomField03 = "c",
		})
		expect(Analytics.fields(nil)).toBeNil()
		expect(Analytics.fields({})).toBeNil()
	end)
end)

describe("Analytics.new", function()
	it("refuses a bad setup", function()
		expect(function()
			Analytics.new({ catalog = {} } :: any)
		end).toThrow()
		expect(function()
			Analytics.new({ sink = Analytics.recorder(), now = os.clock, catalog = { events = { "A", "A" } } })
		end).toThrow()
		local many = {}
		for i = 1, 101 do
			many[i] = `E{i}`
		end
		expect(function()
			Analytics.new({ sink = Analytics.recorder(), now = os.clock, catalog = { events = many } })
		end).toThrow()
	end)

	it("counts onboarding as one of the ten funnels", function()
		local funnels = {}
		for i = 1, 10 do
			funnels[`F{i}`] = { "a" }
		end
		Analytics.new({ sink = Analytics.recorder(), now = os.clock, catalog = { funnels = funnels } })
		expect(function()
			Analytics.new({
				sink = Analytics.recorder(),
				now = os.clock,
				catalog = { funnels = funnels, onboarding = { "x" } },
			})
		end).toThrow()
	end)
end)

describe("onboarding", function()
	it("numbers steps by catalog order and sends each once", function()
		local tracker, rec = make()
		expect(tracker:onboarding("p1", "ClaimedPlot")).toBe(true)
		local ok, reason = tracker:onboarding("p1", "ClaimedPlot")
		expect(ok).toBe(false)
		expect(reason).toBe("Repeat")
		expect(tracker:onboarding("p2", "ClaimedPlot")).toBe(true)
		expect(#rec.events).toBe(2)
		expect(rec.events[1].kind).toBe("onboarding")
		expect(rec.events[1].args[1]).toBe(2)
		expect(rec.events[1].args[2]).toBe("ClaimedPlot")
	end)

	it("drops unknown steps", function()
		local tracker, rec, _, drops = make()
		local ok, reason = tracker:onboarding("p1", "Nope")
		expect(ok).toBe(false)
		expect(reason).toBe("UnknownStep")
		expect(#rec.events).toBe(0)
		expect(drops[1]).toBe("UnknownStep:onboarding:Nope")
	end)

	it("sends again after forget (a new session)", function()
		local tracker, rec = make()
		tracker:onboarding("p1", "Joined")
		tracker:forget("p1")
		tracker:onboarding("p1", "Joined")
		expect(#rec.events).toBe(2)
	end)
end)

describe("funnels", function()
	it("starts a session at step 1 and logs later steps in it", function()
		local n = 0
		local tracker, rec = make({
			newId = function()
				n += 1
				return `id{n}`
			end,
		})
		expect(tracker:startFunnel("p1", "Shop")).toBe(true)
		expect(tracker:funnelStep("p1", "Shop", "Bought", { "Item - Bat" })).toBe(true)
		tracker:startFunnel("p1", "Shop")
		expect(rec.events[1].args).toEqual(table.pack("Shop", "id1", 1, "Opened", nil))
		expect(rec.events[2].args[2]).toBe("id1")
		expect(rec.events[2].args[3]).toBe(3)
		expect(rec.events[2].args[5]).toEqual({ CustomField01 = "Item - Bat" })
		expect(rec.events[3].args[2]).toBe("id2")
	end)

	it("needs an open session and known names", function()
		local tracker = make()
		expect(select(2, tracker:funnelStep("p1", "Shop", "Viewed"))).toBe("NoSession")
		expect(select(2, tracker:startFunnel("p1", "Nope"))).toBe("UnknownFunnel")
		tracker:startFunnel("p1", "Shop")
		expect(select(2, tracker:funnelStep("p1", "Shop", "Nope"))).toBe("UnknownStep")
	end)
end)

describe("custom events", function()
	it("sends known events with a value and drops unknown or bad ones", function()
		local tracker, rec = make()
		expect(tracker:event("p1", "Stole", 3, { "Tier - Rare" })).toBe(true)
		expect(rec.events[1].args).toEqual(table.pack("Stole", 3, { CustomField01 = "Tier - Rare" }))
		expect(select(2, tracker:event("p1", "Nope"))).toBe("UnknownEvent")
		expect(select(2, tracker:event("p1", "Stole", 0 / 0))).toBe("BadValue")
	end)

	it("batches counts per name and fields until the window passes", function()
		local tracker, rec, clock = make({ batchSeconds = 60 })
		tracker:count("p1", "Merged")
		tracker:count("p1", "Merged", 2)
		tracker:count("p1", "Merged", 1, { "Tier - Epic" })
		clock.t = 30
		tracker:update()
		expect(#rec.events).toBe(0)
		clock.t = 61
		tracker:update()
		expect(#rec.events).toBe(2)
		local byField = {}
		for _, e in rec.events do
			byField[(e.args[3] and e.args[3].CustomField01) or "none"] = e.args[2]
		end
		expect(byField.none).toBe(3)
		expect(byField["Tier - Epic"]).toBe(1)
		tracker:update()
		expect(#rec.events).toBe(2)
	end)
end)

describe("economy", function()
	it("sends sources and sinks with flow, balance and sku", function()
		local tracker, rec = make()
		expect(tracker:source("p1", "Coins", 50, 150, "Gameplay", "Sale")).toBe(true)
		expect(tracker:spend("p1", "Coins", 100, 50, "Shop", "Bat", { "Kind - Gear" })).toBe(true)
		expect(rec.events[1].args).toEqual(table.pack("Source", "Coins", 50, 150, "Gameplay", "Sale", nil))
		expect(rec.events[2].args[1]).toBe("Sink")
		expect(rec.events[2].args[7]).toEqual({ CustomField01 = "Kind - Gear" })
	end)

	it("refuses unknown currencies and non-positive amounts", function()
		local tracker = make()
		expect(select(2, tracker:source("p1", "Gems", 1, 1, "Gameplay"))).toBe("UnknownCurrency")
		expect(select(2, tracker:source("p1", "Coins", 0, 1, "Gameplay"))).toBe("BadValue")
		expect(select(2, tracker:source("p1", "Coins", -5, 1, "Gameplay"))).toBe("BadValue")
		expect(select(2, tracker:source("p1", "Coins", 5, 0 / 0, "Gameplay"))).toBe("BadValue")
	end)

	it("adds batched amounts and keeps the latest balance", function()
		local tracker, rec, clock = make({ batchSeconds = 10 })
		tracker:source("p1", "Coins", 5, 105, "Gameplay", "Income", nil, true)
		clock.t = 4
		tracker:source("p1", "Coins", 5, 110, "Gameplay", "Income", nil, true)
		clock.t = 10
		tracker:update()
		expect(#rec.events).toBe(1)
		expect(rec.events[1].args).toEqual(table.pack("Source", "Coins", 10, 110, "Gameplay", "Income", nil))
	end)

	it("flushes pending batches when a player is forgotten", function()
		local tracker, rec = make()
		tracker:source("p1", "Coins", 5, 105, "Gameplay", "Income", nil, true)
		tracker:count("p1", "Merged")
		tracker:forget("p1")
		expect(#rec.events).toBe(2)
		tracker:update(1000)
		expect(#rec.events).toBe(2)
	end)
end)

describe("progression", function()
	it("sends known paths with a valid status", function()
		local tracker, rec = make()
		expect(tracker:progression("p1", "Rebirth", "Complete", 3, "Rank 3")).toBe(true)
		expect(rec.events[1].args).toEqual(table.pack("Rebirth", "Complete", 3, "Rank 3", nil))
		expect(select(2, tracker:progression("p1", "Rebirth", "Done", 3))).toBe("BadStatus")
		expect(select(2, tracker:progression("p1", "Nope", "Start", 1))).toBe("UnknownProgression")
	end)
end)

describe("rate budget", function()
	it("drops events over the per-minute share and refills over time", function()
		-- One player: (120 + 20) * 0.5 = 70 requests a minute.
		local tracker, rec, clock = make({
			budgetShare = 0.5,
			playerCount = function()
				return 1
			end,
		})
		for _ = 1, 80 do
			tracker:event("p1", "Stole")
		end
		expect(#rec.events).toBe(70)
		expect(tracker:stats().dropped).toBe(10)
		expect(tracker:stats().reasons.OverBudget).toBe(10)
		clock.t = 30
		for _ = 1, 50 do
			tracker:event("p1", "Stole")
		end
		expect(#rec.events).toBe(105)
	end)

	it("keeps a batch waiting while the budget is empty", function()
		local tracker, rec, clock = make({
			budgetShare = 0.5,
			batchSeconds = 1,
		})
		tracker:count("p1", "Merged", 4)
		for _ = 1, 70 do
			tracker:event("p1", "Stole")
		end
		-- Due, but the clock has not moved, so the budget is still empty.
		tracker:update(5)
		expect(#rec.events).toBe(70)
		expect(tracker:stats().dropped).toBe(0)
		-- One second refills about 1.17 requests, so the batch goes out now.
		clock.t = 1
		tracker:update()
		expect(#rec.events).toBe(71)
		expect(rec.events[#rec.events].args[1]).toBe("Merged")
		expect(rec.events[#rec.events].args[2]).toBe(4)
	end)
end)

describe("recorder", function()
	it("keeps only the newest entries", function()
		local rec = Analytics.recorder(2)
		rec.custom("a", "x")
		rec.custom("b", "y")
		rec.custom("c", "z")
		expect(#rec.events).toBe(2)
		expect(rec.events[1].key).toBe("b")
	end)
end)
