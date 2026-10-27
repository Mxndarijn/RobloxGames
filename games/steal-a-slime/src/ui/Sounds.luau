--!strict
--[[
	Sounds

	Maps sound names (the `Notify` sound names from CONTRACT.md and the client's own cue names) to asset ids.
	Pure (no Roblox APIs, no requires), so it loads unchanged in the client and under Lune
	(tests/ui/Sounds.spec.luau).

	Two sources:
	  * Free, public-domain Creator Store sounds: classic Roblox library SFX, the Roblox-licensed APM /
	    Pro Sound Effects libraries and a few community uploads. Every id here was loaded in a Studio check
	    (TimeLength > 0).
	  * Our own synthesized sounds from shared/audio-kit (manifest.json). Their id stays "" until the file is
	    uploaded; until then the name plays its FALLBACK (or nothing).

	  Sounds.resolve(name)   asset id, following FALLBACK for a not-yet-uploaded sound; raw ids pass through
	  Sounds.TRIM[name]      seconds: stop (with a short fade) after this, for library files with long tails
	  Sounds.LAYERS[name]    extra names played together with it
	  Sounds.VARIANTS[group] names one of which plays (SoundController.playVariant)
]]

local Sounds = {}

Sounds.IDS = table.freeze({
	Alarm = "rbxassetid://129496339606661", -- siren alarm
	Grab = "rbxassetid://87295773843957", -- "SLIME SQUISHY 1", wet slime squish
	Stolen = "rbxassetid://9045131605", -- APM "Red Handed - Hit3" sneaky sting
	Escape = "rbxassetid://12222200", -- swoosh.wav (SPEED: a bit high), the slime zips away
	Slap = "rbxassetid://132937320140224", -- cartoon bonk
	Lock = "rbxassetid://9116324156", -- Pro Sound Effects key in lock + jingle
	Unlock = "rbxassetid://9117060349", -- Pro Sound Effects "Nasa Transmission Beep 2": your lock is gone
	Merge = "rbxassetid://9112872235", -- Pro Sound Effects "Small Bubbles Float Up Pop 7" (+ MergeSparkle)
	MergeSparkle = "rbxassetid://9126073001", -- Pro Sound Effects "Synth Sparkle Bell Ding"
	Cash = "rbxassetid://125468534978868", -- audio-kit coin (fallback: CashSnap)
	CashSnap = "rbxassetid://12222140", -- snap.wav
	CashRegister = "rbxassetid://85324618959424", -- audio-kit cash_register (fallback: Cash)
	Deposit = "rbxassetid://18145114696", -- "cartoon plop sound"
	Rain = "rbxassetid://9120733724", -- Pro Sound Effects rising airy whoosh
	Rebirth = "rbxassetid://1840076509", -- APM "Through the Roof (sting)"
	Rare = "rbxassetid://4612374036", -- bling_big_diamond_pickup (2.0 s)
	Goal = "rbxassetid://4612373884", -- Achievement_unlocked ding (0.2 s)
	Secret = "rbxassetid://71491555548135", -- Skybound_Gacha_GlowUp (1.9 s)
	ErrorSoft = "rbxassetid://105474838693489", -- "UI bubbly_error"
	-- Announcements
	Announce = "rbxassetid://15675043410", -- Roblox_UI_Tonal_Stinger: a server-wide message
	WeeklyEvent = "rbxassetid://1844584807", -- APM "Glamour Fanfare 4"
	DailyReward = "rbxassetid://9045119921", -- APM "Mascot Party - Mnemonic1"
	Gift = "rbxassetid://9125724621", -- Pro Sound Effects paper tear: a code's gift
	LevelUp = "rbxassetid://128973160752596", -- audio-kit level_up (fallback: Goal)
	PadUnlock = "rbxassetid://72655607679334", -- audio-kit pad_unlock (fallback: Goal)
	Bag = "rbxassetid://113114197468370", -- audio-kit bag_pop (fallback: CashSnap)
	Denied = "rbxassetid://119402957317041", -- audio-kit denied (fallback: ErrorSoft)
	-- Boss fight (contract/boss-event.md)
	BossWarn = "rbxassetid://9113891695", -- Pro Sound Effects conch shell horn: the boss is coming
	BossWindup = "rbxassetid://9119031599", -- Pro Sound Effects "Shaft Of Light 1": rising before an attack
	BossSlam = "rbxassetid://9126009582", -- Pro Sound Effects deep impact
	BossGoo = "rbxassetid://9114447775", -- Pro Sound Effects "Fish Flop Gooshy 5": a spit / goo burst lands
	BossHit1 = "rbxassetid://128710847750782", -- "SLIME SQUISHY 2"
	BossHit2 = "rbxassetid://9117284238", -- Pro Sound Effects "Penguins Flop Watery Splatting Impacts 8"
	BossDefeat = "rbxassetid://1845411858", -- APM "Top Prize"
	BossMvp = "rbxassetid://1844692556", -- APM "Game Show"
	-- Eggs, rituals, the Dex
	EggWobble = "rbxassetid://114176839689061", -- audio-kit egg_wobble
	EggCrack = "rbxassetid://9113959343", -- Pro Sound Effects "Crack Egg Crunchy 11"
	EggHatch = "rbxassetid://9116405618", -- Pro Sound Effects "Magic Poofs Short Breathy Bursts Punchy 2"
	EggReady = "rbxassetid://9116395089", -- Pro Sound Effects "Magic Glows Soft Clusters Of Chiming Hits 4"
	RitualDone = "rbxassetid://9116394756", -- Pro Sound Effects "Magic Glows Soft Clusters Of Chiming Hits 3"
	RitualSpot = "rbxassetid://12221996", -- flashbulb.wav (VOLUME: low), a spot gets taken
	DexNew = "rbxassetid://103005200793008", -- audio-kit dex_new (fallback: Goal)
	Lucky = "", -- the Lucky Charm show's chime (contract/lucky-charm.md); not uploaded yet (fallback: MergeSparkle)
	JarFill = "rbxassetid://128015024195428", -- audio-kit jar_fill
	DespawnPoof = "rbxassetid://9125639751", -- Pro Sound Effects "Magic Poofs Short Breathy Bursts Wheezy Exhale"
	-- UI
	MenuOpen = "rbxassetid://74534008739543", -- audio-kit menu_open
	MenuClose = "rbxassetid://84374344660619", -- audio-kit menu_close
	TutorialTick = "rbxassetid://102300657141248", -- audio-kit tutorial_tick (fallback: Goal)
	-- Slimes (3D, at the slime)
	SlimeSquish1 = "rbxassetid://138542773252631", -- audio-kit slime_squish_1..3
	SlimeSquish2 = "rbxassetid://130838086896738",
	SlimeSquish3 = "rbxassetid://87791729719690",
	SlimeSquishLib = "rbxassetid://87295773843957", -- "SLIME SQUISHY 1"
	SlimeBlip1 = "rbxassetid://94777402130166", -- audio-kit slime_blip_1..3
	SlimeBlip2 = "rbxassetid://114873093794765",
	SlimeBlip3 = "rbxassetid://120922882676473",
	SlimePickup = "rbxassetid://83418434676362", -- audio-kit slime_pickup (fallback: Grab)
	SlimePutdown = "rbxassetid://129995905484350", -- audio-kit slime_putdown (fallback: Deposit)
	-- Weather one-shots (SoundController thunder)
	Thunder1 = "rbxassetid://9116282875", -- Pro Sound Effects "Lightning Strike Sharp Hissing Crack 5"
	Thunder2 = "rbxassetid://9116282544", -- ... Crack 1
	Thunder3 = "rbxassetid://9116282791", -- ... Crack 4
	-- Footsteps (WorldAudio, by floor material)
	StepGrass1 = "rbxassetid://129956418693357", -- "footstep grass 1"
	StepGrass2 = "rbxassetid://78534941650081", -- "footstep grass 2"
	StepGrass3 = "rbxassetid://135037154891351", -- "footstep grass 4"
	StepSnow1 = "rbxassetid://96692894596329", -- "Snow Footstep - 1"
	StepSnow2 = "rbxassetid://128551000876862", -- "Snow Footstep - 2"
	-- PvP feel (FEATURES.PvP, docs/PVP.md): Roblox-created public-domain library sounds.
	PvpHit = "rbxassetid://12222046", -- hit.wav
	PvpCollide = "rbxassetid://12221984", -- collide.wav
	PvpGoo = "rbxassetid://72863740720702", -- audio-kit goo_splat (fallback: PvpGooLib)
	PvpGooLib = "rbxassetid://12222152", -- splat.wav
	PvpSquirt = "rbxassetid://12222103", -- Rubber band sling shot.wav
	PvpBoing = "rbxassetid://110041616643369", -- audio-kit boing (fallback: PvpBoingLib)
	PvpBoingLib = "rbxassetid://12222124", -- Short spring sound.wav
	PvpPop = "rbxassetid://12221996", -- flashbulb.wav
	PvpSqueak = "rbxassetid://9125994570", -- Pro Sound Effects rubber squeeze toy
	PvpFirework = "rbxassetid://12222065", -- Launching rocket.wav
	PvpBubble = "rbxassetid://12222054", -- Kerplunk.wav
	PvpDisco = "rbxassetid://9047231371", -- APM "Copacetic - 15" (15 s), Dance Bomb disco bubble
})

-- A sound whose own file is not uploaded yet plays this one instead.
Sounds.FALLBACK = table.freeze({
	Cash = "CashSnap",
	CashRegister = "Cash",
	LevelUp = "Goal",
	PadUnlock = "Goal",
	Bag = "CashSnap",
	Denied = "ErrorSoft",
	DexNew = "Goal",
	Lucky = "MergeSparkle",
	TutorialTick = "Goal",
	SlimeSquish1 = "SlimeSquishLib",
	SlimeSquish2 = "SlimeSquishLib",
	SlimeSquish3 = "SlimeSquishLib",
	SlimePickup = "Grab",
	SlimePutdown = "Deposit",
	PvpGoo = "PvpGooLib",
	PvpBoing = "PvpBoingLib",
})

Sounds.TRIM = table.freeze({
	BossWindup = 1.2,
	BossGoo = 1.0,
	BossWarn = 2.6,
	Gift = 0.8,
	Thunder2 = 7,
	Thunder3 = 7,
})

-- Per-name volume (0..1, default 1) and PlaybackSpeed (default 1).
Sounds.VOLUME = table.freeze({
	RitualSpot = 0.35,
	SlimeSquish1 = 0.55,
	SlimeSquish2 = 0.55,
	SlimeSquish3 = 0.55,
	SlimeSquishLib = 0.45,
	SlimeBlip1 = 0.5,
	SlimeBlip2 = 0.5,
	SlimeBlip3 = 0.5,
	StepGrass1 = 0.45,
	StepGrass2 = 0.45,
	StepGrass3 = 0.45,
	StepSnow1 = 0.5,
	StepSnow2 = 0.5,
	MenuOpen = 0.6,
	MenuClose = 0.6,
	DespawnPoof = 0.6,
})
Sounds.SPEED = table.freeze({
	Escape = 1.25,
	Lucky = 1.2, -- a brighter bell than the merge's
})

Sounds.LAYERS = table.freeze({
	Merge = table.freeze({ "MergeSparkle" }),
	DexNew = table.freeze({ "JarFill" }),
	Lucky = table.freeze({ "Rare" }),
})

Sounds.VARIANTS = table.freeze({
	SlimeSquish = table.freeze({ "SlimeSquish1", "SlimeSquish2", "SlimeSquish3" }),
	SlimeBlip = table.freeze({ "SlimeBlip1", "SlimeBlip2", "SlimeBlip3" }),
	BossHit = table.freeze({ "BossHit1", "BossHit2" }),
	StepGrass = table.freeze({ "StepGrass1", "StepGrass2", "StepGrass3" }),
	StepSnow = table.freeze({ "StepSnow1", "StepSnow2" }),
})

local function valid(id: any): boolean
	return type(id) == "string" and string.match(id, "^rbxassetid://%d+$") ~= nil
end

-- "Alarm" -> its asset id; a name without an uploaded file follows FALLBACK (a few steps at most); raw
-- "rbxassetid://123" passes through; anything else (unknown names, nil, non-strings) -> nil.
function Sounds.resolve(sound: any): string?
	if type(sound) ~= "string" then
		return nil
	end
	if valid(sound) then
		return sound
	end
	local name: string? = sound
	for _ = 1, 4 do
		if name == nil then
			return nil
		end
		local id = Sounds.IDS[name]
		if valid(id) then
			return id
		end
		name = Sounds.FALLBACK[name]
	end
	return nil
end

return Sounds
