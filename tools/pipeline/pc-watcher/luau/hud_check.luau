-- Client datamodel: are the HUD and nav buttons fully inside the ScreenGui rect
-- (= viewport minus the top bar, SlimeUI has IgnoreGuiInset = false)? 1 px tolerance.
local p = game:GetService("Players").LocalPlayer
local gui = p.PlayerGui:FindFirstChild("SlimeUI")
if not gui then
	return { gui = false }
end
local cam = workspace.CurrentCamera
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
	return true
end
local expected = {
	"Hud", "Hud.Cash", "Hud.Income", "Hud.Rebirths", "Hud.Pads", "Hud.LockStatus", "Hud.Lock", "Hud.BuyPad", "Hud.Shop", "Hud.Daily",
	"Nav", "Nav.NavToggle", "Nav.Plot", "Nav.Merge", "Nav.Shop", "Nav.Rebirth", "Nav.Goals", "Nav.Dex", "Nav.Leaders",
}
local checked, offscreen, missing, hidden = 0, {}, {}, {}
for _, path in expected do
	local cur = gui
	for _, part in string.split(path, ".") do
		cur = cur and cur:FindFirstChild(part)
	end
	if not cur or not cur:IsA("GuiObject") then
		table.insert(missing, path)
	elseif not shown(cur) then
		table.insert(hidden, path)
	else
		checked += 1
		local ap, as = cur.AbsolutePosition, cur.AbsoluteSize
		if ap.X < -TOL or ap.Y < -TOL or ap.X + as.X > gs.X + TOL or ap.Y + as.Y > gs.Y + TOL then
			table.insert(offscreen, string.format("%s (%d,%d %dx%d in %dx%d)", path, math.floor(ap.X), math.floor(ap.Y), math.floor(as.X), math.floor(as.Y), math.floor(gs.X), math.floor(gs.Y)))
		end
	end
end
return {
	gui = true,
	viewport = { cam.ViewportSize.X, cam.ViewportSize.Y },
	gui_size = { gs.X, gs.Y },
	checked = checked,
	offscreen = offscreen,
	missing = missing,
	hidden = hidden,
}
