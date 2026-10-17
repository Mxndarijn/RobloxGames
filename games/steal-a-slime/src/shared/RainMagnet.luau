--!strict
--[[
	RainMagnet (FEATURES.RainMagnet, CONTRACT.md §23)

	The Rain Magnet upgrade (Config.UPGRADES "RainMagnet", rank 6, 5 levels x 5 %): when a wild slime the
	player catches reaches their plot while a weather with a mutation is current, it has that chance to
	pick up the weather's mutation (Rain -> Wet, Snow -> Frozen, Starfall -> Galaxy; Config.WEATHER[id]
	.mutation, the same hook Genome.rollMutation reads) on top of whatever it already carries.
	  * The Slime Rain event (world.raining) counts as Rain while no weather mutation is current, so
	    the magnet also works in the old hourly rain.
	  * Server-authoritative and deterministic: one `rng` draw per deposit with a magnet level and a
	    target (none otherwise, so seeds and old players are untouched), no cost, no price change.
	  * The mutation goes through Genome.addMutation (stacking limit, combos such as Sleet / Comet fuse); a
	    slime that already has it, or has no room for it, is left alone.
	Pure: no Roblox APIs.
]]

local Config = if script then require(script.Parent.Config) else require("./Config")
local Genome = if script then require(script.Parent.Genome) else require("./Genome")
local Rng = if script then require(script.Parent.Rng) else require("./Rng")

local RainMagnet = {}

-- The mutation the magnet pulls in: the current weather's, else Wet during the Slime Rain event, else nil.
function RainMagnet.target(weatherId: string, slimeRain: boolean): string?
	local weather = Config.WEATHER[weatherId]
	if weather and weather.mutation and weather.chanceBonus > 0 then
		return weather.mutation
	end
	if slimeRain then
		local rain = Config.WEATHER.Rain
		return if rain then rain.mutation else nil
	end
	return nil
end

-- Tries to attach `target` to `slime` with `chance`. Returns the mutation added, or nil (no target, no
-- chance, no luck, already carried, or no room). Draws from `rng` only when there is a target and a chance.
function RainMagnet.attract(slime: Genome.Slime, target: string?, chance: number, rng: Rng.Rng): string?
	if not target or chance <= 0 then
		return nil
	end
	if rng:float() >= chance then
		return nil
	end
	local list = Genome.mutationList(slime)
	if table.find(list, target) then
		return nil
	end
	local after = Genome.addMutation(list, target)
	-- addMutation hands back the same list when the id is unknown or there is no room under MAX_MUTATIONS.
	local changed = #after ~= #list
	for i, m in after do
		changed = changed or list[i] ~= m
	end
	if not changed then
		return nil
	end
	Genome.setMutations(slime, after)
	return target
end

return table.freeze(RainMagnet)
