-- Server datamodel: bug probe 9 (ADVISORY), nobody should be able to stand on top of the fountain slide or inside its tube
-- (slide_walk covers the floor sinking, which is meant to be walkable for the ride itself). Drops 4-stud balls
-- (character sized) from 16 studs above up to 14 evenly spaced points (higher than 8 studs) of WorldLayout.SLIDE_PATH, at the centreline and 3.5
-- sideways (outer roof / wall tops), and rolls one more ball into the open mouth (from 10 studs outside, 20 studs/s inward).
-- After 3 s a ball counts as ON THE SLIDE when it rests within 4.5 studs (horizontal) of the path and no lower than 0.5
-- studs under the path height there: it is on the roof (above path + 6) or standing inside the tube (below). ok = every drop
-- ball left the slide and the mouth ball did not get more than 8 studs into the tube. Balls are destroyed afterwards.
local RS = game:GetService("ReplicatedStorage")
local layoutMod = RS:FindFirstChild("Visuals") and RS.Visuals:FindFirstChild("WorldLayout")
if not layoutMod then
	return { ok = false, summary = "ReplicatedStorage.Visuals.WorldLayout missing", detail = {} }
end
local PhysicsService = game:GetService("PhysicsService")
local GROUP = "BugProbe"
pcall(function()
	PhysicsService:RegisterCollisionGroup(GROUP)
end)
pcall(function()
	PhysicsService:CollisionGroupSetCollidable(GROUP, GROUP, false)
end)
local made = {}
local ok, result = pcall(function()
	local path = {}
	for _, p in require(layoutMod).SLIDE_PATH do
		table.insert(path, Vector3.new(p[1], p[2], p[3]))
	end
	local function nearest(pos)
		local best, bestH, at = math.huge, 0, 1
		for i, p in path do
			local h = math.sqrt((p.X - pos.X) ^ 2 + (p.Z - pos.Z) ^ 2)
			if h < best then
				best, bestH, at = h, pos.Y - p.Y, i
			end
		end
		return best, bestH, at
	end
	local function ball(pos)
		local b = Instance.new("Part")
		b.Shape = Enum.PartType.Ball
		b.Size = Vector3.new(4, 4, 4)
		b.Position = pos
		b.CollisionGroup = GROUP
		b.CustomPhysicalProperties = PhysicalProperties.new(0.7, 0.4, 0, 1, 1)
		b.Parent = workspace
		table.insert(made, b)
		return b
	end
	local drops = {}
	local n = #path
	for k = 1, 14 do
		local i = math.clamp(math.floor((k - 0.5) / 14 * n) + 1, 1, n)
		local a, b = path[i], path[math.min(i + 1, n)]
		if a.Y < 8 then
			continue -- near the ground a ball beside the slide would read as on it; the mouth ball covers the low end
		end
		local fwd = b - a
		fwd = Vector3.new(fwd.X, 0, fwd.Z)
		local side = if fwd.Magnitude > 1e-3 then Vector3.new(-fwd.Unit.Z, 0, fwd.Unit.X) else Vector3.xAxis
		for _, off in { 0, if k % 2 == 0 then 3.5 else -3.5 } do
			table.insert(drops, { ball = ball(a + side * off + Vector3.new(0, 16, 0)), index = i, off = off })
		end
	end
	local mouth, prev = path[n], path[n - 1]
	local out = Vector3.new(mouth.X - prev.X, 0, mouth.Z - prev.Z).Unit
	local mball = ball(mouth + out * 10 + Vector3.new(0, 2.5, 0))
	local t0 = os.clock()
	while os.clock() - t0 < 3 do
		local v = mball.AssemblyLinearVelocity
		mball.AssemblyLinearVelocity = Vector3.new(-out.X * 20, v.Y, -out.Z * 20)
		task.wait(0.1)
	end
	local on, details = 0, {}
	for _, d in drops do
		local h, dy, at = nearest(d.ball.Position)
		local onSlide = h <= 4.5 and dy >= -0.5
		if onSlide then
			on += 1
			if #details < 6 then
				table.insert(details, { index = d.index, off = d.off, dy = math.floor(dy * 10) / 10, where = if dy > 6 then "roof" else "inside" })
			end
		end
	end
	local mh, mdy, mat = nearest(mball.Position)
	local mouthDepth = math.sqrt((mball.Position.X - mouth.X) ^ 2 + (mball.Position.Z - mouth.Z) ^ 2)
	local mouthIn = mh <= 4.5 and mdy >= -0.5 and mdy < 6 and mouthDepth > 8
	return { drops = #drops, on_slide = on, on_slide_samples = details, mouth_ball_inside = mouthIn, mouth_depth = mouthDepth }
end)
for _, b in made do
	pcall(function()
		b:Destroy()
	end)
end
if not ok then
	return { ok = false, summary = "probe error: " .. tostring(result), detail = {} }
end
local r = result
return {
	ok = r.on_slide == 0 and not r.mouth_ball_inside,
	summary = string.format("%d / %d dropped balls rest on or in the slide; mouth ball %s", r.on_slide, r.drops, r.mouth_ball_inside and string.format("walked %.0f studs INTO the tube", r.mouth_depth) or "stayed out"),
	detail = r,
}
