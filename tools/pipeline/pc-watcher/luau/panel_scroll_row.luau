-- Client datamodel: scrolls the SlimeUI.%%PANEL%% list so its row with LayoutOrder %%ROW%% is at the top of the
-- window (v29 Dex virtualisation proof: row 40 must show a live ViewportFrame). Reports how many ViewportFrames
-- in the list are live (have a WorldModel) and the row's own preview state.
local gui = game:GetService("Players").LocalPlayer.PlayerGui:FindFirstChild("SlimeUI")
local panel = gui and gui:FindFirstChild(%%PANEL%%)
local list = panel and panel:FindFirstChild("List", true)
if not list or not list:IsA("ScrollingFrame") then
	return { found = false }
end
task.wait(0.3)
local target
for _, c in list:GetChildren() do
	if c:IsA("GuiObject") and c.LayoutOrder == %%ROW%% then
		target = c
	end
end
if target then
	list.CanvasPosition = Vector2.new(0, math.max(0, target.Position.Y.Offset - 4))
end
task.wait(0.6)
local live, rowLive = 0, false
for _, d in list:GetDescendants() do
	if d:IsA("ViewportFrame") and d:FindFirstChildWhichIsA("WorldModel") then
		live += 1
		if target and d:IsDescendantOf(target) then
			rowLive = true
		end
	end
end
return { found = true, row_found = target ~= nil, live = live, row_live = rowLive, canvas_y = list.CanvasPosition.Y }
