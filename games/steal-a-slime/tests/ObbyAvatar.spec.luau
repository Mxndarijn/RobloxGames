--!strict
-- The obby's standard avatar (src/server/ObbyAvatar.luau, contract/obby.md §3): which scales a run sets, the original
-- kept once, a respawn normalised again, the restore once at the end, and nothing for R6 or a player who left.
local Config = require("../src/shared/Config")
local ObbyAvatar = require("../src/server/ObbyAvatar")
local TestRunner = require("./TestRunner")

local describe, it, expect = TestRunner.describe, TestRunner.it, TestRunner.expect

local STANDARD = Config.OBBY.AVATAR_SCALES

-- A tall, wide avatar's scale values.
local function big(): ObbyAvatar.Scales
	return {
		BodyHeightScale = 1.3,
		BodyWidthScale = 1.2,
		BodyDepthScale = 1.1,
		HeadScale = 1.4,
		BodyTypeScale = 0.6,
		BodyProportionScale = 0.5,
	}
end

-- Applies `writes` to `values` the way the adapter does (only names that are there).
local function apply(values: ObbyAvatar.Scales, writes: ObbyAvatar.Scales?)
	for name, value in writes or {} do
		if values[name] ~= nil then
			values[name] = value
		end
	end
end

describe("ObbyAvatar", function()
	it("sets the standard scales from Config on a run", function()
		expect(STANDARD).toEqual({
			BodyHeightScale = 1,
			BodyWidthScale = 1,
			BodyDepthScale = 1,
			HeadScale = 1,
			BodyTypeScale = 0,
			BodyProportionScale = 0,
		})
		local state = ObbyAvatar.new()
		expect(ObbyAvatar.decide(state, 1, true, "char", big())).toEqual(STANDARD)
	end)

	it("writes nothing for a standard avatar, on the run or after it", function()
		local state = ObbyAvatar.new()
		local values = table.clone(STANDARD)
		expect(ObbyAvatar.decide(state, 1, true, "char", values)).toBeNil()
		expect(ObbyAvatar.decide(state, 1, false, "char", values)).toBeNil()
	end)

	it("writes only the fields that are off, and only once", function()
		local state = ObbyAvatar.new()
		local values = table.clone(STANDARD)
		values.BodyHeightScale = 1.25
		expect(ObbyAvatar.decide(state, 1, true, "char", values)).toEqual({ BodyHeightScale = 1 })
		apply(values, { BodyHeightScale = 1 })
		for _ = 1, 5 do
			expect(ObbyAvatar.decide(state, 1, true, "char", values)).toBeNil()
		end
	end)

	it("puts the player's own scales back once when the run ends", function()
		local state = ObbyAvatar.new()
		local values = big()
		apply(values, ObbyAvatar.decide(state, 1, true, "char", values))
		expect(values).toEqual(STANDARD)
		expect(ObbyAvatar.decide(state, 1, true, "char", values)).toBeNil()
		expect(ObbyAvatar.decide(state, 1, false, "char", values)).toEqual(big())
		apply(values, big())
		expect(ObbyAvatar.decide(state, 1, false, "char", values)).toBeNil()
	end)

	it("never keeps a normalised value as the original", function()
		local state = ObbyAvatar.new()
		local values = big()
		apply(values, ObbyAvatar.decide(state, 1, true, "char", values))
		-- Ticks of the run, all already standard: the original stays the player's own.
		ObbyAvatar.decide(state, 1, true, "char", values)
		ObbyAvatar.decide(state, 1, true, "char", values)
		expect(ObbyAvatar.decide(state, 1, false, "char", values)).toEqual(big())
	end)

	it("takes a value the engine sets mid-run (a late appearance load) as the new original", function()
		local state = ObbyAvatar.new()
		local values = big()
		apply(values, ObbyAvatar.decide(state, 1, true, "char", values))
		values.HeadScale = 1.1
		expect(ObbyAvatar.decide(state, 1, true, "char", values)).toEqual({ HeadScale = 1 })
		apply(values, { HeadScale = 1 })
		local back = big()
		back.HeadScale = 1.1
		expect(ObbyAvatar.decide(state, 1, false, "char", values)).toEqual(back)
	end)

	it("normalises a character that respawns mid-run, and leaves the new one alone after", function()
		local state = ObbyAvatar.new()
		local first = big()
		apply(first, ObbyAvatar.decide(state, 1, true, "first", first))
		local second = big() -- the new character loads with the player's own scales
		expect(ObbyAvatar.decide(state, 1, true, "second", second)).toEqual(STANDARD)
		apply(second, STANDARD)
		expect(ObbyAvatar.decide(state, 1, false, "second", second)).toEqual(big())
	end)

	it("restores nothing when the run ends on a different character than the one it normalised", function()
		local state = ObbyAvatar.new()
		local values = big()
		apply(values, ObbyAvatar.decide(state, 1, true, "first", values))
		expect(ObbyAvatar.decide(state, 1, false, "second", big())).toBeNil()
		expect(ObbyAvatar.decide(state, 1, false, "second", big())).toBeNil()
	end)

	it("skips a character it can't scale (R6) and one with no character", function()
		local state = ObbyAvatar.new()
		expect(ObbyAvatar.decide(state, 1, true, "r6", nil)).toBeNil()
		expect(ObbyAvatar.decide(state, 1, false, "r6", nil)).toBeNil()
		expect(ObbyAvatar.decide(state, 2, true, nil, nil)).toBeNil()
		expect(state[1]).toBeNil()
		expect(state[2]).toBeNil()
	end)

	it("writes only the scale values the character has", function()
		local state = ObbyAvatar.new()
		local values = { BodyHeightScale = 1.3 }
		expect(ObbyAvatar.decide(state, 1, true, "char", values)).toEqual({ BodyHeightScale = 1 })
	end)

	it("forgets a player who left", function()
		local state = ObbyAvatar.new()
		local values = big()
		apply(values, ObbyAvatar.decide(state, 1, true, "char", values))
		ObbyAvatar.forget(state, 1)
		expect(state[1]).toBeNil()
		expect(ObbyAvatar.decide(state, 1, false, "char", values)).toBeNil()
	end)

	it("keeps players apart", function()
		local state = ObbyAvatar.new()
		local a, b = big(), big()
		apply(a, ObbyAvatar.decide(state, 1, true, "a", a))
		apply(b, ObbyAvatar.decide(state, 2, true, "b", b))
		expect(ObbyAvatar.decide(state, 1, false, "a", a)).toEqual(big())
		expect(ObbyAvatar.decide(state, 2, true, "b", b)).toBeNil()
	end)
end)
