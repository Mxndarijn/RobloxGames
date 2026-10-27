--!strict
-- Co-op ritual circle (CONTRACT.md §13): spot counting, the Idle / Charging / Cooldown state machine,
-- the reward, the cooldowns, anti-abuse, income, saving, and where the circle sits in the plaza.
local Config = require("../src/shared/Config")
local Fixtures = require("./Fixtures")
local Income = require("../src/server/Income")
local ParadeLane = require("../src/shared/ParadeLane")
local PlayerData = require("../src/shared/PlayerData")
local PropClearance = require("../src/visuals/shared/PropClearance")
local Ritual = require("../src/shared/Ritual")
local RitualService = require("../src/server/RitualService")
local SaveData = require("../src/shared/SaveData")
local ServerFixtures = require("./ServerFixtures")
local Snapshot = require("../src/server/Snapshot")
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
		local occ = Ritual.occupants(state, { onSpot(1, 1), onSpot(2, 2) }, T0)
		expect(count(occ)).toBe(R.SPOTS)
		expect(occ[1]).toBe(1)
		expect(occ[2]).toBe(2)
	end)

	it("ignores players off the spots, too high, or with a bad position", function()
		local state = Ritual.new()
		local far = onSpot(1, 1, R.STAND_RADIUS + 1, 0)
		local high = onSpot(2, 2)
		high.y = R.STAND_HEIGHT + 20
		local nan = onSpot(3, 1)
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
	it("shows n/2 while gathering and charges at 2", function()
		local state = Ritual.new()
		Ritual.step(state, { [1] = 1 }, T0)
		expect(state.phase).toBe("Idle")
		expect(state.count).toBe(1)
		expect(select(2, Ritual.label(state, T0))).toBe("1/2 players")
		Ritual.step(state, { [1] = 1, [2] = 2 }, T0 + 1)
		expect(state.phase).toBe("Charging")
		expect(state.chargeEndsAt).toBe(T0 + 1 + R.HOLD_SECONDS)
	end)

	it("completes after the hold and blesses each participant", function()
		local state = Ritual.new()
		local users = { [1] = 10, [2] = 11 }
		Ritual.step(state, users, T0)
		expect(Ritual.step(state, users, T0 + R.HOLD_SECONDS - 0.1)).toBeNil()
		local done = Ritual.step(state, users, T0 + R.HOLD_SECONDS)
		expect(done).toBeTruthy()
		expect(done and done.userIds[1]).toBe(10)
		expect(#(done and done.userIds or {})).toBe(2)
		expect(done and done.bonus).toBe(R.BONUS[2])
		expect(state.phase).toBe("Cooldown")
		expect(state.blessed[11].untilAt).toBe(T0 + R.HOLD_SECONDS + R.BLESS_SECONDS)
	end)

	it("has one pad per required player, so bonus tiers above that are capped", function()
		expect(R.SPOTS).toBe(R.MIN_PLAYERS)
		expect(#Ritual.spots()).toBe(R.MIN_PLAYERS)
		expect(Ritual.bonus(R.SPOTS + 2)).toBe(R.BONUS[R.SPOTS])
	end)

	it("pays the capped bonus when more than the pads stand (map input)", function()
		local state = Ritual.new()
		local users = { [1] = 1, [2] = 2, [3] = 3, [4] = 4 }
		Ritual.step(state, users, T0)
		local done = Ritual.step(state, users, T0 + R.HOLD_SECONDS)
		expect(done and done.bonus).toBe(R.BONUS[R.SPOTS])
		expect(Ritual.bonus(1)).toBe(0)
		expect(Ritual.bonus(9)).toBe(R.BONUS[R.SPOTS])
	end)

	it("restarts the timer when someone steps off", function()
		local state = Ritual.new()
		local pair = { [1] = 1, [2] = 2 }
		Ritual.step(state, pair, T0)
		Ritual.step(state, { [1] = 1 }, T0 + 3)
		expect(state.phase).toBe("Idle")
		expect(state.chargeEndsAt).toBeNil()
		Ritual.step(state, pair, T0 + 4)
		expect(Ritual.step(state, pair, T0 + 4 + R.HOLD_SECONDS - 0.5)).toBeNil()
		expect(Ritual.step(state, pair, T0 + 4 + R.HOLD_SECONDS)).toBeTruthy()
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
		local later = T0 + R.HOLD_SECONDS + R.PLAYER_COOLDOWN - 1
		expect(count(Ritual.occupants(state, { onSpot(1, 1), onSpot(7, 2) }, later))).toBe(1)
		local after = T0 + R.HOLD_SECONDS + R.PLAYER_COOLDOWN
		expect(count(Ritual.occupants(state, { onSpot(1, 1), onSpot(7, 2) }, after))).toBe(2)
		Ritual.forget(state, 1) -- leaving drops the blessing but not the cooldown
		expect(count(Ritual.occupants(state, { onSpot(1, 1) }, later))).toBe(0)
	end)

	it("is gated by FEATURES.CoopRitual", function()
		expect(type(Config.FEATURES.CoopRitual)).toBe("boolean")
		expect(Ritual.bonus(2) > 0).toBe(Config.FEATURES.CoopRitual)
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

	it("blesses two players, which raises their income, and not the bystander", function()
		local world, sessions, state = setup()
		local before = PlayerData.incomePerSecond(sessions[1].data)
		local group = { onSpot(1, 1), onSpot(2, 2), onSpot(4, 1, 6, 0) }
		RitualService.step(state, world, group, T0)
		local done = RitualService.step(state, world, group, T0 + R.HOLD_SECONDS)
		expect(done).toBeTruthy()
		expect(sessions[2].data.ritualBonus).toBe(R.BONUS[2])
		expect(sessions[4].data.ritualBonus).toBeNil()
		expect(PlayerData.incomePerSecond(sessions[1].data) > before * 1.29).toBeTruthy()
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
		local group = { onSpot(1, 1), onSpot(2, 2) }
		RitualService.step(state, world, group, T0)
		RitualService.step(state, world, group, T0 + R.HOLD_SECONDS)
		RitualService.step(state, world, {}, T0 + R.HOLD_SECONDS + R.BLESS_SECONDS - 1)
		expect(sessions[1].data.ritualBonus).toBe(R.BONUS[2])
		RitualService.step(state, world, {}, T0 + R.HOLD_SECONDS + R.BLESS_SECONDS)
		expect(sessions[1].data.ritualBonus).toBeNil()
		expect(sessions[1].blessedUntil).toBeNil()
	end)

	it("sends State.blessed with the bonus and its end time while it lasts", function()
		local world, sessions, state = setup()
		local group = { onSpot(1, 1), onSpot(2, 2) }
		expect(Snapshot.build(world, sessions[1], T0).blessed).toBeNil()
		RitualService.step(state, world, group, T0)
		RitualService.step(state, world, group, T0 + R.HOLD_SECONDS)
		local view = Snapshot.build(world, sessions[1], T0 + R.HOLD_SECONDS).blessed :: any
		expect(view.bonus).toBe(R.BONUS[2])
		expect(view.endsAt).toBe(T0 + R.HOLD_SECONDS + R.BLESS_SECONDS)
		expect(Snapshot.build(world, sessions[4], T0 + R.HOLD_SECONDS).blessed).toBeNil()
		RitualService.step(state, world, {}, T0 + R.HOLD_SECONDS + R.BLESS_SECONDS)
		expect(Snapshot.build(world, sessions[1], T0 + R.HOLD_SECONDS + R.BLESS_SECONDS).blessed).toBeNil()
	end)

	it("needs a loaded session and a slime", function()
		local world, sessions, state = setup()
		sessions[2].data.slimes = {}
		local group = { onSpot(1, 1), onSpot(2, 2) }
		local ghost = { onSpot(1, 1), onSpot(99, 2) } -- 99 has no session
		RitualService.step(state, world, ghost, T0)
		expect(state.count).toBe(1)
		RitualService.step(state, world, group, T0)
		expect(state.count).toBe(1)
		expect(RitualService.step(state, world, group, T0 + R.HOLD_SECONDS)).toBeNil()
		-- carrying a slime counts
		sessions[2].carry = { slimeId = "x" } :: any
		RitualService.step(state, world, group, T0 + 10)
		expect(state.count).toBe(2)
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
		local group = { onSpot(1, 1), onSpot(2, 2) }
		RitualService.step(state, world, group, T0)
		RitualService.step(state, world, group, T0 + R.HOLD_SECONDS)
		local base1, basePlain = sessions[1].data.cash, plain.data.cash
		for _ = 1, 20 do
			Income.step(world, 5)
		end
		local gain, plainGain = sessions[1].data.cash - base1, plain.data.cash - basePlain
		expect(gain > plainGain * 1.29).toBeTruthy()
	end)
end)

describe("ritual circle placement", function()
	local cx, cz = Ritual.centre()
	local reach = R.CIRCLE_RADIUS
	local margin = 2

	local function dist(ax: number, az: number, bx: number, bz: number): number
		return math.sqrt((ax - bx) ^ 2 + (az - bz) ^ 2)
	end

	-- Distance from the circle centre to the lane's drawn polyline.
	local function laneDistance(): number
		local pts = ParadeLane.drawPoints()
		local best = math.huge
		for i = 1, #pts - 1 do
			local a, b = pts[i], pts[i + 1]
			local dx, dz = b[1] - a[1], b[2] - a[2]
			local t = math.clamp(((cx - a[1]) * dx + (cz - a[2]) * dz) / math.max(dx * dx + dz * dz, 1e-9), 0, 1)
			best = math.min(best, dist(cx, cz, a[1] + dx * t, a[2] + dz * t))
		end
		return best
	end

	it("keeps the whole circle off the slime lane, with a margin", function()
		expect(laneDistance() > reach + ParadeLane.CLEARANCE + margin).toBeTruthy()
		local r = dist(cx, cz, 0, 0)
		expect(r - reach > ParadeLane.LANE_RADIUS + 3.25 + margin).toBeTruthy() -- outside the r 68 lane band too
	end)

	it("clears the slide, the fountain, the ring path, the plots, the border and the props", function()
		local conflicts = PropClearance.conflicts({
			pos = { cx, 0, cz },
			size = { reach * 2 + margin * 2, 1, reach * 2 + margin * 2 },
			yaw = 0,
		})
		expect(table.concat(conflicts, ", ")).toBe("")
		for _, prop in WorldLayout.RANCH_PROPS do
			expect(dist(cx, cz, prop.pos[1], prop.pos[3]) > reach + prop.radius + 2).toBeTruthy()
		end
	end)

	it("keeps clear of every plot and its spoke path", function()
		for i = 1, Config.PLOT_COUNT do
			local c = WorldLayout.plotCentre(i)
			local half = WorldLayout.PLOT_SIZE / 2 + 1 -- the fence
			local inside = math.abs(cx - c[1]) < half + reach and math.abs(cz - c[3]) < half + reach
			expect(inside and dist(cx, cz, c[1], c[3]) < half + reach).toBe(false)
			local yaw = math.rad((i - 1) * 360 / Config.PLOT_COUNT)
			local nx, nz = math.sin(yaw), math.cos(yaw) -- spoke direction (bearing, 0 = +Z)
			local along = cx * nx + cz * nz
			local across = math.abs(cx * nz - cz * nx)
			if along > 0 then
				expect(across > 6 + reach).toBeTruthy()
			end
		end
	end)

	it("generates the sign text from Config and keeps the sign at the plaza edge, off the lane", function()
		local text = Ritual.signText()
		expect(text:find(`{R.MIN_PLAYERS} players`, 1, true) ~= nil).toBe(true)
		expect(text:find(`{R.HOLD_SECONDS}s`, 1, true) ~= nil).toBe(true)
		expect(text:find(`+{math.floor(R.BONUS[R.MIN_PLAYERS] * 100 + 0.5)}%`, 1, true) ~= nil).toBe(true)
		expect(text:find(`{R.BLESS_SECONDS // 60} min`, 1, true) ~= nil).toBe(true)
		local sx, sz = Ritual.signSpot()
		expect(dist(sx, sz, cx, cz) <= reach + margin).toBe(true) -- inside the clearance already tested
		expect(dist(sx, sz, 0, 0) < dist(cx, cz, 0, 0)).toBe(true) -- on the plaza side
	end)

	it("has one pad per required player, evenly spaced (RitualView builds one part per Ritual.spots entry)", function()
		local spots = Ritual.spots()
		expect(#spots).toBe(R.MIN_PLAYERS)
		local gap = dist(spots[1][1], spots[1][2], spots[2][1], spots[2][2])
		for i, a in spots do
			expect(math.abs(dist(a[1], a[2], cx, cz) - R.SPOT_DISTANCE) < 1e-6).toBeTruthy()
			local b = spots[i % #spots + 1]
			expect(math.abs(dist(a[1], a[2], b[1], b[2]) - gap) < 1e-6).toBeTruthy()
		end
	end)

	it("has all spots inside the circle and apart from each other", function()
		local spots = Ritual.spots()
		expect(#spots).toBe(R.SPOTS)
		for i, a in spots do
			expect(dist(a[1], a[2], cx, cz) + R.STAND_RADIUS <= R.CIRCLE_RADIUS).toBeTruthy()
			for j = i + 1, #spots do
				local b = spots[j]
				expect(dist(a[1], a[2], b[1], b[2]) > R.STAND_RADIUS * 2).toBeTruthy()
			end
		end
	end)
end)
