-- Client datamodel: undo shot_camera: ScreenGuis, CoreGui, character, camera back to the player.
local Players = game:GetService("Players")
local StarterGui = game:GetService("StarterGui")
local player = Players.LocalPlayer
local pg = player.PlayerGui

local restored = 0
for _, g in pg:GetChildren() do
	if g:GetAttribute("PcwHidden") then
		g.Enabled = true
		g:SetAttribute("PcwHidden", nil)
		restored += 1
	end
end
local core = pg:GetAttribute("PcwCore")
if core ~= nil then
	for _, name in string.split(core, ",") do
		pcall(function()
			StarterGui:SetCoreGuiEnabled(Enum.CoreGuiType[name], true)
		end)
	end
	pg:SetAttribute("PcwCore", nil)
end

local char = player.Character
local root = char and char:FindFirstChild("HumanoidRootPart")
if root and root:GetAttribute("PcwAnchored") ~= nil then
	root.Anchored = root:GetAttribute("PcwAnchored")
	root:SetAttribute("PcwAnchored", nil)
end
if char then
	for _, d in char:GetDescendants() do
		if d:IsA("BasePart") or d:IsA("Decal") then
			d.LocalTransparencyModifier = 0
		end
	end
end

local cam = workspace.CurrentCamera
cam.CameraType = Enum.CameraType.Custom
local hum = char and char:FindFirstChildOfClass("Humanoid")
if hum then
	cam.CameraSubject = hum
end
return { restored_guis = restored }
