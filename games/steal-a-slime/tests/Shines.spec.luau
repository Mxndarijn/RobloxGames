--!strict
-- Shines (contract/slime-ladder.md §45.5): weather mutations a wild slime rolls on spawn, their income, name, save
-- and how they travel.
local Carry = require("../src/server/Carry")
local Config = require("../src/shared/Config")
local Economy = require("../src/shared/Economy")
local Fixtures = require("./Fixtures")
local Genome = require("../src/shared/Genome")
local PlayerData = require("../src/shared/PlayerData")
local Rng = require("../src/shared/Rng")
local SaveData = require("../src/shared/SaveData")
local ServerFixtures = require("./ServerFixtures")
local SlimeLabel = require("../src/shared/SlimeLabel")
local SlimeLooks = require("../src/shared/SlimeLooks")
local Spawner = require("../src/server/Spawner")
local TestRunner = require("./TestRunner")

local describe, it, expect = TestRunner.describe, TestRunner.it, TestRunner.expect
local T0 = ServerFixtures.T0

-- A shine rng that returns `value` once per roll.
local function fixed(value: number): Rng.Rng
	local rng = Rng.new(1);
	(rng :: any).float = function(): number
		return value
	end
	return rng
end

-- A world whose weather is `id` (nil = no weather service, Clear).
local function inWeather(id: string?): any
	local world = ServerFixtures.world()
	world.weather = if id then { id = id, changeAt = T0 + 60 } else nil
	return world
end

describe("Config.SHINES", function()
	it("Gold x1.5 in any weather, Diamond x2 in Snow, Rainbow x3 in Starfall", function()
		local rows = {}
		for _, row in Config.SHINES do
			rows[row.id] = `x{row.mult} {row.weather or "any"} {row.chance}`
		end
		expect(rows).toEqual({ Gold = "x1.5 any 0.03", Diamond = "x2 Snow 0.04", Rainbow = "x3 Starfall 0.02" })
		for _, row in Config.SHINES do
			expect(row.weather == nil or Config.WEATHER[row.weather] ~= nil).toBe(true)
		end
	end)
end)

describe("Spawner.rollShine and the weather", function()
	it("a low roll is Gold in every weather", function()
		for _, id in { "Clear", "Rain", "Snow", "Starfall" } do
			local world = inWeather(id)
			world.shineRng = fixed(0.01)
			expect(Spawner.rollShine(world)).toBe("Gold")
		end
		local clear = inWeather(nil)
		clear.shineRng = fixed(0.01)
		expect(Spawner.rollShine(clear)).toBe("Gold")
	end)
	it("Diamond only in Snow and Rainbow only in Starfall", function()
		local function at(id: string?, roll: number): string?
			local world = inWeather(id)
			world.shineRng = fixed(roll)
			return Spawner.rollShine(world)
		end
		-- just past Gold's slice: the weather's own shine, if it has one
		expect(at("Snow", 0.04)).toBe("Diamond")
		expect(at("Starfall", 0.04)).toBe("Rainbow")
		expect(at("Clear", 0.04)).toBeNil()
		expect(at("Rain", 0.04)).toBeNil()
		expect(at(nil, 0.04)).toBeNil()
		expect(at("Starfall", 0.06)).toBeNil()
		expect(at("Snow", 0.08)).toBeNil()
	end)
	it("over many spawns each weather gives its shines at their chance and never another weather's", function()
		for _, case in
			{
				{ weather = "Clear", want = { Gold = 0.03 } },
				{ weather = "Snow", want = { Gold = 0.03, Diamond = 0.04 } },
				{ weather = "Starfall", want = { Gold = 0.03, Rainbow = 0.02 } },
			}
		do
			local world = inWeather(case.weather)
			world.shineRng = Rng.new(17)
			local counts: { [string]: number } = {}
			local n = 20000
			for _ = 1, n do
				local id = Spawner.rollShine(world)
				if id then
					counts[id] = (counts[id] or 0) + 1
				end
			end
			for id, hits in counts do
				local chance = case.want[id]
				expect(`{case.weather} {id} {chance ~= nil}`).toBe(`{case.weather} {id} true`)
				expect(math.abs(hits / n - (chance :: number)) < 0.006).toBe(true)
			end
			for id in case.want do
				expect((counts[id] or 0) > 0).toBe(true)
			end
		end
	end)
	it("spawned wild slimes carry the rolled shine", function()
		local world = inWeather("Starfall")
		world.shineRng = fixed(0.04)
		local id = Spawner.spawnSlime(world, T0)
		expect(world.wild[id].slime.shine).toBe("Rainbow")
	end)
	it("shine rolls never shift the fountain's slime sequence", function()
		local function run(weather: string?, shineSeed: number): ({ string }, number)
			local world = inWeather(weather)
			world.shineRng = Rng.new(shineSeed)
			local out = {}
			for i = 1, 300 do
				local id = Spawner.spawnSlime(world, T0 + i * 5)
				local slime = world.wild[id].slime
				table.insert(out, `{slime.tier} {slime.species} {slime.size}`)
				world.wild[id] = nil
			end
			return out, world.rng.state
		end
		local plain, plainState = run(nil, 1)
		local shiny, shinyState = run("Starfall", 99)
		expect(shiny).toEqual(plain)
		expect(shinyState).toBe(plainState)
	end)
end)

describe("a shine on a slime", function()
	it("multiplies income and the fountain price by its mult; no shine is x1", function()
		for _, row in Config.SHINES do
			local plain = Fixtures.slime("a", 4, { species = "blaze" })
			local shiny = Fixtures.slime("b", 4, { species = "blaze", shine = row.id })
			expect(Genome.shineMultiplier(shiny)).toBe(row.mult)
			expect(Genome.baseIncome(shiny)).toBeCloseTo(Genome.baseIncome(plain) * row.mult, 1e-9)
			expect(Economy.wildPrice(shiny)).toBe(math.floor(Genome.baseIncome(shiny) * Config.WILD_PRICE_SECONDS[4]))
			expect(Economy.wildPrice(shiny) > Economy.wildPrice(plain)).toBe(true)
		end
		expect(Genome.shineMultiplier(Fixtures.slime("c", 4))).toBe(1)
		expect(Genome.shineMultiplier(Fixtures.slime("d", 4, { shine = "Mud" }))).toBe(1)
	end)
	it("prefixes the display name; the label name is the plain species name (the shine is a pill)", function()
		local slime = Fixtures.slime("a", 5, { name = "Globble", shine = "Diamond" })
		expect(Genome.displayName(slime)).toBe("Diamond Legendary Globble")
		expect(Genome.displayName(Fixtures.slime("b", 5, { name = "Globble" }))).toBe("Legendary Globble")
		expect((SlimeLabel.attributes(slime))).toBe("Globble")
		expect((SlimeLabel.attributes(Fixtures.slime("c", 5, { name = "Globble", shine = "Gold", brewed = 1 })))).toBe(
			"Brewed Globble"
		)
	end)
	it("every shine has a recoloured-kit suffix, a real material and a colour", function()
		local seen: { [string]: boolean } = {}
		for _, row in Config.SHINES do
			expect(type(row.kit) == "string" and row.kit ~= "").toBe(true)
			expect(seen[row.kit]).toBeNil()
			seen[row.kit] = true
			expect(`{row.id}: {SlimeLooks.isMaterial(row.material)}`).toBe(`{row.id}: true`) -- never Glass
			expect(row.reflectance >= 0 and row.reflectance <= 1).toBe(true)
			expect(#row.color).toBe(3)
		end
	end)
	it("sanitize keeps only a known shine id", function()
		local function clean(shine: any): string?
			local raw = table.clone(Fixtures.slime("a", 3)) :: any
			raw.shine = shine
			return (Genome.sanitize(raw) :: Genome.Slime).shine
		end
		for _, row in Config.SHINES do
			expect(clean(row.id)).toBe(row.id)
		end
		expect(clean("Mud")).toBeNil()
		expect(clean("gold")).toBeNil()
		expect(clean(5)).toBeNil()
		expect(clean(nil)).toBeNil()
	end)
	it("survives a save round trip, and a slime without one stays without", function()
		local data = Fixtures.data({
			Fixtures.slime("a", 6, { shine = "Rainbow" }),
			Fixtures.slime("b", 2),
		})
		local back = SaveData.deserialize(SaveData.serialize(data, T0))
		expect((PlayerData.findSlime(back, "a") :: Genome.Slime).shine).toBe("Rainbow")
		expect((PlayerData.findSlime(back, "b") :: Genome.Slime).shine).toBeNil()
	end)
	it("travels with the slime when it is stolen", function()
		local world = ServerFixtures.world()
		local owner = ServerFixtures.join(world, 1, { Fixtures.slime("s", 4, { shine = "Gold" }) })
		local thief = ServerFixtures.join(world, 2)
		ServerFixtures.unlock(owner)
		expect((Carry.grab(world, 2, "s", 2, T0))).toBe(true)
		expect((Carry.deposit(world, 2, T0 + 5))).toBe(true)
		expect((PlayerData.findSlime(thief.data, "s") :: Genome.Slime).shine).toBe("Gold")
	end)
end)
