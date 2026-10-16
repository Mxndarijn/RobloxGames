--!strict
-- Co-op ritual circle (CONTRACT.md §13): spot counting, the Idle / Charging / Cooldown state machine,
-- the reward, the cooldowns, anti-abuse, income, saving, and where the circle sits in the plaza.
local Config = require("../src/shared/Config")
local Fixtures = require("./Fixtures")
local Income = require("../src/server/Income")
local PlayerData = require("../src/shared/PlayerData")
local Ritual = require("../src/shared/Ritual")
local RitualService = require("../src/server/RitualService")
local SaveData = require("../src/shared/SaveData")
local ServerFixtures = require("./ServerFixtures")
local TestRunner = require("./TestRunner")
local WorldLayout = require("../src/visuals/shared/WorldLayout")

local describe, it, expect = TestRunner.describe, TestRunner.it, TestRunner.expect
local T0 = ServerFixtures.T0
local R = Config.RITUAL

-- A player standing on spot `i` (dx / dz move them off its centre).
local function onSpot(userId: number, i: number, dx: number?, dz: number?): Ritual.Candidate
	local s = Ritual.spots()[i]
	return { userId = userId, x = s[1] + (dx or 0), y = 3, z = s[2] + (dz or 0) }
end

local function count(t: { [number]: number }): number
	local n = 0
	for _ in t do
		n += 1
	end
	return n
end

describe("Ritual.occupants", function()
	it("counts a player on each spot", function()
		local state = Ritual.new()
		local occ = Ritual.occupants(state, { onSpot(1, 1), onSpot(2, 2), onSpot(3, 3) }, T0)
		expect(count(occ)).toBe(3)
		expect(occ[1]).toBe(1)
		expect(occ[3]).toBe(3)
	end)

	it("ignores players off the spots, too high, or with a bad position", function()
		local state = Ritual.new()
		local far = onSpot(1, 1, R.STAND_RADIUS + 1, 0)
		local high = onSpot(2, 2)
		high.y = R.STAND_HEIGHT + 20
		local nan = onSpot(3, 3)
		nan.x = 0 / 0
		expect(count(Ritual.occupants(state, { far, high, nan }, T0))).toBe(0)
	end)

	it("gives a shared spot to the nearest player only (no two accounts on one spot)", function()
		local state = Ritual.new()
		local occ = Ritual.occupants(state, { onSpot(5, 1, 1.5, 0), onSpot(4, 1, 0.5, 0) }, T0)
		expect(count(occ)).toBe(1)
		expect(occ[1]).toBe(4)
		-- exact tie: the lower userId
		local tie = Ritual.occupants(state, { onSpot(9, 1), onSpot(8, 1) }, T0)
		expect(tie[1]).toBe(8)
	end)

	it("counts one player once even when listed twice", function()
		local state = Ritual.new()
		local occ = Ritual.occupants(state, { onSpot(1, 1), onSpot(1, 2) }, T0)
		expect(count(occ)).toBe(1)
	end)
end)

describe("Ritual.step", function()
	it("shows n/3 while gathering and charges at 3", function()
		local state = Ritual.new()
		Ritual.step(state, { [1] = 1, [2] = 2 }, T0)
		expect(state.phase).toBe("Idle")
		expect(state.count).toBe(2)
		expect(select(2, Ritual.label(state, T0))).toBe("2/3 players")
		Ritual.step(state, { [1] = 1, [2] = 2, [3] = 3 }, T0 + 1)
		expect(state.phase).toBe("Charging")
		expect(state.chargeEndsAt).toBe(T0 + 1 + R.HOLD_SECONDS)
	end)

	it("completes after the hold and blesses each participant", function()
		local state = Ritual.new()
		local users = { [1] = 10, [2] = 11, [3] = 12 }
		Ritual.step(state, users, T0)
		expect(Ritual.step(state, users, T0 + R.HOLD_SECONDS - 0.1)).toBeNil()
		local done = Ritual.step(state, users, T0 + R.HOLD_SECONDS)
		expect(done).toBeTruthy()
		expect(done and done.userIds[1]).toBe(10)
		expect(#(done and done.userIds or {})).toBe(3)
		expect(done and done.bonus).toBe(R.BONUS[3])
		expect(state.phase).toBe("Cooldown")
		expect(state.blessed[11].untilAt).toBe(T0 + R.HOLD_SECONDS + R.BLESS_SECONDS)
	end)

	it("pays more for 4 players", function()
		local state = Ritual.new()
		local users = { [1] = 1, [2] = 2, [3] = 3, [4] = 4 }
		Ritual.step(state, users, T0)
		local done = Ritual.step(state, users, T0 + R.HOLD_SECONDS)
		expect(done and done.bonus).toBe(R.BONUS[4])
		expect(Ritual.bonus(2)).toBe(0)
		expect(Ritual.bonus(9)).toBe(R.BONUS[4])
	end)

	it("restarts the timer when someone steps off", function()
		local state = Ritual.new()
		local three = { [1] = 1, [2] = 2, [3] = 3 }
		Ritual.step(state, three, T0)
		Ritual.step(state, { [1] = 1, [2] = 2 }, T0 + 3)
		expect(state.phase).toBe("Idle")
		expect(state.chargeEndsAt).toBeNil()
		Ritual.step(state, three, T0 + 4)
		expect(Ritual.step(state, three, T0 + 4 + R.HOLD_SECONDS - 0.5)).toBeNil()
		expect(Ritual.step(state, three, T0 + 4 + R.HOLD_SECONDS)).toBeTruthy()
	end)

	it("rests for the server cooldown, ignoring everyone, then opens again", function()
		local state = Ritual.new()
		local users = { [1] = 1, [2] = 2, [3] = 3 }
		Ritual.step(state, users, T0)
		Ritual.step(state, users, T0 + R.HOLD_SECONDS)
		local mid = T0 + R.HOLD_SECONDS + 10
		expect(Ritual.step(state, users, mid)).toBeNil()
		expect(state.phase).toBe("Cooldown")
		expect(state.count).toBe(0)
		expect(Ritual.label(state, mid)).toBe("Ritual resting")
		Ritual.step(state, users, T0 + R.HOLD_SECONDS + R.SERVER_COOLDOWN)
		expect(state.phase).toBe("Charging")
	end)

	it("expires a blessing and reports who", function()
		local state = Ritual.new()
		local users = { [1] = 1, [2] = 2, [3] = 3 }
		Ritual.step(state, users, T0)
		Ritual.step(state, users, T0 + R.HOLD_SECONDS)
		local _, expired = Ritual.step(state, {}, T0 + R.HOLD_SECONDS + R.BLESS_SECONDS)
		expect(#expired).toBe(3)
		expect(next(state.blessed)).toBeNil()
	end)

	it("keeps a player on personal cooldown out of the next ritual", function()
		local state = Ritual.new()
		local users = { [1] = 1, [2] = 2, [3] = 3 }
		Ritual.step(state, users, T0)
		Ritual.step(state, users, T0 + R.HOLD_SECONDS)
		local later = T0 + R.HOLD_SECONDS + R.SERVER_COOLDOWN + 1
		expect(count(Ritual.occupants(state, { onSpot(1, 1), onSpot(7, 2) }, later))).toBe(1)
		local after = T0 + R.HOLD_SECONDS + R.PLAYER_COOLDOWN
		expect(count(Ritual.occupants(state, { onSpot(1, 1), onSpot(7, 2) }, after))).toBe(2)
		Ritual.forget(state, 1) -- leaving drops the blessing but not the cooldown
		expect(count(Ritual.occupants(state, { onSpot(1, 1) }, later))).toBe(0)
	end)

	it("is gated by FEATURES.CoopRitual", function()
		expect(type(Config.FEATURES.CoopRitual)).toBe("boolean")
		expect(Ritual.bonus(3) > 0).toBe(Config.FEATURES.CoopRitual)
	end)
end)

describe("RitualService.step", function()
	local function setup()
		local world = ServerFixtures.world()
		local sessions = {}
		for id = 1, 4 do
			sessions[id] = ServerFixtures.join(world, id, { Fixtures.slime(`s{id}`) }, 0)
		end
		return world, sessions, Ritual.new()
	end

	it("blesses three players, which raises their income, and not the bystander", function()
		local world, sessions, state = setup()
		local before = PlayerData.incomePerSecond(sessions[1].data)
		local group = { onSpot(1, 1), onSpot(2, 2), onSpot(3, 3), onSpot(4, 4, 6, 0) }
		RitualService.step(state, world, group, T0)
		local done = RitualService.step(state, world, group, T0 + R.HOLD_SECONDS)
		expect(done).toBeTruthy()
		expect(sessions[2].data.ritualBonus).toBe(R.BONUS[3])
		expect(sessions[4].data.ritualBonus).toBeNil()
		expect(PlayerData.incomePerSecond(sessions[1].data) > before * 1.19).toBeTruthy()
		local pays = 0
		for _, event in ServerFixtures.world and require("../src/server/World").drain(world) do
			if event.type == "Notify" and event.userId == 1 then
				pays += 1
			end
		end
		expect(pays > 0).toBeTruthy()
	end)

	it("ends the blessing at the deadline", function()
		local world, sessions, state = setup()
		local group = { onSpot(1, 1), onSpot(2, 2), onSpot(3, 3) }
		RitualService.step(state, world, group, T0)
		RitualService.step(state, world, group, T0 + R.HOLD_SECONDS)
		RitualService.step(state, world, {}, T0 + R.HOLD_SECONDS + R.BLESS_SECONDS - 1)
		expect(sessions[1].data.ritualBonus).toBe(R.BONUS[3])
		RitualService.step(state, world, {}, T0 + R.HOLD_SECONDS + R.BLESS_SECONDS)
		expect(sessions[1].data.ritualBonus).toBeNil()
	end)

	it("needs a loaded session and a slime", function()
		local world, sessions, state = setup()
		sessions[3].data.slimes = {}
		local group = { onSpot(1, 1), onSpot(2, 2), onSpot(3, 3), onSpot(99, 4) } -- 99 has no session
		RitualService.step(state, world, group, T0)
		expect(state.count).toBe(2)
		expect(RitualService.step(state, world, group, T0 + R.HOLD_SECONDS)).toBeNil()
		-- carrying a slime counts
		sessions[3].carry = { slimeId = "x" } :: any
		RitualService.step(state, world, group, T0 + 10)
		expect(state.count).toBe(3)
	end)

	it("is runtime only: the bonus is never saved", function()
		local data = Fixtures.data({ Fixtures.slime("a") }, 0)
		data.ritualBonus = 0.3
		local saved = SaveData.serialize(data, T0)
		expect(saved.ritualBonus).toBeNil()
		expect(SaveData.deserialize(saved).ritualBonus).toBeNil()
	end)

	it("pays Blessed income through Income.step", function()
		local world, sessions, state = setup()
		local plain = ServerFixtures.join(world, 50, { Fixtures.slime("p") }, 0)
		local group = { onSpot(1, 1), onSpot(2, 2), onSpot(3, 3) }
		RitualService.step(state, world, group, T0)
		RitualService.step(state, world, group, T0 + R.HOLD_SECONDS)
		local base1, basePlain = sessions[1].data.cash, plain.data.cash
		for _ = 1, 20 do
			Income.step(world, 5)
		end
		local gain, plainGain = sessions[1].data.cash - base1, plain.data.cash - basePlain
		expect(gain > plainGain * 1.19).toBeTruthy()
	end)
end)

describe("ritual circle placement", function()
	local cx, cz = Ritual.centre()
	local reach = R.CIRCLE_RADIUS

	it("sits in the plaza, clear of the slide, the parade lane, the ring path and the prop spots", function()
		local r = math.sqrt(cx ^ 2 + cz ^ 2)
		expect(r - reach > WorldLayout.SLIDE_END_RADIUS + 2).toBeTruthy()
		expect(r + reach < 64).toBeTruthy() -- the goo-parade lane keeps r 64.75..71.25 clear
		expect(r + reach < WorldLayout.PLAZA_RADIUS).toBeTruthy()
		for _, spot in WorldLayout.PROP_SPOTS do
			expect(math.sqrt((cx - spot.pos[1]) ^ 2 + (cz - spot.pos[3]) ^ 2) > reach + 12).toBeTruthy()
		end
		for _, prop in WorldLayout.RANCH_PROPS do
			expect(math.sqrt((cx - prop.pos[1]) ^ 2 + (cz - prop.pos[3]) ^ 2) > reach + prop.radius + 2).toBeTruthy()
		end
	end)

	it("keeps clear of every plot and its spoke path", function()
		for i = 1, Config.PLOT_COUNT do
			local c = WorldLayout.plotCentre(i)
			local half = WorldLayout.PLOT_SIZE / 2 + 4
			local near = math.abs(cx - c[1]) < half + reach and math.abs(cz - c[3]) < half + reach
			expect(near).toBe(false)
			local yaw = math.rad((i - 1) * 360 / Config.PLOT_COUNT)
			local nx, nz = math.sin(yaw), math.cos(yaw) -- spoke direction (bearing, 0 = +Z)
			local along = cx * nx + cz * nz
			local across = math.abs(cx * nz - cz * nx)
			if along > 0 then
				expect(across > 6 + reach).toBeTruthy()
			end
		end
	end)

	it("has all spots inside the circle and apart from each other", function()
		local spots = Ritual.spots()
		expect(#spots).toBe(R.SPOTS)
		for i, a in spots do
			expect(math.sqrt((a[1] - cx) ^ 2 + (a[2] - cz) ^ 2) + R.STAND_RADIUS <= R.CIRCLE_RADIUS).toBeTruthy()
			for j = i + 1, #spots do
				local b = spots[j]
				expect(math.sqrt((a[1] - b[1]) ^ 2 + (a[2] - b[2]) ^ 2) > R.STAND_RADIUS * 2).toBeTruthy()
			end
		end
	end)
end)
