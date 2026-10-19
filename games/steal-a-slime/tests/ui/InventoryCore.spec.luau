--!strict
-- S3 inventory: what the hotbar / panel list (InventoryCore), the hotbar geometry (InventoryLayout) and the
-- gate-size fit of the hotbar zone. Pure: no Instances.
local Config = require("../../src/shared/Config")
local InventoryCore = require("../../src/ui/InventoryCore")
local InventoryLayout = require("../../src/ui/InventoryLayout")
local ItemIcons = require("../../src/ui/ItemIcons")
local Layout = require("../../src/ui/Layout")
local LayoutAssert = require("./LayoutAssert")
local Remotes = require("../../src/shared/Remotes")
local TestRunner = require("../TestRunner")

local describe, it, expect = TestRunner.describe, TestRunner.it, TestRunner.expect

local registry = InventoryCore.withTools(ItemIcons.build(Config))

local function input(overrides: { [string]: any }?): InventoryCore.Input
	local base: any = {
		tools = { { name = "Bat", equipped = false } },
		pvp = nil,
		config = Config,
		registry = registry,
		counts = nil,
		now = 100,
	}
	for k, v in overrides or {} do
		base[k] = v
	end
	return base
end

local function ids(entries: { InventoryCore.Entry }): { string }
	local out = {}
	for _, e in entries do
		table.insert(out, e.key)
	end
	return out
end

describe("InventoryCore.entries", function()
	it("lists the Bat first with its picture, even before the Tool exists", function()
		local entries = InventoryCore.entries(input({ tools = {} }))
		expect(#entries).toBe(1)
		expect(entries[1].key).toBe("tool:Bat")
		expect(entries[1].iconId).toBe("Pvp_Bat")
		expect(registry.get(entries[1].iconId) ~= nil).toBe(true)
		expect(entries[1].equipped).toBe(false)
	end)

	it("marks the held Tool selected and lists other Tools (Speed Coil) by name after the Bat", function()
		local entries = InventoryCore.entries(input({
			tools = {
				{ name = "SpeedCoil", equipped = false },
				{ name = "Bat", equipped = true },
				{ name = "Zeta", equipped = false },
			},
		}))
		expect(table.concat(ids(entries), ",")).toBe("tool:Bat,tool:SpeedCoil,tool:Zeta")
		expect(entries[1].equipped).toBe(true)
		expect(entries[2].iconId).toBe("SpeedCoil")
		expect(entries[2].name).toBe("Speed Coil")
		expect(entries[3].iconId).toBe("Unknown") -- a Tool without art gets the neutral tile, never an error
		expect(entries[3].name).toBe("Zeta")
	end)

	it("lists owned PvP items in catalog order, and only those", function()
		local owned = {}
		local want = {}
		for i, def in Config.PVP_TOOLS do
			if i % 3 == 0 then
				owned[def.id] = true
				table.insert(want, `pvp:{def.id}`)
			end
		end
		local entries = InventoryCore.entries(input({ pvp = { owned = owned, equipped = nil, cooldowns = {} } }))
		local got = ids(entries)
		table.remove(got, 1) -- the Bat
		expect(table.concat(got, ",")).toBe(table.concat(want, ","))
		for _, e in entries do
			expect(registry.get(e.iconId) ~= nil).toBe(true)
		end
	end)

	it("every Config.PVP_TOOLS item has a registry picture, so a new catalog row needs no UI change", function()
		for _, def in Config.PVP_TOOLS do
			local entries = InventoryCore.entries(input({ pvp = { owned = { [def.id] = true }, cooldowns = {} } }))
			expect(entries[2].iconId).toBe(`Pvp_{def.id}`)
			expect(registry.get(`Pvp_{def.id}`) ~= nil).toBe(true)
			expect(entries[2].name).toBe(def.name)
		end
	end)

	it("marks the equipped PvP item and its cooldown", function()
		local def = Config.PVP_TOOLS[1]
		local entries = InventoryCore.entries(input({
			pvp = { owned = { [def.id] = true }, equipped = def.id, cooldowns = { [def.id] = 104.2 } },
		}))
		expect(entries[2].equipped).toBe(true)
		expect(InventoryCore.cooldownText(entries[2], 100)).toBe("5")
		expect(InventoryCore.cooldownText(entries[2], 104.2)).toBe(nil)
		local ready = InventoryCore.entries(input({
			pvp = { owned = { [def.id] = true }, cooldowns = { [def.id] = 50 } },
		}))
		expect(ready[2].readyAt).toBe(nil)
	end)

	it("never lists permanent upgrades, locks or consumables (they are not held)", function()
		local entries = InventoryCore.entries(input({ pvp = { owned = {}, cooldowns = {} } }))
		expect(#entries).toBe(1)
		for _, e in entries do
			expect(string.find(e.key, "Upgrade", 1, true)).toBe(nil)
			expect(string.find(e.key, "Lock", 1, true)).toBe(nil)
		end
	end)

	it("a flag-off PvP (State.pvp nil) lists no PvP items", function()
		expect(#InventoryCore.entries(input({ pvp = nil }))).toBe(1)
	end)

	it("shows a stack count only when the server supplies one", function()
		local entries = InventoryCore.entries(input({ counts = { Bat = 3 } }))
		expect(entries[1].count).toBe(3)
		expect(InventoryCore.countText(3)).toBe("3")
		expect(InventoryCore.countText(250)).toBe("99+")
		expect(InventoryCore.countText(nil)).toBe(nil)
		expect(InventoryCore.countText(0)).toBe(nil)
		expect(InventoryCore.entries(input())[1].count).toBe(nil)
	end)

	it("a Tool listed twice (Backpack and character) is one slot", function()
		local entries = InventoryCore.entries(input({
			tools = { { name = "Bat", equipped = false }, { name = "Bat", equipped = true } },
		}))
		expect(#entries).toBe(1)
		expect(entries[1].equipped).toBe(true)
	end)
end)

describe("InventoryCore.select / byKey / signature", function()
	local def = Config.PVP_TOOLS[1]
	local function pvpEntry(equipped: boolean): InventoryCore.Entry
		return InventoryCore.entries(input({
			pvp = { owned = { [def.id] = true }, equipped = if equipped then def.id else nil, cooldowns = {} },
		}))[2]
	end

	it("a Tool toggles through the Humanoid, a PvP item through the existing EquipPvpItem action", function()
		local bat = InventoryCore.entries(input())[1]
		expect((InventoryCore.select(bat) :: any).kind).toBe("Tool")
		expect((InventoryCore.select(bat) :: any).equip).toBe(true)
		local held = InventoryCore.entries(input({ tools = { { name = "Bat", equipped = true } } }))[1]
		expect((InventoryCore.select(held) :: any).equip).toBe(false)

		local a: any = InventoryCore.select(pvpEntry(false))
		expect(a.kind).toBe("Request")
		expect(a.action).toBe("EquipPvpItem")
		expect(a.arg).toBe(def.id)
		local b: any = InventoryCore.select(pvpEntry(true))
		expect(b.action).toBe("EquipPvpItem")
		expect(b.arg).toBe(nil)
	end)

	it("EquipPvpItem is a real Remotes action taking an optional string", function()
		expect(Remotes.ACTIONS[InventoryCore.PVP_ACTION] ~= nil).toBe(true)
	end)

	it("number keys pick only slots the bar shows", function()
		local entries = InventoryCore.entries(input({ pvp = { owned = { [def.id] = true }, cooldowns = {} } }))
		expect(InventoryCore.byKey(entries, 2, 1) == entries[1]).toBe(true)
		expect(InventoryCore.byKey(entries, 2, 2) == entries[2]).toBe(true)
		expect(InventoryCore.byKey(entries, 1, 2)).toBe(nil) -- on the phone-narrow bar slot 2 is in the bag only
		expect(InventoryCore.byKey(entries, 2, 0)).toBe(nil)
		expect(InventoryCore.byKey(entries, 2, 10)).toBe(nil)
	end)

	it("the signature changes with selection, stack and cooldown, not with identical input", function()
		local a = InventoryCore.signature(InventoryCore.entries(input()))
		expect(InventoryCore.signature(InventoryCore.entries(input()))).toBe(a)
		local held =
			InventoryCore.signature(InventoryCore.entries(input({ tools = { { name = "Bat", equipped = true } } })))
		expect(held ~= a).toBe(true)
		expect(InventoryCore.signature(InventoryCore.entries(input({ counts = { Bat = 2 } }))) ~= a).toBe(true)
	end)
end)

describe("InventoryLayout geometry", function()
	local zone = { x = 200, y = 400, w = 800, h = 67 }
	it("centres the bar in its zone, bottom aligned, slots in a row and the bag last", function()
		local bar = InventoryLayout.bar(zone, 4, false, Layout.MIN_TOUCH_DESIGN)
		expect(bar.shown).toBe(4)
		expect(#bar.slots).toBe(4)
		expect(bar.rect.y + bar.rect.h).toBe(zone.y + zone.h)
		expect(math.abs((bar.rect.x + bar.rect.w / 2) - (zone.x + zone.w / 2)) <= 1).toBe(true)
		for i = 2, 4 do
			expect(bar.slots[i].x).toBe(bar.slots[i - 1].x + bar.slots[i - 1].w + InventoryLayout.GAP)
		end
		expect(bar.bag.x).toBe(bar.slots[4].x + bar.slots[4].w + InventoryLayout.GAP)
		expect(bar.bag.x + bar.bag.w + InventoryLayout.PAD).toBe(bar.rect.x + bar.rect.w)
	end)
	it("drops slots that do not fit (they stay in the bag panel), never below the bag cell", function()
		local narrow = { x = 12, y = 0, w = 200, h = 67 }
		local bar = InventoryLayout.bar(narrow, 9, true, Layout.MIN_TOUCH_DESIGN)
		expect(bar.shown < 9).toBe(true)
		expect(bar.rect.w <= narrow.w).toBe(true)
		expect(InventoryLayout.bar(narrow, 0, true, Layout.MIN_TOUCH_DESIGN).shown).toBe(0)
	end)
	it("phone slots are at least the touch minimum", function()
		expect(InventoryLayout.slotSize(true, Layout.MIN_TOUCH_DESIGN) >= Layout.MIN_TOUCH_DESIGN).toBe(true)
		expect(InventoryLayout.slotSize(false, Layout.MIN_TOUCH_DESIGN)).toBe(InventoryLayout.SLOT)
	end)
	it("the grid fits the body width and counts rows", function()
		local c = InventoryLayout.CELL
		expect(InventoryLayout.columns(536)).toBe(4)
		expect(InventoryLayout.columns(440)).toBe(3)
		for _, w in { 300, 440, 536, 900 } do
			local cols, size = InventoryLayout.columns(w), InventoryLayout.cellSize(w)
			expect(cols * size + (cols - 1) * c.gap <= w).toBe(true)
			expect(size <= c.max).toBe(true)
		end
		local size = InventoryLayout.cellSize(536)
		expect(InventoryLayout.gridHeight(0, 536)).toBe(0)
		expect(InventoryLayout.gridHeight(1, 536)).toBe(size)
		expect(InventoryLayout.gridHeight(5, 536)).toBe(2 * size + c.gap)
	end)
	it("the grid is whole rows of at least minRows, the items first and empty slots after", function()
		local c = InventoryLayout.CELL
		expect(InventoryLayout.slotCount(0, 536)).toBe(c.minRows * 4)
		expect(InventoryLayout.slotCount(2, 536)).toBe(8)
		expect(InventoryLayout.slotCount(9, 536)).toBe(12)
		expect(InventoryLayout.slotCount(2, 440)).toBe(6)
		expect(InventoryLayout.contentHeight(2, 536)).toBe(c.top + c.topGap + InventoryLayout.gridHeight(8, 536))
	end)
end)

describe("hotbar at the gate sizes (raw and under the 58 px top bar)", function()
	local sizes = { { 390, 844 }, { 844, 390 }, { 1024, 768 }, { 1366, 768 }, { 1920, 1080 }, { 844, 332 } }
	for _, size in sizes do
		for _, collapsed in { true, false } do
			it(
				`{size[1]}x{size[2]} nav {if collapsed then "collapsed" else "expanded"}: zone on screen, clear of money, status, nav, HUD, banners, touch zones`,
				function()
					local screen = Layout.screen(size[1], size[2], { navCollapsed = collapsed })
					local check = LayoutAssert.new(`{size[1]}x{size[2]}`, screen)
					LayoutAssert.hotbarChecks(check)
					expect(check.report()).toBe("")
					local bar =
						InventoryLayout.bar(screen.hotbar, 3, screen.compact, Layout.MIN_TOUCH_DESIGN, screen.tight)
					expect(bar.shown).toBe(3)
				end
			)
		end
	end
	it("a desktop bar holds all nine number-key slots; the narrowest phone (tight bar) holds at least three", function()
		local d = Layout.screen(1920, 1080)
		expect(InventoryLayout.bar(d.hotbar, 9, false, Layout.MIN_TOUCH_DESIGN).shown).toBe(9)
		local p = Layout.screen(390, 844)
		expect(InventoryLayout.bar(p.hotbar, 9, true, Layout.MIN_TOUCH_DESIGN, p.tight).shown >= 3).toBe(true)
	end)
	it("the hotbar check catches a bar over the money cluster", function()
		local s = table.clone(Layout.screen(1920, 1080)) :: any
		s.hotbar = Layout.rect(s.money.rect.x, s.money.rect.y, 600, 60)
		local check = LayoutAssert.new("bad", s)
		LayoutAssert.hotbarChecks(check)
		expect(string.find(check.report(), "overlaps Money", 1, true) ~= nil).toBe(true)
	end)
	it("every shipped Layout.MENU_HEIGHTS key has an Inventory card the panel checks cover", function()
		expect(Layout.MENU_HEIGHTS.Inventory ~= nil).toBe(true)
		local found = false
		for _, key in LayoutAssert.menuKeys() do
			found = found or key == "Inventory"
		end
		expect(found).toBe(true)
	end)
end)

describe("InventoryCore consumables (S3 stacks)", function()
	local HELD = { LuckPotion = 2, WeatherTotem = 5 }

	it("lists each consumable with a stack after the Tools and PvP items, count = the stack", function()
		local def = Config.PVP_TOOLS[1]
		local entries = InventoryCore.entries(input({
			pvp = { owned = { [def.id] = true }, cooldowns = {} },
			held = HELD,
		}))
		expect(table.concat(ids(entries), ",")).toBe(
			`tool:Bat,pvp:{def.id},consumable:LuckPotion,consumable:WeatherTotem`
		)
		local potion = entries[3]
		expect(potion.kind).toBe("consumable")
		expect(potion.count).toBe(2)
		expect(potion.iconId).toBe("Consumable_LuckPotion")
		expect(registry.get(potion.iconId) ~= nil).toBe(true)
		expect(InventoryCore.countText(potion.count)).toBe("2")
		-- an empty or missing stack is not listed
		expect(#InventoryCore.entries(input({ held = { LuckPotion = 0 } }))).toBe(1)
		expect(#InventoryCore.entries(input())).toBe(1)
	end)

	it("the consumable in hand is the selected one; selecting toggles it", function()
		local held = InventoryCore.entries(input({ held = HELD, heldConsumable = "WeatherTotem" }))
		expect(held[2].equipped).toBe(false)
		expect(held[3].equipped).toBe(true)
		local equip: any = InventoryCore.select(held[2])
		expect(equip.kind).toBe("Consumable")
		expect(equip.equip).toBe(true)
		expect((InventoryCore.select(held[3]) :: any).equip).toBe(false)
	end)

	it("using needs the item in hand and sends the item id", function()
		local entries = InventoryCore.entries(input({ held = HELD, heldConsumable = "LuckPotion" }))
		local req = InventoryCore.useRequest(entries[2]) :: { string }
		expect(req[1]).toBe("UseConsumable")
		expect(#req).toBe(2)
		expect(req[2]).toBe("LuckPotion")
		expect(InventoryCore.useRequest(entries[3])).toBeNil() -- not in hand
		expect(InventoryCore.useRequest(entries[1])).toBeNil() -- not a consumable
		expect(Remotes.ACTIONS[InventoryCore.USE_ACTION] ~= nil).toBe(true)
	end)
end)

describe("InventoryCore.pvpUseRequest", function()
	local PvpRules = require("../../src/shared/PvpRules")
	local ME = { X = 0, Y = 3, Z = 0 }

	local function equipped(id: string, readyAt: number?): InventoryCore.Entry
		local entries = InventoryCore.entries(input({
			pvp = { owned = { [id] = true }, equipped = id, cooldowns = { [id] = readyAt } },
		}))
		return entries[2]
	end
	local function use(id: string, aim: any, readyAt: number?): (InventoryCore.PvpUse?, string?)
		aim.players = aim.players or {}
		return InventoryCore.pvpUseRequest(equipped(id, readyAt), PvpRules.tool(id), aim, Config, 100)
	end
	local function at(x: number): any
		return { X = x, Y = 3, Z = 0 }
	end

	it("every PvP item has an aim mode and sends UsePvpItem, a real Request action", function()
		for _, def in Config.PVP_TOOLS do
			local mode = InventoryCore.pvpAimMode(def)
			expect(InventoryCore.PVP_AIM[def.id] ~= nil or InventoryCore.PVP_AIM[def.line] ~= nil).toBe(true)
			expect(type(mode)).toBe("string")
		end
		local args = Remotes.ACTIONS[InventoryCore.PVP_USE_ACTION].args
		expect(table.concat(args, ",")).toBe("string,number?,vector3?")
	end)

	it("gloves target the clicked player in reach, else the nearest, thieves first", function()
		local players = { { userId = 2, position = at(4) }, { userId = 3, position = at(8), carrying = true } }
		local r = use("KnockGlove1", { self = ME, players = players }) :: InventoryCore.PvpUse
		expect(r.action).toBe("UsePvpItem")
		expect(r.itemId).toBe("KnockGlove1")
		expect(r.target).toBe(3) -- the thief, though farther
		expect(r.aim).toBe(nil)
		expect((use("KnockGlove1", { self = ME, players = players, hovered = 2 }) :: any).target).toBe(2)
		-- clicked but out of reach: the nearest in reach instead
		local far = { { userId = 2, position = at(4) }, { userId = 4, position = at(50) } }
		expect((use("KnockGlove1", { self = ME, players = far, hovered = 4 }) :: any).target).toBe(2)
	end)

	it("a glove with nobody in reach sends nothing and says why", function()
		local r, why = use("KnockGlove2", { self = ME, players = { { userId = 2, position = at(30) } } })
		expect(r).toBe(nil)
		expect(why).toBe("No one in reach")
		local _, noSelf = use("KnockGlove2", { players = {} })
		expect(noSelf).toBe("Can't find you")
	end)

	it("a cooling-down item sends nothing and shows the seconds left", function()
		local r, why = use("GooBlaster1", { self = ME, point = at(10) }, 102.3)
		expect(r).toBe(nil)
		expect(why).toBe("Ready in 3s")
	end)

	it("blasters shoot at the clicked player, else the clicked point, else far along the ray", function()
		local players = { { userId = 2, position = at(20) } }
		local hit = use("GooBlaster2", { self = ME, players = players, hovered = 2, point = at(19) }) :: any
		expect(hit.aim.X).toBe(20)
		expect(hit.target).toBe(nil)
		expect((use("GooBlaster2", { self = ME, point = at(15) }) :: any).aim.X).toBe(15)
		expect((use("GooBlaster2", { self = ME, far = at(200) }) :: any).aim.X).toBe(200)
		local none, why = use("GooBlaster2", { self = ME })
		expect(none).toBe(nil)
		expect(why).toBe("Aim somewhere")
	end)

	it("traps and the balloon need a clicked point", function()
		expect((use("GooTrap1", { self = ME, point = at(6) }) :: any).aim.X).toBe(6)
		expect((use("FunBalloon", { self = ME, point = at(6) }) :: any).aim.X).toBe(6)
		local none, why = use("GooTrap1", { self = ME, far = at(200) })
		expect(none).toBe(nil)
		expect(why).toBe("Aim at the ground")
	end)

	it("bounce pad and fireworks use the point only within FUN_AIM_RANGE, else your own spot", function()
		local near = at(Config.PVP.FUN_AIM_RANGE - 1)
		local far = at(Config.PVP.FUN_AIM_RANGE + 1)
		expect((use("FunBouncePad", { self = ME, point = near }) :: any).aim.X).toBe(near.X)
		local own = use("FunFireworks", { self = ME, point = far }) :: any
		expect(own.aim).toBe(nil)
		expect(own.target).toBe(nil)
	end)

	it("self items send no target and no aim, whoever is around", function()
		local players = { { userId = 2, position = at(2) } }
		local r = use("FunConfetti", { self = ME, players = players, hovered = 2, point = at(2) }) :: any
		expect(r.itemId).toBe("FunConfetti")
		expect(r.target).toBe(nil)
		expect(r.aim).toBe(nil)
		expect((use("FunBubbles", { self = ME, players = players }) :: any).target).toBe(nil)
	end)

	it("the hat launcher targets only the clicked player, the squeaky hammer only a nearby thief", function()
		local players = { { userId = 2, position = at(3) }, { userId = 3, position = at(5), carrying = true } }
		expect((use("FunHatLauncher", { self = ME, players = players }) :: any).target).toBe(nil)
		expect((use("FunHatLauncher", { self = ME, players = players, hovered = 2 }) :: any).target).toBe(2)
		expect((use("FunSqueaky", { self = ME, players = players }) :: any).target).toBe(3)
		local calm = { { userId = 2, position = at(3) } }
		local squeak = use("FunSqueaky", { self = ME, players = calm }) :: any
		expect(squeak ~= nil and squeak.target == nil).toBe(true)
	end)

	it("the dance bomb needs a player in reach", function()
		local players = { { userId = 3, position = at(5), carrying = true } }
		expect((use("FunDanceBomb", { self = ME, players = players }) :: any).target).toBe(3)
		local none = use("FunDanceBomb", { self = ME, players = {} })
		expect(none).toBe(nil)
	end)

	it("an item that is not the equipped PvP item sends nothing, silently", function()
		local entries = InventoryCore.entries(input({ pvp = { owned = { KnockGlove1 = true }, cooldowns = {} } }))
		local r, why =
			InventoryCore.pvpUseRequest(entries[2], PvpRules.tool("KnockGlove1"), { players = {} }, Config, 100)
		expect(r).toBe(nil)
		expect(why).toBe(nil)
		expect(InventoryCore.pvpUseRequest(entries[1], nil, { players = {} }, Config, 100)).toBe(nil)
	end)

	it("server refusals read as tips", function()
		expect(InventoryCore.reasonText("too far away")).toBe("Too far away")
		expect(InventoryCore.reasonText(nil)).toBe("Can't use that here")
	end)
end)
