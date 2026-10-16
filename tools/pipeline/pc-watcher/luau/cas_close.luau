-- Client datamodel: the Esc test without any input injection. Sets the Studio-only SlimeUI attribute
-- "PcwPress" = "Escape" (src/ui/init.client): the hook runs the game's CloseMenu action handler
-- (src/ui/MenuClose) with a Begin state, then clears PcwPress and writes PcwPressResult.
-- ContextActionService:CallFunction is not allowed from execute_luau (lacking capability RobloxScript).
local gui = game:GetService("Players").LocalPlayer.PlayerGui:FindFirstChild("SlimeUI")
if not gui then
	return { called = false, error = "SlimeUI not found" }
end
gui:SetAttribute("PcwPressResult", nil)
gui:SetAttribute("PcwPress", nil) -- an unchanged value fires no signal
gui:SetAttribute("PcwPress", "Escape")
local t0 = os.clock()
while gui:GetAttribute("PcwPress") ~= nil and os.clock() - t0 < 3 do
	task.wait(0.05)
end
local result = gui:GetAttribute("PcwPressResult")
if gui:GetAttribute("PcwPress") ~= nil or result == nil then
	return { called = false, error = "PcwPress hook did not answer (Studio-only hook missing in this build?)" }
end
return {
	called = result ~= "not_bound",
	result = result,
	bound = result ~= "not_bound",
	error = if result == "not_bound" then "Esc not bound (Layout.CLOSE_WITH_ESCAPE is false)" else nil,
}
