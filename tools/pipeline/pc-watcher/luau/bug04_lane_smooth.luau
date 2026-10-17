-- Server datamodel: bug probe 4 (ADVISORY), the slime lane is angular. Samples the real lane geometry densely and
-- measures the heading change between consecutive ~2-stud chords (degrees):
--   visual = ParadeLane.drawPoints() (the polyline ParadeView lays the goo strip along, resampled every 2 studs)
--   walk   = ParadeLane.pointAt(s) every 2 studs (what slimes follow)
-- ok = the visual path's max turn per 2 studs <= 20 degrees. Reports max, the count of corners above 20 degrees
-- (and above 8) and the worst corner positions for both.
local shared = game:GetService("ReplicatedStorage"):FindFirstChild("Shared")
local lane = shared and require(shared:FindFirstChild("ParadeLane"))
if not lane then
	return { ok = false, summary = "ReplicatedStorage.Shared.ParadeLane missing", detail = {} }
end
local STEP, LIMIT = 2, 20
local function turns(points)
	local worst, over20, over8, list = 0, 0, 0, {}
	local prev
	for i = 2, #points do
		local d = points[i] - points[i - 1]
		if d.Magnitude > 1e-4 then
			d = d.Unit
			if prev then
				local a = math.deg(math.acos(math.clamp(prev:Dot(d), -1, 1)))
				if a > worst then
					worst = a
				end
				if a > LIMIT then
					over20 += 1
				end
				if a > 8 then
					over8 += 1
				end
				if a > 8 and #list < 6 then
					table.insert(list, { at = { points[i - 1].X, points[i - 1].Z }, deg = math.floor(a * 10) / 10 })
				end
			end
			prev = d
		end
	end
	return { max_deg = math.floor(worst * 10) / 10, over_20 = over20, over_8 = over8, worst = list, samples = #points }
end
-- Resamples a polyline every STEP studs along its length.
local function resample(poly)
	local out, carry = { poly[1] }, 0
	for i = 2, #poly do
		local a, b = poly[i - 1], poly[i]
		local len = (b - a).Magnitude
		local at = STEP - carry
		while at <= len do
			table.insert(out, a:Lerp(b, at / len))
			at += STEP
		end
		carry = len - (at - STEP)
	end
	table.insert(out, poly[#poly])
	return out
end
local ok, result = pcall(function()
	local draw = {}
	for _, p in lane.drawPoints() do
		table.insert(draw, Vector3.new(p[1], 0, p[2]))
	end
	local walk = {}
	local s = 0
	while s < lane.LENGTH do
		local x, z = lane.pointAt(s)
		table.insert(walk, Vector3.new(x, 0, z))
		s += STEP
	end
	local x, z = lane.pointAt(lane.LENGTH)
	table.insert(walk, Vector3.new(x, 0, z))
	return { visual = turns(resample(draw)), walk = turns(walk), strips = #draw - 1, length = lane.LENGTH }
end)
if not ok then
	return { ok = false, summary = "probe error: " .. tostring(result), detail = {} }
end
local v = result.visual
return {
	ok = v.max_deg <= LIMIT,
	summary = string.format("visual lane max turn %.1f deg per %d studs (%d corners > %d deg, %d > 8 deg, %d strips)", v.max_deg, STEP, v.over_20, LIMIT, v.over_8, result.strips),
	detail = result,
}
