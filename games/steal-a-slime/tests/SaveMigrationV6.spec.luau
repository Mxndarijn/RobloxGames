--!strict
-- Save v5 -> v6: plotSkin / stealLog / settings are versioned and normalised (SaveData.migrateV5),
-- The Settings menu request lives in PlayerSettings.spec.
local Config = require("../src/shared/Config")
local PlayerData = require("../src/shared/PlayerData")
local SaveData = require("../src/shared/SaveData")
local ServerFixtures = require("./ServerFixtures")
local TestRunner = require("./TestRunner")

local describe, it, expect = TestRunner.describe, TestRunner.it, TestRunner.expect
local T0 = ServerFixtures.T0

-- A save as SaveData.serialize wrote it at SAVE_VERSION 5 (no `settings`).
local function v5Save(): { [string]: any }
	local out = SaveData.serialize(PlayerData.new(), T0)
	out.version = 5
	out.settings = nil
	return out
end

describe("save v6: migration", function()
	it("is exactly one version above v5", function()
		expect(SaveData.migrateV5(v5Save()).version).toBe(6)
	end)
	it("a v5 save without the fields gets classic / empty / default settings", function()
		local save = v5Save()
		save.plotSkin = nil
		save.stealLog = nil
		local out = SaveData.migrateV5(save)
		expect(out.plotSkin).toBe("classic")
		expect(#out.stealLog).toBe(0)
		expect(out.settings.musicVolume).toBe(Config.AUDIO.DEFAULT_MUSIC_VOLUME)
		expect(out.settings.sfxVolume).toBe(Config.AUDIO.DEFAULT_SFX_VOLUME)
		expect(out.settings.muted).toBe(false)
	end)
	it("keeps valid values", function()
		local save = v5Save()
		save.plotSkin = "candy"
		save.stealLog = { { thief = "Bob", slime = "Blorp", at = 100 } }
		save.settings = { musicVolume = 0.2, sfxVolume = 1, muted = true }
		local out = SaveData.migrateV5(save)
		expect(out.plotSkin).toBe("candy")
		expect(#out.stealLog).toBe(1)
		expect(out.stealLog[1].thief).toBe("Bob")
		expect(out.settings.musicVolume).toBe(0.2)
		expect(out.settings.sfxVolume).toBe(1)
		expect(out.settings.muted).toBe(true)
	end)
	it("junk becomes the defaults and the log stays capped", function()
		local save = v5Save()
		save.plotSkin = { 1 }
		save.stealLog = "nope"
		save.settings = { musicVolume = "loud", sfxVolume = 0 / 0, muted = "yes" }
		local out = SaveData.migrateV5(save)
		expect(out.plotSkin).toBe("classic")
		expect(#out.stealLog).toBe(0)
		expect(out.settings.musicVolume).toBe(Config.AUDIO.DEFAULT_MUSIC_VOLUME)
		expect(out.settings.sfxVolume).toBe(Config.AUDIO.DEFAULT_SFX_VOLUME)
		expect(out.settings.muted).toBe(false)
		save.stealLog = {}
		for i = 1, 40 do
			table.insert(save.stealLog, { thief = "t", slime = "s", at = i })
		end
		expect(#SaveData.migrateV5(save).stealLog <= Config.STEAL_ALERT.LOG_CAP).toBe(true)
		save.settings = 7
		expect(SaveData.migrateV5(save).settings.muted).toBe(false)
	end)
	it("is pure and idempotent", function()
		local save = v5Save()
		save.settings = { musicVolume = 5, sfxVolume = -3, muted = true }
		local once = SaveData.migrateV5(save)
		expect(save.version).toBe(5)
		expect(save.settings.musicVolume).toBe(5)
		local twice = SaveData.migrateV5(once)
		expect(twice.settings.musicVolume).toBe(1)
		expect(twice.settings.sfxVolume).toBe(0)
		expect(twice.settings.muted).toBe(true)
		expect(twice.plotSkin).toBe(once.plotSkin)
	end)
	it("older saves chain through every step", function()
		for _, version in { 1, 2, 3, 4 } do
			local d = SaveData.deserialize({ version = version, cash = 10 })
			expect(d.settings.muted).toBe(false)
			expect(d.settings.sfxVolume).toBe(Config.AUDIO.DEFAULT_SFX_VOLUME)
			expect(d.plotSkin).toBe("classic")
		end
		expect(SaveData.deserialize({ Cash = 5, Rebirths = 0, Slimes = {} }).settings.muted).toBe(false)
		expect(SaveData.migrate(v5Save()).version).toBe(Config.SAVE_VERSION)
	end)
	it("a newer version is read field by field and still cleaned", function()
		local d = SaveData.deserialize({ version = 99, cash = 3, settings = { musicVolume = 9, muted = true } })
		expect(d.settings.musicVolume).toBe(1)
		expect(d.settings.muted).toBe(true)
	end)
end)

describe("save v6: round trip and flags", function()
	it("round-trips settings, steal log and plot skin", function()
		local data = PlayerData.new()
		data.settings = { musicVolume = 0.55, sfxVolume = 0.1, muted = true }
		data.stealLog = { { thief = "Bob", slime = "Blorp", at = 50 } }
		local stored = SaveData.serialize(data, T0)
		expect(stored.version).toBe(Config.SAVE_VERSION)
		local back = SaveData.deserialize(stored)
		expect(back.settings.musicVolume).toBe(0.55)
		expect(back.settings.sfxVolume).toBe(0.1)
		expect(back.settings.muted).toBe(true)
		expect(back.stealLog[1].thief).toBe("Bob")
	end)
	it("a new profile saves the default settings", function()
		local stored = SaveData.serialize(PlayerData.new(), T0)
		expect(stored.settings.musicVolume).toBe(Config.AUDIO.DEFAULT_MUSIC_VOLUME)
		expect(stored.settings.muted).toBe(false)
	end)
	it("the fields survive load -> save whatever the flags are (the migration never reads them)", function()
		local stored = v5Save()
		stored.settings = { musicVolume = 0.3, sfxVolume = 0.6, muted = true }
		stored.stealLog = { { thief = "Bob", slime = "Blorp", at = 7 } }
		local again = SaveData.serialize(SaveData.deserialize(stored), T0)
		expect(again.settings.musicVolume).toBe(0.3)
		expect(again.settings.sfxVolume).toBe(0.6)
		expect(again.settings.muted).toBe(true)
		expect(#again.stealLog).toBe(1)
	end)
end)
