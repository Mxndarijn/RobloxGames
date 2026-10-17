-- Server datamodel: bug probe 5 (ADVISORY), slimes must start straight out of the fountain, not glide to a point.
-- Waits up to 9 s for a NEW model in workspace.WildSlimes (SPAWN_INTERVAL 4 s; at the 18 cap a slot opens when one
-- drains) and samples its pivot every Heartbeat for 6 s. The reference path is the real ride: FountainRide's emerge
-- start (WorldLayout.SLIDE_PATH head minus EMERGE_DEPTH), the head and every SLIDE_PATH waypoint.
-- ok = the first sample (one Heartbeat after it appeared) is within 4 studs of the emerge start AND every sample in
-- the first 8 studs of motion is within 3 studs of the reference polyline (no straight-line glide to a separate start)
-- AND it started moving within 0.5 s. ok = null when no new wild slime appeared in the window.
local RS = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local layoutMod = RS:FindFirstChild("Visuals") and RS.Visuals:FindFirstChild("WorldLayout")
local rideMod = RS:FindFirstChild("Shared") and RS.Shared:FindFirstChild("FountainRide")
local folder = workspace:FindFirstChild("WildSlimes")
if not (layoutMod and rideMod and folder) then
	return { ok = false, summary = "WorldLayout / FountainRide / WildSlimes missing", detail = {} }
end
local layout, ride = require(layoutMod), require(rideMod)
local ref = {}
local head = layout.SLIDE_PATH[1]
table.insert(ref, Vector3.new(head[1], head[2] - ride.EMERGE_DEPTH, head[3]))
for _, p in layout.SLIDE_PATH do
	table.insert(ref, Vector3.new(p[1], p[2], p[3]))
end
local function offPath(pos)
	local best = math.huge
	for i = 2, #ref do
		local a, b = ref[i - 1], ref[i]
		local ab = b - a
		local t = math.clamp((pos - a):Dot(ab) / math.max(ab:Dot(ab), 1e-6), 0, 1)
		best = math.min(best, (pos - (a + ab * t)).Magnitude)
	end
	return best
end
local fresh, seen = nil, {}
for _, m in folder:GetChildren() do
	seen[m] = true
end
local conn = folder.ChildAdded:Connect(function(m)
	if m:IsA("Model") and not fresh then
		fresh = { model = m, born = os.clock() }
	end
end)
local deadline = os.clock() + 9
while not fresh and os.clock() < deadline do
	task.wait(0.1)
end
conn:Disconnect()
if not fresh then
	return { ok = nil, summary = "no new wild slime in 9 s (spawn cap?)", detail = { wild = #folder:GetChildren() } }
end
RunService.Heartbeat:Wait() -- WorldView poses the ride at spawn; the Parent step itself is not the first frame
local m = fresh.model
local first = m:GetPivot().Position
local samples, travelled, last, startedAt, worst = 0, 0, first, nil, 0
local firstOff = (first - ref[1]).Magnitude
local t0 = os.clock()
while os.clock() - t0 < 6 and m.Parent do
	local p = m:GetPivot().Position
	travelled += (p - last).Magnitude
	last = p
	if not startedAt and (p - first).Magnitude > 0.5 then
		startedAt = os.clock() - fresh.born
	end
	if travelled <= 8 then
		worst = math.max(worst, offPath(p))
	end
	samples += 1
	RunService.Heartbeat:Wait()
end
local ok = firstOff <= 4 and worst <= 3 and startedAt ~= nil and startedAt <= 0.5
return {
	ok = ok,
	summary = string.format("first sample %.1f studs from the emerge start, %.1f studs max off the ride in the first 8 studs, moving after %s s", firstOff, worst, startedAt and string.format("%.2f", startedAt) or "never"),
	detail = {
		emerge_start = { ref[1].X, ref[1].Y, ref[1].Z },
		first = { first.X, first.Y, first.Z },
		first_off_m = firstOff,
		max_off_path_8 = worst,
		start_delay_s = startedAt,
		samples = samples,
		travelled = travelled,
	},
}
