--!strict
local KitRequest = require("../src/shared/KitRequest")
local SlimeLooks = require("../src/shared/SlimeLooks")
local TestRunner = require("./TestRunner")

local describe, it, expect = TestRunner.describe, TestRunner.it, TestRunner.expect

-- Species ids of the first `n` kits ("slime_<id>").
local function species(n: number): { string }
	local out = {}
	for i = 1, n do
		table.insert(out, string.sub(SlimeLooks.KITS[i], #"slime_" + 1))
	end
	return out
end

describe("KitRequest", function()
	it("maps species ids to their kit names, in order and without repeats", function()
		expect(KitRequest.parse("gummy,mochi,gummy")).toEqual({ "slime_gummy", "slime_mochi" })
		expect(KitRequest.kitOf("gummy")).toBe("slime_gummy")
		expect(KitRequest.kitOf("nope")).toBeNil()
	end)
	it("refuses malformed requests", function()
		expect(KitRequest.parse(nil)).toBeNil()
		expect(KitRequest.parse(42)).toBeNil()
		expect(KitRequest.parse("")).toBeNil()
		expect(KitRequest.parse("gummy,")).toBeNil()
		expect(KitRequest.parse("gummy,nope")).toBeNil()
		expect(KitRequest.parse(string.rep("a", KitRequest.MAX_LENGTH + 1))).toBeNil()
	end)
	it("takes at most MAX species per request", function()
		local ids = species(KitRequest.MAX + 1)
		expect(#(KitRequest.parse(table.concat(ids, ",", 1, KitRequest.MAX)) :: { string })).toBe(KitRequest.MAX)
		expect(KitRequest.parse(table.concat(ids, ","))).toBeNil()
	end)
	it("encodes wants into requests parse accepts, dropping species without a kit", function()
		local ids = species(KitRequest.MAX + 2)
		table.insert(ids, 1, "nope")
		local raws = KitRequest.encode(ids)
		expect(#raws).toBe(2)
		local total = 0
		for _, raw in raws do
			local kits = KitRequest.parse(raw)
			expect(kits ~= nil).toBe(true)
			total += #(kits :: { string })
		end
		expect(total).toBe(KitRequest.MAX + 2)
		expect(KitRequest.encode({ "nope" })).toEqual({})
	end)
	it("every kit is reachable by its species id", function()
		for _, kit in SlimeLooks.KITS do
			local id = string.sub(kit, #"slime_" + 1)
			expect(#id <= KitRequest.MAX_ID_LENGTH).toBe(true)
			expect(KitRequest.kitOf(id)).toBe(kit)
		end
	end)
end)
