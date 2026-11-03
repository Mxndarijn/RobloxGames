--!strict
-- Vine ropes for everyone (contract/obby.md §5; Merijn: other players must see each other swing): the runner's
-- client says which rope it holds (Request ObbyVine, paced by visuals/shared/ObbyVineSend), the server keeps it on
-- the run only for a rope of that course (ObbyService.holdVine / heldVine, published as the Player's ObbyVine
-- attribute), and every other client turns that rope to the angle the holder's root hangs at (Vine.angleAt).
local Actions = require("../src/server/Actions")
local ObbyCourse = require("../src/shared/ObbyCourse")
local ObbyService = require("../src/server/ObbyService")
local ObbyVineSend = require("../src/visuals/shared/ObbyVineSend")
local ServerFixtures = require("./ServerFixtures")
local TestRunner = require("./TestRunner")
local Validate = require("../src/shared/Validate")
local Vine = require("../src/shared/ObbySections/Vine")

local describe, it, expect = TestRunner.describe, TestRunner.it, TestRunner.expect

local T = ObbyCourse.slotStart(ObbyCourse.slot(ServerFixtures.T0) + 1) + 10
local ROPE = "9.1"
local PLACE: ObbyService.Place = {
	frame = { origin = { 0, 400, -9000 }, yaw = 180 },
	portal = { -95, 0, 230 },
	portalRadius = 5,
	exit = { -92, 3, 222 },
	exitYaw = 337.5,
	zone = { centre = { 0, 400, -9150 }, radius = 1500 },
}
local ctx: Actions.Context = {
	distanceBetween = function()
		return 2
	end,
	positionOf = function()
		return "pos"
	end,
}

-- A world whose player 1 is on a run, on a course with one vine rope (ROPE) and one plain part ("9.2").
local function running(): (any, any)
	local world = ServerFixtures.world(T)
	ServerFixtures.join(world, 1, nil, 0, T)
	ObbyService.setup(world, T)
	table.insert(world.obby.parts, { id = ROPE, vine = { reach = 4 } } :: any)
	table.insert(world.obby.parts, { id = "9.2" } :: any)
	local session = world.sessions[1]
	expect((ObbyService.enter(world, session, PLACE, T))).toBe(true)
	return world, session
end

describe("Vine.angleAt", function()
	it("turns a hanging root back into the rope angle it hangs at", function()
		local arm = 9
		for _, th in { -1, -0.4, 0, 0.3, 0.9 } do
			local s, y = Vine.rootAt(arm, th)
			expect(math.abs((Vine.angleAt(arm, s, y) :: number) - th) < 1e-4).toBe(true)
		end
	end)
	it("draws nobody on a rope they are nowhere near", function()
		expect(Vine.angleAt(9, 0, -(Vine.length(9) + Vine.HOLD_SLACK + 1))).toBe(nil)
		expect(Vine.angleAt(9, 30, 0)).toBe(nil)
	end)
end)

describe("ObbyService.holdVine", function()
	it("keeps the rope a runner holds on their run and publishes it until they let go", function()
		local world, session = running()
		expect((ObbyService.holdVine(world, session, ROPE))).toBe(true)
		expect(ObbyService.heldVine(world, session)).toBe(ROPE)
		expect((ObbyService.holdVine(world, session, ""))).toBe(true)
		expect(ObbyService.heldVine(world, session)).toBe(nil)
	end)
	it("refuses a part that is no rope, a part not on the course and anyone off a run", function()
		local world, session = running()
		expect(select(2, ObbyService.holdVine(world, session, "9.2"))).toBe("not a vine")
		expect(select(2, ObbyService.holdVine(world, session, "nope"))).toBe("not a vine")
		session.obbyRun = nil
		expect(select(2, ObbyService.holdVine(world, session, ROPE))).toBe("not on a run")
		expect(ObbyService.heldVine(world, session)).toBe(nil)
	end)
	it("lets go for everyone once the run ends or the course rotates", function()
		local world, session = running()
		ObbyService.holdVine(world, session, ROPE)
		world.obby.slot += 1
		expect(ObbyService.heldVine(world, session)).toBe(nil)
		world.obby.slot -= 1
		session.obbyRun = nil
		expect(ObbyService.heldVine(world, session)).toBe(nil)
	end)
end)

describe("Actions ObbyVine", function()
	it("sets the held rope without a State push, rate-limited per player", function()
		local world, session = running()
		session.dirty = false
		local res, ran = Actions.handle(world, 1, "ObbyVine", { ROPE }, T + 1, ctx)
		expect(res.ok).toBe(true)
		expect(ran).toBe(false)
		expect(session.dirty).toBe(false)
		expect(ObbyService.heldVine(world, session)).toBe(ROPE)
		expect(Actions.handle(world, 1, "ObbyVine", { "" }, T + 1.05, ctx).message).toBe("too fast")
		expect(Actions.handle(world, 1, "ObbyVine", { "" }, T + 1.2, ctx).ok).toBe(true)
		expect(ObbyService.heldVine(world, session)).toBe(nil)
	end)
	it("refuses bad arguments", function()
		local world = running()
		expect(Actions.handle(world, 1, "ObbyVine", { 42 }, T + 1, ctx).message).toBe("bad argument")
		expect(Actions.handle(world, 1, "ObbyVine", { string.rep("a", 65) }, T + 2, ctx).message).toBe("bad argument")
	end)
end)

describe("ObbyVineSend", function()
	it("sends only the latest hold, one at a time, never faster than the server allows", function()
		local s = ObbyVineSend.new()
		expect(ObbyVineSend.next(s, "", "", 0)).toBe(nil) -- nothing held, nothing sent
		expect(ObbyVineSend.next(s, ROPE, "", 1)).toBe(ROPE)
		expect(ObbyVineSend.next(s, "", "", 1.5)).toBe(nil) -- still in flight
		ObbyVineSend.done(s)
		expect(ObbyVineSend.next(s, "", ROPE, 1 + ObbyVineSend.GAP / 2)).toBe(nil) -- too soon
		expect(ObbyVineSend.next(s, "9.3", ROPE, 1 + ObbyVineSend.GAP)).toBe("9.3") -- a quick let go and grab: one send
		ObbyVineSend.done(s)
		expect(ObbyVineSend.GAP > Validate.ACTIONS.ObbyVine).toBe(true)
	end)
	it("sends a hold again that the server has not shown after RESEND, and nothing once it shows", function()
		local s = ObbyVineSend.new()
		expect(ObbyVineSend.next(s, ROPE, "", 0)).toBe(ROPE)
		ObbyVineSend.done(s)
		expect(ObbyVineSend.next(s, ROPE, "", ObbyVineSend.RESEND / 2)).toBe(nil)
		expect(ObbyVineSend.next(s, ROPE, "", ObbyVineSend.RESEND + 0.01)).toBe(ROPE)
		ObbyVineSend.done(s)
		expect(ObbyVineSend.next(s, ROPE, ROPE, 5)).toBe(nil)
		-- the run ended and the server let go for us as we let go: nothing to send
		expect(ObbyVineSend.next(s, "", "", 6)).toBe(nil)
		expect(ObbyVineSend.next(s, "", "", 7)).toBe(nil)
	end)
end)
