-- WalkCheck (Client): grabs a wild slime off the lane (no eggs or bosses), carries it to CASE's drop spot and drops
-- it there with the real "Drop" request, then moves up out of the slime's way.
local CS = game:GetService("CollectionService")
local RunService = game:GetService("RunService")
local lp = game:GetService("Players").LocalPlayer
local char = lp.Character or lp.CharacterAdded:Wait()
local hrp = char:WaitForChild("HumanoidRootPart") :: BasePart
local request = RS:WaitForChild(Constants.REMOTES_FOLDER):WaitForChild(Constants.REQUEST) :: RemoteFunction

-- The anti-cheat (SlimeGuard) kicks a player who teleports, so the character glides everywhere at GLIDE_SPEED, under
-- the guard's walk limit (14.4 studs/s while carrying). It moves by physics (velocity toward the goal every frame,
-- platform-standing, its parts not colliding so it passes through walls): the server sees neither an anchored root
-- moved on the client nor CFrame writes the physics step undoes.
local GLIDE_SPEED = 12
-- One run at a time: a run left over from a broken case stops at its next step instead of fighting this one.
_G.WalkCheckRun = (_G.WalkCheckRun or 0) + 1
local run = _G.WalkCheckRun
local humanoid = char:WaitForChild("Humanoid") :: Humanoid
-- The player's follow camera: the game only shows prompts on screen, so a camera left pointing elsewhere (Studio
-- restores the camera type a script set after it ends) means no grab. Set after a moment: this runs as a job.
task.delay(0.2, function()
	local cam = workspace.CurrentCamera
	cam.CameraType = Enum.CameraType.Custom
	cam.CameraSubject = humanoid
end)
hrp.Anchored = false
humanoid.PlatformStand = true
-- each part's own CanCollide, read once per character (a broken run may have left them off), put back on release
local collide = _G.WalkCheckCollide
if not collide or collide.char ~= char then
	collide = { char = char, parts = {} }
	for _, part in char:GetDescendants() do
		if part:IsA("BasePart") then
			collide.parts[part] = part.CanCollide
		end
	end
	_G.WalkCheckCollide = collide
end
local noclip: RBXScriptConnection
noclip = RunService.Stepped:Connect(function()
	if _G.WalkCheckRun ~= run then
		noclip:Disconnect()
		return
	end
	for part in collide.parts do
		part.CanCollide = false
	end
end)
local function release()
	noclip:Disconnect()
	RunService.Stepped:Wait()
	for part, was in collide.parts do
		part.CanCollide = was
	end
	humanoid.PlatformStand = false
	hrp.AssemblyLinearVelocity = Vector3.zero
end
-- the server's toasts, for a refused grab
local toasts = {}
local notify = RS:WaitForChild(Constants.REMOTES_FOLDER):WaitForChild("Notify") :: RemoteEvent
local listen = notify.OnClientEvent:Connect(function(message)
	table.insert(toasts, tostring(message))
end)
task.delay(400, function()
	listen:Disconnect()
end)
-- Steers toward `at` for this frame: full glide speed when far, slowing down over the last studs.
local function pin(at: Vector3)
	if _G.WalkCheckRun ~= run then
		error("superseded by a newer run")
	end
	local gap = at - hrp.Position
	hrp.AssemblyLinearVelocity = if gap.Magnitude > 0.05
		then gap.Unit * math.min(GLIDE_SPEED, gap.Magnitude * 8)
		else Vector3.zero
	hrp.AssemblyAngularVelocity = Vector3.zero
end
local function hold(at: Vector3, seconds: number)
	local t = os.clock()
	while os.clock() - t < seconds do
		pin(at)
		RunService.Heartbeat:Wait()
	end
end
local function glideStep(to: Vector3): boolean
	if (to - hrp.Position).Magnitude < 0.6 then
		return false
	end
	pin(to)
	RunService.Heartbeat:Wait()
	return true
end
local function glide(to: Vector3)
	local t = os.clock()
	while glideStep(to) and os.clock() - t < 120 do
	end
end

local spot, why = resolveSpot(CASE)
if not spot then
	return { error = why }
end
if lp:GetAttribute("Carrying") then
	request:InvokeServer("Drop") -- left over from a case that broke off
	task.wait(1)
end
-- The admin menu's test-save cheats (memory store only): an empty plot (a carry that glides through our own plot
-- deposits the slime, and a full plot refuses every grab without a toast), cash for any lane slime, no tutorial.
request:InvokeServer("Admin", "resetSave")
request:InvokeServer("Admin", "cashSet", nil, 1e15)
request:InvokeServer("Admin", "skipTutorial")

local function grabbable(m: Instance): boolean
	local species = tostring(m:GetAttribute("Species") or "")
	local cash = lp:FindFirstChild("leaderstats") and lp.leaderstats:FindFirstChild("Cash")
	local prompt = m:FindFirstChildWhichIsA("ProximityPrompt", true)
	local body = (m :: Model).PrimaryPart
	local _, offLane = ParadeLane.nearest(if body then body.Position.X else 1e6, if body then body.Position.Z else 1e6)
	-- on the lane, and not one this run dropped (the game hides a dropped slime's prompt from whoever dropped it)
	return m:GetAttribute("State") == "Wild"
		and offLane <= ParadeLane.HALF_WIDTH
		and not (_G.WalkCheckDropped or {})[m:GetAttribute("SlimeId")]
		and prompt ~= nil
		and prompt:GetAttribute(Constants.PROMPT_HIDE_ATTRIBUTE) ~= lp.UserId
		and not m:GetAttribute("Riding")
		and not m:GetAttribute(Constants.BOSS_ATTRIBUTE)
		and not m:GetAttribute(Constants.GRAB_REBIRTHS_ATTRIBUTE)
		and species ~= "" -- eggs carry no species (and smash when dropped)
		and not string.find(string.lower(species .. m.Name), "egg")
		and (m:GetAttribute("Price") or 1e9) <= (if cash then cash.Value else 0)
		and (m :: Model).PrimaryPart ~= nil
		and prompt ~= nil
		and prompt.Enabled
end

-- One grab try: the nearest grabbable slime, caught up with, its prompt held. Returns the slime's id and details, or
-- nil and why. While the slime is out of sight (the client swaps its model) the character hovers where it was.
local function tryGrab(): (string?, string?, number?, string?)
	local target: Model? = nil
	local t1 = os.clock()
	while not target and os.clock() - t1 < 90 do
		local best = math.huge
		for _, m in CS:GetTagged("Slime") do
			if grabbable(m) then
				local d = ((m :: Model).PrimaryPart.Position - hrp.Position).Magnitude
				if d < best then
					target, best = m :: Model, d
				end
			end
		end
		if not target then
			hold(hrp.Position, 0.5)
		end
	end
	if not target then
		return nil, nil, nil, "nothing to grab"
	end
	local id = target:GetAttribute("SlimeId")
	local species = target:GetAttribute("Species")
	local size = ((target :: Model).PrimaryPart :: BasePart).Size.X
	local function current(): (Model?, ProximityPrompt?)
		for _, m in CS:GetTagged("Slime") do
			if m:GetAttribute("SlimeId") == id and m:GetAttribute("State") == "Wild" and (m :: Model).PrimaryPart then
				return m :: Model, m:FindFirstChildWhichIsA("ProximityPrompt", true) :: ProximityPrompt?
			end
		end
		return nil, nil
	end
	local last = hrp.Position
	local function beside(): Vector3
		local m = current()
		if m then
			last = (m.PrimaryPart :: BasePart).Position + Vector3.new(0, 1, 2.5)
		end
		return last
	end
	-- catch up with it (it walks the lane slower than we glide), then stay beside it and hold its prompt
	local t = os.clock()
	while os.clock() - t < 60 and glideStep(beside()) do
	end
	local follow: RBXScriptConnection
	follow = RunService.Heartbeat:Connect(function()
		if _G.WalkCheckRun ~= run then
			follow:Disconnect()
		else
			pin(beside())
		end
	end)
	t = os.clock()
	local held: ProximityPrompt? = nil
	while os.clock() - t < 6 and lp:GetAttribute("Carrying") ~= id do
		local _, prompt = current()
		if prompt and prompt ~= held then
			if held then
				held:InputHoldEnd()
			end
			held = prompt
			-- slime prompts are OnePerButton: a neighbour's prompt can be the one shown, and a hold on a hidden
			-- prompt does nothing. Show this one too (client side only).
			prompt.Exclusivity = Enum.ProximityPromptExclusivity.AlwaysShow
			prompt:InputHoldBegin()
		end
		task.wait(0.05)
	end
	if held then
		held:InputHoldEnd()
	end
	follow:Disconnect()
	if lp:GetAttribute("Carrying") ~= id then
		_G.WalkCheckDropped = _G.WalkCheckDropped or {}
		_G.WalkCheckDropped[id] = true -- don't pick it again
		return nil, nil, nil, string.format("%s %s", tostring(species), if current() then "still there" else "gone")
	end
	return id, species, size, nil
end

-- Grabs are refused (silently) while a boss is out: wait for it to leave
local function bossOut(): boolean
	for _, m in CS:GetTagged("Slime") do
		if m:GetAttribute(Constants.BOSS_ATTRIBUTE) then
			return true
		end
	end
	return false
end
local waited = os.clock()
while bossOut() and os.clock() - waited < 300 do
	hold(hrp.Position, 1)
end

local slimeId, species, size, failed
local tries = {}
for _ = 1, 4 do
	slimeId, species, size, failed = tryGrab()
	if slimeId then
		break
	end
	table.insert(tries, failed)
end
if not slimeId then
	release()
	return {
		error = string.format("grab failed (%s; toasts: %s)", table.concat(tries, ", "), table.concat(toasts, " | ")),
	}
end
-- carry it to the drop spot and hover there (a ledge or a slope can't move us), then drop
local stand = spot + Vector3.new(0, 3, 0)
glide(stand)
hold(stand, 0.6)
local res
task.spawn(function()
	res = request:InvokeServer("Drop")
end)
_G.WalkCheckDropped = _G.WalkCheckDropped or {}
_G.WalkCheckDropped[slimeId] = true
hold(stand, 0.4)
-- up out of the camera's way, then let go (it falls back down after the slime has left)
local above = spot + Vector3.new(0, 12, 0)
glide(above)
hold(above, 1)
release()
return {
	slime = slimeId,
	species = species,
	size = size,
	drop = res,
	spot = { spot.X, spot.Y, spot.Z },
}
