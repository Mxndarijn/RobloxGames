-- Client datamodel: SlimeUI state plus click centres (viewport px, GuiInset added) of the
-- buttons the watcher clicks. Names come from src/ui (init.client, Hud, Nav, Widgets.panel,
-- Panels/TutorialOverlay).
local GuiService = game:GetService("GuiService")
local p = game:GetService("Players").LocalPlayer
local gui = p.PlayerGui:FindFirstChild("SlimeUI")
if not gui then
	return { gui = false }
end
local inset = GuiService:GetGuiInset()
local off = if gui.IgnoreGuiInset then Vector2.zero else inset
local vp = workspace.CurrentCamera.ViewportSize

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
local function find(path)
	local cur = gui
	for _, part in string.split(path, ".") do
		cur = cur and cur:FindFirstChild(part)
	end
	return cur
end
local function rect(path)
	local o = find(path)
	if not o or not o:IsA("GuiObject") then
		return { found = false }
	end
	local ap, as = o.AbsolutePosition, o.AbsoluteSize
	return {
		found = true,
		shown = shown(o),
		x = ap.X,
		y = ap.Y,
		w = as.X,
		h = as.Y,
		cx = ap.X + as.X / 2 + off.X,
		cy = ap.Y + as.Y / 2 + off.Y,
	}
end

local targets = {}
for _, path in { "Hud.Shop", "Nav.Shop", "ShopPanel", "ShopPanel.Close", "TutorialOverlay", "TutorialOverlay.Hide", "DailyPopup" } do
	targets[path] = rect(path)
end
local openPanels = {}
for _, child in gui:GetChildren() do
	if child:IsA("GuiObject") and string.sub(child.Name, -5) == "Panel" and child.Visible then
		table.insert(openPanels, child.Name)
	end
end
local counter = find("TutorialOverlay.Counter")
local title = find("TutorialOverlay.Title")
return {
	gui = true,
	inset = { inset.X, inset.Y },
	viewport = { vp.X, vp.Y },
	gui_size = { gui.AbsoluteSize.X, gui.AbsoluteSize.Y },
	shop_open = targets.ShopPanel.found and targets.ShopPanel.shown,
	tutorial_visible = targets.TutorialOverlay.found and targets.TutorialOverlay.shown,
	tutorial_counter = if counter then counter.Text else nil,
	tutorial_title = if title then title.Text else nil,
	step = p:GetAttribute("TutorialStep"),
	step_id = p:GetAttribute("TutorialStepId"),
	carrying = p:GetAttribute("Carrying"),
	open_panels = openPanels,
	targets = targets,
}
