--!strict
--[[
	PlayerData

	The authoritative per-player state the server keeps in memory and saves,
	plus pure plot operations on it (pads, adding / removing slimes, buying
	pads, selling, favourites, SlimeDex). No Roblox APIs.
]]

local Config = if script then require(script.Parent.Config) else require("./Config")
local AudioSettings = if script then require(script.Parent.AudioSettings) else require("./AudioSettings")
local Economy = if script then require(script.Parent.Economy) else require("./Economy")
local Genome = if script then require(script.Parent.Genome) else require("./Genome")
local Perks = if script then require(script.Parent.Perks) else require("./Perks")
local SpeciesDex = if script then require(script.Parent.SpeciesDex) else require("./SpeciesDex")
local StealAlert = if script then require(script.Parent.StealAlert) else require("./StealAlert")

type Slime = Genome.Slime

export type Daily = { lastDay: number, streak: number }

-- Daily quests (Quests): the UTC day they were rolled for and the rolled slots.
export type QuestSlot = { id: string, target: number, base: number, claimed: boolean }
export type DailyQuests = { day: number, slots: { QuestSlot } }

-- Counters for goals (CONTRACT.md §8.8); stolen / earned / rebirths / pads live elsewhere.
export type Stats = { caught: number, merges: number, locks: number, sold: number }

-- Purchases of Consumables in restock `slot` (a new slot resets `bought`), and the stack held per item id
-- (`held`: bought, not used yet; it survives the restock).
export type Consumables = { slot: number, bought: { [string]: number }, held: { [string]: number } }

-- FEATURES.PvP purchases: best owned tier per line (Knockback / Trap / Blaster), owned fun item ids, play seconds
-- counted towards the new-player shield (capped at Config.PVP.NEW_PLAYER_SHIELD_SECONDS).
export type Pvp = { tiers: { [string]: number }, fun: { [string]: boolean }, played: number }

export type Data = {
	version: number,
	cash: number,
	rebirths: number,
	padsUnlocked: number,
	slimes: { Slime },
	favoriteId: string?,
	lastOnline: number, -- unix seconds of the last save while playing
	daily: Daily,
	quests: DailyQuests, -- Quests (day 0 = nothing rolled yet)
	found: { [string]: boolean }, -- SlimeDex species found (SpeciesDex, CONTRACT.md §35)
	stamps: { [string]: boolean }, -- SlimeDex stamps "<species>:<Mutation>"
	totalEarned: number,
	totalStolen: number,
	lockLevel: number, -- Shop: lock upgrade level 0..LOCK_UPGRADE_MAX
	speedCoil: boolean, -- Shop: Speed Coil owned
	tutorialStep: number, -- TutorialProgress: 1..#STEPS, 0 = finished
	-- v3 (CONTRACT.md §8.9)
	upgrades: { [string]: number }, -- Config.UPGRADES id -> level
	stats: Stats,
	goals: { [string]: number }, -- Config.GOALS id -> stages paid
	speciesRewards: number, -- Config.DEX_MILESTONES.species paid
	stampRewards: number, -- Config.DEX_MILESTONES.stamps paid
	plotSkin: string, -- equipped Config.PLOT_SKINS id (PlotSkins; "classic" = default)
	-- Redeem codes (Codes, CONTRACT.md §10)
	redeemed: { [string]: boolean }, -- normalized codes already used
	boostMult: number, -- active income boost (1 = none)
	weekendMult: number?, -- runtime only (never saved): x2 Weekend multiplier set by Income.step, nil = none
	friendBonus: number?, -- runtime only (never saved): friends in this server, FriendBonus.bonus; nil = none
	ritualBonus: number?, -- runtime only (never saved): "Blessed" income bonus from the co-op ritual; nil = none
	boostUntil: number, -- unix seconds the boost ends (0 = none)
	stealLog: { StealAlert.Entry }, -- FEATURES.StealAlerts: thefts of my slimes since the last join, capped (StealAlert.record)
	settings: AudioSettings.Settings, -- Sound card values (save v6; used only with FEATURES.Audio)
	consumables: Consumables, -- restocking shop purchases (added without a version bump)
	pvp: Pvp, -- FEATURES.PvP owned items (PvpRules, CONTRACT.md §26; added without a version bump)
	trophies: { Slime }, -- boss trophies, one per boss species (contract/boss-event.md; added without a version bump)
}

local PlayerData = {}

function PlayerData.new(): Data
	return {
		version = Config.SAVE_VERSION,
		cash = Config.STARTING_CASH,
		rebirths = 0,
		padsUnlocked = Config.PADS_START,
		slimes = {},
		favoriteId = nil,
		lastOnline = 0,
		daily = { lastDay = 0, streak = 0 },
		quests = { day = 0, slots = {} },
		found = {},
		stamps = {},
		totalEarned = 0,
		totalStolen = 0,
		lockLevel = 0,
		speedCoil = false,
		tutorialStep = 1,
		upgrades = {},
		stats = { caught = 0, merges = 0, locks = 0, sold = 0 },
		goals = {},
		speciesRewards = 0,
		stampRewards = 0,
		plotSkin = Config.PLOT_SKIN_DEFAULT,
		redeemed = {},
		boostMult = 1,
		boostUntil = 0,
		stealLog = {},
		settings = AudioSettings.defaults(),
		consumables = { slot = 0, bought = {}, held = {} },
		pvp = { tiers = {}, fun = {}, played = 0 },
		trophies = {},
	}
end

function PlayerData.findSlime(data: Data, id: string): (Slime?, number?)
	for i, slime in data.slimes do
		if slime.id == id then
			return slime, i
		end
	end
	return nil, nil
end

function PlayerData.slimeOnPad(data: Data, pad: number): Slime?
	for _, slime in data.slimes do
		if slime.pad == pad then
			return slime
		end
	end
	return nil
end

-- Lowest unlocked pad with no slime on it, or nil if the plot is full.
function PlayerData.freePad(data: Data): number?
	local used = {}
	for _, slime in data.slimes do
		if slime.pad then
			used[slime.pad] = true
		end
	end
	for pad = 1, data.padsUnlocked do
		if not used[pad] then
			return pad
		end
	end
	return nil
end

-- Records the slime in the SlimeDex (species found + mutation stamp). Every way of getting a slime runs this
-- (addSlime does). Returns whether the species is new.
function PlayerData.discover(data: Data, slime: Slime): boolean
	return SpeciesDex.record(data, slime)
end

-- SlimeDex entries found (of SpeciesDex.TOTAL).
function PlayerData.dexCount(data: Data): number
	return SpeciesDex.count(data)
end

-- Puts a slime on a free pad (or `pad` if given and free). Returns the pad.
function PlayerData.addSlime(data: Data, slime: Slime, pad: number?): (boolean, number? | string)
	if PlayerData.findSlime(data, slime.id) then
		return false, "duplicate"
	end
	local target = pad
	if target then
		if target < 1 or target > data.padsUnlocked or PlayerData.slimeOnPad(data, target) then
			return false, "pad taken"
		end
	else
		target = PlayerData.freePad(data)
	end
	if not target then
		return false, "plot full"
	end
	slime.pad = target
	table.insert(data.slimes, slime)
	PlayerData.discover(data, slime)
	return true, target
end

function PlayerData.removeSlime(data: Data, id: string): Slime?
	local slime, index = PlayerData.findSlime(data, id)
	if not slime or not index then
		return nil
	end
	table.remove(data.slimes, index)
	if data.favoriteId == id then
		data.favoriteId = nil
	end
	return slime
end

-- Plot income incl. rebirth, upgrade, rank and SlimeDex bonuses (Perks.incomeMultiplier).
-- Pad slimes (minus `skip`, the ones being carried) plus boss trophies, which always earn.
function PlayerData.incomePerSecond(data: Data, skip: { [string]: boolean }?): number
	local base = Economy.plotIncome(data.slimes, data.rebirths, skip) + Economy.plotIncome(data.trophies, data.rebirths)
	return base * Perks.bonusMultiplier(data)
end

-- One slime's income for this player (State SlimeView.income).
function PlayerData.slimeIncome(data: Data, slime: Slime): number
	return Economy.slimeIncome(slime, data.rebirths) * Perks.bonusMultiplier(data)
end

function PlayerData.earn(data: Data, amount: number)
	if amount > 0 then
		data.cash += amount
		data.totalEarned += amount
	end
end

function PlayerData.spend(data: Data, amount: number): boolean
	if amount < 0 or data.cash < amount then
		return false
	end
	data.cash -= amount
	return true
end

function PlayerData.buyPad(data: Data): (boolean, string?)
	local cost = Economy.padCost(data.padsUnlocked)
	if not cost then
		return false, "all pads unlocked"
	end
	if not PlayerData.spend(data, cost) then
		return false, "not enough cash"
	end
	data.padsUnlocked += 1
	return true, nil
end

function PlayerData.sell(data: Data, id: string): (boolean, number | string)
	local slime = PlayerData.findSlime(data, id)
	if not slime then
		return false, "not your slime"
	end
	local price = Economy.sellPrice(slime, data.rebirths)
	PlayerData.removeSlime(data, id)
	PlayerData.earn(data, price)
	data.stats.sold += 1
	return true, price
end

function PlayerData.setFavorite(data: Data, id: string?): boolean
	if id == nil then
		data.favoriteId = nil
		return true
	end
	if not PlayerData.findSlime(data, id) then
		return false
	end
	data.favoriteId = id
	return true
end

return PlayerData
