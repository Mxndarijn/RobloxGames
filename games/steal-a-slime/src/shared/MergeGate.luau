--!strict
--[[
	MergeGate (pure, contract/merge-vat.md §21.9)

	Which rarities a player may put in the merge vat, by rebirths. Each Config.REBIRTH_TIERS rank that opens a
	rarity carries `merge` (the top input tier it allows); the best reached rank counts. Loading a locked slime
	is fine: only starting the brew and the +2 jump check the gate.
]]

local Config = if script then require(script.Parent.Config) else require("./Config")
local Lib = if script then (game:GetService("ReplicatedStorage") :: any).Lib else nil
local Localize = if Lib then require(Lib.locale.Localize) else require("../../../../shared/luau/src/locale/Localize")

local MergeGate = {}

local function rarityName(tier: number): string
	local rarity = Config.RARITIES[math.clamp(tier, 1, Config.MAX_TIER)]
	return rarity.name
end

-- shared/TaggedText, loaded on first use: it reads the Strings catalog, which reads this module.
local function tagged(): any
	return if script then require(script.Parent.TaggedText) :: any else require("./TaggedText") :: any
end

-- A rarity's name as its data message ("data.rarity.<name>.name"), so it is translated inside a sentence.
local function rarityText(tier: number): Localize.Text
	local name = rarityName(tier)
	return tagged().known(`data.rarity.{name}.name`, name)
end

-- The highest rarity tier a player with `rebirths` may merge (put three of in the vat).
function MergeGate.topTier(rebirths: number): number
	local top = 0
	for _, rank in Config.REBIRTH_TIERS do
		if rank.merge and rebirths >= rank.rebirths and rank.merge > top then
			top = rank.merge
		end
	end
	return top
end

function MergeGate.allows(tier: number, rebirths: number): boolean
	return tier <= MergeGate.topTier(rebirths)
end

-- The rebirth count that opens merges of `tier`; nil if no rank does.
function MergeGate.rebirthsFor(tier: number): number?
	local best: number? = nil
	for _, rank in Config.REBIRTH_TIERS do
		if rank.merge and rank.merge >= tier and (best == nil or rank.rebirths < best) then
			best = rank.rebirths
		end
	end
	return best
end

-- Whether the +2 jump from `fromTier` may roll: the rarity it lands on has to be open as a result.
function MergeGate.jumpAllowed(fromTier: number, rebirths: number): boolean
	return fromTier + 2 <= MergeGate.topTier(rebirths) + 1
end

-- "Rebirth 3 to unlock" (the vat's main button and VatStart's refusal); "Locked" if no rank opens `tier`. As a
-- Localize message: draw it with ui/Text.text.
function MergeGate.lockMessage(tier: number): Localize.Message
	local need = MergeGate.rebirthsFor(tier)
	return if need
		then Localize.msg("world.reason.rebirth_to_unlock", { count = need })
		else Localize.msg("world.reason.locked")
end

-- The English of MergeGate.lockMessage (also VatStart's refusal reason).
function MergeGate.lockText(tier: number): string
	return tagged().english(MergeGate.lockMessage(tier))
end

-- "Epic merges open at Rebirth 3", as a Localize message.
function MergeGate.opensMessage(tier: number): Localize.Message
	local need = MergeGate.rebirthsFor(tier)
	local rarity = rarityText(tier)
	return if need
		then Localize.msg("world.vat.merges_open", { rarity = rarity, count = need })
		else Localize.msg("world.vat.merges_locked", { rarity = rarity })
end

-- The English of MergeGate.opensMessage.
function MergeGate.opensText(tier: number): string
	return tagged().english(MergeGate.opensMessage(tier))
end

-- "Up to Rare": the top rarity a player with `rebirths` may merge, as a Localize message.
function MergeGate.capMessage(rebirths: number): Localize.Message
	local top = MergeGate.topTier(rebirths)
	return if top >= 1
		then Localize.msg("world.vat.up_to", { rarity = rarityText(top) })
		else Localize.msg("world.reason.locked")
end

-- The English of MergeGate.capMessage.
function MergeGate.capText(rebirths: number): string
	return tagged().english(MergeGate.capMessage(rebirths))
end

-- "Epic" for a rank that opens Epic merges; nil for a rank that opens nothing new (or the first rank).
-- The rarity tiers `rank` newly opens for merging, lowest first; nil when it opens none.
function MergeGate.opensAtTiers(rank: Config.RebirthTier): { number }?
	if not rank.merge or rank.rebirths <= 0 then
		return nil
	end
	local before = MergeGate.topTier(rank.rebirths - 1)
	if rank.merge <= before then
		return nil
	end
	local tiers = {}
	for tier = before + 1, math.min(rank.merge, Config.MAX_TIER) do
		table.insert(tiers, tier)
	end
	return tiers
end

function MergeGate.opensAt(rank: Config.RebirthTier): string?
	local tiers = MergeGate.opensAtTiers(rank)
	if tiers == nil then
		return nil
	end
	local names = {}
	for _, tier in tiers do
		table.insert(names, rarityName(tier))
	end
	return table.concat(names, " and ")
end

return table.freeze(MergeGate)
