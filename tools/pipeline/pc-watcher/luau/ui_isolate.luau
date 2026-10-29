-- Client datamodel: ui proof shot. %%HIDE%% = true hides the tutorial card, popups and every SlimeUI
-- *Panel except %%KEEP%% (marked PcwUiHidden); false shows exactly those again.
local gui = game:GetService("Players").LocalPlayer.PlayerGui:FindFirstChild("SlimeUI")
if not gui then
	return { gui = false }
end
local keep = %%KEEP%%
local names = {}
local banners = gui:FindFirstChild("Banners")
local tutorial = banners and banners:FindFirstChild("Tutorial") -- the tutorial notice cards (src/ui/TutorialCard)
local list = gui:GetChildren()
if tutorial then
	table.insert(list, tutorial)
end
for _, c in list do
	if not c:IsA("GuiObject") or c.Name == keep then
		continue
	end
	local other = c == tutorial or string.sub(c.Name, -5) == "Panel" or string.sub(c.Name, -5) == "Popup"
	if %%HIDE%% then
		if other and c.Visible then
			c:SetAttribute("PcwUiHidden", true)
			c.Visible = false
			table.insert(names, c.Name)
		end
	elseif c:GetAttribute("PcwUiHidden") then
		c:SetAttribute("PcwUiHidden", nil)
		c.Visible = true
		table.insert(names, c.Name)
	end
end
return { gui = true, changed = names }
