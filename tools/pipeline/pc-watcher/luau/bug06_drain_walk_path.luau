-- Server datamodel: bug probe 6 (ADVISORY). The "drain" is Plaza.GooDrain (ParadeLane.DRAIN, goo drain at x 0, z 52.5,
-- the slimes' despawn funnel). Merijn's bug is that a HUMAN walk path runs to it (WorldLayout paths(): the SlideExit
-- strip from the landing ring's outer edge over the plaza, straight through the drain's footprint); the ask is to remove
-- it. So ok = NO Map.Paths part reaches the drain (any path part whose footprint is within 6 studs of the drain centre,
-- or named SlideExit). The path parts found, their names and sizes are in detail.
local map = workspace:FindFirstChild("Map")
local paths = map and map:FindFirstChild("Paths")
if not paths then
	return { ok = false, summary = "workspace.Map.Paths missing", detail = {} }
end
local drain = Vector3.new(0, 0, 52.5)
local gd = map:FindFirstChild("Plaza") and map.Plaza:FindFirstChild("GooDrain")
if gd and gd:IsA("BasePart") then
	drain = Vector3.new(gd.Position.X, 0, gd.Position.Z)
end
local reaching, total = {}, 0
for _, p in paths:GetChildren() do
	-- the Plaza disc itself (the drain sits on its rim) is not a walkway to the drain
	if p:IsA("BasePart") and p.Name ~= "Plaza" then
		total += 1
		local l = p.CFrame:PointToObjectSpace(Vector3.new(drain.X, p.Position.Y, drain.Z))
		local dx = math.max(math.abs(l.X) - p.Size.X / 2, 0)
		local dz = math.max(math.abs(l.Z) - p.Size.Z / 2, 0)
		local gap = math.sqrt(dx * dx + dz * dz)
		if gap <= 6 or p.Name == "SlideExit" then
			table.insert(reaching, { name = p.Name, size = { p.Size.X, p.Size.Z }, pos = { p.Position.X, p.Position.Z }, gap = math.floor(gap * 10) / 10 })
		end
	end
end
return {
	ok = #reaching == 0,
	summary = if #reaching == 0 then string.format("no walk path reaches the goo drain (%d path parts)", total)
		else string.format("%d path part(s) reach the goo drain, e.g. %s", #reaching, reaching[1].name),
	detail = { drain = { drain.X, drain.Z }, path_parts = total, reaching = reaching, drain_found = gd ~= nil },
}
