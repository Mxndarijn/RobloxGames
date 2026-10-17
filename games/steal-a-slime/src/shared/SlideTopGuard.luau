--!strict
--[[
	SlideTopGuard (pure)

	Bug #9: the slide's solid fill (SlideColliders, kind "Fill") must not be a place to stand. Its box is topped by a steep
	ridge roof (SlideColliders.ridge / wedge, server/FountainColliders builds two WedgeParts), but a Humanoid climbs anything below 89
	degrees, so the server also moves a character that stays above a fill's footprint. This module is the maths:
	  onTop(specs, x, y, z, groundY)   the Fill spec a root at (x, y, z) is on / over, or nil. "On" = inside the fill's
	                                   oriented footprint, from just under the roof surface up to REACH above it, and the roof
	                                   there at least MIN_RISE over the ground. The ride line / trough (inside the solid, under
	                                   the roof), the ground beside the slide and a low mouth fringe are never "on top".
	  nudge(specs, x, z, cx, cz)       horizontal point just outside every Fill footprint, reached by walking sideways
	                                   (across the slide) from (x, z) on the side away from (cx, cz) (the slide's centre);
	                                   the server finds the ground under it. Never into the trough: the trough is inside
	                                   the footprints.
	No Roblox APIs: runs unchanged under Lune. Specs are SlideColliders specs.
]]

local SlideColliders = if script then require(script.Parent.SlideColliders) else require("./SlideColliders")

type Spec = SlideColliders.Spec

local SlideTopGuard = {}

SlideTopGuard.DWELL = 0.3 -- seconds on top before the server moves the character
SlideTopGuard.INTERVAL = 0.2 -- server check period (5 Hz)
SlideTopGuard.BELOW = 1 -- a root this far under the roof surface still counts as on it (standing root is ~3 over it)
SlideTopGuard.REACH = 10 -- ... and up to this far over it (a jump apex is ~7 + 3)
SlideTopGuard.MIN_RISE = 4 -- the roof must be this far over the ground, else it is just a kerb
SlideTopGuard.STEP = 1 -- studs per sideways step of nudge()
SlideTopGuard.MAX_STEPS = 30
SlideTopGuard.OUT = 3 -- studs clear of the footprint after a nudge

local function frame(spec: Spec): ({ number }, { number }, { number })
	local f = spec.forward
	local len = math.sqrt(f[1] * f[1] + f[3] * f[3])
	local right = { -f[3] / len, 0, f[1] / len }
	local up = {
		right[2] * f[3] - right[3] * f[2],
		right[3] * f[1] - right[1] * f[3],
		right[1] * f[2] - right[2] * f[1],
	}
	return right, up, f
end

-- Horizontal footprint test (y ignored), grown by `grow` studs on every side.
local function inFootprint(spec: Spec, x: number, z: number, grow: number): boolean
	local right, _, f = frame(spec)
	local dx, dz = x - spec.centre[1], z - spec.centre[3]
	local hLen = math.sqrt(f[1] * f[1] + f[3] * f[3]) -- the box's length shrinks by this on the ground
	return math.abs(dx * right[1] + dz * right[3]) < spec.size[1] / 2 + grow
		and math.abs((dx * f[1] + dz * f[3]) / hLen) < spec.size[3] / 2 * hLen + grow
end

function SlideTopGuard.onTop(specs: { Spec }, x: number, y: number, z: number, groundY: number): Spec?
	for _, spec in specs do
		if spec.kind ~= "Fill" then
			continue
		end
		local right, up, f = frame(spec)
		local d = { x - spec.centre[1], y - spec.centre[2], z - spec.centre[3] }
		local lx = d[1] * right[1] + d[3] * right[3]
		local ly = d[1] * up[1] + d[2] * up[2] + d[3] * up[3]
		local lz = d[1] * f[1] + d[2] * f[2] + d[3] * f[3]
		local ridge = SlideColliders.ridge(spec)
		if math.abs(lx) >= ridge.half or math.abs(lz) >= spec.size[3] / 2 then
			continue
		end
		local above = ly + SlideColliders.FILL / 2 -- over the ride line, along the spec's up
		local surface = ridge.base + ridge.rise * (1 - math.abs(lx) / ridge.half) -- box top at the eaves, ridge on the centreline
		local rideY = spec.centre[2] - up[2] * SlideColliders.FILL / 2 + f[2] * lz -- ride line height under the root
		if
			above >= surface - SlideTopGuard.BELOW
			and above <= surface + SlideTopGuard.REACH
			and rideY + up[2] * surface - groundY >= SlideTopGuard.MIN_RISE
		then
			return spec
		end
	end
	return nil
end

-- Where to put a character found on `spec`'s roof: (x, z) outside every Fill footprint, across the slide.
function SlideTopGuard.nudge(
	specs: { Spec },
	spec: Spec,
	x: number,
	z: number,
	cx: number,
	cz: number
): (number, number)
	local right = frame(spec)
	local function clear(px: number, pz: number): boolean
		for _, other in specs do
			if other.kind == "Fill" and inFootprint(other, px, pz, SlideTopGuard.OUT) then
				return false
			end
		end
		return true
	end
	local best: { number }? = nil
	for _, sign in { 1, -1 } do
		for n = 1, SlideTopGuard.MAX_STEPS do
			local px, pz = x + right[1] * sign * n * SlideTopGuard.STEP, z + right[3] * sign * n * SlideTopGuard.STEP
			if clear(px, pz) then
				local away = (px - cx) ^ 2 + (pz - cz) ^ 2 -- prefer the side away from the fountain
				if not best or away > best[3] then
					best = { px, pz, away }
				end
				break
			end
		end
	end
	if best then
		return best[1], best[2]
	end
	return x, z
end

return table.freeze(SlideTopGuard)
