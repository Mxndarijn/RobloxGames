-- Client datamodel: size and placement of SlimeUI.%%PANEL%% and its Close button, in the same
-- rect hud_check uses (ScreenGui = viewport minus the top bar, 1 px tolerance).
-- frac_* are AbsoluteSize / ViewportSize (#76 menus are content-sized cards, not full-window).
local p = game:GetService("Players").LocalPlayer
local gui = p.PlayerGui:FindFirstChild("SlimeUI")
if not gui then
	return { gui = false }
end
local vp = workspace.CurrentCamera.ViewportSize
local gs = gui.AbsoluteSize
local TOL = 1
local function shown(o)
	local cur = o
	while cur and cur ~= gui do
		if cur:IsA("GuiObject") and not cur.Visible then
			return false
		end
		cur = cur.Parent
	end
	return gui.Enabled
end
local function inside(o)
	local ap, as = o.AbsolutePosition, o.AbsoluteSize
	return ap.X >= -TOL and ap.Y >= -TOL and ap.X + as.X <= gs.X + TOL and ap.Y + as.Y <= gs.Y + TOL
end
local panel = gui:FindFirstChild(%%PANEL%%)
if not panel or not panel:IsA("GuiObject") then
	return { gui = true, found = false }
end
local as, ap = panel.AbsoluteSize, panel.AbsolutePosition
local close = panel:FindFirstChild("Close", true)
local closeInfo = { found = false }
if close and close:IsA("GuiObject") then
	local cs, cp = close.AbsoluteSize, close.AbsolutePosition
	closeInfo = {
		found = true,
		shown = shown(close),
		on_screen = inside(close),
		size = { cs.X, cs.Y },
		pos = { cp.X, cp.Y },
	}
end
return {
	gui = true,
	found = true,
	shown = shown(panel),
	on_screen = inside(panel),
	size = { as.X, as.Y },
	pos = { ap.X, ap.Y },
	viewport = { vp.X, vp.Y },
	gui_size = { gs.X, gs.Y },
	close = closeInfo,
}
