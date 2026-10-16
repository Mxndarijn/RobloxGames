-- Client datamodel: world proof shot. Hides every PlayerGui ScreenGui, the CoreGui, every BillboardGui
-- and ProximityPrompt, moves the character behind the camera and anchors it, then locks the camera at
-- %%EYE%% looking at %%AT%% with a BindToRenderStep at RenderPriority.Last + 1 (after the default camera
-- scripts, which otherwise take the camera back). shot_camera_reset undoes all of it: instances marked
-- PcwHidden, the root's Anchored in PcwAnchored, the character pivot in PcwPivot, CoreGui in PcwCore.
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local StarterGui = game:GetService("StarterGui")
local player = Players.LocalPlayer
local pg = player.PlayerGui
local eye, at = Vector3.new(%%EYE%%), Vector3.new(%%AT%%)
local BIND = "PcwShotCam"

local function hide(inst)
	inst:SetAttribute("PcwHidden", true)
	inst.Enabled = false
end

local hidden, billboards, prompts = 0, 0, 0
for _, g in pg:GetChildren() do
	if g:IsA("ScreenGui") and g.Enabled and g.Name ~= "PcwProbe" then
		hide(g)
		hidden += 1
	end
end
for _, root in { workspace, pg } do
	for _, d in root:GetDescendants() do
		if d:IsA("BillboardGui") and d.Enabled then
			hide(d)
			billboards += 1
		elseif d:IsA("ProximityPrompt") and d.Enabled then
			hide(d)
			prompts += 1
		end
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

-- Character: anchored a little behind and above the camera (out of the frustum, keeps the shot area
-- streamed in), and transparent every frame in case the TransparencyController resets it.
local char = player.Character
local root = char and char:FindFirstChild("HumanoidRootPart")
local back = eye - at
back = if back.Magnitude > 1e-3 then back.Unit else Vector3.zAxis
if root then
	if root:GetAttribute("PcwAnchored") == nil then
		root:SetAttribute("PcwAnchored", root.Anchored)
		char:SetAttribute("PcwPivot", char:GetPivot())
	end
	root.Anchored = true
	char:PivotTo(CFrame.new(eye + back * 12 + Vector3.yAxis * 6))
end
local parts = {}
if char then
	for _, d in char:GetDescendants() do
		if d:IsA("BasePart") or d:IsA("Decal") then
			table.insert(parts, d)
		end
	end
end

pcall(function()
	player:RequestStreamAroundAsync(at, 5)
end)
local cam = workspace.CurrentCamera
local cf = CFrame.lookAt(eye, at)
pcall(function()
	RunService:UnbindFromRenderStep(BIND)
end)
RunService:BindToRenderStep(BIND, Enum.RenderPriority.Last.Value + 1, function()
	cam.CameraType = Enum.CameraType.Scriptable
	cam.CFrame = cf
	for _, d in parts do
		d.LocalTransparencyModifier = 1
	end
end)
pg:SetAttribute("PcwShotCam", true)
task.wait(1.5)
local drift = (cam.CFrame.Position - eye).Magnitude
return {
	hidden_guis = hidden,
	hidden_billboards = billboards,
	hidden_prompts = prompts,
	core_gui_hidden = coreHidden,
	character_moved = root ~= nil,
	drift = drift,
	locked = drift < 0.05,
	camera_type = cam.CameraType.Name,
}
