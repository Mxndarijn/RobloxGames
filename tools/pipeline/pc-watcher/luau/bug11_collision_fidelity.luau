-- Server datamodel: bug probe 11 (INFORMATIONAL, ok = nil), real mesh collision instead of manual collision boxes. Two parts:
-- 1) AUDIT (kept): every MeshPart in workspace.Map, workspace.Plots and ReplicatedStorage counted per CollisionFidelity / CanCollide; "key" meshes are the
--    fountain, slide, vat, statues (name or ancestor name contains fountain / slide / vat / emerge / statue / chute / cauldron). detail.audit_ok = at least one
--    key mesh and every one CanCollide with PreciseConvexDecomposition (since #252 slime_fountain_emerge is Hull on purpose, so this verdict is stale and no
--    longer decides `ok`); detail.audit lists the offenders. The manual collider parts (attribute MeshCollider / FountainCollider, CanCollide) are `manual_colliders`.
-- 2) EXPERIMENT, the fountain tower: counts the invisible collision parts under Map.Volcano (BasePart, CanCollide, Transparency >= 0.99: the SlideColliders
--    folder = FountainColliders output, plus TopCollider / Basin / Trim / Silo ...) = the potential part saving. Then re-runs a reduced fountain_walk-style ball
--    grid (r 2 .. 13.2 over basin / dome / eave, 8 azimuths, 2-stud "feet" and 4-stud character balls, 6 studs above the kit's visual top, 1.5 s) three ways:
--      colliders  the shipped invisible colliders (baseline)
--      mesh_pcd   colliders temporarily CanCollide false, a MeshPart from the fountain's MeshId made with AssetService:CreateMeshPartAsync(meshId,
--                 {CollisionFidelity = PreciseConvexDecomposition}), same CFrame / Size as the visual mesh, invisible, CanCollide
--      mesh_hull  the same with Hull
--    per variant: sank (centre < 0.4 above the visual top while not falling fast), fell (reached y < 2), balls, parts_saved (colliders - 1) and
--    tower_parts_saved (without the slide folder, which must stay hand-placed: a precise mesh would make the trough walkable, COLLISION.md). Everything is
--    restored (CanCollide of every collider, the experiment meshes destroyed). Budget < 20 s: a variant is skipped (n/a) when the clock runs out.
local t_start = os.clock()
local RS = game:GetService("ReplicatedStorage")
local roots = { workspace:FindFirstChild("Map"), workspace:FindFirstChild("Plots"), RS }
local KEYS = { "fountain", "slide", "vat", "emerge", "statue", "chute", "cauldron" }
local function isKey(inst)
	local node = inst
	while node and node ~= workspace and node ~= RS do
		local n = string.lower(node.Name)
		for _, k in KEYS do
			if string.find(n, k, 1, true) then
				return true
			end
		end
		node = node.Parent
	end
	return false
end
local fidelity, collide, key, offenders, bad, manual, meshes = {}, { yes = 0, no = 0 }, 0, {}, 0, 0, 0
for _, root in roots do
	if root then
		for _, d in root:GetDescendants() do
			if d:IsA("MeshPart") then
				meshes += 1
				local f = d.CollisionFidelity.Name
				fidelity[f] = (fidelity[f] or 0) + 1
				collide[d.CanCollide and "yes" or "no"] += 1
				if isKey(d) then
					key += 1
					if not d.CanCollide or d.CollisionFidelity ~= Enum.CollisionFidelity.PreciseConvexDecomposition then
						bad += 1
						if #offenders < 12 then
							table.insert(offenders, { path = d:GetFullName(), fidelity = f, can_collide = d.CanCollide })
						end
					end
				end
			elseif d:IsA("BasePart") and d.CanCollide and (d:GetAttribute("MeshCollider") ~= nil or d:GetAttribute("FountainCollider") ~= nil) then
				manual += 1
			end
		end
	end
end

local function experiment()
	local volcano = workspace:FindFirstChild("Map") and workspace.Map:FindFirstChild("Volcano")
	local slot = volcano and volcano:FindFirstChild("FountainMesh")
	local visual = slot and slot:FindFirstChild("Mesh")
	if not (visual and visual:IsA("MeshPart")) then
		return { skipped = "Map.Volcano.FountainMesh.Mesh (the fountain MeshPart) is not loaded" }
	end
	local colliders, slideCount, towerCount = {}, 0, 0
	local slideFolder = volcano:FindFirstChild("SlideColliders")
	for _, d in volcano:GetDescendants() do
		if d:IsA("BasePart") and not d:IsA("MeshPart") and d.CanCollide and d.Transparency >= 0.99 then
			table.insert(colliders, d)
			if slideFolder and d:IsDescendantOf(slideFolder) then
				slideCount += 1
			else
				towerCount += 1
			end
		end
	end
	local AssetService = game:GetService("AssetService")
	local PhysicsService = game:GetService("PhysicsService")
	local GROUP = "FountainProbe"
	pcall(function()
		PhysicsService:RegisterCollisionGroup(GROUP)
	end)
	pcall(function()
		PhysicsService:CollisionGroupSetCollidable(GROUP, GROUP, false)
	end)
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
	local made = {}
	local function makeMesh(fidelity)
		local ok, mp = pcall(function()
			return AssetService:CreateMeshPartAsync(visual.MeshId, { CollisionFidelity = fidelity })
		end)
		if not ok or typeof(mp) ~= "Instance" then
			return nil, tostring(mp)
		end
		mp.Size = visual.Size
		mp.CFrame = visual.CFrame
		mp.Anchored = true
		mp.CanCollide = true
		mp.CanQuery = false
		mp.CanTouch = false
		mp.Transparency = 1
		mp.Name = "PcwExperimentMesh"
		table.insert(made, mp)
		return mp, nil
	end
	local meshes, errs = {}, {}
	local pending = 2
	for name, fid in { mesh_pcd = Enum.CollisionFidelity.PreciseConvexDecomposition, mesh_hull = Enum.CollisionFidelity.Hull } do
		task.spawn(function()
			meshes[name], errs[name] = makeMesh(fid)
			pending -= 1
		end)
	end
	local tw = os.clock()
	while pending > 0 and os.clock() - tw < 6 do
		task.wait(0.1)
	end
	local results = {}
	local function grid(label)
		local active = {}
		for _, size in { 2, 4 } do
			for _, r in { 2, 5.5, 8.5, 9.5, 11, 12.5, 13.2 } do
				local surface = profile(r)
				for ai = 0, 7 do
					local a = ai * math.pi / 4 + (if r > 9 then math.pi / 8 else 0)
					local b = Instance.new("Part")
					b.Shape = Enum.PartType.Ball
					b.Size = Vector3.new(size, size, size)
					b.CanQuery = false
					b.CanTouch = false
					b.CollisionGroup = GROUP
					b.Transparency = 1
					b.Position = Vector3.new(math.cos(a) * r, surface + 6 + size / 2, math.sin(a) * r)
					b.Parent = workspace
					table.insert(active, { part = b, r = r, size = size })
				end
			end
		end
		local total, sank, fell = #active, 0, 0
		local t0 = os.clock()
		while os.clock() - t0 < 1.5 and #active > 0 do
			task.wait()
			for n = #active, 1, -1 do
				local s = active[n]
				local pos = s.part.Position
				local surface = profile(math.sqrt(pos.X ^ 2 + pos.Z ^ 2))
				local failed = false
				if surface and pos.Y > 29 and s.part.AssemblyLinearVelocity.Y >= -5 and pos.Y - surface < 0.4 then
					sank += 1
					failed = true
				elseif pos.Y < 2 then
					fell += 1
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
		results[label] = { balls = total, sank = sank, fell = fell }
	end
	local saved = {}
	for _, c in colliders do
		saved[c] = c.CanCollide
	end
	local function collidersOn(on)
		for _, c in colliders do
			c.CanCollide = if on then saved[c] else false
		end
	end
	local okRun, err = pcall(function()
		collidersOn(true)
		grid("colliders")
		for _, name in { "mesh_pcd", "mesh_hull" } do
			local mp = meshes[name]
			if not mp then
				results[name] = { error = errs[name] or "CreateMeshPartAsync did not finish" }
			elseif os.clock() - t_start > 16 then
				results[name] = { skipped = "time budget" }
			else
				collidersOn(false)
				mp.Parent = workspace
				task.wait(0.2)
				grid(name)
				mp.Parent = nil
			end
		end
	end)
	collidersOn(true)
	for _, c in colliders do
		c.CanCollide = saved[c]
	end
	for _, m in made do
		pcall(function()
			m:Destroy()
		end)
	end
	if not okRun then
		results.error = tostring(err)
	end
	for _, name in { "mesh_pcd", "mesh_hull" } do
		if results[name] and results[name].balls then
			results[name].parts_saved = #colliders - 1
			results[name].tower_parts_saved = towerCount - 1
		end
	end
	if results.colliders then
		results.colliders.parts = #colliders
	end
	return { colliders_total = #colliders, slide_colliders = slideCount, tower_colliders = towerCount, variants = results }
end
local okE, exp = pcall(experiment)
if not okE then
	exp = { error = tostring(exp) }
end
local function line(name)
	local v = exp.variants and exp.variants[name]
	if not v then
		return name .. " n/a"
	elseif v.balls then
		return string.format("%s sank %d fell %d of %d%s", name, v.sank, v.fell, v.balls, if v.parts_saved then string.format(" (saves %d parts, %d without the slide)", v.parts_saved, v.tower_parts_saved) else "")
	end
	return name .. " " .. tostring(v.error or v.skipped)
end
local summary
if exp.skipped or exp.error then
	summary = "experiment n/a: " .. tostring(exp.skipped or exp.error)
else
	summary = string.format("%d invisible colliders (%d slide, %d tower); %s; %s; %s", exp.colliders_total, exp.slide_colliders, exp.tower_colliders, line("colliders"), line("mesh_pcd"), line("mesh_hull"))
end
return {
	ok = nil,
	summary = summary .. string.format("; audit: %d key meshes, %d not PCD+CanCollide", key, bad),
	detail = {
		experiment = exp,
		audit_ok = key > 0 and bad == 0,
		audit = { meshparts = meshes, per_fidelity = fidelity, cancollide = collide, key_meshes = key, offenders = offenders, manual_colliders = manual },
	},
}
