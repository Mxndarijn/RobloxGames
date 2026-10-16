--!nocheck
--[[
	Open Cloud Luau Execution runner for the server specs (tools/pipeline/cloud-test.sh).

	Runs inside a real Roblox server for the Saved cloud-test place version.
	That place is default.project.json plus ServerStorage.CloudTests, which
	holds tests/*.luau with their requires rewritten to the place's real
	modules (tools/pipeline/stage-specs.luau). The place's own Scripts don't
	start, nothing replicates, and changes are discarded afterwards.

	DataStores are REAL here. DataStoreMode = "Memory" is set before any
	module loads, and stage-specs leaves out any file that names a DataStore
	API.

	Returns a JSON string:
	  { ok, passed, failed, total, specs, failures = [{ name, error }] }
	A spec that fails to load counts as one failure named "<spec> (load)".
]]

local HttpService = game:GetService("HttpService")
local ServerStorage = game:GetService("ServerStorage")

workspace:SetAttribute("DataStoreMode", "Memory")

local MAX_FAILURES = 50

local result = { ok = false, passed = 0, failed = 0, total = 0, specs = 0, failures = {} }

local function addFailure(name, err)
	result.failed += 1
	if #result.failures < MAX_FAILURES then
		table.insert(result.failures, { name = name, error = string.sub(tostring(err), 1, 500) })
	end
	print(`  FAIL  {name}\n        {err}`)
end

local root = ServerStorage:FindFirstChild("CloudTests")
if not root then
	result.error = "ServerStorage.CloudTests missing: this place version was not built by tools/pipeline/cloud-test.sh"
	return HttpService:JSONEncode(result)
end

local TestRunner = require(root.TestRunner)

local specs = {}
for _, child in root:GetChildren() do
	if child:IsA("ModuleScript") and string.match(child.Name, "%.spec$") then
		table.insert(specs, child)
	end
end
table.sort(specs, function(a, b)
	return a.Name < b.Name
end)
result.specs = #specs

-- Load every spec (each registers its tests with the shared TestRunner).
for _, spec in specs do
	local ok, err = pcall(require, spec)
	if not ok then
		addFailure(`{spec.Name} (load)`, err)
	end
end

-- Run them ourselves so each failure is reported by name.
local tests = TestRunner._tests or {}
for _, test in tests do
	local ok, err = pcall(test.fn)
	if ok then
		result.passed += 1
	else
		addFailure(test.name, err)
	end
end
table.clear(tests)

result.total = result.passed + result.failed
result.ok = result.failed == 0 and result.passed > 0
print(`{result.passed} passed, {result.failed} failed, {result.total} total ({result.specs} specs)`)
return HttpService:JSONEncode(result)
