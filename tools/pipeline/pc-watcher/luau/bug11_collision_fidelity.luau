-- Server datamodel: bug probe 11 (ADVISORY), real mesh collision instead of manual collision boxes. Audits every MeshPart in
-- workspace.Map, workspace.Plots and ReplicatedStorage (the client vat meshes) and counts them per CollisionFidelity (and per
-- CanCollide). "Key" meshes are the fountain, slide, vat, statues (name or ancestor name contains fountain / slide / vat /
-- emerge / statue / chute / cauldron). ok = at least one key mesh exists and EVERY key mesh is CanCollide with
-- PreciseConvexDecomposition (Box / Hull / Default / non-colliding are offenders, listed with their fidelity). The manual
-- collider parts (attribute MeshCollider / FountainCollider, CanCollide) are counted as `manual_colliders`.
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
return {
	ok = key > 0 and bad == 0,
	summary = if key == 0 then "no key collidable meshes found (fountain / slide / vat / statues are not MeshParts)"
		else string.format("%d key meshes, %d offender(s) not PreciseConvexDecomposition+CanCollide; %d manual collider parts", key, bad, manual),
	detail = { meshparts = meshes, per_fidelity = fidelity, cancollide = collide, key_meshes = key, offenders = offenders, manual_colliders = manual },
}
