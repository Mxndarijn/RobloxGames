--!strict
-- Procedural Bat / PvP item animations, pure part (src/ui/PvpAnimLogic, CONTRACT.md §26.3): which clip each item
-- plays, that every clip starts and ends at rest, the hold pose and how it blends in.
local Config = require("../../src/shared/Config")
local Logic = require("../../src/ui/PvpAnimLogic")
local TestRunner = require("../TestRunner")

local describe, it, expect = TestRunner.describe, TestRunner.it, TestRunner.expect

local function magnitude(pose: any): number
	local m = 0
	for _, angles in pose or {} do
		for _, v in angles do
			m = math.max(m, math.abs(v))
		end
	end
	return m
end

describe("PvpAnimLogic.kindFor", function()
	it("gives the Bat and every PvP item a clip by line", function()
		expect(Logic.kindFor("Bat", Config.PVP_TOOLS)).toBe("swing")
		for _, tool in Config.PVP_TOOLS do
			local kind = Logic.kindFor(tool.id, Config.PVP_TOOLS)
			expect(kind ~= nil and Logic.CLIPS[kind :: string] ~= nil).toBe(true)
		end
		expect(Logic.kindFor("KnockGlove3", Config.PVP_TOOLS)).toBe("punch")
		expect(Logic.kindFor("GooBlaster2", Config.PVP_TOOLS)).toBe("blast")
		expect(Logic.kindFor("GooTrap1", Config.PVP_TOOLS)).toBe("throw")
		expect(Logic.kindFor("FunBouncePad", Config.PVP_TOOLS)).toBe("throw")
		expect(Logic.kindFor("FunSqueaky", Config.PVP_TOOLS)).toBe("swing")
		expect(Logic.kindFor("FunConfetti", Config.PVP_TOOLS)).toBe("use")
	end)
	it("unknown or missing ids play nothing", function()
		expect(Logic.kindFor("Nope", Config.PVP_TOOLS)).toBeNil()
		expect(Logic.kindFor(nil, Config.PVP_TOOLS)).toBeNil()
	end)
end)

describe("PvpAnimLogic.pose", function()
	it("every clip moves clearly in the middle and is over before the next use can start", function()
		for kind, clip in Logic.CLIPS do
			expect(magnitude(Logic.pose(kind, clip.seconds * 0.4)) > 0.2).toBe(true)
			expect(Logic.pose(kind, clip.seconds)).toBeNil()
			expect(clip.seconds <= Config.PVP.MIN_COOLDOWN).toBe(true)
		end
		expect(Logic.CLIPS.swing.seconds <= Config.BAT.SWING_GAP).toBe(true)
	end)
	it("every clip starts and ends at rest, so no joint is left bent", function()
		for kind, clip in Logic.CLIPS do
			expect(magnitude(Logic.pose(kind, 0)) < 1e-6).toBe(true)
			expect(magnitude(Logic.pose(kind, clip.seconds - 1e-4)) < 0.01).toBe(true)
			expect(#clip.keys >= 3).toBe(true)
			expect(clip.keys[1].t).toBe(0)
			expect(clip.keys[#clip.keys].t).toBe(1)
		end
	end)
	it("only poses R15 joints it knows", function()
		local known: { [string]: boolean } = {}
		for _, name in Logic.JOINTS do
			known[name] = true
		end
		for kind, clip in Logic.CLIPS do
			for _, key in clip.keys do
				for joint in key.pose do
					expect(`{kind}.{joint} {known[joint] == true}`).toBe(`{kind}.{joint} true`)
				end
			end
		end
	end)
	it("the glove punch winds the fist back, then jabs with the chest turning into it", function()
		local clip = Logic.CLIPS.punch
		local windUp = Logic.pose("punch", clip.seconds * 0.3) :: any
		local strike = Logic.pose("punch", clip.seconds * 0.5) :: any
		expect(windUp.RightElbow.rx > 0.5).toBe(true)
		expect(windUp.Waist.ry < 0).toBe(true)
		expect(strike.Waist.ry > 0).toBe(true)
	end)
	it("the blaster recoil kicks the arm up and the chest back", function()
		local recoil = Logic.pose("blast", Logic.CLIPS.blast.seconds * 0.3) :: any
		expect(recoil.RightShoulder.rx > 0.3).toBe(true)
		expect(recoil.Waist.rx > 0).toBe(true)
	end)
	it("rejects unknown clips and bad times", function()
		expect(Logic.pose("nope", 0.1)).toBeNil()
		expect(Logic.pose("punch", -1)).toBeNil()
		expect(Logic.pose("punch", 0 / 0)).toBeNil()
	end)
end)

describe("PvpAnimLogic hold pose", function()
	it("holds every PvP item out front; blasters with both hands; the Bat keeps its Tool pose", function()
		for _, tool in Config.PVP_TOOLS do
			local hold = Logic.holdFor(tool.id, Config.PVP_TOOLS) :: any
			expect(hold.RightShoulder.rx > 1).toBe(true)
			expect(hold.LeftShoulder ~= nil).toBe(tool.line == "Blaster")
		end
		expect(Logic.holdFor("Bat", Config.PVP_TOOLS)).toBeNil()
		expect(Logic.holdFor(nil, Config.PVP_TOOLS)).toBeNil()
	end)
	it("combine scales the hold by its weight and adds the use clip on top", function()
		local out = Logic.combine(Logic.HOLD, 0.5, { RightShoulder = { rx = 0.2 }, Waist = { ry = 0.1 } }) :: any
		local want = (Logic.HOLD.RightShoulder.rx :: number) * 0.5 + 0.2
		expect(math.abs(out.RightShoulder.rx - want) < 1e-9).toBe(true)
		expect(out.Waist.ry).toBe(0.1)
		expect(next(Logic.combine(Logic.HOLD, 0, nil))).toBeNil()
	end)
	it("fades in and out at HOLD_RATE without overshooting", function()
		expect(Logic.approach(0, 1, 0.05)).toBe(Logic.HOLD_RATE * 0.05)
		expect(Logic.approach(0.9, 1, 1)).toBe(1)
		expect(Logic.approach(0.1, 0, 1)).toBe(0)
	end)
end)
