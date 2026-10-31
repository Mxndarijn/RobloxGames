--!strict
-- The obby's bottom-right status slot over its three phases (contract/obby.md §4): the boost's time left, then a
-- dimmed cooldown countdown to State.obby.readyAt, then nothing once a finish earns the boost again.
local Config = require("../../src/shared/Config")
local Constants = require("../../src/shared/Constants")
local Genome = require("../../src/shared/Genome")
local HudClusters = require("../../src/ui/HudClusters")
local Layout = require("../../src/ui/Layout")
local Remotes = require("../../src/shared/Remotes")
local TestRunner = require("../TestRunner")
local UiHarness = require("./UiHarness")

local describe, it, expect = TestRunner.describe, TestRunner.it, TestRunner.expect

-- State.obby at now = 1000: boosted until 1300, ready at 1600.
local function view(extra: { [string]: any }?): any
	local v: { [string]: any } = { bonus = 0.5, sections = { "Jelly Steps" }, rotatesAt = 1600 }
	for k, x in extra or {} do
		v[k] = x
	end
	return v
end

local function ids(input: any, places: number?): string
	local out = {}
	for _, s in HudClusters.status(input, 1000, places or Layout.STATUS.count) do
		table.insert(out, `{s.id}:{s.kind}`)
	end
	return table.concat(out, ",")
end

describe("Obby status slot: cooldown", function()
	it("counts down to readyAt as a dimmed cooldown slot once the boost is over", function()
		local slot = HudClusters.obby(view({ readyAt = 1192 }), 1000) :: HudClusters.Slot
		expect(slot.id).toBe("Obby")
		expect(slot.icon).toBe("Boost_Obby")
		expect(slot.kind).toBe("cooldown")
		expect(slot.text).toBe("3:12")
		local tip = HudClusters.tooltip(slot)
		expect(tip.title).toBe("Obby")
		expect(tip.time).toBe("Next boost ready in 3:12")
		expect(string.find(tip.body, "x1.5 income boost", 1, true) ~= nil).toBe(true)
	end)

	it("shows the boost while it runs, even with readyAt set", function()
		local slot = HudClusters.obby(view({ endsAt = 1300, readyAt = 1600 }), 1000) :: HudClusters.Slot
		expect(slot.kind).toBe("active")
		expect(slot.text).toBe("5:00")
		expect(HudClusters.tooltip(slot).title).toBe("Obby")
	end)

	it("turns into the cooldown the moment the boost ends, and goes away once ready", function()
		local v = view({ endsAt = 1300, readyAt = 1600 })
		expect((HudClusters.obby(v, 1300) :: HudClusters.Slot).kind).toBe("cooldown")
		expect((HudClusters.obby(v, 1300) :: HudClusters.Slot).text).toBe("5:00")
		expect(HudClusters.obby(v, 1600)).toBeNil()
		expect(HudClusters.obby(view({ readyAt = 1000 }), 1000)).toBeNil()
		expect(HudClusters.obby(view(), 1000)).toBeNil()
		expect(HudClusters.obby(view({ readyAt = 0 / 0 }), 1000)).toBeNil()
		expect(HudClusters.obby({ readyAt = 1200 } :: any, 1000)).toBeNil()
	end)

	it("keeps its place in the row while there is room", function()
		local input = {
			modifierEnabled = false,
			friendsEnabled = false,
			blessed = { bonus = 0.3, endsAt = 1179 },
			obby = view({ readyAt = 1192 }),
			codes = { boostMult = 2, boostEndsAt = 1300 },
		}
		expect(ids(input)).toBe("Blessed:active,Obby:cooldown,Boost:active")
	end)

	it("gives way first when the row is full, before the featured Secret", function()
		local input = {
			rain = { active = true, endsAt = 1097 },
			modifierEnabled = false,
			friends = { count = 1, bonus = 0.1 },
			friendsEnabled = true,
			blessed = { bonus = 0.3, endsAt = 1179 },
			obby = view({ readyAt = 1192 }),
			featuredSecret = { id = "X", name = "Glimmer", endsAt = 9000 },
		}
		expect(ids(input, 4)).toBe("Rain:active,Friend:boost,Blessed:active,Secret:week")
		input.featuredSecret = nil
		expect(ids(input, 4)).toBe("Rain:active,Friend:boost,Blessed:active,Obby:cooldown")
		-- a running boost keeps its normal priority over the Secret
		input.obby = view({ endsAt = 1300, readyAt = 1600 })
		input.featuredSecret = { id = "X", name = "Glimmer", endsAt = 9000 }
		expect(ids(input, 4)).toBe("Rain:active,Friend:boost,Blessed:active,Obby:active")
	end)
end)

describe("Obby status slot: mounted Hud", function()
	local function mount(): (any, any)
		for _, name in { "RainActive", "RainEndsAt", "RainNextAt" } do
			UiHarness.workspaceAttributes[name] = nil
		end
		local gui = UiHarness.root()
		local hud = UiHarness.ui("Hud").new(gui, {
			Config = Config,
			Constants = Constants,
			Genome = Genome,
			actions = Remotes.ACTIONS,
			send = function() end,
			request = function() end,
			serverNow = function()
				return 1000
			end,
			playerName = function()
				return "Tester"
			end,
			itemIcons = UiHarness.ui("ItemIcons").build(Config),
		})
		hud.layout(Layout.screen(1920, 1080))
		return hud, gui
	end
	local function state(obby: any): any
		return { cash = 0, incomePerSec = 0, rebirths = 0, slimes = {}, daily = {}, rain = {}, obby = obby }
	end

	it("dims the icon and mutes the timer while cooling down, and shows a bright boost while boosted", function()
		local hud, gui = mount()
		local slot = UiHarness.find(UiHarness.find(gui, "Status"), "Obby")
		local timer = UiHarness.find(slot, "Timer")

		hud.update(state(view({ endsAt = 1300, readyAt = 1600 })))
		hud.tick(1000)
		expect(slot.Visible).toBe(true)
		expect(slot:GetAttribute("Kind")).toBe("active")
		expect(slot:FindFirstChild("Dim", true)).toBeNil() -- only made once a cooldown shows
		expect(timer.Text).toBe("5:00")

		hud.tick(1408)
		expect(slot.Visible).toBe(true)
		expect(slot:GetAttribute("Kind")).toBe("cooldown")
		local dim = UiHarness.find(slot, "Dim")
		expect(dim.Visible).toBe(true)
		expect(timer.Text).toBe("3:12")
		expect(timer.TextColor3).toBe(UiHarness.ui("Widgets").Theme.Muted)

		hud.tick(1600)
		expect(slot.Visible).toBe(false)

		-- a new boost lifts the veil again
		hud.update(state(view({ endsAt = 1900, readyAt = 2200 })))
		hud.tick(1600)
		expect(slot.Visible).toBe(true)
		expect(dim.Visible).toBe(false)
	end)
end)
