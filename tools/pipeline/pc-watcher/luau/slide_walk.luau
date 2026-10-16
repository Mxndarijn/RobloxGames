-- Server datamodel: B6 proof, nobody falls through the fountain slide, very top to bottom. For every
-- SlideFloor<i> collider (Map.Volcano.SlideColliders, in path order, head first) drops a free 2-stud
-- ball (CanCollide, unanchored: stands in for a player) from 4 studs above the floor surface at the
-- segment's start, middle and end, then watches it for 1.2 s. Fails when a ball ever has its centre
-- under the top face of ANY floor slab it is over (fell into / through the slide), or sinks below
-- y = -1. Reports the segment count, the top / bottom surface heights and the worst clearance seen
-- (ball centre minus floor top, studs; a ball resting on the surface reads about 1).
local folder = workspace:FindFirstChild("Map") and workspace.Map:FindFirstChild("Volcano")
folder = folder and folder:FindFirstChild("SlideColliders")
if not folder then
	return { ok = false, error = "Map.Volcano.SlideColliders missing" }
end
local floors = {}
for _, p in folder:GetChildren() do
	local n = tonumber(string.match(p.Name, "^SlideFloor(%d+)$"))
	if n then
		floors[n] = p
	end
end
local count = 0
for _ in floors do
	count += 1
end
if count == 0 then
	return { ok = false, error = "no SlideFloor parts" }
end
local function surface(p, k)
	local overlap = 0.35
	return p.Position + p.CFrame.UpVector * (p.Size.Y / 2) + p.CFrame.LookVector * ((k - 0.5) * (p.Size.Z - overlap))
end
-- Clearance of a ball centre above the top face of the floor slab it is over; nil when not over one.
local function clearance(pos)
	local best = nil
	for _, p in floors do
		local l = p.CFrame:PointToObjectSpace(pos)
		if math.abs(l.X) < p.Size.X / 2 and math.abs(l.Z) < p.Size.Z / 2 then
			local c = l.Y - p.Size.Y / 2
			best = if best == nil then c else math.max(best, c)
		end
	end
	return best
end
local ball = Instance.new("Part")
ball.Shape = Enum.PartType.Ball
ball.Size = Vector3.new(2, 2, 2)
ball.CanQuery = false
ball.CanTouch = false
ball.Transparency = 1
local bad, samples, worst = {}, 0, math.huge
local topY, bottomY = -math.huge, math.huge
-- All balls are dropped at once and watched together (sequential runs exceeded the tool timeout).
local active = {}
for i = 1, #floors do
	local p = floors[i]
	if not p then
		bad[#bad + 1] = "SlideFloor" .. i .. " missing"
		continue
	end
	for _, k in { 0.05, 0.5, 0.95 } do
		local s = surface(p, k)
		topY, bottomY = math.max(topY, s.Y), math.min(bottomY, s.Y)
		local b = ball:Clone()
		b.Position = s + Vector3.new(0, 5, 0)
		b.Parent = workspace
		samples += 1
		active[#active + 1] = { part = b, i = i, k = k }
	end
end
local t0 = os.clock()
while os.clock() - t0 < 1.2 and #active > 0 do
	task.wait()
	for n = #active, 1, -1 do
		local a = active[n]
		local pos = a.part.Position
		local c = clearance(pos)
		local failed = false
		if c then
			worst = math.min(worst, c)
			if c < -0.1 then
				bad[#bad + 1] = string.format("segment %d k=%.2f ball %.2f below the slide", a.i, a.k, -c)
				failed = true
			end
		end
		if not failed and pos.Y < -1 then
			bad[#bad + 1] = string.format("segment %d k=%.2f ball fell to y=%.1f", a.i, a.k, pos.Y)
			failed = true
		end
		if failed then
			a.part:Destroy()
			table.remove(active, n)
		end
	end
end
for _, a in active do
	a.part:Destroy()
end
ball:Destroy()
return {
	ok = #bad == 0,
	segments = count,
	samples = samples,
	top_y = topY,
	bottom_y = bottomY,
	worst_clearance = worst,
	violations = bad,
}
