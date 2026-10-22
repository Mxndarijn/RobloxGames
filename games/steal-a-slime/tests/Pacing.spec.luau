--!strict
-- The pacing sim (tools/livetest/pacing): its bots still play the real game code, and the report maths hold.
local Profiles = require("../tools/livetest/pacing/Profiles")
local Report = require("../tools/livetest/pacing/Report")
local Rng = require("../src/shared/Rng")
local Schedule = require("../tools/livetest/pacing/Schedule")
local Server = require("../tools/livetest/pacing/Server")
local TestRunner = require("./TestRunner")

local describe, it, expect = TestRunner.describe, TestRunner.it, TestRunner.expect

describe("Pacing report", function()
	it("takes nearest-rank percentiles and shows median with the 10-90 range", function()
		local values = { 5, 1, 4, 2, 3, 6, 7, 8, 9, 10 }
		expect(Report.percentile(values, 0.5)).toBe(5)
		expect(Report.percentile(values, 0.1)).toBe(1)
		expect(Report.percentile(values, 0.9)).toBe(9)
		expect(Report.percentile({}, 0.5)).toBeNil()
		expect(Report.spread(values)).toBe("5 (1-9)")
		expect(Report.spread({ 3, 3 })).toBe("3")
		expect(Report.spread({})).toBe("-")
	end)
end)

describe("Pacing schedule", function()
	it("plays the first day, keeps sessions in order and apart", function()
		for _, profile in Profiles.LIST do
			local sessions = Schedule.build(profile, Rng.new(4), 0, 7, 2)
			expect(sessions[1] ~= nil and sessions[1].start >= 2 * 86400 and sessions[1].start < 3 * 86400).toBe(true)
			for i, s in sessions do
				expect(s.stop > s.start).toBe(true)
				local prev = sessions[i - 1]
				if prev then
					expect(s.start >= prev.stop + 600).toBe(true)
				end
			end
		end
	end)
end)

describe("Pacing server", function()
	local function run()
		return Server.run({
			seed = 3,
			days = 1,
			mix = { casual = 1, grinder = 2 },
			stagger = 1,
			checkpoints = { 0.5 },
			plots = 8,
		})
	end

	it("bots play the real game: they finish the tutorial and rebirth", function()
		local records = run()
		expect(#records).toBe(3)
		for _, r in records do
			expect(r.final.played > 0).toBe(true)
			if r.profile == "grinder" then
				expect(r.tutorialAt ~= nil).toBe(true)
				expect(r.rebirthAt[1] ~= nil).toBe(true)
				expect(r.hours[1] ~= nil and r.hours[1].played == 1800).toBe(true)
			end
		end
	end)

	it("keeps milestones, a time series, the cash ledger and steal events per bot", function()
		local records = Server.run({
			seed = 3,
			days = 1,
			mix = { grinder = 2, thief = 1 },
			stagger = 1,
			checkpoints = { 0.5 },
			plots = 8,
			codes = true,
			seriesEvery = 300,
		})
		for _, r in records do
			expect(#r.series > 0).toBe(true)
			expect(r.milestones.Rare ~= nil).toBe(true)
			expect((r.earnedBy.active or 0) > 0).toBe(true)
			expect((r.earnedBy.code or 0) >= 1000).toBe(true)
			expect((r.spentBy.pad or 0) > 0).toBe(true)
		end
		local json = Report.json(
			records,
			{ seeds = { 3 }, days = 1, mix = { grinder = 2, thief = 1 }, stagger = 1, checkpoints = { 0.5 } }
		)
		expect(#json.bots).toBe(3)
	end)

	it("late joiners arrive on their day and are reported under their own name", function()
		local records = Server.run({
			seed = 3,
			days = 3,
			mix = { grinder = 1 },
			stagger = 1,
			checkpoints = { 0.5 },
			plots = 8,
			late = { { profile = "casual", day = 2, count = 1 } },
		})
		expect(records[2].profile).toBe("late-casual")
		expect(records[2].joinDay).toBe(2)
		expect(records[2].series[1] == nil or records[2].series[1].days < 1).toBe(true)
	end)

	it("a flip probe buys wild slimes and sells them at once for more than they cost", function()
		local records = Server.run({
			seed = 3,
			days = 1,
			mix = { flipprobe = 1 },
			stagger = 1,
			checkpoints = { 1 },
			plots = 8,
			startLevel = 2,
		})
		local level = records[1].stats.levels["2"]
		expect(level ~= nil and level.flips > 20).toBe(true)
		expect(level.revenue > level.paid).toBe(true)
		expect(records[1].final.rebirths).toBe(2)
	end)

	it("bots merge in the plot vat, so a Secret is not minutes away", function()
		local records =
			Server.run({ seed = 3, days = 1, mix = { grinder = 2 }, stagger = 1, checkpoints = { 0.5 }, plots = 8 })
		for _, r in records do
			expect(r.milestones.Secret == nil or r.milestones.Secret.played > 600).toBe(true)
		end
	end)

	it("is deterministic for a seed", function()
		local a, b = run(), run()
		for i, r in a do
			expect(r.final.earned).toBe(b[i].final.earned)
			expect(r.final.rebirths).toBe(b[i].final.rebirths)
		end
	end)
end)
