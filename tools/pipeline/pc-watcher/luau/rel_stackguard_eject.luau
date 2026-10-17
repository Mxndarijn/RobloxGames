-- Server datamodel: release probe R1 (ADVISORY), StackGuard (#273, bug 10): a character whose root is inside the fountain-top slime stack
-- (Map.Volcano.EmergeMesh = slime_fountain_emerge, Box collision) is moved by the server (WorldView.ejectFromStack -> StackGuard.ejectPoint)
-- to just above the top, or radially outside. The REAL test player's character (unanchored, server network ownership) is teleported into the
-- stack's oriented box and its root sampled every 0.05 s for 3 s. The box is the MeshPart child "Mesh" (else the slot part), in its own frame.
-- Per try: before / after positions (world and box-local), time to eject, number of > 3 stud jumps, final state (on_top / outside / inside).
-- Every eject also prints "[PCW StackGuard] eject before=(x,y,z) after=(x,y,z) t=..s" (shows in the Studio output).
-- Checks (ok = every non-nil check true):
--   eject_from_centre     root put at the box centre: ejected within 1 s, ends on top or outside, never back inside
--   eject_under_top       root put 0.8 studs under the box top: the same
-- The character ends where it started with its Anchored states, owner and WalkSpeed. ~8 s.
local Players = game:GetService("Players")
local ORDER = { "eject_from_centre", "eject_under_top" }
local checks = {}
local function set(name, ok, info)
	checks[name] = { ok = ok, info = info }
end
local function finish(extra)
	local parts, all, any = {}, true, false
	for _, name in ORDER do
		local c = checks[name] or { ok = nil, info = "not run" }
		checks[name] = c
		table.insert(parts, name .. " " .. (if c.ok == true then "PASS" elseif c.ok == false then "FAIL" else "n/a"))
		if c.ok == false then
			all = false
		elseif c.ok == true then
			any = true
		end
	end
	return {
		ok = if not all then false elseif any then true else nil,
		summary = table.concat(parts, ", "),
		detail = { checks = checks, extra = extra },
	}
end
local function missing(msg)
	return { ok = false, summary = msg, detail = { checks = checks } }
end

local player = Players:GetPlayers()[1]
if not player then
	return finish("no real Player in the server")
end
-- character: the REAL test player's, unanchored with server network ownership for the probe and restored at the end -------------------
local char, hum, root = player.Character, nil, nil
hum = char and char:FindFirstChildOfClass("Humanoid")
root = char and char:FindFirstChild("HumanoidRootPart")
if not (root and hum) then
	return finish("the test player has no character")
end
local startCF = root.CFrame
local startAnchored = {}
for _, d in char:GetDescendants() do
	if d:IsA("BasePart") then
		startAnchored[d] = d.Anchored
	end
end
local startSpeed = hum.WalkSpeed
local function free()
	for _, d in char:GetDescendants() do
		if d:IsA("BasePart") then
			d.Anchored = false
		end
	end
	hum.WalkSpeed = 16
	pcall(function()
		root:SetNetworkOwner(nil)
	end)
end
local function teleport(cf)
	char:PivotTo(cf)
	root.AssemblyLinearVelocity = Vector3.zero
	root.AssemblyAngularVelocity = Vector3.zero
end
local made = {}
local undo = {} -- functions that restore what the probe touched
local extraInfo = {}
local volcano = workspace:FindFirstChild("Map") and workspace.Map:FindFirstChild("Volcano")
local slot = volcano and volcano:FindFirstChild("EmergeMesh")
local ref = slot and (slot:FindFirstChild("Mesh") or slot)
if not (ref and ref:IsA("BasePart")) then
	return missing("Map.Volcano.EmergeMesh (fountain statues) missing")
end
-- the game's own thresholds when its module can be required, else the same numbers
local MARGIN, SLACK = 0.5, 1.5
pcall(function()
	local SG = require(game:GetService("ServerScriptService").Server.StackGuard)
	MARGIN, SLACK = SG.MARGIN, SG.TOP_SLACK
end)
local half = ref.Size / 2
local function stateOf(l)
	if math.abs(l.X) < half.X - MARGIN and math.abs(l.Z) < half.Z - MARGIN and l.Y > -half.Y and l.Y < half.Y + SLACK then
		return "inside"
	end
	if math.abs(l.X) < half.X and math.abs(l.Z) < half.Z and l.Y >= half.Y - 0.5 then
		return "on_top"
	end
	return "outside"
end
local function v3(v)
	return { v.X, v.Y, v.Z }
end
extraInfo.box = { size = v3(ref.Size), centre = v3(ref.Position), can_collide = ref.CanCollide, fidelity = tostring(ref.CollisionFidelity) }

local function try(name, localPoint)
	free()
	teleport(CFrame.new(ref.CFrame * localPoint))
	local before = root.Position
	local beforeL = ref.CFrame:PointToObjectSpace(before)
	local last, t0 = before, os.clock()
	local tEject, after, afterL, jumps, backInside = nil, nil, nil, 0, false
	while os.clock() - t0 < 3 do
		task.wait(0.05)
		local pos = root.Position
		local l = ref.CFrame:PointToObjectSpace(pos)
		if (pos - last).Magnitude > 3 then
			jumps += 1
			if not tEject then
				tEject, after, afterL = os.clock() - t0, pos, l
				print(string.format("[PCW StackGuard] eject before=(%.1f,%.1f,%.1f) after=(%.1f,%.1f,%.1f) t=%.2fs", before.X, before.Y, before.Z, pos.X, pos.Y, pos.Z, tEject))
			end
		elseif tEject and stateOf(l) == "inside" then
			backInside = true
		end
		last = pos
	end
	local final = stateOf(ref.CFrame:PointToObjectSpace(root.Position))
	local info = {
		before = v3(before), before_local = v3(beforeL),
		after = after and v3(after), after_local = afterL and v3(afterL),
		time_to_eject_s = tEject, jumps_over_3_studs = jumps, final_state = final, back_inside = backInside,
	}
	if not tEject then
		info.problem = "never ejected"
	end
	set(name, tEject ~= nil and tEject <= 1 and final ~= "inside" and not backInside, info)
end

local function run()
	try("eject_from_centre", Vector3.zero)
	try("eject_under_top", Vector3.new(0, half.Y - 0.8, 0))
end

local ok, err = pcall(run)
for _, o in made do
	pcall(function()
		o:Destroy()
	end)
end
for _, fn in undo do
	pcall(fn)
end
pcall(function()
	hum:MoveTo(root.Position)
	for _, d in char:GetDescendants() do
		if d:IsA("BasePart") then
			d.Anchored = false
		end
	end
	char:PivotTo(startCF)
	root.AssemblyLinearVelocity = Vector3.zero
	hum.WalkSpeed = startSpeed
	pcall(function()
		root:SetNetworkOwnershipAuto()
	end)
	for d, a in startAnchored do
		d.Anchored = a
	end
end)
if not ok then
	for _, name in ORDER do
		if not checks[name] then
			set(name, false, "probe error: " .. tostring(err))
		end
	end
	return finish("probe error: " .. tostring(err))
end
return finish(extraInfo)
