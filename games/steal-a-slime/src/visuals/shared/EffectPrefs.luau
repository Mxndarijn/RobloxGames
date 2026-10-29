--!strict
--[[
	EffectPrefs

	How client effects read the player's Visuals settings (Shared.PlayerSettings): reduced motion, "Goo effects"
	Low, camera shake and other players' effects, plus the Low maths (fewer particles, lower emitter rates) and
	which server-made emitters the client dims (visuals/client/EffectsDimmer).

	`player` is anything with GetAttribute (the LocalPlayer on the client, a fake in specs; nil reads the defaults).
	`gui` is GuiService or anything with ReducedMotionEnabled. Pure: reads only what it is handed.
]]

local PlayerSettings = if script
	then require((game:GetService("ReplicatedStorage") :: any).Shared.PlayerSettings)
	else require("../../shared/PlayerSettings")

local EffectPrefs = {}

EffectPrefs.LOW_SCALE = 0.35 -- particle counts and emitter rates are this much of Full on Low
EffectPrefs.FULL_RATE_ATTRIBUTE = "FullRate" -- a dimmed emitter keeps its own Rate here until Full comes back

-- Server-made emitters that replicate to every client: Effects.play holders ("Effect_<kind>"), the parade drain
-- splash and a shining slime's sparkles. Anything else (the boss carry trail, client-made bursts) is left alone.
local DIM_HOLDER_PREFIX = "Effect_"
local DIM_HOLDERS = table.freeze({ DrainSplash = true })
local DIM_EMITTERS = table.freeze({ ShineFx = true })

local function readReduced(gui: any): boolean
	if gui == nil then
		return false
	end
	local ok, on = pcall(function()
		return gui.ReducedMotionEnabled
	end)
	return ok and on == true
end

-- True on "Goo effects: Low", or when the caller's own graphics-quality check says low.
function EffectPrefs.isLow(player: any, qualityLow: boolean?): boolean
	return qualityLow == true or PlayerSettings.get(player, "effects") == "low"
end

-- True when Roblox's own Reduced Motion or the game's setting is on.
function EffectPrefs.reducedMotion(player: any, gui: any?): boolean
	return readReduced(gui) or PlayerSettings.on(player, "reducedMotion")
end

-- True when the camera may shake or zoom: Camera shake on and no reduced motion.
function EffectPrefs.cameraMoves(player: any, gui: any?): boolean
	return PlayerSettings.on(player, "cameraShake") and not EffectPrefs.reducedMotion(player, gui)
end

-- True when other players' effects are drawn.
function EffectPrefs.showOthers(player: any): boolean
	return PlayerSettings.on(player, "othersEffects")
end

-- A burst's particle count: Full as is, Low scaled down but never below 1.
function EffectPrefs.count(count: number, low: boolean): number
	if not low or count <= 0 then
		return count
	end
	return math.max(1, math.floor(count * EffectPrefs.LOW_SCALE + 0.5))
end

-- True for an emitter the server made and the client dims on Low (by its name and its parent's name).
function EffectPrefs.dimmable(emitterName: string, holderName: string?): boolean
	if DIM_EMITTERS[emitterName] then
		return true
	end
	if holderName == nil then
		return false
	end
	return DIM_HOLDERS[holderName] == true or string.sub(holderName, 1, #DIM_HOLDER_PREFIX) == DIM_HOLDER_PREFIX
end

-- An emitter's Rate for the setting: `rate` is its Rate now, `saved` its FULL_RATE_ATTRIBUTE (nil when not dimmed).
-- Returns the Rate to set and the attribute value to keep (nil = clear it).
function EffectPrefs.dim(rate: number, saved: number?, low: boolean): (number, number?)
	if low then
		local full = saved or rate
		return full * EffectPrefs.LOW_SCALE, full
	end
	return saved or rate, nil
end

return table.freeze(EffectPrefs)
