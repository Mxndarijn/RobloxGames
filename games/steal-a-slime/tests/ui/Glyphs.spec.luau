--!strict
-- Every non-ASCII codepoint in src/ui string literals must be on the
-- allowlist of glyphs seen rendering in PC-watcher frames (or any
-- supplementary-plane emoji). U+2630 (the old nav toggle) drew tofu.
local Icons = require("../../src/ui/Icons")
local Nav = require("../../src/ui/Nav")
local TestRunner = require("../TestRunner")
local fs = require("@lune/fs")

local describe, it, expect = TestRunner.describe, TestRunner.it, TestRunner.expect

local GlyphCheck = require("./GlyphCheck")
local stripComments, bad = GlyphCheck.stripComments, GlyphCheck.bad

-- "\u{2705}" in a string literal is the same glyph as typing it, so it is checked the same way.
local function decodeEscapes(src: string): string
	return (
		string.gsub(src, "\\u{(%x+)}", function(hex: string): string
			return utf8.char(tonumber(hex, 16) :: number)
		end)
	)
end

local function collect(dir: string, out: { string })
	for _, name in fs.readDir(dir) do
		local path = `{dir}/{name}`
		if fs.isDir(path) then
			collect(path, out)
		elseif string.match(name, "%.luau$") then
			table.insert(out, path)
		end
	end
end

describe("UI glyphs", function()
	it("src/ui source uses only allowlisted non-ASCII codepoints", function()
		local files = {}
		collect("src/ui", files)
		for _, path in files do
			local found = bad(decodeEscapes(stripComments(fs.readFile(path))))
			expect(`{path}: {table.concat(found, ",")}`).toBe(`{path}: `)
		end
	end)
	it("rejects the tofu glyphs it exists to catch", function()
		expect(#bad("\u{2630}")).toBe(1)
		expect(#bad("\u{200D}")).toBe(1)
		expect(#bad("\u{1F468}\u{200D}\u{1F4BB}")).toBe(1)
		expect(#bad("\u{2500}\u{2190}\u{25C0}")).toBe(3)
		expect(#bad("x\u{FE0F}")).toBe(1)
		expect(#bad("\u{2705}\u{2713}\u{2714}")).toBe(3) -- "done" is Widgets.check
		expect(#bad(decodeEscapes("\\u{2705}"))).toBe(1)
		expect(#bad("\u{267B}\u{FE0F}")).toBe(0)
	end)
	it("HUD chrome icons and nav badges are safe", function()
		for _, v in { Icons.FAV_ON, Icons.FAV_OFF } do
			expect(#bad(v)).toBe(0)
		end
		for _, entry in Nav.ENTRIES do
			expect(#bad(entry.icon)).toBe(0)
		end
	end)
end)
