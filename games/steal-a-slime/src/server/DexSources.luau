--!strict
--[[
	DexSources

	What the SlimeDex view (SpeciesDex.view, CONTRACT.md §35.4) reads from other systems: the merge recipe of a
	hybrid (its ingredients and hint line) and the featured event Secret rotation. Snapshot passes this table.
]]

local Shared = if script then (game:GetService("ReplicatedStorage") :: any).Shared else nil
local SpeciesDex = if Shared then require(Shared.SpeciesDex) else require("../shared/SpeciesDex")

local DexSources: SpeciesDex.Sources = {
	recipeFor = function(_hybridId: string): SpeciesDex.Recipe?
		return nil
	end,
	featuredWeek = function(_id: string, _now: number): number?
		return nil
	end,
}

return table.freeze(DexSources)
