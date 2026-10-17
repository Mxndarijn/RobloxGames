-- Server datamodel: locked-base trap probe (ADVISORY). A non-owner standing inside a plot when its owner locks it must end up OUTSIDE the gate,
-- on the ground, facing away from the plot (WorldView.ejectIntruders, the sweep updatePlots runs the moment a plot flips to locked; it shares
-- PlotLockGuard.ejectPose with the per-player guard in enforceLocks). The REAL test player is the intruder; the owner is a fake (userId -9001) in a
-- MIRROR pure World (the live `world` is a local of init.server and not reachable), on a plot nobody owns and that is unlocked right now.
-- The probe teleports the player to the middle of that plot, then does what updatePlots does on the lock flip: sets the Locked attribute and calls the
-- real WorldView.ejectIntruders(mirror, index). Checks (ok = every check true):
--   inside_before   the player's root is trapped in the plot (PlotLockGuard.trapped) before the lock
--   outside_gate    after the lock the root is past the front slab's outer face (plot-local z < WorldLayout.frontBarrier().zOuter), not trapped
--   on_ground       a ray down from the root hits ground within STAND_HEIGHT + 2 studs (not floating, not sunk)
--   facing_out      the root's look vector points away from the plot (plot-local -Z), dot >= 0.9
--   owner_untouched an owner-side stand-in (the mirror owner is not a real Player) is n/a; instead a second ejectIntruders call is a no-op for a
--                   character already outside (position unchanged within 0.5 studs)
-- The character's CFrame and Anchored states, the plot's Locked attribute are restored; nothing else is made.
local Players = game:GetService("Players")
local RS = game:GetService("ReplicatedStorage")
local Server = game:GetService("ServerScriptService"):FindFirstChild("Server")
if not Server then
	return { ok = false, summary = "ServerScriptService.Server missing", detail = {} }
end
local reqOk, mods = pcall(function()
	local Shared = RS.Shared
	return {
		World = require(Server.World),
		Sessions = require(Server.Sessions),
		WorldView = require(Server.WorldView),
		Guard = require(Server.PlotLockGuard),
		PlayerData = require(Shared.PlayerData),
		Config = require(Shared.Config),
		Constants = require(Shared.Constants),
		Layout = require(RS.Visuals.WorldLayout),
	}
end)
if not reqOk then
	return { ok = false, summary = "require failed: " .. tostring(mods), detail = {} }
end
local Guard, WorldView = mods.Guard, mods.WorldView
local LOCKED = mods.Constants.PLOT_LOCKED_ATTRIBUTE
local checks = {}
local ORDER = { "inside_before", "outside_gate", "on_ground", "facing_out", "second_call_noop" }
local function set(name, ok, info)
	checks[name] = { ok = ok, info = info }
end
local function finish(extra)
	local parts, all = {}, true
	for _, name in ORDER do
		local c = checks[name] or { ok = nil, info = "not run" }
		checks[name] = c
		table.insert(parts, name .. " " .. (if c.ok == true then "PASS" elseif c.ok == false then "FAIL" else "n/a"))
		all = all and c.ok == true
	end
	return { ok = all, summary = table.concat(parts, ", "), detail = { checks = checks, extra = extra } }
end

local player = Players:GetPlayers()[1]
local char = player and player.Character
local root = char and char:FindFirstChild("HumanoidRootPart")
if not root then
	return finish("no real Player / character in the server")
end
local plotsFolder = workspace:FindFirstChild(mods.Constants.PLOTS_FOLDER)
local index, plot
for n = 0, mods.Config.PLOT_COUNT - 1 do
	local i = (n + 1) % mods.Config.PLOT_COUNT + 1 -- Plot_2 first (the shot's target)
	local p = plotsFolder and plotsFolder:FindFirstChild("Plot_" .. i)
	local o = p and p:GetAttribute("OwnerUserId")
	if p and p:FindFirstChild("Base") and (o == 0 or o == nil) and p:GetAttribute(LOCKED) ~= true then
		index, plot = i, p
		break
	end
end
if not plot then
	return finish("no free unlocked plot to use")
end
local base = plot.Base
local half = base.Size.X / 2
local frontZ = mods.Layout.frontBarrier().zOuter

local now = os.time()
local mirror = mods.World.new({ now = now, seed = 11, plotCount = mods.Config.PLOT_COUNT })
local owner = mods.Sessions.join(mirror, -9001, "PCW Lock Owner", mods.PlayerData.new(), now)
if not owner then
	return finish("could not join the mirror owner")
end
mirror.plots[owner.plotIndex] = nil
owner.plotIndex = index
mirror.plots[index] = -9001

local startCF = root.CFrame
local anchored = {}
for _, d in char:GetDescendants() do
	if d:IsA("BasePart") then
		anchored[d] = d.Anchored
		d.Anchored = false
	end
end
local function localPos()
	return base.CFrame:PointToObjectSpace(root.Position)
end

char:PivotTo(base.CFrame * CFrame.new(3, 4, 0))
root.AssemblyLinearVelocity = Vector3.zero
task.wait(0.5)
local p0 = localPos()
set("inside_before", Guard.trapped(p0.X, p0.Y, p0.Z, half, frontZ), { x = p0.X, y = p0.Y, z = p0.Z })

plot:SetAttribute(LOCKED, true)
WorldView.ejectIntruders(mirror, index)
task.wait(1)
local p1 = localPos()
set("outside_gate", p1.Z < frontZ and not Guard.trapped(p1.X, p1.Y, p1.Z, half, frontZ), { x = p1.X, y = p1.Y, z = p1.Z, frontZ = frontZ })

local params = RaycastParams.new()
params.FilterType = Enum.RaycastFilterType.Exclude
params.FilterDescendantsInstances = { char }
local hit = workspace:Raycast(root.Position, Vector3.new(0, -(Guard.STAND_HEIGHT + 8), 0), params)
local drop = hit and (root.Position.Y - hit.Position.Y)
set("on_ground", drop ~= nil and math.abs(drop - Guard.STAND_HEIGHT) <= 2, { drop = drop, hit = hit and hit.Instance:GetFullName() })

local look = base.CFrame:VectorToObjectSpace(root.CFrame.LookVector)
local flat = Vector3.new(look.X, 0, look.Z)
local dot = if flat.Magnitude > 0 then flat.Unit:Dot(Vector3.new(0, 0, -1)) else 0
set("facing_out", dot >= 0.9, { dot = dot })

local before = root.Position
WorldView.ejectIntruders(mirror, index)
task.wait(0.2)
set("second_call_noop", (root.Position - before).Magnitude <= 0.5, { moved = (root.Position - before).Magnitude })

plot:SetAttribute(LOCKED, false)
char:PivotTo(startCF)
root.AssemblyLinearVelocity = Vector3.zero
for d, a in anchored do
	d.Anchored = a
end
return finish(nil)
