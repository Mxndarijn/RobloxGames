--!strict
local Config = require("../src/shared/Config")
local ParadeLane = require("../src/shared/ParadeLane")
local ServerFixtures = require("./ServerFixtures")
local Spawner = require("../src/server/Spawner")
local TestRunner = require("./TestRunner")
local Volcano = require("../src/shared/Volcano")

local describe, it, expect = TestRunner.describe, TestRunner.it, TestRunner.expect
local T0 = ServerFixtures.T0
local LIFE = Config.WILD_LIFETIME
local HOP = ParadeLane.HOP_SECONDS
local TAU = math.pi * 2

-- Signed smallest difference a - b in (-pi, pi].
local function angleDiff(a: number, b: number): number
	local d = (a - b) % TAU
	return if d > math.pi then d - TAU else d
end

describe("ParadeLane lane / time mapping", function()
	it("sits at the entry while hopping on, then walks to the gate centre by expiry", function()
		local entry = ParadeLane.GATE_ANGLE - ParadeLane.GATE_HALF_WIDTH
		expect(ParadeLane.remaining(T0, T0 + LIFE, T0)).toBe(1)
		expect(ParadeLane.remaining(T0, T0 + LIFE, T0 + HOP)).toBeCloseTo(1, 1e-6)
		expect(angleDiff(ParadeLane.angleAt(1), entry)).toBeCloseTo(0, 1e-9)
		expect(ParadeLane.remaining(T0, T0 + LIFE, T0 + LIFE)).toBe(0)
		expect(ParadeLane.angleAt(0)).toBeCloseTo(ParadeLane.GATE_ANGLE, 1e-9)
		expect(ParadeLane.remaining(T0, T0 + LIFE, T0 + LIFE + 30)).toBe(0)
	end)
	it("gate is +Z on the centreline r 68", function()
		local x, z = ParadeLane.positionOnLane(T0, T0 + LIFE, T0 + LIFE)
		expect(x).toBeCloseTo(0, 1e-9)
		expect(z).toBeCloseTo(ParadeLane.LANE_RADIUS, 1e-9)
		expect(ParadeLane.LANE_RADIUS).toBe(68)
	end)
	it("midpoint of the walk is half the sweep from the gate", function()
		local mid = T0 + HOP + (LIFE - HOP) / 2
		expect(ParadeLane.remaining(T0, T0 + LIFE, mid)).toBeCloseTo(0.5, 1e-6)
		expect(ParadeLane.arcToGate(T0, T0 + LIFE, mid)).toBeCloseTo(ParadeLane.SWEEP / 2, 1e-6)
		local x, z = ParadeLane.positionOnLane(T0, T0 + LIFE, mid)
		expect(math.sqrt(x * x + z * z)).toBeCloseTo(68, 1e-9)
	end)
	it("arc to the gate only shrinks as time passes (monotonic)", function()
		local last = math.huge
		for t = T0, T0 + LIFE + 2, 0.25 do
			local arc = ParadeLane.arcToGate(T0, T0 + LIFE, t)
			expect(arc <= last).toBeTruthy()
			last = arc
		end
		expect(last).toBe(0)
	end)
	it("angle moves in one direction (decreasing, kit counter-clockwise) every step", function()
		local prev = ParadeLane.angleAt(ParadeLane.remaining(T0, T0 + LIFE, T0 + HOP))
		for t = T0 + HOP + 1, T0 + LIFE, 1 do
			local a = ParadeLane.angleAt(ParadeLane.remaining(T0, T0 + LIFE, t))
			local d = angleDiff(a, prev)
			expect(d < 0).toBeTruthy()
			prev = a
		end
	end)
	it("works for the Boss lifetime too", function()
		expect(ParadeLane.remaining(T0, T0 + Config.BOSS_LIFETIME, T0 + Config.BOSS_LIFETIME)).toBe(0)
		local mid = T0 + HOP + (Config.BOSS_LIFETIME - HOP) / 2
		expect(ParadeLane.remaining(T0, T0 + Config.BOSS_LIFETIME, mid)).toBeCloseTo(0.5, 1e-6)
	end)
end)

describe("ParadeLane ring warn", function()
	it("warn window is the last 5..8 s and matches the despawn telegraph", function()
		expect(ParadeLane.WARN_SECONDS >= 5 and ParadeLane.WARN_SECONDS <= 8).toBeTruthy()
		expect(ParadeLane.WARN_SECONDS).toBe(Config.DESPAWN_TELEGRAPH_SECONDS)
		local W = ParadeLane.WARN_SECONDS
		expect(ParadeLane.inWarnWindow(T0 + LIFE - W - 0.01, T0 + LIFE)).toBe(false)
		expect(ParadeLane.inWarnWindow(T0 + LIFE - W, T0 + LIFE)).toBe(true)
		expect(ParadeLane.inWarnWindow(T0 + LIFE - 0.01, T0 + LIFE)).toBe(true)
		expect(ParadeLane.inWarnWindow(T0 + LIFE, T0 + LIFE)).toBe(false)
		expect(ParadeLane.inWarnWindow(T0 + LIFE - 7, T0 + LIFE, 8)).toBe(true)
	end)
	it("the warning starts on the last 45° lane piece before the gate centre", function()
		local arc = ParadeLane.arcToGate(T0, T0 + LIFE, T0 + LIFE - ParadeLane.WARN_SECONDS)
		expect(arc <= math.pi / 4).toBeTruthy()
	end)
	it("billboard text says leaving! only on the parade", function()
		expect(ParadeLane.warnText(3, true)).toBe("leaving! 3")
		expect(ParadeLane.warnText(3, false)).toBe("3")
	end)
end)

describe("ParadeLane.place", function()
	it("moves a lane wild and leaves a dropped one alone", function()
		local wild = { angle = 1, radius = 40, position = nil :: any, spawnedAt = T0, expiresAt = T0 + LIFE }
		ParadeLane.place(wild, T0 + LIFE)
		expect(wild.radius).toBe(68)
		expect(wild.angle).toBeCloseTo(ParadeLane.GATE_ANGLE, 1e-9)
		local dropped = { angle = 1, radius = 40, position = "here" :: any, spawnedAt = T0, expiresAt = T0 + LIFE }
		ParadeLane.place(dropped, T0 + 30)
		expect(dropped.angle).toBe(1)
		expect(dropped.radius).toBe(40)
	end)
end)

describe("Parade flag off (default): wild placement unchanged", function()
	it("defaults to false", function()
		expect(Config.FEATURES.Parade).toBe(false)
		expect(ParadeLane.enabled()).toBe(false)
		expect(ParadeLane.enabled({ Parade = true })).toBe(true)
		expect(ParadeLane.enabled({})).toBe(false)
	end)
	it("spawnOne keeps the Volcano.roll landing (same rng stream)", function()
		local a = ServerFixtures.world()
		local b = ServerFixtures.world()
		for _ = 1, 50 do
			local id = Spawner.spawnOne(a, T0)
			local drop = Volcano.roll(b.rng, b.newId(), false, Spawner.pityTier(b.pity))
			b.rng:float() -- Spawner.price roll
			local tier = drop.slime.tier
			b.pity.sinceEpic = if tier >= 4 then 0 else b.pity.sinceEpic + 1
			b.pity.sinceLegendary = if tier >= 5 then 0 else b.pity.sinceLegendary + 1
			expect(a.wild[id].angle).toBe(drop.angle)
			expect(a.wild[id].radius).toBe(drop.radius)
		end
	end)
	it("step never moves wilds off their landing band", function()
		local world = ServerFixtures.world()
		Spawner.step(world, T0)
		local before = {}
		for id, wild in world.wild do
			before[id] = { wild.angle, wild.radius }
		end
		for t = T0, T0 + LIFE - 1, 0.5 do
			Spawner.step(world, t)
		end
		for id, wild in world.wild do
			expect(wild.radius >= Volcano.MIN_RADIUS and wild.radius <= Volcano.MAX_RADIUS).toBeTruthy()
			local was = before[id]
			if was then
				expect(wild.angle).toBe(was[1])
				expect(wild.radius).toBe(was[2])
			end
		end
	end)
end)
