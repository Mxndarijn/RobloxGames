-- Server datamodel (play): memory categories (Stats:GetMemoryUsageMbAllCategories) and memory and engine counters for the perf report. Total memory, every
-- Enum.DeveloperMemoryTag (a tag that errors is left out), instance / primitive counts, heartbeat and
-- physics step time when the engine lets the script read them.
local Stats = game:GetService("Stats")
local function try(f)
	local ok, v = pcall(f)
	return if ok then v else nil
end
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
local tags = {}
for _, tag in Enum.DeveloperMemoryTag:GetEnumItems() do
	local ok, v = pcall(function()
		return Stats:GetMemoryUsageMbForTag(tag)
	end)
	if ok and type(v) == "number" then
		tags[tag.Name] = v
	end
end
return {
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
	heartbeat_ms = try(function()
		return Stats.HeartbeatTimeMs
	end),
	physics_step_ms = try(function()
		return Stats.PhysicsStepTimeMs
	end),
}
