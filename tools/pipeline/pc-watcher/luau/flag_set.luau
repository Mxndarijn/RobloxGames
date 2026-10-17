-- Edit or Server datamodel: sets (ON true) or clears (ON false) the Studio-only ReplicatedStorage attribute
-- PcwFlag_<Name> for each comma-separated flag in %%NAMES%%. src/shared/FeatureOverride reads it as
-- Config.FEATURES.<Name> = true, only when RunService:IsStudio(); a published server ignores it.
local storage = game:GetService("ReplicatedStorage")
local on = %%ON%%
local out = {}
for name in string.gmatch(%%NAMES%%, "[^,]+") do
	storage:SetAttribute("PcwFlag_" .. name, if on then true else nil)
	out[name] = storage:GetAttribute("PcwFlag_" .. name) == true
end
return { studio = game:GetService("RunService"):IsStudio(), flags = out }
