-- SlimeCam scenario (Server): six wild slimes of different gaits cloned onto pads 2..7 of plot 1 (PcwFill), plus
-- the pad 1 slime from the PcwGrowth hook. Measurement only.
local CS = game:GetService("CollectionService")
local Http = game:GetService("HttpService")
local RunService = game:GetService("RunService")
local player = game.Players:GetPlayers()[1]
local plot = workspace.Plots.Plot_1
local folder = plot:FindFirstChild("Slimes") or plot
local function padTop(i)
	local pad = plot:FindFirstChild("Pad_" .. i)
	return pad.Position + Vector3.new(0, pad.Size.Y / 2, 0)
end
-- the model pivot that puts the Body's bottom on pad i, facing -Z (the pivot is not always the Body centre)
local function onPad(m, i)
	local b = m.PrimaryPart
	local top = padTop(i)
	local at = Vector3.new(top.X, top.Y + b.Size.Y / 2, top.Z)
	local bodyCf = CFrame.lookAt(at, at + Vector3.new(0, 0, -1))
	return bodyCf * b.CFrame:ToObjectSpace(m:GetPivot())
end
local function fills()
	local out = {}
	for _, m in CS:GetTagged("Slime") do
		if m:GetAttribute("PcwFill") then
			out[m:GetAttribute("PcwPad")] = m
		end
	end
	return out
end
-- the server's own WorldView glide (eased, facing the pad)
local function glide(from, to)
	local flat = Vector3.new(to.X - from.X, 0, to.Z - from.Z)
	local facing = if flat.Magnitude > 1e-3 then flat.Unit else to.LookVector
	return function(t)
		if t >= 1 then
			return to
		end
		local u = t * t * (3 - 2 * t)
		local at = from.Position:Lerp(to.Position, u)
		return CFrame.lookAt(at, at + facing)
	end
end
local function run(model, seconds, path)
	local start = os.clock()
	while true do
		local t = math.min((os.clock() - start) / seconds, 1)
		model:PivotTo(path(t))
		if t >= 1 then
			return
		end
		RunService.Heartbeat:Wait()
	end
end

do


	player:SetAttribute("PcwGrowth", 60)
	for _, m in CS:GetTagged("Slime") do
		if m:GetAttribute("PcwFill") then
			m:Destroy()
		end
	end
	-- one wild of each gait we can find, cloned onto pads 2..7
	local want = { "Hop", "Ooze", "Waddle", "Float", "Scoot", "Hop" }
	local Persona = require(game.ReplicatedStorage.Shared.SlimePersona)
	local used, picked = {}, {}
	for _, gait in want do
		for _, m in CS:GetTagged("Slime") do
			local sp = m:GetAttribute("Species")
			if m:GetAttribute("State") == "Wild" and sp and not used[m] and Persona.of(sp).gait == gait and m.PrimaryPart then
				used[m] = true
				table.insert(picked, m)
				break
			end
		end
	end
	for _, m in CS:GetTagged("Slime") do
		if #picked >= 6 then
			break
		end
		if m:GetAttribute("State") == "Wild" and not used[m] and m.PrimaryPart and m:GetAttribute("Species") then
			used[m] = true
			table.insert(picked, m)
		end
	end
	local made = {}
	for i, src in picked do
		local pad = i + 1
		local m = src:Clone()
		for _, k in { "LaneAt", "LaneUntil", "ChoreoSeed", "Riding", "DespawnAt", "Price", "LifeMode", "LifeTier", "LifeAnimating" } do
			m:SetAttribute(k, nil)
		end
		for _, d in m:GetDescendants() do
			if d:IsA("ProximityPrompt") then
				d:Destroy()
			end
		end
		m:SetAttribute("State", "Pad")
		m:SetAttribute("OwnerUserId", player.UserId)
		m:SetAttribute("SlimeId", Http:GenerateGUID(false))
		m:SetAttribute("PcwFill", true)
		m:SetAttribute("PcwPad", pad)
		m:PivotTo(onPad(m, pad))
		m.Parent = folder
		CS:AddTag(m, "Slime")
		table.insert(made, pad .. ":" .. tostring(m:GetAttribute("Species")))
	end
	_G.PcwMade = table.concat(made, " ")
end
return _G.PcwMade
