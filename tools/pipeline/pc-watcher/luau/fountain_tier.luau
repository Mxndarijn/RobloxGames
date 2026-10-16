-- Client datamodel: sets the Studio-only SlimeUI attribute "PcwFountainTier" (read by
-- src/visuals/client/FountainTierFx) to %%TIER%% (1..4; 0 = off) so the fountain wears that tier's ring / crest /
-- glow on a solo Studio server with FEATURES.FountainTiers off. Never active in live servers.
local gui = game:GetService("Players").LocalPlayer.PlayerGui:FindFirstChild("SlimeUI")
if not gui then
	return { found = false }
end
local tier = %%TIER%%
gui:SetAttribute("PcwFountainTier", if tier > 0 then tier else nil)
task.wait(1.2) -- FountainTierFx refresh (2 Hz) + the mesh clone
local folder = workspace:FindFirstChild("ClientFountainTier")
return { found = true, tier = gui:GetAttribute("PcwFountainTier"), meshes = if folder then #folder:GetChildren() else 0 }
