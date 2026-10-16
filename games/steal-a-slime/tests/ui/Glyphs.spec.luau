--!strict
-- Every non-ASCII codepoint in src/ui string literals must be on the
-- allowlist of glyphs seen rendering in PC-watcher frames (or any
-- supplementary-plane emoji). U+2630 (the old nav toggle) drew tofu.
local Icons = require("../../src/ui/Icons")
local Nav = require("../../src/ui/Nav")
local TestRunner = require("../TestRunner")
local fs = require("@lune/fs")

local describe, it, expect = TestRunner.describe, TestRunner.it, TestRunner.expect

-- BMP glyphs proven (or plain-text-safe) in frames.
local ALLOWED: { [number]: boolean } = {
	[0xB7] = true, -- middle dot
	[0x2192] = true, -- arrow (Speed 16 -> 22, seen in shop frame)
	[0x2605] = true, -- black star
	[0x2B50] = true, -- star emoji
	[0x267B] = true, -- recycle
	[0x23F1] = true, -- stopwatch
	[0x2B06] = true, -- up arrow emoji
	[0x26F2] = true, -- fountain
	[0x26A1] = true, -- high voltage
	[0x2705] = true, -- check mark button
	[0x2728] = true, -- sparkles
}
-- U+FE0F is only valid after these emoji bases (as in the proven recycle icon).
local VS16_BASES: { [number]: boolean } = { [0x267B] = true, [0x23F1] = true, [0x2B06] = true, [0x1F590] = true }

local function stripComments(src: string): string
	src = string.gsub(src, "%-%-%[%[.-%]%]", "")
	src = string.gsub(src, "%-%-[^\n]*", "")
	return src
end

local function bad(src: string): { string }
	local out = {}
	local prev = 0
	for _, cp in utf8.codes(src) do
		if cp < 0x80 then
			prev = cp
			continue
		end
		local ok = ALLOWED[cp] or (cp >= 0x1F300 and cp <= 0x1FAFF and cp ~= 0x1F3FB)
		if cp == 0xFE0F then
			ok = VS16_BASES[prev]
		end
		if not ok then
			table.insert(out, string.format("U+%04X", cp))
		end
		prev = cp
	end
	return out
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
			local found = bad(stripComments(fs.readFile(path)))
			expect(`{path}: {table.concat(found, ",")}`).toBe(`{path}: `)
		end
	end)
	it("rejects the tofu glyphs it exists to catch", function()
		expect(#bad("\u{2630}")).toBe(1)
		expect(#bad("\u{200D}")).toBe(1)
		expect(#bad("\u{1F468}\u{200D}\u{1F4BB}")).toBe(1)
		expect(#bad("\u{2500}\u{2190}\u{25C0}")).toBe(3)
		expect(#bad("x\u{FE0F}")).toBe(1)
		expect(#bad("\u{267B}\u{FE0F}")).toBe(0)
	end)
	it("HUD chrome icons and nav badges are safe", function()
		for _, v in { Icons.NAV_COLLAPSED, Icons.NAV_EXPANDED, Icons.FAV_ON, Icons.FAV_OFF } do
			expect(#bad(v)).toBe(0)
		end
		for _, entry in Nav.ENTRIES do
			expect(#bad(entry.icon)).toBe(0)
		end
	end)
end)
