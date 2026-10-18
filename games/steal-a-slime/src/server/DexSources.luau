--!strict
--[[
	DexSources

	What the SlimeDex view (SpeciesDex.view, CONTRACT.md §36.4) reads from other systems: the merge recipe of a
	hybrid (MergeRecipes: its ingredients and hint line) and the featured event Secret rotation (EventSecrets). Snapshot passes this table.
]]

local Shared = if script then (game:GetService("ReplicatedStorage") :: any).Shared else nil
local EventSecrets = if Shared then require(Shared.EventSecrets) else require("../shared/EventSecrets")
local MergeRecipes = if Shared then require(Shared.MergeRecipes) else require("../shared/MergeRecipes")
local SpeciesDex = if Shared then require(Shared.SpeciesDex) else require("../shared/SpeciesDex")

local DexSources: SpeciesDex.Sources = {
	recipeFor = function(hybridId: string): SpeciesDex.Recipe?
		return MergeRecipes.recipeFor(hybridId)
	end,
	featuredWeek = EventSecrets.featuredWeek,
}

return table.freeze(DexSources)
