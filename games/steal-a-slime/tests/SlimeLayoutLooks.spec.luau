--!strict
-- #70 per-type looks reach SlimeLayout: every roster type's SlimeLooks
-- material and colour land on the Body part; unknown types fall back.
local Fixtures = require("./Fixtures")
local SlimeLayout = require("../src/visuals/shared/SlimeLayout")
local SlimeLooks = require("../src/shared/SlimeLooks")
local SlimeRoster = require("../src/shared/SlimeRoster")
local TestRunner = require("./TestRunner")

local describe, it, expect = TestRunner.describe, TestRunner.it, TestRunner.expect

local function body(slime: any): SlimeLayout.PartSpec
	return SlimeLayout.build(slime)[1]
end

describe("SlimeLayout per-type looks (#70)", function()
	it("gives every roster type its SlimeLooks material and colour on the Body", function()
		for _, entry in SlimeRoster.ROSTER do
			local look = SlimeLooks.get(entry.id) :: SlimeLooks.Look
			local slime =
				Fixtures.slime("s", 1, { species = entry.id, color = { look.color[1], look.color[2], look.color[3] } })
			local b = body(slime)
			expect(b.name).toBe("Body")
			expect(b.material).toBe(look.material)
			expect(b.color).toEqual({ look.color[1], look.color[2], look.color[3] })
		end
	end)

	it("falls back to SmoothPlastic for unknown or missing types", function()
		expect(body(Fixtures.slime("a", 1, { species = "not_a_type" })).material).toBe("SmoothPlastic")
		expect(body(Fixtures.slime("b", 1)).material).toBe("SmoothPlastic")
	end)

	it("lets a mutation material win over the type material", function()
		local b = body(Fixtures.slime("c", 1, { species = "cosmo", mutation = "Gold" }))
		expect(b.material).toBe("Foil")
		local g = body(Fixtures.slime("d", 1, { species = "cosmo", mutation = "Glow" }))
		expect(g.material).toBe("Neon")
	end)
end)
