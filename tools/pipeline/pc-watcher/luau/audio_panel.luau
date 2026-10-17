-- Client datamodel: finds the Sound icon button (FEATURES.Audio) in SlimeUI and, with %%ON%%, opens the Sound
-- card through the Studio-only PcwOpen hook (setOpen, like a tap) and checks its Mute row + Music / SFX sliders.
-- false closes it again.
local gui = game:GetService("Players").LocalPlayer.PlayerGui:FindFirstChild("SlimeUI")
local button = if gui then gui:FindFirstChild("SoundButton") else nil
local panel = if gui then gui:FindFirstChild("SoundPanel") else nil
if not (button and panel) then
	return { ok = false, button = button ~= nil, panel = panel ~= nil }
end
local idleVisible = button.Visible
gui:SetAttribute("PcwOpen", nil)
gui:SetAttribute("PcwOpen", if %%ON%% then "Sound" else "")
task.wait(0.4)
local sliders = 0
for _, d in panel:GetDescendants() do
	if d.Name == "Track" then
		sliders += 1
	end
end
return {
	ok = sliders >= 2 and panel.Visible == %%ON%%,
	button = true,
	button_idle_visible = idleVisible,
	panel_visible = panel.Visible,
	sliders = sliders,
}
