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
--      split_pcd  (FEATURES.FountainSplit draft, option (a)) the tower colliders (Basin / Trim / Silo / Top, NOT the SlideColliders folder) temporarily
--                 CanCollide false and the 4 tower pieces of MeshAssets.FOUNTAIN_SPLIT (basin, dome, eave, silo; the decor slide piece is not needed) made
--                 with CreateMeshPartAsync(meshId, {CollisionFidelity = PreciseConvexDecomposition}) at the assembled transforms (slot CFrame + each piece
--                 offset, IMPORT_YAW), invisible, CanCollide. Reads the ids from Shared.MeshAssets, so it runs with the flag OFF (no flag flip); with the flag
--                 ON the pieces already exist and are measured as they are (split_pcd.source = "flag"). parts_saved = tower colliders - 4 pieces.
--    per variant: sank (centre < 0.4 above the visual top while not falling fast), fell (reached y < 2), balls, parts_saved (colliders - 1) and
--    tower_parts_saved (without the slide folder, which must stay hand-placed: a precise mesh would make the trough walkable, COLLISION.md). Everything is
--    restored (CanCollide of every collider, the experiment meshes destroyed). Budget < 28 s (was 20 before split_pcd): a variant is skipped (n/a) when the clock runs out.
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
	if visual and not visual:IsA("MeshPart") then
		visual = nil
	end
	local okMA, MeshAssets = pcall(function()
		return require(RS.Shared.MeshAssets)
	end)
	if not okMA then
		MeshAssets = nil
	end
	local flagPieces = MeshAssets and slot and slot:FindFirstChild(MeshAssets.FOUNTAIN_SPLIT[1]) -- FEATURES.FountainSplit is on
	if not slot or not (visual or flagPieces) then
		return { skipped = "Map.Volcano.FountainMesh.Mesh (the fountain MeshPart) is not loaded" }
	end
	local colliders, towerList, slideCount, towerCount = {}, {}, 0, 0
	local slideFolder = volcano:FindFirstChild("SlideColliders")
	for _, d in volcano:GetDescendants() do
		if d:IsA("BasePart") and not d:IsA("MeshPart") and d.CanCollide and d.Transparency >= 0.99 then
			table.insert(colliders, d)
			if slideFolder and d:IsDescendantOf(slideFolder) then
				slideCount += 1
			else
				towerCount += 1
				table.insert(towerList, d)
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
	local RIM_R = 13.4 -- profile() returns nil beyond this radius: the kit's outer rim
	local FELL_BALLS_CAP = 64
	local function round2(x)
		return math.floor(x * 100 + 0.5) / 100
	end
	local function profile(r)
		if r > RIM_R then
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
		if not visual then
			return nil, "single mesh not loaded (FEATURES.FountainSplit is on)"
		end
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
	-- split_pcd: the tower pieces of MeshAssets.FOUNTAIN_SPLIT, each from its own mesh id with its MeshAssets.COLLISION fidelity
	-- (PreciseConvexDecomposition), placed exactly like server/MeshSwap.swapFountainSplit: slot CFrame (stand on the bottom, one
	-- uniform scale) * piece offset * IMPORT_YAW. The decor slide piece is skipped: the slide stays the SlideColliders block.
	local splitPieces, splitErr = {}, nil
	if flagPieces then
		for _, name in MeshAssets.FOUNTAIN_SPLIT do
			local piece = slot:FindFirstChild(name)
			if piece and piece:IsA("MeshPart") and piece.CanCollide then
				table.insert(splitPieces, piece)
			end
		end
	elseif not MeshAssets then
		splitErr = "Shared.MeshAssets not found"
	else
		local _, scale, below = MeshAssets.fit("slime_fountain", { slot.Size.X, slot.Size.Y, slot.Size.Z })
		local k = scale or 1
		for _, name in MeshAssets.FOUNTAIN_SPLIT do
			local fid = MeshAssets.collision(name)
			local id, entry = MeshAssets.meshId(name), MeshAssets.get(name)
			if not fid then
				continue -- decor piece (slide)
			elseif not (id and entry and entry.size and entry.offset) then
				splitErr = name .. " has no mesh id / size / offset in MeshAssets"
				break
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
					mp.Name = "PcwExperimentMesh"
					table.insert(made, mp)
					table.insert(splitPieces, mp)
				else
					splitErr = name .. ": " .. tostring(mp)
				end
				pending -= 1
			end)
		end
	end
	local tw = os.clock()
	while pending > 0 and os.clock() - tw < 10 do
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
					table.insert(active, { part = b, r = r, size = size, az = math.deg(a) % 360, prevR = r })
				end
			end
		end
		local total, sank, fell = #active, 0, 0
		local fellBalls, fellTruncated = {}, false
		local t0 = os.clock()
		while os.clock() - t0 < 1.5 and #active > 0 do
			task.wait()
			for n = #active, 1, -1 do
				local s = active[n]
				local pos = s.part.Position
				local curR = math.sqrt(pos.X ^ 2 + pos.Z ^ 2)
				if s.prevR <= RIM_R and curR > RIM_R then
					s.rimR, s.rimY = curR, pos.Y
				end
				s.prevR = curR
				local surface = profile(curR)
				local failed = false
				if surface and pos.Y > 29 and s.part.AssemblyLinearVelocity.Y >= -5 and pos.Y - surface < 0.4 then
					sank += 1
					failed = true
				elseif pos.Y < 2 then
					fell += 1
					if #fellBalls < FELL_BALLS_CAP then
						table.insert(fellBalls, { size = s.size, r = round2(s.r), az = round2(s.az), rim_r = if s.rimR then round2(s.rimR) else nil, rim_y = if s.rimY then round2(s.rimY) else nil, crossed = s.rimR ~= nil })
					else
						fellTruncated = true
					end
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
		results[label] = { balls = total, sank = sank, fell = fell, fell_balls = fellBalls, fell_balls_truncated = if fellTruncated then true else nil }
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
		grid("colliders") -- with FEATURES.FountainSplit on this baseline is already the split (the tower colliders are off)
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
		if #splitPieces < 4 then
			results.split_pcd = { error = splitErr or ("only %d of the 4 tower pieces were made"):format(#splitPieces) }
		elseif os.clock() - t_start > 22 then
			results.split_pcd = { skipped = "time budget" }
		else
			collidersOn(true)
			for _, c in towerList do -- the slide block stays: the slide piece is decor
				c.CanCollide = false
			end
			for _, mp in splitPieces do
				if not flagPieces then
					mp.Parent = workspace
				end
			end
			task.wait(0.2)
			grid("split_pcd")
			results.split_pcd.source = if flagPieces then "flag" else "experiment"
			if not flagPieces then
				for _, mp in splitPieces do
					mp.Parent = nil
				end
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
	if results.split_pcd and results.split_pcd.balls then
		results.split_pcd.pieces = #splitPieces
		if not flagPieces then -- the slide block stays, the 4 PCD pieces replace the tower colliders
			results.split_pcd.parts_saved = towerCount - #splitPieces
			results.split_pcd.tower_parts_saved = results.split_pcd.parts_saved
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
	summary = string.format("%d invisible colliders (%d slide, %d tower); %s; %s; %s; %s", exp.colliders_total, exp.slide_colliders, exp.tower_colliders, line("colliders"), line("mesh_pcd"), line("mesh_hull"), line("split_pcd"))
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
