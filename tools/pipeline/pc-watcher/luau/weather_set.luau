-- Client datamodel: weather proof shot. Sets the client-only workspace attribute WeatherDebug to
-- %%WEATHER%% ("" clears it) so WeatherFx draws that weather on THIS client (never replicated), then waits
-- %%WAIT%% s for the tween in and reports the weather emitters' live rates and the tint.
local ATTR = "WeatherDebug"
local before = workspace:GetAttribute(ATTR)
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
return { ok = id == "" or active > 0, before = before, now = workspace:GetAttribute(ATTR), emitter_part = part ~= nil, rates = rates, active = active, tint = tint ~= nil and tostring(tint.TintColor) or nil }
