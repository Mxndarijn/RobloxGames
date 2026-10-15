--!nocheck
--[[
	Dry-runs an Open Cloud Luau Execution script against a local place file in
	the fake runtime (the place's own Scripts are NOT started, like in the cloud):

	  lune run tools/livetest/cloud-local build.rbxlx [tools/livetest/cloud/smoke.luau] [--seconds 30]

	Prints the script's output and the returned table as JSON. Real-time loops
	(os.clock deadlines, task.wait) run on the fake clock, so 20 s take ~1 s.
]]
local fs = require("@lune/fs")
local process = require("@lune/process")
local roblox = require("@lune/roblox")
local serde = require("@lune/serde")

local Runtime = require("./Runtime")

local place = process.args[1] or "build.rbxlx"
local scriptPath = process.args[2] or "tools/livetest/cloud/smoke.luau"
local seconds = 60
for i, arg in process.args do
	if arg == "--seconds" then
		seconds = tonumber(process.args[i + 1]) or seconds
	end
end

local rt = Runtime.new(place, { verbose = true })
local runner = roblox.Instance.new("Script")
runner.Name = "LuauExecutionTask"
runner.Source = fs.readFile(scriptPath)
runner.Parent = rt.workspace
local chunk = rt:load(runner)
local result
rt:spawn(function()
	result = table.pack(chunk())
end)
rt:advance(seconds, 0.1)
if not result then
	print("script did not finish within the simulated time (or errored, see above)")
	process.exit(2)
end
local ok, json = pcall(serde.encode, "json", { results = { result[1] } }, true)
print(if ok then json else tostring(result[1]))
process.exit(if type(result[1]) == "table" and result[1].ok then 0 else 1)
