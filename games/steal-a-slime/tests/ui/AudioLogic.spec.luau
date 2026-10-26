--!strict
-- Pure audio rules (src/ui/AudioLogic.luau, FEATURES.Audio).
local AudioLogic = require("../../src/ui/AudioLogic")
local Config = require("../../src/shared/Config")
local DayNight = require("../../src/shared/DayNight")
local TestRunner = require("../TestRunner")

local describe, it, expect = TestRunner.describe, TestRunner.it, TestRunner.expect
local cfg = Config.AUDIO

describe("AudioLogic volume", function()
	it("clamps to 0..1 and falls back for junk", function()
		expect(AudioLogic.clampVolume(2)).toBe(1)
		expect(AudioLogic.clampVolume(-1)).toBe(0)
		expect(AudioLogic.clampVolume(0.4)).toBe(0.4)
		expect(AudioLogic.clampVolume("x", 0.5)).toBe(0.5)
		expect(AudioLogic.clampVolume(0 / 0, 0.7)).toBe(0.7)
		expect(AudioLogic.clampVolume(nil)).toBe(0)
	end)
	it("sanitize fills defaults and clamps", function()
		local s = AudioLogic.sanitize({ muted = true, sfx = 5 }, cfg)
		expect(s.muted).toBe(true)
		expect(s.sfx).toBe(1)
		expect(s.music).toBe(cfg.DEFAULT_MUSIC_VOLUME)
		expect(AudioLogic.sanitize(nil, cfg).muted).toBe(false)
	end)
	it("mute zeroes both groups", function()
		local s = AudioLogic.sanitize({ muted = true, sfx = 1, music = 1 }, cfg)
		expect(AudioLogic.groupVolume(s, "SFX")).toBe(0)
		expect(AudioLogic.groupVolume(s, "Music")).toBe(0)
		s.muted = false
		expect(AudioLogic.groupVolume(s, "Music")).toBe(1)
	end)
end)

describe("AudioLogic.resolveSfx", function()
	it("resolves every registry name that maps to a valid id", function()
		for _, name in { "buy", "collect", "steal", "merge", "rebirth", "alarm", "error", "click" } do
			expect(type(AudioLogic.resolveSfx(cfg, name))).toBe("string")
		end
	end)
	it("falls back to nil for unknown, empty or malformed ids", function()
		expect(AudioLogic.resolveSfx(cfg, "nope")).toBe(nil)
		expect(AudioLogic.resolveSfx(cfg, nil)).toBe(nil)
		expect(AudioLogic.resolveSfx({ SFX = { x = "" } }, "x")).toBe(nil)
		expect(AudioLogic.resolveSfx({ SFX = { x = "http://evil" } }, "x")).toBe(nil)
	end)
	it("accepts Notify names and raw ids", function()
		expect(AudioLogic.resolveSfx(cfg, "Goal")).toBe("rbxassetid://4612373884")
		expect(AudioLogic.resolveSfx(cfg, "rbxassetid://5")).toBe("rbxassetid://5")
	end)
end)

describe("AudioLogic ambience", function()
	it("picks day between sunrise and sunset, night otherwise", function()
		expect((AudioLogic.ambientFor(12, cfg, DayNight))).toBe("day")
		expect((AudioLogic.ambientFor(6.5, cfg, DayNight))).toBe("day")
		expect((AudioLogic.ambientFor(17.5, cfg, DayNight))).toBe("night")
		expect((AudioLogic.ambientFor(0, cfg, DayNight))).toBe("night")
		expect((AudioLogic.ambientFor(24 + 3, cfg, DayNight))).toBe("night")
	end)
	it("returns the configured id, nil when empty", function()
		local _, id = AudioLogic.ambientFor(12, { AMBIENT_DAY_ID = "rbxassetid://9", AMBIENT_NIGHT_ID = "" }, DayNight)
		expect(id).toBe("rbxassetid://9")
		local _, none = AudioLogic.ambientFor(0, { AMBIENT_DAY_ID = "rbxassetid://9", AMBIENT_NIGHT_ID = "" }, DayNight)
		expect(none).toBe(nil)
	end)
	it("fades linearly and lands on the target", function()
		expect(AudioLogic.fadeStep(0, 1, 1, 4)).toBe(0.25)
		expect(AudioLogic.fadeStep(0.9, 1, 1, 4)).toBe(1)
		expect(AudioLogic.fadeStep(1, 0, 2, 4)).toBe(0.5)
		expect(AudioLogic.fadeStep(0.3, 1, 1, 0)).toBe(1)
	end)
end)

describe("AudioLogic sliders", function()
	it("snaps to 5% steps and clamps", function()
		expect(AudioLogic.snapVolume(0.37)).toBe(0.35)
		expect(AudioLogic.snapVolume(0.38)).toBe(0.4)
		expect(AudioLogic.snapVolume(0.35)).toBe(0.35)
		expect(AudioLogic.snapVolume(1.7)).toBe(1)
		expect(AudioLogic.snapVolume(-0.2)).toBe(0)
		expect(AudioLogic.snapVolume(0 / 0)).toBe(0)
		expect(AudioLogic.snapVolume(0.33, 0.1)).toBe(0.3)
	end)
	it("maps pointer pixels on the track to a snapped volume", function()
		expect(AudioLogic.volumeFromPixel(100, 100, 200)).toBe(0)
		expect(AudioLogic.volumeFromPixel(200, 100, 200)).toBe(0.5)
		expect(AudioLogic.volumeFromPixel(300, 100, 200)).toBe(1)
		expect(AudioLogic.volumeFromPixel(500, 100, 200)).toBe(1)
		expect(AudioLogic.volumeFromPixel(0, 100, 200)).toBe(0)
		expect(AudioLogic.volumeFromPixel(113, 100, 200)).toBe(0.05)
		expect(AudioLogic.volumeFromPixel(150, 100, 0)).toBe(0)
		expect(AudioLogic.volumeFromPixel(nil, 100, 200)).toBe(0)
	end)
	it("formats percent and fill", function()
		expect(AudioLogic.percentText(0.35)).toBe("35%")
		expect(AudioLogic.percentText(1)).toBe("100%")
		expect(AudioLogic.percentText(nil)).toBe("0%")
		expect(AudioLogic.volumeToAlpha(2)).toBe(1)
		expect(AudioLogic.volumeToAlpha(0.4)).toBe(0.4)
	end)
end)

describe("AudioLogic SFX throttle", function()
	local tcfg = { SFX_MIN_GAP = 0.05, SFX_MAX_LIVE = 2 }
	it("drops a repeat of the same name inside the gap, not other names", function()
		local st = AudioLogic.newSfxState()
		expect(AudioLogic.allowSfx(st, "click", 10, tcfg)).toBe(true)
		expect(AudioLogic.allowSfx(st, "click", 10.01, tcfg)).toBe(false)
		expect(AudioLogic.allowSfx(st, "Cash", 10.01, tcfg)).toBe(true)
		expect(AudioLogic.allowSfx(st, "click", 10.06, tcfg)).toBe(true)
	end)
	it("caps live copies per name until one is released", function()
		local st = AudioLogic.newSfxState()
		expect(AudioLogic.allowSfx(st, "PvpHit", 1, tcfg)).toBe(true)
		expect(AudioLogic.allowSfx(st, "PvpHit", 2, tcfg)).toBe(true)
		expect(AudioLogic.allowSfx(st, "PvpHit", 3, tcfg)).toBe(false)
		AudioLogic.releaseSfx(st, "PvpHit")
		expect(AudioLogic.allowSfx(st, "PvpHit", 4, tcfg)).toBe(true)
	end)
	it("never counts below zero", function()
		local st = AudioLogic.newSfxState()
		AudioLogic.releaseSfx(st, "click")
		expect(st.live.click).toBe(0)
	end)
end)

describe("AudioLogic night one-shot", function()
	local ocfg = {
		NIGHT_ONESHOT_ID = "rbxassetid://9",
		NIGHT_ONESHOT_MIN_SECONDS = 20,
		NIGHT_ONESHOT_MAX_SECONDS = 40,
		NIGHT_ONESHOT_SPEED_JITTER = 0.05,
		NIGHT_ONESHOT_MIN_LEVEL = 0.9,
	}
	local function fixed(v: number): () -> number
		return function()
			return v
		end
	end
	it("never runs while the night is not faded in", function()
		local timer, fire = AudioLogic.oneshotStep(5, 10, 0.5, ocfg, fixed(0))
		expect(timer).toBe(nil)
		expect(fire).toBe(false)
	end)
	it("starts a gap in MIN..MAX on the first full-night frame, then fires when it runs out", function()
		local timer, fire = AudioLogic.oneshotStep(nil, 1, 1, ocfg, fixed(0.5))
		expect(timer).toBe(30)
		expect(fire).toBe(false)
		timer, fire = AudioLogic.oneshotStep(timer, 29, 1, ocfg, fixed(0.5))
		expect(timer).toBe(1)
		expect(fire).toBe(false)
		timer, fire = AudioLogic.oneshotStep(timer, 1, 1, ocfg, fixed(1))
		expect(fire).toBe(true)
		expect(timer).toBe(40)
	end)
	it("gap and speed stay inside their ranges", function()
		expect(AudioLogic.oneshotGap(ocfg, fixed(0))).toBe(20)
		expect(AudioLogic.oneshotGap(ocfg, fixed(2))).toBe(40)
		expect(AudioLogic.oneshotSpeed(ocfg, fixed(0))).toBe(0.95)
		expect(AudioLogic.oneshotSpeed(ocfg, fixed(1))).toBe(1.05)
	end)
	it("an empty id means no owl", function()
		expect(AudioLogic.oneshotId({ NIGHT_ONESHOT_ID = "" })).toBe(nil)
		expect(AudioLogic.oneshotId(ocfg)).toBe("rbxassetid://9")
	end)
end)

describe("AudioLogic layers", function()
	local lcfg = {
		MUSIC = { day = "rbxassetid://1", night = "rbxassetid://2", boss = "rbxassetid://3" },
		MUSIC_VOLUME = 0.5,
		MUSIC_FADE_SECONDS = 3,
		AMBIENT_DAY_ID = "rbxassetid://4",
		AMBIENT_NIGHT_ID = "rbxassetid://5",
		AMBIENT_VOLUME = 0.25,
		AMBIENT_NIGHT_VOLUME = 0.1,
		AMBIENT_FADE_SECONDS = 4,
		WEATHER_BEDS = { Rain = "rbxassetid://6", Snow = "" },
		WEATHER_BED_VOLUME = 0.35,
		WEATHER_DUCK = 0.5,
	}
	local function keys(t: { [string]: any }): { string }
		local out = {}
		for k in t do
			table.insert(out, k)
		end
		table.sort(out)
		return out
	end
	it("plays the day music and the birds by day", function()
		local t = AudioLogic.layerTargets({ clockTime = 12 }, lcfg, DayNight)
		expect(table.concat(keys(t), ",")).toBe("bed_day,music_day")
		expect(t.music_day.volume).toBe(0.5)
		expect(t.bed_day.volume).toBe(0.25)
	end)
	it("switches to the night music and the night bed at its own volume", function()
		local t = AudioLogic.layerTargets({ clockTime = 0 }, lcfg, DayNight)
		expect(table.concat(keys(t), ",")).toBe("bed_night,music_night")
		expect(t.bed_night.volume).toBe(0.1)
	end)
	it("the boss track replaces the day / night music", function()
		local t = AudioLogic.layerTargets({ clockTime = 0, boss = true }, lcfg, DayNight)
		expect(t.music_boss ~= nil).toBe(true)
		expect(t.music_night).toBe(nil)
	end)
	it("rain adds its bed and ducks the day bed; a weather without an id adds nothing", function()
		local t = AudioLogic.layerTargets({ clockTime = 12, weather = "Rain" }, lcfg, DayNight)
		expect(t.weather_Rain.id).toBe("rbxassetid://6")
		expect(t.bed_day.volume).toBe(0.125)
		local s = AudioLogic.layerTargets({ clockTime = 12, weather = "Snow" }, lcfg, DayNight)
		expect(s.weather_Snow).toBe(nil)
		expect(s.bed_day.volume).toBe(0.25)
	end)
	it("leaves out layers with empty or malformed ids", function()
		local t = AudioLogic.layerTargets({ clockTime = 12 }, {
			MUSIC = { day = "", night = "x", boss = "" },
			AMBIENT_DAY_ID = "nope",
			AMBIENT_NIGHT_ID = "",
			WEATHER_BEDS = {},
		}, DayNight)
		expect(#keys(t)).toBe(0)
	end)
	it("every shipped music and weather id is valid", function()
		for _, track in { "day", "night", "boss" } do
			local t = AudioLogic.layerTargets(
				{ clockTime = if track == "night" then 0 else 12, boss = track == "boss" },
				cfg,
				DayNight
			)
			expect(t["music_" .. track] ~= nil).toBe(true)
		end
		for weather in cfg.WEATHER_BEDS do
			local t = AudioLogic.layerTargets({ clockTime = 12, weather = weather }, cfg, DayNight)
			expect(t["weather_" .. weather] ~= nil).toBe(true)
		end
	end)
	it("every thunder name resolves", function()
		for _, name in cfg.THUNDER do
			expect(type(AudioLogic.resolveSfx(cfg, name))).toBe("string")
		end
	end)
end)

describe("AudioLogic one-shot spec and variants", function()
	local function fixed(v: number): () -> number
		return function()
			return v
		end
	end
	it("a custom spec sets the gap range and the bed level it needs", function()
		local spec = { min = 10, max = 20, minLevel = 0.5 }
		local timer, fire = AudioLogic.oneshotStep(nil, 1, 0.4, cfg, fixed(0), spec)
		expect(timer).toBe(nil)
		expect(fire).toBe(false)
		timer = AudioLogic.oneshotStep(nil, 1, 0.6, cfg, fixed(1), spec)
		expect(timer).toBe(20)
	end)
	it("jitter stays within base +- spread", function()
		expect(AudioLogic.jitter(1, 0.1, fixed(0))).toBe(0.9)
		expect(AudioLogic.jitter(1, 0.1, fixed(1))).toBe(1.1)
	end)
	it("pick covers the whole list and nil for an empty one", function()
		expect(AudioLogic.pick({ "a", "b", "c" }, fixed(0))).toBe("a")
		expect(AudioLogic.pick({ "a", "b", "c" }, fixed(0.99))).toBe("c")
		expect(AudioLogic.pick({ "a", "b", "c" }, fixed(1))).toBe("c")
		expect(AudioLogic.pick({}, fixed(0.5))).toBe(nil)
	end)
end)
