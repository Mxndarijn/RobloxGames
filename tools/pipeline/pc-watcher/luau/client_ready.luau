-- Client datamodel: is the play client up (LocalPlayer, character, SlimeUI)?
local Players = game:GetService("Players")
local p = Players.LocalPlayer
if not p then
	return { ready = false, why = "no LocalPlayer" }
end
local pg = p:FindFirstChildOfClass("PlayerGui")
local gui = pg and pg:FindFirstChild("SlimeUI")
local cam = workspace.CurrentCamera
return {
	ready = gui ~= nil and p.Character ~= nil and p:GetAttribute("TutorialStepId") ~= nil,
	player = p.Name,
	has_gui = gui ~= nil,
	has_character = p.Character ~= nil,
	step_id = p:GetAttribute("TutorialStepId"),
	store_status = workspace:GetAttribute("DataStoreStatus"),
	viewport = if cam then { cam.ViewportSize.X, cam.ViewportSize.Y } else nil,
}
