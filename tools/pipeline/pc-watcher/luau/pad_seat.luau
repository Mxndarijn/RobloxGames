-- Server datamodel: shot set-up. Puts a real rigged slime on the pad at %%PATH%% like WorldView does
-- (model under the plot's "Slimes" folder, PivotTo(pad top): slime models pivot at the bottom
-- centre). The live World is a local of src/server, so a tagged rigged slime (AnimationController) is
-- cloned instead (as slime_fill does); an earlier PcwPad clone is replaced. Returns the slime, its
-- bottom Y (seat_y) and the pad top Y.
local node = game
for part in string.gmatch(%%PATH%%, "[^.]+") do
	if node == game and part == "Workspace" then
		node = workspace
	else
		node = node and node:FindFirstChild(part)
	end
end
if not node or not node:IsA("BasePart") then
	return { ok = false, error = "pad not found" }
end
local CollectionService = game:GetService("CollectionService")
local source
for _, m in CollectionService:GetTagged("Slime") do
	if m:GetAttribute("PcwPad") then
		m:Destroy()
	elseif not source and m:IsA("Model") and m:FindFirstChild("AnimationController") and not m:GetAttribute("PcwFill") then
		source = m
	end
end
if not source then
	return { ok = false, error = "no rigged slime to clone" }
end
local plot = node.Parent
local slime = source:Clone()
slime:SetAttribute("PcwPad", true)
slime:SetAttribute("SlimeId", "pcw-pad")
slime:SetAttribute("State", "Pad")
slime:SetAttribute("DespawnAt", nil)
slime.Parent = if plot then plot:FindFirstChild("Slimes") or plot else workspace
local top = node.CFrame * CFrame.new(0, node.Size.Y / 2, 0)
slime:PivotTo(top)
local cf, size = slime:GetBoundingBox()
return {
	ok = true,
	slime = slime.Name,
	seat_y = cf.Position.Y - size.Y / 2,
	pad_top_y = top.Position.Y,
}
