-- A stand-in for the owner chasing the thief: a client-side copy of the local avatar (no player, no physics).
local Players = game:GetService("Players")
local old = workspace:FindFirstChild("VidChaser") if old then old:Destroy() end
local src = Players.LocalPlayer.Character
src.Archivable = true
local m = src:Clone()
m.Name = "VidChaser"
for _, d in m:GetDescendants() do
	if d:IsA("Script") or d:IsA("LocalScript") then d:Destroy()
	elseif d:IsA("BasePart") then d.Anchored = (d.Name == "HumanoidRootPart") d.CanCollide = false d.LocalTransparencyModifier = 0 end
end
m.Humanoid.DisplayDistanceType = Enum.HumanoidDisplayDistanceType.None
local shirt = m:FindFirstChildOfClass("Shirt") if shirt then shirt:Destroy() end
for _, d in m:GetDescendants() do
	if d:IsA("BasePart") and (d.Name:find("Torso") or d.Name:find("Arm") or d.Name:find("Hand")) then d.Color = Color3.fromRGB(46, 160, 92) end
	if d:IsA("BasePart") and (d.Name:find("Leg") or d.Name:find("Foot")) then d.Color = Color3.fromRGB(40, 48, 70) end
end
m.Parent = workspace
m.HumanoidRootPart.CFrame = CFrame.lookAt(Vector3.new(%%P%%), Vector3.new(%%F%%))
local an = Instance.new("Animation") an.AnimationId = "rbxassetid://913376220"
local tr = m.Humanoid:FindFirstChildOfClass("Animator"):LoadAnimation(an)
tr:Play(0) tr.TimePosition = %%T%% tr:AdjustSpeed(0)
task.wait(0.5)
return { ok = true }
