-- Server datamodel: waits (up to %%WAIT%% s) until the REAL pad slime (a tagged Slime model near the pad at
-- %%PATH%%, never a PcwSeat / PcwPad clone) carries the Growth attribute and the LabelHeight attribute that the
-- server's SlimeLabelView sets (each client draws the slime labels from them). Returns {found, percent, label_text, path,
-- pos, label_pos} (label_pos = the Body position plus LabelHeight, i.e. the bottom edge of the floating tag).
local CollectionService = game:GetService("CollectionService")
local node = game
for part in string.gmatch(%%PATH%%, "[^.]+") do
	if node == game and part == "Workspace" then
		node = workspace
	else
		node = node and node:FindFirstChild(part)
	end
end
if not node then
	return { found = false, error = "pad not found" }
end
local padPos = if node:IsA("BasePart") then node.Position else node:GetPivot().Position
local deadline = os.clock() + %%WAIT%%
local last = { found = false }
while true do
	local best, bestD = nil, 8
	for _, m in CollectionService:GetTagged("Slime") do
		if m:IsA("Model") and not m:GetAttribute("PcwSeat") and not m:GetAttribute("PcwPad") and not m:GetAttribute("PcwFill") then
			local p = m:GetPivot().Position
			local d = Vector2.new(p.X - padPos.X, p.Z - padPos.Z).Magnitude
			if d < bestD and math.abs(p.Y - padPos.Y) < 12 then
				best, bestD = m, d
			end
		end
	end
	if best then
		local percent = best:GetAttribute("Growth")
		local height = best:GetAttribute("LabelHeight")
		local body = best.PrimaryPart or best:FindFirstChild("Body")
		local pos = best:GetPivot().Position
		local labelPos = pos
		if type(height) == "number" and body and body:IsA("BasePart") then
			labelPos = body.Position + Vector3.new(0, height, 0)
		end
		last = {
			found = percent ~= nil or height ~= nil,
			percent = percent,
			label_text = if type(percent) == "number" and percent >= 1 then `Growth {math.min(100, percent)}%` else nil,
			path = best:GetFullName(),
			pos = { pos.X, pos.Y, pos.Z },
			label_pos = { labelPos.X, labelPos.Y, labelPos.Z },
		}
		if percent ~= nil and height ~= nil then
			break
		end
	end
	if os.clock() > deadline then
		last.timed_out = true
		break
	end
	task.wait(0.25)
end
return last
