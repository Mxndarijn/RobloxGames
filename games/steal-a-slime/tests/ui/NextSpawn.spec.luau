--!strict
-- Next-event HUD chip (src/ui/NextSpawn.luau): countdown math from server-time attributes.
local Constants = require("../../src/shared/Constants")
local LayoutAssert = require("./LayoutAssert")
local MenuState = require("../../src/ui/MenuState")
local NextSpawn = require("../../src/ui/NextSpawn")
local TestRunner = require("../TestRunner")

local describe, it, expect = TestRunner.describe, TestRunner.it, TestRunner.expect

describe("NextSpawn.chip", function()
	it("picks the sooner of rain and boss", function()
		local rain = NextSpawn.chip(false, 1000 + 125, 1000 + 400, 1000) :: NextSpawn.Info
		expect(rain.kind).toBe("rain")
		expect(rain.seconds).toBe(125)
		expect(rain.text).toBe("🌧 Slime Rain in 2:05")
		local boss = NextSpawn.chip(false, 1000 + 900, 1000 + 61, 1000) :: NextSpawn.Info
		expect(boss.kind).toBe("boss")
		expect(boss.text).toBe("👑 Boss Slime in 1:01")
	end)
	it("is the same for a late joiner: only the server times and now matter", function()
		local a = NextSpawn.chip(false, nil, 5000, 4000) :: NextSpawn.Info
		local b = NextSpawn.chip(false, nil, 5000, 4990) :: NextSpawn.Info
		expect(a.seconds).toBe(1000)
		expect(b.seconds).toBe(10)
	end)
	it("ignores past, missing and malformed times", function()
		expect(NextSpawn.chip(false, 10, 20, 100)).toBeNil()
		expect(NextSpawn.chip(false, nil, nil, 100)).toBeNil()
		expect((NextSpawn.chip(false, "soon", 160, 100) :: NextSpawn.Info).kind).toBe("boss")
		expect(NextSpawn.chip(false, 0 / 0, nil, 100)).toBeNil()
	end)
	it("hides while it rains (the rain banner owns that)", function()
		expect(NextSpawn.chip(true, 500, 500, 100)).toBeNil()
	end)
end)

describe("NextSpawn hide rule", function()
	local info = NextSpawn.chip(false, 200, nil, 100)
	it("shows idle, hides behind every menu", function()
		expect(NextSpawn.visible(info, nil)).toBe(true)
		for _, key in LayoutAssert.menuKeys() do
			expect(NextSpawn.visible(info, key)).toBe(false)
			expect(MenuState.bannersVisible(key)).toBe(false)
		end
		expect(NextSpawn.visible(nil, nil)).toBe(false)
	end)
	it("uses a replicated attribute name", function()
		expect(Constants.BOSS_NEXT_AT_ATTRIBUTE).toBe("BossNextAt")
	end)
end)

describe("NextSpawn layout", function()
	for _, entry in LayoutAssert.screens(LayoutAssert.GATE_VIEWPORTS) do
		it(`{entry.label}: the longest chip text fits the banner column, clear of the nav`, function()
			local s = entry.screen
			local Layout = require("../../src/ui/Layout")
			local text = (NextSpawn.chip(false, 100 + 3599, nil, 100) :: NextSpawn.Info).text
			local w, h = Layout.textSize(text, 15, true)
			expect(w + 20 <= s.banners.w).toBe(true)
			expect(Layout.overlaps(Layout.rect(s.banners.x, s.banners.y, s.banners.w, h + 8), s.nav)).toBe(false)
		end)
	end
end)
