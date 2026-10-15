--!nocheck
--[[
	Headless boot test of a built place (no Studio, no network):

	  rojo build -o build.rbxlx
	  lune run tools/livetest/run build.rbxlx [--seconds 60] [--player] [--mesh] [--verbose]

	Boots ServerScriptService.Server from the place file in the fake runtime
	(tools/livetest/Runtime.luau), runs N seconds of server time and prints
	PASS / FAIL per check (tools/livetest/Checks.luau). Exit 1 on any FAIL.
	--player joins one fake player (plot assignment, sign owner, Speed Coil...);
	--mesh lets InsertService:LoadAsset return a MeshPart package (default: it
	fails, which is also what happens in a live server without asset access).
	--patch <Full.Name> <find> <replace> edits a script's Source in memory only
	(plain find, all matches) to test a fix hypothesis without touching src/.
]]

local process = require("@lune/process")
local roblox = require("@lune/roblox")

local Checks = require("./Checks")
local Runtime = require("./Runtime")

local path = "build.rbxlx"
local seconds = 60
local withPlayer, withMesh, verbose = false, false, false
local patches = {}
local i = 1
while i <= #process.args do
	local arg = process.args[i]
	if arg == "--seconds" then
		i += 1
		seconds = tonumber(process.args[i]) or seconds
	elseif arg == "--player" then
		withPlayer = true
	elseif arg == "--mesh" then
		withMesh = true
	elseif arg == "--verbose" then
		verbose = true
	elseif arg == "--patch" then
		table.insert(patches, { process.args[i + 1], process.args[i + 2], process.args[i + 3] })
		i += 3
	else
		path = arg
	end
	i += 1
end

local rt = Runtime.new(path, {
	verbose = verbose,
	loadAsset = if withMesh
		then function()
			local model = roblox.Instance.new("Model")
			local mesh = roblox.Instance.new("MeshPart")
			mesh.Name = "SlimeMesh"
			mesh.Parent = model
			return model
		end
		else nil,
})
for _, patch in patches do
	local target = rt.game
	for _, name in string.split(patch[1], ".") do
		target = target and target:FindFirstChild(name)
	end
	assert(target, `--patch: no instance {patch[1]}`)
	local source = target.Source
	local start = string.find(source, patch[2], 1, true)
	assert(start, `--patch: "{patch[2]}" not found in {patch[1]}`)
	local n = 0
	while start do
		source = string.sub(source, 1, start - 1) .. patch[3] .. string.sub(source, start + #patch[2])
		n += 1
		start = string.find(source, patch[2], start + #patch[3], true)
	end
	target.Source = source
	print(`patched {patch[1]} ({n} match(es), in memory only)`)
end
local scripts = rt:boot()
print(`booted {#scripts} server script(s) from {path}`)
rt:advance(1)
if withPlayer then
	rt:addPlayer(1001, "Tester", roblox.Vector3.new(0, 10, 0))
end
rt:advance(seconds)

local failed = 0
for _, check in Checks.all(rt) do
	print(`{if check.ok then "PASS" else "FAIL"}  {check.name}: {check.detail}`)
	if not check.ok then
		failed += 1
	end
end
print(`{failed} check(s) failed after {seconds} s of server time`)
process.exit(if failed > 0 then 1 else 0)
