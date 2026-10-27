--!strict
-- State-driven sound cues (src/ui/SoundCues.luau).
local SoundCues = require("../../src/ui/SoundCues")
local TestRunner = require("../TestRunner")

local describe, it, expect = TestRunner.describe, TestRunner.it, TestRunner.expect

local function state(fields: { [string]: any }?): any
	local s: any = {
		boss = { active = false, meter = 0, yourPoints = 0, yourShare = 0, badges = 0 },
		dex = { found = 3, total = 40, bonusFound = 0, bonusTotal = 0, entries = {} },
		tutorialStep = 2,
	}
	for k, v in fields or {} do
		s[k] = v
	end
	return s
end

local function boss(fields: { [string]: any }): any
	local b: any = { active = true, meter = 1, yourPoints = 0, yourShare = 0, badges = 0 }
	for k, v in fields do
		b[k] = v
	end
	return b
end

local function names(cues: { SoundCues.Cue }): string
	local out = {}
	for _, cue in cues do
		table.insert(out, cue.name)
	end
	return table.concat(out, ",")
end

describe("SoundCues.diff", function()
	it("never cues on the first State after joining", function()
		local s = state({ boss = boss({ phase = "won", winnerName = "Ann" }), tutorialStep = nil })
		expect(#SoundCues.diff(nil, s, "Ann")).toBe(0)
	end)

	it("plays nothing when nothing changed", function()
		expect(#SoundCues.diff(state(), state(), "Ann")).toBe(0)
	end)

	it("plays BossDefeat once when the boss is won", function()
		local fight = state({ boss = boss({ phase = "haul" }) })
		local won = state({ boss = boss({ phase = "won", winnerName = "Bob" }) })
		expect(names(SoundCues.diff(fight, won, "Ann"))).toBe("BossDefeat")
		expect(#SoundCues.diff(won, won, "Ann")).toBe(0)
	end)

	it("leaves BossMvp to the Boss Champion Notify for the player who carried it home", function()
		local fight = state({ boss = boss({ phase = "haul" }) })
		local won = state({ boss = boss({ phase = "won", winnerName = "Ann", yourPoints = 4, yourShare = 0.5 }) })
		expect(names(SoundCues.diff(fight, won, "Ann"))).toBe("BossDefeat")
	end)

	it("plays no fanfare when the boss gets away", function()
		local fight = state({ boss = boss({ phase = "fight" }) })
		local failed = state({ boss = boss({ phase = "failed" }) })
		expect(#SoundCues.diff(fight, failed, "Ann")).toBe(0)
	end)

	it("plays DexNew when a species is discovered, not when the count stays", function()
		local before = state()
		local after = state({ dex = { found = 4, total = 40, bonusFound = 0, bonusTotal = 0, entries = {} } })
		expect(names(SoundCues.diff(before, after))).toBe("DexNew")
		expect(#SoundCues.diff(after, after)).toBe(0)
	end)

	it("ticks when the tutorial moves on or finishes, never when it goes back", function()
		local function at(step: number?): any
			local s = state()
			s.tutorialStep = step
			return s
		end
		expect(names(SoundCues.diff(at(2), at(3)))).toBe("TutorialTick")
		expect(names(SoundCues.diff(at(5), at(nil)))).toBe("TutorialTick")
		expect(#SoundCues.diff(at(3), at(2))).toBe(0)
		expect(#SoundCues.diff(at(nil), at(nil))).toBe(0)
	end)
end)

describe("SoundCues.bossMusic", function()
	it("is on during the fight and the haul only", function()
		for phase, on in { warning = false, fight = true, haul = true, won = false, failed = false } do
			expect(SoundCues.bossMusic(state({ boss = boss({ phase = phase }) }))).toBe(on)
		end
		expect(SoundCues.bossMusic(state())).toBe(false)
		expect(SoundCues.bossMusic(nil)).toBe(false)
	end)
end)

describe("SoundCues.watcher", function()
	it("keeps the previous State between pushes", function()
		local push = SoundCues.watcher("Ann")
		expect(#push(state({ tutorialStep = 1 }))).toBe(0)
		expect(names(push(state({ tutorialStep = 2 })))).toBe("TutorialTick")
		expect(#push(state({ tutorialStep = 2 }))).toBe(0)
	end)
end)
