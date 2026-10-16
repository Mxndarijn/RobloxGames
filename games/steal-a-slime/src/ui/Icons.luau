--!strict
--[[
	Icons

	Glyphs for the HUD chrome that are not emoji badges. Roblox fonts have no
	U+2630 (the old nav toggle drew an empty tofu box), so only ASCII or
	glyphs seen rendering in PC-watcher frames go here
	(tests/ui/Glyphs.spec.luau holds the allowlist).
]]

local Icons = {}

Icons.NAV_COLLAPSED = "Menu"
Icons.NAV_EXPANDED = "< Menu"
Icons.FAV_ON = "★"
Icons.FAV_OFF = "+"

return Icons
