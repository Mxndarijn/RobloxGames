-- Client datamodel: sets the Studio-only SlimeUI attribute "PcwWorldShop" (src/ui/init.client) to %%SHOP%%
-- ("ItemShop" | "UpgradeShop"; "" clears it): the world shop card (open "worldshop") shows that shop when
-- PcwOpen opens it. Never active in live servers.
local gui = game:GetService("Players").LocalPlayer.PlayerGui:FindFirstChild("SlimeUI")
if not gui then
	return { found = false }
end
local shop = %%SHOP%%
gui:SetAttribute("PcwWorldShop", if shop == "" then nil else shop)
return { found = true, shop = gui:GetAttribute("PcwWorldShop") }
