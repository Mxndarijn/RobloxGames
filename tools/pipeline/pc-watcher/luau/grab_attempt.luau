-- Client datamodel: put the character next to the cheapest wild slime so a real E press
-- (user_keyboard_input) can trigger its ProximityPrompt (tutorial step "Grab").
local p = game:GetService("Players").LocalPlayer
local folder = workspace:FindFirstChild("WildSlimes")
local best, bestPrice = nil, nil
for _, m in (if folder then folder:GetChildren() else {}) do
	local prompt = m:FindFirstChildWhichIsA("ProximityPrompt", true)
	local price = m:GetAttribute("Price") or 0
	if prompt and prompt.Enabled and m:GetAttribute("State") ~= "Escaping" and (bestPrice == nil or price < bestPrice) then
		best, bestPrice = m, price
	end
end
if not best then
	return { found = false, wild = if folder then #folder:GetChildren() else 0 }
end
local hrp = p.Character and p.Character:FindFirstChild("HumanoidRootPart")
if not hrp then
	return { found = true, moved = false, why = "no HumanoidRootPart" }
end
local pos = best:GetPivot().Position
hrp.CFrame = CFrame.lookAt(pos + Vector3.new(3, 2, 0), Vector3.new(pos.X, pos.Y + 2, pos.Z))
return { found = true, moved = true, price = bestPrice, name = best.Name, step_id = p:GetAttribute("TutorialStepId") }
