-- Client datamodel: the perf measurement window. A Scriptable camera (BindToRenderStep at RenderPriority.Last + 1,
-- after the default camera scripts) makes one full orbit around %%CENTRE%% over %%SECONDS%% s at %%RADIUS%% studs
-- and %%HEIGHT%% studs up, always looking at the centre; angle = 2 * pi * t / SECONDS from a fixed start angle.
-- The HUD stays visible; only the character is parked out of view (anchored, transparent) like shot_camera.
-- Collects every RenderStepped dt (ms, 0.1 precision), client memory, instance / primitive counts and render
-- memory by Stats category (studio_process_mb is Studio's whole process, not a client figure), render
-- stats sampled at 25 / 50 / 75 % of the window (median of the samples). A stat that errors is reported in
-- render_unavailable {name: error text}. The camera and the character are restored at the end.
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local Stats = game:GetService("Stats")
local SECONDS = %%SECONDS%%
local centre = Vector3.new(%%CENTRE%%)
local RADIUS, HEIGHT, START = %%RADIUS%%, %%HEIGHT%%, 0
local BIND = "PcwPerfCam"
local player = Players.LocalPlayer
local cam = workspace.CurrentCamera
local char = player.Character
local root = char and char:FindFirstChild("HumanoidRootPart")
local charParts = {}
local oldPivot, oldAnchored, oldType, oldCF
if char and root then
	oldPivot, oldAnchored = char:GetPivot(), root.Anchored
	for _, d in char:GetDescendants() do
		if d:IsA("BasePart") or d:IsA("Decal") then
			table.insert(charParts, d)
		end
	end
end
oldType, oldCF = cam.CameraType, cam.CFrame

local function eyeAt(t)
	local a = START + math.pi * 2 * t / SECONDS
	return centre + Vector3.new(math.cos(a) * RADIUS, HEIGHT, math.sin(a) * RADIUS)
end
if root then
	root.Anchored = true
	char:PivotTo(CFrame.new(eyeAt(0) + Vector3.new(0, 30, 0)))
end

local dts = {}
local t0 = os.clock()
pcall(function()
	RunService:UnbindFromRenderStep(BIND)
end)
RunService:BindToRenderStep(BIND, Enum.RenderPriority.Last.Value + 1, function()
	local t = math.min(os.clock() - t0, SECONDS)
	cam.CameraType = Enum.CameraType.Scriptable
	cam.CFrame = CFrame.lookAt(eyeAt(t), centre)
	for _, d in charParts do
		d.LocalTransparencyModifier = 1
	end
end)
pcall(function()
	player:RequestStreamAroundAsync(centre, 5)
end)
task.wait(1) -- the camera is in place before the window opens

local STATS = { "SceneDrawcallCount", "SceneTriangleCount", "ShadowsDrawcallCount", "ShadowsTriangleCount",
	"UI2DDrawcallCount", "UI2DTriangleCount", "UI3DDrawcallCount", "UI3DTriangleCount",
	"RenderCPUFrameTime", "RenderGPUFrameTime", "FrameTime", "HeartbeatTime" }
local samples, unavailable = {}, {}
local function sample()
	for _, name in STATS do
		local ok, v = pcall(function()
			return (Stats :: any)[name]
		end)
		if ok and type(v) == "number" then
			samples[name] = samples[name] or {}
			table.insert(samples[name], v)
		elseif not ok then
			unavailable[name] = tostring(v):sub(1, 160)
		else
			unavailable[name] = "type " .. typeof(v)
		end
	end
end
local perfStats = {}
local function samplePerf()
	local ok, kids = pcall(function()
		return Stats.PerformanceStats:GetChildren()
	end)
	if not ok then
		perfStats._error = tostring(kids):sub(1, 160)
		return
	end
	for _, c in kids do
		local gok, v = pcall(function()
			return (c :: any):GetValue()
		end)
		if gok and type(v) == "number" then
			perfStats[c.Name] = v
		end
	end
end

local conn = RunService.RenderStepped:Connect(function(dt)
	table.insert(dts, dt)
end)
local windowStart = os.clock()
local nextSample = 1
while os.clock() - windowStart < SECONDS do
	task.wait(0.1)
	if nextSample <= 3 and os.clock() - windowStart >= SECONDS * nextSample * 0.25 then
		sample()
		if nextSample == 2 then
			samplePerf()
		end
		nextSample += 1
	end
end
conn:Disconnect()

-- Stats memory categories (Studio's MemoryTrackingEnabled): {name: MB} from GetMemoryUsageMbAllCategories, or nil with the
-- reason in memory_categories_error. GetTotalMemoryUsageMb is Studio's WHOLE process, not a client / server figure.
local function memoryCategories()
	local ok, enabled = pcall(function()
		return (Stats :: any).MemoryTrackingEnabled
	end)
	if not (ok and enabled) then
		pcall(function()
			(Stats :: any).MemoryTrackingEnabled = true
		end)
		task.wait(1)
		ok, enabled = pcall(function()
			return (Stats :: any).MemoryTrackingEnabled
		end)
	end
	if not (ok and enabled) then
		return nil, "MemoryTrackingEnabled is " .. tostring(enabled)
	end
	local gok, all = pcall(function()
		return (Stats :: any):GetMemoryUsageMbAllCategories()
	end)
	if not gok or type(all) ~= "table" then
		return nil, "GetMemoryUsageMbAllCategories: " .. tostring(all):sub(1, 160)
	end
	local out = {}
	for k, v in all do
		if type(v) == "number" then
			out[tostring(k)] = v
		end
	end
	return out, nil
end
local memCats, memCatsErr = memoryCategories()
local function median(list)
	table.sort(list)
	local n = #list
	return if n % 2 == 1 then list[(n + 1) / 2] else (list[n / 2] + list[n / 2 + 1]) / 2
end
local render = {}
for name, list in samples do
	render[name] = median(list)
end
local function try(f)
	local ok, v = pcall(f)
	return if ok then v else nil
end
local tags = {}
for _, tag in Enum.DeveloperMemoryTag:GetEnumItems() do
	local ok, v = pcall(function()
		return Stats:GetMemoryUsageMbForTag(tag)
	end)
	if ok and type(v) == "number" then
		tags[tag.Name] = v
	end
end
local ms = table.create(#dts)
for i, dt in dts do
	ms[i] = math.floor(dt * 10000 + 0.5) / 10
end
local result = {
	seconds = SECONDS,
	elapsed = os.clock() - windowStart,
	dts_ms = ms,
	studio_process_mb = try(function()
		return Stats:GetTotalMemoryUsageMb()
	end),
	memory_categories = memCats,
	memory_categories_error = memCatsErr,
	tags_mb = tags,
	instance_count = try(function()
		return Stats.InstanceCount
	end),
	primitives = try(function()
		return Stats.PrimitivesCount
	end),
	render = render,
	render_unavailable = unavailable,
	performance_stats = perfStats,
	viewport = { cam.ViewportSize.X, cam.ViewportSize.Y },
}

RunService:UnbindFromRenderStep(BIND)
cam.CameraType = Enum.CameraType.Custom
if root and oldPivot then
	char:PivotTo(oldPivot)
	root.Anchored = oldAnchored
	for _, d in charParts do
		d.LocalTransparencyModifier = 0
	end
end
return result
