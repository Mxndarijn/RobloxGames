-- Client datamodel: procedural-motion proof shot. Finds the rigged slime nearest the pad at %%PATH%% (<= 14
-- studs; slime_seat put one there), waits up to 4 s for SlimeLifeRunner to drive it (attribute LifeMode:
-- "motor" = SlimeMotor on the Motor6D Transforms, "anim" = uploaded animations, "weld" = LifeRoot; nothing
-- = frozen), then plays %%KIND%% ("Idle" = just watch, "Hop" / "LookLeft" / "LookRight" via the LifeForce
-- attribute) and compares the FaceRoot / SkinRoot Transform and the Mesh size A -> B, %%WAIT%% s apart
-- (the capture lands on B: hop apex ~0.35, look peak ~0.35, idle any). moved = how far B is from A.
-- %%KIND%% "Tiers" behaves like "Idle" (nothing forced). Every kind also reports tiers = { near, mid, far }:
-- the LifeTier attribute (SlimeLifeRunner, FEATURES.SlimeLod) of the animated slimes within 80 studs of
-- the pad (all "near" while the flag is off).
local node = game
for part in string.gmatch(%%PATH%%, "[^.]+") do
	if node == game and part == "Workspace" then
		node = workspace
	else
		node = node and node:FindFirstChild(part)
	end
end
if not node then
	return { ok = false, error = "pad not found" }
end
local origin = if node:IsA("Model") then node:GetPivot().Position else (node :: BasePart).Position
local CollectionService = game:GetService("CollectionService")
local slime, best = nil, 14
for _, m in CollectionService:GetTagged("Slime") do
	local body = m:IsA("Model") and (m.PrimaryPart or m:FindFirstChild("Body"))
	if body and m:FindFirstChild("AnimationController") then
		local d = (body.Position - origin).Magnitude
		if d < best then
			slime, best = m, d
		end
	end
end
if not slime then
	return { ok = false, error = "no rigged slime near the pad" }
end
local t0 = os.clock()
while not slime:GetAttribute("LifeMode") and os.clock() - t0 < 4 do
	task.wait(0.1)
end
local mode = slime:GetAttribute("LifeMode")
local body = slime.PrimaryPart or slime:FindFirstChild("Body")
local face, skin = body:FindFirstChild("FaceRoot"), body:FindFirstChild("SkinRoot")
local mesh = slime:FindFirstChild("Mesh")
local function sample()
	local ft = if face then face.Transform else CFrame.new()
	local _, yaw = ft:ToEulerAnglesYXZ()
	return { y = ft.Position.Y, yaw = yaw, sy = if mesh then mesh.Size.Y else 0, skin_same = skin ~= nil and face ~= nil and skin.Transform == face.Transform }
end
local kind = %%KIND%%
if kind ~= "Idle" and kind ~= "Tiers" then
	slime:SetAttribute("LifeForce", kind)
end
task.wait(0.05)
local a = sample()
task.wait(%%WAIT%%)
local b = sample()
local moved = math.abs(b.y - a.y) + math.abs(b.yaw - a.yaw) + math.abs(b.sy - a.sy)
local animating, near = 0, 0
local tiers = { near = 0, mid = 0, far = 0 }
for _, m in CollectionService:GetTagged("Slime") do
	local mb = m:IsA("Model") and (m.PrimaryPart or m:FindFirstChild("Body"))
	if mb and (mb.Position - origin).Magnitude <= 80 then
		near += 1
		if m:GetAttribute("LifeAnimating") or m:FindFirstChild("LifeRoot") then
			animating += 1
		end
		local tier = m:GetAttribute("LifeTier")
		if tiers[tier] then
			tiers[tier] += 1
		end
	end
end
return { ok = mode ~= nil and moved > 0.01, slime = slime.Name, mode = mode, kind = kind, a = a, b = b, moved = moved, animating = animating, near = near, tiers = tiers }
