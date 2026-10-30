-- WalkCheck common part (Client and Server): resolves CASE (set by run.py above this file) to a drop spot.
-- A case's spot is one of:
--   { at = { x, z }, top = y }       world x, z; ground = first solid surface below y `top` (default 80)
--   { behind = "Map/Decor/Well", gap = 3 }  past that part / model, on the side away from the nearest lane point
--   { lane = share, out = studs }    `out` studs from the lane centre at LENGTH * share, away from the fountain
local RS = game:GetService("ReplicatedStorage")
local Constants = require(RS.Shared.Constants)
local ParadeLane = require(RS.Shared.ParadeLane)

local function solidParams(): RaycastParams
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.RespectCanCollide = true
	local exclude: { Instance } = {}
	local wild = workspace:FindFirstChild(Constants.WILD_FOLDER)
	if wild then
		table.insert(exclude, wild)
	end
	for _, plot in workspace[Constants.PLOTS_FOLDER]:GetChildren() do
		local slimes = plot:FindFirstChild(Constants.PLOT_SLIMES_FOLDER)
		if slimes then
			table.insert(exclude, slimes)
		end
	end
	for _, player in game:GetService("Players"):GetPlayers() do
		if player.Character then
			table.insert(exclude, player.Character)
		end
	end
	local temp = workspace:FindFirstChild("WalkCheckTemp")
	if temp then
		table.insert(exclude, temp)
	end
	params.FilterDescendantsInstances = exclude
	return params
end

-- Solid parts that overlap a ball or box at `cf`, by their real collision geometry (GetPartsInPart through a probe
-- part; the bounds queries would count the fountain's whole bounding box as solid). Slimes, characters and the
-- terrain never count; the case's own walls count when `walls` is true.
local probes: { [string]: Part } = {}
local function solidsIn(cf: CFrame, size: Vector3, shape: Enum.PartType, walls: boolean): { BasePart }
	local key = shape.Name
	local probe = probes[key]
	if not probe or not probe.Parent then
		local folder = workspace:FindFirstChild("WalkCheckProbe") or Instance.new("Folder")
		folder.Name = "WalkCheckProbe"
		folder.Parent = workspace
		probe = Instance.new("Part")
		probe.Name = "Probe" .. key
		probe.Shape = shape
		probe.Anchored = true
		probe.CanCollide = false
		probe.CanQuery = false
		probe.CanTouch = false
		probe.Transparency = 1
		probe.Parent = folder
		probes[key] = probe
	end
	probe.Size = size
	probe.CFrame = cf
	local exclude = solidParams().FilterDescendantsInstances
	table.insert(exclude, workspace.Terrain)
	table.insert(exclude, probe.Parent)
	if walls then
		local temp = workspace:FindFirstChild("WalkCheckTemp")
		local i = table.find(exclude, temp)
		if i then
			table.remove(exclude, i)
		end
	end
	local op = OverlapParams.new()
	op.FilterType = Enum.RaycastFilterType.Exclude
	op.RespectCanCollide = true
	op.FilterDescendantsInstances = exclude
	return workspace:GetPartsInPart(probe, op)
end

local function groundAt(x: number, z: number, top: number?): number?
	local from = top or 80
	local hit = workspace:Raycast(Vector3.new(x, from, z), Vector3.new(0, -(from + 50), 0), solidParams())
	return if hit then hit.Position.Y else nil
end

local function find(path: string): Instance?
	local node: Instance? = workspace
	for name in string.gmatch(path, "[^/]+") do
		node = node and node:FindFirstChild(name)
	end
	return node
end

local function boxOf(inst: Instance): (CFrame, Vector3)
	if inst:IsA("Model") then
		return inst:GetBoundingBox()
	end
	local part = inst :: BasePart
	return part.CFrame, part.Size
end

-- The drop spot (world Vector3 on the ground) for CASE, or nil and why.
local function resolveSpot(case: any): (Vector3?, string?)
	local x, z, top
	if case.at then
		x, z, top = case.at[1], case.at[2], case.top
	elseif case.behind then
		local inst = find(case.behind)
		if not inst then
			return nil, "no " .. case.behind
		end
		local cf, size = boxOf(inst)
		local s = ParadeLane.nearest(cf.X, cf.Z)
		local lx, lz = ParadeLane.pointAt(s)
		local away = Vector3.new(cf.X - lx, 0, cf.Z - lz).Unit
		-- out past the part's footprint along `away`, then `gap` more
		local reach = math.abs(cf.RightVector:Dot(away)) * size.X / 2 + math.abs(cf.LookVector:Dot(away)) * size.Z / 2
		local p = cf.Position + away * (reach + (case.gap or 3))
		x, z, top = p.X, p.Z, case.top or 4
	elseif case.lane then
		local cx, cz = ParadeLane.pointAt(ParadeLane.LENGTH * case.lane)
		local out = Vector3.new(cx, 0, cz).Unit * case.out
		x, z, top = cx + out.X, cz + out.Z, case.top or 6
	else
		return nil, "case has no spot"
	end
	local y = groundAt(x, z, top)
	if not y then
		return nil, "no ground under the spot"
	end
	-- a slime must fit there: nothing solid in a small box from 0.8 studs over the ground (clear of a sloped roof) up
	-- (a ray that starts inside a mesh misses it and lands on the floor under it)
	local inside = solidsIn(CFrame.new(x, y + 2.6, z), Vector3.new(2, 3.6, 2), Enum.PartType.Block, false)
	if #inside > 0 then
		return nil, "spot is inside " .. inside[1].Parent.Name .. "/" .. inside[1].Name
	end
	return Vector3.new(x, y, z), nil
end
