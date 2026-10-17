-- Client datamodel: parks the camera on one point of the perf orbit (angle %%ANGLE%% rad, same RADIUS / HEIGHT /
-- CENTRE as perf_window) for the proof frame, HUD untouched. %%ON%% = false releases the camera again (Custom).
local RunService = game:GetService("RunService")
local BIND = "PcwPerfPose"
local cam = workspace.CurrentCamera
pcall(function()
	RunService:UnbindFromRenderStep(BIND)
end)
if not %%ON%% then
	cam.CameraType = Enum.CameraType.Custom
	return { released = true }
end
local centre = Vector3.new(%%CENTRE%%)
local a = %%ANGLE%%
local eye = centre + Vector3.new(math.cos(a) * %%RADIUS%%, %%HEIGHT%%, math.sin(a) * %%RADIUS%%)
RunService:BindToRenderStep(BIND, Enum.RenderPriority.Last.Value + 1, function()
	cam.CameraType = Enum.CameraType.Scriptable
	cam.CFrame = CFrame.lookAt(eye, centre)
end)
task.wait(1.5)
return { posed = true, drift = (cam.CFrame.Position - eye).Magnitude }
