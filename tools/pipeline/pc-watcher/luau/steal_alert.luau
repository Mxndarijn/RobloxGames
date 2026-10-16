-- Client datamodel: sets the Studio-only SlimeUI attribute "PcwStealAlert" (src/ui/init.client,
-- src/ui/StealAlertFx) to %%ON%%: true fakes one theft of my slime (red screen-edge flash held at its
-- peak, direction arrow pointing right with a distance, and the "While you were away ..." toast); false
-- clears it. The fake draws even while FEATURES.StealAlerts is off. Never active in live servers.
local gui = game:GetService("Players").LocalPlayer.PlayerGui:FindFirstChild("SlimeUI")
if not gui then
	return { found = false }
end
local on = %%ON%%
gui:SetAttribute("PcwStealAlert", if on then true else nil)
task.wait(0.8)
local fx = gui:FindFirstChild("StealAlertFx")
local arrow = fx and fx:FindFirstChild("ThiefArrow")
return {
	found = true,
	on = gui:GetAttribute("PcwStealAlert") == true,
	fx = fx ~= nil,
	arrow_visible = arrow ~= nil and arrow.Visible,
}
