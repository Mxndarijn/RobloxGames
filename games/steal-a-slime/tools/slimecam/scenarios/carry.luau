-- SlimeCam scenario (Client): grabs a slime off the lane (affordable or free), then walks home with it into plot 1
-- while the recording runs: the carry struggle, then the hop onto a free pad.
local CS = game:GetService("CollectionService")
local RS = game:GetService("RunService")
local lp = game.Players.LocalPlayer
local char = lp.Character or lp.CharacterAdded:Wait()
local hum = char:WaitForChild("Humanoid")
local hrp = char:WaitForChild("HumanoidRootPart")
workspace.CurrentCamera.CameraType = Enum.CameraType.Custom
local target
local t1 = os.clock()
while not target and os.clock() - t1 < 90 do
	local cash = lp.leaderstats.Cash.Value
	for _, m in CS:GetTagged("Slime") do
		local p = m:FindFirstChildWhichIsA("ProximityPrompt", true)
		if m:GetAttribute("State") == "Wild" and not m:GetAttribute("Riding") and (m:GetAttribute("Price") or 1e9) <= cash
			and m.PrimaryPart and p and p.Enabled then
			target = m
			break
		end
	end
	if not target then
		task.wait(0.5)
	end
end
if not target then
	return { error = "nothing to grab" }
end
local prompt = target:FindFirstChildWhichIsA("ProximityPrompt", true)
local c = RS.Heartbeat:Connect(function()
	if target.PrimaryPart then
		hrp.CFrame = CFrame.new(target.PrimaryPart.Position + Vector3.new(0, 1, 2.5))
	end
end)
task.wait(0.3)
prompt:InputHoldBegin()
local t = os.clock()
while os.clock() - t < prompt.HoldDuration + 2 and target:GetAttribute("State") ~= "Carried" do
	task.wait(0.05)
end
prompt:InputHoldEnd()
c:Disconnect()
if target:GetAttribute("State") ~= "Carried" then
	return { error = "grab failed" }
end
-- just outside plot 1's gate, then walk in during the recording
hrp.CFrame = CFrame.lookAt(Vector3.new(-14, 4.5, 118), Vector3.new(-14, 4.5, 140))
task.wait(1.2)
task.delay(1.5, function()
	hum:MoveTo(Vector3.new(-14, 4.5, 140))
end)
return { species = target:GetAttribute("Species") }
