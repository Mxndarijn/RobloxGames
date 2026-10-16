-- Client datamodel: sets the Studio-only SlimeUI attribute "PcwPlotSkin" (src/ui/init.client, read by
-- src/visuals/client/PlotVisuals too) to the skin id %%SKIN%% ("" = off, "classic" = back to the plain look),
-- so Plot_1 wears a plot skin and the SlimeDex picker shows it on a solo Studio server with
-- FEATURES.PlotSkins off. Never active in live servers.
local gui = game:GetService("Players").LocalPlayer.PlayerGui:FindFirstChild("SlimeUI")
if not gui then
	return { found = false }
end
gui:SetAttribute("PcwPlotSkin", "%%SKIN%%")
task.wait(1.2) -- PlotVisuals refresh (4 Hz) + the decor clone
return { found = true, skin = gui:GetAttribute("PcwPlotSkin") }
