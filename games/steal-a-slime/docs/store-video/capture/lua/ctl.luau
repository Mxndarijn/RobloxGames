-- Installs the video camera: every render frame the camera takes workspace attrs VCamPos/VCamAt/VFov.
-- HUD: every PlayerGui ScreenGui and the CoreGui off (VKeepGui = name of one ScreenGui to keep). VHideBB hides billboards.
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local StarterGui = game:GetService("StarterGui")
local player = Players.LocalPlayer
local pg = player.PlayerGui
pcall(function() RunService:UnbindFromRenderStep("VidCam") end)
pcall(function() StarterGui:SetCoreGuiEnabled(Enum.CoreGuiType.All, false) end)
local cam = workspace.CurrentCamera
local hideChar = %%HIDECHAR%%
RunService:BindToRenderStep("VidCam", Enum.RenderPriority.Last.Value + 2, function()
	local p, a = workspace:GetAttribute("VCamPos"), workspace:GetAttribute("VCamAt")
	if typeof(p) == "Vector3" and typeof(a) == "Vector3" then
		cam.CameraType = Enum.CameraType.Scriptable
		cam.CFrame = CFrame.lookAt(p, a)
	end
	local f = workspace:GetAttribute("VFov")
	if type(f) == "number" then cam.FieldOfView = f end
	local keep = workspace:GetAttribute("VKeepGui")
	for _, g in pg:GetChildren() do
		if g:IsA("ScreenGui") then
			g.Enabled = (keep ~= nil and g.Name == keep)
		end
	end
	if workspace:GetAttribute("VHideBB") then
		for _, d in pg:GetDescendants() do
			if d:IsA("BillboardGui") then d.Enabled = false end
		end
		for _, d in workspace:GetDescendants() do
			if d:IsA("BillboardGui") then d.Enabled = false
			elseif d:IsA("ProximityPrompt") then d.Enabled = false end
		end
	end
	local guide = workspace:FindFirstChild("Guide")
	if guide then
		for _, d in guide:GetDescendants() do
			if d:IsA("BasePart") then d.LocalTransparencyModifier = 1
			elseif d:IsA("BillboardGui") or d:IsA("Highlight") or d:IsA("Beam") then d.Enabled = false end
		end
	end
	if hideChar and player.Character then
		for _, d in player.Character:GetDescendants() do
			if d:IsA("BasePart") or d:IsA("Decal") then d.LocalTransparencyModifier = 1 end
		end
	end
end)
return { ok = true, vp = tostring(cam.ViewportSize) }
