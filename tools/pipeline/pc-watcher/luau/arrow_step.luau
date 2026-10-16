-- Client datamodel: v30 C11 TutorialArrow probe. Forces the local Player's TutorialStepId to "%%STEP%%" (client-only
-- attribute; "" restores the real one) so VisualsClient/TutorialArrow draws its Beam towards a target that is far
-- from the character, waits for its 0.5 s poll, then reports the TutorialArrow Beam's attachment distance next to
-- the character-to-target distance. Pair with fx_streaks, which fails any Beam longer than its cap.
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
for _, d in workspace:GetDescendants() do
	if d:IsA("Beam") and d.Name == "TutorialArrow" and d.Attachment0 and d.Attachment1 then
		found = true
		length = math.max(length, (d.Attachment0.WorldPosition - d.Attachment1.WorldPosition).Magnitude)
	end
end
return { found = found, length = length }
