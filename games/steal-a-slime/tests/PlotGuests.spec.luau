--!strict
-- The friends switch (src/server/PlotGuests.luau, FEATURES.FriendsInBase): who is a guest of a locked base, and what
-- a guest may do there (walk in, steal, never count as an intruder).
local Actions = require("../src/server/Actions")
local Carry = require("../src/server/Carry")
local Fixtures = require("./Fixtures")
local Friends = require("../src/server/Friends")
local PlotGuests = require("../src/server/PlotGuests")
local PlotPrompts = require("../src/server/PlotPrompts")
local SaveData = require("../src/shared/SaveData")
local Scene = require("../src/server/Scene")
local ServerFixtures = require("./ServerFixtures")
local SlimeGuard = require("../src/server/SlimeGuard")
local StealService = require("../src/server/StealService")
local TestRunner = require("./TestRunner")
local World = require("../src/server/World")

local describe, it, expect = TestRunner.describe, TestRunner.it, TestRunner.expect
local T0 = ServerFixtures.T0
local ON = { FriendsInBase = true }
local OFF = { FriendsInBase = false }

-- Owner 1 has "gem" on a locked plot; 2 is their friend, 3 a stranger. Nobody has switched anything on yet.
local function setup()
	local world = ServerFixtures.world()
	local owner = ServerFixtures.join(world, 1, { Fixtures.slime("gem", 4) })
	local friend = ServerFixtures.join(world, 2)
	local stranger = ServerFixtures.join(world, 3)
	owner.friendIds = { [2] = true }
	friend.friendIds = { [1] = true }
	stranger.friendIds = {}
	owner.lockStartedAt = T0
	owner.lockUntil = T0 + 100
	return world, owner, friend, stranger
end

local ctx: Actions.Context = {
	distanceBetween = function()
		return 2
	end,
	positionOf = function()
		return "pos"
	end,
	features = ON,
}

describe("PlotGuests.isGuest", function()
	it("is true only for a friend in the server while the owner's switch is on", function()
		local world, owner, _, _ = setup()
		expect(PlotGuests.isGuest(owner, 2, ON)).toBe(false) -- switch off
		owner.data.allowFriends = true
		expect(PlotGuests.isGuest(owner, 2, ON)).toBe(true)
		expect(PlotGuests.isGuest(owner, 3, ON)).toBe(false) -- not a friend
		expect(PlotGuests.isGuest(owner, 1, ON)).toBe(false) -- the owner is not their own guest
		expect(PlotGuests.isGuest(owner, 2, OFF)).toBe(false) -- feature off
		expect(PlotGuests.isGuestOf(world, owner.plotIndex, 2, ON)).toBe(true)
		expect(PlotGuests.isGuest(nil, 2, ON)).toBe(false)
	end)

	it("lists the guests in the server, sorted, and who passes each stopper", function()
		local world, owner, friend, _ = setup()
		ServerFixtures.join(world, 4)
		owner.friendIds = { [4] = true, [2] = true, [99] = true } -- 99 left the server
		owner.data.allowFriends = true
		expect(PlotGuests.list(world, owner, ON)).toEqual({ 2, 4 })
		expect(PlotGuests.encode(PlotGuests.list(world, owner, ON))).toBe(",2,4,")
		expect(PlotGuests.encode({})).toBeNil()
		local passes = SlimeGuard.stopperPasses(world, ON)
		expect(passes[owner.plotIndex]).toEqual({ 2, 4 })
		expect(passes[friend.plotIndex]).toBeNil() -- the friend has not switched theirs on
		expect(next(SlimeGuard.stopperPasses(world, OFF))).toBeNil()
	end)
end)

describe("PlotGuests.toggle", function()
	it("flips the switch, tells the owner and, on switching on, the friends in the server", function()
		local world, owner, _, _ = setup()
		local res = Actions.handle(world, 1, "ToggleFriends", { n = 0 }, T0 + 1, ctx)
		expect(res.ok).toBe(true)
		expect(owner.data.allowFriends).toBe(true)
		expect(#ServerFixtures.notifications(world, 1)).toBe(1)
		expect(string.find(ServerFixtures.notifications(world, 2)[1] or "", "lets you into their base", 1, true)).toBeTruthy()
		expect(#ServerFixtures.notifications(world, 3)).toBe(0)
		ServerFixtures.clearEvents(world)
		expect(Actions.handle(world, 1, "ToggleFriends", { n = 0 }, T0 + 2, ctx).ok).toBe(true)
		expect(owner.data.allowFriends).toBeNil()
		expect(string.find(ServerFixtures.notifications(world, 1)[1] or "", "blocked", 1, true)).toBeTruthy()
		expect(#ServerFixtures.notifications(world, 2)).toBe(0)
	end)

	it("is refused with the feature off", function()
		local world, owner, _, _ = setup()
		local off = table.clone(ctx)
		off.features = OFF
		expect(Actions.handle(world, 1, "ToggleFriends", { n = 0 }, T0 + 1, off).ok).toBe(false)
		expect(owner.data.allowFriends).toBeNil()
	end)

	it("is rate limited like the lock", function()
		local world, owner, _, _ = setup()
		expect(Actions.handle(world, 1, "ToggleFriends", { n = 0 }, T0 + 1, ctx).ok).toBe(true)
		expect(Actions.handle(world, 1, "ToggleFriends", { n = 0 }, T0 + 1.1, ctx).message).toBe("too fast")
		expect(owner.data.allowFriends).toBe(true)
	end)

	it("only the owner flips it from the lock button", function()
		local world, owner, _, _ = setup()
		Actions.triggerPlotPrompt(world, 2, owner.plotIndex, "ToggleFriends", T0 + 1, ctx)
		expect(owner.data.allowFriends).toBeNil()
		expect(Actions.triggerPlotPrompt(world, 1, owner.plotIndex, "ToggleFriends", T0 + 1, ctx).ok).toBe(true)
		expect(owner.data.allowFriends).toBe(true)
	end)
end)

describe("a guest in a locked base", function()
	it("may steal there; a stranger may not", function()
		local world, owner, _, _ = setup()
		expect((StealService.steal(world, world.sessions[3], "gem", 1, T0 + 1))).toBe(false)
		expect((StealService.steal(world, world.sessions[2], "gem", 1, T0 + 1))).toBe(false) -- switch off
		owner.data.allowFriends = true
		expect((StealService.steal(world, world.sessions[3], "gem", 1, T0 + 1))).toBe(false)
		expect((Carry.grab(world, 2, "gem", 1, T0 + 1))).toBe(true)
	end)

	it("is never an intruder while a guest, nor after the switch goes off while still inside", function()
		local world, owner, friend, _ = setup()
		world.guardMode = "watch"
		owner.data.allowFriends = true
		-- Walked in after the lock began: a stranger would be an intruder.
		expect(SlimeGuard.trackPlot(world, friend, owner.plotIndex, T0 + 10)).toBeNil()
		expect(SlimeGuard.trackPlot(world, friend, owner.plotIndex, T0 + 11)).toBeNil()
		owner.data.allowFriends = nil
		-- Removed while inside: stays put, not an intruder, can't steal, and the stopper still lets them out.
		expect(SlimeGuard.trackPlot(world, friend, owner.plotIndex, T0 + 12)).toBeNil()
		expect(SlimeGuard.trackPlot(world, friend, owner.plotIndex, T0 + 30)).toBeNil()
		expect((Carry.grab(world, 2, "gem", 1, T0 + 30))).toBe(false)
		expect(SlimeGuard.formerGuests(world)[owner.plotIndex][2]).toBe(true)
		expect(SlimeGuard.stopperPasses(world, ON)[owner.plotIndex]).toEqual({ 2 })
		-- Out of the jar: the pass is gone, and walking back in after the lock began makes them an intruder.
		expect(SlimeGuard.trackPlot(world, friend, nil, T0 + 31)).toBeNil()
		expect(SlimeGuard.formerGuests(world)[owner.plotIndex]).toBeNil()
		expect(SlimeGuard.trackPlot(world, friend, owner.plotIndex, T0 + 32)).toBe(owner.plotIndex)
	end)

	it("sees the Steal prompts: on, for the guests only", function()
		local world, owner, _, _ = setup()
		local entry = Scene.describe(world, T0 + 1)["gem"]
		expect(entry.promptEnabled).toBe(false)
		expect(entry.guestsOnly).toBeNil()
		owner.data.allowFriends = true
		entry = Scene.describe(world, T0 + 1)["gem"]
		expect(entry.promptEnabled).toBe(true)
		expect(entry.guestsOnly).toBe(",2,")
		-- Unlocked: open to everyone again.
		ServerFixtures.unlock(owner)
		entry = Scene.describe(world, T0 + 1)["gem"]
		expect(entry.promptEnabled).toBe(true)
		expect(entry.guestsOnly).toBeNil()
	end)
end)

describe("the lock button's friends prompt", function()
	it("says what pressing it does, and the plot shows the switch", function()
		local world, owner, _, _ = setup()
		local view = PlotPrompts.describe(world, owner.plotIndex, T0 + 1)
		expect(view.friends.actionText).toBe("Allow friends")
		expect(view.friends.objectText).toBe("Friends: blocked")
		expect(view.friendsAllowed).toBe(false)
		owner.data.allowFriends = true
		view = PlotPrompts.describe(world, owner.plotIndex, T0 + 1)
		expect(view.friends.actionText).toBe("Block friends")
		expect(view.friends.objectText).toBe("Friends can enter")
		expect(view.friendsAllowed).toBe(true)
	end)

	it("is off on a free plot", function()
		local world = ServerFixtures.world()
		expect(PlotPrompts.describe(world, 1, T0).friends.enabled).toBe(false)
	end)
end)

describe("the friends switch is saved", function()
	it("round-trips on, and a missing or junk value loads as off", function()
		local data = World.session(select(1, setup()), 1)
		assert(data, "session")
		data.data.allowFriends = true
		local stored = SaveData.serialize(data.data, T0)
		expect(stored.allowFriends).toBe(true)
		expect(SaveData.deserialize(stored).allowFriends).toBe(true)
		stored.allowFriends = "yes"
		expect(SaveData.deserialize(stored).allowFriends).toBeNil()
		stored.allowFriends = nil
		expect(SaveData.deserialize(stored).allowFriends).toBeNil()
		data.data.allowFriends = nil
		expect(SaveData.serialize(data.data, T0).allowFriends).toBeNil()
	end)
end)

describe("Friends.refresh friend ids", function()
	it("records each session's friends in the server for the switch", function()
		local world = ServerFixtures.world()
		local a = ServerFixtures.join(world, 1)
		local b = ServerFixtures.join(world, 2)
		local c = ServerFixtures.join(world, 3)
		local cache = Friends.new(function(x: number, y: number): boolean
			return (x == 1 and y == 2) or (x == 2 and y == 1)
		end)
		Friends.refresh(cache, world, T0)
		expect(a.friendIds and a.friendIds[2]).toBe(true)
		expect(b.friendIds and b.friendIds[1]).toBe(true)
		expect(c.friendIds and next(c.friendIds)).toBeNil()
	end)
end)
