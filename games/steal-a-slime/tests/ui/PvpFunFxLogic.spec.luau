--!strict
-- Fun item effects, pure part (src/ui/PvpFunFxLogic, CONTRACT.md §26.4): proxy key lists end at rest and fit their
-- time, the proxy size maths, the lob velocity, the hat-slime walk, the bounded effect list and the use poses.
local Config = require("../../src/shared/Config")
local Logic = require("../../src/ui/PvpFunFxLogic")
local PvpAnimLogic = require("../../src/ui/PvpAnimLogic")
local TestRunner = require("../TestRunner")

local describe, it, expect = TestRunner.describe, TestRunner.it, TestRunner.expect
local FUN = Config.PVP_FUN

local function near(a: number, b: number, eps: number?): boolean
	return math.abs(a - b) < (eps or 1e-6)
end

local function last(keys: { Logic.Key }): Logic.Key
	return keys[#keys]
end

local function atRest(key: Logic.Key): boolean
	return key.scale[1] == 1 and key.scale[2] == 1 and key.scale[3] == 1
end

describe("PvpFunFxLogic proxy keys", function()
	it("a squashed slime goes flat, springs back and ends at rest within its squash time", function()
		for _, combo in { false, true } do
			local keys = Logic.slimeSquash(combo)
			expect(keys[1].scale[2] < 0.5).toBe(true)
			expect(atRest(last(keys))).toBe(true)
			expect(last(keys).offset).toEqual({ 0, 0, 0 })
			expect(Logic.seconds(keys) <= FUN.HAMMER.SLIME_SQUASH_SECONDS).toBe(true)
		end
		expect(Logic.slimeSquash(true)[1].scale[2] < Logic.slimeSquash(false)[1].scale[2]).toBe(true)
	end)
	it("a pancaked player is flatter and wider than tall, then springs back to rest", function()
		local flat = Logic.pancake(false)[1]
		expect(flat.scale[2] < 0.2 and flat.scale[1] > 1).toBe(true)
		expect(atRest(last(Logic.spring(false)))).toBe(true)
		local tool = Config.PVP_TOOLS[1]
		for _, def in Config.PVP_TOOLS do
			if def.id == "FunSqueaky" then
				tool = def
			end
		end
		expect(Logic.seconds(Logic.pancake(true)) < (tool.control :: number)).toBe(true)
	end)
	it("a floating slime rises, drifts, lands where asked and fits its float time", function()
		local keys = Logic.float(5, FUN.BUBBLES.SLIME_FLOAT_SECONDS, { 3, -2 })
		expect(keys[1].offset[2]).toBe(5)
		expect(last(keys).offset).toEqual({ 3, 0, -2 })
		expect(atRest(last(keys))).toBe(true)
		expect(near(Logic.seconds(keys), FUN.BUBBLES.SLIME_FLOAT_SECONDS, 0.05)).toBe(true)
	end)
	it("hops reach their height and end at rest", function()
		local keys = Logic.hop(8, 2)
		local top = 0
		for _, k in keys do
			top = math.max(top, k.offset[2])
		end
		expect(top).toBe(8)
		expect(atRest(last(keys))).toBe(true)
		expect(last(keys).offset).toEqual({ 0, 0, 0 })
	end)
	it("every key names a real easing style and direction", function()
		local styles = { Linear = true, Sine = true, Back = true, Quad = true }
		local dirs = { In = true, Out = true, InOut = true }
		for _, keys in
			{
				Logic.slimeSquash(true),
				Logic.pancake(true),
				Logic.spring(true),
				Logic.float(4, 2.5, {}),
				Logic.hop(3, 3),
			}
		do
			for _, k in keys do
				expect(styles[k.style] == true and dirs[k.dir] == true and k.seconds >= 0).toBe(true)
			end
		end
	end)
end)

describe("PvpFunFxLogic maths", function()
	it("a part aligned with the proxy scales by the proxy's own factors; a turned one by its axes", function()
		local aligned = Logic.axisScale({ { 1, 0, 0 }, { 0, 1, 0 }, { 0, 0, 1 } }, { 2, 0.5, 3 })
		expect(aligned).toEqual({ 2, 0.5, 3 })
		local turned = Logic.axisScale({ { 0, 1, 0 }, { 1, 0, 0 }, { 0, 0, 1 } }, { 2, 0.5, 3 })
		expect(turned).toEqual({ 0.5, 2, 3 })
		local tilted = Logic.axisScale({ { math.sqrt(0.5), math.sqrt(0.5), 0 }, { 0, 1, 0 }, { 0, 0, 1 } }, { 1, 1, 1 })
		expect(near(tilted[1], 1)).toBe(true)
	end)
	it("a lob launched with the ballistic velocity lands on its target after its flight", function()
		local from, to = { X = 0, Y = 5, Z = 0 }, { X = 30, Y = 2, Z = -10 }
		local t, g = 0.8, 196.2
		local v = Logic.ballistic(from, to, t, g)
		expect(near(from.X + v.X * t, to.X)).toBe(true)
		expect(near(from.Z + v.Z * t, to.Z)).toBe(true)
		expect(near(from.Y + v.Y * t - 0.5 * g * t * t, to.Y)).toBe(true)
	end)
	it("a hat-slime walk is the same for the same seed and keeps its step", function()
		local a = Logic.hatPath(42, { X = 0, Y = 3, Z = 0 }, 10, 2)
		local b = Logic.hatPath(42, { X = 0, Y = 3, Z = 0 }, 10, 2)
		expect(a).toEqual(b)
		expect(#a).toBe(10)
		local dx, dz = a[2].X - a[1].X, a[2].Z - a[1].Z
		expect(near(math.sqrt(dx * dx + dz * dz), 2)).toBe(true)
		expect(Logic.hatPath(7, { X = 0, Y = 3, Z = 0 }, 3, 2)[1].X ~= a[1].X).toBe(true)
	end)
	it("the effect list is bounded: past its max the oldest is evicted", function()
		local q = Logic.queue(2)
		expect(q.push("a")).toBe(nil)
		expect(q.push("b")).toBe(nil)
		expect(q.push("c")).toBe("a")
		expect(q.count()).toBe(2)
		expect(q.remove("b")).toBe(true)
		expect(q.remove("b")).toBe(false)
		expect(q.items()).toEqual({ "c" })
	end)
	it("low quality halves particle counts, never below 1", function()
		expect(Logic.count(40, true)).toBe(20)
		expect(Logic.count(1, true)).toBe(1)
		expect(Logic.count(40, false)).toBe(40)
	end)
end)

describe("PvpFunFxLogic events", function()
	it("knows the Fun items and nothing else", function()
		for _, def in Config.PVP_TOOLS do
			expect(Logic.isFun(def.id)).toBe(def.line == "Fun")
		end
		expect(Logic.isFun("Bat")).toBe(false)
		expect(Logic.isFun(nil)).toBe(false)
	end)
	it("every use effect has a real pose; effects on others have none", function()
		for _, effect in { "Confetti", "Balloon", "Bubbles", "Squash", "Hat", "Disco", "Firework" } do
			local kind = Logic.useAnim(effect)
			expect(kind ~= nil and PvpAnimLogic.CLIPS[kind :: string] ~= nil).toBe(true)
		end
		for _, effect in { "Paint", "Bubble", "Pop", "Bounce", "Boing", "Dance", "Nope" } do
			expect(Logic.useAnim(effect)).toBe(nil)
		end
		for _, kind in { "dance", "flip", "hit" } do
			expect(PvpAnimLogic.CLIPS[kind] ~= nil).toBe(true)
		end
	end)
end)
