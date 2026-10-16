-- Client datamodel: sets the Studio-only SlimeUI attribute "PcwAdminEvent" (src/ui/init.client) to
-- %%EVENT%% ("luck" | "mutation" | "rain"; empty = the real State), so the live admin event banner on the
-- HUD can be shot without a second admin account. Never active in live servers.
local gui = game:GetService("Players").LocalPlayer.PlayerGui:FindFirstChild("SlimeUI")
if not gui then
	return { found = false }
end
gui:SetAttribute("PcwAdminEvent", %%EVENT%%)
task.wait(0.3)
return { found = true, event = gui:GetAttribute("PcwAdminEvent") }
