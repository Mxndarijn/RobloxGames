--!strict
-- The Grab step's guide leads to the closest slime the player can afford, else the cheapest with "Need $X".
local TestRunner = require("./TestRunner")
local TutorialTargets = require("../src/visuals/shared/TutorialTargets")

local describe, it, expect = TestRunner.describe, TestRunner.it, TestRunner.expect

local function slime(key: string, x: number, price: number): TutorialTargets.Wild
	return { key = key, x = x, z = 0, price = price, value = key }
end

local HERE = { x = 0, z = 0 }

describe("TutorialTargets.grab", function()
	it("leads to the closest slime the player can afford, with no price of its own (the slime's tag has it)", function()
		local picked, label = TutorialTargets.grab({ slime("cheapFar", 40, 10), slime("pricyNear", 5, 900) }, 50, HERE)
		expect(picked and picked.key).toBe("cheapFar")
		expect(label).toBeNil()
	end)

	it("always counts free slimes, even with no cash", function()
		local picked, label = TutorialTargets.grab({ slime("free", 30, 0), slime("paid", 5, 10) }, 0, HERE)
		expect(picked and picked.key).toBe("free")
		expect(label).toBe("Grab")
	end)

	it("counts a slime that costs exactly the player's cash", function()
		local picked = TutorialTargets.grab({ slime("exact", 10, 25) }, 25, HERE)
		expect(picked and picked.key).toBe("exact")
	end)

	it("falls back to the cheapest slime with a Need label when nothing is affordable", function()
		local picked, label = TutorialTargets.grab({ slime("a", 5, 900), slime("b", 50, 300) }, 10, HERE)
		expect(picked and picked.key).toBe("b")
		expect(label).toBe("Need $300")
	end)

	it("keeps the current slime while another is only slightly closer", function()
		local wild = { slime("current", 10, 0), slime("other", 9, 0) }
		local picked = TutorialTargets.grab(wild, 0, HERE, "current")
		expect(picked and picked.key).toBe("current")
	end)

	it("returns nothing when there are no wild slimes", function()
		local picked, label = TutorialTargets.grab({}, 100, HERE)
		expect(picked).toBeNil()
		expect(label).toBeNil()
	end)
end)
