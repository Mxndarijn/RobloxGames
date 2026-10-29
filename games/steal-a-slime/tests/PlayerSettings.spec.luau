--!strict
-- The Settings menu values (PlayerSettings): cleaning, the SetSettings request, State, the save round trip, the
-- client attribute read and the ReplayTutorial request.
local Actions = require("../src/server/Actions")
local Config = require("../src/shared/Config")
local PlayerData = require("../src/shared/PlayerData")
local PlayerSettings = require("../src/shared/PlayerSettings")
local Remotes = require("../src/shared/Remotes")
local SaveData = require("../src/shared/SaveData")
local ServerFixtures = require("./ServerFixtures")
local Snapshot = require("../src/server/Snapshot")
local TestRunner = require("./TestRunner")
local TutorialProgress = require("../src/shared/TutorialProgress")
local Validate = require("../src/shared/Validate")

local describe, it, expect = TestRunner.describe, TestRunner.it, TestRunner.expect
local T0 = ServerFixtures.T0

local ctx: Actions.Context = {
	distanceBetween = function()
		return 2
	end,
	positionOf = function()
		return nil
	end,
}

local function send(world: any, userId: number, changes: any, now: number?)
	return Actions.handle(world, userId, "SetSettings", { changes }, now or T0 + 100, ctx)
end

describe("PlayerSettings", function()
	it("defaults keep the audio values the save has always had", function()
		local d = PlayerSettings.defaults()
		expect(d.musicVolume).toBe(Config.AUDIO.DEFAULT_MUSIC_VOLUME)
		expect(d.sfxVolume).toBe(Config.AUDIO.DEFAULT_SFX_VOLUME)
		expect(d.muted).toBe(false)
		expect(d.stealAlarm).toBe(true)
		expect(d.showOnBoards).toBe(true)
		expect(d.effects).toBe("full")
	end)

	it("an old save with only the three audio fields keeps them and gets defaults for the rest", function()
		local v = PlayerSettings.clean({ musicVolume = 0.3, sfxVolume = 0.46, muted = true })
		expect(v.musicVolume).toBe(0.3)
		expect(v.sfxVolume).toBe(0.46)
		expect(v.muted).toBe(true)
		expect(v.holdToSell).toBe(true)
		expect(v.numberStyle).toBe("short")
	end)

	it("every card row is a known setting with an attribute, once", function()
		local seen: { [string]: boolean } = {}
		local attrs: { [string]: boolean } = {}
		for _, tab in PlayerSettings.TABS do
			for _, entry in tab.entries do
				expect(PlayerSettings.schema.byId[entry.id] ~= nil).toBe(true)
				expect(seen[entry.id]).toBeNil()
				expect(attrs[entry.attribute]).toBeNil()
				seen[entry.id] = true
				attrs[entry.attribute] = true
				local def = PlayerSettings.schema.byId[entry.id]
				if def.kind == "choice" then
					expect(#(entry.labels or {})).toBe(#(def.choices :: { string }))
				end
			end
		end
		for _, def in PlayerSettings.schema.defs do
			expect(seen[def.id]).toBe(true)
		end
	end)

	it("reads the local value from the player attribute, default when unset or junk", function()
		local attrs: { [string]: any } = {}
		local player = {
			GetAttribute = function(_self: any, name: string)
				return attrs[name]
			end,
		}
		expect(PlayerSettings.on(player, "cameraShake")).toBe(true)
		attrs.SettingCameraShake = false
		expect(PlayerSettings.on(player, "cameraShake")).toBe(false)
		attrs.SettingEffects = "low"
		expect(PlayerSettings.get(player, "effects")).toBe("low")
		attrs.SettingEffects = "ultra"
		expect(PlayerSettings.get(player, "effects")).toBe("full")
		attrs[Config.HABITAT_ANIM.REDUCED_ATTRIBUTE] = true
		expect(PlayerSettings.on(player, "reducedMotion")).toBe(true)
	end)

	it("a hidden player shows as the hidden name on boards", function()
		expect(PlayerSettings.boardName({ showOnBoards = false }, "Bob")).toBe(PlayerSettings.HIDDEN_NAME)
		expect(PlayerSettings.boardName({}, "Bob")).toBe("Bob")
	end)
end)

describe("SetSettings request", function()
	it("is declared with a rate limit", function()
		expect(Remotes.ACTIONS.SetSettings.args[1]).toBe("settings")
		expect(Validate.ACTIONS.SetSettings).toBe(0.5)
	end)

	it("stores the changed values and keeps the others; State carries them", function()
		local world = ServerFixtures.world()
		local session = ServerFixtures.join(world, 1, {}, 0)
		local res = send(world, 1, { musicVolume = 0.25, cameraShake = false, effects = "low" })
		expect(res.ok).toBe(true)
		expect(session.data.settings.musicVolume).toBe(0.25)
		expect(session.data.settings.cameraShake).toBe(false)
		expect(session.data.settings.effects).toBe("low")
		expect(session.data.settings.sfxVolume).toBe(Config.AUDIO.DEFAULT_SFX_VOLUME)
		send(world, 1, { sfxVolume = 7 }, T0 + 200)
		expect(session.data.settings.sfxVolume).toBe(1)
		expect(session.data.settings.cameraShake).toBe(false)
		local state = Snapshot.build(world, session, T0)
		local s = state.settings :: any
		expect(s.cameraShake).toBe(false)
		expect(s.effects).toBe("low")
	end)

	it("refuses anything that is not a table of known settings with valid values", function()
		local world = ServerFixtures.world()
		local session = ServerFixtures.join(world, 1, {}, 0)
		local bad: { any } = {
			"muted",
			7,
			{ muted = "yes" },
			{ nope = true },
			{ effects = "ultra" },
			{ musicVolume = 0 / 0 },
			{ musicVolume = math.huge },
			{ [1] = true },
		}
		for i, changes in bad do
			local res = send(world, 1, changes, T0 + 100 + i)
			expect(res.ok).toBe(false)
			expect(res.message).toBe("bad argument")
		end
		expect(session.data.settings.muted).toBe(false)
	end)

	it("is rate limited", function()
		local world = ServerFixtures.world()
		local session = ServerFixtures.join(world, 1, {}, 0)
		expect(send(world, 1, { musicVolume = 0.1 }, T0 + 100).ok).toBe(true)
		local res = send(world, 1, { musicVolume = 0.9 }, T0 + 100.2)
		expect(res.ok).toBe(false)
		expect(res.message).toBe("too fast")
		expect(session.data.settings.musicVolume).toBe(0.1)
		expect(send(world, 1, { musicVolume = 0.9 }, T0 + 100.7).ok).toBe(true)
		expect(session.data.settings.musicVolume).toBe(0.9)
	end)

	it("every setting survives a save round trip", function()
		local data = PlayerData.new()
		data.settings = PlayerSettings.clean({
			muted = true,
			stealAlarm = false,
			numberStyle = "full",
			showOnBoards = false,
		})
		local again = SaveData.deserialize(SaveData.serialize(data, T0))
		expect(again.settings.muted).toBe(true)
		expect(again.settings.stealAlarm).toBe(false)
		expect(again.settings.numberStyle).toBe("full")
		expect(again.settings.showOnBoards).toBe(false)
	end)
end)

describe("ReplayTutorial request", function()
	local function replay(world: any, now: number?)
		return Actions.handle(world, 1, "ReplayTutorial", {}, now or T0 + 100, ctx)
	end

	it("is declared with a rate limit", function()
		expect(#Remotes.ACTIONS.ReplayTutorial.args).toBe(0)
		expect(Validate.ACTIONS.ReplayTutorial ~= nil).toBe(true)
	end)

	it("starts a finished tutorial again at the first step", function()
		local world = ServerFixtures.world()
		local session = ServerFixtures.join(world, 1, {}, 0)
		session.data.tutorialStep = 0
		expect(replay(world).ok).toBe(true)
		expect(TutorialProgress.currentId(session.data)).toBe("Grab")
	end)

	it("is refused while the tutorial still runs", function()
		local world = ServerFixtures.world()
		local session = ServerFixtures.join(world, 1, {}, 0)
		session.data.tutorialStep = 3
		local res = replay(world)
		expect(res.ok).toBe(false)
		expect(session.data.tutorialStep).toBe(3)
	end)

	it("a replay waits for each step's own action, even ones the save shows as done", function()
		local data: any = { tutorialStep = 0, stats = { caught = 5, locks = 2, merges = 1 }, padsUnlocked = 9 }
		expect(TutorialProgress.restart(data)).toBe(true)
		TutorialProgress.complete(data, "Grab")
		expect(TutorialProgress.currentId(data)).toBe("Deposit")
		TutorialProgress.complete(data, "Deposit")
		expect(TutorialProgress.currentId(data)).toBe("Lock")
	end)

	it("a normal run still skips the steps the save shows as done", function()
		local data: any = { tutorialStep = 1, stats = { caught = 5, locks = 0 } }
		TutorialProgress.complete(data, "Grab")
		expect(TutorialProgress.currentId(data)).toBe("Lock")
	end)

	it("the replay flag is runtime only and clears when the tutorial ends", function()
		local data = PlayerData.new()
		data.tutorialStep = 0
		TutorialProgress.restart(data)
		expect(SaveData.serialize(data, T0).tutorialReplay).toBeNil()
		TutorialProgress.skip(data)
		expect(data.tutorialReplay).toBeNil()
	end)
end)
