-- SlimeCam scenario (Client): the end of the goo lane. Waits for a wild slime of species _G.SlimeCamWant (any
-- species when unset) to be about 9 s from the end of its life, then pins a side camera on the last stretch of the
-- lane and the drain, with the player standing beside it, so the recording covers the despawn telegraph (the last
-- DESPAWN_TELEGRAPH_SECONDS) and the drain.
local CS = game:GetService("CollectionService")
local RS = game:GetService("RunService")
local ParadeLane = require(game.ReplicatedStorage.Shared.ParadeLane)
local lp = game.Players.LocalPlayer
local char = lp.Character or lp.CharacterAdded:Wait()
local hrp = char:WaitForChild("HumanoidRootPart")
local want = _G.SlimeCamWant
local endAt = { ParadeLane.offsetAt(ParadeLane.LENGTH - 8, 0) }
local target
local t1 = os.clock()
while not target and os.clock() - t1 < 170 do
	for _, m in CS:GetTagged("Slime") do
		local untilAt = m:GetAttribute("LaneUntil")
		if
			m:GetAttribute("State") == "Wild"
			and (want == nil or m:GetAttribute("Species") == want)
			and type(untilAt) == "number"
			and untilAt - workspace:GetServerTimeNow() < 9.5
			and untilAt - workspace:GetServerTimeNow() > 8
		then
			target = m
			break
		end
	end
	if not target then
		task.wait(0.1)
	end
end
if not target then
	return { error = "no " .. tostring(want) .. " near the drain" }
end
local focus = Vector3.new(endAt[1] + 2, 1.5, endAt[2])
hrp.CFrame = CFrame.lookAt(focus + Vector3.new(4, 3, -9), focus)
local view = CFrame.lookAt(focus + Vector3.new(2, 8, -20), focus)
local t0 = os.clock()
RS:BindToRenderStep("SlimeCamPin", Enum.RenderPriority.Last.Value + 2, function()
	if os.clock() - t0 > 60 then
		RS:UnbindFromRenderStep("SlimeCamPin")
		return
	end
	local cam = workspace.CurrentCamera
	cam.CameraType = Enum.CameraType.Scriptable
	cam.CFrame = view
end)
return { species = target:GetAttribute("Species") }
