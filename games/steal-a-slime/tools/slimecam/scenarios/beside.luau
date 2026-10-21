-- SlimeCam scenario (Client): the player walks beside an affordable hopper on the goo lane, 3.5 studs to its side,
-- with the normal follow camera. Waits up to 90 s for such a slime; keeps walking for 40 s.
local CS = game:GetService("CollectionService")
local RS = game:GetService("RunService")
local P = require(game.ReplicatedStorage.Shared.SlimePersona)
local lp = game.Players.LocalPlayer
local char = lp.Character or lp.CharacterAdded:Wait()
local hum = char:WaitForChild("Humanoid")
local hrp = char:WaitForChild("HumanoidRootPart")
workspace.CurrentCamera.CameraType = Enum.CameraType.Custom
local want = _G.SlimeCamWant or "Hop"
local target
local t1 = os.clock()
while not target and os.clock() - t1 < 90 do
	local cash = lp.leaderstats.Cash.Value
	for _, m in CS:GetTagged("Slime") do
		local sp = m:GetAttribute("Species")
		local untilAt = m:GetAttribute("LaneUntil")
		if
			m:GetAttribute("State") == "Wild"
			and sp
			and P.of(sp).gait == want
			and ((m:GetAttribute("Price") or 1e9) <= cash or os.clock() - t1 > 20) -- affordable first, any after 20 s
			and not m:GetAttribute("Riding")
			and untilAt
			and untilAt - workspace:GetServerTimeNow() > 20
		then
			target = m
			break
		end
	end
	if not target then
		task.wait(0.5)
	end
end
if not target then
	return { error = "no affordable " .. want }
end
local b = target.PrimaryPart
hrp.CFrame = CFrame.new(b.Position + Vector3.new(3, 2, 3))
local t0 = os.clock()
local conn
conn = RS.RenderStepped:Connect(function()
	if os.clock() - t0 > 40 or not target.Parent or target:GetAttribute("State") ~= "Wild" then
		conn:Disconnect()
		return
	end
	local bp, look = b.Position, b.CFrame.LookVector
	local side = Vector3.new(-look.Z, 0, look.X)
	hum:MoveTo(bp + side * 3.5 + look * 0.5)
end)
task.wait(1.5) -- settle in beside it
return { species = target:GetAttribute("Species") }
