--!strict
-- PurchaseService with a fake backend and save: receipts are granted once and confirmed only after a save.
local Config = require("../src/shared/Config")
local PurchaseService = require("../src/server/PurchaseService")
local ServerFixtures = require("./ServerFixtures")
local TestRunner = require("./TestRunner")

local describe, it, expect = TestRunner.describe, TestRunner.it, TestRunner.expect
local T0 = ServerFixtures.T0

local function setup(opts: { saveOk: boolean?, owns: { [number]: boolean }?, restricted: any?, on: boolean? }?)
	local o = opts or {}
	local world = ServerFixtures.world()
	local calls = { saves = 0, owns = 0, changed = 0 }
	local saveOk = o.saveOk ~= false
	local service = PurchaseService.service({
		world = world,
		backend = {
			ownsPass = function(_userId: number, passId: number): boolean
				calls.owns += 1
				return (o.owns or {})[passId] == true
			end,
			paidRandomRestricted = function(_userId: number): boolean
				if o.restricted == "error" then
					error("policy down")
				end
				return o.restricted == true
			end,
		},
		save = function(_userId: number, _data: any): boolean
			calls.saves += 1
			return saveOk
		end,
		now = function()
			return T0
		end,
		wait = function() end,
		changed = function()
			calls.changed += 1
		end,
		ctx = { features = { ExclusiveShop = o.on ~= false } },
		attempts = 1,
	})
	return world, service, calls, function(ok: boolean)
		saveOk = ok
	end
end

describe("PurchaseService receipts", function()
	it("is not processed yet for a player who is not loaded, an unknown product id or while the flag is off", function()
		local world, service = setup()
		expect(service.grantProduct(5, "Seat_ufo", "p1")).toBe("NotProcessedYet")
		ServerFixtures.join(world, 1)
		expect(service.processReceipt({ PlayerId = 1, ProductId = 123, PurchaseId = "p1" })).toBe("NotProcessedYet")
		expect(service.processReceipt({ PlayerId = 1, ProductId = 0, PurchaseId = "p1" })).toBe("NotProcessedYet")
		local offWorld, off = setup({ on = false })
		ServerFixtures.join(offWorld, 1)
		expect(off.grantProduct(1, "Seat_ufo", "p1")).toBe("NotProcessedYet")
	end)
	it("grants, records and saves once; the same PurchaseId again is granted without a second grant", function()
		local world, service, calls = setup()
		local s = ServerFixtures.join(world, 1, nil, 0)
		expect(service.grantProduct(1, "FinishBrew_1", "p1")).toBe("PurchaseGranted")
		expect(s.data.credits.brew).toBe(1)
		expect(s.data.receipts).toEqual({ "p1" })
		expect(calls.saves).toBe(1)
		expect(service.grantProduct(1, "FinishBrew_1", "p1")).toBe("PurchaseGranted")
		expect(s.data.credits.brew).toBe(1)
		expect(calls.saves).toBe(1)
		expect(calls.changed >= 1).toBe(true)
	end)
	it("answers NotProcessedYet while the save fails and confirms the retry after a good save", function()
		local world, service, calls, setSave = setup({ saveOk = false })
		local s = ServerFixtures.join(world, 1, nil, 0)
		expect(service.grantProduct(1, "Seat_ufo", "p9")).toBe("NotProcessedYet")
		expect(s.data.ownedSeats).toEqual({ "ufo" })
		setSave(true)
		expect(service.grantProduct(1, "Seat_ufo", "p9")).toBe("PurchaseGranted")
		expect(s.data.ownedSeats).toEqual({ "ufo" })
		expect(s.data.receipts).toEqual({ "p9" })
		expect(calls.saves).toBe(2)
	end)
end)

describe("PurchaseService passes and policy", function()
	it("skips passes without an id and reads the paid random items policy", function()
		local world, service, calls = setup({ restricted = false })
		local s = ServerFixtures.join(world, 1)
		service.join(1)
		expect(calls.owns).toBe(0) -- every Config pass id is still 0
		expect(s.paidRandomAllowed).toBe(true)
		expect(s.passes).toEqual({ Income2x = false, Offline2x = false })
	end)
	it("keeps paid random items hidden when the policy restricts them or can't be read", function()
		local world, service = setup({ restricted = true })
		local s = ServerFixtures.join(world, 1)
		service.join(1)
		expect(s.paidRandomAllowed).toBe(false)
		local world2, service2 = setup({ restricted = "error" })
		local s2 = ServerFixtures.join(world2, 1)
		service2.join(1)
		expect(s2.paidRandomAllowed).toBeNil()
	end)
	it("setPass applies the pass factors; setPaidRandomAllowed overrides the policy", function()
		local world, service = setup()
		local s = ServerFixtures.join(world, 1)
		expect(service.setPass(1, "Income2x", true)).toBe(true)
		expect(s.data.passIncomeMult).toBe(Config.EXCLUSIVE_SHOP.passes.Income2x.incomeMult)
		expect(service.setPass(1, "Nope", true)).toBe(false)
		expect(service.setPass(1, "Income2x", false)).toBe(true)
		expect(s.data.passIncomeMult).toBeNil()
		expect(service.setPaidRandomAllowed(1, true)).toBe(true)
		expect(s.paidRandomAllowed).toBe(true)
	end)
end)
