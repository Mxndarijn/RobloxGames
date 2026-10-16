-- Client datamodel: scriptable camera at %%EYE%% looking at %%AT%% (CameraType restored by shot_camera_reset).
local eye, at = Vector3.new(%%EYE%%), Vector3.new(%%AT%%)
pcall(function()
	game:GetService("Players").LocalPlayer:RequestStreamAroundAsync(at, 5)
end)
local cam = workspace.CurrentCamera
cam.CameraType = Enum.CameraType.Scriptable
cam.CFrame = CFrame.lookAt(eye, at)
task.wait(1)
return { ok = true }
