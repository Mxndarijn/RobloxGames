-- Client datamodel: Heartbeat dt over %%SECONDS%% s, memory, instance counts.
local RunService = game:GetService("RunService")
local Stats = game:GetService("Stats")
local function try(f)
	local ok, v = pcall(f)
	return if ok then v else nil
end
local dts = {}
local conn = RunService.Heartbeat:Connect(function(dt)
	table.insert(dts, dt)
end)
task.wait(%%SECONDS%%)
conn:Disconnect()
local sum, maxdt = 0, 0
for _, dt in dts do
	sum += dt
	if dt > maxdt then
		maxdt = dt
	end
end
table.sort(dts)
local p95 = if #dts > 0 then dts[math.max(1, math.ceil(#dts * 0.95))] else 0
local parts, meshParts = 0, 0
for _, d in workspace:GetDescendants() do
	if d:IsA("BasePart") then
		parts += 1
		if d:IsA("MeshPart") then
			meshParts += 1
		end
	end
end
return {
	frames = #dts,
	frame_time_ms = if #dts > 0 then sum / #dts * 1000 else nil,
	p95_ms = p95 * 1000,
	max_ms = maxdt * 1000,
	fps = if sum > 0 then #dts / sum else nil,
	memory_mb = try(function()
		return Stats:GetTotalMemoryUsageMb()
	end),
	instance_count = try(function()
		return Stats.InstanceCount
	end),
	primitives = try(function()
		return Stats.PrimitivesCount
	end),
	play_parts = parts,
	play_mesh_parts = meshParts,
}
