--!strict
local KitDelivery = require("../src/server/KitDelivery")
local TestRunner = require("./TestRunner")

local describe, it, expect = TestRunner.describe, TestRunner.it, TestRunner.expect

local function setup()
	local loaded: { [string]: any } = { slime_a = "meshA" }
	local failed: { [string]: boolean } = { slime_bad = true }
	local sent: { string } = {}
	local delivery = KitDelivery.new({
		loaded = function(kit: string)
			return loaded[kit]
		end,
		failed = function(kit: string)
			return failed[kit] == true
		end,
		deliver = function(userId: number, kit: string, mesh: any)
			table.insert(sent, `{userId}:{kit}:{mesh}`)
		end,
	})
	return delivery, sent, loaded
end

describe("KitDelivery", function()
	it("sends a loaded kit to the asking player only, once", function()
		local d, sent = setup()
		expect(KitDelivery.request(d, 1, { "slime_a" })).toBe(1)
		expect(KitDelivery.request(d, 1, { "slime_a" })).toBe(0)
		expect(sent).toEqual({ "1:slime_a:meshA" })
		KitDelivery.request(d, 2, { "slime_a" })
		expect(sent).toEqual({ "1:slime_a:meshA", "2:slime_a:meshA" })
	end)
	it("sends a kit that is still loading when it arrives, to every player waiting", function()
		local d, sent, loaded = setup()
		KitDelivery.request(d, 1, { "slime_b" })
		KitDelivery.request(d, 2, { "slime_b" })
		expect(sent).toEqual({})
		loaded.slime_b = "meshB"
		KitDelivery.kitLoaded(d, "slime_b", "meshB")
		table.sort(sent)
		expect(sent).toEqual({ "1:slime_b:meshB", "2:slime_b:meshB" })
		KitDelivery.kitLoaded(d, "slime_b", "meshB")
		expect(#sent).toBe(2)
	end)
	it("never sends a failed kit, and forgets a player who left", function()
		local d, sent = setup()
		KitDelivery.request(d, 1, { "slime_bad", "slime_c" })
		KitDelivery.forget(d, 1)
		KitDelivery.kitLoaded(d, "slime_c", "meshC")
		expect(sent).toEqual({})
		expect(next(d.waiting)).toBeNil()
		-- After a rejoin the player is sent the kit again.
		KitDelivery.request(d, 1, { "slime_a" })
		KitDelivery.forget(d, 1)
		KitDelivery.request(d, 1, { "slime_a" })
		expect(#sent).toBe(2)
	end)
end)
