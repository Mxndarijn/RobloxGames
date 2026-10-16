--!strict
--[[
	SlimeLod (FEATURES.SlimeLod): level of detail for the code-driven slime
	motion (SlimeMotor), on top of SlimeLife.select's cap and on-screen check.

	  SlimeLod.readQuality(settings) -> number?   saved graphics level, nil = unknown
	  SlimeLod.radii(cfg, level) -> near, mid     studs; the *_LOW radii at low quality
	  SlimeLod.tierFor(cfg, level, distance, prev) -> "near" | "mid" | "far"
	  SlimeLod.due(tier, frame, slot, cfg) -> boolean   write this frame?

	near = full motion every frame; mid = squish only, smaller, every
	cfg.MID_EVERY frames (staggered by `slot`); far = reset once, then skipped.
	Pure and allocation-free: `cfg` is Config.SLIME_LOD.
]]

local SlimeLod = {}

export type Tier = "near" | "mid" | "far"
export type Cfg = {
	NEAR: number,
	MID: number,
	NEAR_LOW: number,
	MID_LOW: number,
	LOW_QUALITY_MAX: number,
	MID_EVERY: number,
	MID_AMPLITUDE: number,
	HYSTERESIS: number,
}

-- `settings` = UserSettings():GetService("UserGameSettings") (or a mock). SavedQualityLevel is a
-- QualityLevel enum item (.Value 0 = Automatic, 1..21) or a plain number; any failure reads as unknown.
function SlimeLod.readQuality(settings: any): number?
	local ok, level = pcall(function()
		return settings.SavedQualityLevel
	end)
	if not ok then
		return nil
	end
	if type(level) ~= "number" then
		local okValue, value = pcall(function()
			return (level :: any).Value
		end)
		level = if okValue then value else nil
	end
	return if type(level) == "number" and level == level then level else nil
end

function SlimeLod.isLow(cfg: Cfg, level: number?): boolean
	return level ~= nil and level >= 1 and level <= cfg.LOW_QUALITY_MAX
end

function SlimeLod.radii(cfg: Cfg, level: number?): (number, number)
	if SlimeLod.isLow(cfg, level) then
		return cfg.NEAR_LOW, cfg.MID_LOW
	end
	return cfg.NEAR, cfg.MID
end

-- `prev` (the slime's last tier) widens the radius it is already inside by HYSTERESIS,
-- so a slime on a border doesn't flip tier at every selection.
function SlimeLod.tierFor(cfg: Cfg, level: number?, distance: number, prev: Tier?): Tier
	local near, mid = SlimeLod.radii(cfg, level)
	local keep = 1 + cfg.HYSTERESIS
	if distance ~= distance then
		return "far"
	end
	if distance <= (if prev == "near" then near * keep else near) then
		return "near"
	end
	if distance <= (if prev == "near" or prev == "mid" then mid * keep else mid) then
		return "mid"
	end
	return "far"
end

function SlimeLod.due(tier: Tier, frame: number, slot: number, cfg: Cfg): boolean
	if tier == "near" then
		return true
	elseif tier == "mid" then
		return (frame + slot) % cfg.MID_EVERY == 0
	end
	return false
end

return SlimeLod
