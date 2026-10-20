--!strict
--[[
	GuideTrail (pure)

	Lays out the arrows of a ground trail along a route. The route is a list
	of points from the player to the target (a straight line is two points,
	a pathfinding route has more). Arrows sit every `spacing` studs, shifted
	forward by `phase` so the trail scrolls toward the target. Each arrow
	gets an alpha (1 = fully shown) that fades it in near the player and
	out near the end of the trail.

	The trail stops `endGap` studs before the target, so it never covers
	the target or its prompt, and shows at most `maxLength` studs and
	`maxCount` arrows. Heights are interpolated along the route; the Roblox
	adapter snaps each arrow to the ground afterwards.

	  GuideTrail.layout(route, phase, options?) -> { Arrow }
	  GuideTrail.advance(phase, dt, options?) -> phase   (scroll, wraps at spacing)
	  GuideTrail.length(route) -> number
]]

export type Point = { x: number, y: number, z: number }
export type Arrow = {
	x: number,
	y: number,
	z: number,
	dirX: number, -- unit direction on the ground plane the arrow points along
	dirZ: number,
	alpha: number, -- 0..1
	distance: number, -- studs from the start of the route
}
export type Options = {
	spacing: number?,
	maxLength: number?,
	maxCount: number?,
	startGap: number?, -- no arrows closer than this to the player
	endGap: number?,
	fadeIn: number?,
	fadeOut: number?,
	speed: number?, -- studs per second for `advance`
}

local GuideTrail = {}

GuideTrail.DEFAULTS = table.freeze({
	spacing = 4,
	maxLength = 120,
	maxCount = 30,
	startGap = 2,
	endGap = 6,
	fadeIn = 6,
	fadeOut = 8,
	speed = 6,
})

local function option(options: Options?, name: string): number
	local value = if options then (options :: any)[name] else nil
	return if type(value) == "number" then value else (GuideTrail.DEFAULTS :: any)[name]
end

local function segmentLength(a: Point, b: Point): number
	local dx, dy, dz = b.x - a.x, b.y - a.y, b.z - a.z
	return math.sqrt(dx * dx + dy * dy + dz * dz)
end

function GuideTrail.length(route: { Point }): number
	local total = 0
	for i = 2, #route do
		total += segmentLength(route[i - 1], route[i])
	end
	return total
end

function GuideTrail.advance(phase: number, dt: number, options: Options?): number
	local spacing = option(options, "spacing")
	return (phase + dt * option(options, "speed")) % spacing
end

function GuideTrail.layout(route: { Point }, phase: number, options: Options?): { Arrow }
	local arrows: { Arrow } = {}
	if #route < 2 then
		return arrows
	end
	local spacing = math.max(option(options, "spacing"), 0.1)
	local startGap = option(options, "startGap")
	local fadeIn = option(options, "fadeIn")
	local fadeOut = option(options, "fadeOut")
	local maxCount = option(options, "maxCount")
	local stop = math.min(GuideTrail.length(route) - option(options, "endGap"), option(options, "maxLength"))
	if stop <= startGap then
		return arrows
	end

	local index = 2 -- current segment is route[index - 1] -> route[index]
	local segmentStart = 0 -- route distance where that segment starts
	local s = startGap + (phase % spacing)
	while s <= stop and #arrows < maxCount do
		local a, b = route[index - 1], route[index]
		local len = segmentLength(a, b)
		while s > segmentStart + len and index < #route do
			segmentStart += len
			index += 1
			a, b = route[index - 1], route[index]
			len = segmentLength(a, b)
		end
		local t = if len > 0 then math.clamp((s - segmentStart) / len, 0, 1) else 0
		local dx, dz = b.x - a.x, b.z - a.z
		local flat = math.sqrt(dx * dx + dz * dz)
		if flat > 1e-6 then
			local fade = math.min(
				if fadeIn > 0 then (s - startGap) / fadeIn else 1,
				if fadeOut > 0 then (stop - s) / fadeOut else 1,
				1
			)
			table.insert(arrows, {
				x = a.x + (b.x - a.x) * t,
				y = a.y + (b.y - a.y) * t,
				z = a.z + (b.z - a.z) * t,
				dirX = dx / flat,
				dirZ = dz / flat,
				alpha = math.clamp(fade, 0, 1),
				distance = s,
			})
		end
		s += spacing
	end
	return arrows
end

return table.freeze(GuideTrail)
