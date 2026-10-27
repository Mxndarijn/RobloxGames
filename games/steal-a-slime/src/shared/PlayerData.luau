--!strict
--[[
	PlayerData

	The authoritative per-player state the server keeps in memory and saves,
	plus pure plot operations on it (pads, adding / removing slimes, buying
	pads, selling, favourites, SlimeDex). No Roblox APIs.
]]

local Config = if script then require(script.Parent.Config) else require("./Config")
local AudioSettings = if script then require(script.Parent.AudioSettings) else require("./AudioSettings")
local BossBadges = if script then require(script.Parent.BossBadges) else require("./BossBadges")
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

-- FEATURES.PvP purchases: best owned tier per line (Knockback / Blaster), Goo Trap charges per trap id (at most
-- Config.PVP.TRAP_MAX_HELD each) and owned fun item ids.
export type Pvp = {
	tiers: { [string]: number },
	traps: { [string]: number },
	fun: { [string]: boolean },
}

-- `base` = totalEarned when the save was first seen in Monday-based week `week` (WeeklyEvents.weekIndex); 0 = never.
export type Weekly = { week: number, base: number }

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
	found: { [string]: boolean }, -- SlimeDex species found (SpeciesDex, CONTRACT.md §36)
	totalEarned: number,
	totalStolen: number,
	speedCoil: boolean, -- Shop: Speed Coil owned
	tutorialStep: number, -- TutorialProgress: 1..#STEPS, 0 = finished
	-- v3 (CONTRACT.md §8.9)
	upgrades: { [string]: number }, -- Config.UPGRADES id -> level
	stats: Stats,
	goals: { [string]: number }, -- Config.GOALS id -> stages paid
	speciesRewards: number, -- Config.DEX_MILESTONES.species paid
	plotSkin: string, -- equipped Config.PLOT_SKINS id (PlotSkins; "classic" = default)
	plotBase: string, -- equipped Config.PLOT_BASES id (PlotBases; "jar" = default)
	petSeat: string, -- equipped Config.PET_SEATS id (PetSeats; "cloud" = default; no version bump)
	-- Redeem codes (Codes, CONTRACT.md §10)
	redeemed: { [string]: boolean }, -- normalized codes already used
	boostMult: number, -- active income boost (1 = none)
	weekendMult: number?, -- runtime only (never saved): x2 Weekend multiplier set by Income.step, nil = none
	friendBonus: number?, -- runtime only (never saved): friends in this server, FriendBonus.bonus; nil = none
	ritualBonus: number?, -- runtime only (never saved): "Blessed" income bonus from the co-op ritual; nil = none
	mvpBonus: number?, -- runtime only (never saved): Boss Champion income bonus, also +BOSS.MVP_SPEED walk speed (BossCredit); nil = none
	boostUntil: number, -- unix seconds the boost ends (0 = none)
	stealLog: { StealAlert.Entry }, -- FEATURES.StealAlerts: thefts of my slimes since the last join, capped (StealAlert.record)
	settings: AudioSettings.Settings, -- Sound card values (save v6; used only with FEATURES.Audio)
	allowFriends: boolean?, -- the lock button's friends switch (FEATURES.FriendsInBase): true = friends pass a locked base; nil = off
	consumables: Consumables, -- restocking shop purchases (added without a version bump)
	pvp: Pvp, -- FEATURES.PvP owned items (PvpRules, CONTRACT.md §26; added without a version bump)
	boss: BossBadges.Record, -- boss record and save-only boss badges (BossBadges, contract/boss-event.md)
	hotbar: { string }?, -- HotbarOrder: 9 slot keys, "" = empty; nil until the player sets one (no version bump)
	eggLuck: { [string]: number }?, -- Mystery Egg lucky meter: misses in a row per kind id (contract/mystery-egg.md; no version bump)
	weekly: Weekly, -- Weekly Top Earners: totalEarned at the start of `week` (Leaderboards.rollWeek; no version bump)
	vat: { ids: { string }, endsAt: number?, startedAt: number? }?, -- merge vat load and brew end (VatState, CONTRACT.md §21; no version bump)
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
		totalEarned = 0,
		totalStolen = 0,
		speedCoil = false,
		tutorialStep = 1,
		upgrades = {},
		stats = { caught = 0, merges = 0, locks = 0, sold = 0 },
		goals = {},
		speciesRewards = 0,
		plotSkin = Config.PLOT_SKIN_DEFAULT,
		plotBase = Config.PLOT_BASE_DEFAULT,
		petSeat = Config.PET_SEAT_DEFAULT,
		redeemed = {},
		boostMult = 1,
		boostUntil = 0,
		stealLog = {},
		settings = AudioSettings.defaults(),
		consumables = { slot = 0, bought = {}, held = {} },
		pvp = { tiers = {}, traps = {}, fun = {} },
		boss = BossBadges.new(),
		eggLuck = {},
		weekly = { week = 0, base = 0 },
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

-- Records the slime in the SlimeDex (species found). Every way of getting a slime runs this
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

-- Moves slime `id` to unlocked pad `pad`; a slime already there takes `id`'s old pad (a swap).
function PlayerData.moveSlime(data: Data, id: string, pad: number): (boolean, string?)
	local slime = PlayerData.findSlime(data, id)
	if not slime or slime.pad == nil then
		return false, "not your slime"
	end
	if pad ~= math.floor(pad) or pad < 1 or pad > data.padsUnlocked then
		return false, "pad is locked"
	end
	if slime.pad == pad then
		return true, nil
	end
	local other = PlayerData.slimeOnPad(data, pad)
	if other then
		other.pad = slime.pad
	end
	slime.pad = pad
	return true, nil
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
-- Pad slimes, minus `skip` (the ones being carried).
function PlayerData.incomePerSecond(data: Data, skip: { [string]: boolean }?): number
	return Economy.plotIncome(data.slimes, data.rebirths, skip) * Perks.bonusMultiplier(data)
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
	local need = Economy.padRebirths(data.padsUnlocked) or 0
	if data.rebirths < need then
		return false, `Rebirth {need} to unlock this pad`
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
	local price = Economy.sellPrice(slime)
	if not price then
		return false, "eggs can't be sold"
	end
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
	local slime = PlayerData.findSlime(data, id)
	if not slime or slime.egg then
		return false
	end
	data.favoriteId = id
	return true
end

return PlayerData
