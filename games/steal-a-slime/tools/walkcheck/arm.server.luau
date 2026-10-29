-- WalkCheck (Server): arms the recorder for CASE. The next slime that goes from "Carried" to "Wild" is recorded
-- every Heartbeat until it is back on the lane (or CASE.seconds pass). The result lands in _G.WalkCheck[CASE.id]
-- (collect.server.luau reads it). Builds the case's temporary walls in workspace.WalkCheckTemp.
local CS = game:GetService("CollectionService")
local RunService = game:GetService("RunService")

_G.WalkCheck = _G.WalkCheck or {}
local results = _G.WalkCheck
results[CASE.id] = { state = "armed" }

local old = workspace:FindFirstChild("WalkCheckTemp")
if old then
	old:Destroy()
end
local temp = Instance.new("Folder")
temp.Name = "WalkCheckTemp"
temp.Parent = workspace

local function wall(cf: CFrame, size: Vector3)
	local p = Instance.new("Part")
	p.Name = "WalkCheckWall"
	p.Anchored = true
	p.CanCollide = true
	p.Size = size
	p.CFrame = cf
	p.Color = Color3.fromRGB(230, 60, 60)
	p.Transparency = 0.3
	p.Parent = temp
	return p
end

local spot, why = resolveSpot(CASE)
if not spot then
	results[CASE.id] = { state = "done", error = why }
	return { armed = false, error = why }
end
if CASE.box then
	-- four walls round the drop spot, BOX studs out: no way out at all
	local r = CASE.box
	for k = 0, 3 do
		local a = k * math.pi / 2
		local c = spot + Vector3.new(math.cos(a) * r, 5, math.sin(a) * r)
		wall(CFrame.lookAt(c, Vector3.new(spot.X, c.Y, spot.Z)), Vector3.new(2 * r + 2, 10, 1))
	end
end

local function groundParams(): RaycastParams
	local params = solidParams()
	local list = params.FilterDescendantsInstances
	local keep = {}
	for _, inst in list do
		if inst ~= temp then
			table.insert(keep, inst)
		end
	end
	params.FilterDescendantsInstances = keep -- the case's walls are ground too
	return params
end

local function bodyOf(model: Model): BasePart?
	return model.PrimaryPart or model:FindFirstChild("Body") :: BasePart?
end

local SECONDS = CASE.seconds or 60
local SAMPLE = 0.1

task.spawn(function()
	local armedAt = os.clock()
	local players = game:GetService("Players")
	local function modelOf(id: string): Model?
		for _, m in CS:GetTagged("Slime") do
			if m:GetAttribute("SlimeId") == id and m:GetAttribute("State") == "Wild" then
				return m :: Model
			end
		end
		return nil
	end
	-- the slime a player carries (its id), then the Wild model it becomes when dropped
	local id: string? = nil
	local found: Model? = nil
	while os.clock() - armedAt < 240 and not found do
		for _, player in players:GetPlayers() do
			local carrying = player:GetAttribute("Carrying")
			if type(carrying) == "string" then
				id = carrying
			end
		end
		if id and not players:GetPlayers()[1]:GetAttribute("Carrying") then
			found = modelOf(id)
		end
		RunService.Heartbeat:Wait()
	end
	if not found or not id then
		results[CASE.id] = { state = "done", error = "no slime was dropped" }
		return
	end
	local model: Model = found
	results[CASE.id] = { state = "recording" }

	local gp = groundParams()
	local t0 = os.clock()
	local first = model:GetPivot().Position
	local last = first
	local walked, frames, insideFrames, floatFrames, fallFrames = 0, 0, 0, 0, 0
	local recent: { { number } } = {} -- (t, y) over the last SINK_WINDOW
	local SINK_WINDOW = 0.15
	local maxFloat, maxSpeed, maxInside = 0, 0, 0
	local hits: { [string]: number } = {}
	local path = {}
	local nextSample = 0
	local onLaneSince: number? = nil
	local reachedAt: number? = nil
	local laneFloat: number? = nil
	local blocked = false
	local ended = "timeout"
	while true do
		local dt = RunService.Heartbeat:Wait()
		local now = os.clock()
		local t = now - t0
		if not model.Parent or model:GetAttribute("State") ~= "Wild" then
			local again = modelOf(id)
			if not again then
				local state = nil
				for _, m in CS:GetTagged("Slime") do
					if m:GetAttribute("SlimeId") == id then
						state = m:GetAttribute("State")
					end
				end
				ended = if state then "state " .. tostring(state) else "slime gone"
				break
			end
			model = again
		end
		local body = bodyOf(model)
		local pivot = model:GetPivot()
		local p = pivot.Position
		frames += 1
		-- inside: collidable parts within 60% of the body's half size round its centre
		local inside = false
		if body then
			local r = 0.6 * math.min(body.Size.X, body.Size.Y, body.Size.Z) / 2
			local parts = solidsIn(CFrame.new(body.Position), Vector3.one * (2 * r), Enum.PartType.Ball, true)
			if #parts > 0 then
				inside = true
				insideFrames += 1
				maxInside = math.max(maxInside, #parts)
				for _, part in parts do
					local key = part.Parent.Name .. "/" .. part.Name
					hits[key] = (hits[key] or 0) + 1
				end
			end
		end
		-- float: pivot height over the first solid surface below it
		local hit = workspace:Raycast(p + Vector3.new(0, 1.5, 0), Vector3.new(0, -300, 0), gp)
		local float = if hit then p.Y - hit.Position.Y else 999
		local _, away = ParadeLane.nearest(p.X, p.Z)
		local onLane = away <= ParadeLane.HALF_WIDTH
		if onLane and not laneFloat and t > 1 then
			laneFloat = float
		end
		-- a fall off a ledge is not floating: only count it while it is not on its way down (its speed over the last
		-- SINK_WINDOW: the walk and this recorder both run on Heartbeat, so one frame can show no move at all)
		table.insert(recent, { t, p.Y })
		while recent[1][1] < t - SINK_WINDOW do
			table.remove(recent, 1)
		end
		local span = t - recent[1][1]
		local sinking = span > 0 and (p.Y - recent[1][2]) / span < -2
		if sinking then
			fallFrames += 1
		end
		if t > 0.9 and not onLane and not sinking then
			maxFloat = math.max(maxFloat, float)
			if float > 1 then
				floatFrames += 1
			end
		end
		local flat = Vector3.new(p.X - last.X, 0, p.Z - last.Z).Magnitude
		walked += flat
		if t > 0.9 and dt > 0 then
			maxSpeed = math.max(maxSpeed, flat / dt)
		end
		last = p
		if CASE.blockAt and not blocked and t >= CASE.blockAt then
			blocked = true
			local look = Vector3.new(pivot.LookVector.X, 0, pivot.LookVector.Z).Unit
			local c = p + look * 6 + Vector3.new(0, 4, 0)
			wall(CFrame.lookAt(c, c + look), Vector3.new(16, 10, 1))
		end
		if t >= nextSample then
			nextSample += SAMPLE
			table.insert(path, {
				math.floor(t * 100) / 100,
				math.floor(p.X * 10) / 10,
				math.floor(p.Y * 10) / 10,
				math.floor(p.Z * 10) / 10,
				if inside then 1 else 0,
				math.floor(math.min(float, 99) * 10) / 10,
			})
		end
		if onLane and t > 1 then
			onLaneSince = onLaneSince or now
			reachedAt = reachedAt or t
			if now - onLaneSince > 1.5 then
				ended = "on lane"
				break
			end
		else
			onLaneSince = nil
			reachedAt = nil
		end
		if t > SECONDS then
			break
		end
	end
	local s = ParadeLane.nearest(first.X, first.Z)
	local lx, lz = ParadeLane.pointAt(s)
	local hitList = {}
	for key, n in hits do
		table.insert(hitList, { key, n })
	end
	table.sort(hitList, function(a, b)
		return a[2] > b[2]
	end)
	results[CASE.id] = {
		state = "done",
		ended = ended,
		spot = { spot.X, spot.Y, spot.Z },
		drop = { first.X, first.Y, first.Z },
		reachedAt = reachedAt,
		straight = Vector3.new(lx - first.X, 0, lz - first.Z).Magnitude,
		walked = walked,
		frames = frames,
		insideFrames = insideFrames,
		hits = { table.unpack(hitList, 1, math.min(#hitList, 6)) },
		maxFloat = maxFloat,
		floatFrames = floatFrames,
		fallSeconds = fallFrames / 60,
		laneFloat = laneFloat,
		maxSpeed = maxSpeed,
		path = path,
	}
end)
return { armed = true, spot = { spot.X, spot.Y, spot.Z } }
