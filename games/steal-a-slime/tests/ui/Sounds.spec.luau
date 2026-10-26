--!strict
-- Sound name -> asset id mapping (src/ui/Sounds.luau).
local Sounds = require("../../src/ui/Sounds")
local TestRunner = require("../TestRunner")

local describe, it, expect = TestRunner.describe, TestRunner.it, TestRunner.expect

-- Every name Sounds.IDS maps: the `Notify` sound names in CONTRACT.md plus the client's own cue names.
local CONTRACT_NAMES = {
	"Alarm",
	"Grab",
	"Stolen",
	"Escape",
	"Slap",
	"Lock",
	"Unlock",
	"Merge",
	"MergeSparkle",
	"Cash",
	"CashSnap",
	"CashRegister",
	"Deposit",
	"Rain",
	"Rebirth",
	"Rare",
	"Goal",
	"Secret",
	"ErrorSoft",
	"Announce",
	"WeeklyEvent",
	"DailyReward",
	"Gift",
	"LevelUp",
	"PadUnlock",
	"Bag",
	"Denied",
	"BossWarn",
	"BossWindup",
	"BossSlam",
	"BossGoo",
	"BossHit1",
	"BossHit2",
	"BossDefeat",
	"BossMvp",
	"EggWobble",
	"EggCrack",
	"EggHatch",
	"EggReady",
	"RitualDone",
	"RitualSpot",
	"DexNew",
	"JarFill",
	"DespawnPoof",
	"MenuOpen",
	"MenuClose",
	"TutorialTick",
	"SlimeSquish1",
	"SlimeSquish2",
	"SlimeSquish3",
	"SlimeSquishLib",
	"SlimeBlip1",
	"SlimeBlip2",
	"SlimeBlip3",
	"SlimePickup",
	"SlimePutdown",
	"Thunder1",
	"Thunder2",
	"Thunder3",
	"StepGrass1",
	"StepGrass2",
	"StepGrass3",
	"StepSnow1",
	"StepSnow2",
	"PvpHit",
	"PvpCollide",
	"PvpGoo",
	"PvpGooLib",
	"PvpSquirt",
	"PvpBoing",
	"PvpBoingLib",
	"PvpPop",
	"PvpSqueak",
	"PvpFirework",
	"PvpBubble",
	"PvpDisco",
}

-- Client-only cues that stay silent until their own file is uploaded (no library sound fits them).
local SILENT_UNTIL_UPLOADED = {
	"EggWobble",
	"JarFill",
	"MenuOpen",
	"MenuClose",
	"SlimeBlip1",
	"SlimeBlip2",
	"SlimeBlip3",
}

local function isAssetId(id: any): boolean
	return type(id) == "string" and string.match(id, "^rbxassetid://%d+$") ~= nil
end

describe("Sounds.resolve", function()
	it("resolves every name to a numeric rbxassetid, apart from the cues that wait for an upload", function()
		for _, name in CONTRACT_NAMES do
			local id = Sounds.resolve(name)
			if table.find(SILENT_UNTIL_UPLOADED, name) then
				expect(id == nil or isAssetId(id)).toBe(true)
			else
				expect(isAssetId(id)).toBe(true)
			end
		end
	end)
	it("maps exactly the CONTRACT list", function()
		local count = 0
		for name in Sounds.IDS do
			count += 1
			expect(table.find(CONTRACT_NAMES, name) ~= nil).toBe(true)
		end
		expect(count).toBe(#CONTRACT_NAMES)
	end)
	it("only a cue waiting for an upload has neither an id nor a fallback", function()
		for name, id in Sounds.IDS do
			if id == "" and Sounds.FALLBACK[name] == nil then
				expect(table.find(SILENT_UNTIL_UPLOADED, name) ~= nil).toBe(true)
			end
		end
	end)
	it("plays the fallback's id for a sound that is not uploaded yet", function()
		for name, target in Sounds.FALLBACK do
			if Sounds.IDS[name] == "" then
				expect(Sounds.resolve(name)).toBe(Sounds.resolve(target))
			else
				expect(Sounds.resolve(name)).toBe(Sounds.IDS[name])
			end
		end
	end)
	it("follows a fallback chain to a real id", function()
		-- CashRegister falls back to Cash, which falls back to CashSnap while both are pending.
		if Sounds.IDS.CashRegister == "" and Sounds.IDS.Cash == "" then
			expect(Sounds.resolve("CashRegister")).toBe(Sounds.IDS.CashSnap)
		end
		expect(isAssetId(Sounds.resolve("CashRegister"))).toBe(true)
	end)
	it("uses the sound's own id once it is uploaded", function()
		expect(Sounds.resolve("Alarm")).toBe(Sounds.IDS.Alarm)
	end)
	it("passes raw rbxassetid strings through", function()
		expect(Sounds.resolve("rbxassetid://123456")).toBe("rbxassetid://123456")
	end)
	it("returns nil for nil, unknown names and malformed ids", function()
		expect(Sounds.resolve(nil)).toBe(nil)
		expect(Sounds.resolve("Nope")).toBe(nil)
		expect(Sounds.resolve("rbxassetid://abc")).toBe(nil)
		expect(Sounds.resolve(42)).toBe(nil)
	end)
end)

describe("Sounds tables", function()
	local function known(name: any): boolean
		return type(name) == "string" and Sounds.IDS[name] ~= nil
	end
	it("FALLBACK keys and targets are known names", function()
		for name, target in Sounds.FALLBACK do
			expect(known(name)).toBe(true)
			expect(known(target)).toBe(true)
			expect(name ~= target).toBe(true)
		end
	end)
	it("LAYERS and VARIANTS only name known sounds", function()
		for name, extras in Sounds.LAYERS do
			expect(known(name)).toBe(true)
			for _, extra in extras do
				expect(known(extra)).toBe(true)
			end
		end
		for _, names in Sounds.VARIANTS do
			expect(#names > 0).toBe(true)
			for _, name in names do
				expect(known(name)).toBe(true)
			end
		end
	end)
	it("TRIM, VOLUME and SPEED keys are known names with sensible values", function()
		for name, seconds in Sounds.TRIM do
			expect(known(name)).toBe(true)
			expect(seconds > 0).toBe(true)
		end
		for name, volume in Sounds.VOLUME do
			expect(known(name)).toBe(true)
			expect(volume > 0 and volume <= 1).toBe(true)
		end
		for name, speed in Sounds.SPEED do
			expect(known(name)).toBe(true)
			expect(speed > 0).toBe(true)
		end
	end)
end)
