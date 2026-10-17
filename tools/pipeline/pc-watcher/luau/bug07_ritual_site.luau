-- Server datamodel: bug probe 7 (ADVISORY), Slime Ritual: 2 players for now, and off the slime path.
-- ok = Config.RITUAL.MIN_PLAYERS == 2 AND the ritual circle centre (the built Map.RitualCircle disc when it exists, else
-- Ritual.centre()) is farther than ParadeLane.HALF_WIDTH + the circle radius from every sample of the lane (ParadeLane.pointAt
-- every 1 stud, plus its drawPoints polyline). Reports the nearest lane distance, the needed distance and MIN_PLAYERS.
local shared = game:GetService("ReplicatedStorage"):FindFirstChild("Shared")
if not shared then
	return { ok = false, summary = "ReplicatedStorage.Shared missing", detail = {} }
end
local ok, result = pcall(function()
	local Config, Ritual, lane = require(shared.Config), require(shared.Ritual), require(shared.ParadeLane)
	local cfg = Config.RITUAL
	local cx, cz = Ritual.centre()
	local radius = cfg.CIRCLE_RADIUS
	local built = workspace:FindFirstChild("Map") and workspace.Map:FindFirstChild("RitualCircle")
	if built and built:IsA("Model") then
		local cf, size = built:GetBoundingBox()
		cx, cz = cf.Position.X, cf.Position.Z
		radius = math.max(radius, math.max(size.X, size.Z) / 2)
	end
	local best = math.huge
	local function consider(x, z)
		best = math.min(best, math.sqrt((x - cx) ^ 2 + (z - cz) ^ 2))
	end
	local s = 0
	while s <= lane.LENGTH do
		consider(lane.pointAt(s))
		s += 1
	end
	for _, p in lane.drawPoints() do
		consider(p[1], p[2])
	end
	local needed = lane.HALF_WIDTH + radius
	return { min_players = cfg.MIN_PLAYERS, centre = { cx, cz }, radius = radius, nearest_lane = best, needed = needed, built = built ~= nil }
end)
if not ok then
	return { ok = false, summary = "probe error: " .. tostring(result), detail = {} }
end
local r = result
local fine = r.min_players == 2 and r.nearest_lane > r.needed
return {
	ok = fine,
	summary = string.format("MIN_PLAYERS %d (want 2); circle centre %.1f studs from the lane, needs > %.1f", r.min_players, r.nearest_lane, r.needed),
	detail = r,
}
