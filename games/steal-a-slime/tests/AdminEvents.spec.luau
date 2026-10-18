--!strict
-- Live admin events: admin gate, command + payload validation, rate limit, effects, cross-server (CONTRACT.md §12).
local AdminEvents = require("../src/shared/AdminEvents")
local AdminEventsService = require("../src/server/AdminEventsService")
local Config = require("../src/shared/Config")
local CycleModifier = require("../src/shared/CycleModifier")
local ServerFixtures = require("./ServerFixtures")
local Snapshot = require("../src/server/Snapshot")
local Spawner = require("../src/server/Spawner")
local TestRunner = require("./TestRunner")

local describe, it, expect = TestRunner.describe, TestRunner.it, TestRunner.expect
local T0 = ServerFixtures.T0
local OWNER, STRANGER = 1000, 2000

local function notifies(world: any): number
	local n = 0
	for _, e in world.outbox do
		if e.type == "Notify" then
			n += 1
		end
	end
	return n
end

local function service(sent: { any }?)
	local world = ServerFixtures.world()
	local transport = if sent
		then {
			publish = function(_topic: string, data: any)
				table.insert(sent, data)
			end,
		}
		else nil
	return AdminEventsService.new(world, OWNER, transport), world
end

describe("AdminEvents gate", function()
	it("accepts only the owner and listed UserIds", function()
		expect(AdminEvents.isAdmin(OWNER, OWNER)).toBe(true)
		expect(AdminEvents.isAdmin(STRANGER, OWNER)).toBe(false)
		expect(AdminEvents.isAdmin(0, 0)).toBe(false)
		expect(AdminEvents.isAdmin(nil, OWNER)).toBe(false)
		expect(AdminEvents.isAdmin("1000", OWNER)).toBe(false)
		expect(AdminEvents.isAdmin(0 / 0, OWNER)).toBe(false)
	end)
	it("a non-admin chat command changes nothing, not even a reply", function()
		local sent = {}
		local svc, world = service(sent)
		expect(AdminEventsService.command(svc, STRANGER, "/event luck 10", T0)).toBeNil()
		expect(world.adminEvent).toBeNil()
		expect(world.modifier.name).toBe("None")
		expect(#sent).toBe(0)
		expect(notifies(world)).toBe(0)
	end)
	it("a forged cross-server payload from a non-admin is dropped", function()
		local svc, world = service()
		local forged = AdminEvents.payload("luck", 600, STRANGER, "n1")
		expect(AdminEventsService.receive(svc, forged, T0)).toBe(false)
		expect(world.adminEvent).toBeNil()
		expect(AdminEventsService.receive(svc, "luck", T0)).toBe(false)
		expect(AdminEventsService.receive(svc, { v = 1, id = "luck", by = OWNER }, T0)).toBe(false)
	end)
end)

describe("AdminEvents parse + validate", function()
	it("parses /event <id> [minutes] and clamps", function()
		local id, seconds = AdminEvents.parse("/event luck 10")
		expect(id).toBe("luck")
		expect(seconds).toBe(600)
		expect(select(2, AdminEvents.parse("/event rain"))).toBe(Config.ADMIN_EVENT_DEFAULT_SECONDS)
		expect(select(2, AdminEvents.parse("/event luck 9999"))).toBe(Config.ADMIN_EVENT_MAX_SECONDS)
		expect(select(2, AdminEvents.parse("/event luck 0"))).toBe(Config.ADMIN_EVENT_MIN_SECONDS)
		expect(AdminEvents.parse("/event nope 5")).toBeNil()
		expect(AdminEvents.parse("hello")).toBeNil()
		expect(AdminEvents.parse(5)).toBeNil()
	end)
	it("rejects bad payload fields and clamps seconds", function()
		expect(AdminEvents.validate(AdminEvents.payload("luck", 600, OWNER, "a"), OWNER) ~= nil).toBe(true)
		expect(AdminEvents.validate(AdminEvents.payload("bogus", 600, OWNER, "a"), OWNER)).toBeNil()
		expect(AdminEvents.validate({ v = 2, id = "luck", seconds = 60, by = OWNER, nonce = "a" }, OWNER)).toBeNil()
		expect(AdminEvents.validate({ v = 1, id = "luck", seconds = 60, by = OWNER, nonce = "" }, OWNER)).toBeNil()
		local p = AdminEvents.validate({ v = 1, id = "luck", seconds = 1e9, by = OWNER, nonce = "a" }, OWNER)
		expect((p :: any).seconds).toBe(Config.ADMIN_EVENT_MAX_SECONDS)
	end)
end)

describe("AdminEvents effects", function()
	it("luck event overrides the modifier, shows in State with its icon, then ends", function()
		local sent = {}
		local svc, world = service(sent)
		expect(AdminEventsService.command(svc, OWNER, "/event luck 1", T0)).toBe("Event started in all servers.")
		expect(#sent).toBe(1)
		expect(world.modifier.luck).toBe(3)
		expect(world.modifierEndsAt).toBe(T0 + 60)
		expect(CycleModifier.multiplier(world.modifier)).toBe(3)
		expect(notifies(world) >= 1).toBe(true)
		Spawner.stepModifier(world, T0 + 30)
		expect(world.modifier.luck).toBe(3)
		Spawner.stepModifier(world, T0 + 61)
		expect(world.adminEvent).toBeNil()
		expect(world.modifier.luck ~= 3).toBe(true)
	end)
	it("rain event starts a Slime Rain", function()
		local svc, world = service()
		AdminEventsService.command(svc, OWNER, "/event rain", T0)
		expect(Spawner.rain(world, T0 + 1)).toBe(true)
	end)
	it("rate limits triggers and applies a received event once", function()
		local svc, world = service()
		expect(AdminEventsService.command(svc, OWNER, "/event luck 1", T0)).toBeTruthy()
		expect(AdminEventsService.command(svc, OWNER, "/event rain", T0 + 1)).toBe(
			"Event cooldown: wait a few seconds."
		)
		expect(AdminEventsService.receive(svc, AdminEvents.payload("rain", 60, OWNER, "r0"), T0 + 5)).toBe(false) -- cooldown
		local p = AdminEvents.payload("luck", 120, OWNER, "remote-1")
		expect(AdminEventsService.receive(svc, p, T0 + 100)).toBe(true)
		expect(world.modifier.luck).toBe(3)
		expect(AdminEventsService.receive(svc, p, T0 + 300)).toBe(false) -- same nonce
	end)
	it("a failing transport still starts the event here", function()
		local world = ServerFixtures.world()
		local svc = AdminEventsService.new(world, OWNER, {
			publish = function()
				error("MessagingService throttled")
			end,
		})
		expect(AdminEventsService.command(svc, OWNER, "/event luck", T0)).toBe(
			"Event started here (cross-server send failed)."
		)
		expect(world.adminEvent ~= nil).toBe(true)
	end)
	it("Snapshot carries the icon while active", function()
		local svc, world = service()
		AdminEventsService.command(svc, OWNER, "/event luck", T0)
		local session = ServerFixtures.join(world, OWNER)
		local state = Snapshot.build(world, session, T0 + 1)
		expect(state.modifier.icon).toBe("🍀")
	end)
end)
