--!strict
--[[
	FeatureOverride (pure)

	Studio-only per-run forcing of the default-off Config.FEATURES flags, for the pc-watcher review
	shots (tools/pipeline/pc-watcher, shot field "flags"). In a Studio session a ReplicatedStorage
	attribute PcwFlag_<Name> = true reads as that flag ON. Outside Studio, or for any other flag, the
	shipped table is returned untouched, so a published build can never be flipped by an attribute.
	Only ever turns a flag on; false / missing / other types are ignored.
]]

local FeatureOverride = {}

FeatureOverride.PREFIX = "PcwFlag_"
-- The default-off flags that are review-able; anything else is never overridden.
FeatureOverride.FLAGS = table.freeze({
	"FountainTiers",
	"StealAlerts",
	"WeeklyEvents",
	"PlotSkins",
	"ServerProfiler",
	"Audio",
	"PvP",
})

local allowed: { [string]: boolean } = {}
for _, name in FeatureOverride.FLAGS do
	allowed[name] = true
end

-- `base` itself when not in Studio; else a read-only live view of `base` where PcwFlag_<Name> = true
-- (read through `read`, e.g. ReplicatedStorage:GetAttribute) turns an allowed flag on.
function FeatureOverride.wrap(base: { [string]: any }, isStudio: boolean, read: (string) -> any): { [string]: any }
	if not isStudio then
		return base
	end
	return setmetatable({}, {
		__index = function(_, key: any)
			if allowed[key] and read(FeatureOverride.PREFIX .. key) == true then
				return true
			end
			return base[key]
		end,
		__newindex = function()
			error("Config.FEATURES is read-only")
		end,
		__metatable = "locked",
	}) :: any
end

-- The wrap for the live DataModel; the base table itself under Lune or any non-Roblox host.
function FeatureOverride.install(base: { [string]: any }): { [string]: any }
	local ok, isStudio, storage = pcall(function()
		local game_: any = game
		return game_:GetService("RunService"):IsStudio(), game_:GetService("ReplicatedStorage")
	end)
	if not ok or isStudio ~= true then
		return base
	end
	return FeatureOverride.wrap(base, true, function(name: string)
		return (storage :: any):GetAttribute(name)
	end)
end

return FeatureOverride
