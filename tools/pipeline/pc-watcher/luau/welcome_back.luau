-- Client datamodel: sets the Studio-only SlimeUI attribute "PcwWelcome" (src/ui/init.client) to %%ON%%
-- (true = fake State.welcomeBack: 5 h 30 m away, cash, 3 slimes grown) and opens the Welcome card through
-- the normal setOpen path (PcwOpen); false clears both. Never active in live servers.
local gui = game:GetService("Players").LocalPlayer.PlayerGui:FindFirstChild("SlimeUI")
if not gui then
	return { found = false }
end
local on = %%ON%%
gui:SetAttribute("PcwWelcome", if on then true else nil)
task.wait(0.5)
gui:SetAttribute("PcwOpen", if on then "Welcome" else "")
task.wait(0.5)
local card = gui:FindFirstChild("WelcomePanel")
return { found = card ~= nil, visible = card ~= nil and card.Visible }
