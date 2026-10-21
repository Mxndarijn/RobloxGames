--!strict
--[[
	BossSlime (pure, contract/boss-event.md)

	Builds the slime the boss event puts in the plaza: a SlimeRoster kind "boss" species with its name, colour and
	tier, at MAX_SIZE. No Roblox APIs.
]]

local Config = if script then require(script.Parent.Config) else require("./Config")
local Genome = if script then require(script.Parent.Genome) else require("./Genome")
local Rng = if script then require(script.Parent.Rng) else require("./Rng")
local SlimeLooks = if script then require(script.Parent.SlimeLooks) else require("./SlimeLooks")
local SlimeRoster = if script then require(script.Parent.SlimeRoster) else require("./SlimeRoster")

type Slime = Genome.Slime

local BossSlime = {}

-- The boss slime of `species` (a SlimeRoster kind "boss" id): its name, colour and tier, MAX_SIZE. Nil for a species that isn't a boss.
function BossSlime.build(rng: Rng.Rng, id: string, species: string): Slime?
	local entry = SlimeRoster.get(species)
	if not entry or entry.kind ~= "boss" then
		return nil
	end
	local slime = Genome.generate(rng, { id = id, tier = entry.tier })
	slime.species = entry.id
	slime.name = entry.name
	local look = SlimeLooks.get(entry.id)
	if look then
		slime.color = { look.color[1], look.color[2], look.color[3] }
	end
	slime.size = Config.MAX_SIZE
	return slime
end

return table.freeze(BossSlime)
