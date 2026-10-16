--!strict
-- Boss Slime banner rules (src/ui/RareAnnounce.luau, CONTRACT §2 Extras).
local fs = require("@lune/fs")

local RareAnnounce = require("../../src/ui/RareAnnounce")
local TestRunner = require("../TestRunner")

local describe, it, expect = TestRunner.describe, TestRunner.it, TestRunner.expect

-- Exact server wording (src/server/Spawner.luau, Carry.luau).
local SPAWN = "A BOSS SLIME slid into the plaza: Glow Globble! Grab it first!"
local CAUGHT = "Ann caught the Boss Slime!"

describe("RareAnnounce.classify", function()
	it("recognises the server's boss spawn and catch messages", function()
		expect(RareAnnounce.classify(SPAWN)).toBe("spawn")
		expect(RareAnnounce.classify(CAUGHT)).toBe("caught")
	end)
	it("still matches the wording in the server source (drift guard)", function()
		local spawner = fs.readFile("src/server/Spawner.luau")
		local carry = fs.readFile("src/server/Carry.luau")
		expect(string.find(spawner, "A BOSS SLIME slid into the plaza: {", 1, true) ~= nil).toBe(true)
		expect(string.find(carry, "caught the Boss Slime!", 1, true) ~= nil).toBe(true)
		expect(string.find(fs.readFile("src/server/WorldView.luau"), '"BOSS "', 1, true) ~= nil).toBe(true)
	end)
	it("ignores other toasts, including the rain heads-up", function()
		expect(RareAnnounce.classify("Slime Rain in 1 minute! Get ready")).toBeNil()
		expect(RareAnnounce.classify("SLIME RAIN!")).toBeNil()
		expect(RareAnnounce.classify(nil)).toBeNil()
	end)
end)

describe("RareAnnounce names", function()
	it("reads the slime name from the Notify text and the prompt ObjectText", function()
		expect(RareAnnounce.nameFromNotify(SPAWN)).toBe("Glow Globble")
		expect(RareAnnounce.nameFromNotify("BOSS SLIME!")).toBeNil()
		expect(RareAnnounce.nameFromObjectText("BOSS Glow Globble")).toBe("Glow Globble")
		expect(RareAnnounce.nameFromObjectText("Glow Globble")).toBeNil()
		expect(RareAnnounce.nameFromObjectText("BOSS ")).toBeNil()
		expect(RareAnnounce.nameFromObjectText(42)).toBeNil()
	end)
end)

describe("RareAnnounce.banner", function()
	it("counts down a wild boss and hides it once expired", function()
		local boss = { name = "Glow Globble", expiresAt = 1090, carried = false }
		local b = RareAnnounce.banner(boss, nil, 1000) :: RareAnnounce.Banner
		expect(b.kind).toBe("boss")
		expect(b.text).toBe("👑 BOSS SLIME: Glow Globble! Grab it at the fountain - 1:30")
		expect(RareAnnounce.banner(boss, nil, 1090)).toBeNil()
	end)
	it("works without a name or timer (model seen after joining)", function()
		local b = RareAnnounce.banner({ carried = false }, nil, 0) :: RareAnnounce.Banner
		expect(b.text).toBe("👑 BOSS SLIME! Grab it at the fountain")
	end)
	it("says chase when it's being carried", function()
		local b = RareAnnounce.banner({ name = "Zed", carried = true }, nil, 0) :: RareAnnounce.Banner
		expect(b.text).toBe("👑 BOSS SLIME: Zed is being carried - chase & slap!")
	end)
	it("shows the catch for a few seconds, over any boss", function()
		local caught = { text = CAUGHT, untilTime = 1000 + RareAnnounce.CAUGHT_SECONDS }
		local b = RareAnnounce.banner({ carried = false }, caught, 1000) :: RareAnnounce.Banner
		expect(b.kind).toBe("caught")
		expect(b.text).toBe("👑 " .. CAUGHT)
		expect(RareAnnounce.banner(nil, caught, caught.untilTime)).toBeNil()
		expect(RareAnnounce.banner(nil, nil, 0)).toBeNil()
	end)
end)

describe("RareAnnounce Legendary+ drops (CONTRACT §8.6 / §8.7)", function()
	local TIERS = { "Common", "Uncommon", "Rare", "Epic", "Legendary", "Mythic" }
	it("classifies the Rare Notify by sound or wording", function()
		expect(RareAnnounce.classify("A LEGENDARY Glow Globble spilled from the fountain!", "Rare")).toBe("drop")
		expect(RareAnnounce.classify("A MYTHIC Zed spilled from the fountain!!", nil)).toBe("drop")
		expect(RareAnnounce.classify("Goal complete: Catch 10 slimes! +$500", "Goal")).toBeNil()
	end)
	it("reads the workspace RareSpawn attributes", function()
		local drop = RareAnnounce.dropFromAttributes(6, 1000) :: RareAnnounce.Drop
		expect(drop.tier).toBe(6)
		expect(drop.at).toBe(1000)
		expect(RareAnnounce.dropFromAttributes(6, nil)).toBeNil()
		expect((RareAnnounce.dropFromAttributes("x", 5) :: RareAnnounce.Drop).tier).toBeNil()
	end)
	it("shows the Notify text, else a generic line, for DROP_SECONDS", function()
		local generic = RareAnnounce.dropBanner({ tier = 5, at = 1000 }, 1001, TIERS) :: RareAnnounce.Banner
		expect(generic.kind).toBe("drop")
		expect(generic.text).toBe("✨ A LEGENDARY slime spilled from the fountain! Grab it!")
		local named = RareAnnounce.dropBanner({ tier = 6, at = 1000, text = "A MYTHIC Zed spilled!!" }, 1000, TIERS)
		expect((named :: RareAnnounce.Banner).text).toBe("✨ A MYTHIC Zed spilled!!")
		expect(RareAnnounce.dropBanner({ at = 1000 }, 1000, TIERS) ~= nil).toBe(true)
		expect(RareAnnounce.dropBanner({ tier = 5, at = 1000 }, 1000 + RareAnnounce.DROP_SECONDS, TIERS)).toBeNil()
		expect(RareAnnounce.dropBanner(nil, 0, TIERS)).toBeNil()
	end)
end)
