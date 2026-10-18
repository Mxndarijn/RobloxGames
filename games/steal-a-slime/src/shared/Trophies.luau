--!strict
--[[
	Trophies (pure, contract/boss-event.md)

	Boss slimes and the trophy stand in `data.trophies`: one trophy per boss species. A trophy earns income
	(PlayerData.incomePerSecond) but is not in `data.slimes`, so it can't be stolen, merged, sold or put on a pad.
	Winning a species you already hold keeps the trophy you have. No Roblox APIs.
]]

local Config = if script then require(script.Parent.Config) else require("./Config")
local Genome = if script then require(script.Parent.Genome) else require("./Genome")
local PlayerData = if script then require(script.Parent.PlayerData) else require("./PlayerData")
local Rng = if script then require(script.Parent.Rng) else require("./Rng")
local SlimeLooks = if script then require(script.Parent.SlimeLooks) else require("./SlimeLooks")
local SlimeRoster = if script then require(script.Parent.SlimeRoster) else require("./SlimeRoster")

type Slime = Genome.Slime

local Trophies = {}

-- The boss slime of `species` (a SlimeRoster kind "boss" id): its name, colour and tier, MAX_SIZE. Nil for a species that isn't a boss.
function Trophies.bossSlime(rng: Rng.Rng, id: string, species: string): Slime?
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

-- The trophy of `species` in `data`, or nil.
function Trophies.find(data: PlayerData.Data, species: string): Slime?
	for _, trophy in data.trophies do
		if trophy.species == species then
			return trophy
		end
	end
	return nil
end

--[[
	Puts the won boss `slime` on the stand. Returns ("new", trophy) for a first trophy of its species, or
	("owned", trophy) when the player already has one: that trophy stays and `slime` is discarded.
]]
function Trophies.award(data: PlayerData.Data, slime: Slime): (string, Slime)
	local species = slime.species or ""
	local held = Trophies.find(data, species)
	if held then
		return "owned", held
	end
	slime.pad = nil
	slime.keep = nil
	table.insert(data.trophies, slime)
	PlayerData.discover(data, slime)
	return "new", slime
end

return table.freeze(Trophies)
