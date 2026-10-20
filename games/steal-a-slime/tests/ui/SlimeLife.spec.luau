--!strict
-- Living slimes (src/ui/SlimeLife.luau, TODO v28 #17): per-rarity params,
-- distance / count gating, sparkle cap, no hops of their own (a forced hop
-- still works), the walking sway and pose bounds.
local SlimeLife = require("../../src/ui/SlimeLife")
local TestRunner = require("../TestRunner")

local describe, it, expect = TestRunner.describe, TestRunner.it, TestRunner.expect

-- Deterministic uniform [0, 1) stream.
local function lcg(seed: number): () -> number
	local s = seed
	return function()
		s = (s * 1103515245 + 12345) % 2147483648
		return s / 2147483648
	end
end

local function cand(id: string, distance: number, state: string?, extra: { [string]: any }?): SlimeLife.Candidate
	local c: any = { id = id, distance = distance, state = state or "Wild", tier = 1 }
	for k, v in extra or {} do
		c[k] = v
	end
	return c
end

local function count(set: { [string]: boolean }): number
	local n = 0
	for _ in set do
		n += 1
	end
	return n
end

describe("SlimeLife.params per rarity", function()
	it("rarer tiers wobble more and squish at least as much", function()
		for tier = 2, SlimeLife.MAX_TIER do
			local lo, hi = SlimeLife.params(tier - 1, "Wild"), SlimeLife.params(tier, "Wild")
			expect(hi.wobble > lo.wobble).toBe(true)
			expect(hi.squishAmp >= lo.squishAmp).toBe(true)
			expect(hi.sparkleRate >= lo.sparkleRate).toBe(true)
		end
	end)

	it("Common and Uncommon don't sparkle; Rare and up do, more with rarity", function()
		expect(SlimeLife.params(1).sparkleRate).toBe(0)
		expect(SlimeLife.params(2).sparkleRate).toBe(0)
		expect(SlimeLife.params(3).sparkleRate > 0).toBe(true)
		expect(SlimeLife.params(6).sparkleRate > SlimeLife.params(3).sparkleRate).toBe(true)
		expect(SlimeLife.params(4).landBurst > 0).toBe(true)
	end)

	it("keeps every emitter within the per-emitter particle limit", function()
		for tier = 1, SlimeLife.MAX_TIER do
			local p = SlimeLife.params(tier)
			local alive = p.sparkleRate * SlimeLife.SPARKLE_LIFETIME[2] + p.landBurst
			expect(alive <= SlimeLife.MAX_SPARKLES_ALIVE + 10).toBe(true)
			expect(p.sparkleRate * SlimeLife.SPARKLE_LIFETIME[2] <= SlimeLife.MAX_SPARKLES_ALIVE).toBe(true)
		end
	end)

	it("wild slimes sway as they walk; pad slimes rest without a sway", function()
		for tier = 1, SlimeLife.MAX_TIER do
			local wild, pad = SlimeLife.params(tier, "Wild"), SlimeLife.params(tier, "Pad")
			expect(wild.sway > 0 and wild.sway <= 0.1).toBe(true)
			expect(pad.sway).toBe(0)
			expect(pad.hopHeight < wild.hopHeight).toBe(true)
		end
	end)

	it("clamps unknown tiers instead of erroring", function()
		expect(SlimeLife.params(nil).tier).toBe(1)
		expect(SlimeLife.params(0).tier).toBe(1)
		expect(SlimeLife.params(0 / 0).tier).toBe(1)
		expect(SlimeLife.params(99).tier).toBe(SlimeLife.MAX_TIER)
		expect(SlimeLife.params(3.7).tier).toBe(3)
	end)
end)

describe("SlimeLife gating", function()
	it("only animates Wild and Pad slimes that aren't despawning", function()
		expect(SlimeLife.eligible(cand("a", 10, "Wild"))).toBe(true)
		expect(SlimeLife.eligible(cand("a", 10, "Pad"))).toBe(true)
		expect(SlimeLife.eligible(cand("a", 10, "Carried"))).toBe(false)
		expect(SlimeLife.eligible(cand("a", 10, "Escaping"))).toBe(false)
		expect(SlimeLife.eligible({ id = "a", distance = 10 })).toBe(false)
		expect(SlimeLife.eligible(cand("a", 10, "Wild", { despawning = true }))).toBe(false)
	end)

	it("skips slimes beyond MAX_DISTANCE (and NaN distances)", function()
		expect(SlimeLife.eligible(cand("a", SlimeLife.MAX_DISTANCE))).toBe(true)
		expect(SlimeLife.eligible(cand("a", SlimeLife.MAX_DISTANCE + 1))).toBe(false)
		expect(SlimeLife.eligible(cand("a", 0 / 0))).toBe(false)
	end)

	it("keeps an active slime up to KEEP_DISTANCE (hysteresis)", function()
		local d = (SlimeLife.MAX_DISTANCE + SlimeLife.KEEP_DISTANCE) / 2
		expect(SlimeLife.KEEP_DISTANCE > SlimeLife.MAX_DISTANCE).toBe(true)
		expect(count(SlimeLife.select({ cand("a", d) }, {}))).toBe(0)
		expect(SlimeLife.select({ cand("a", d) }, { a = true }).a).toBe(true)
		expect(count(SlimeLife.select({ cand("a", SlimeLife.KEEP_DISTANCE + 1) }, { a = true }))).toBe(0)
	end)

	it("caps the active set at MAX_ACTIVE, nearest first", function()
		local cands = {}
		for i = 1, SlimeLife.MAX_ACTIVE * 3 do
			table.insert(cands, cand(`s{i}`, (SlimeLife.MAX_ACTIVE * 3 - i) + 0.5))
		end
		local picked = SlimeLife.select(cands, nil)
		expect(count(picked)).toBe(SlimeLife.MAX_ACTIVE)
		for i = 1, SlimeLife.MAX_ACTIVE * 3 do
			local nearest = cands[i].distance < SlimeLife.MAX_ACTIVE
			expect(picked[cands[i].id] == true).toBe(nearest)
		end
	end)

	it("an active far slime never beats a nearer new one", function()
		local cands = { cand("far", SlimeLife.KEEP_DISTANCE - 1) }
		for i = 1, SlimeLife.MAX_ACTIVE do
			table.insert(cands, cand(`near{i}`, i))
		end
		local picked = SlimeLife.select(cands, { far = true })
		expect(picked.far).toBe(nil)
		expect(count(picked)).toBe(SlimeLife.MAX_ACTIVE)
	end)

	it("sparkles at most MAX_SPARKLING active slimes, rarest first, none for Common", function()
		local cands, active = {}, {}
		for i = 1, 20 do
			local tier = (i % SlimeLife.MAX_TIER) + 1
			table.insert(cands, cand(`s{i}`, i, "Wild", { tier = tier }))
			active[`s{i}`] = true
		end
		table.insert(cands, cand("inactive", 0.1, "Wild", { tier = 6 }))
		local set = SlimeLife.sparkleSet(cands, active)
		expect(count(set) <= SlimeLife.MAX_SPARKLING).toBe(true)
		expect(set.inactive).toBe(nil)
		local minPicked, maxSkipped = math.huge, 0
		for _, c in cands do
			if active[c.id] then
				if set[c.id] then
					minPicked = math.min(minPicked, c.tier :: number)
				elseif SlimeLife.params(c.tier).sparkleRate > 0 then
					maxSkipped = math.max(maxSkipped, c.tier :: number)
				end
				if (c.tier :: number) <= 2 then
					expect(set[c.id]).toBe(nil)
				end
			end
		end
		expect(minPicked >= maxSkipped).toBe(true)
	end)
end)

describe("SlimeLife clock and pose", function()
	it("never hops on its own, wild or pad, however long it lives", function()
		for _, state in { "Wild", "Pad" } do
			local p = SlimeLife.params(4, state)
			local rand = lcg(11)
			local clock = SlimeLife.newClock(p, 0, rand)
			local t = 0
			while t < 300 do
				expect(SlimeLife.advance(clock, p, t, rand)).toBe(false)
				expect(SlimeLife.pose(p, clock, t).lift).toBe(0)
				t += 1 / 30
			end
		end
	end)

	it("a forced hop: lift peaks at hopHeight mid-air, zero on the ground", function()
		local p = SlimeLife.params(1, "Wild")
		local clock = SlimeLife.newClock(p, 0, lcg(7))
		clock.hopAt = 5
		local at = clock.hopAt
		expect((SlimeLife.hop(p, clock, at - 1))).toBe(0)
		local peak = SlimeLife.hop(p, clock, at + SlimeLife.AIR / 2)
		expect(math.abs(peak - p.hopHeight) < 1e-9).toBe(true)
		expect((SlimeLife.hop(p, clock, at + SlimeLife.AIR + 0.01))).toBe(0)
	end)

	it("squats before take-off and squashes on landing", function()
		local p = SlimeLife.params(1, "Wild")
		local clock = SlimeLife.newClock(p, 0, lcg(3))
		clock.hopAt = 5
		local _, windup = SlimeLife.hop(p, clock, clock.hopAt - 0.01)
		local _, rise = SlimeLife.hop(p, clock, clock.hopAt + 0.01)
		local _, land = SlimeLife.hop(p, clock, clock.hopAt + SlimeLife.AIR + 0.01)
		expect(windup > 0).toBe(true)
		expect(rise < 0).toBe(true) -- stretched
		expect(land > 0).toBe(true)
	end)

	it("reports a forced hop's landing once, then stays on the ground", function()
		local p = SlimeLife.params(4, "Pad")
		local rand = lcg(11)
		local clock = SlimeLife.newClock(p, 0, rand)
		clock.hopAt = 1
		local landings, t = 0, 0
		while t < 30 do
			if SlimeLife.advance(clock, p, t, rand) then
				landings += 1
			end
			t += 1 / 60
		end
		expect(landings).toBe(1)
		expect(clock.hopAt).toBe(math.huge)
	end)

	it("keeps squash, wobble and look within bounds for every tier", function()
		for tier = 1, SlimeLife.MAX_TIER do
			for _, state in { "Wild", "Pad" } do
				local p = SlimeLife.params(tier, state)
				local rand = lcg(tier * 13)
				local clock = SlimeLife.newClock(p, 0, rand)
				local t = 0
				while t < 30 do
					SlimeLife.advance(clock, p, t, rand)
					local pose = SlimeLife.pose(p, clock, t)
					expect(pose.sy >= SlimeLife.SQUASH_LIMIT[1] and pose.sy <= SlimeLife.SQUASH_LIMIT[2]).toBe(true)
					expect(math.abs(pose.sx * pose.sy * pose.sz - 1) < 1e-9).toBe(true)
					expect(math.abs(pose.roll) <= p.wobble + p.sway + 1e-9).toBe(true)
					expect(math.abs(pose.yaw) <= p.lookYaw + p.sway / 2 + 1e-9).toBe(true)
					expect(pose.lift >= 0 and pose.lift <= p.hopHeight + 1e-9).toBe(true)
					t += 0.05
				end
			end
		end
	end)
end)

describe("SlimeLife runner", function()
	it("uses only the built-in sparkle texture, no uploaded assets", function()
		expect(string.find(SlimeLife.SPARKLE_TEXTURE, "^rbxasset://textures/particles/") ~= nil).toBe(true)
	end)
end)
