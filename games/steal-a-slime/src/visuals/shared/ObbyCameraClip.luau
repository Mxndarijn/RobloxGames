--!strict
--[[
	ObbyCameraClip (pure, no Roblox API at load time)

	Roblox's camera only stops at parts that collide, so it would slide into the obby's non-collide course parts (the lava
	floors) and, from inside a part, show straight through it. visuals/client/ObbyCameraGuard stops the camera in
	front of those parts each frame, the way a wall already stops it. Tunables are Config.OBBY.CAMERA_CLIP.

	  ObbyCameraClip.blocks(sx, sy, sz, transparency) -> boolean
	      whether a non-collide part of this size and transparency stops the camera: thick enough on every side, a big
	      enough largest face and not too see-through (keys, blobs, banners and zones don't)
	  ObbyCameraClip.entry(ox, oy, oz, dx, dy, dz, hx, hy, hz) -> number?
	      where the segment from o to o + d enters a box with half sizes h centred on the origin (all in the box's own
	      space), as a fraction of d in [0, 1]; nil when it misses the box or o is already inside it (the runner
	      stands in it, so it doesn't stop the camera)
	  ObbyCameraClip.distance(length, t) -> number
	      the camera's new distance from its focus when the segment of `length` enters a part at `t`: MARGIN in front
	      of the face, never below 0
]]

local Config = if script then require(script.Parent.Parent.Shared.Config) else require("../../shared/Config")

local ObbyCameraClip = {}

local TUNE = Config.OBBY.CAMERA_CLIP

function ObbyCameraClip.blocks(sx: number, sy: number, sz: number, transparency: number): boolean
	if transparency >= TUNE.MAX_TRANSPARENCY then
		return false
	end
	if math.min(sx, sy, sz) < TUNE.MIN_THICK then
		return false
	end
	return math.max(sx * sy, sy * sz, sx * sz) >= TUNE.MIN_FACE
end

function ObbyCameraClip.entry(
	ox: number,
	oy: number,
	oz: number,
	dx: number,
	dy: number,
	dz: number,
	hx: number,
	hy: number,
	hz: number
): number?
	if math.abs(ox) <= hx and math.abs(oy) <= hy and math.abs(oz) <= hz then
		return nil
	end
	local enter, leave = 0, 1
	for _, axis in { { ox, dx, hx }, { oy, dy, hy }, { oz, dz, hz } } do
		local o, d, h = axis[1], axis[2], axis[3]
		if math.abs(d) < 1e-9 then
			if math.abs(o) > h then
				return nil
			end
		else
			local a, b = (-h - o) / d, (h - o) / d
			if a > b then
				a, b = b, a
			end
			enter = math.max(enter, a)
			leave = math.min(leave, b)
			if enter > leave then
				return nil
			end
		end
	end
	return enter
end

function ObbyCameraClip.distance(length: number, t: number): number
	return math.max(length * math.clamp(t, 0, 1) - TUNE.MARGIN, 0)
end

return table.freeze(ObbyCameraClip)
