-- Server datamodel: locate a shots/*.json target by name. Exact-name matches sorted by full name (the
-- %%INDEX%%th, 1-based), else the first substring match. `front` = the #75 front (see geometry.luau):
-- the "Mesh" child's LookVector, else -LookVector of a Part slot / the pivot LookVector of a Model.
local pat = string.lower(%%TARGET%%)
local index = %%INDEX%%
local Players = game:GetService("Players")
local exact, loose = {}, nil
for _, d in workspace:GetDescendants() do
	if (d:IsA("Model") or d:IsA("BasePart")) and not Players:GetPlayerFromCharacter(d) then
		local n = string.lower(d.Name)
		if n == pat then
			table.insert(exact, d)
		elseif not loose and string.find(n, pat, 1, true) then
			loose = d
		end
	end
end
table.sort(exact, function(a, b)
	return a:GetFullName() < b:GetFullName()
end)
local hit = exact[index] or (if #exact == 0 then loose else nil)
if not hit then
	return { found = false, matches = #exact }
end
local cf, size
if hit:IsA("Model") then
	cf, size = hit:GetBoundingBox()
else
	cf, size = hit.CFrame, hit.Size
end
local mesh = hit:FindFirstChild("Mesh")
local fr = if mesh and mesh:IsA("BasePart") then mesh.CFrame.LookVector elseif hit:IsA("Model") then hit:GetPivot().LookVector else -hit.CFrame.LookVector
local p, lv = cf.Position, cf.LookVector
return {
	found = true,
	matches = #exact,
	path = hit:GetFullName(),
	pos = { p.X, p.Y, p.Z },
	look = { lv.X, lv.Y, lv.Z },
	front = { fr.X, fr.Y, fr.Z },
	size = { size.X, size.Y, size.Z },
}
