--!strict
--[[
	HabitatMorph (pure, FEATURES.Habitats, HABITATS.md "Animation")

	The feel of the pad <-> habitat morph on top of Habitats.stepWeights.
	Weights stay linear 0..1; this maps a look's weight to each prop's scale.

	  HabitatMorph.quality(cfg, reduced, distance, animating)
	                              "full" | "simple" | "snap"
	  HabitatMorph.propScale(q, w, i, n, rising, cfg)
	                              scale of prop i of n at weight w
	  HabitatMorph.burst(cfg, q)  puff particles for a transform (0 = none)
	  HabitatMorph.tint(w)        0..1 pad colour shift toward the habitat accent

	Both ends are exact: propScale(_, 1, ...) == 1 and propScale(_, 0, ...) ==
	FLOOR, so a settled look is the static habitat. No Roblox APIs.
]]

local HabitatMorph = {}

export type Quality = "full" | "simple" | "snap"
export type Cfg = {
	STAGGER: number,
	OVERSHOOT: number,
	BURST_FULL: number,
	BURST_SIMPLE: number,
	MAX_ANIMATING: number,
	SNAP_BEYOND: number,
}

HabitatMorph.FLOOR = 0.05 -- smallest prop scale (parts keep a size)

-- snap: reduced motion, far from the camera, or too many pads already morphing:
-- the change shows its final state at once, no puff. simple: plain ease, small
-- puff. full: staggered rise with overshoot.
function HabitatMorph.quality(cfg: Cfg, reduced: boolean, distance: number?, animating: number): Quality
	if reduced or animating >= cfg.MAX_ANIMATING then
		return "snap"
	end
	if distance and distance > cfg.SNAP_BEYOND then
		return "snap"
	end
	if distance and distance > cfg.SNAP_BEYOND * 0.5 then
		return "simple"
	end
	return "full"
end

local function easeOut(t: number): number
	return 1 - (1 - t) ^ 3
end

local function easeOutBack(t: number, s: number): number
	local u = t - 1
	return 1 + (s + 1) * u ^ 3 + s * u ^ 2
end

-- Prop i of n (1-based) starts at weight STAGGER * (i-1)/(n-1) and reaches full
-- at weight 1, so the last prop is the last up and (same curve, weight falling)
-- the first to go. Overshoot only while rising.
function HabitatMorph.propScale(q: Quality, w: number, i: number, n: number, rising: boolean, cfg: Cfg): number
	if w >= 1 then
		return 1
	end
	local t: number
	if q == "full" then
		local delay = if n > 1 then cfg.STAGGER * (i - 1) / (n - 1) else 0
		t = math.clamp((w - delay) / (1 - delay), 0, 1)
	else
		t = math.clamp(w, 0, 1)
	end
	local e = if q == "full" and rising then easeOutBack(t, cfg.OVERSHOOT) else easeOut(t)
	return HabitatMorph.FLOOR + (1 - HabitatMorph.FLOOR) * e
end

function HabitatMorph.burst(cfg: Cfg, q: Quality): number
	if q == "full" then
		return cfg.BURST_FULL
	elseif q == "simple" then
		return cfg.BURST_SIMPLE
	end
	return 0
end

-- Pad colour shift: the full accent by half way, exactly 0 at weight 0.
function HabitatMorph.tint(w: number): number
	return math.clamp(w * 2, 0, 1)
end

return table.freeze(HabitatMorph)
