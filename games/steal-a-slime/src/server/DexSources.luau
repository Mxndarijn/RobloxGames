--!strict
--[[
	DexSources

	What the SlimeDex view (SpeciesDex.view, CONTRACT.md §35.4) reads from other systems: the merge recipe of a
	hybrid (its ingredients and hint line; nil until MergeRecipes is in) and the featured event Secret rotation
	(EventSecrets). Snapshot passes this table.
]]

local Shared = if script then (game:GetService("ReplicatedStorage") :: any).Shared else nil
local EventSecrets = if Shared then require(Shared.EventSecrets) else require("../shared/EventSecrets")
local SpeciesDex = if Shared then require(Shared.SpeciesDex) else require("../shared/SpeciesDex")

local DexSources: SpeciesDex.Sources = {
	recipeFor = function(_hybridId: string): SpeciesDex.Recipe?
		return nil
	end,
	featuredWeek = EventSecrets.featuredWeek,
}

return table.freeze(DexSources)
