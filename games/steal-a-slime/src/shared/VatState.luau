--!strict
--[[
	VatState (pure, CONTRACT.md §21)

	A plot's merge vat, saved as `data.vat`. Players Move up to Config.VAT_SIZE of their own pad slimes of one
	rarity into it. A slime in the vat keeps its pad (the pad shows a see-through copy), so `ids` only names
	which owned slimes are in. Start sets `endsAt` (unix seconds, so a brew runs on while the player is
	offline); Cancel clears it; Collect, once `endsAt` has passed, merges the three (TripleMerge.apply: the
	child takes the first input's pad) and empties the vat.

	  * Waiting (no `endsAt`): the inputs earn as usual and can be stolen or sold; one that leaves the plot
	    leaves the vat too (`prune`).
	  * Brewing (`endsAt` set): the inputs are locked: no income, no stealing, no moving, no selling.

	Every change checks all its rules first and changes nothing when it refuses. Pure: no Roblox APIs.
]]

local Config = if script then require(script.Parent.Config) else require("./Config")
local Genome = if script then require(script.Parent.Genome) else require("./Genome")
local MergeGate = if script then require(script.Parent.MergeGate) else require("./MergeGate")
local PlayerData = if script then require(script.Parent.PlayerData) else require("./PlayerData")
local Rng = if script then require(script.Parent.Rng) else require("./Rng")
local TripleMerge = if script then require(script.Parent.TripleMerge) else require("./TripleMerge")

type Slime = Genome.Slime
type Data = PlayerData.Data

export type Vat = {
	ids: { string }, -- owned slime ids in the vat, in the order they went in (spot 1, 2, 3)
	endsAt: number?, -- unix seconds the brew is done; nil = not brewing
	startedAt: number?, -- unix seconds the brew started (for the progress bar); set with endsAt
}

local VatState = {}

VatState.SIZE = Config.VAT_SIZE

local function setVat(data: Data, vat: Vat?)
	local raw: any = data
	raw.vat = vat
end

local function vatOf(data: Data): Vat?
	local vat = (data :: any).vat
	if type(vat) == "table" and type(vat.ids) == "table" then
		return vat
	end
	return nil
end

local function ensure(data: Data): Vat
	local vat = vatOf(data)
	if vat then
		return vat
	end
	local fresh: Vat = { ids = {} }
	setVat(data, fresh)
	return fresh
end

-- Drops ids that are no longer owned pad slimes (stolen, sold) and an `endsAt` without a full load.
-- Returns whether anything changed. Every read below prunes first, so the vat never names a lost slime.
function VatState.prune(data: Data): boolean
	local vat = vatOf(data)
	if not vat then
		return false
	end
	local changed = false
	local kept: { string } = {}
	local seen: { [string]: boolean } = {}
	for _, id in vat.ids do
		local slime = if type(id) == "string" then PlayerData.findSlime(data, id) else nil
		if slime and slime.pad ~= nil and not seen[id] and #kept < VatState.SIZE then
			seen[id] = true
			table.insert(kept, id)
		else
			changed = true
		end
	end
	if changed then
		vat.ids = kept
	end
	if vat.endsAt ~= nil and (type(vat.endsAt) ~= "number" or #kept < VatState.SIZE) then
		vat.endsAt = nil
		changed = true
	end
	if vat.endsAt == nil then
		vat.startedAt = nil
	end
	if #kept == 0 and vat.endsAt == nil then
		setVat(data, nil)
	end
	return changed
end

-- The ids in the vat (a copy), in spot order.
function VatState.ids(data: Data): { string }
	VatState.prune(data)
	local vat = vatOf(data)
	return if vat then table.clone(vat.ids) else {}
end

-- The slimes in the vat, in spot order.
function VatState.slimes(data: Data): { Slime }
	local out = {}
	for _, id in VatState.ids(data) do
		table.insert(out, (PlayerData.findSlime(data, id)) :: Slime)
	end
	return out
end

function VatState.contains(data: Data, id: string): boolean
	return table.find(VatState.ids(data), id) ~= nil
end

-- The rarity the vat takes (the first slime's), nil while empty.
function VatState.tier(data: Data): number?
	local slimes = VatState.slimes(data)
	return if slimes[1] then slimes[1].tier else nil
end

function VatState.endsAt(data: Data): number?
	VatState.prune(data)
	local vat = vatOf(data)
	return if vat then vat.endsAt else nil
end

function VatState.isBrewing(data: Data): boolean
	return VatState.endsAt(data) ~= nil
end

-- Brewing and the timer has run out.
function VatState.isReady(data: Data, now: number): boolean
	local ends = VatState.endsAt(data)
	return ends ~= nil and now >= ends
end

-- Seconds left on the brew (0 when ready or not brewing).
function VatState.timeLeft(data: Data, now: number): number
	local ends = VatState.endsAt(data)
	return if ends then math.max(0, ends - now) else 0
end

-- Whether slime `id` is locked in a brewing vat: no income, no stealing, no moving, no selling.
function VatState.isLocked(data: Data, id: string): boolean
	return VatState.isBrewing(data) and VatState.contains(data, id)
end

-- The ids locked in a brewing vat, as a set (empty when not brewing).
function VatState.lockedSet(data: Data): { [string]: boolean }
	local out: { [string]: boolean } = {}
	if VatState.isBrewing(data) then
		for _, id in VatState.ids(data) do
			out[id] = true
		end
	end
	return out
end

-- What State.vat carries (Types.VatView): the ids in spot order, the rarity, the brew window and the time one
-- brew would take now (with `factor`).
function VatState.view(data: Data, factor: number?): { [string]: any }
	local ids = VatState.ids(data)
	local vat = vatOf(data)
	local tier = VatState.tier(data)
	return {
		ids = ids,
		tier = tier,
		endsAt = if vat then vat.endsAt else nil,
		startedAt = if vat then vat.startedAt else nil,
		seconds = if tier then VatState.brewSeconds(tier, factor) else nil,
	}
end

-- Seconds one brew of `tier` takes with `factor` (Perks.brewFactor; 1 = full time). At least 1 second.
function VatState.brewSeconds(tier: number, factor: number?): number
	local list = Config.MERGE_BREW_SECONDS
	local base = list[math.clamp(tier, 1, #list)]
	return math.max(1, math.floor(base * (factor or 1) + 0.5))
end

-- The add rules on a vat load (`ids`, its rarity, brewing or not) for `slime`: the server checks a save with
-- `canAdd`, Move mode checks State.vat with this. Returns (ok, player-facing reason).
function VatState.checkLoad(ids: { string }, tier: number?, brewing: boolean, slime: Slime): (boolean, string?)
	if slime.egg then
		return false, "Eggs can't go in the vat"
	end
	if table.find(ids, slime.id) then
		return false, "Already in the vat"
	end
	if brewing then
		return false, "The vat is brewing"
	end
	if #ids >= VatState.SIZE then
		return false, "The vat is full"
	end
	if tier and slime.tier ~= tier then
		return false, `The vat takes {Genome.rarity(tier).name} slimes`
	end
	return true, nil
end

-- Whether `slime` can go into the vat now; a player-facing reason when not.
function VatState.canAdd(data: Data, slime: Slime?): (boolean, string?)
	if not slime or slime.pad == nil or PlayerData.findSlime(data, slime.id) == nil then
		return false, "not your slime"
	end
	return VatState.checkLoad(VatState.ids(data), VatState.tier(data), VatState.isBrewing(data), slime)
end

-- Puts owned slime `id` into the next free spot. Returns (ok, reason).
function VatState.add(data: Data, id: string): (boolean, string?)
	local slime = PlayerData.findSlime(data, id)
	local ok, reason = VatState.canAdd(data, slime)
	if not ok then
		return false, reason
	end
	table.insert(ensure(data).ids, id)
	return true, nil
end

-- Takes slime `id` out (it stays on its own pad). Not while brewing.
function VatState.remove(data: Data, id: string): (boolean, string?)
	local ids = VatState.ids(data)
	local index = table.find(ids, id)
	if not index then
		return false, "not in the vat"
	end
	if VatState.isBrewing(data) then
		return false, "Cancel the brew first"
	end
	local vat = ensure(data)
	table.remove(vat.ids, index)
	VatState.prune(data)
	return true, nil
end

-- What Start would say while the vat is not full ("Add 1 more Common"), nil when it can start.
function VatState.missingText(data: Data): string?
	local ids = VatState.ids(data)
	if #ids >= VatState.SIZE then
		return nil
	end
	local tier = VatState.tier(data)
	local missing = VatState.SIZE - #ids
	if not tier then
		return `Add {missing} slimes of one rarity`
	end
	return `Add {missing} more {Genome.rarity(tier).name}`
end

-- The lock on the vat's load: MergeGate.lockText when the player's rank can't merge its rarity yet, else nil.
-- Loading ignores it; only Start refuses (contract/merge-vat.md §21.9).
function VatState.gateText(data: Data): string?
	local tier = VatState.tier(data)
	if tier and not MergeGate.allows(tier, data.rebirths) then
		return MergeGate.lockText(tier)
	end
	return nil
end

-- Starts the brew: `endsAt = now + brewSeconds(tier, factor)`. Returns (ok, reason).
function VatState.start(data: Data, now: number, factor: number?): (boolean, string?)
	if VatState.isBrewing(data) then
		return false, "already brewing"
	end
	local missing = VatState.missingText(data)
	if missing then
		return false, missing
	end
	local slimes = VatState.slimes(data)
	local ok, reason = TripleMerge.canMerge(slimes)
	if not ok then
		return false, reason
	end
	local gate = VatState.gateText(data)
	if gate then
		return false, gate
	end
	local vat = ensure(data)
	vat.startedAt = now
	vat.endsAt = now + VatState.brewSeconds(slimes[1].tier, factor)
	return true, nil
end

-- Stops the brew; the slimes stay in the vat.
function VatState.cancel(data: Data): (boolean, string?)
	if not VatState.isBrewing(data) then
		return false, "not brewing"
	end
	local vat = ensure(data)
	vat.endsAt, vat.startedAt = nil, nil
	return true, nil
end

-- Merges a finished brew (TripleMerge.apply; the child takes the first input's pad) and empties the vat.
-- Returns (ok, childOrReason).
function VatState.collect(
	data: Data,
	now: number,
	rng: Rng.Rng,
	newId: string,
	busy: { [string]: boolean }?
): (boolean, Slime | string)
	if not VatState.isBrewing(data) then
		return false, "not brewing"
	end
	if not VatState.isReady(data, now) then
		return false, "still brewing"
	end
	local ok, result = TripleMerge.apply(data, VatState.ids(data), busy, rng, newId)
	if not ok then
		return false, result
	end
	setVat(data, nil)
	return true, result
end

-- Cleans a loaded `vat` table (SaveData.deserialize): ids as strings, endsAt as a number. Returns nil for junk.
function VatState.sanitize(raw: any): Vat?
	if type(raw) ~= "table" or type(raw.ids) ~= "table" then
		return nil
	end
	local ids: { string } = {}
	for _, id in raw.ids do
		if type(id) == "string" and #ids < VatState.SIZE then
			table.insert(ids, id)
		end
	end
	if #ids == 0 then
		return nil
	end
	local function time(v: any): number?
		return if type(v) == "number" and v == v and v > 0 and v < 1e11 then v else nil
	end
	local endsAt = time(raw.endsAt)
	local startedAt = if endsAt then time(raw.startedAt) or endsAt else nil
	return { ids = ids, endsAt = endsAt, startedAt = startedAt }
end

return table.freeze(VatState)
