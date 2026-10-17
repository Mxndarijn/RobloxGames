-- Server datamodel: release probe R3 (ADVISORY), #264 merge_vat: every plot's MergeVat disc wears the merge_vat MeshPart ("VatMesh", MeshSwap.swapPlotVats)
-- with Hull collision (MeshAssets.COLLISION). For every plot in workspace.Plots (the plot Base is the footprint / ground reference):
-- Checks (ok = every non-nil check true; each lists every plot in its info):
--   vat_exists        a "VatMesh" MeshPart (else any MeshPart under the plot's MergeVat / named *vat*) exists
--   hull_collides     CanCollide true and CollisionFidelity Hull
--   sits_on_plot      the mesh centre is inside the Base footprint (Base frame) and its bottom is within 1 stud of the Base top
--   character_rests   the REAL test player's character (unanchored, server network ownership) dropped 6 studs over the mesh top (at its centre)
--                     rests on it for 1.5 s: feet within -0.5..+1.5 of the top, not inside it, not fallen through (feet < Base top - 2)
-- The vat meshes are CanQuery false (MeshSwap): CanQuery is set true for the raycast and restored. The character ends where it started. ~20 s.
local Players = game:GetService("Players")
local ORDER = { "vat_exists", "hull_collides", "sits_on_plot", "character_rests" }
local checks = {}
local function set(name, ok, info)
	checks[name] = { ok = ok, info = info }
end
local function finish(extra)
	local parts, all, any = {}, true, false
	for _, name in ORDER do
		local c = checks[name] or { ok = nil, info = "not run" }
		checks[name] = c
		table.insert(parts, name .. " " .. (if c.ok == true then "PASS" elseif c.ok == false then "FAIL" else "n/a"))
		if c.ok == false then
			all = false
		elseif c.ok == true then
			any = true
		end
	end
	return {
		ok = if not all then false elseif any then true else nil,
		summary = table.concat(parts, ", "),
		detail = { checks = checks, extra = extra },
	}
end
local function missing(msg)
	return { ok = false, summary = msg, detail = { checks = checks } }
end

local player = Players:GetPlayers()[1]
if not player then
	return finish("no real Player in the server")
end
-- character: the REAL test player's, unanchored with server network ownership for the probe and restored at the end -------------------
local char, hum, root = player.Character, nil, nil
hum = char and char:FindFirstChildOfClass("Humanoid")
root = char and char:FindFirstChild("HumanoidRootPart")
if not (root and hum) then
	return finish("the test player has no character")
end
local startCF = root.CFrame
local startAnchored = {}
for _, d in char:GetDescendants() do
	if d:IsA("BasePart") then
		startAnchored[d] = d.Anchored
	end
end
local startSpeed = hum.WalkSpeed
local function free()
	for _, d in char:GetDescendants() do
		if d:IsA("BasePart") then
			d.Anchored = false
		end
	end
	hum.WalkSpeed = 16
	pcall(function()
		root:SetNetworkOwner(nil)
	end)
end
local function teleport(cf)
	char:PivotTo(cf)
	root.AssemblyLinearVelocity = Vector3.zero
	root.AssemblyAngularVelocity = Vector3.zero
end
local made = {}
local undo = {} -- functions that restore what the probe touched
local extraInfo = {}
local plots = workspace:FindFirstChild("Plots")
if not plots then
	return missing("workspace.Plots missing")
end
local function findVat(plot)
	local disc = plot:FindFirstChild("MergeVat")
	local m = disc and disc:FindFirstChild("VatMesh")
	if m and m:IsA("MeshPart") then
		return m
	end
	for _, d in plot:GetDescendants() do
		if d:IsA("MeshPart") and (d.Name == "VatMesh" or string.find(string.lower(d.Name), "vat") or d:GetAttribute("MeshAsset") == "merge_vat") then
			return d
		end
	end
	return nil
end
local rows = {}
local list = plots:GetChildren()
table.sort(list, function(a, b)
	return a.Name < b.Name
end)
for _, plot in list do
	local base = plot:FindFirstChild("Base")
	if plot:IsA("Model") and base and base:IsA("BasePart") then
		local row = { plot = plot.Name }
		local mesh = findVat(plot)
		row.exists = mesh ~= nil
		if mesh then
			row.can_collide, row.fidelity = mesh.CanCollide, tostring(mesh.CollisionFidelity)
			row.hull = mesh.CanCollide and mesh.CollisionFidelity == Enum.CollisionFidelity.Hull
			local l = base.CFrame:PointToObjectSpace(mesh.Position)
			local baseTop = base.Position.Y + base.Size.Y / 2
			local bottom = mesh.Position.Y - mesh.Size.Y / 2
			row.inside_footprint = math.abs(l.X) <= base.Size.X / 2 and math.abs(l.Z) <= base.Size.Z / 2
			row.bottom_over_base = bottom - baseTop
			row.on_plot = row.inside_footprint and math.abs(bottom - baseTop) <= 1.05
			row.mesh = mesh
		end
		table.insert(rows, row)
	end
end

local function aggregate(name, field, note)
	local bad, n, any = {}, 0, false
	for _, row in rows do
		local v = row[field]
		if v ~= nil then
			any = true
		end
		if v == false then
			table.insert(bad, row.plot)
		end
		n += 1
	end
	local per = {}
	for _, row in rows do
		table.insert(per, { plot = row.plot, ok = row[field], fidelity = row.fidelity, bottom_over_base = row.bottom_over_base, feet_over_top = row.feet_over_top, fell_through = row.fell_through, inside = row.inside, note = row.rests_note })
	end
	set(name, if not any then nil else #bad == 0, { plots = n, failing = bad, per_plot = per })
end

local function run()
	if #rows == 0 then
		return
	end
	local deadline = os.clock() + 22
	free()
	for _, row in rows do
		local mesh = row.mesh
		if not mesh then
			continue
		end
		if os.clock() > deadline then
			row.rests = nil
			row.rests_note = "not run (time budget)"
			continue
		end
		local q = mesh.CanQuery
		mesh.CanQuery = true
		local rpm = RaycastParams.new()
		rpm.FilterType = Enum.RaycastFilterType.Include
		rpm.FilterDescendantsInstances = { mesh }
		local hit = workspace:Raycast(mesh.Position + Vector3.new(0, mesh.Size.Y + 5, 0), Vector3.new(0, -(mesh.Size.Y + 10), 0), rpm)
		mesh.CanQuery = q
		local top = if hit then hit.Position.Y else mesh.Position.Y + mesh.Size.Y / 2
		row.top = top
		local base = mesh.Parent and mesh:FindFirstAncestorOfClass("Model") and mesh:FindFirstAncestorOfClass("Model"):FindFirstChild("Base")
		local baseTop = if base then base.Position.Y + base.Size.Y / 2 else top - mesh.Size.Y
		local feetOff = hum.HipHeight + root.Size.Y / 2
		teleport(CFrame.new(mesh.Position.X, top + 6 + feetOff, mesh.Position.Z))
		task.wait(1.5)
		local feet = root.Position.Y - feetOff
		row.feet_over_top = feet - top
		row.fell_through = feet < baseTop - 2
		row.inside = feet < top - 0.5 and not row.fell_through
		row.rests = feet >= top - 0.5 and feet <= top + 1.5 and root.AssemblyLinearVelocity.Magnitude < 3
	end
	aggregate("character_rests", "rests")
end
if #rows == 0 then
	set("vat_exists", nil, "no plot with a Base in workspace.Plots")
else
	aggregate("vat_exists", "exists")
	aggregate("hull_collides", "hull")
	aggregate("sits_on_plot", "on_plot")
end
extraInfo.plots = #rows

local ok, err = pcall(run)
for _, o in made do
	pcall(function()
		o:Destroy()
	end)
end
for _, fn in undo do
	pcall(fn)
end
pcall(function()
	hum:MoveTo(root.Position)
	for _, d in char:GetDescendants() do
		if d:IsA("BasePart") then
			d.Anchored = false
		end
	end
	char:PivotTo(startCF)
	root.AssemblyLinearVelocity = Vector3.zero
	hum.WalkSpeed = startSpeed
	pcall(function()
		root:SetNetworkOwnershipAuto()
	end)
	for d, a in startAnchored do
		d.Anchored = a
	end
end)
if not ok then
	for _, name in ORDER do
		if not checks[name] then
			set(name, false, "probe error: " .. tostring(err))
		end
	end
	return finish("probe error: " .. tostring(err))
end
return finish(extraInfo)
