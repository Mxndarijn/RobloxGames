--!strict
local fs = require("@lune/fs")

local Config = require("../src/shared/Config")
local SnowCover = require("../src/visuals/shared/SnowCover")
local TestRunner = require("./TestRunner")
local WeatherLook = require("../src/visuals/shared/WeatherLook")
local WorldLayout = require("../src/visuals/shared/WorldLayout")

local describe, it, expect = TestRunner.describe, TestRunner.it, TestRunner.expect

local function run(level: number, seconds: number, snowing: boolean, dt: number): number
	local t = 0
	while t < seconds do
		level = SnowCover.step(level, dt, snowing)
		t += dt
	end
	return level
end

describe("SnowCover (F2)", function()
	it("builds from bare to full over BUILD_SECONDS while it snows", function()
		expect(run(0, SnowCover.BUILD_SECONDS / 2, true, 0.1) > 0.45).toBe(true)
		expect(run(0, SnowCover.BUILD_SECONDS / 2, true, 0.1) < 0.55).toBe(true)
		expect(run(0, SnowCover.BUILD_SECONDS + 1, true, 0.1)).toBe(1)
	end)
	it("melts from full to bare over MELT_SECONDS once the snow stops", function()
		expect(run(1, SnowCover.MELT_SECONDS / 2, false, 0.1) > 0.45).toBe(true)
		expect(run(1, SnowCover.MELT_SECONDS + 1, false, 0.1)).toBe(0)
	end)
	it("is independent of the frame rate and never leaves 0..1", function()
		local a, b = run(0, 20, true, 1 / 60), run(0, 20, true, 1 / 20)
		expect(math.abs(a - b) < 0.01).toBe(true)
		expect(SnowCover.step(0.99, 100, true)).toBe(1)
		expect(SnowCover.step(0.01, 100, false)).toBe(0)
	end)
	it("a short snow shower leaves a partial cover that melts from where it was", function()
		local partial = run(0, 10, true, 0.1)
		expect(partial > 0 and partial < 1).toBe(true)
		local later = run(partial, 5, false, 0.1)
		expect(later < partial).toBe(true)
	end)
	it("visible / settled", function()
		expect(SnowCover.visible(0)).toBe(false)
		expect(SnowCover.visible(0.2)).toBe(true)
		expect(SnowCover.settled(1, true)).toBe(true)
		expect(SnowCover.settled(0, false)).toBe(true)
		expect(SnowCover.settled(0.5, true)).toBe(false)
		expect(SnowCover.settled(0.5, false)).toBe(false)
	end)
	it("adds no part and no mesh slot: it tints what is there", function()
		expect(SnowCover.PART_COUNT).toBe(0)
		expect(SnowCover.MESH_SLOTS).toBe(0)
		expect(SnowCover.MESH_SLOTS <= WorldLayout.RUNTIME_SLOT_ALLOWANCE).toBe(true)
		local source = fs.readFile("src/visuals/client/SnowGround.luau")
		expect(string.find(source, 'Instance.new("Part"', 1, true)).toBe(nil)
		expect(string.find(source, 'Instance.new("MeshPart"', 1, true)).toBe(nil)
		expect(string.find(source, "Instance.new", 1, true)).toBe(nil)
	end)
	it("snow flakes reach the ground: speed x lifetime beats the emitter height at the steepest spread", function()
		local flakes = WeatherLook.EMITTERS.Flakes
		local minSpeed, spreadDeg, height = 7, 15, 42 -- WeatherFx makeEmitter / SNOW_EMITTER_Y
		local down = minSpeed * flakes.lifetime * math.cos(math.rad(spreadDeg * 1.5))
		expect(down >= height).toBe(true)
		expect(Config.WEATHER_PARTICLE_CAP >= 1).toBe(true)
	end)
end)

describe("SnowCover late join", function()
	local B, M = SnowCover.BUILD_SECONDS, SnowCover.MELT_SECONDS

	it("joining 10 s into the build-up shows the partial level", function()
		local level = SnowCover.levelAt(true, 1000, nil, 1010)
		expect(math.abs(level - 10 / B) < 1e-9).toBe(true)
		expect(SnowCover.levelAt(true, 1000, nil, 1000)).toBe(0)
		expect(SnowCover.levelAt(true, 1000, nil, 1000 + B)).toBe(1)
		expect(SnowCover.levelAt(true, 1000, nil, 1000 + B * 5)).toBe(1)
	end)

	it("joining mid-melt shows the partial level, and a finished melt is bare", function()
		local level = SnowCover.levelAt(false, 2000, 2000, 2000 + M / 3)
		expect(math.abs(level - 2 / 3) < 1e-9).toBe(true)
		expect(SnowCover.levelAt(false, 2000, 2000, 2000 + M)).toBe(0)
		expect(SnowCover.levelAt(false, 2000, 2000, 2000 + M * 4)).toBe(0)
	end)

	it("clamps a client clock that reads slightly before the stamp", function()
		expect(SnowCover.levelAt(true, 1000, nil, 999)).toBe(0)
		expect(SnowCover.levelAt(false, 1000, 1000, 999)).toBe(1)
	end)

	it("falls back when the stamps are missing", function()
		expect(SnowCover.levelAt(true, nil, nil, 500)).toBe(1) -- mid-snow, unknown start: full
		expect(SnowCover.levelAt(false, nil, nil, 500)).toBe(0) -- clear, unknown end: bare
		expect(SnowCover.levelAt(false, 100, nil, 500)).toBe(0)
		expect(SnowCover.levelAt(true, nil, 100, 500)).toBe(1)
	end)

	it("a pinned / debug-preview client builds up from 0 whatever the stamps say", function()
		expect(SnowCover.levelAt(true, 1000, nil, 1020, true)).toBe(0)
		expect(SnowCover.levelAt(true, nil, nil, 1020, true)).toBe(0)
		expect(SnowCover.levelAt(false, 1000, 1000, 1001, true)).toBe(0)
	end)

	it("continues from the placed level with step", function()
		local level = SnowCover.levelAt(true, 0, nil, B / 2)
		expect(math.abs(level - 0.5) < 1e-9).toBe(true)
		expect(SnowCover.step(level, B / 2, true)).toBe(1)
	end)
end)

describe("SnowCover tints (v2)", function()
	local function path(level: number, snowing: boolean)
		return SnowCover.tints(level, snowing).path
	end

	it("level 0 has every weight exactly 0, both phases", function()
		for _, snowing in { true, false } do
			local t = SnowCover.tints(0, snowing)
			expect(t.grass).toBe(0)
			expect(t.terrainGrass).toBe(0)
			expect(t.rock).toBe(0)
			expect(t.path).toBe(0)
		end
	end)

	it("full cover: grass is fully white, rock lighter, paths only a light frost", function()
		local t = SnowCover.tints(1, true)
		expect(t.grass).toBe(1)
		expect(t.terrainGrass).toBe(1)
		expect(t.rock > 0.2 and t.rock < 0.5).toBe(true)
		expect(t.path > 0.1 and t.path <= 0.25).toBe(true)
		expect(SnowCover.tints(1, false).path).toBe(t.path) -- a melt starts from the same look
	end)

	it("settling is monotonic up for every class", function()
		local last = SnowCover.tints(0, true)
		for i = 1, 100 do
			local t = SnowCover.tints(i / 100, true)
			expect(t.grass >= last.grass and t.terrainGrass >= last.terrainGrass).toBe(true)
			expect(t.rock >= last.rock and t.path >= last.path).toBe(true)
			last = t
		end
	end)

	it("melting is monotonic down for every class", function()
		local last = SnowCover.tints(1, false)
		for i = 99, 0, -1 do
			local t = SnowCover.tints(i / 100, false)
			expect(t.grass <= last.grass and t.terrainGrass <= last.terrainGrass).toBe(true)
			expect(t.rock <= last.rock and t.path <= last.path).toBe(true)
			last = t
		end
	end)

	it("during the melt the paths reach 0 before the grass does", function()
		local level = 1
		local pathGone, grassGone = nil, nil
		local t = 0
		while level > 0 do
			level = SnowCover.step(level, 0.1, false)
			t += 0.1
			local tints = SnowCover.tints(level, false)
			if not pathGone and tints.path == 0 then
				pathGone = t
			end
			if not grassGone and tints.grass == 0 then
				grassGone = t
			end
		end
		expect(pathGone ~= nil and grassGone ~= nil).toBe(true)
		expect((pathGone :: number) < (grassGone :: number)).toBe(true)
		expect((pathGone :: number) < SnowCover.MELT_SECONDS * 0.55).toBe(true) -- twice as fast
		expect(SnowCover.tints(0.5, false).grass > 0.4).toBe(true)
		expect(path(0.5, false)).toBe(0)
		expect(path(0.5, true) > 0.05).toBe(true) -- settling at the same level still has its frost
	end)

	it("settle full -> melt -> 0 restores the weights exactly 0", function()
		local level = run(0, SnowCover.BUILD_SECONDS + 1, true, 0.1)
		expect(level).toBe(1)
		level = run(level, SnowCover.MELT_SECONDS + 1, false, 0.1)
		local t = SnowCover.tints(level, false)
		expect(t.grass + t.terrainGrass + t.rock + t.path).toBe(0)
	end)

	it("melting differs from settling at the same level", function()
		local settle, melt = SnowCover.tints(0.5, true), SnowCover.tints(0.5, false)
		expect(melt.grass > settle.grass + 0.1).toBe(true) -- the grass holds its snow
		expect(melt.terrainGrass).toBe(melt.grass)
		expect(settle.path > melt.path).toBe(true)
		expect(SnowCover.tints(1, false).grass).toBe(SnowCover.tints(1, true).grass)
	end)

	it("quantize snaps to 1/QUANT_STEPS, is clamped and idempotent", function()
		local n = SnowCover.QUANT_STEPS
		expect(SnowCover.quantize(0)).toBe(0)
		expect(SnowCover.quantize(1)).toBe(1)
		expect(SnowCover.quantize(-3)).toBe(0)
		expect(SnowCover.quantize(7)).toBe(1)
		expect(SnowCover.quantize(0.4 / n)).toBe(0)
		expect(SnowCover.quantize(0.6 / n)).toBe(1 / n)
		local q = SnowCover.quantize(0.3337)
		expect(SnowCover.quantize(q)).toBe(q)
		-- a 60 fps build-up writes far fewer colours than frames
		local level, steps, last = 0, 0, SnowCover.quantize(0)
		for _ = 1, 60 * SnowCover.BUILD_SECONDS do
			level = SnowCover.step(level, 1 / 60, true)
			local qq = SnowCover.quantize(level)
			if qq ~= last then
				steps += 1
				last = qq
			end
		end
		expect(steps <= n).toBe(true)
	end)

	it("lerpColor is exact at 0 and 1 and mixes in between", function()
		local r, g, b = SnowCover.lerpColor(0.1234, 0.5678, 0.9, 0)
		expect(r).toBe(0.1234)
		expect(g).toBe(0.5678)
		expect(b).toBe(0.9)
		r, g, b = SnowCover.lerpColor(0.1234, 0.5678, 0.9, -1)
		expect(r).toBe(0.1234)
		r, g, b = SnowCover.lerpColor(0.1234, 0.5678, 0.9, 1)
		expect(r).toBe(SnowCover.SNOW_COLOR[1])
		expect(g).toBe(SnowCover.SNOW_COLOR[2])
		expect(b).toBe(SnowCover.SNOW_COLOR[3])
		r = SnowCover.lerpColor(0, 0, 0, 0.5)
		expect(math.abs(r - SnowCover.SNOW_COLOR[1] / 2) < 1e-12).toBe(true)
		expect(SnowCover.SNOW_COLOR[1] * 255).toBe(248)
	end)

	it("classify picks the Ground and big grass, the paths, plaza and pads; skips decor and hidden parts", function()
		expect(SnowCover.classify("Ground", "Grass", false, 640, 640, 0)).toBe("grass")
		expect(SnowCover.classify("Meadow", "LeafyGrass", false, 40, 20, 0)).toBe("grass")
		expect(SnowCover.classify("Path3", "SmoothPlastic", true, 8, 30, 0)).toBe("path")
		expect(SnowCover.classify("Plaza", "Sand", true, 60, 60, 0)).toBe("path")
		expect(SnowCover.classify("Pad_4", "SmoothPlastic", false, 8, 8, 0)).toBe("path")
		expect(SnowCover.classify("Pad_x", "SmoothPlastic", false, 8, 8, 0)).toBe(nil)
		expect(SnowCover.classify("Blade", "Grass", false, 0.5, 3, 0)).toBe(nil) -- grass blades and bushes
		expect(SnowCover.classify("Chunk", "Grass", false, 55, 55, 1)).toBe(nil) -- hidden mesh slot
		expect(SnowCover.classify("Base", "Pavement", false, 60, 60, 0)).toBe(nil)
	end)
end)

describe("SnowCover late join phase", function()
	local B, M = SnowCover.BUILD_SECONDS, SnowCover.MELT_SECONDS

	it("a joiner mid-build is settling, a joiner mid-melt is melting with the paths cleared first", function()
		local phase, level = SnowCover.phaseAt(true, 1000, nil, 1000 + B / 2)
		expect(phase).toBe("settling")
		expect(math.abs(level - 0.5) < 1e-9).toBe(true)
		phase, level = SnowCover.phaseAt(false, 2000, 2000, 2000 + M * 0.6)
		expect(phase).toBe("melting")
		expect(math.abs(level - 0.4) < 1e-9).toBe(true)
		local t = SnowCover.tints(level, false)
		expect(t.path).toBe(0)
		expect(t.grass > 0).toBe(true)
	end)

	it("a pin starts from 0 in either phase; missing stamps fall back", function()
		local phase, level = SnowCover.phaseAt(false, 2000, 2000, 2001, true)
		expect(phase).toBe("melting")
		expect(level).toBe(0)
		phase, level = SnowCover.phaseAt(true, nil, nil, 500)
		expect(phase).toBe("settling")
		expect(level).toBe(1)
	end)
end)
