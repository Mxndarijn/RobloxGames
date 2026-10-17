-- Client datamodel: finds the HUD "EventsBoard" banner (FEATURES.EventsBoard; a Frame of icon + text rows,
-- or the older single TextLabel) and reports whether it is visible, its lines and how many rows carry an
-- icon. Read only.
local players = game:GetService("Players")
local gui = players.LocalPlayer:FindFirstChild("PlayerGui")
local board = if gui then gui:FindFirstChild("EventsBoard", true) else nil
if not board then
	return { found = false, ok = false }
end
local lines, icons = {}, 0
if board:IsA("TextLabel") then
	lines = string.split(board.Text, "\n")
elseif board:IsA("GuiObject") then
	for _, row in board:GetChildren() do
		if row:IsA("Frame") and row.Visible then
			local label = row:FindFirstChild("Text")
			if label and label:IsA("TextLabel") then
				table.insert(lines, label.Text)
			end
			if row:FindFirstChild("Icon") then
				icons += 1
			end
		end
	end
else
	return { found = false, ok = false }
end
local iconsOk = board:IsA("TextLabel") or icons == #lines
return { found = true, ok = board.Visible and #lines >= 2 and iconsOk, visible = board.Visible, lines = lines, icons = icons }
