-- Client datamodel: finds the HUD "EventsBoard" banner (FEATURES.EventsBoard) and reports whether it is
-- visible and what it says. Read only.
local players = game:GetService("Players")
local gui = players.LocalPlayer:FindFirstChild("PlayerGui")
local board = if gui then gui:FindFirstChild("EventsBoard", true) else nil
if not board or not board:IsA("TextLabel") then
	return { found = false, ok = false }
end
local lines = string.split(board.Text, "\n")
return { found = true, ok = board.Visible and #lines >= 2, visible = board.Visible, lines = lines }
