-- WalkCheck (Client): points the camera at the walking slime from above and behind, for one screenshot.
-- CASE.slime is the SlimeId drop.client.luau returned. CASE.reset puts the camera back.
local cam = workspace.CurrentCamera
if CASE.reset then
	_G.WalkCheckCam = nil
	cam.CameraType = Enum.CameraType.Custom
	return { reset = true }
end
local m: Model? = nil
for _, slime in game:GetService("CollectionService"):GetTagged("Slime") do
	if slime:GetAttribute("SlimeId") == CASE.slime then
		m = slime :: Model
	end
end
local at = if m then m:GetPivot().Position else Vector3.new(CASE.spot[1], CASE.spot[2], CASE.spot[3])
local s = ParadeLane.nearest(at.X, at.Z)
local lx, lz = ParadeLane.pointAt(s)
local toLane = Vector3.new(lx - at.X, 0, lz - at.Z)
local dir = if toLane.Magnitude > 1 then toLane.Unit else Vector3.new(0, 0, -1)
local view = CFrame.lookAt(at - dir * 26 + Vector3.new(0, 22, 0) + dir:Cross(Vector3.yAxis) * 8, at + dir * 8)
-- Studio puts the camera back to Custom after each execute_luau: keep setting it for the shot
_G.WalkCheckCam = view
task.spawn(function()
	local t = os.clock()
	while os.clock() - t < 4 and _G.WalkCheckCam == view do
		cam.CameraType = Enum.CameraType.Scriptable
		cam.CFrame = view
		game:GetService("RunService").RenderStepped:Wait()
	end
end)
return { at = { at.X, at.Y, at.Z } }
