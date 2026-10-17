-- Client datamodel: finds the SoundController mute button (FEATURES.Audio) in SlimeUI and, with %%ON%%, opens
-- its SoundPanel (Mute row + SFX / Music volume sliders) so the frame shows it. false closes it again.
local gui = game:GetService("Players").LocalPlayer.PlayerGui:FindFirstChild("SlimeUI")
local button = if gui then gui:FindFirstChild("MuteToggle") else nil
local panel = if gui then gui:FindFirstChild("SoundPanel") else nil
if not (button and panel) then
	return { ok = false, button = button ~= nil, panel = panel ~= nil }
end
panel.Visible = %%ON%%
task.wait(0.3)
local sliders = 0
for _, d in panel:GetDescendants() do
	if d.Name == "Track" then
		sliders += 1
	end
end
return { ok = sliders >= 2, button = true, panel_visible = panel.Visible, sliders = sliders }
