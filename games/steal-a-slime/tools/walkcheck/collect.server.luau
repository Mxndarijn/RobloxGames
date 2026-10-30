-- WalkCheck (Server): returns CASE's result once it is done, with the footprints of the solid parts round its path
-- (for the report's top view). Returns { state = ... } while it still records.
local r = _G.WalkCheck and _G.WalkCheck[CASE.id]
if not r or r.state ~= "done" or r.error then
	return r or { state = "missing" }
end
local lo = Vector3.new(math.huge, 0, math.huge)
local hi = Vector3.new(-math.huge, 0, -math.huge)
for _, s in r.path do
	lo = Vector3.new(math.min(lo.X, s[2]), 0, math.min(lo.Z, s[4]))
	hi = Vector3.new(math.max(hi.X, s[2]), 0, math.max(hi.Z, s[4]))
end
local pad = 14
local centre = Vector3.new((lo.X + hi.X) / 2, 30, (lo.Z + hi.Z) / 2)
local size = Vector3.new(hi.X - lo.X + 2 * pad, 64, hi.Z - lo.Z + 2 * pad)
local op = OverlapParams.new()
op.RespectCanCollide = true
op.FilterType = Enum.RaycastFilterType.Exclude
op.FilterDescendantsInstances = { workspace.Terrain }
local feet = {}
for _, part in workspace:GetPartBoundsInBox(CFrame.new(centre), size, op) do
	local isSlime = part:FindFirstAncestor(Constants.WILD_FOLDER)
		or part:FindFirstAncestor(Constants.PLOT_SLIMES_FOLDER)
	local isChar = part:FindFirstAncestorWhichIsA("Model")
		and part:FindFirstAncestorWhichIsA("Model"):FindFirstChildOfClass("Humanoid")
	if not isSlime and not isChar and part.Size.X < 120 and part.Size.Z < 120 and #feet < 220 then
		local cf = part.CFrame
		-- footprint from the part's world bounding size (rotated parts: use the extents along x and z)
		local ex = math.abs(cf.RightVector.X) * part.Size.X
			+ math.abs(cf.UpVector.X) * part.Size.Y
			+ math.abs(cf.LookVector.X) * part.Size.Z
		local ez = math.abs(cf.RightVector.Z) * part.Size.X
			+ math.abs(cf.UpVector.Z) * part.Size.Y
			+ math.abs(cf.LookVector.Z) * part.Size.Z
		local top = cf.Y
			+ (
					math.abs(cf.RightVector.Y) * part.Size.X
					+ math.abs(cf.UpVector.Y) * part.Size.Y
					+ math.abs(cf.LookVector.Y) * part.Size.Z
				)
				/ 2
		table.insert(feet, {
			math.floor(cf.X * 10) / 10,
			math.floor(cf.Z * 10) / 10,
			math.floor(ex * 10) / 10,
			math.floor(ez * 10) / 10,
			math.floor(top * 10) / 10,
			part.Parent.Name .. "/" .. part.Name,
		})
	end
end
local out = table.clone(r)
out.feet = feet
return out
