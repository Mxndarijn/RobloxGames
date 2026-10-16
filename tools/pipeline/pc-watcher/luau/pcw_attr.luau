-- Server datamodel: sets the Studio-only Player attribute %%NAME%% to %%VALUE%% (false clears it) on
-- every player. src/server/init.server watches "PcwGrowth" (percent) and "PcwDexWeather" (true) and changes
-- the player's real session data, so WorldView (Growth % label, scale) and the Dex panel draw it themselves.
local value = %%VALUE%%
if value == false then
	value = nil
end
local out = {}
for _, player in game:GetService("Players"):GetPlayers() do
	player:SetAttribute(%%NAME%%, value)
	table.insert(out, player.Name)
end
task.wait(0.5)
return { players = out }
