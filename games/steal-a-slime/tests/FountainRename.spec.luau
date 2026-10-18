--!strict
-- Volcano -> slime fountain rename (docs/archive/RANCH_RENAME.md): save ids stay, players
-- see the new names. Old saves with the "Lava" mutation load identically and
-- display as "Syrup"; no player-facing string says volcano / lava / erupt.
local fs = require("@lune/fs")
local serde = require("@lune/serde")

local BossEvent = require("../src/server/BossEvent")
local Config = require("../src/shared/Config")
local Fountain = require("../src/shared/Fountain")
local Genome = require("../src/shared/Genome")
local PlayerData = require("../src/shared/PlayerData")
local SaveData = require("../src/shared/SaveData")
local ServerFixtures = require("./ServerFixtures")
local SlimeDex = require("../src/ui/SlimeDex")
local SlimeRoster = require("../src/shared/SlimeRoster")
local Spawner = require("../src/server/Spawner")
local TestRunner = require("./TestRunner")
local Volcano = require("../src/shared/Volcano")

local describe, it, expect = TestRunner.describe, TestRunner.it, TestRunner.expect
local T0 = ServerFixtures.T0

local BANNED = { "volcan", "lava", "erupt" }

-- Internal names that are not shown to players: the legacy Map.Volcano model,
-- the "Lava" mutation save id and the client FX preset / decor part names.
local INTERNAL = {
	["Volcano"] = true,
	["Lava"] = true,
	["Map.Volcano.Crater"] = true,
	["Eruption"] = true,
}

local function banned(text: string): string?
	local lower = string.lower(text)
	for _, word in BANNED do
		if string.find(lower, word, 1, true) then
			return word
		end
	end
	return nil
end

-- A save written before the rename (v3 shape), as it sits in the DataStore.
local OLD_SAVE = [[{
	"version": 3,
	"cash": 5000,
	"rebirths": 1,
	"padsUnlocked": 4,
	"lastOnline": 1700000000,
	"favoriteId": "old-lava",
	"tutorialStep": 0,
	"slimes": [
		{ "id": "old-lava", "name": "Blorp", "tier": 4, "color": [255, 110, 40], "size": 1,
		  "pattern": "Spots", "eyes": "Happy", "mouth": "Smile", "mutation": "Lava", "pad": 1 },
		{ "id": "old-glow", "name": "Zed", "tier": 2, "color": [200, 255, 200], "size": 1.2,
		  "pattern": "Plain", "eyes": "Round", "mouth": "Smile", "mutation": "Glow", "pad": 2 }
	],
	"dex": ["4:Lava:Spots:Happy", "2:Glow:Plain:Round", "1:None:Plain:Round"]
}]]

describe("Fountain module", function()
	it("Volcano is a thin alias for Fountain (same behaviour)", function()
		expect(Volcano).toBe(Fountain)
		expect(Fountain.MIN_RADIUS).toBeCloseTo(48.4)
		expect(Fountain.MAX_RADIUS).toBe(62)
	end)
end)

describe("Mutation display names", function()
	it("keeps every mutation save id and shows Lava as Syrup", function()
		local ids, shown = {}, {}
		for _, m in Config.MUTATIONS do
			table.insert(ids, m.name)
			shown[m.name] = m.displayName
		end
		expect(ids).toEqual({ "Glow", "Lava", "Galaxy", "Rainbow", "Gold", "Crystal", "Eclipse" })
		expect(shown).toEqual({
			Glow = "Glow",
			Lava = "Syrup",
			Galaxy = "Galaxy",
			Rainbow = "Rainbow",
			Gold = "Gold",
			Crystal = "Crystal",
			Eclipse = "Eclipse",
		})
		for _, m in Config.MUTATIONS do
			expect(banned(m.displayName)).toBeNil()
			expect(SlimeRoster.MUTATION_DISPLAY[m.name]).toBe(m.displayName)
		end
	end)
	it("maps ids to display names and passes None / unknown ids through", function()
		expect(Genome.mutationDisplayName("Lava")).toBe("Syrup")
		expect(Genome.mutationDisplayName("Glow")).toBe("Glow")
		expect(Genome.mutationDisplayName("None")).toBe("None")
		expect(Genome.mutationDisplayName("Nope")).toBe("Nope")
		expect(Genome.mutationMultiplier("Lava")).toBe(2)
		expect(Genome.mutationDisplay).toBe(Genome.mutationDisplayName) -- v28 alias
	end)
end)

describe("Old saves after the rename", function()
	it("load the Lava mutation, dex keys and favourite unchanged", function()
		local data = SaveData.deserialize(serde.decode("json", OLD_SAVE))
		local lava = PlayerData.findSlime(data, "old-lava")
		assert(lava, "old Lava slime loaded")
		expect(lava.mutation).toBe("Lava")
		expect(lava.pad).toBe(1)
		expect(Genome.baseIncome(lava)).toBe(Config.RARITIES[4].income * 2)
		expect(data.favoriteId).toBe("old-lava")
		expect(data.dex["4:Lava:Spots:Happy"]).toBe(true)
		expect(data.dex["2:Glow:Plain:Round"]).toBe(true)
		expect(data.dex["1:None:Plain:Round"]).toBe(true)
		expect(PlayerData.dexCount(data)).toBe(3)
	end)
	it("display the new names", function()
		local data = SaveData.deserialize(serde.decode("json", OLD_SAVE))
		local lava = PlayerData.findSlime(data, "old-lava")
		assert(lava, "old Lava slime loaded")
		expect(Genome.displayName(lava)).toBe("Syrup Epic Blorp")
		local dex = {}
		for key in data.dex do
			table.insert(dex, key)
		end
		local titles = {}
		for _, row in SlimeDex.rows(dex, nil, Config) do
			titles[row.key] = row
			expect(banned(row.title)).toBeNil()
		end
		expect(titles["4:Lava:Spots:Happy"].title).toBe("Epic · Syrup · Spots · Happy")
		expect(titles["4:Lava:Spots:Happy"].color).toBe(SlimeDex.MUTATION_COLORS.Lava)
	end)
	it("save back with the old ids (no Syrup in the stored data)", function()
		local data = SaveData.deserialize(serde.decode("json", OLD_SAVE))
		local json = serde.encode("json", SaveData.serialize(data, 1700000000))
		expect(string.find(json, '"Lava"', 1, true) ~= nil).toBe(true)
		expect(string.find(json, "4:Lava:Spots:Happy", 1, true) ~= nil).toBe(true)
		expect(string.find(json, "Syrup", 1, true)).toBeNil()
		local again = SaveData.deserialize(serde.decode("json", json))
		expect(again.slimes).toEqual(data.slimes)
		expect(again.dex).toEqual(data.dex)
		expect(again.favoriteId).toBe(data.favoriteId)
	end)
	it("still migrate v1 saves", function()
		local data = SaveData.deserialize({ Cash = 42, Slimes = { { Id = "v1", Rarity = "Rare", Size = 1 } } })
		expect(data.cash).toBe(42)
		expect(data.slimes[1].id).toBe("v1")
		expect(data.slimes[1].tier).toBe(3)
	end)
end)

describe("Player-facing copy", function()
	it("server announcements say fountain / plaza, never volcano / lava / erupt", function()
		local world = ServerFixtures.world()
		ServerFixtures.join(world, 1)
		world.pity.sinceLegendary = Config.PITY_LEGENDARY - 1 -- the next drop is announced
		local bossOver = Config.BOSS.FIRST_AT + Config.BOSS.FIGHT_SECONDS
		local stop = T0 + math.max(bossOver, Config.RAIN_FIRST_AT + Config.RAIN_DURATION) + 5
		for t = T0, stop do
			Spawner.step(world, t)
			BossEvent.step(world, t)
		end
		local texts = {}
		for _, event in world.outbox do
			if event.type == "Notify" and event.text then
				table.insert(texts, event.text)
				expect(banned(event.text)).toBeNil()
			end
		end
		local all = table.concat(texts, "\n")
		expect(string.find(all, "spilled from the fountain", 1, true) ~= nil).toBe(true)
		expect(string.find(all, "is in the plaza", 1, true) ~= nil).toBe(true) -- the boss arrives
		expect(string.find(all, "Head to the fountain", 1, true) ~= nil).toBe(true)
	end)
	it("rare drop text uses the mutation display name", function()
		local slime = Genome.copy(Genome.sanitize({ id = "r", tier = 5, name = "Globble", mutation = "Lava" }) :: any)
		expect(Spawner.rareText(slime)).toBe("A LEGENDARY Syrup Globble spilled from the fountain!")
	end)
	it("no string literal in src says volcano / lava / erupt (internal names excepted)", function()
		local hits = {}
		local function scan(path: string)
			local inBlock = false
			for line in string.gmatch(fs.readFile(path) .. "\n", "(.-)\n") do
				-- Skip --[[ ]] blocks and -- comments.
				if inBlock or string.match(line, "^%s*%-%-%[=*%[") then
					inBlock = string.find(line, "]]", 1, true) == nil
				elseif not string.match(line, "^%s*%-%-") then
					for _, quote in { '"', "'", "`" } do
						for literal in string.gmatch(line, quote .. "(.-)" .. quote) do
							if not INTERNAL[literal] and banned(literal) then
								table.insert(hits, `{path}: {literal}`)
							end
						end
					end
				end
			end
		end
		local function walk(dir: string)
			for _, name in fs.readDir(dir) do
				local path = `{dir}/{name}`
				if fs.isDir(path) then
					walk(path)
				elseif string.match(name, "%.luau$") then
					scan(path)
				end
			end
		end
		for _, root in { "src/ui", "src/server", "src/shared", "src/visuals" } do
			walk(root)
		end
		expect(hits).toEqual({})
	end)
end)
