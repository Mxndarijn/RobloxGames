-- SlimeCam scenario (Client): the player stands by plot 1's pads; a camera pinned every frame looks over them.
local RS = game:GetService("RunService")
local lp = game.Players.LocalPlayer
local char = lp.Character or lp.CharacterAdded:Wait()
local hrp = char:WaitForChild("HumanoidRootPart")
hrp.CFrame = CFrame.lookAt(Vector3.new(0, 4.5, 136), Vector3.new(0, 4, 150))
local cx = _G.CamX and tonumber(_G.CamX) or 0
local view = CFrame.lookAt(Vector3.new(cx, 8, 129), Vector3.new(cx, 3.5, 145))
local t0 = os.clock()
RS:BindToRenderStep("SlimeCamPin", Enum.RenderPriority.Last.Value + 2, function()
	if os.clock() - t0 > 60 then
		RS:UnbindFromRenderStep("SlimeCamPin")
		return
	end
	local cam = workspace.CurrentCamera
	cam.CameraType = Enum.CameraType.Scriptable
	cam.CFrame = view
end)
task.wait(2)
return { ok = true }
