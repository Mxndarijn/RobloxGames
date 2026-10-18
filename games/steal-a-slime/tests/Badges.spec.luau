--!strict
local Badges = require("../src/server/Badges")
local Config = require("../src/shared/Config")
local Fixtures = require("./Fixtures")
local GameLoop = require("../src/server/GameLoop")
local ServerFixtures = require("./ServerFixtures")
local SpeciesDex = require("../src/shared/SpeciesDex")
local TestRunner = require("./TestRunner")
local World = require("../src/server/World")

local describe, it, expect = TestRunner.describe, TestRunner.it, TestRunner.expect

local function badgeEvents(world: World.World): { string }
	local out = {}
	for _, event in World.drain(world) do
		if event.type == "Badge" then
			table.insert(out, event.badge :: string)
		end
	end
	return out
end

local function fakeService(opts: { owned: boolean?, failures: number? }?)
	local calls = { has = 0, award = 0, waits = 0 }
	local toasts: { string } = {}
	local failures = if opts and opts.failures then opts.failures else 0
	local service = Badges.service({
		backend = {
			hasBadge = function()
				calls.has += 1
				if failures > 0 then
					failures -= 1
					error("HTTP 429")
				end
				return opts ~= nil and opts.owned == true
			end,
			award = function()
				calls.award += 1
				return true
			end,
		},
		wait = function()
			calls.waits += 1
		end,
		notify = function(_, text)
			table.insert(toasts, text)
		end,
		list = { { key = "FirstSlime", name = "First Slime", trigger = "caught", value = 1, badgeId = 111 } },
	})
	return service, calls, toasts
end

describe("Badges config", function()
	it("ships every milestone with a nil placeholder id", function()
		expect(#Config.BADGES).toBe(10)
		for _, badge in Config.BADGES do
			expect(badge.badgeId).toBeNil()
		end
	end)
end)

describe("Badges triggers", function()
	it("fire at their milestone and only then", function()
		local data = Fixtures.data()
		expect(#Badges.reached(data)).toBe(0)
		data.stats.caught = 1
		data.totalStolen = 1
		data.rebirths = 1
		data.totalEarned = 1_000_000
		expect(table.concat(Badges.reached(data), ",")).toBe("FirstSlime,FirstSteal,FirstRebirth,Millionaire")
		data.rebirths = 5
		expect(table.find(Badges.reached(data), "Rebirth5") ~= nil).toBe(true)
	end)
	it("fire for the dex percentages and the Legendary / Secret tiers", function()
		local data = Fixtures.data()
		-- Lowest tiers first, so the tier badges stay unearned until the end.
		local ordered = table.clone(SpeciesDex.ENTRIES)
		table.sort(ordered, function(a, b)
			return a.tier < b.tier
		end)
		local want = math.ceil(SpeciesDex.TOTAL * 0.25)
		for i = 1, want - 1 do
			data.found[ordered[i].id] = true
		end
		expect(table.find(Badges.reached(data), "Dex25")).toBeNil()
		data.found[ordered[want].id] = true
		expect(table.find(Badges.reached(data), "Dex25") ~= nil).toBe(true)
		expect(table.find(Badges.reached(data), "Dex50")).toBeNil()
		expect(table.find(Badges.reached(data), "FirstLegendary")).toBeNil()
		data.found.king = true
		expect(table.find(Badges.reached(data), "FirstLegendary") ~= nil).toBe(true)
		expect(table.find(Badges.reached(data), "FirstSecret")).toBeNil()
		data.found.midas = true
		expect(table.find(Badges.reached(data), "FirstSecret") ~= nil).toBe(true)
		expect(table.find(Badges.reached(data), "Dex100")).toBeNil()
		for _, entry in SpeciesDex.ENTRIES do
			data.found[entry.id] = true
		end
		expect(table.find(Badges.reached(data), "Dex100") ~= nil).toBe(true)
	end)
	it("emit one Badge event per milestone through the game loop, once per session", function()
		local world = ServerFixtures.world()
		local s = ServerFixtures.join(world, 1, { Fixtures.slime("a", 1) })
		World.drain(world)
		GameLoop.step(world, ServerFixtures.T0 + 2)
		expect(table.concat(badgeEvents(world), ",")).toBe("FirstSlime")
		GameLoop.step(world, ServerFixtures.T0 + 4)
		expect(#badgeEvents(world)).toBe(0)
		s.data.totalStolen = 1
		GameLoop.step(world, ServerFixtures.T0 + 6)
		expect(table.concat(badgeEvents(world), ",")).toBe("FirstSteal")
	end)
end)

describe("Badges service", function()
	it("skips a nil badgeId without any BadgeService call", function()
		local service, calls, toasts = fakeService()
		expect(service.grant(1, "FirstSteal")).toBe(false) -- not in the list: ignored
		for _, badge in Config.BADGES do
			local placeholder = Badges.service({
				backend = {
					hasBadge = function()
						calls.has += 1
						return false
					end,
					award = function()
						calls.award += 1
						return true
					end,
				},
				wait = function() end,
				notify = function() end,
			})
			expect(placeholder.grant(1, badge.key)).toBe(false)
		end
		expect(calls.has + calls.award).toBe(0)
		expect(#toasts).toBe(0)
	end)
	it("awards once and toasts once", function()
		local service, calls, toasts = fakeService()
		expect(service.grant(1, "FirstSlime")).toBe(true)
		expect(service.grant(1, "FirstSlime")).toBe(false)
		expect(calls.has).toBe(1)
		expect(calls.award).toBe(1)
		expect(toasts[1]).toBe("Badge unlocked: First Slime")
		expect(#toasts).toBe(1)
	end)
	it("does not award or toast a badge the player already owns", function()
		local service, calls, toasts = fakeService({ owned = true })
		expect(service.grant(1, "FirstSlime")).toBe(false)
		expect(service.grant(1, "FirstSlime")).toBe(false)
		expect(calls.has).toBe(1)
		expect(calls.award).toBe(0)
		expect(#toasts).toBe(0)
	end)
	it("retries a failing call with backoff and gives up without erroring", function()
		local service, calls = fakeService({ failures = 2 })
		expect(service.grant(1, "FirstSlime")).toBe(true)
		expect(calls.has).toBe(3)
		expect(calls.waits).toBe(2)
		local dead, deadCalls, toasts = fakeService({ failures = 99 })
		expect(dead.grant(2, "FirstSlime")).toBe(false)
		expect(deadCalls.award).toBe(0)
		expect(deadCalls.has).toBe(Config.BADGE_RETRIES)
		expect(#toasts).toBe(0)
	end)
end)
