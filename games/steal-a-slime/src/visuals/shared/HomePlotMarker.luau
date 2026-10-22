--!strict
--[[
	HomePlotMarker (pure)

	Shows the local player where their own plot is (client only, see
	client/HomePlotMarker): a light beacon over the plot, a glowing ring along
	the round plot floor's edge, a "Your plot" tag (a mint house badge) and an edge-of-screen arrow
	while the plot is off screen. This module holds the look numbers and the
	math; it touches no Roblox API.

	HomePlotMarker.ownPlot(plots, userId) -> index?
	HomePlotMarker.pastEdge(dx, dz, radius) -> studs outside the round plot floor (0 = on it)
	HomePlotMarker.fade(pastEdge) -> 0..1                 -- 0 = hidden (standing on the plot)
	HomePlotMarker.rim(radius) -> { RimSegment }          -- the ring's straight strips
]]

export type PlotInfo = { index: number, owner: any }
export type Insets = { left: number, right: number, top: number, bottom: number }
-- One straight strip of the rim ring: `angle` (radians, round the plot's Y axis, 0 = the plot's -Z side),
-- its centre `mid` studs from the plot centre, `length` studs along the edge.
export type RimSegment = { angle: number, mid: number, length: number }

local HomePlotMarker = {}

HomePlotMarker.COLOR = table.freeze({ 126, 217, 87 }) -- Widgets.Theme.Good: "yours" (red stays for thieves)
HomePlotMarker.BEACON_HEIGHT = 220 -- studs above the plot floor
HomePlotMarker.BEACON_WIDTH = 4 -- bright core
HomePlotMarker.HALO_WIDTH = 11 -- soft glow around the core
HomePlotMarker.TAG_HEIGHT = 30 -- "Your plot" tag, studs above the floor
HomePlotMarker.RIM_WIDTH = 2 -- floor rim ring width, studs
HomePlotMarker.RIM_SEGMENTS = 48 -- straight strips that make up the ring
HomePlotMarker.FADE_BAND = 40 -- studs past the plot edge over which the beacon fades in
-- Arrow box (shared/EdgeArrow), viewport px in from each screen edge: clear of the left button column and the bottom HUD.
HomePlotMarker.EDGE_INSETS = table.freeze({ left = 200, right = 120, top = 110, bottom = 240 })
HomePlotMarker.PULSE_SPEED = 2.4 -- rim / ring pulse, radians per second

-- The plot index the player owns, or nil.
function HomePlotMarker.ownPlot(plots: { PlotInfo }, userId: number): number?
	for _, plot in plots do
		if plot.owner == userId and userId ~= 0 then
			return plot.index
		end
	end
	return nil
end

-- Flat studs from a point to the round plot floor. `dx`, `dz` = the point relative to the
-- floor's centre; `radius` = the floor's radius. 0 anywhere on the floor, its edge included.
function HomePlotMarker.pastEdge(dx: number, dz: number, radius: number): number
	return math.max(math.sqrt(dx * dx + dz * dz) - radius, 0)
end

-- The rim ring along the inside of a round floor of `radius`: RIM_SEGMENTS strips RIM_WIDTH wide whose outer
-- edges meet on the floor's edge (the inner edges overlap a little), so the ring shows no gaps.
function HomePlotMarker.rim(radius: number): { RimSegment }
	local n = HomePlotMarker.RIM_SEGMENTS
	local length = 2 * radius * math.tan(math.pi / n)
	local mid = radius - HomePlotMarker.RIM_WIDTH / 2
	local out = table.create(n)
	for k = 0, n - 1 do
		table.insert(out, { angle = k * 2 * math.pi / n, mid = mid, length = length })
	end
	return out
end

-- How visible the far-away markers are `pastEdge` studs outside the plot:
-- 0 while standing on the plot, rising to 1 over FADE_BAND studs past its edge.
function HomePlotMarker.fade(pastEdge: number): number
	return math.clamp(pastEdge / HomePlotMarker.FADE_BAND, 0, 1)
end

-- Rim / ring pulse 0..1 at time `t`.
function HomePlotMarker.pulse(t: number): number
	return 0.5 + 0.5 * math.sin(t * HomePlotMarker.PULSE_SPEED)
end

return table.freeze(HomePlotMarker)
