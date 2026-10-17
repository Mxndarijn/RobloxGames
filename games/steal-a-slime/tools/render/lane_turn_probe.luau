--!nocheck
-- lune run tools/render/lane_turn_probe   Port of tools/pipeline/pc-watcher/luau/bug04_lane_smooth.luau's math.
local ParadeLane = require("../../src/shared/ParadeLane")
local STEP = 2
local function turns(points)
	local worst, at, prev = 0, nil, nil
	for i = 2, #points do
		local dx, dz = points[i][1] - points[i - 1][1], points[i][2] - points[i - 1][2]
		local m = math.sqrt(dx * dx + dz * dz)
		if m > 1e-4 then
			dx, dz = dx / m, dz / m
			if prev then
				local a = math.deg(math.acos(math.clamp(prev[1] * dx + prev[2] * dz, -1, 1)))
				if a > worst then
					worst, at = a, points[i - 1]
				end
			end
			prev = { dx, dz }
		end
	end
	return worst, at
end
local function resample(poly)
	local out, carry = { poly[1] }, 0
	for i = 2, #poly do
		local a, b = poly[i - 1], poly[i]
		local len = math.sqrt((b[1] - a[1]) ^ 2 + (b[2] - a[2]) ^ 2)
		local at = STEP - carry
		while at <= len do
			table.insert(out, { a[1] + (b[1] - a[1]) * at / len, a[2] + (b[2] - a[2]) * at / len })
			at += STEP
		end
		carry = len - (at - STEP)
	end
	table.insert(out, poly[#poly])
	return out
end
local vw, vat = turns(resample(ParadeLane.drawPoints()))
local walk, s = {}, 0
while s < ParadeLane.LENGTH do
	local x, z = ParadeLane.pointAt(s)
	table.insert(walk, { x, z })
	s += STEP
end
local x, z = ParadeLane.pointAt(ParadeLane.LENGTH)
table.insert(walk, { x, z })
local ww, wat = turns(walk)
print(`visual max {vw} at ({vat[1]}, {vat[2]})`)
print(`walk   max {ww} at ({wat[1]}, {wat[2]})`)
print(`LENGTH {ParadeLane.LENGTH} LEAD_LENGTH {ParadeLane.LEAD_LENGTH} drawPoints {#ParadeLane.drawPoints()}`)
