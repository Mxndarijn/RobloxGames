--!strict
--[[
	Sounds

	Maps the `Notify` sound names from CONTRACT.md to asset ids. Pure (no
	Roblox APIs, no requires), so it loads unchanged in the client and under
	Lune (tests/ui/Sounds.spec.luau).

	The ids are free, public-domain Creator Store sounds: classic Roblox library
	SFX, the Roblox-licensed APM / Pro Sound Effects libraries and a few
	community uploads. The commented ones were checked to load in Studio.
]]

local Sounds = {}

Sounds.IDS = table.freeze({
	Alarm = "rbxassetid://129496339606661", -- siren alarm
	Grab = "rbxassetid://12221967",
	Stolen = "rbxassetid://9045131605", -- APM "Red Handed - Hit3" sneaky sting
	Escape = "rbxassetid://12222216",
	Slap = "rbxassetid://132937320140224", -- cartoon bonk
	Lock = "rbxassetid://9116324156", -- Pro Sound Effects key in lock + jingle
	Unlock = "rbxassetid://12222095",
	Merge = "rbxassetid://12222124",
	Cash = "rbxassetid://12222140",
	Deposit = "rbxassetid://12222152",
	Rain = "rbxassetid://9120733724", -- Pro Sound Effects rising airy whoosh
	Rebirth = "rbxassetid://1840076509", -- APM "Through the Roof (sting)"
	-- Free Creator Store sounds, each its own so the big moments don't sound like a cash ring.
	Rare = "rbxassetid://4612374036", -- bling_big_diamond_pickup (2.0 s)
	Goal = "rbxassetid://4612373884", -- Achievement_unlocked ding (0.2 s)
	Secret = "rbxassetid://71491555548135", -- Skybound_Gacha_GlowUp (1.9 s)
	-- v22 PvP feel (FEATURES.PvP, docs/PVP.md): Roblox-created public-domain library sounds.
	PvpHit = "rbxassetid://12222046", -- hit.wav
	PvpCollide = "rbxassetid://12221984", -- collide.wav
	PvpGoo = "rbxassetid://12222152", -- splat.wav
	PvpSquirt = "rbxassetid://12222103", -- Rubber band sling shot.wav
	PvpBoing = "rbxassetid://12222124", -- Short spring sound.wav
	PvpPop = "rbxassetid://12221996", -- flashbulb.wav
	PvpSqueak = "rbxassetid://9125994570", -- Pro Sound Effects rubber squeeze toy
	PvpFirework = "rbxassetid://12222065", -- Launching rocket.wav
	PvpBubble = "rbxassetid://12222054", -- Kerplunk.wav
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
