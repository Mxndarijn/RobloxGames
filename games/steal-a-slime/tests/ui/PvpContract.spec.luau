--!strict
-- The PvP client against the REAL server code (CONTRACT.md §26.1): every PvpEvent kind and State.pvp field the
-- adapter reads exists in main's Types / PvpService / Remotes, and the real PvpService's events and State.pvp, fed
-- straight into the adapter, give the answers the HUD shows. Pure: PvpService runs under Lune with its test sink.
local Config = require("../../src/shared/Config")
local Constants = require("../../src/shared/Constants")
local PvpClient = require("../../src/ui/PvpClient")
local PvpRules = require("../../src/shared/PvpRules")
local PvpService = require("../../src/server/PvpService")
local Remotes = require("../../src/shared/Remotes")
local ServerFixtures = require("../ServerFixtures")
local TestRunner = require("../TestRunner")
local fs = require("@lune/fs")

local describe, it, expect = TestRunner.describe, TestRunner.it, TestRunner.expect
local T0 = ServerFixtures.T0
local FAR = { X = 200, Y = 3, Z = -200 } -- clear of every safe zone
local FOUNTAIN = { X = 1, Y = 3, Z = 1 }

local env = {
	positionOf = function(): any?
		return FAR
	end,
	onOwnPlot = function(): boolean
		return true
	end,
}

-- A real world with player 1 (rank `rebirths`, rich) on a PvpService that records every event it sends.
local function setup(rebirths: number): (any, any, { { target: number?, payload: any } })
	local events: { { target: number?, payload: any } } = {}
	PvpService.setSink(function(target, payload)
		table.insert(events, { target = target, payload = payload })
	end, function()
		return T0
	end)
	local world = ServerFixtures.world()
	local a = ServerFixtures.join(world, 1, nil, 1e12)
	local b = ServerFixtures.join(world, 2, nil, 1e12) -- a target
	a.data.rebirths, b.data.rebirths = rebirths, 5
	PvpService.join(a, T0, true)
	PvpService.join(b, T0, true)
	return world, a, events
end

local function done()
	PvpService.setSink(nil)
	PvpService.registerLine("Knockback", nil)
end

-- A client on a clock fixed at `clock.t`, fed with the events the server sent.
local function client(clock: { t: number }): any
	return PvpClient.new({
		now = function()
			return clock.t
		end,
		flag = true,
	})
end

-- The source from `startPattern` to the next `endPattern`.
local function body(source: string, startPattern: string, endPattern: string): string
	local from = string.find(source, startPattern, 1, true)
	assert(from, `{startPattern} not found`)
	local to = string.find(source, endPattern, from, true)
	assert(to, `{endPattern} not found`)
	return string.sub(source, from, to)
end

describe("PvP contract: names the adapter reads exist on the server side", function()
	it("every State.pvp field the adapter reads is in Types.PvpView and built by PvpService.view", function()
		local types = body(fs.readFile("src/shared/Types.luau"), "export type PvpView = {", "\n}\n")
		local service = fs.readFile("src/server/PvpService.luau")
		local view = body(service, "function PvpService.view(", "\nend\n")
		for _, field in { "rank", "owned", "best", "equipped", "cooldowns", "shieldUntil", "safeZone" } do
			expect(`Types.PvpView.{field}: {string.find(types, `\t{field}:`, 1, true) ~= nil}`).toBe(
				`Types.PvpView.{field}: true`
			)
			expect(`PvpService.view {field}: {string.find(view, `{field} = `, 1, true) ~= nil}`).toBe(
				`PvpService.view {field}: true`
			)
		end
		local clientSource = fs.readFile("src/ui/PvpClient.luau")
		for field in string.gmatch(clientSource, "pvp%.(%a+)") do
			expect(`adapter reads pvp.{field}: {string.find(types, `\t{field}:`, 1, true) ~= nil}`).toBe(
				`adapter reads pvp.{field}: true`
			)
		end
	end)

	it("every PvpEvent kind the adapter handles is sent by PvpService, with the fields it reads", function()
		local service = fs.readFile("src/server/PvpService.luau")
		for kind, fields in
			{
				Cooldown = { "itemId", "duration", "startedAt" },
				Shield = { "endsAt" },
				SafeZone = { "zone", "inside" },
				Effect = {},
				TrapPlaced = {},
				TrapCleared = {},
			} :: { [string]: { string } }
		do
			expect(`kind {kind}: {string.find(service, `"{kind}"`, 1, true) ~= nil}`).toBe(`kind {kind}: true`)
			for _, field in fields do
				expect(`{kind}.{field}: {string.find(service, `{field} = `, 1, true) ~= nil}`).toBe(
					`{kind}.{field}: true`
				)
			end
		end
		local clientSource = fs.readFile("src/ui/PvpClient.luau")
		for kind in string.gmatch(clientSource, 'kind == "(%a+)"') do
			expect(`adapter kind {kind}: {string.find(service, `"{kind}"`, 1, true) ~= nil}`).toBe(
				`adapter kind {kind}: true`
			)
		end
	end)

	it("the remote, the actions and the attributes are the ones the client uses", function()
		local def = Remotes.definition(Constants.PVP_EVENT)
		expect(def and def.class).toBe("RemoteEvent")
		expect(PvpClient.EVENT_NAME).toBe(Constants.PVP_EVENT)
		expect(Remotes.ACTIONS[PvpClient.EQUIP_ACTION].args).toEqual({ "string?" })
		expect(Remotes.ACTIONS[PvpClient.USE_ACTION].args).toEqual({ "string", "number?", "vector3?" })
		expect(Constants.PVP_SHIELD_ATTRIBUTE).toBe("PvpShieldUntil")
		expect(Constants.PVP_EQUIPPED_ATTRIBUTE).toBe("PvpEquipped")
	end)

	it("the adapter's effect names exist in Config.PVP_TOOLS (slow / traps), the §26.1 spellings do not", function()
		local slow, traps = false, false
		for _, tool in Config.PVP_TOOLS do
			slow = slow or PvpClient.effectSlowPercent(tool) ~= nil
			traps = traps or PvpClient.effectCount(tool) ~= nil
			expect((tool :: any).slowPercent).toBeNil()
			expect((tool :: any).count).toBeNil()
			expect((tool :: any).rearm).toBeNil()
		end
		expect(slow and traps).toBe(true)
	end)
end)

describe("PvP contract: real PvpService output through the adapter", function()
	it("State.pvp: rank, owned, best, equipped and the hotbar follow a real buy + equip", function()
		local world, a = setup(5)
		local clock = { t = T0 + 1 }
		local c = client(clock)
		c.applyState({ pvp = PvpService.view(a, T0) })
		expect(#c.hotbarSlots()).toBe(0)
		expect((PvpService.buy(world, a, "KnockGlove2", true))).toBe(true)
		expect((PvpService.buy(world, a, "FunConfetti", true))).toBe(true)
		expect((PvpService.equip(a, "KnockGlove2", true))).toBe(true)
		c.applyState({ pvp = PvpService.view(a, T0) })
		expect(c.rank()).toBe(5)
		expect(c.owns("KnockGlove2")).toBe(true)
		expect(c.owns("KnockGlove1")).toBe(true) -- a higher tier supersedes the lower ones
		expect(c.owns("GooTrap1")).toBe(false)
		expect(c.best("Knockback")).toBe("KnockGlove2")
		expect(c.equipped()).toBe("KnockGlove2")
		local slots = c.hotbarSlots()
		expect(#slots).toBe(2)
		expect(slots[1].id).toBe("KnockGlove2")
		expect(slots[2].id).toBe("FunConfetti")
		expect((PvpService.equip(a, nil, true))).toBe(true)
		c.applyState({ pvp = PvpService.view(a, T0) })
		expect(c.equipped()).toBeNil()
		done()
	end)

	it("a real use sends a Cooldown event the ring follows, and State.pvp.cooldowns resyncs it", function()
		local world, a, events = setup(5)
		expect((PvpService.buy(world, a, "KnockGlove2", true))).toBe(true)
		expect((PvpService.equip(a, "KnockGlove2", true))).toBe(true)
		PvpService.registerLine("Knockback", function()
			return true, nil
		end)
		local before = #events
		local ok = PvpService.use(world, a, "KnockGlove2", 2, nil, T0 + 1, true, env)
		expect(ok).toBe(true)
		local clock = { t = T0 + 1 }
		local c = client(clock)
		c.applyState({ pvp = PvpService.view(a, T0 + 1) })
		for i = before + 1, #events do
			expect(events[i].target).toBe(1)
			c.applyEvent(events[i].payload)
		end
		local duration = (PvpRules.tool("KnockGlove2") :: any).cooldown
		local fraction, left = c.cooldown("KnockGlove2")
		expect(left).toBe(duration)
		expect(fraction).toBe(1)
		clock.t = T0 + 1 + duration / 2
		fraction, left = c.cooldown("KnockGlove2")
		expect(fraction).toBe(0.5)
		-- A later snapshot carries cooldowns[id] = endsAt: same answer.
		c.applyState({ pvp = PvpService.view(a, T0 + 1 + duration / 2) })
		expect(select(2, c.cooldown("KnockGlove2"))).toBe(left)
		-- Once the server stops listing it, it is over.
		clock.t = T0 + 1 + duration + 2
		c.applyState({ pvp = PvpService.view(a, clock.t) })
		fraction, left = c.cooldown("KnockGlove2")
		expect(fraction + left).toBe(0)
		done()
	end)

	it("real SafeZone events and State.pvp.safeZone name the zone the way the chip shows it", function()
		local _, a, events = setup(5)
		local c = client({ t = T0 + 1 })
		PvpService.tick(a, FAR, T0 + 1)
		PvpService.tick(a, FOUNTAIN, T0 + 2)
		for _, e in events do
			c.applyEvent(e.payload)
		end
		expect(c.safeZone()).toBe("Fountain")
		c.applyState({ pvp = PvpService.view(a, T0 + 2) })
		expect(c.safeZone()).toBe("Fountain")
		local from = #events
		PvpService.tick(a, FAR, T0 + 3)
		expect(#events > from).toBe(true)
		for i = from + 1, #events do
			c.applyEvent(events[i].payload)
		end
		expect(c.safeZone()).toBeNil()
		c.applyState({ pvp = PvpService.view(a, T0 + 3) })
		expect(c.safeZone()).toBeNil()
		done()
	end)

	it("a new player's real Shield event and State.pvp.shieldUntil give the same chip; a rebirth ends it", function()
		local _, a, events = setup(0)
		local clock = { t = T0 + 1 }
		local c = client(clock)
		PvpService.tick(a, FAR, T0 + 1)
		local shieldEvents = 0
		for _, e in events do
			if e.payload.kind == "Shield" then
				c.applyEvent(e.payload)
				shieldEvents += 1
			end
		end
		expect(shieldEvents).toBe(1)
		local active, left = c.shield()
		expect(active).toBe(true)
		local view = PvpService.view(a, T0 + 1) :: any
		expect(view.shieldUntil ~= nil).toBe(true)
		expect(left).toBe(view.shieldUntil - clock.t)
		c.applyState({ pvp = view })
		expect(select(2, c.shield())).toBe(left)
		a.data.rebirths = 1
		view = PvpService.view(a, T0 + 2) :: any
		expect(view.shieldUntil).toBeNil()
		c.applyState({ pvp = view })
		expect(c.shield()).toBe(false)
		done()
	end)

	it("with the flag off the server sends no State.pvp and the adapter shows nothing", function()
		PvpService.setSink(nil)
		local world = ServerFixtures.world()
		local s = ServerFixtures.join(world, 1, nil, 1e12)
		PvpService.join(s, T0, false)
		expect(PvpService.view(s, T0)).toBeNil()
		local c = client({ t = T0 })
		c.applyState({ pvp = PvpService.view(s, T0) })
		expect(#c.hotbarSlots()).toBe(0)
		expect(c.shield()).toBe(false)
		expect(c.safeZone()).toBeNil()
	end)
end)
