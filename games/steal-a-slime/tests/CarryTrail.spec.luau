--!strict
-- Carry trails (Visuals.CarryTrail, contract/exclusive-shop.md §9): every trail in the catalogue has a look in its own
-- colours and style; a trail shows only while carrying, near the camera, for a known id; it stays visible, behind the
-- back and below the carried slime, and its particle count stays phone-friendly.
local CarryTrail = require("../src/visuals/shared/CarryTrail")
local Config = require("../src/shared/Config")
local TestRunner = require("./TestRunner")

local describe, it, expect = TestRunner.describe, TestRunner.it, TestRunner.expect

local TRAILS = Config.EXCLUSIVE_SHOP.trails

local function sameRgb(a: { number }, b: { number }): boolean
	return a[1] == b[1] and a[2] == b[2] and a[3] == b[3]
end

describe("carry trail catalogue", function()
	it("finds every catalogue trail by id and nothing else", function()
		for _, def in TRAILS do
			expect(CarryTrail.def(def.id)).toBe(def)
		end
		expect(CarryTrail.def("nope")).toBeNil()
		expect(CarryTrail.def(nil)).toBeNil()
		expect(CarryTrail.def(7)).toBeNil()
	end)
	it("gives every trail a style the client draws", function()
		for _, def in TRAILS do
			expect(`{def.id} {table.find(CarryTrail.STYLES, def.style) ~= nil}`).toBe(`{def.id} true`)
		end
	end)
	it("draws the trail and its particles in the trail's own colours, in order", function()
		for _, def in TRAILS do
			local look = CarryTrail.look(def :: any)
			for _, seq in { look.trail.colors, look.particles.colors } do
				expect(seq[1].t).toBe(0)
				expect(seq[#seq].t).toBe(1)
				expect(sameRgb(seq[1].rgb, def.colors[1])).toBe(true)
				expect(sameRgb(seq[#seq].rgb, def.colors[#def.colors])).toBe(true)
				expect(#seq).toBe(math.max(2, #def.colors))
			end
		end
	end)
	it("gives the rainbow ribbon all five colours along a wider, longer trail", function()
		local rainbow = CarryTrail.look(CarryTrail.def("rainbow") :: any)
		local sparkle = CarryTrail.look(CarryTrail.def("sparkle") :: any)
		expect(#rainbow.trail.colors).toBe(5)
		expect(rainbow.trail.top - rainbow.trail.bottom > sparkle.trail.top - sparkle.trail.bottom).toBe(true)
		expect(rainbow.trail.lifetime > sparkle.trail.lifetime).toBe(true)
	end)
	it("uses built-in textures only (nothing to upload)", function()
		for _, def in TRAILS do
			local texture = CarryTrail.look(def :: any).particles.texture
			expect(`{def.id} {string.sub(texture, 1, 11)}`).toBe(`{def.id} rbxasset://`)
		end
	end)
	it("matches each style's particles: twinkles, falling goo blobs, rising hearts, falling stars", function()
		local function particles(id: string)
			return CarryTrail.look(CarryTrail.def(id) :: any).particles
		end
		expect(particles("sparkle").texture).toBe(CarryTrail.TEXTURES.sparkle)
		expect(particles("goo_drip").texture).toBe(CarryTrail.TEXTURES.blob)
		expect(particles("goo_drip").accel[2] < -10).toBe(true)
		expect(particles("hearts").texture).toBe(CarryTrail.TEXTURES.heart)
		expect(particles("hearts").accel[2] > 0).toBe(true)
		expect(particles("starfall").texture).toBe(CarryTrail.TEXTURES.star)
		expect(particles("starfall").accel[2] < 0).toBe(true)
	end)
end)

describe("when a trail shows", function()
	it("shows only for a known trail while carrying, within the draw distance", function()
		expect(CarryTrail.shows("sparkle", "slime_1", 10)).toBe(true)
		expect(CarryTrail.shows("sparkle", nil, 10)).toBe(false) -- not carrying
		expect(CarryTrail.shows(nil, "slime_1", 10)).toBe(false) -- nothing equipped
		expect(CarryTrail.shows("gone", "slime_1", 10)).toBe(false) -- unknown id
		expect(CarryTrail.shows("sparkle", "slime_1", CarryTrail.MAX_DISTANCE)).toBe(true)
		expect(CarryTrail.shows("sparkle", "slime_1", CarryTrail.MAX_DISTANCE + 1)).toBe(false)
	end)
	it("draws only the nearest carriers", function()
		local candidates = {}
		for i = 1, CarryTrail.MAX_DRAWN + 3 do
			table.insert(candidates, { key = i, distance = 100 - i })
		end
		local picked = CarryTrail.pick(candidates)
		local n = 0
		for _ in picked do
			n += 1
		end
		expect(n).toBe(CarryTrail.MAX_DRAWN)
		expect(picked[CarryTrail.MAX_DRAWN + 3]).toBe(true) -- the nearest
		expect(picked[1]).toBeNil() -- the farthest
		expect(CarryTrail.pick({ { key = "a", distance = 5 } }, 3).a).toBe(true)
	end)
end)

describe("trail rules", function()
	it("stays visible: opaque at the player, never near-invisible along the ribbon", function()
		for _, def in TRAILS do
			local trail = CarryTrail.look(def :: any).trail
			expect(`{def.id} {trail.transparency[1].v <= 0.1}`).toBe(`{def.id} true`)
			for _, k in trail.transparency do
				expect(`{def.id} {k.v <= 0.6}`).toBe(`{def.id} true`)
			end
			for _, k in trail.width do
				expect(`{def.id} {k.v >= 0.3}`).toBe(`{def.id} true`)
			end
			expect(`{def.id} {trail.top - trail.bottom >= 1.5}`).toBe(`{def.id} true`) -- a real ribbon, not a thread
			expect(`{def.id} {trail.lifetime >= 0.4}`).toBe(`{def.id} true`)
		end
	end)
	it("keeps the particles readable: opaque most of their life and not tiny", function()
		for _, def in TRAILS do
			local p = CarryTrail.look(def :: any).particles
			for _, k in p.transparency do
				if k.t <= 0.75 then
					expect(`{def.id} {k.v <= 0.15}`).toBe(`{def.id} true`)
				end
			end
			local biggest = 0
			for _, k in p.size do
				biggest = math.max(biggest, k.v)
			end
			expect(`{def.id} {biggest >= 0.4}`).toBe(`{def.id} true`)
		end
	end)
	it("never covers the carried slime: behind the back, below the head", function()
		for _, def in TRAILS do
			local look = CarryTrail.look(def :: any)
			expect(`{def.id} {look.trail.top <= CarryTrail.HEAD_CLEAR}`).toBe(`{def.id} true`)
			expect(`{def.id} {look.trail.back > 0}`).toBe(`{def.id} true`)
			expect(`{def.id} {look.particles.offset[3] > 0}`).toBe(`{def.id} true`)
			local rise = CarryTrail.maxRise(look.particles)
			expect(`{def.id} {rise < CarryTrail.SLIME_SEAT}`).toBe(`{def.id} true`)
		end
	end)
	it("keeps particle counts phone-friendly", function()
		for _, def in TRAILS do
			local p = CarryTrail.look(def :: any).particles
			expect(`{def.id} {CarryTrail.alive(p) <= CarryTrail.MAX_ALIVE}`).toBe(`{def.id} true`)
		end
		expect(CarryTrail.MAX_DRAWN * CarryTrail.MAX_ALIVE <= 128).toBe(true) -- whole screen
	end)
end)
