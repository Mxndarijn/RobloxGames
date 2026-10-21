-- Server datamodel (play): facing / centring numbers for checks.json (%%CHECKS%% = its JSON text).
-- Raw values only; watcher.geometry_verdict decides pass/fail.
-- Front convention (#75, MeshAssets.IMPORT_YAW = 180): MeshSwap parents a MeshPart "Mesh" under each skinned
-- slot. A Part slot's Mesh is turned 180 about Y from the slot, whose kit front is local +Z, so
-- Mesh.CFrame.LookVector is the front. A Model skin (WorldProps) is not turned and its front is -Z, which
-- is also Mesh.CFrame.LookVector. Without a Mesh (MeshSwap not run) fall back to -LookVector (Part) or the
-- pivot LookVector (Model), noted in front_src.
local HttpService = game:GetService("HttpService")
local cfg = HttpService:JSONDecode(%%CHECKS%%)
local centre = Vector3.new(cfg.plaza_centre[1], 0, cfg.plaza_centre[2])
local frontParts = cfg.front_parts or {}

local function flat(v)
	local f = Vector3.new(v.X, 0, v.Z)
	return if f.Magnitude > 1e-6 then f.Unit else f
end
local function dotAngle(a, b)
	local d = flat(a):Dot(flat(b))
	return d, math.deg(math.acos(math.clamp(d, -1, 1)))
end
local function r(n)
	return math.round(n * 1000) / 1000
end
local function v3(v)
	return { r(v.X), r(v.Y), r(v.Z) }
end
local function find(root, name, all)
	local out = {}
	for _, d in root:GetDescendants() do
		if d.Name == name and (d:IsA("BasePart") or d:IsA("Model")) then
			table.insert(out, d)
			if not all then
				break
			end
		end
	end
	return out
end
-- (front vector, source) of a slot / model instance
local function front(inst)
	local base = inst
	local sub = frontParts[inst.Name]
	if sub then
		base = inst:FindFirstChild(sub) or inst
	end
	local mesh = base:FindFirstChild("Mesh")
	if mesh and mesh:IsA("BasePart") then
		return mesh.CFrame.LookVector, "Mesh"
	end
	if base:IsA("Model") then
		return base:GetPivot().LookVector, "model -Z (no Mesh)"
	end
	return -base.CFrame.LookVector, "slot +Z (no Mesh)"
end
local function position(inst)
	if inst:IsA("Model") then
		local cf = inst:GetBoundingBox()
		return cf.Position
	end
	return inst.Position
end

local out = {}

-- a) bench -> campfire
do
	local c, items, errors = cfg.bench_faces_campfire, {}, {}
	local fires = find(workspace, c.target, true)
	local benches = find(workspace, c.bench, true)
	if #benches == 0 then
		table.insert(errors, `no {c.bench} in workspace`)
	end
	if #fires == 0 then
		table.insert(errors, `no {c.target} in workspace`)
	end
	for _, b in benches do
		local best, bd = nil, math.huge
		for _, f in fires do
			local d = Vector3.new(f.Position.X - b.Position.X, 0, f.Position.Z - b.Position.Z).Magnitude
			if d < bd then
				best, bd = f, d
			end
		end
		if best then
			local fr, src = front(b)
			local dot, ang = dotAngle(fr, best.Position - b.Position)
			table.insert(items, { name = b:GetFullName(), campfire = best:GetFullName(), distance = r(bd), front = v3(fr), front_src = src, dot = r(dot), angle_deg = r(ang) })
		end
	end
	out.bench_faces_campfire = { items = items, errors = errors }
end

-- b) shops -> plaza centre
do
	local c, items, errors = cfg.shops_face_centre, {}, {}
	local seen = {}
	for _, name in c.names do
		for _, s in find(workspace, name, true) do
			local nested = false
			for p in seen do
				if s:IsDescendantOf(p) then
					nested = true
				end
			end
			if not nested then
				seen[s] = true
				local pos = position(s)
				local fr, src = front(s)
				local dot, ang = dotAngle(fr, centre - pos)
				table.insert(items, { name = s:GetFullName(), pos = v3(pos), front = v3(fr), front_src = src, dot = r(dot), angle_deg = r(ang) })
			end
		end
	end
	if #items == 0 then
		table.insert(errors, "no shop instance found: " .. table.concat(c.names, ", "))
	end
	out.shops_face_centre = { items = items, errors = errors }
end

-- c) silo centre
do
	local c, items, errors = cfg.silo_centred, {}, {}
	local slot = find(workspace, c.slot, false)[1]
	if not slot then
		table.insert(errors, `no {c.slot} in workspace`)
	else
		local bbox = slot.Position
		local mesh = slot:FindFirstChild("Mesh")
		local axis = Vector3.new(bbox.X + c.silo_offset[1], 0, bbox.Z + c.silo_offset[2])
		local want = Vector3.new(c.centre[1], 0, c.centre[2])
		local item = {
			name = slot:GetFullName(),
			bbox_centre = v3(bbox),
			silo_offset = c.silo_offset,
			silo_axis_xz = { r(axis.X), r(axis.Z) },
			dist = r((axis - want).Magnitude),
			raw_bbox_dist = r(Vector3.new(bbox.X - want.X, 0, bbox.Z - want.Z).Magnitude),
		}
		if mesh and mesh:IsA("BasePart") then
			item.mesh_bbox_centre = v3(mesh.Position)
			local _, slotYaw = slot.CFrame:ToOrientation()
			local _, meshYaw = mesh.CFrame:ToOrientation()
			item.mesh_turn_deg = r(math.deg((meshYaw - slotYaw) % (2 * math.pi)))
		end
		table.insert(items, item)
	end
	out.silo_centred = { items = items, errors = errors }
end

-- d) plot signs: the name label on jar 1's glass. Each SurfaceGui must sit on the configured face, point out of the
-- jar (away from the plot centre, the Base) and not read mirrored.
do
	local c, items, errors = cfg.plot_signs, {}, {}
	local folder = workspace:FindFirstChild(c.plots_folder)
	if not folder then
		table.insert(errors, `no workspace.{c.plots_folder}`)
	else
		for _, plot in folder:GetChildren() do
			local sign = plot:FindFirstChild(c.sign, true)
			local base = plot.PrimaryPart
			if not (sign and sign:IsA("BasePart") and base) then
				table.insert(errors, `{plot.Name}: no {c.sign} part or no PrimaryPart`)
			else
				local offset = sign.Position - base.Position
				local out_dir = flat(offset)
				local cf = sign.CFrame
				local det = cf.RightVector:Cross(cf.UpVector):Dot(-cf.LookVector)
				local guis = {}
				for _, g in sign:GetChildren() do
					if g:IsA("SurfaceGui") then
						table.insert(guis, g)
					end
				end
				if #guis == 0 then
					table.insert(errors, `{plot.Name}: {c.sign} has no SurfaceGui`)
				end
				for _, g in guis do
					local n = cf:VectorToWorldSpace(Vector3.fromNormalId(g.Face))
					local texts = {}
					for _, t in g:GetDescendants() do
						if t:IsA("TextLabel") then
							texts[t.Name] = t.Text
						end
					end
					local dotOut, angOut = dotAngle(n, out_dir)
					local item = {
						name = `{plot.Name}/{sign.Name}/{g.Name}`,
						face = g.Face.Name,
						normal = v3(n),
						dot_out = r(dotOut),
						angle_out_deg = r(angOut),
						radius = r(Vector3.new(offset.X, 0, offset.Z).Magnitude),
						text = texts,
						enabled = g.Enabled,
						frame_det = r(det),
						mirrored = det < 0.5,
						size = v3(sign.Size),
					}
					table.insert(items, item)
				end
			end
		end
		if #items == 0 and #errors == 0 then
			table.insert(errors, "no plots")
		end
	end
	out.plot_signs = { items = items, errors = errors }
end

return out
