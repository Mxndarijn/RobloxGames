-- Client datamodel: bug probe 12 (ADVISORY), stray pink beams / glow decals over the fountain and slide. PlotVisuals puts one
-- RareSpawn "RareFx_<tier>" model per wild rare slime under workspace.ClientRareFx and RareSpawn.place poses it on the slime.
-- The old bug: the per-part offsets lived in a weak-keyed table and got collected, so place() stopped posing parts and they
-- stayed where they were built. Samples ClientRareFx at 0, 2, 4 and 6 s. For every fx model (parented in workspace) it takes
-- the Core / Beam part position and the nearest Slime-tagged model (CollectionService tag "Slime", horizontal distance).
-- Orphans: an fx farther than 3 studs from every slime, OR one that does not move with its slime (the slime moved > 1 stud
-- between samples and the fx moved < half of that). Also scans the whole workspace once for Beam instances (not the
-- TutorialArrow / characters), visible Neon parts named Beam / BeamCore / Ring_*, and visible Decals whose name contains
-- "glow" within 40 studs of the fountain axis (the slide spirals inside r 36) that have no slime within 3 studs.
-- ok = no orphan of any kind. ok = null when there is no fx, no beam and no glow at all (nothing to judge).
local CS = game:GetService("CollectionService")
local Players = game:GetService("Players")
local function slimes()
	local out = {}
	for _, m in CS:GetTagged("Slime") do
		if m:IsA("Model") and m:IsDescendantOf(workspace) then
			table.insert(out, m)
		end
	end
	return out
end
local function nearest(pos, list)
	local best, who = math.huge, nil
	for _, m in list do
		local p = m:GetPivot().Position
		local d = math.sqrt((p.X - pos.X) ^ 2 + (p.Z - pos.Z) ^ 2)
		if d < best then
			best, who = d, m
		end
	end
	return best, who
end
local function fxPart(model)
	return model:FindFirstChild("Core") or model:FindFirstChild("Beam") or model.PrimaryPart or model:FindFirstChildWhichIsA("BasePart")
end
local function r1(x)
	return math.floor(x * 10 + 0.5) / 10
end
local previous = {}
local orphans, stationary, fxSeen = {}, {}, 0
for step = 0, 3 do
	local list = slimes()
	local folder = workspace:FindFirstChild("ClientRareFx")
	local now = {}
	if folder then
		for _, model in folder:GetChildren() do
			local part = model:IsA("Model") and fxPart(model)
			if part then
				local pos = part.Position
				local d, slime = nearest(pos, list)
				now[model] = { pos = pos, slime = slime, slime_pos = slime and slime:GetPivot().Position }
				if step == 0 then
					fxSeen += 1
				end
				if d > 3 and #orphans < 10 then
					table.insert(orphans, { kind = "fx", name = model.Name, pos = { r1(pos.X), r1(pos.Y), r1(pos.Z) }, nearest = r1(d), step = step })
				end
				local was = previous[model]
				if was and slime and was.slime == slime then
					local slimeMoved = (now[model].slime_pos - was.slime_pos) * Vector3.new(1, 0, 1)
					local fxMoved = (pos - was.pos) * Vector3.new(1, 0, 1)
					if slimeMoved.Magnitude > 1 and fxMoved.Magnitude < slimeMoved.Magnitude * 0.5 and #stationary < 10 then
						table.insert(stationary, { name = model.Name, slime_moved = r1(slimeMoved.Magnitude), fx_moved = r1(fxMoved.Magnitude), step = step })
					end
				end
			end
		end
	end
	previous = now
	if step < 3 then
		task.wait(2)
	end
end
-- one full scan for stray beams / glow decals near the fountain and slide
local list = slimes()
local chars = {}
for _, p in Players:GetPlayers() do
	if p.Character then
		chars[p.Character] = true
	end
end
local function inCharacter(inst)
	for c in chars do
		if inst:IsDescendantOf(c) then
			return true
		end
	end
	return false
end
local cam = workspace.CurrentCamera
local stray, candidates = {}, 0
local function check(kind, inst, pos)
	if not pos or pos.X ^ 2 + pos.Z ^ 2 > 40 * 40 then
		return
	end
	candidates += 1
	local d = nearest(pos, list)
	if d > 3 and #stray < 10 then
		table.insert(stray, { kind = kind, path = inst:GetFullName(), pos = { r1(pos.X), r1(pos.Y), r1(pos.Z) }, nearest = r1(d) })
	end
end
for _, d in workspace:GetDescendants() do
	if d:IsA("Beam") and d.Enabled and d.Name ~= "TutorialArrow" and not inCharacter(d) then
		local a = d.Attachment0
		check("Beam", d, a and a.WorldPosition or (d.Parent:IsA("BasePart") and d.Parent.Position))
	elseif d:IsA("BasePart") and d.Transparency < 1 and not inCharacter(d) and not (cam and d:IsDescendantOf(cam)) then
		local n = d.Name
		if d.Material == Enum.Material.Neon and (n == "Beam" or n == "BeamCore" or string.find(n, "^Ring_")) then
			check("NeonPart", d, d.Position)
		end
	elseif d:IsA("Decal") and d.Transparency < 1 and string.find(string.lower(d.Name), "glow", 1, true) and d.Parent:IsA("BasePart") then
		check("GlowDecal", d, d.Parent.Position)
	end
end
local bad = #orphans + #stationary + #stray
local ok = bad == 0
if ok and fxSeen == 0 and candidates == 0 then
	ok = nil
end
return {
	ok = ok,
	summary = if ok == nil then "no RareFx / beams / glow decals present: nothing to judge"
		else string.format("%d fx models, %d orphan(s) > 3 studs from a slime, %d not following, %d stray beam/glow near the fountain", fxSeen, #orphans, #stationary, #stray),
	detail = { fx_models = fxSeen, slimes = #list, orphans = orphans, not_following = stationary, stray = stray, near_fountain_candidates = candidates },
}
