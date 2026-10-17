-- Client datamodel: weather proof shot. Sets the client-only workspace attribute WeatherDebug to
-- %%WEATHER%% ("" clears it) so WeatherFx draws that weather on THIS client (never replicated), then waits
-- %%WAIT%% s for the tween in and reports the weather emitters' live rates and the tint.
local ATTR = "WeatherDebug"
local before = workspace:GetAttribute(ATTR)
-- %%COVER%% >= 0 pins the client-local ground snow cover (SnowCoverDebug, 0..1) for the snow shots; -1 clears the pin.
-- With the pin set SnowGround v2 reads the phase from the weather: "Snow" = settling, anything else (the melt shots
-- use "Clear") = melting, so a Clear shot pinned at 0.5 shows the melt look (paths cleared first, grass still white).
local cover = %%COVER%%
workspace:SetAttribute("SnowCoverDebug", if cover >= 0 then cover else nil)
local id = %%WEATHER%%
workspace:SetAttribute(ATTR, if id == "" then nil else id)
task.wait(%%WAIT%%)
local part = workspace:FindFirstChild("WeatherEmitter")
local rates, active = {}, 0
if part then
	for _, e in part:GetChildren() do
		if e:IsA("ParticleEmitter") then
			rates[e.Name] = e.Rate
			if e.Rate > 0 then
				active += 1
			end
		end
	end
end
local tint = game:GetService("Lighting"):FindFirstChild("WeatherTint")
local map = workspace:FindFirstChild("Map")
-- The ground is voxel terrain now (GroundTerrain): SnowGround tints the Terrain material colours.
local terrain = workspace.Terrain
local groundColor = terrain:GetMaterialColor(Enum.Material.Grass)
local plazaColor = terrain:GetMaterialColor(Enum.Material.Sand)
return { ground_color = tostring(groundColor), plaza_color = tostring(plazaColor), path_color = tostring(terrain:GetMaterialColor(Enum.Material.Ground)), cover_part = workspace:FindFirstChild("SnowCover") ~= nil, ok = id == "" or id == "Clear" or active > 0, before = before, now = workspace:GetAttribute(ATTR), emitter_part = part ~= nil, rates = rates, active = active, tint = tint ~= nil and tostring(tint.TintColor) or nil }
