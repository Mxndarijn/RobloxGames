--!strict
--[[
	LabelFit (pure)

	Screen-size maths for labels in the 3D world (BillboardGui / SurfaceGui). See
	guides/roblox-world-labels.md for how to choose a label's size and MaxDistance.

	    LabelFit.pxPerStud(viewportHeight, fov, distance)  -- on-screen px one stud covers
	    LabelFit.readDistance(textStuds, viewportHeight)   -- how far a text line stays readable
	    LabelFit.pxScale(viewportHeight)                   -- shrink factor for pixel tags on small screens
	    LabelFit.maxDistance(desktop, phone, viewportHeight)

	Every function takes an optional `options` table merged over `LabelFit.DEFAULTS`.
]]

local LabelFit = {}

export type Options = {
	referenceHeightPx: number?, -- viewport height a pixel tag is designed for (pxScale 1)
	minPxScale: number?, -- a pixel tag never shrinks below this fraction
	smallViewportPx: number?, -- a viewport shorter than this counts as a phone
	fovDegrees: number?, -- vertical field of view when the caller has no camera
	readablePx: number?, -- a text box at least this tall on screen reads
}

LabelFit.DEFAULTS = table.freeze({
	referenceHeightPx = 720,
	minPxScale = 0.6,
	smallViewportPx = 500,
	fovDegrees = 70,
	readablePx = 14,
})

local function opt(options: Options?, key: string): number
	local value = if options then (options :: any)[key] else nil
	return if type(value) == "number" then value else (LabelFit.DEFAULTS :: any)[key]
end

-- Screen px one stud covers at `distance` studs from a camera with vertical field of view `fovDegrees`
-- on a viewport `viewportHeight` px tall.
function LabelFit.pxPerStud(viewportHeight: number, fovDegrees: number, distance: number): number
	local d = math.max(distance, 1e-3)
	return viewportHeight / (2 * d * math.tan(math.rad(fovDegrees) / 2))
end

-- The farthest distance (studs) at which a text box `textStuds` tall still covers `readablePx` on screen.
function LabelFit.readDistance(textStuds: number, viewportHeight: number, options: Options?): number
	local fov = opt(options, "fovDegrees")
	return textStuds * viewportHeight / (2 * math.tan(math.rad(fov) / 2) * opt(options, "readablePx"))
end

-- Whether a viewport `viewportHeight` px tall is phone-sized.
function LabelFit.isSmall(viewportHeight: number, options: Options?): boolean
	return viewportHeight < opt(options, "smallViewportPx")
end

-- How much a pixel tag's pixels shrink on a viewport `viewportHeight` px tall, so it takes the same share of a
-- phone's screen as of the reference screen (never below minPxScale, never above 1).
function LabelFit.pxScale(viewportHeight: number, options: Options?): number
	return math.clamp(viewportHeight / opt(options, "referenceHeightPx"), opt(options, "minPxScale"), 1)
end

-- MaxDistance for a viewport `viewportHeight` px tall: `phone` (when given) on a phone-sized one, else `desktop`.
function LabelFit.maxDistance(desktop: number, phone: number?, viewportHeight: number, options: Options?): number
	if phone and LabelFit.isSmall(viewportHeight, options) then
		return phone
	end
	return desktop
end

-- Marks a BillboardGui for LabelFitView (the client fitter): its pixels shrink on a phone, and `phoneDistance`
-- (when given) is its MaxDistance there. `keepSize` keeps the pixels and only applies the distance. Works on
-- any side; a server-built tag replicates its tag and attributes.
LabelFit.TAG = "LabelFit"
LabelFit.PHONE_DISTANCE = "LabelFitPhoneDistance" -- number attribute
LabelFit.KEEP_SIZE = "LabelFitKeepSize" -- bool attribute

export type Mark = { phoneDistance: number?, keepSize: boolean? }

function LabelFit.mark(gui: any, mark: Mark?)
	gui:AddTag(LabelFit.TAG)
	if mark and mark.phoneDistance then
		gui:SetAttribute(LabelFit.PHONE_DISTANCE, mark.phoneDistance)
	end
	if mark and mark.keepSize then
		gui:SetAttribute(LabelFit.KEEP_SIZE, true)
	end
end

-- A pixel size (`x`, `y`) scaled by `k`, rounded to whole px.
function LabelFit.scalePx(x: number, y: number, k: number): (number, number)
	return math.floor(x * k + 0.5), math.floor(y * k + 0.5)
end

return table.freeze(LabelFit)
