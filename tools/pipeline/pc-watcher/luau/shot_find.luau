-- Server datamodel: locate a shots.json target by name (exact first, else first substring match).
local pat = string.lower(%%TARGET%%)
local Players = game:GetService("Players")
local exact, loose
for _, d in workspace:GetDescendants() do
	if (d:IsA("Model") or d:IsA("BasePart")) and not Players:GetPlayerFromCharacter(d) then
		local n = string.lower(d.Name)
		if n == pat then
			exact = d
			break
		end
		if not loose and string.find(n, pat, 1, true) then
			loose = d
		end
	end
end
local hit = exact or loose
if not hit then
	return { found = false }
end
local cf, size
if hit:IsA("Model") then
	cf, size = hit:GetBoundingBox()
else
	cf, size = hit.CFrame, hit.Size
end
local p, lv = cf.Position, cf.LookVector
return { found = true, path = hit:GetFullName(), pos = { p.X, p.Y, p.Z }, look = { lv.X, lv.Y, lv.Z }, size = { size.X, size.Y, size.Z } }
