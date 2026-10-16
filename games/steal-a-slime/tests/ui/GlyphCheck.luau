--!strict
-- Shared by Glyphs.spec and ItemIcons.spec: the allowlist of non-ASCII codepoints seen rendering in
-- PC-watcher frames, and `bad`, which lists the codepoints of a string that are not on it.
local GlyphCheck = {}

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

function GlyphCheck.stripComments(src: string): string
	src = string.gsub(src, "%-%-%[%[.-%]%]", "")
	src = string.gsub(src, "%-%-[^\n]*", "")
	return src
end

function GlyphCheck.bad(src: string): { string }
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

return GlyphCheck
