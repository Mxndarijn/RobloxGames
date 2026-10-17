--!strict
-- FEATURES.PvP client adapter (src/ui/PvpClient): hotbar slots, cooldown / shield / safe-zone rules, commands,
-- lock state per rank, against the real Config.PVP_TOOLS and Shared.PvpRules. Pure: fixtures (PvpFixtures) supply
-- the state.pvp builder, the clock and send.
local Config = require("../../src/shared/Config")
local Constants = require("../../src/shared/Constants")
local FeatureOverride = require("../../src/shared/FeatureOverride")
local PvpClient = require("../../src/ui/PvpClient")
local PvpFixtures = require("./PvpFixtures")
local PvpRules = require("../../src/shared/PvpRules")
local Remotes = require("../../src/shared/Remotes")
local TestRunner = require("../TestRunner")

local describe, it, expect = TestRunner.describe, TestRunner.it, TestRunner.expect

local make = PvpFixtures.client

local function ids(slots: { PvpClient.Slot }): string
	local out = {}
	for _, s in slots do
		table.insert(out, s.id)
	end
	return table.concat(out, ",")
end

describe("PvP flag", function()
	it("is off by default, a Studio-previewable flag, and the adapter reports it", function()
		expect(Config.FEATURES.PvP).toBe(false)
		expect(table.find(FeatureOverride.FLAGS, "PvP") ~= nil).toBe(true)
		expect(PvpClient.new({}).enabled()).toBe(false)
		expect(PvpClient.new({ flag = true }).enabled()).toBe(true)
	end)
end)

describe("PvpClient catalog (Config.PVP_TOOLS)", function()
	it("is exactly Config.PVP_TOOLS in ladder order, with the 19 ids, lines and rank gates", function()
		local lines: { [string]: number } = {}
		local catalog = PvpClient.catalog()
		expect(#catalog).toBe(#Config.PVP_TOOLS)
		expect(#catalog).toBe(19)
		for _, t in catalog do
			lines[t.line] = (lines[t.line] or 0) + 1
			expect(t.cooldown > 0).toBe(true)
			expect(t.kind).toBe(if t.line == "Fun" then "fun" else "tool")
			expect(PvpRules.tool(t.id) == (t :: any)).toBe(true)
		end
		expect(lines.Knockback).toBe(5)
		expect(lines.Trap).toBe(3)
		expect(lines.Blaster).toBe(3)
		expect(lines.Fun).toBe(8)
		local gates: { [number]: boolean } = {}
		for _, tier in Config.REBIRTH_TIERS do
			gates[tier.rebirths] = true
		end
		for _, t in catalog do
			expect(`{t.id}: {gates[t.rebirths] == true}`).toBe(`{t.id}: true`)
		end
		local c = PvpClient.new({})
		expect(#c.catalog()).toBe(19)
		expect(c.tool("KnockGlove1") ~= nil and c.tool("Nope") == nil).toBe(true)
	end)
	it("effect text reads main's Config names: Blaster slow (a fraction) and Trap traps", function()
		local byId: { [string]: any } = {}
		for _, t in PvpClient.catalog() do
			byId[t.id] = t
			expect((t :: any).slowPercent).toBeNil()
			expect((t :: any).count).toBeNil()
			expect((t :: any).rearm).toBeNil()
			expect((t :: any).damage).toBeNil()
		end
		expect(PvpClient.effectSlowPercent(byId.GooBlaster1)).toBe(30)
		expect(PvpClient.effectSlowPercent(byId.GooBlaster3)).toBe(50)
		expect(PvpClient.effectSlowPercent(byId.KnockGlove1)).toBeNil()
		expect(PvpClient.effectCount(byId.GooTrap2)).toBe(2)
		expect(PvpClient.effectCount(byId.KnockGlove1)).toBeNil()
		expect(byId.GooTrap2.cooldown).toBe(25) -- a trap's cooldown is its rearm
	end)
	it("BASE_SLAP is display-only: free rank 0 of Knockback, not in the catalog, never a hotbar slot", function()
		local b = PvpClient.BASE_SLAP
		expect(b.name).toBe("Base slap")
		expect(b.line).toBe("Knockback")
		expect(b.rebirths).toBe(0)
		expect(b.free).toBe(true)
		for _, t in PvpClient.catalog() do
			expect(t.id ~= b.id).toBe(true)
		end
		local c = make(nil, 20)
		expect(c.tool(b.id)).toBeNil()
		for _, slot in c.hotbarSlots() do
			expect(slot.id ~= b.id).toBe(true)
		end
		local d = PvpClient.new({})
		d.applyState({ pvp = { owned = { [b.id] = true }, best = { Knockback = b.id }, equipped = b.id } })
		expect(#d.hotbarSlots()).toBe(0)
	end)
	it("listens on Constants.PVP_EVENT and sends the §26.1 action names", function()
		expect(PvpClient.EVENT_NAME).toBe(Constants.PVP_EVENT)
		expect(PvpClient.EQUIP_ACTION).toBe("EquipPvpItem")
		expect(PvpClient.USE_ACTION).toBe("UsePvpItem")
		expect(Remotes.ACTIONS[PvpClient.EQUIP_ACTION] ~= nil).toBe(true)
		expect(Remotes.ACTIONS[PvpClient.USE_ACTION] ~= nil).toBe(true)
	end)
end)

describe("PvpClient state and hotbar", function()
	it("state.pvp nil (flag off server-side) = empty PvP data", function()
		local c = make(nil, 20)
		c.applyState({})
		expect(c.rank()).toBe(0)
		expect(c.owns("KnockGlove1")).toBe(false)
		expect(c.best("Knockback")).toBeNil()
		expect(c.equipped()).toBeNil()
		expect(#c.hotbarSlots()).toBe(0)
		expect(c.safeZone()).toBeNil()
		expect(c.shield()).toBe(false)
		local fraction, left = c.cooldown("KnockGlove1")
		expect(fraction + left).toBe(0)
		c.applyState(nil)
		expect(#c.hotbarSlots()).toBe(0)
	end)

	it(
		"orders best Knockback, Trap, Blaster, then owned fun items by gate; a higher tier supersedes the lower",
		function()
			local c = make(nil, 30)
			expect(c.rank()).toBe(30)
			expect(c.best("Knockback")).toBe("KnockGlove5")
			expect(ids(c.hotbarSlots())).toBe(
				"KnockGlove5,GooTrap3,GooBlaster3,FunConfetti,FunBalloon,FunBubbles,FunBouncePad,FunSqueaky,FunHatLauncher,FunDanceBomb,FunFireworks"
			)
			local slots = c.hotbarSlots()
			expect(#slots).toBe(11)
			expect(slots[1].keybind).toBe("1")
			expect(slots[9].keybind).toBe("9")
			expect(slots[10].keybind).toBeNil()
			expect(slots[11].keybind).toBeNil()
			expect(slots[1].name).toBe("Royal Glove")
			expect(slots[1].line).toBe("Knockback")
			expect(slots[1].tier).toBe(5)
		end
	)

	it("rank 0 has only the Confetti Popper; rank 1 adds the Bonk Glove and the Balloon", function()
		expect(ids(make(nil, 0).hotbarSlots())).toBe("FunConfetti")
		expect(ids(make(nil, 1).hotbarSlots())).toBe("KnockGlove1,FunConfetti,FunBalloon")
		expect(ids(make(nil, 4).hotbarSlots())).toBe("KnockGlove1,GooTrap1,FunConfetti,FunBalloon,FunBubbles")
	end)

	it(
		"takes the snapshot's `best` as is: no best entry, or one that is not in the catalog / the line, is nil",
		function()
			local c = make()
			c.applyState({
				pvp = { owned = { KnockGlove1 = true, KnockGlove2 = true }, best = { Knockback = "KnockGlove1" } },
			})
			expect(c.best("Knockback")).toBe("KnockGlove1")
			c.applyState({ pvp = { owned = { KnockGlove1 = true, KnockGlove2 = true } } })
			expect(c.best("Knockback")).toBeNil()
			c.applyState({ pvp = { owned = { GooTrap2 = true }, best = { Trap = "Nope", Blaster = "GooTrap2" } } })
			expect(c.best("Trap")).toBeNil()
			expect(c.best("Blaster")).toBeNil() -- wrong line
			expect(ids(c.hotbarSlots())).toBe("")
			expect(c.owns("Nope")).toBe(false)
		end
	)

	it("equipped follows the snapshot only; the client never equips locally", function()
		local c, log = make(nil, 6)
		expect(c.equipped()).toBe("KnockGlove2")
		c.equip("FunBalloon")
		expect(c.equipped()).toBe("KnockGlove2")
		expect(#log.calls).toBe(1)
		local state = { pvp = PvpFixtures.pvp(6) }
		state.pvp.equipped = "FunBalloon"
		c.applyState(state)
		expect(c.equipped()).toBe("FunBalloon")
	end)

	it("fires `changed` on state, events and the attribute; disconnect stops it", function()
		local c = make()
		local n = 0
		local off = c.onChanged(function()
			n += 1
		end)
		c.applyState({ pvp = PvpFixtures.pvp(3) })
		c.applyEvent({ kind = "Shield", endsAt = 200 })
		c.applyEvent({ kind = "SafeZone", zone = "Spawn", inside = true })
		c.applyEvent({ kind = "Cooldown", itemId = "KnockGlove1", startedAt = 100, duration = 1 })
		c.setShieldAttribute(300)
		expect(n).toBe(5)
		off()
		c.applyState({})
		expect(n).toBe(5)
	end)

	it("forwards Effect / TrapPlaced / TrapCleared to onEffect only, and ignores unknown kinds", function()
		local c = make()
		local seen: { string } = {}
		local changed = 0
		c.onChanged(function()
			changed += 1
		end)
		c.onEffect(function(ev: any)
			table.insert(seen, ev.kind)
		end)
		c.applyEvent({ kind = "Effect", effect = "Freeze" })
		c.applyEvent({ kind = "TrapPlaced", trapId = "t1" })
		c.applyEvent({ kind = "TrapCleared", trapId = "t1" })
		c.applyEvent({ kind = "Nonsense" })
		c.applyEvent("not a table")
		expect(table.concat(seen, ",")).toBe("Effect,TrapPlaced,TrapCleared")
		expect(changed).toBe(0)
	end)
end)

describe("PvpClient commands", function()
	it("equip sends EquipPvpItem with the item id, and nil to unequip", function()
		local c, log = make(nil, 6)
		expect(c.equip("GooTrap2")).toBe(true)
		expect(log.calls[1].n).toBe(2)
		expect(log.calls[1][1]).toBe("EquipPvpItem")
		expect(log.calls[1][2]).toBe("GooTrap2")
		c.equip(nil)
		expect(log.calls[2].n).toBe(2)
		expect(log.calls[2][1]).toBe("EquipPvpItem")
		expect(log.calls[2][2]).toBeNil()
	end)

	it("use sends UsePvpItem with item, target and aim", function()
		local c, log = make(nil, 6)
		local aim = { X = 1, Y = 2, Z = 3 }
		expect(c.use("KnockGlove2", 4242, nil)).toBe(true)
		expect(c.use("GooBlaster1", nil, aim)).toBe(true)
		expect(c.use("FunConfetti")).toBe(true)
		expect(log.calls[1][1]).toBe("UsePvpItem")
		expect(log.calls[1][2]).toBe("KnockGlove2")
		expect(log.calls[1][3]).toBe(4242)
		expect(log.calls[1][4]).toBeNil()
		expect(log.calls[2][3]).toBeNil()
		expect(log.calls[2][4]).toBe(aim)
		expect(log.calls[3][2]).toBe("FunConfetti")
	end)

	it("a refused use returns false, reason and starts no local cooldown", function()
		local c, log = make({ false, "Too far away" }, 6)
		local ok, reason = c.use("KnockGlove2", 7)
		expect(ok).toBe(false)
		expect(reason).toBe("Too far away")
		expect(#log.calls).toBe(1)
		local fraction, left = c.cooldown("KnockGlove2")
		expect(fraction + left).toBe(0)
		local ok2, reason2 = make({ false }, 6).equip("KnockGlove1")
		expect(ok2).toBe(false)
		expect(reason2).toBe("refused")
	end)

	it("an accepted use does not start a cooldown either: only the server does", function()
		local c = make({ true }, 6)
		expect(c.use("KnockGlove2", 7)).toBe(true)
		local fraction, left = c.cooldown("KnockGlove2")
		expect(fraction + left).toBe(0)
	end)

	it("without a send hook every command is refused", function()
		local c = PvpClient.new({})
		local ok, reason = c.use("KnockGlove1")
		expect(ok).toBe(false)
		expect(reason).toBe("offline")
	end)

	it("activate equips a slot, and uses it (no target) when it is already equipped", function()
		local c, log = make(nil, 6)
		c.activate("GooTrap2") -- equipped is KnockGlove2
		expect(log.calls[1][1]).toBe("EquipPvpItem")
		c.activate("KnockGlove2")
		expect(log.calls[2][1]).toBe("UsePvpItem")
		expect(log.calls[2].n).toBe(4)
		expect(log.calls[2][3]).toBeNil()
	end)

	it("number keys equip that slot, unequip the equipped one and refuse empty slots and keys past 9", function()
		local c, log = make(nil, 30)
		expect(c.pressKey(2)).toBe(true) -- GooTrap3
		expect(log.calls[1][2]).toBe("GooTrap3")
		expect(c.pressKey(1)).toBe(true) -- KnockGlove5 is the equipped one: unequip
		expect(log.calls[2].n).toBe(2)
		expect(log.calls[2][2]).toBeNil()
		expect(c.pressKey(10)).toBe(false) -- slot 10 exists but has no key
		expect(c.pressKey(0)).toBe(false)
		expect(#log.calls).toBe(2)
		local empty, log2 = make(nil, 0)
		expect(empty.pressKey(3)).toBe(false)
		expect(#log2.calls).toBe(0)
	end)
end)

describe("PvpClient cooldowns", function()
	it("falls back to state.pvp.cooldowns over the catalog cooldown", function()
		local c, _, clock = make(nil, 12)
		local state = { pvp = PvpFixtures.pvp(12) }
		state.pvp.cooldowns = { GooBlaster2 = 105.5, KnockGlove4 = 100.75 }
		c.applyState(state)
		local fraction, left = c.cooldown("GooBlaster2") -- 11 s cooldown
		expect(left).toBe(5.5)
		expect(fraction).toBe(0.5)
		local f2, l2 = c.cooldown("KnockGlove4") -- 1.5 s
		expect(l2).toBe(0.75)
		expect(f2).toBe(0.5)
		clock.t = 102
		local f3, l3 = c.cooldown("KnockGlove4")
		expect(f3 + l3).toBe(0)
		expect(select(2, c.cooldown("GooBlaster2"))).toBe(3.5)
	end)

	it("a Cooldown event starts the ring, over its own duration, replacing an earlier snapshot value", function()
		local c, _, clock = make(nil, 12)
		local state = { pvp = PvpFixtures.pvp(12) }
		state.pvp.cooldowns = { GooBlaster2 = 200 }
		c.applyState(state)
		c.applyEvent({ kind = "Cooldown", itemId = "GooBlaster2", startedAt = 100, duration = 8 })
		local fraction, left = c.cooldown("GooBlaster2")
		expect(left).toBe(8)
		expect(fraction).toBe(1)
		clock.t = 104
		fraction, left = c.cooldown("GooBlaster2")
		expect(left).toBe(4)
		expect(fraction).toBe(0.5)
		clock.t = 108
		fraction, left = c.cooldown("GooBlaster2")
		expect(fraction + left).toBe(0)
		c.applyEvent({ kind = "Cooldown", itemId = "GooBlaster2", startedAt = 108, duration = 4 })
		expect(select(2, c.cooldown("GooBlaster2"))).toBe(4)
	end)

	it("a snapshot that lists the id resyncs the event's end (shorter or longer), keeping the ring length", function()
		local c, _, clock = make(nil, 12)
		c.applyEvent({ kind = "Cooldown", itemId = "GooBlaster2", startedAt = 100, duration = 8 })
		-- The state says it ends at 104: a stale event cannot keep the ring alive past that.
		local state = { pvp = PvpFixtures.pvp(12) }
		state.pvp.cooldowns = { GooBlaster2 = 104 }
		c.applyState(state)
		local fraction, left = c.cooldown("GooBlaster2")
		expect(left).toBe(4)
		expect(fraction).toBe(0.5) -- still over the event's 8 s
		clock.t = 104
		fraction, left = c.cooldown("GooBlaster2")
		expect(fraction + left).toBe(0)
		-- Longer: the state extends it.
		state.pvp.cooldowns = { GooBlaster2 = 110 }
		c.applyState(state)
		expect(select(2, c.cooldown("GooBlaster2"))).toBe(6)
		-- And the next event is the newest word again.
		c.applyEvent({ kind = "Cooldown", itemId = "GooBlaster2", startedAt = 104, duration = 2 })
		expect(select(2, c.cooldown("GooBlaster2"))).toBe(2)
	end)

	it("a snapshot that omits the id drops an old event, but not one started within the grace window", function()
		local c, _, clock = make(nil, 12)
		c.applyEvent({ kind = "Cooldown", itemId = "GooBlaster2", startedAt = 100, duration = 11 })
		c.applyEvent({ kind = "Cooldown", itemId = "GooTrap1", startedAt = 100, duration = 30 })
		clock.t = 100.5 -- the snapshot may predate both events
		c.applyState({ pvp = PvpFixtures.pvp(12) })
		expect(select(2, c.cooldown("GooBlaster2"))).toBe(10.5)
		expect(select(2, c.cooldown("GooTrap1"))).toBe(29.5)
		clock.t = 103 -- a later snapshot without them: the state says they ended
		c.applyState({ pvp = PvpFixtures.pvp(12) })
		local f, l = c.cooldown("GooBlaster2")
		expect(f + l).toBe(0)
		f, l = c.cooldown("GooTrap1")
		expect(f + l).toBe(0)
		-- An id never seen in an event just follows the state.
		local state = { pvp = PvpFixtures.pvp(12) }
		state.pvp.cooldowns = { KnockGlove4 = 104 }
		c.applyState(state)
		expect(select(2, c.cooldown("KnockGlove4"))).toBe(1)
	end)

	it("clamps: never above 1, below 0 or NaN, whatever the server sends", function()
		local c, _, clock = make(nil, 12)
		local state = { pvp = PvpFixtures.pvp(12) }
		state.pvp.cooldowns =
			{ KnockGlove4 = 500, GooTrap2 = 0 / 0, GooBlaster2 = -10, FunBalloon = math.huge, FunBubbles = "x" }
		c.applyState(state)
		local fraction, left = c.cooldown("KnockGlove4")
		expect(fraction).toBe(1) -- 400 s left on a 1.5 s cooldown
		expect(left).toBe(400)
		for _, id in { "GooTrap2", "GooBlaster2", "FunBalloon", "FunBubbles", "Unknown", "GooTrap1" } do
			local f, l = c.cooldown(id)
			expect(`{id}: {f == 0 and l == 0}`).toBe(`{id}: true`)
		end
		-- Bad events change nothing.
		c.applyEvent({ kind = "Cooldown", itemId = "GooTrap1", startedAt = 0 / 0, duration = 5 })
		c.applyEvent({ kind = "Cooldown", itemId = "GooTrap1", startedAt = 100, duration = math.huge })
		c.applyEvent({ kind = "Cooldown", itemId = 7, startedAt = 100, duration = 5 })
		expect(select(2, c.cooldown("GooTrap1"))).toBe(0)
		-- A zero duration event is ready at once; a NaN clock reads as ready.
		c.applyEvent({ kind = "Cooldown", itemId = "GooTrap1", startedAt = 100, duration = 0 })
		expect(select(2, c.cooldown("GooTrap1"))).toBe(0)
		c.applyEvent({ kind = "Cooldown", itemId = "GooTrap2", startedAt = 100, duration = 5 })
		clock.t = 0 / 0
		local f, l = c.cooldown("GooTrap2")
		expect(f + l).toBe(0)
	end)

	it("an item the catalog does not know still counts its seconds, with no ring", function()
		local c = make()
		c.applyState({ pvp = { cooldowns = { Mystery = 110 } } })
		local fraction, left = c.cooldown("Mystery")
		expect(fraction).toBe(0)
		expect(left).toBe(10)
	end)
end)

describe("PvpClient shield", function()
	it("state.pvp.shieldUntil wins over the PvpShieldUntil attribute", function()
		local c = make()
		c.setShieldAttribute(500)
		c.applyState({ pvp = { shieldUntil = 130 } })
		local active, left = c.shield()
		expect(active).toBe(true)
		expect(left).toBe(30)
	end)

	it("falls back to the attribute without a state value, and clears with it", function()
		local c, _, clock = make()
		c.applyState({ pvp = {} })
		expect(c.shield()).toBe(false)
		c.setShieldAttribute(160)
		local active, left = c.shield()
		expect(active).toBe(true)
		expect(left).toBe(60)
		clock.t = 160
		expect(c.shield()).toBe(false) -- over at the second
		c.setShieldAttribute(nil)
		clock.t = 100
		expect(c.shield()).toBe(false)
		c.setShieldAttribute(0 / 0)
		expect(c.shield()).toBe(false)
	end)

	it(
		"a Shield event updates it (endsAt nil = over, even with the attribute still set) until the next snapshot",
		function()
			local c, _, clock = make()
			c.setShieldAttribute(400)
			c.applyEvent({ kind = "Shield", endsAt = 150 })
			local _, left = c.shield()
			expect(left).toBe(50)
			c.applyEvent({ kind = "Shield" })
			expect(c.shield()).toBe(false)
			c.applyState({ pvp = { shieldUntil = 120 } }) -- the snapshot is authoritative again
			expect(select(2, c.shield())).toBe(20)
			clock.t = 121
			expect(c.shield()).toBe(false)
		end
	)
end)

describe("PvpClient safe zone", function()
	it("comes from the server only: the snapshot field or a SafeZone event", function()
		local c = make()
		expect(c.safeZone()).toBeNil()
		c.applyState({ pvp = { safeZone = "Spawn" } })
		expect(c.safeZone()).toBe("Spawn")
		c.applyEvent({ kind = "SafeZone", zone = "Shop", inside = true })
		expect(c.safeZone()).toBe("Shop")
		c.applyEvent({ kind = "SafeZone", zone = "Spawn", inside = false }) -- not the zone we are in
		expect(c.safeZone()).toBe("Shop")
		c.applyEvent({ kind = "SafeZone", zone = "Shop", inside = false })
		expect(c.safeZone()).toBeNil()
		c.applyState({ pvp = { safeZone = "Fountain" } })
		expect(c.safeZone()).toBe("Fountain")
		c.applyEvent({ kind = "SafeZone", zone = "Shop", inside = true })
		c.applyState({ pvp = { safeZone = "Spawn" } }) -- Sync: the snapshot resyncs
		expect(c.safeZone()).toBe("Spawn")
		c.applyState({ pvp = { safeZone = "" } })
		expect(c.safeZone()).toBeNil()
		c.applyState({})
		expect(c.safeZone()).toBeNil()
	end)
end)

describe("PvpClient lock state per rank", function()
	local function idsOf(list: { PvpClient.Tool }): string
		local out = {}
		for _, t in list do
			table.insert(out, t.id)
		end
		return table.concat(out, ",")
	end

	it(
		"unlockedAt(rank) is exactly the PVP_TOOLS with rebirths <= rank and agrees with PvpRules.isUnlocked, at every REBIRTH_TIERS threshold",
		function()
			local previous = 0
			for _, tier in Config.REBIRTH_TIERS do
				local data: PvpRules.Data = { cash = 0, rebirths = tier.rebirths }
				local unlocked = PvpClient.unlockedAt(tier.rebirths)
				local expected = 0
				for _, t in Config.PVP_TOOLS do
					local should = t.rebirths <= tier.rebirths
					expect(`rank {tier.rebirths} {t.id}: {PvpClient.isUnlocked(t.id, tier.rebirths)}`).toBe(
						`rank {tier.rebirths} {t.id}: {should}`
					)
					expect(PvpRules.isUnlocked(data, t.id)).toBe(PvpClient.isUnlocked(t.id, tier.rebirths))
					if should then
						expected += 1
					end
				end
				expect(#unlocked).toBe(expected)
				expect(#unlocked >= previous).toBe(true) -- ranks only ever unlock more
				previous = #unlocked
			end
			expect(previous).toBe(19)
		end
	)

	it("matches the plan table at the key ranks", function()
		expect(idsOf(PvpClient.unlockedAt(0))).toBe("FunConfetti")
		expect(idsOf(PvpClient.unlockedAt(1))).toBe("KnockGlove1,FunConfetti,FunBalloon")
		expect(idsOf(PvpClient.unlockedAt(3))).toBe("KnockGlove1,GooTrap1,FunConfetti,FunBalloon,FunBubbles")
		expect(idsOf(PvpClient.unlockedAt(7))).toBe(
			"KnockGlove1,KnockGlove2,GooTrap1,GooTrap2,GooBlaster1,FunConfetti,FunBalloon,FunBubbles,FunBouncePad,FunSqueaky,FunHatLauncher"
		)
		expect(PvpClient.isUnlocked("GooTrap1", 2)).toBe(false)
		expect(PvpClient.isUnlocked("GooTrap1", 3)).toBe(true)
		expect(PvpClient.isUnlocked("KnockGlove5", 19)).toBe(false)
		expect(PvpClient.isUnlocked("KnockGlove5", 20)).toBe(true)
		expect(PvpClient.isUnlocked("Nope", 30)).toBe(false)
		expect(PvpClient.isUnlocked("KnockGlove1", 0 / 0)).toBe(false)
		expect(#PvpClient.unlockedAt(-1)).toBe(0)
		expect(#PvpClient.unlockedAt(0 / 0)).toBe(0)
	end)

	it("the fixture's state.pvp owns the unlocked items with the best tools, as PvpService.view builds it", function()
		local pvp = PvpFixtures.pvp(12)
		expect(pvp.rank).toBe(12)
		expect(pvp.best.Knockback).toBe("KnockGlove4")
		expect(pvp.best.Trap).toBe("GooTrap3")
		expect(pvp.best.Blaster).toBe("GooBlaster2")
		expect(pvp.equipped).toBe("KnockGlove4")
		expect(pvp.owned.FunSqueaky).toBe(true)
		expect(pvp.owned.FunFireworks).toBe(true)
		expect(pvp.owned.GooBlaster3).toBeNil() -- gate 20
	end)
end)
