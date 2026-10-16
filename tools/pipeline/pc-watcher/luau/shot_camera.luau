-- Client datamodel: world proof shot. Hides every PlayerGui ScreenGui and the CoreGui, anchors and
-- hides the character, then holds a scriptable camera at %%EYE%% looking at %%AT%%. Re-asserted after
-- the wait in case the camera scripts took it back. shot_camera_reset undoes all of it (PlayerGui
-- children marked PcwHidden, the root's original Anchored in PcwAnchored, CoreGui state in PcwCore).
local Players = game:GetService("Players")
local StarterGui = game:GetService("StarterGui")
local player = Players.LocalPlayer
local pg = player.PlayerGui
local eye, at = Vector3.new(%%EYE%%), Vector3.new(%%AT%%)

local hidden = 0
for _, g in pg:GetChildren() do
	if g:IsA("LayerCollector") and g.Enabled and g.Name ~= "PcwProbe" then
		g:SetAttribute("PcwHidden", true)
		g.Enabled = false
		hidden += 1
	end
end
if pg:GetAttribute("PcwCore") == nil then
	local on = {}
	for _, t in Enum.CoreGuiType:GetEnumItems() do
		if t ~= Enum.CoreGuiType.All and StarterGui:GetCoreGuiEnabled(t) then
			table.insert(on, t.Name)
		end
	end
	pg:SetAttribute("PcwCore", table.concat(on, ","))
end
local coreHidden = pcall(function()
	StarterGui:SetCoreGuiEnabled(Enum.CoreGuiType.All, false)
end)

local char = player.Character
local root = char and char:FindFirstChild("HumanoidRootPart")
if root and root:GetAttribute("PcwAnchored") == nil then
	root:SetAttribute("PcwAnchored", root.Anchored)
	root.Anchored = true
end
if char then
	for _, d in char:GetDescendants() do
		if d:IsA("BasePart") or d:IsA("Decal") then
			d.LocalTransparencyModifier = 1
		end
	end
end

pcall(function()
	player:RequestStreamAroundAsync(at, 5)
end)
local cam = workspace.CurrentCamera
local cf = CFrame.lookAt(eye, at)
cam.CameraType = Enum.CameraType.Scriptable
cam.CFrame = cf
task.wait(1.5)
local drift = (cam.CFrame.Position - eye).Magnitude
cam.CameraType = Enum.CameraType.Scriptable
cam.CFrame = cf
task.wait(0.1)
return {
	hidden_guis = hidden,
	core_gui_hidden = coreHidden,
	character_hidden = char ~= nil,
	drift = drift,
	camera_type = cam.CameraType.Name,
}
