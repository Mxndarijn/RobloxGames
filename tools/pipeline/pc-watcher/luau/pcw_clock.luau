-- Server datamodel: pins the time of day for a daytime proof shot. %%TIME%% (a number, e.g. 14) sets the
-- Studio-only Lighting attribute PcwClock, which src/server/init.server honours in place of the DayNight
-- cycle (Studio + in-memory store only), and sets Lighting.ClockTime to it; false clears the pin so the
-- cycle takes over again. Returns the ClockTime now in effect.
local Lighting = game:GetService("Lighting")
local value = %%TIME%%
if value == false then
	Lighting:SetAttribute("PcwClock", nil)
else
	Lighting:SetAttribute("PcwClock", value)
	Lighting.ClockTime = value
end
task.wait(1)
return { clock = Lighting.ClockTime, pinned = Lighting:GetAttribute("PcwClock") }
