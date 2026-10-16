-- Client datamodel: %%SECONDS%% s of RenderStepped dt (avg / p95 / max ms, FPS), memory and the number of
-- slimes SlimeLife is animating (a slime with a LifeRoot child or the client-only LifeAnimating attribute, see src/ui/SlimeLifeRunner) and of tagged
-- slimes within SlimeLife.MAX_DISTANCE (80 studs) of the camera. Waits up to 8 s for >= 16 animating first.
local CollectionService = game:GetService("CollectionService")
local RunService = game:GetService("RunService")
local Stats = game:GetService("Stats")
local cam = workspace.CurrentCamera
local function count()
	local animating, near = 0, 0
	for _, m in CollectionService:GetTagged("Slime") do
		if m:IsA("Model") and m:IsDescendantOf(workspace) then
			local body = m.PrimaryPart or m:FindFirstChild("Body")
			if body and (body.Position - cam.CFrame.Position).Magnitude <= 80 then
				near += 1
			end
			if m:FindFirstChild("LifeRoot") or m:GetAttribute("LifeAnimating") then
				animating += 1
			end
		end
	end
	return animating, near
end
local t0 = os.clock()
local animating, near = count()
while animating < 16 and os.clock() - t0 < 8 do
	task.wait(0.5)
	animating, near = count()
end
local dts = {}
local conn = RunService.RenderStepped:Connect(function(dt)
	table.insert(dts, dt)
end)
task.wait(%%SECONDS%%)
conn:Disconnect()
local animatingAfter = count()
local sum, maxdt = 0, 0
for _, dt in dts do
	sum += dt
	maxdt = math.max(maxdt, dt)
end
table.sort(dts)
local p95 = if #dts > 0 then dts[math.max(1, math.ceil(#dts * 0.95))] else 0
local okMem, mem = pcall(function()
	return Stats:GetTotalMemoryUsageMb()
end)
return {
	frames = #dts,
	avg_ms = if #dts > 0 then sum / #dts * 1000 else nil,
	p95_ms = p95 * 1000,
	max_ms = maxdt * 1000,
	fps = if sum > 0 then #dts / sum else nil,
	memory_mb = if okMem then mem else nil,
	animating = animatingAfter,
	animating_at_start = animating,
	slimes_near = near,
	viewport = { cam.ViewportSize.X, cam.ViewportSize.Y },
}
