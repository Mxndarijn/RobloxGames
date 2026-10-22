--!strict
-- The boss event over World (src/server/BossEvent.luau, contract/boss-event.md): the schedule and its Slime Rain skip,
-- the rotation, the boss in the plaza, no slimes during the fight, the haul through Carry, the win and its boss badges, the escape and State.boss.
local BossCredit = require("../src/server/BossCredit")
local BossEvent = require("../src/server/BossEvent")
local BossFight = require("../src/shared/BossFight")
local Carry = require("../src/server/Carry")
local Config = require("../src/shared/Config")
local Fixtures = require("./Fixtures")
local Perks = require("../src/shared/Perks")
local PlayerData = require("../src/shared/PlayerData")
local Scene = require("../src/server/Scene")
local ServerFixtures = require("./ServerFixtures")
local SlimeRoster = require("../src/shared/SlimeRoster")
local Snapshot = require("../src/server/Snapshot")
local Spawner = require("../src/server/Spawner")
local TestRunner = require("./TestRunner")

local describe, it, expect = TestRunner.describe, TestRunner.it, TestRunner.expect
local T0 = ServerFixtures.T0
local BOSS = Config.BOSS

-- A world whose Slime Rain is far from `arriveAt`: the rain clock starts long before it.
local function world(players: number?): any
	local w = ServerFixtures.world()
	w.startedAt = T0 - Config.RAIN_FIRST_AT - Config.RAIN_DURATION - 600
	w.nextSpawnAt = math.huge -- no fountain drops: wild counts are the boss's own
	for userId = 1, players or 2 do
		ServerFixtures.join(w, userId, nil, 0)
	end
	w.nextBossAt = T0 + BOSS.WARNING_SECONDS
	return w
end

-- Runs the event to the fight phase; returns the boss id.
local function arrive(w: any): string
	BossEvent.step(w, T0)
	assert(w.boss and w.boss.fight.phase == "warning", "warning")
	BossEvent.step(w, T0 + BOSS.WARNING_SECONDS)
	local id = BossEvent.bossId(w)
	assert(id, "boss arrived")
	return id
end

local function wildCount(w: any): number
	local n = 0
	for _ in w.wild do
		n += 1
	end
	return n
end

-- Fills the meter with player `userId` (and `other` once per two hits); returns the time after.
local function fill(w: any, userId: number, other: number?): number
	local t = T0 + BOSS.WARNING_SECONDS
	local i = 0
	while w.boss.fight.phase == "fight" do
		i += 1
		BossEvent.hit(w, w.sessions[userId], t)
		if other and i % 2 == 0 then
			BossEvent.hit(w, w.sessions[other], t)
		end
		t += BOSS.HIT_GAP
		assert(i < 1000, "meter never filled")
	end
	return t
end

describe("BossEvent schedule", function()
	it("warns WARNING_SECONDS before the first arrival at FIRST_AT, then every INTERVAL", function()
		local w = ServerFixtures.world()
		w.startedAt = T0 - Config.RAIN_FIRST_AT - Config.RAIN_DURATION - 600
		w.nextBossAt = T0 + BOSS.FIRST_AT
		local s = ServerFixtures.join(w, 1)
		BossEvent.step(w, T0 + BOSS.FIRST_AT - BOSS.WARNING_SECONDS - 1)
		expect(w.boss).toBeNil()
		s.dirty = false
		BossEvent.step(w, T0 + BOSS.FIRST_AT - BOSS.WARNING_SECONDS)
		expect(w.boss.fight.phase).toBe("warning")
		expect(w.boss.fight.endsAt).toBe(T0 + BOSS.FIRST_AT)
		expect(w.nextBossAt).toBe(T0 + BOSS.FIRST_AT + BOSS.INTERVAL)
		expect(s.dirty).toBe(true)
		local heads = ServerFixtures.notifications(w, nil)
		expect(string.find(heads[#heads], "BOSS INCOMING", 1, true) ~= nil).toBe(true)
	end)
	it("a new world schedules the first boss FIRST_AT after start, and the first Slime Rain doesn't push it", function()
		local w = ServerFixtures.world()
		ServerFixtures.join(w, 1)
		expect(w.nextBossAt).toBe(T0 + BOSS.FIRST_AT)
		BossEvent.step(w, T0 + BOSS.FIRST_AT - BOSS.WARNING_SECONDS)
		expect(w.boss ~= nil).toBe(true)
	end)
	it("moves SKIP_DELAY later while Slime Rain runs or is due within RAIN_GAP", function()
		local w = ServerFixtures.world() -- rain first at RAIN_FIRST_AT after T0
		ServerFixtures.join(w, 1)
		w.nextBossAt = T0 + Config.RAIN_FIRST_AT + 60 -- arrives a minute into the rain
		BossEvent.step(w, w.nextBossAt - BOSS.WARNING_SECONDS)
		expect(w.boss).toBeNil()
		expect(w.nextBossAt).toBe(T0 + Config.RAIN_FIRST_AT + 60 + BOSS.SKIP_DELAY)
		local due = ServerFixtures.world()
		ServerFixtures.join(due, 1)
		due.nextBossAt = T0 + Config.RAIN_FIRST_AT - BOSS.RAIN_GAP + 1 -- rain due right after it
		BossEvent.step(due, due.nextBossAt - BOSS.WARNING_SECONDS)
		expect(due.boss).toBeNil()
		local clear = ServerFixtures.world()
		ServerFixtures.join(clear, 1)
		clear.nextBossAt = T0 + Config.RAIN_FIRST_AT - BOSS.RAIN_GAP - 1
		BossEvent.step(clear, clear.nextBossAt - BOSS.WARNING_SECONDS)
		expect(clear.boss ~= nil).toBe(true)
	end)
end)

describe("BossEvent rotation", function()
	it("brings all six bosses in one lap on a Starlight fountain, then starts over", function()
		local out = {}
		for i = 1, 11 do
			table.insert(out, BossEvent.speciesFor(i, BOSS.SECRET_FOUNTAIN_TIER))
		end
		expect(table.concat(out, ",")).toBe(
			"goozilla,queen_jelly,klawdius,pumpking,mecha_goo,goozilla,queen_jelly,klawdius,pumpking,goomancer,goozilla"
		)
		local seen = {}
		for _, species in BOSS.ROTATION do
			seen[species] = true
		end
		for _, entry in SlimeRoster.ofKind("boss") do
			expect(`{entry.id}: {seen[entry.id] == true}`).toBe(`{entry.id}: true`)
		end
	end)
	it("gives every Secret slot to SECRET_FALLBACK below Starlight", function()
		expect(BossEvent.speciesFor(5, BOSS.SECRET_FOUNTAIN_TIER - 1)).toBe(BOSS.SECRET_FALLBACK)
		expect(BossEvent.speciesFor(10, BOSS.SECRET_FOUNTAIN_TIER - 1)).toBe(BOSS.SECRET_FALLBACK)
		expect(BossEvent.speciesFor(4, BOSS.SECRET_FOUNTAIN_TIER - 1)).toBe("pumpking")
	end)
	it("each event takes the next slot", function()
		local w = world()
		w.bossIndex = 2
		BossEvent.step(w, T0)
		expect(w.boss.fight.species).toBe("queen_jelly")
		expect(w.bossIndex).toBe(3)
	end)
end)

describe("BossEvent fight", function()
	it("the boss arrives as a free MAX_SIZE boss slime outside the wild cap, at BOSS.SCALE, no prompt", function()
		local w = world()
		local id = arrive(w)
		local boss = w.wild[id]
		expect(boss.boss).toBe(true)
		expect(boss.price).toBe(0)
		expect(boss.slime.species).toBe("goozilla")
		expect(boss.slime.tier).toBe(6)
		expect(boss.slime.size).toBe(Config.MAX_SIZE)
		expect(Spawner.wildCount(w)).toBe(0)
		local entry = Scene.describe(w, T0 + BOSS.WARNING_SECONDS)[id]
		expect(entry.boss).toBe(true)
		expect(entry.bossScale).toBe(BOSS.SCALE)
		expect(entry.promptEnabled).toBe(false)
		expect(entry.despawnAt).toBeNil()
		expect((Carry.grab(w, 1, id, 1, T0 + BOSS.WARNING_SECONDS))).toBe(false)
	end)
	it("never drops wild slimes during the fight: filling the meter only speeds it up", function()
		local w = world()
		arrive(w)
		local before = wildCount(w)
		fill(w, 1)
		expect(wildCount(w) - before).toBe(0)
		expect(BossFight.stage(w.boss.fight)).toBe(math.ceil(1 / BOSS.STAGE_EVERY) - 1)
	end)
	it("the meter target scales with the players on the server", function()
		local solo, crowd = world(1), world(4)
		arrive(solo)
		arrive(crowd)
		local soloHits = 0
		local t = T0 + BOSS.WARNING_SECONDS
		while solo.boss.fight.phase == "fight" do
			BossEvent.hit(solo, solo.sessions[1], t)
			soloHits += 1
			t += BOSS.HIT_GAP
		end
		expect(soloHits).toBe(BOSS.POINTS_PER_PLAYER)
		t = T0 + BOSS.WARNING_SECONDS
		local crowdHits = 0
		while crowd.boss.fight.phase == "fight" do
			for userId = 1, 4 do
				BossEvent.hit(crowd, crowd.sessions[userId], t)
				crowdHits += 1
			end
			t += BOSS.HIT_GAP
		end
		expect(crowdHits).toBe(BOSS.POINTS_PER_PLAYER * 4)
	end)
	it("a fight that runs out lets the boss get away without dropping slimes", function()
		local w = world()
		local id = arrive(w)
		BossEvent.hit(w, w.sessions[1], T0 + BOSS.WARNING_SECONDS)
		local before = wildCount(w)
		BossEvent.step(w, T0 + BOSS.WARNING_SECONDS + BOSS.FIGHT_SECONDS)
		expect(w.wild[id]).toBeNil()
		expect(w.boss.fight.phase).toBe("failed")
		expect(wildCount(w)).toBe(before - 1)
		local texts = ServerFixtures.notifications(w, nil)
		expect(texts[#texts]).toBe("The boss got away! Fill the meter faster next time.")
		BossEvent.step(w, T0 + BOSS.WARNING_SECONDS + BOSS.FIGHT_SECONDS + BOSS.LINGER_SECONDS)
		expect(w.boss).toBeNil()
	end)
end)

describe("BossEvent haul", function()
	it("shrinks to carry size; the top contributor grabs first, then anyone", function()
		local w = world()
		local id = arrive(w)
		expect(w.wild[id].move.kind).toBe("arrive") -- it drops onto the boss spot
		local t = fill(w, 1, 2)
		local down = w.wild[id].move
		expect(down.kind).toBe("down") -- and stands where the hit that filled the meter caught it
		expect(down.at).toBe(t - BOSS.HIT_GAP)
		local shrinking = Scene.describe(w, t)[id]
		expect(shrinking.bossScale).toBe(BOSS.SCALE)
		expect(shrinking.promptEnabled).toBe(false)
		t = down.at + BOSS.SHRINK_SECONDS
		local entry = Scene.describe(w, t)[id]
		expect(entry.bossScale).toBeNil()
		expect(entry.promptEnabled).toBe(true)
		local ok, reason = Carry.grab(w, 2, id, 1, t)
		expect(ok).toBe(false)
		expect(reason).toBe("the top helper grabs first")
		expect((Carry.grab(w, 2, id, 1, t + BOSS.PRIORITY_SECONDS))).toBe(true)
		expect(w.boss.fight.carrierUserId).toBe(2)
		expect(Scene.describe(w, t + BOSS.PRIORITY_SECONDS)[id].promptEnabled).toBe(false)
	end)
	it("the carrier walks at the boss carry slow, Speed Coil or not", function()
		local w = world()
		local id = arrive(w)
		local t = fill(w, 1)
		local s = w.sessions[1]
		s.data.speedCoil = true
		expect((Carry.grab(w, 1, id, 1, t + BOSS.SHRINK_SECONDS))).toBe(true)
		expect(Carry.walkSpeed(s)).toBeCloseTo(Config.BASE_WALK_SPEED * (1 - BOSS.CARRY_SLOW), 1e-9)
		expect(Snapshot.build(w, s, t + 1).carrying.walkSpeed).toBeCloseTo(
			Config.BASE_WALK_SPEED * (1 - BOSS.CARRY_SLOW),
			1e-9
		)
	end)
	it("a slap drops it on the spot (no escape home) and anyone may grab it again", function()
		local w = world()
		local id = arrive(w)
		local t = fill(w, 1, 2)
		expect((Carry.grab(w, 1, id, 1, t + BOSS.SHRINK_SECONDS))).toBe(true)
		local deadline = w.wild[id].expiresAt
		local spot = { X = 5, Y = 0, Z = 5 }
		local slapper, carrier = w.sessions[2], w.sessions[1]
		expect((BossEvent.slapCarrier(w, slapper, carrier, Config.SLAP_REACH + 1, t + 1, spot))).toBe(false)
		expect((BossEvent.slapCarrier(w, slapper, carrier, 3, t + 1, spot))).toBe(true)
		expect(w.carriedBy[id]).toBeNil()
		expect(carrier.carry).toBeNil()
		expect(w.wild[id].position).toBe(spot)
		expect(w.wild[id].expiresAt).toBe(deadline)
		expect(w.escaping[id]).toBeNil()
		local again, reason = BossEvent.slapCarrier(w, slapper, carrier, 3, t + 1.1, spot)
		expect(again).toBe(false)
		expect(reason).toBe("target isn't carrying the boss")
		expect((Carry.grab(w, 2, id, 1, t + BOSS.PRIORITY_SECONDS))).toBe(true)
	end)
	it("Request Drop also leaves it on the spot with the deadline unchanged", function()
		local w = world()
		local id = arrive(w)
		local t = fill(w, 1)
		Carry.grab(w, 1, id, 1, t + BOSS.SHRINK_SECONDS)
		local deadline = w.wild[id].expiresAt
		expect(Carry.release(w, 1, t + 3, "spot", "drop")).toBe(true)
		expect(w.wild[id].expiresAt).toBe(deadline)
		expect(w.boss.fight.carrierUserId).toBeNil()
	end)
	it("home with a full plot is a win: the boss joins nobody's slimes and earns no income", function()
		local w = world()
		local id = arrive(w)
		local t = fill(w, 1)
		local s = w.sessions[1]
		for i = 1, Config.PADS_MAX do
			PlayerData.addSlime(s.data, Fixtures.slime(`pad{i}`, 1))
		end
		expect(PlayerData.freePad(s.data)).toBeNil()
		local income = PlayerData.incomePerSecond(s.data)
		Carry.grab(w, 1, id, 1, t + BOSS.SHRINK_SECONDS)
		expect((Carry.deposit(w, 1, t + 5))).toBe(true)
		expect(s.data.boss.wins.goozilla).toBe(1)
		expect(PlayerData.findSlime(s.data, id)).toBeNil()
		expect(#s.data.slimes).toBe(Config.PADS_MAX)
		expect(w.wild[id]).toBeNil()
		expect(w.boss.fight.phase).toBe("won")
		expect(w.boss.fight.winnerUserId).toBe(1)
		expect(PlayerData.incomePerSecond(s.data)).toBe(income * (1 + BOSS.MVP_BONUS)) -- only the MVP boost, no boss income
		local texts = ServerFixtures.notifications(w, nil)
		expect(texts[#texts]).toBe("P1 brought Goozilla home!")
		expect(table.find(ServerFixtures.notifications(w, 1), "You brought Goozilla home!") ~= nil).toBe(true)
	end)
	it("only the carrier wins (badge, haul and SlimeDex); the top hitter gets the Boss MVP income boost", function()
		local w = world(3)
		local id = arrive(w)
		local t = fill(w, 1, 2) -- P1 hits twice as often as P2; P3 never hits
		local p1, p2, p3 = w.sessions[1], w.sessions[2], w.sessions[3]
		expect((Carry.grab(w, 3, id, 1, t + BOSS.PRIORITY_SECONDS))).toBe(true)
		expect((Carry.deposit(w, 3, t + BOSS.PRIORITY_SECONDS + 2))).toBe(true)
		expect(p1.data.boss.wins.goozilla).toBeNil() -- the top hitter didn't carry it
		expect(p2.data.boss.wins.goozilla).toBeNil()
		expect(p3.data.boss.wins.goozilla).toBe(1) -- the carrier wins, even with no hits
		expect(p3.data.boss.hauls).toBe(1)
		expect(p1.data.boss.hauls).toBe(0)
		expect(p1.data.boss.mvps).toBe(1)
		expect(p2.data.boss.mvps).toBe(0)
		expect(p1.data.found.goozilla).toBeNil() -- helpers get nothing for the boss itself
		expect(p2.data.found.goozilla).toBeNil()
		expect(p3.data.found.goozilla).toBe(true) -- the carrier held it
		expect(p1.data.boss.badges.BossBrawler ~= nil).toBe(true)
		expect(p1.data.boss.badges.BossGoozilla).toBeNil()
		-- The top hitter's MVP is a timed income boost, not a badge.
		local home = t + BOSS.PRIORITY_SECONDS + 2
		expect(p1.data.mvpBonus).toBe(BOSS.MVP_BONUS)
		expect(p1.mvpUntil).toBe(home + BOSS.MVP_SECONDS)
		expect(p2.data.mvpBonus).toBeNil()
		expect(p3.data.mvpBonus).toBeNil()
		expect(math.abs(Perks.bonusMultiplier(p1.data) / Perks.bonusMultiplier(p2.data) - (1 + BOSS.MVP_BONUS)) < 1e-9).toBe(
			true
		)
		expect(Snapshot.build(w, p1, home).mvpBoost).toEqual({
			bonus = BOSS.MVP_BONUS,
			endsAt = home + BOSS.MVP_SECONDS,
		})
		expect(Snapshot.build(w, p2, home).mvpBoost).toBeNil()
		expect(p2.data.boss.badges.BossGoozilla).toBeNil()
		expect(p3.data.boss.badges.BossHauler ~= nil).toBe(true)
		expect(p3.data.boss.badges.BossGoozilla ~= nil).toBe(true)
		local toasts = ServerFixtures.notifications(w, 1)
		expect(table.find(toasts, "Badge earned: Goozilla Tamer!")).toBeNil()
		expect(table.find(toasts, "Boss MVP! +50% income for 5 min") ~= nil).toBe(true)
		-- It runs out after MVP_SECONDS.
		BossCredit.expire(w, home + BOSS.MVP_SECONDS - 1)
		expect(p1.data.mvpBonus).toBe(BOSS.MVP_BONUS)
		BossCredit.expire(w, home + BOSS.MVP_SECONDS)
		expect(p1.data.mvpBonus).toBeNil()
		expect(p1.mvpUntil).toBeNil()
		local after = ServerFixtures.notifications(w, 1)
		expect(after[#after]).toBe("Your Boss MVP income boost ended")
		expect(table.find(ServerFixtures.notifications(w, 3), "Badge earned: Goozilla Tamer!") ~= nil).toBe(true)
		expect(table.find(ServerFixtures.notifications(w, 3), "Badge earned: Heavy Lifter!") ~= nil).toBe(true)
	end)
	it("the first counted hit earns Boss Brawler once, with a toast", function()
		local w = world()
		arrive(w)
		local t = T0 + BOSS.WARNING_SECONDS
		local s = w.sessions[1]
		expect((BossEvent.hit(w, s, t))).toBe(true)
		expect((BossEvent.hit(w, s, t))).toBe(false) -- too fast: not counted
		BossEvent.hit(w, s, t + BOSS.HIT_GAP)
		expect(s.data.boss.hits).toBe(2)
		expect(s.data.boss.badges.BossBrawler).toBe(math.floor(t))
		local toasts = ServerFixtures.notifications(w, 1)
		local n = 0
		for _, text in toasts do
			if text == "Badge earned: Boss Brawler!" then
				n += 1
			end
		end
		expect(n).toBe(1)
		expect(Snapshot.build(w, s, t + 1).bossBadges[1].key).toBe("BossBrawler")
		expect(Snapshot.build(w, s, t + 1).boss.badges).toBe(1)
	end)
	it("a haul that runs out lets the boss get away from the carrier's arms", function()
		local w = world()
		local id = arrive(w)
		local t = fill(w, 1)
		Carry.grab(w, 1, id, 1, t + BOSS.SHRINK_SECONDS)
		local before = wildCount(w)
		BossEvent.step(w, t + BOSS.HAUL_SECONDS)
		expect(w.sessions[1].carry).toBeNil()
		expect(w.wild[id]).toBeNil()
		expect(w.carriedBy[id]).toBeNil()
		expect(wildCount(w)).toBe(before - 1)
		expect(w.boss.fight.failReason).toBe("haul")
		local texts = ServerFixtures.notifications(w, nil)
		expect(texts[#texts]).toBe("Nobody brought the boss home! It got away.")
	end)
end)

describe("BossEvent State.boss", function()
	it("reports the phase, the meter and this player's share", function()
		local w = world()
		local id = arrive(w)
		local t = T0 + BOSS.WARNING_SECONDS
		for i = 0, 3 do
			BossEvent.hit(w, w.sessions[1], t + i * BOSS.HIT_GAP)
		end
		BossEvent.hit(w, w.sessions[2], t)
		local view = Snapshot.build(w, w.sessions[2], t + 1).boss
		expect(view.active).toBe(true)
		expect(view.phase).toBe("fight")
		expect(view.kind).toBe("goozilla")
		expect(view.name).toBe("Goozilla")
		expect(view.tier).toBe(6)
		expect(view.meter).toBeCloseTo(5 / (BOSS.POINTS_PER_PLAYER * 2), 1e-9)
		expect(view.endsAt).toBe(t + BOSS.FIGHT_SECONDS)
		expect(view.yourPoints).toBe(1)
		expect(view.yourShare).toBeCloseTo(0.25, 1e-9)
		expect(id ~= nil).toBe(true)
	end)
	it("names the head start, the carrier and the winner", function()
		local w = world()
		local id = arrive(w)
		local t = fill(w, 1)
		local view = BossEvent.view(w, w.sessions[2], t)
		expect(view.phase).toBe("haul")
		expect(view.priorityName).toBe("P1")
		expect(view.priorityUntil).toBeCloseTo(t - BOSS.HIT_GAP + BOSS.PRIORITY_SECONDS, 1e-6) -- from the last hit
		Carry.grab(w, 1, id, 1, t + BOSS.SHRINK_SECONDS)
		expect(BossEvent.view(w, w.sessions[2], t).carrierName).toBe("P1")
		Carry.deposit(w, 1, t + 2)
		local won = BossEvent.view(w, w.sessions[2], t + 2)
		expect(won.phase).toBe("won")
		expect(won.active).toBe(false)
		expect(won.winnerName).toBe("P1")
		expect(BossEvent.view(w, w.sessions[1], t + 2).badges).toBe(3) -- Brawler, Goozilla Tamer, Heavy Lifter (MVP is a boost)
	end)
	it("every phase change pushes State to every player", function()
		local w = world()
		BossEvent.step(w, T0)
		for _, s in w.sessions do
			s.dirty = false
		end
		BossEvent.step(w, T0 + BOSS.WARNING_SECONDS)
		for _, s in w.sessions do
			expect(s.dirty).toBe(true)
		end
	end)
end)
