-- Client datamodel: rig animation proof shot. Finds the tagged slime on the pad at %%PATH%% (the Server
-- shot_find path of the shots/*.json target) that has the slime rig (Motor6Ds FaceRoot / SkinRoot and an
-- AnimationController > Animator, src/visuals/shared/SlimeRig), plays the animation %%ANIM%% on THIS
-- client's Animator (asset id from shots/*.json "animId" = MeshAssets.ANIMATIONS) and waits %%WAIT%% s,
-- so the capture lands at the pose of that moment (SlimeHop apex 0.45, look peak 0.2, idle low 1.25).
-- Reports the joints and the largest Motor6D offset seen while it played, as numbers for the report.
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
	if m:GetAttribute("PcwPad") and m:FindFirstChild("AnimationController") then
		slime, best = m, 0 -- the pad_seat slime wins
		break
	end
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
local animator = slime.AnimationController:FindFirstChildOfClass("Animator")
local animation = Instance.new("Animation")
animation.AnimationId = %%ID%%
local track = animator:LoadAnimation(animation)
track.Priority = Enum.AnimationPriority.Action4
track.Looped = false
track:Play(0)
local motors, peak = {}, 0
local body = slime.PrimaryPart or slime:FindFirstChild("Body")
for _, d in body:GetChildren() do
	if d:IsA("Motor6D") then
		table.insert(motors, d)
	end
end
local t0 = os.clock()
while os.clock() - t0 < %%WAIT%% do
	for _, m in motors do
		local yaw = m.Transform:ToEulerAnglesYXZ()
		peak = math.max(peak, m.Transform.Position.Magnitude, math.abs(select(2, m.Transform:ToEulerAnglesYXZ())), math.abs(yaw))
	end
	task.wait()
end
local out = { ok = true, slime = slime.Name, motors = #motors, playing = track.IsPlaying, length = track.Length, peak = peak }
track:Stop(0)
animation:Destroy()
return out
