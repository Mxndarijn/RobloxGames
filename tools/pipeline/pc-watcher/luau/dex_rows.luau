-- Client datamodel: sets the Studio-only SlimeUI attribute "PcwDexRows" (src/ui/init.client forceDex) to %%COUNT%%
-- (> 0 = fake that many discovered Dex keys in State.dex so the list is long enough to scroll; 0 clears it).
-- Never active in live servers.
local gui = game:GetService("Players").LocalPlayer.PlayerGui:FindFirstChild("SlimeUI")
if not gui then
	return { found = false }
end
local count = %%COUNT%%
gui:SetAttribute("PcwDexRows", if count > 0 then count else nil)
task.wait(0.3)
return { found = true, rows = gui:GetAttribute("PcwDexRows") }
