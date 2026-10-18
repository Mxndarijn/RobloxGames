--!strict
-- Rain Magnet upgrade (FEATURES.RainMagnet, CONTRACT.md §23): the upgrade entry and its flag, the weather
-- mutation target, the roll, the deposit hook (server-authoritative) and save safety. Flag off by default.
local Actions = require("../src/server/Actions")
local Carry = require("../src/server/Carry")
local Config = require("../src/shared/Config")
local Fixtures = require("./Fixtures")
local Genome = require("../src/shared/Genome")
local Perks = require("../src/shared/Perks")
local PlayerData = require("../src/shared/PlayerData")
local RainMagnet = require("../src/shared/RainMagnet")
local Rng = require("../src/shared/Rng")
local SaveData = require("../src/shared/SaveData")
local ServerFixtures = require("./ServerFixtures")
local ShopCatalog = require("../src/ui/ShopCatalog")
local Spawner = require("../src/server/Spawner")
local TestRunner = require("./TestRunner")
local Upgrades = require("../src/shared/Upgrades")
local Weather = require("../src/shared/Weather")

local describe, it, expect = TestRunner.describe, TestRunner.it, TestRunner.expect
local T0 = ServerFixtures.T0

-- Back to Clear with Genome re-bound: Weather.reset drops every listener without a Changed, so Genome's
-- cached weather bonus would otherwise outlive the test.
local function clearWeather()
	Weather.reset()
	Genome.bindWeather()
end

local function def(): Config.Upgrade
	return Perks.upgradeDef("RainMagnet") :: Config.Upgrade
end

describe("RainMagnet: the upgrade entry", function()
	it("is behind FEATURES.RainMagnet, default off, and the def is flag-tagged", function()
		expect(Config.FEATURES.RainMagnet).toBe(false)
		expect(def().flag).toBe("RainMagnet")
		expect(def().requires).toBe(6) -- Goo Tycoon
		expect(def().maxLevel * def().step <= 0.25 + 1e-9).toBe(true)
	end)
	it("is not listed, not buyable and has no effect while the flag is off", function()
		local d = Fixtures.data(nil, 1e12)
		d.rebirths = 10
		for _, v in Upgrades.view(d) do
			expect(v.id ~= "RainMagnet").toBe(true)
		end
		expect(select(2, Upgrades.buy(d, "RainMagnet"))).toBe("unknown upgrade")
		d.upgrades.RainMagnet = 3 -- a level from a save
		expect(Perks.rainMagnetChance(d)).toBe(0)
		expect(math.abs(Perks.rainMagnetChance(d, true) - 0.15) < 1e-9).toBe(true)
	end)
	it("old upgrades are listed exactly as before", function()
		local d = Fixtures.data()
		local ids = {}
		for _, v in Upgrades.view(d) do
			table.insert(ids, v.id)
		end
		expect(ids).toEqual({ "Income", "CarrySpeed", "OfflineCap", "Luck" })
	end)
	it("a saved level survives a load whether or not the flag is on", function()
		local d = Fixtures.data()
		d.upgrades.RainMagnet = 4
		local back = SaveData.deserialize(SaveData.serialize(d))
		expect(back.upgrades.RainMagnet).toBe(4)
		d.upgrades.RainMagnet = 99
		expect(SaveData.deserialize(SaveData.serialize(d)).upgrades.RainMagnet).toBe(def().maxLevel)
	end)
	it("has a shop badge and a one-line text", function()
		expect(ShopCatalog.UPGRADE_ICONS.RainMagnet ~= nil).toBe(true)
		expect(ShopCatalog.upgradeText("RainMagnet", def().text)).toBe("+5% weather mutation chance")
	end)
end)

describe("RainMagnet: target and roll", function()
	it("targets the weather's mutation, Wet in the Slime Rain event, nothing in Clear", function()
		expect(RainMagnet.target("Rain", false)).toBe("Wet")
		expect(RainMagnet.target("Snow", false)).toBe("Frozen")
		expect(RainMagnet.target("Starfall", false)).toBe("Galaxy")
		expect(RainMagnet.target("Clear", false)).toBeNil()
		expect(RainMagnet.target("Clear", true)).toBe("Wet")
		expect(RainMagnet.target("Snow", true)).toBe("Frozen") -- a weather mutation wins
		expect(RainMagnet.target("nope", false)).toBeNil()
	end)
	it("draws nothing without a target or a chance", function()
		local rng = Rng.new(1)
		local s = Fixtures.slime("a", 2)
		local before = rng:float()
		local rng2 = Rng.new(1)
		expect(RainMagnet.attract(s, nil, 1, rng2)).toBeNil()
		expect(RainMagnet.attract(s, "Wet", 0, rng2)).toBeNil()
		expect(rng2:float()).toBe(before)
	end)
	it("hits about `chance` of the time and adds the mutation", function()
		local rng = Rng.new(21)
		local hits, n = 0, 4000
		for i = 1, n do
			local s = Fixtures.slime(`s{i}`, 2)
			if RainMagnet.attract(s, "Wet", 0.15, rng) == "Wet" then
				hits += 1
				expect(Genome.mutationList(s)).toEqual({ "Wet" })
				expect(s.mutation).toBe("Wet")
			end
		end
		expect(math.abs(hits / n - 0.15) < 0.03).toBe(true)
	end)
	it("keeps what the slime has, fuses combos and never doubles up", function()
		local rng = Rng.new(2)
		local frozen = Fixtures.slime("a", 2, { mutation = "Frozen", mutations = { "Frozen" } })
		expect(RainMagnet.attract(frozen, "Wet", 1, rng)).toBe("Wet")
		expect(Genome.mutationList(frozen)).toEqual({ "Sleet" }) -- Wet + Frozen fuse
		local wet = Fixtures.slime("b", 2, { mutation = "Wet", mutations = { "Wet" } })
		expect(RainMagnet.attract(wet, "Wet", 1, rng)).toBeNil()
		local glow = Fixtures.slime("c", 2, { mutation = "Glow", mutations = { "Glow" } })
		expect(RainMagnet.attract(glow, "Wet", 1, rng)).toBe("Wet")
		expect(#Genome.mutationList(glow)).toBe(2)
	end)
	it("is deterministic for a seed", function()
		local function run(): string
			local s = Fixtures.slime("a", 3)
			RainMagnet.attract(s, "Frozen", 0.5, Rng.new(77))
			return s.mutation
		end
		expect(run()).toBe(run())
	end)
end)

describe("RainMagnet: deposit hook", function()
	local function setup(level: number): (any, any, Genome.Slime)
		local world = ServerFixtures.world()
		local session = ServerFixtures.join(world, 1, nil, 1e9)
		session.data.rebirths = 6
		session.data.upgrades.RainMagnet = level
		return world, session, Fixtures.slime("w", 2)
	end

	it("with the magnet on, level 5 in Rain: about a quarter of caught slimes come home Wet", function()
		Weather.set("Rain")
		local hits, n = 0, 2000
		local world, session = setup(5)
		for i = 1, n do
			local slime = Fixtures.slime(`w{i}`, 2)
			if Carry.applyMagnet(world, session, slime, true) then
				hits += 1
				expect(Genome.mutationList(slime)).toEqual({ "Wet" })
			end
		end
		expect(math.abs(hits / n - 0.25) < 0.04).toBe(true)
		clearWeather()
	end)
	it("tells the player what it pulled in", function()
		Weather.set("Snow")
		local world, session, slime = setup(5)
		session.data.upgrades.RainMagnet = 5
		local pulled = false
		for _ = 1, 50 do
			pulled = Carry.applyMagnet(world, session, Fixtures.slime("x", 2), true) or pulled
		end
		expect(pulled).toBe(true)
		expect(string.find(table.concat(ServerFixtures.notifications(world, 1), "\n"), "Frozen", 1, true) ~= nil).toBe(
			true
		)
		expect(slime.mutation).toBe("None")
		clearWeather()
	end)
	it("does nothing in Clear, at level 0, with the flag off, or for a full-stack slime", function()
		local world, session, slime = setup(5)
		clearWeather()
		expect(Carry.applyMagnet(world, session, slime, true)).toBe(false) -- Clear, no Slime Rain
		Weather.set("Rain")
		expect(Carry.applyMagnet(world, session, slime)).toBe(false) -- flag off
		session.data.upgrades.RainMagnet = 0
		expect(Carry.applyMagnet(world, session, slime, true)).toBe(false)
		session.data.upgrades.RainMagnet = 5
		world.raining = true
		clearWeather()
		local pulledInSlimeRain = false
		for _ = 1, 60 do
			pulledInSlimeRain = Carry.applyMagnet(world, session, Fixtures.slime("y", 1), true) or pulledInSlimeRain
		end
		expect(pulledInSlimeRain).toBe(true) -- Slime Rain event counts as Rain
		clearWeather()
	end)
	it("a full deposit with the flag off leaves the slime and the rng alone", function()
		Weather.set("Rain")
		local world = ServerFixtures.world()
		local s = ServerFixtures.join(world, 1, nil, 1e9)
		s.data.upgrades.RainMagnet = 5
		local id = Spawner.spawnOne(world, T0)
		world.wild[id].price = 0
		world.wild[id].slime.mutation = "None"
		world.wild[id].slime.mutations = {}
		expect((Carry.grab(world, 1, id, 5, T0 + 1))).toBe(true)
		expect((Carry.deposit(world, 1, T0 + 2))).toBe(true)
		expect(s.data.slimes[1].mutation).toBe("None")
		clearWeather()
	end)
	it("stolen slimes are untouched and draw nothing", function()
		Weather.set("Rain")
		local world = ServerFixtures.world()
		local victim = ServerFixtures.join(world, 1, { Fixtures.slime("gem", 2) }, 0)
		local thief = ServerFixtures.join(world, 2, nil, 0)
		ServerFixtures.unlock(victim)
		thief.data.upgrades.RainMagnet = 5
		local draws = 0
		local real = world.rng
		world.rng = {
			float = function(_self: any)
				draws += 1
				return real:float()
			end,
		} :: any
		expect((Carry.grab(world, 2, "gem", 1, T0))).toBe(true)
		expect((Carry.deposit(world, 2))).toBe(true)
		local slime = PlayerData.findSlime(thief.data, "gem") :: Genome.Slime
		expect(slime.mutation).toBe("None")
		expect(draws).toBe(0)
		clearWeather()
	end)
	it("deposit draws the same rng with and without weather while the flag is off", function()
		local function run(weather: string): number
			Weather.set(weather)
			local world = ServerFixtures.world()
			local s = ServerFixtures.join(world, 1, nil, 1e9)
			s.data.upgrades.RainMagnet = 5
			local id = Spawner.spawnOne(world, T0)
			world.wild[id].price = 0
			Carry.grab(world, 1, id, 5, T0 + 1)
			local draws = 0
			local real = world.rng
			world.rng = {
				float = function(_self: any)
					draws += 1
					return real:float()
				end,
			} :: any
			expect((Carry.deposit(world, 1, T0 + 2))).toBe(true)
			clearWeather()
			return draws
		end
		expect(run("Rain")).toBe(run("Clear"))
	end)
	it("applyMagnet draws exactly once with a level and a target, never otherwise", function()
		local world, session, slime = setup(3)
		local draws = 0
		local real = world.rng
		world.rng = {
			float = function(_self: any)
				draws += 1
				return real:float()
			end,
		} :: any
		Weather.set("Starfall")
		Carry.applyMagnet(world, session, slime, true)
		expect(draws).toBe(1)
		Carry.applyMagnet(world, session, Fixtures.slime("n", 1), false) -- flag off: chance 0
		expect(draws).toBe(1)
		clearWeather()
		Carry.applyMagnet(world, session, Fixtures.slime("c", 1), true) -- Clear: no target
		expect(draws).toBe(1)
		session.data.upgrades.RainMagnet = 0
		Weather.set("Rain")
		Carry.applyMagnet(world, session, Fixtures.slime("l", 1), true) -- level 0
		expect(draws).toBe(1)
		clearWeather()
	end)
	it("the Slime Rain event (world.raining) makes a Clear-weather catch Wet", function()
		local world, session = setup(5)
		world.raining = true
		clearWeather()
		local wet = 0
		for i = 1, 200 do
			local slime = Fixtures.slime(`r{i}`, 1)
			if Carry.applyMagnet(world, session, slime, true) then
				expect(slime.mutation).toBe("Wet")
				wet += 1
			end
		end
		expect(wet > 0).toBe(true)
	end)
	it("a full mutation stack is left alone, a fusing combo still fits", function()
		Weather.set("Rain")
		local world, session = setup(5)
		session.data.upgrades.RainMagnet = 5
		local full = Fixtures.slime("f", 2)
		Genome.setMutations(full, { "Glow", "Rainbow", "Golden" })
		local before = table.clone(Genome.mutationList(full))
		expect(#before).toBe(Config.MAX_MUTATIONS)
		for _ = 1, 40 do
			expect(Carry.applyMagnet(world, session, full, true)).toBe(false)
		end
		expect(Genome.mutationList(full)).toEqual(before)
		local fuse = Fixtures.slime("g", 2)
		Genome.setMutations(fuse, { "Glow", "Rainbow", "Frozen" })
		local fused = false
		for _ = 1, 80 do
			fused = Carry.applyMagnet(world, session, fuse, true) or fused
		end
		expect(fused).toBe(true)
		expect(#Genome.mutationList(fuse) <= Config.MAX_MUTATIONS).toBe(true)
		clearWeather()
	end)
	it("buying is refused with the flag off even for a rich rank-6 player", function()
		local world = ServerFixtures.world()
		local s = ServerFixtures.join(world, 1, nil, 1e12)
		s.data.rebirths = 6
		s.limiter = {}
		local r = Actions.handle(world, 1, "BuyUpgrade", { "RainMagnet" }, T0 + 5, {
			distanceBetween = function()
				return 2
			end,
			positionOf = function()
				return nil
			end,
		})
		expect(r.ok).toBe(false)
		expect(s.data.upgrades.RainMagnet).toBeNil()
		expect(PlayerData.findSlime(s.data, "x")).toBeNil()
	end)
end)

describe("RainMagnet: prop", function()
	local MagnetDecor = require("../src/visuals/shared/MagnetDecor")
	local MeshAssets = require("../src/shared/MeshAssets")
	local RanchProps = require("../src/visuals/shared/RanchProps")
	local Constants = require("../src/shared/Constants")
	local WorldLayout = require("../src/visuals/shared/WorldLayout")

	it("stands on the vat's bottom, beside it, and shows only for a positive level", function()
		local pose = MagnetDecor.pose()
		expect(math.abs(pose.offset[2] - pose.size[2] / 2 + MagnetDecor.DISC_HEIGHT / 2) < 1e-9).toBe(true)
		expect(pose.offset[1]).toBe(MagnetDecor.OFFSET_X)
		expect(MagnetDecor.shown(0)).toBe(false)
		expect(MagnetDecor.shown(nil)).toBe(false)
		expect(MagnetDecor.shown("3")).toBe(false)
		expect(MagnetDecor.shown(2)).toBe(true)
		expect(Constants.PLOT_RAIN_MAGNET_ATTRIBUTE).toBe("RainMagnet")
	end)
	it("is an uploaded run-time-only kit mesh: 0 WorldLayout slots", function()
		expect(MeshAssets.meshId("rain_magnet") ~= nil).toBe(true)
		expect(RanchProps.INTENTIONALLY_UNPLACED.rain_magnet ~= nil).toBe(true)
		local function scan(node: any)
			local a = node.attributes or {}
			expect(a.MeshAsset ~= "rain_magnet" and a.BorderMesh ~= "rain_magnet").toBe(true)
			for _, c in node.children or {} do
				scan(c)
			end
		end
		for _, root in WorldLayout.build() do
			scan(root)
		end
	end)
	it("with no rain_magnet entry the pose and the upgrade still work (no mesh, no error)", function()
		expect(MeshAssets.get("rain_magnet_missing")).toBeNil()
		expect(MeshAssets.meshId("rain_magnet_missing")).toBeNil()
		expect(MeshAssets.entries.rain_magnet.assetId).toBe(87228491807524)
		expect(MeshAssets.meshId("rain_magnet")).toBe("rbxassetid://102515085429965")
		local saved = MeshAssets.entries.rain_magnet
		MeshAssets.entries.rain_magnet = nil :: any
		local ok, pose = pcall(MagnetDecor.pose)
		MeshAssets.entries.rain_magnet = saved
		expect(ok).toBe(true)
		expect(#(pose :: any).size).toBe(3)
		local world = ServerFixtures.world()
		local session = ServerFixtures.join(world, 1, nil, 1e9)
		session.data.upgrades.RainMagnet = 5
		local slime = Fixtures.slime("m", 1)
		Weather.set("Rain")
		expect(Carry.applyMagnet(world, session, slime, false)).toBe(false) -- gameplay independent of the mesh
		clearWeather()
	end)
end)
