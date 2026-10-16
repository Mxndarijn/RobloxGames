-- Client datamodel: opens (SHOW) or closes SlimeUI.%%PANEL%%: first the Studio-only PcwOpen hook, else Visible =
-- %%SHOW%% directly (no input injection). Showing one hides the other *Panel frames, like setOpen does.
local gui = game:GetService("Players").LocalPlayer.PlayerGui:FindFirstChild("SlimeUI")
local panel = gui and gui:FindFirstChild(%%PANEL%%)
if not panel or not panel:IsA("GuiObject") then
	return { found = false }
end
-- Preferred: the UI's Studio-only "PcwOpen" hook (src/ui/init.client.luau) opens the panel
-- through setOpen, so its contents render. Falls back to Visible below.
do
	local key = string.gsub(%%PANEL%%, "Panel$", "")
	gui:SetAttribute("PcwOpen", nil) -- an unchanged value fires no signal; nil -> setOpen(nil) first
	gui:SetAttribute("PcwOpen", if %%SHOW%% then key else "")
	task.wait(0.3)
	if panel.Visible == %%SHOW%% then
		return { found = true, visible = panel.Visible, via = "pcw_open_hook" }
	end
end
if %%SHOW%% then
	for _, c in gui:GetChildren() do
		if c ~= panel and c:IsA("GuiObject") and string.sub(c.Name, -5) == "Panel" then
			c.Visible = false
		end
	end
end
panel.Visible = %%SHOW%%
return { found = true, visible = panel.Visible, via = "visible_fallback" }
