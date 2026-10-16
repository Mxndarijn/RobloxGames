-- Client datamodel: shows (%%ON%% true) or hides the Daily reward popup (SlimeUI.DailyPopup). The popup's own
-- state is already rendered by init.client; this only flips its backdrop Visible (what DailyPopup.isOpen reads),
-- so Esc / gamepad B (cas_close) closes it like a real open.
local gui = game:GetService("Players").LocalPlayer.PlayerGui:FindFirstChild("SlimeUI")
local popup = gui and gui:FindFirstChild("DailyPopup")
if not popup or not popup:IsA("GuiObject") then
	return { found = false }
end
popup.Visible = %%ON%%
task.wait(0.3)
return { found = true, visible = popup.Visible }
