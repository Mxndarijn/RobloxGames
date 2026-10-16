-- Server datamodel: B6 HARD proof, nobody falls through or out of the fountain slide, very top to bottom.
-- For every SlideFloor<i> collider (Map.Volcano.SlideColliders, in path order, head first) drops free 2-stud
-- balls (CanCollide, unanchored: stand in for a player) from 4 studs above the surface at 12 positions per
-- segment (k = 0, .02, .05, .1, .25, .5, .75, .9, .95, .98, 1 and 1 again) at the centre, plus two lateral
-- offsets at the joins, each once at rest and once launched down the slide at 40 studs/s (the speed that
-- tunnelled / hopped the bends), and watches them for 1.5 s. Balls sit in their own collision group that
-- does not collide with itself, so a ball is only ever stopped by the slide, never by another ball.
-- Fails when a ball ever has its centre under the top face of ANY slab (floor or joint filler) it is over
-- (fell into / through the slide), leaves the trough sideways, or sinks below y = -1. Reports the segment
-- count, the top / bottom surface heights and the worst clearance seen (ball centre minus floor top,
-- studs; a ball resting on the surface reads about 1). `ok` is false on ANY violation.
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
local slabs = {} -- every floor slab and joint filler: what a ball can stand on
for _, p in folder:GetChildren() do
	if string.match(p.Name, "^SlideFloor%d+$") or string.match(p.Name, "^SlideJoint%d+$") then
		slabs[#slabs + 1] = p
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
	for _, p in slabs do
		local l = p.CFrame:PointToObjectSpace(pos)
		if math.abs(l.X) < p.Size.X / 2 and math.abs(l.Z) < p.Size.Z / 2 then
			local c = l.Y - p.Size.Y / 2
			best = if best == nil then c else math.max(best, c)
		end
	end
	return best
end
-- True when the ball is within 8 studs of a slab's surface but outside every slab's width (left the trough).
local function escaped(pos)
	local near = false
	for _, p in slabs do
		local l = p.CFrame:PointToObjectSpace(pos)
		if math.abs(l.Z) < p.Size.Z / 2 and math.abs(l.Y - p.Size.Y / 2) < 8 then
			if math.abs(l.X) < p.Size.X / 2 + 0.2 then
				return false
			end
			near = true
		end
	end
	return near
end
local PhysicsService = game:GetService("PhysicsService")
local GROUP = "SlideProbe"
pcall(function()
	PhysicsService:RegisterCollisionGroup(GROUP)
end)
pcall(function()
	PhysicsService:CollisionGroupSetCollidable(GROUP, GROUP, false)
end)
local ball = Instance.new("Part")
ball.Shape = Enum.PartType.Ball
ball.Size = Vector3.new(2, 2, 2)
ball.CanQuery = false
ball.CanTouch = false
ball.CollisionGroup = GROUP
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
	for _, k in { 0, 0.02, 0.05, 0.1, 0.25, 0.5, 0.75, 0.9, 0.95, 0.98, 1 } do
		local s = surface(p, k)
		topY, bottomY = math.max(topY, s.Y), math.min(bottomY, s.Y)
		for _, side in { 0, -2.4, 2.4 } do
			if side ~= 0 and k < 0.9 and k > 0.1 then
				continue
			end
			for _, speed in { 0, 40 } do
				local b = ball:Clone()
				b.Position = s + p.CFrame.RightVector * side + Vector3.new(0, 5, 0)
				b.Parent = workspace
				if speed > 0 then
					b.AssemblyLinearVelocity = p.CFrame.LookVector * speed
				end
				samples += 1
				active[#active + 1] = { part = b, i = i, k = k, side = side, speed = speed }
			end
		end
	end
end
local t0 = os.clock()
while os.clock() - t0 < 1.5 and #active > 0 do
	task.wait()
	for n = #active, 1, -1 do
		local a = active[n]
		local pos = a.part.Position
		local c = clearance(pos)
		local failed = false
		if c then
			worst = math.min(worst, c)
			if c < -0.1 then
				bad[#bad + 1] = string.format("segment %d k=%.2f side=%.1f v=%d ball %.2f below the slide", a.i, a.k, a.side, a.speed, -c)
				failed = true
			elseif escaped(pos) then
				bad[#bad + 1] = string.format("segment %d k=%.2f side=%.1f v=%d ball left the trough sideways", a.i, a.k, a.side, a.speed)
				failed = true
			end
		end
		if not failed and pos.Y < -1 then
			bad[#bad + 1] = string.format("segment %d k=%.2f v=%d ball fell to y=%.1f", a.i, a.k, a.speed, pos.Y)
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
