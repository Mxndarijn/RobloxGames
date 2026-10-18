-- Server datamodel: C10 HARD proof, nobody sinks into or through the TOP of the fountain (eave, red dome, basin floor).
-- The visual profile is the kit's (models/slime_fountain.py): the eave edge top is 31.3 at r 13.4, the dome shoulder runs
-- z = 31.3 + 4.6 * sqrt(1 - ((r - 8.9) / 4.5)^2) up to the flat basin floor at 35.9 (r <= 8.9). Drops free balls
-- (CanCollide, unanchored: stand in for feet, radius 1) and character-sized balls (radius 2, the player's height) 6 studs above that
-- surface on a dense polar grid over the whole top (r every 0.5 from 0.5 to 13.4, 24 azimuths per ring, dozens of rings),
-- each once at rest and once rolling inward at 8 studs/s (a player walking onto the top), and watches them for 1.5 s.
-- Balls sit in their own collision group that does not collide with itself, so only the fountain stops a ball.
-- Fails when a ball's centre is ever less than 0.4 above the visual surface under it (r <= 13.4), when it reaches y < 2
-- (fell through to the ground), or when the TopCollider<i> parts are missing / off. `ok` is false on ANY violation.
-- The clearance check is skipped while a ball is still falling fast (AssemblyLinearVelocity.Y < -5): the impact frame
-- of a ~49 studs/s drop depenetrates a little (sank 0.02-0.11), which is physics settling, not a gap in the surface.
-- SPLIT (shot option "fountain_split": true; FEATURES.FountainSplit draft, option (a) of the collision choice): the same grid against the 4 tower
-- pieces of MeshAssets.FOUNTAIN_SPLIT (basin, dome, eave, silo; PreciseConvexDecomposition via CreateMeshPartAsync, assembled exactly like
-- MeshSwap.swapFountainSplit, invisible) instead of the hand-placed MeshCollider colliders (Basin / Trim / Silo / TopCollider<i>), which are switched off
-- for the run and restored after; the SlideColliders block stays. It reads the ids from Shared.MeshAssets, so the flag can stay OFF. With the flag ON
-- the pieces already exist and the colliders are already off: the grid just runs on them (`split = "flag"`). Result: `split` = "experiment" | "flag" | nil.
local folder = workspace:FindFirstChild("Map") and workspace.Map:FindFirstChild("Volcano")
if not folder then
	return { ok = false, error = "Map.Volcano missing" }
end
local SPLIT = %%SPLIT%%
local tiers, off = 0, false
for _, p in folder:GetChildren() do
	if string.match(p.Name, "^TopCollider%d+$") then
		tiers += 1
		if not p.CanCollide then
			off = true
		end
	end
end
if tiers == 0 then
	return { ok = false, error = "no TopCollider parts under Map.Volcano" }
end
local slot = folder:FindFirstChild("FountainMesh")
local okMA, MeshAssets = pcall(function()
	return require(game:GetService("ReplicatedStorage").Shared.MeshAssets)
end)
local flagPieces = SPLIT and okMA and slot and slot:FindFirstChild(MeshAssets.FOUNTAIN_SPLIT[1]) ~= nil
if off and not flagPieces then
	return { ok = true, skipped = true, note = "a TopCollider is off: the fountain mesh is not loaded, the visible stand-ins carry the collision" }
end
if SPLIT and not okMA then
	return { ok = false, error = "split: Shared.MeshAssets not found" }
end
local function profile(r)
	if r > 13.4 then
		return nil
	end
	if r <= 8.9 then
		return 35.9
	end
	local c = (r - 8.9) / 4.5
	return 31.3 + 4.6 * math.sqrt(math.max(0, 1 - c * c))
end
local made, offColliders = {}, {} -- split mode: the experiment pieces and the hand-placed colliders switched off
local function run()
	local splitMode = nil
	if flagPieces then
		splitMode = "flag"
	elseif SPLIT then
		local _, scale, below = MeshAssets.fit("slime_fountain", { slot.Size.X, slot.Size.Y, slot.Size.Z })
		local k = scale or 1
		local AssetService = game:GetService("AssetService")
		local pending, err = 0, nil
		for _, name in MeshAssets.FOUNTAIN_SPLIT do
			local fid = MeshAssets.collision(name)
			local id, entry = MeshAssets.meshId(name), MeshAssets.get(name)
			if not fid then
				continue -- decor piece (slide): the slide stays the SlideColliders block
			elseif not (id and entry and entry.size and entry.offset) then
				return { ok = false, error = "split: " .. name .. " has no mesh id / size / offset in MeshAssets" }
			end
			pending += 1
			task.spawn(function()
				local ok, mp = pcall(function()
					return AssetService:CreateMeshPartAsync(id, { CollisionFidelity = Enum.CollisionFidelity[fid] })
				end)
				if ok and typeof(mp) == "Instance" then
					mp.Size = Vector3.new(entry.size[1] * k, entry.size[2] * k, entry.size[3] * k)
					mp.CFrame = slot.CFrame
						* CFrame.new(0, -below, 0)
						* CFrame.new(entry.offset[1] * k, entry.offset[2] * k, entry.offset[3] * k)
						* CFrame.Angles(0, math.rad(MeshAssets.IMPORT_YAW), 0)
					mp.Anchored = true
					mp.CanCollide = true
					mp.CanQuery = false
					mp.CanTouch = false
					mp.Transparency = 1
					mp.Name = "PcwSplitPiece"
					table.insert(made, mp)
				else
					err = name .. ": " .. tostring(mp)
				end
				pending -= 1
			end)
		end
		local tw = os.clock()
		while pending > 0 and os.clock() - tw < 12 do
			task.wait(0.1)
		end
		if err or pending > 0 or #made < 4 then
			return { ok = false, error = "split: " .. tostring(err or ("only %d of 4 pieces made"):format(#made)) }
		end
		for _, d in folder:GetDescendants() do
			if d:IsA("BasePart") and d:GetAttribute("MeshCollider") == "slime_fountain" and d.CanCollide then
				table.insert(offColliders, d)
				d.CanCollide = false
			end
		end
		for _, mp in made do
			mp.Parent = workspace
		end
		task.wait(0.2)
		splitMode = "experiment"
	end
	local PhysicsService = game:GetService("PhysicsService")
	local GROUP = "FountainProbe"
	pcall(function()
		PhysicsService:RegisterCollisionGroup(GROUP)
	end)
	pcall(function()
		PhysicsService:CollisionGroupSetCollidable(GROUP, GROUP, false)
	end)
	local active, samples = {}, 0
	for _, size in { 2, 4 } do
		for ri = 1, 27 do
			local r = ri * 0.5
			local surface = profile(r)
			if not surface then
				continue
			end
			for ai = 0, 23 do
				local a = ai * math.pi / 12 + (ri % 2) * math.pi / 24
				local dir = Vector3.new(math.cos(a), 0, math.sin(a))
				for _, speed in { 0, 8 } do
					local b = Instance.new("Part")
					b.Shape = Enum.PartType.Ball
					b.Size = Vector3.new(size, size, size)
					b.CanQuery = false
					b.CanTouch = false
					b.CollisionGroup = GROUP
					b.Transparency = 1
					b.Position = Vector3.new(dir.X * r, surface + 6 + size / 2, dir.Z * r)
					b.Parent = workspace
					if speed > 0 then
						b.AssemblyLinearVelocity = -dir * speed
					end
					samples += 1
					active[#active + 1] = { part = b, r = r, a = ai, speed = speed, size = size }
				end
			end
		end
	end
	local bad, worst = {}, math.huge
	local t0 = os.clock()
	while os.clock() - t0 < 1.5 and #active > 0 do
		task.wait()
		for n = #active, 1, -1 do
			local s = active[n]
			local pos = s.part.Position
			local surface = profile(math.sqrt(pos.X ^ 2 + pos.Z ^ 2))
			local failed = false
			if surface and pos.Y > 29 and s.part.AssemblyLinearVelocity.Y >= -5 then
				local clearance = pos.Y - surface
				worst = math.min(worst, clearance)
				if clearance < 0.4 then
					bad[#bad + 1] = string.format("r=%.1f a=%d v=%d size=%d ball sank %.2f below the top surface", s.r, s.a, s.speed, s.size, 0.4 - clearance)
					failed = true
				end
			end
			if not failed and pos.Y < 2 then
				bad[#bad + 1] = string.format("r=%.1f a=%d v=%d size=%d ball fell through to y=%.1f", s.r, s.a, s.speed, s.size, pos.Y)
				failed = true
			end
			if failed then
				s.part:Destroy()
				table.remove(active, n)
			end
		end
	end
	for _, s in active do
		s.part:Destroy()
	end
	return {
		ok = #bad == 0,
		split = splitMode,
		tiers = tiers,
		samples = samples,
		worst_clearance = worst,
		violations = bad,
	}
end
local okRun, res = pcall(run)
-- always put the colliders back and drop the experiment pieces, even when the run errored
for _, d in offColliders do
	d.CanCollide = true
end
for _, mp in made do
	pcall(function()
		mp:Destroy()
	end)
end
if not okRun then
	return { ok = false, error = tostring(res) }
end
return res
