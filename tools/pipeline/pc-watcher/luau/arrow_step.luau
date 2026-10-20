-- Client datamodel: TutorialArrow probe. Forces the local Player's TutorialStepId to "%%STEP%%" (client-only
-- attribute; "" restores the real one) so VisualsClient/TutorialArrow lays its ground trail (shared GuideView,
-- workspace.Guide) towards that step's target, waits for its poll, then reports whether trail arrows show and how far
-- the farthest visible arrow is from the character. Pair with fx_streaks, which fails any long Neon part.
local player = game:GetService("Players").LocalPlayer
local step = %%STEP%%
if step == "" then
	player:SetAttribute("TutorialStepId", player:GetAttribute("PcwTutPrev"))
	player:SetAttribute("PcwTutPrev", nil)
	return { restored = true }
end
if player:GetAttribute("PcwTutPrev") == nil then
	player:SetAttribute("PcwTutPrev", player:GetAttribute("TutorialStepId") or "")
end
player:SetAttribute("TutorialStepId", step)
task.wait(1.5)
local found, length = false, 0
local guide = workspace:FindFirstChild("Guide")
local character = player.Character
local root = character and character:FindFirstChild("HumanoidRootPart")
for _, d in if guide then guide:GetDescendants() else {} do
	if d:IsA("BasePart") and d.Transparency < 1 and d.Parent and string.find(d.Parent.Name, "^Arrow_") then
		found = true
		if root then
			length = math.max(length, (d.Position - root.Position).Magnitude)
		end
	end
end
return { found = found, length = length }
