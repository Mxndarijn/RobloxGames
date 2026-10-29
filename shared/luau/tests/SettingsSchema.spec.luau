--!strict
local SettingsSchema = require("../src/settings/SettingsSchema")
local T = require("../testing/TestRunner")
local describe, it, expect = T.describe, T.it, T.expect

local function schema()
	return SettingsSchema.new({
		{ id = "muted", kind = "toggle", default = false },
		{ id = "music", kind = "slider", default = 0.5, min = 0, max = 1, step = 0.05 },
		{ id = "quality", kind = "choice", default = "full", choices = { "low", "full" } },
	})
end

describe("SettingsSchema", function()
	it("gives every setting its default", function()
		local d = schema():defaults()
		expect(d.muted).toBe(false)
		expect(d.music).toBe(0.5)
		expect(d.quality).toBe("full")
	end)

	it("cleans a saved table: keeps good values, defaults junk, drops unknown keys", function()
		local v = schema():clean({ muted = true, music = "loud", quality = "ultra", extra = 1 })
		expect(v.muted).toBe(true)
		expect(v.music).toBe(0.5)
		expect(v.quality).toBe("full")
		expect(v.extra).toBe(nil)
	end)

	it("cleans a non-table to the defaults", function()
		expect(schema():clean(nil).music).toBe(0.5)
		expect(schema():clean("x").muted).toBe(false)
	end)

	it("clamps sliders and snaps them to the step", function()
		local s = schema()
		expect(s:clean({ music = 2 }).music).toBe(1)
		expect(s:clean({ music = -1 }).music).toBe(0)
		expect(s:clean({ music = 0.33 }).music).toBe(0.35)
		expect(s:clean({ music = 0 / 0 }).music).toBe(0.5)
		expect(s:clean({ music = math.huge }).music).toBe(0.5)
	end)

	it("parses valid client changes and refuses anything else", function()
		local s = schema()
		local ok = s:parse({ muted = true, quality = "low" }) :: any
		expect(ok.muted).toBe(true)
		expect(ok.quality).toBe("low")
		expect(s:parse({ unknown = true })).toBe(nil)
		expect(s:parse({ muted = "yes" })).toBe(nil)
		expect(s:parse({ quality = "ultra" })).toBe(nil)
		expect(s:parse({ [1] = true })).toBe(nil)
		expect(s:parse("muted")).toBe(nil)
	end)

	it("refuses more entries than there are settings", function()
		local s = schema()
		expect(type(s:parse({ muted = true, music = 0.1, quality = "low" }))).toBe("table")
		local big: { [string]: any } = { muted = true, music = 0.1, quality = "low" }
		for i = 1, 10 do
			big["x" .. i] = true
		end
		expect(s:parse(big)).toBe(nil)
	end)

	it("applies changes and lists what changed", function()
		local s = schema()
		local next, changed = s:apply(s:defaults(), { muted = true, quality = "full" })
		expect(next.muted).toBe(true)
		expect(#changed).toBe(1)
		expect(changed[1]).toBe("muted")
	end)

	it("compares clean values", function()
		local s = schema()
		expect(s:equal({ music = 0.5 }, s:defaults())).toBe(true)
		expect(s:equal({ muted = true }, s:defaults())).toBe(false)
	end)

	it("returns nil for an unknown id and the default for a bad value", function()
		local s = schema()
		expect(s:value("nope", true)).toBe(nil)
		expect(s:value("muted", 3)).toBe(false)
		expect(s:value("quality", "low")).toBe("low")
	end)

	it("refuses a bad schema", function()
		expect(function()
			SettingsSchema.new({ { id = "a", kind = "toggle", default = 1 } } :: any)
		end).toThrow()
		expect(function()
			SettingsSchema.new({ { id = "a", kind = "slider", default = 0, min = 1, max = 0 } } :: any)
		end).toThrow()
		expect(function()
			SettingsSchema.new({
				{ id = "a", kind = "toggle", default = true },
				{ id = "a", kind = "toggle", default = true },
			})
		end).toThrow()
		expect(function()
			SettingsSchema.new({ { id = "a", kind = "choice", default = "x", choices = {} } } :: any)
		end).toThrow()
	end)
end)
