-- Client datamodel: fallback when no click opens a panel: SlimeUI.%%PANEL%%.Visible = %%SHOW%%
-- directly (the UI's own setOpen is a local in src/ui/init.client.luau; there is no BindableEvent).
-- Showing one hides the other *Panel frames, like setOpen does.
local gui = game:GetService("Players").LocalPlayer.PlayerGui:FindFirstChild("SlimeUI")
local panel = gui and gui:FindFirstChild(%%PANEL%%)
if not panel or not panel:IsA("GuiObject") then
	return { found = false }
end
if %%SHOW%% then
	for _, c in gui:GetChildren() do
		if c ~= panel and c:IsA("GuiObject") and string.sub(c.Name, -5) == "Panel" then
			c.Visible = false
		end
	end
end
panel.Visible = %%SHOW%%
return { found = true, visible = panel.Visible }
