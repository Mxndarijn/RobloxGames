-- Client datamodel: hold-to-confirm proof shot (B1). %%ON%% = true shows the HoldFill bar of the first visible
-- SlimeUI button named %%NAME%% half full (a hold ring mid-hold, 0.5); false hides it again. Display only: no
-- input is sent and nothing is confirmed.
local gui = game:GetService("Players").LocalPlayer.PlayerGui:FindFirstChild("SlimeUI")
if not gui then
	return { found = false }
end
local seconds = nil
local touched = 0
for _, d in gui:GetDescendants() do
	local fill = d.Name == %%NAME%% and d:IsA("GuiButton") and d:FindFirstChild("HoldFill")
	if fill and fill:IsA("GuiObject") then
		seconds = d:GetAttribute("HoldConfirm")
		fill.Size = UDim2.fromScale(if %%ON%% then 0.5 else 0, 1)
		fill.Visible = %%ON%%
		touched += 1
	end
end
return { found = touched > 0, touched = touched, hold_seconds = seconds }
