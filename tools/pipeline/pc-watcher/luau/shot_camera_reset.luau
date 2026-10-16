-- Client datamodel: undo shot_camera: render-step lock, ScreenGuis / BillboardGuis / ProximityPrompts,
-- CoreGui, tutorial arrow, character (pivot, Anchored, transparency), camera back to the player.
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local StarterGui = game:GetService("StarterGui")
local player = Players.LocalPlayer
local pg = player.PlayerGui

pcall(function()
	RunService:UnbindFromRenderStep("PcwShotCam")
end)
pg:SetAttribute("PcwShotCam", nil)

local restored = 0
for _, root in { pg, workspace } do
	for _, d in root:GetDescendants() do
		if d:GetAttribute("PcwHidden") and (d:IsA("LayerCollector") or d:IsA("ProximityPrompt") or d:IsA("Beam")) then
			d.Enabled = true
			d:SetAttribute("PcwHidden", nil)
			restored += 1
		end
	end
end
local chevrons = workspace.CurrentCamera:FindFirstChild("TutorialChevrons")
if chevrons then
	for _, d in chevrons:GetDescendants() do
		if d:IsA("BasePart") then
			d.LocalTransparencyModifier = 0
		end
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
if char and char:GetAttribute("PcwPivot") ~= nil then
	char:PivotTo(char:GetAttribute("PcwPivot"))
	char:SetAttribute("PcwPivot", nil)
end
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
return { restored = restored }
