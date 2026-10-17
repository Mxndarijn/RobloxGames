-- Client datamodel: sets the Studio-only SlimeUI attribute "PcwTooltip" (src/ui/init.client) to %%ID%% ("Rain" |
-- "Event" | "Friend": opens that bottom-right status icon's tooltip, B8; "" closes it). Reports the tooltip card's
-- visibility, text and whether it lies inside the ScreenGui. Never active in live servers.
local gui = game:GetService("Players").LocalPlayer.PlayerGui:FindFirstChild("SlimeUI")
if not gui then
	return { found = false }
end
gui:SetAttribute("PcwTooltip", %%ID%%)
task.wait(0.4)
local tip = gui:FindFirstChild("Tooltip")
if not tip or not tip:IsA("GuiObject") then
	return { found = true, tooltip = false }
end
local ap, as, gs = tip.AbsolutePosition, tip.AbsoluteSize, gui.AbsoluteSize
local function text(name)
	local label = tip:FindFirstChild(name)
	return label and label.Text or ""
end
return {
	found = true,
	tooltip = true,
	visible = tip.Visible,
	title = text("Title"),
	body = text("Body"),
	time = text("Time"),
	on_screen = ap.X >= -1 and ap.Y >= -1 and ap.X + as.X <= gs.X + 1 and ap.Y + as.Y <= gs.Y + 1,
}
