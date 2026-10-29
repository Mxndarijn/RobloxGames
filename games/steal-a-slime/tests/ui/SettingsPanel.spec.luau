--!strict
-- The Settings card (src/ui/Panels/Settings.luau) and the client SettingsController (src/ui/SettingsController.luau).
local Config = require("../../src/shared/Config")
local PlayerSettings = require("../../src/shared/PlayerSettings")
local SettingsController = require("../../src/ui/SettingsController")
local TestRunner = require("../TestRunner")
local UiHarness = require("./UiHarness")

local describe, it, expect = TestRunner.describe, TestRunner.it, TestRunner.expect

-- A controller over a plain table, like SettingsController without the attributes.
local function fakeController(): any
	local values = PlayerSettings.defaults()
	return {
		values = values,
		get = function(id: string)
			return values[id]
		end,
		set = function(id: string, v: any)
			values[id] = PlayerSettings.schema:value(id, v)
		end,
		reset = function()
			for id, v in PlayerSettings.defaults() do
				values[id] = v
			end
		end,
	}
end

local function build(): (any, any, { any })
	local sent = {}
	local controller = fakeController()
	local ctx: any = {
		Config = Config,
		PlayerSettings = PlayerSettings,
		settings = controller,
		userId = 42,
		placeVersion = 19,
		request = function(action: string, _done: any, ...: any)
			table.insert(sent, { action, ... })
		end,
	}
	return UiHarness.ui("Panels/Settings").new(UiHarness.root(), ctx), controller, sent
end

local function within(panel: any, rowName: string, child: string): any
	local row = UiHarness.find(panel.frame, rowName)
	assert(row, `no row {rowName}`)
	return UiHarness.find(row, child)
end

describe("Settings panel", function()
	it("opens on Sound with a tab per settings tab and every row", function()
		local panel = build()
		expect(panel.tab()).toBe("sound")
		for _, tab in PlayerSettings.TABS do
			expect(UiHarness.find(panel.frame, `Tab_{tab.key}`) ~= nil).toBe(true)
			for _, entry in tab.entries do
				expect(UiHarness.find(panel.frame, entry.id) ~= nil).toBe(true)
			end
		end
	end)

	it("a toggle shows its state and flips the setting", function()
		local panel, controller = build()
		local toggle = within(panel, "stealAlarm", "Toggle")
		expect(toggle.Text).toBe("On")
		UiHarness.fire(toggle, "Activated")
		expect(controller.values.stealAlarm).toBe(false)
		panel.refresh()
		expect(toggle.Text).toBe("Off")
	end)

	it("a choice button picks its value", function()
		local panel, controller = build()
		UiHarness.fire(within(panel, "effects", "Choice_low"), "Activated")
		expect(controller.values.effects).toBe("low")
		UiHarness.fire(within(panel, "numberStyle", "Choice_full"), "Activated")
		expect(controller.values.numberStyle).toBe("full")
	end)

	it("sliders show their percent", function()
		local panel, controller = build()
		controller.values.musicVolume = 0.25
		panel.refresh()
		expect(within(panel, "musicVolume", "Percent").Text).toBe("25%")
	end)

	it("switching tabs shows only that tab's list", function()
		local panel = build()
		panel.showTab("visuals")
		expect(panel.tab()).toBe("visuals")
		expect(UiHarness.find(panel.frame, "List_visuals").Visible).toBe(true)
		expect(UiHarness.find(panel.frame, "List_sound").Visible).toBe(false)
	end)

	it("Replay tutorial asks the server, and is off while the tutorial runs", function()
		local panel, _, sent = build()
		panel.update({ tutorialStepId = "Grab" })
		local replay = within(panel, "replayTutorial", "Replay")
		expect(replay.Text).toBe("Running")
		panel.update({})
		expect(replay.Text).toBe("Replay")
		UiHarness.fire(replay, "Activated")
		expect(sent[1][1]).toBe("ReplayTutorial")
	end)

	it("shows the game version and the player id", function()
		local panel = build()
		expect(within(panel, "version", "Version").Text).toBe("v19")
		expect(within(panel, "version", "Hint").Text).toBe("Player ID 42")
		local Settings = UiHarness.ui("Panels/Settings")
		expect((Settings.versionText(0, 1))).toBe("Studio")
	end)
end)

-- A player with attributes and change signals, and a delay that runs when the test says so.
local function fakePlayer(): any
	local attrs: { [string]: any } = {}
	local handlers: { [string]: { () -> () } } = {}
	local player = {}
	function player.GetAttribute(_self: any, name: string)
		return attrs[name]
	end
	function player.SetAttribute(_self: any, name: string, value: any)
		if attrs[name] == value then
			return
		end
		attrs[name] = value
		for _, fn in handlers[name] or {} do
			fn()
		end
	end
	function player.GetAttributeChangedSignal(_self: any, name: string)
		return {
			Connect = function(_s: any, fn: () -> ())
				handlers[name] = handlers[name] or {}
				table.insert(handlers[name], fn)
				return { Disconnect = function() end }
			end,
		}
	end
	return player
end

local function controller(): (any, any, { any }, () -> ())
	local player = fakePlayer()
	local sent: { any } = {}
	local pending: { () -> () } = {}
	local c = SettingsController.new({
		player = player,
		PlayerSettings = PlayerSettings,
		send = function(action: string, ...: any)
			table.insert(sent, { action, ... })
		end,
		delay = function(_seconds: number, fn: () -> ())
			table.insert(pending, fn)
		end,
	})
	local function runDelays()
		local now = table.clone(pending)
		table.clear(pending)
		for _, fn in now do
			fn()
		end
	end
	return c, player, sent, runDelays
end

describe("SettingsController", function()
	it("loads the saved values onto the attributes without sending them back", function()
		local c, player, sent, runDelays = controller()
		c.load({ muted = true, cameraShake = false, effects = "low" })
		runDelays()
		expect(player:GetAttribute("AudioMuted")).toBe(true)
		expect(PlayerSettings.on(player, "cameraShake")).toBe(false)
		expect(c.get("effects")).toBe("low")
		expect(#sent).toBe(0)
	end)

	it("sends only the changed ids once the last change settles", function()
		local c, _, sent, runDelays = controller()
		c.load({})
		c.set("cameraShake", false)
		c.set("numberStyle", "full")
		runDelays()
		expect(#sent).toBe(1)
		expect(sent[1][1]).toBe("SetSettings")
		expect(sent[1][2].cameraShake).toBe(false)
		expect(sent[1][2].numberStyle).toBe("full")
		expect(sent[1][2].muted).toBeNil()
	end)

	it("sends nothing before the first load, and a later load is ignored", function()
		local c, _, sent, runDelays = controller()
		c.set("muted", true)
		runDelays()
		expect(#sent).toBe(0)
		c.load({ muted = false })
		c.load({ muted = true })
		expect(c.get("muted")).toBe(false)
	end)

	it("reset puts every setting back to its default", function()
		local c, _, sent, runDelays = controller()
		c.load({ muted = true, showOnBoards = false })
		c.reset()
		runDelays()
		expect(c.get("muted")).toBe(false)
		expect(c.get("showOnBoards")).toBe(true)
		expect(sent[1][2].muted).toBe(false)
		expect(sent[1][2].showOnBoards).toBe(true)
	end)

	it("tells listeners which setting changed", function()
		local c = controller()
		local seen: { string } = {}
		c.onChanged(function(id: string)
			table.insert(seen, id)
		end)
		c.set("othersEffects", false)
		expect(seen[1]).toBe("othersEffects")
	end)
end)
