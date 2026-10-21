--!strict
--[[
	HomePlotMarker (pure)

	Shows the local player where their own plot is (client only, see
	client/HomePlotMarker): a light beacon over the plot, a glowing floor rim,
	a "YOUR PLOT" tag with the player's avatar and an edge-of-screen arrow
	while the plot is off screen. This module holds the look numbers and the
	math; it touches no Roblox API.

	HomePlotMarker.ownPlot(plots, userId) -> index?
	HomePlotMarker.pastEdge(dx, dz, halfX, halfZ) -> studs outside the plot floor (0 = on it)
	HomePlotMarker.fade(pastEdge) -> 0..1                 -- 0 = hidden (standing on the plot)
]]

export type PlotInfo = { index: number, owner: any }
export type Insets = { left: number, right: number, top: number, bottom: number }

local HomePlotMarker = {}

HomePlotMarker.COLOR = table.freeze({ 126, 217, 87 }) -- Widgets.Theme.Good: "yours" (red stays for thieves)
HomePlotMarker.BEACON_HEIGHT = 220 -- studs above the plot floor
HomePlotMarker.BEACON_WIDTH = 4 -- bright core
HomePlotMarker.HALO_WIDTH = 11 -- soft glow around the core
HomePlotMarker.TAG_HEIGHT = 30 -- "YOUR PLOT" tag, studs above the floor
HomePlotMarker.RIM_WIDTH = 2 -- floor rim strip width, studs
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

-- Flat studs from a point to the plot floor rectangle. `dx`, `dz` = the point in the
-- floor's own axes, relative to its centre; `halfX`, `halfZ` = half the floor size.
-- 0 anywhere on the floor, corners included.
function HomePlotMarker.pastEdge(dx: number, dz: number, halfX: number, halfZ: number): number
	local ox = math.max(math.abs(dx) - halfX, 0)
	local oz = math.max(math.abs(dz) - halfZ, 0)
	return math.sqrt(ox * ox + oz * oz)
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
