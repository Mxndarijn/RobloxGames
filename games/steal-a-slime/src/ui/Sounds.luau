--!strict
--[[
	Sounds

	Maps the `Notify` sound names from CONTRACT.md to asset ids. Pure (no
	Roblox APIs, no requires), so it loads unchanged in the client and under
	Lune (tests/ui/Sounds.spec.luau).

	The ids are classic public Roblox library SFX picked as stand-ins and not
	verified in Studio; Merijn can swap them for final sounds later.
]]

local Sounds = {}

Sounds.IDS = table.freeze({
	Alarm = "rbxassetid://12222242",
	Grab = "rbxassetid://12221967",
	Stolen = "rbxassetid://12222005",
	Escape = "rbxassetid://12222216",
	Slap = "rbxassetid://12222084",
	Lock = "rbxassetid://12222076",
	Unlock = "rbxassetid://12222095",
	Merge = "rbxassetid://12222124",
	Cash = "rbxassetid://12222140",
	Deposit = "rbxassetid://12222152",
	Rain = "rbxassetid://12222200",
	Rebirth = "rbxassetid://12222225",
	-- v13 (CONTRACT §8.6); stand-ins reusing the Rain / Cash sounds.
	Rare = "rbxassetid://12222200",
	Goal = "rbxassetid://12222140",
	-- Secret spawn announcement; stand-in reusing the Rebirth fanfare.
	Secret = "rbxassetid://12222225",
})

-- "Alarm" -> its asset id; raw "rbxassetid://123" passes through; anything
-- else (unknown names, nil, non-strings) -> nil.
function Sounds.resolve(sound: any): string?
	if type(sound) ~= "string" then
		return nil
	end
	if string.match(sound, "^rbxassetid://%d+$") then
		return sound
	end
	return Sounds.IDS[sound]
end

return Sounds
