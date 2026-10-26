--!strict
--[[
	HomeZone (pure)

	Whether a point is on a plot's home ground: inside the plot's HomeZone part (CONTRACT.md §5.3), given in the
	zone's own frame. The zone is the round plot floor when the part has a `Radius` attribute (every goo jar plot):
	inside that circle on the ground plane. Without one it is the part's box. Height: from 4 studs under the part
	to 8 studs over it, plus the part's `ReachUp` (the upper jar floors).
]]

local HomeZone = {}

HomeZone.BELOW = 4 -- studs under the part's bottom that still count
HomeZone.ABOVE = 8 -- studs over the part's top that still count

-- `x, y, z`: the point in the zone part's frame; `size`: the part's size; `radius` / `reachUp`: its attributes.
function HomeZone.contains(x: number, y: number, z: number, size: { number }, radius: any, reachUp: any): boolean
	local hx, hy, hz = size[1] / 2, size[2] / 2, size[3] / 2
	local top = hy + HomeZone.ABOVE + (if type(reachUp) == "number" then reachUp else 0)
	if y < -hy - HomeZone.BELOW or y > top then
		return false
	end
	if type(radius) == "number" and radius > 0 then
		return x * x + z * z <= radius * radius
	end
	return math.abs(x) <= hx and math.abs(z) <= hz
end

return table.freeze(HomeZone)
