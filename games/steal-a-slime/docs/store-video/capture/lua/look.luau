-- Capture-only look (client, this play session only; never saved): max quality, a grade on top of the game's own,
-- less haze, and a depth of field the camera script drives through workspace attribute VDof = (focus, radius, far).
local log = {}
local r = settings().Rendering
r.QualityLevel = Enum.QualityLevel.Level21
pcall(function() r.MeshPartDetailLevel = Enum.MeshPartDetailLevel.Level04 end)
local L = game.Lighting
local cc = L:FindFirstChild("VidGrade") or Instance.new("ColorCorrectionEffect")
cc.Name = "VidGrade" cc.Saturation = %%SAT%% cc.Contrast = %%CON%% cc.Brightness = %%BRI%% cc.Parent = L
local atm = L:FindFirstChildOfClass("Atmosphere")
if atm then
	if atm:GetAttribute("VidHaze0") == nil then atm:SetAttribute("VidHaze0", atm.Haze) atm:SetAttribute("VidDens0", atm.Density) end
	atm.Haze = atm:GetAttribute("VidHaze0") * %%HAZE%%
	atm.Density = atm:GetAttribute("VidDens0") * %%DENS%%
end
local bloom = L:FindFirstChildOfClass("BloomEffect")
if bloom then
	if bloom:GetAttribute("VidInt0") == nil then bloom:SetAttribute("VidInt0", bloom.Intensity) end
	bloom.Intensity = bloom:GetAttribute("VidInt0") * %%BLOOM%%
end
if L:GetAttribute("VidExp0") == nil then L:SetAttribute("VidExp0", L.ExposureCompensation) end
L.ExposureCompensation = L:GetAttribute("VidExp0") + %%EXP%%
local dof = L:FindFirstChild("VidDof") or Instance.new("DepthOfFieldEffect")
dof.Name = "VidDof" dof.NearIntensity = 0 dof.Enabled = false dof.Parent = L
local RS = game:GetService("RunService")
pcall(function() RS:UnbindFromRenderStep("VidDof") end)
RS:BindToRenderStep("VidDof", Enum.RenderPriority.Last.Value + 3, function()
	local v = workspace:GetAttribute("VDof")
	if typeof(v) == "Vector3" and v.Z > 0 then
		dof.Enabled = true dof.FocusDistance = v.X dof.InFocusRadius = v.Y dof.FarIntensity = v.Z
	else
		dof.Enabled = false
	end
end)
local function precise(d) if d:IsA("MeshPart") then pcall(function() d.RenderFidelity = Enum.RenderFidelity.Precise end) end end
if not workspace:GetAttribute("VidPrecise") then
	for _, d in workspace:GetDescendants() do precise(d) end
	workspace.DescendantAdded:Connect(precise)
	workspace:SetAttribute("VidPrecise", true)
end
table.insert(log, tostring(r.QualityLevel))
return { log = log }
