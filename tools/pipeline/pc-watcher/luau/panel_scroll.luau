-- Client datamodel: scrolls every ScrollingFrame under SlimeUI.%%PANEL%% so the descendant named
-- %%TARGET%% is in view (bottom of the canvas when it is not found). Used by shots whose card sits below
-- the scroll fold at the 844x390 crop.
local gui = game:GetService("Players").LocalPlayer.PlayerGui:FindFirstChild("SlimeUI")
local panel = gui and gui:FindFirstChild(%%PANEL%%)
if not panel then
	return { found = false }
end
task.wait(0.3)
local target = panel:FindFirstChild(%%TARGET%%, true)
local scrolled = 0
for _, d in panel:GetDescendants() do
	if d:IsA("ScrollingFrame") then
		local y = d.AbsoluteCanvasSize.Y - d.AbsoluteSize.Y
		if target and target:IsDescendantOf(d) then
			y = target.AbsolutePosition.Y - d.AbsolutePosition.Y + d.CanvasPosition.Y - 4
		end
		d.CanvasPosition = Vector2.new(0, math.max(0, y))
		scrolled += 1
	end
end
task.wait(0.2)
return { found = true, scrolled = scrolled, target = target ~= nil }
