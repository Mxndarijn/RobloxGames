-- Client datamodel: re-aims the camera lock of shot_camera at %%EYE%% looking at %%AT%% WITHOUT touching any
-- GUI (shot_camera hides every BillboardGui, which would hide the GrowthLabel WorldView just made).
local RunService = game:GetService("RunService")
local cam = workspace.CurrentCamera
local eye, at = Vector3.new(%%EYE%%), Vector3.new(%%AT%%)
local cf = CFrame.lookAt(eye, at)
local parts = {}
local char = game:GetService("Players").LocalPlayer.Character
if char then
	for _, d in char:GetDescendants() do
		if d:IsA("BasePart") or d:IsA("Decal") then
			table.insert(parts, d)
		end
	end
end
pcall(function()
	game:GetService("Players").LocalPlayer:RequestStreamAroundAsync(at, 5)
end)
pcall(function()
	RunService:UnbindFromRenderStep("PcwShotCam")
end)
RunService:BindToRenderStep("PcwShotCam", Enum.RenderPriority.Last.Value + 1, function()
	cam.CameraType = Enum.CameraType.Scriptable
	cam.CFrame = cf
	for _, d in parts do
		d.LocalTransparencyModifier = 1
	end
end)
task.wait(0.5)
local drift = (cam.CFrame.Position - eye).Magnitude
return { drift = drift, locked = drift < 0.05 }
