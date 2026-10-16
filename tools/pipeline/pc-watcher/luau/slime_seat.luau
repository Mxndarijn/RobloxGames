-- Server datamodel: seat a slime on the pad at %%PATH%% (the shot_find path of the shots.json target), so
-- habitat and motion shots always have a slime to look at, and report its seat height. Reuses a tagged
-- slime already standing on the pad (<= 4 studs sideways), else clones a rigged Wild / Pad slime onto the
-- pad top (PcwSeat, unique SlimeId, State "Pad"). Reports gap = slime bottom - pad top (studs): about 0
-- = resting on the pad top; the habitat Seat column keeps the same height (HabitatFx). PATH = "" removes
-- every PcwSeat clone (end of the shots step).
local CollectionService = game:GetService("CollectionService")
for _, m in CollectionService:GetTagged("Slime") do
	if m:GetAttribute("PcwSeat") and (%%PATH%% == "" or not m:GetAttribute("PcwKeep")) then
		m:Destroy()
	end
end
if %%PATH%% == "" then
	return { ok = true, removed = true }
end
local node = game
for part in string.gmatch(%%PATH%%, "[^.]+") do
	if node == game and part == "Workspace" then
		node = workspace
	else
		node = node and node:FindFirstChild(part)
	end
end
if not node then
	return { ok = false, error = "pad not found" }
end
-- The pad slab: the part itself, else the widest flat part of the model.
local pad = nil
if node:IsA("BasePart") then
	pad = node
else
	local best = 0
	for _, d in node:GetDescendants() do
		if d:IsA("BasePart") and d.Name ~= "Seat" and d.Size.X * d.Size.Z > best and not CollectionService:HasTag(d, "Slime") then
			pad, best = d, d.Size.X * d.Size.Z
		end
	end
end
if not pad then
	return { ok = false, error = "no pad part" }
end
local top = pad.Position + Vector3.new(0, pad.Size.Y / 2, 0)
local function bottom(m)
	local cf, size = m:GetBoundingBox()
	return cf.Position.Y - size.Y / 2
end
local seated, sources = nil, {}
for _, m in CollectionService:GetTagged("Slime") do
	if m:IsA("Model") and m:FindFirstChild("AnimationController") and m:GetAttribute("DespawnAt") == nil then
		local p = m:GetPivot().Position
		if Vector2.new(p.X - top.X, p.Z - top.Z).Magnitude <= 4 and math.abs(p.Y - top.Y) < 6 then
			seated = seated or m
		elseif m:GetAttribute("State") == "Wild" or m:GetAttribute("State") == "Pad" then
			table.insert(sources, m)
		end
	end
end
local cloned = false
if not seated then
	local src = sources[1]
	if not src then
		return { ok = false, error = "no rigged slime to seat" }
	end
	seated = src:Clone()
	seated:SetAttribute("PcwSeat", true)
	seated:SetAttribute("SlimeId", "pcw-seat-" .. pad:GetFullName())
	seated:SetAttribute("State", "Pad")
	seated:SetAttribute("DespawnAt", nil)
	seated.Parent = workspace
	local drop = seated:GetPivot().Position.Y - bottom(seated)
	seated:PivotTo(CFrame.new(top.X, top.Y + drop, top.Z) * seated:GetPivot().Rotation)
	cloned = true
end
return { ok = true, cloned = cloned, slime = seated:GetFullName(), pad = pad:GetFullName(), pad_top = top.Y, gap = bottom(seated) - top.Y }
