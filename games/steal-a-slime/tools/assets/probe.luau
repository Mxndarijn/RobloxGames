-- Asset load probe (Open Cloud Luau Execution), body of tools/assets/check_assets.py: that script puts LISTS and
-- MODE_FILTER above this line. Never touches DataStores or DataService; everything it makes dies with the task.
local HttpService = game:GetService("HttpService")
local AssetService = game:GetService("AssetService")
local InsertService = game:GetService("InsertService")
local ContentProvider = game:GetService("ContentProvider")

local MODE = MODE_FILTER
local result = { failed = {}, counts = {} }
local function bad(kind, id, label, why)
	table.insert(result.failed, { kind = kind, id = id, label = label, why = string.sub(tostring(why), 1, 160) })
end

local function runAll(kind, list, worker, width)
	local keys = {}
	for id, label in list do
		table.insert(keys, { id, label })
	end
	local nextIndex, active = 1, 0
	local okCount = 0
	local function pump()
		while nextIndex <= #keys do
			local item = keys[nextIndex]
			nextIndex += 1
			local ok, why = pcall(worker, item[1])
			if ok and why == nil then
				okCount += 1
			else
				bad(kind, item[1], item[2], why)
			end
		end
		active -= 1
	end
	for _ = 1, width do
		active += 1
		task.spawn(pump)
	end
	local t0 = os.clock()
	while active > 0 and os.clock() - t0 < 200 do
		task.wait(0.2)
	end
	result.counts[kind] = { total = #keys, ok = okCount, unfinished = active > 0 }
end

if MODE == nil or MODE == "audio" then
	runAll("audio", LISTS.audio, function(id)
		local s = Instance.new("Sound")
		s.Volume = 0
		s.SoundId = "rbxassetid://" .. id
		s.Parent = workspace
		local t0 = os.clock()
		while not s.IsLoaded and os.clock() - t0 < 15 do
			task.wait(0.1)
		end
		local len, loaded = s.TimeLength, s.IsLoaded
		s:Destroy()
		if not loaded then
			return "not loaded after 15 s"
		end
		if len <= 0 then
			return "TimeLength 0"
		end
		return nil
	end, 16)
end

if MODE == nil or MODE == "model" then
	runAll("model", LISTS.model, function(id)
		local m = InsertService:LoadAsset(tonumber(id))
		local hasMesh = m:FindFirstChildWhichIsA("MeshPart", true) ~= nil
		m:Destroy()
		return if hasMesh then nil else "no MeshPart in the asset"
	end, 8)
end

if MODE == nil or MODE == "mesh" then
	runAll("mesh", LISTS.mesh, function(id)
		local p = AssetService:CreateMeshPartAsync("rbxassetid://" .. id)
		p:Destroy()
		return nil
	end, 16)
end

if MODE == nil or MODE == "image" then
	local list = {}
	for id in LISTS.image do
		table.insert(list, "rbxassetid://" .. id)
	end
	local status = {}
	pcall(function()
		ContentProvider:PreloadAsync(list, function(contentId, st)
			status[contentId] = st
		end)
	end)
	local ok = 0
	for id, label in LISTS.image do
		local st = status["rbxassetid://" .. id]
		if st == Enum.AssetFetchStatus.Success then
			ok += 1
		else
			bad("image", id, label, tostring(st))
		end
	end
	local n = 0
	for _ in LISTS.image do
		n += 1
	end
	result.counts.image = { total = n, ok = ok, note = "server-side PreloadAsync status" }
end

result.ok = #result.failed == 0
return HttpService:JSONEncode(result)
