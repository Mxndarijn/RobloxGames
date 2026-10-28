--!strict
--[[
	Types

	Payload types that cross the network (CONTRACT.md §3–§5). Type-only apart
	from the re-export of the slime genome; loads under Lune.

	All timestamps are server time: `workspace:GetServerTimeNow()` on both
	sides, so the client can compute countdowns without extra remotes.
]]

local Collection = if script then require(script.Parent.Collection) else require("./Collection")
local Genome = if script then require(script.Parent.Genome) else require("./Genome")
local NoticeCards = if script then require(script.Parent.NoticeCards) else require("./NoticeCards")
local PlotBases = if script then require(script.Parent.PlotBases) else require("./PlotBases")
local PetSeats = if script then require(script.Parent.PetSeats) else require("./PetSeats")
local PlotSkins = if script then require(script.Parent.PlotSkins) else require("./PlotSkins")
local SpeciesDex = if script then require(script.Parent.SpeciesDex) else require("./SpeciesDex")

-- The full slimeData shape (= Genome.Slime). Passed to ModelFactory.build.
export type SlimeData = Genome.Slime

-- Return value of every `Request` invoke.
export type RequestResult = { ok: boolean, message: string?, code: string? } -- code: ShopEvent deny code (OpenShop / ShopBuy, CONTRACT.md §27.7)

export type NotifyKind = "info" | "good" | "bad" | "badge"

-- One slime the next rebirth needs (State.rebirthSlimes). A species asked for twice is two rows.
export type RebirthSlimeView = { id: string, name: string, tier: number, color: { number }, owned: boolean }

export type SlimeView = {
	slime: SlimeData,
	income: number, -- cash/sec incl. rebirth multiplier (0 while stolenBy ~= nil)
	sellPrice: number?, -- nil for a Mystery Egg (can't be sold)
	stolenBy: number?, -- UserId of the player currently carrying it away
}

export type CarryView = {
	slime: SlimeData,
	kind: "wild" | "stolen",
	ownerUserId: number?, -- victim, only when kind == "stolen"
	startedAt: number,
	walkSpeed: number, -- current server-applied WalkSpeed
}

export type RainView = {
	active: boolean,
	endsAt: number?, -- when active
	nextAt: number?, -- when not active
}

-- day: the streak day the pending claim pays (1..DAILY_STREAK_CAP); when
-- nothing is pending, the day the last claim paid.
-- Redeem codes (CONTRACT.md §10): the active income boost (1 / 0 = none).
-- Friend income bonus (CONTRACT.md §11): friends in this server and the income bonus they give (0.2 = +20%).
export type FriendsView = { count: number, bonus: number }

-- x2 Weekend (Weekend): the multiplier and when the window ends (unix seconds); absent / inactive = no chip.
export type WeekendView = { active: boolean, multiplier: number, endsAt: number? }
-- The featured event Secret of the week (EventSecrets, CONTRACT.md §34); `endsAt` in server time.
export type FeaturedSecretView = { id: string, name: string, endsAt: number }
-- The co-op ritual's Blessed income bonus (FEATURES.CoopRitual); `endsAt` in server time.
export type BlessedView = { bonus: number, endsAt: number }

-- Follow-pet passive (CONTRACT.md §14): the favourite slime's perk, text "+5% luck".
export type PetPerkView = { kind: string, value: number, icon: string, text: string }

-- Plot skins (CONTRACT.md §15): one skin with its SlimeDex set progress.
export type PlotSkinView = PlotSkins.View
export type PlotBaseView = PlotBases.View
export type PetSeatView = PetSeats.View -- contract/pet-seats.md

export type CodesView = { boostMult: number, boostEndsAt: number, redeemed: number }

export type QuestView = {
	id: string,
	title: string,
	icon: string,
	progress: number,
	target: number,
	done: boolean,
	claimed: boolean,
	reward: string,
	rewardKind: string,
}
export type DailyQuestsView = { day: number, resetsIn: number, quests: { QuestView } }
export type DailyView = { available: boolean, streak: number, amount: number, day: number }

-- Keys are the UI's ShopCatalog item ids. price nil = maxed / owned.
export type ShopView = {
	SpeedCoil: { price: number?, owned: boolean },
}

-- State.pvp (FEATURES.PvP, CONTRACT.md §26.1): nil with the flag off.
export type PvpView = {
	rank: number, -- rebirths
	owned: { [string]: boolean },
	best: { [string]: string }, -- Knockback / Trap / Blaster -> best owned item id
	equipped: string?,
	cooldowns: { [string]: number }, -- item id -> server time it is ready again
	charges: { [string]: number }, -- Goo Trap id -> charges held
}

-- State.consumables (FEATURES.Consumables): this restock's items for this player.
export type ConsumableItemView = {
	id: string,
	name: string,
	icon: string,
	text: string,
	price: number,
	left: number, -- this player may still buy this many until the restock
	max: number, -- the slot's quantity per player
	held: number, -- the stack this player holds (bought, not used yet)
}
export type ConsumablesView = {
	slot: number,
	restockAt: number, -- unix seconds, same clock as State.serverTime
	items: { ConsumableItemView },
	luckUntil: number, -- active server luck potion ends (0 = none)
	luckMult: number, -- the potion's rarity multiplier
	totemWeather: string, -- the weather a Weather Totem calls this restock
	held: { [string]: number }, -- item id -> stack held (every consumable with a stack, shown or not)
}

-- State.egg: the newest Mystery Egg hatch, for the reveal banner (never saved).
export type EggView = {
	hatched: { slime: SlimeData, at: number }?,
}

-- v13 progression views (CONTRACT.md §8.2)
export type RebirthTierView = { rebirths: number, title: string, text: string, unlocked: boolean }
export type NextRebirthTier = { rebirths: number, title: string, text: string }
export type UpgradeView = {
	id: string,
	name: string,
	text: string,
	level: number,
	maxLevel: number,
	price: number?, -- nil = maxed or locked
	requires: number,
	unlocked: boolean,
}
export type GoalView = {
	id: string,
	title: string,
	stat: string,
	progress: number,
	stage: number,
	stages: number,
	target: number?,
	reward: number?,
	nextTitle: string?, -- the step after the current one (nil on the last step)
	done: boolean,
}
-- SlimeDex (CONTRACT.md §36.4): one milestone of the species ladder, and the Dex itself.
export type DexRewardView = Collection.View
export type DexView = SpeciesDex.View
export type DexEntryView = SpeciesDex.EntryView
-- State.boss (contract/boss-event.md)
export type BossView = {
	active: boolean, -- a boss event is on (warning, fight or haul)
	phase: string?, -- "warning" | "fight" | "haul" | "won" | "failed"; nil = no event
	kind: string?, -- boss species id (SlimeRoster)
	name: string?, -- species display name
	tier: number?,
	meter: number, -- 0..1 goo meter (1 from the haul on)
	endsAt: number?, -- server time the current phase ends (warning: the arrival)
	nextAt: number?, -- server time of the next arrival
	yourPoints: number, -- this player's hits on this boss
	yourShare: number, -- yourPoints / the top contributor's points, 0..1
	yourPercent: number?, -- yourPoints / everyone's points, 0..1 (the boss panel's "You 42%")
	carrierName: string?, -- haul: who carries it
	priorityName: string?, -- haul: the top contributor while their head start runs
	priorityUntil: number?,
	winnerName: string?, -- "won": who brought it home
	badges: number, -- boss badges this player has earned
	move: string?, -- fight: the boss's move kind (BossChoreo: "windup", "attack", "dazed", "rise", ...)
	moveEndsAt: number?, -- server time that move ends
	multiplier: number?, -- dazed: meter points per bat hit (more on a vent from behind)
	guardsLeft: number?, -- rise: guards still standing
	guardsTotal: number?, -- rise: guards it called
	stunnedUntil: number?, -- this player can't hit until then (a boss attack got them)
}
-- State.bossBadges: one earned boss badge (Config.BOSS_BADGES key, unix seconds it was earned)
export type BossBadgeView = { key: string, earnedAt: number }

export type ModifierView = {
	name: string, -- Config.MODIFIERS name; "None" = quiet phase
	label: string,
	luck: number,
	endsAt: number?, -- server time the dawn / dusk phase ends (or the admin event)
	icon: string?, -- FEATURES.AdminEvents: emoji of a live admin event, nil for dawn / dusk modifiers
}

export type StatsView = {
	caught: number,
	merges: number,
	locks: number,
	sold: number,
	stolen: number,
	earned: number,
	rebirths: number,
}

-- Payload of the `State` RemoteEvent: always a full snapshot.
export type State = {
	serverTime: number,
	plotIndex: number, -- 1..8, workspace.Plots.Plot_<plotIndex>
	cash: number,
	incomePerSec: number,
	rebirths: number,
	rebirthMultiplier: number,
	nextRebirthMultiplier: number, -- income multiplier after the next rebirth (= rebirthMultiplier at max)
	rebirthCost: number,
	canRebirth: boolean,
	rebirthSlimes: { RebirthSlimeView }, -- the slimes the next rebirth needs and uses up, one row per slime (empty at max)
	padsUnlocked: number,
	padsMax: number,
	nextPadCost: number?, -- nil when every pad is unlocked
	nextPadRebirths: number?, -- rebirths the next pad still needs; nil when it can be bought now or all are open
	slimes: { SlimeView },
	favoriteId: string?,
	lockUntil: number,
	lockStartedAt: number, -- v16: server time the current lock began (CONTRACT.md §9.3)
	lockDuration: number,
	carrying: CarryView?,
	rain: RainView,
	dex: DexView, -- the species Dex: counts, entries (CONTRACT.md §36.4)
	daily: DailyView,
	dailyQuests: DailyQuestsView?, -- Quests.view: nil on a server without daily quests
	codes: CodesView,
	shop: ShopView,
	tutorialStep: number?, -- 1..#TutorialProgress.STEPS; nil = finished
	-- v13 (CONTRACT.md §8.2)
	walkSpeed: number, -- server base WalkSpeed (Speed Coil included); carry.walkSpeed has the carry slowdown applied
	tutorialStepId: string?, -- TutorialProgress.STEPS name; nil = finished
	incomeMultiplier: number, -- rebirth x upgrade x rank x dex
	rebirthTitle: string,
	rebirthTiers: { RebirthTierView },
	nextRebirthTier: NextRebirthTier?,
	upgrades: { UpgradeView },
	goals: { GoalView },
	dexRewards: { DexRewardView }, -- both ladders, species first
	dexBonus: number,
	stats: StatsView,
	boss: BossView,
	bossBadges: { BossBadgeView }, -- earned boss badges, in Config.BOSS_BADGES order (contract/boss-event.md)
	modifier: ModifierView, -- FEATURES.CycleModifier
	egg: EggView,
	consumables: ConsumablesView?, -- FEATURES.Consumables (nil when off)
	pvp: PvpView?, -- FEATURES.PvP (nil when off)
	friends: FriendsView, -- FEATURES.FriendBonus (count 0 / bonus 0 when off)
	blessed: BlessedView?, -- FEATURES.CoopRitual: the ritual's Blessed bonus while it lasts; nil = not blessed
	mvpBoost: BlessedView?, -- the Boss Champion boost (BossCredit, same shape as blessed) while it lasts; nil = none
	weekend: WeekendView?, -- x2 Weekend window (server clock)
	featuredSecret: FeaturedSecretView?, -- this week's event Secret in the Secret pool
	petPerk: PetPerkView?, -- Perks.petPassive; nil without a favourite
	settings: { musicVolume: number, sfxVolume: number, muted: boolean }?, -- FEATURES.Audio: saved Sound card values (nil when off)
	plotSkin: string?, -- FEATURES.PlotSkins: equipped skin id (nil when off)
	plotSkins: { PlotSkinView }?, -- FEATURES.PlotSkins: every skin with its Dex-set progress (nil when off)
	plotBase: string?, -- FEATURES.BaseShapes: equipped base id (nil when off)
	plotBases: { PlotBaseView }?, -- FEATURES.BaseShapes: every base with its rebirth gate (nil when off)
	petSeat: string, -- the seat the follow pet rides (PetSeats.current)
	petSeats: { PetSeatView }, -- every pet seat with its unlock progress (contract/pet-seats.md)
	welcomeBack: { away: number, cash: number, grown: number }?, -- join report (seconds away, offline cash paid, pad slimes grown); nil = none (CONTRACT.md §19)
	notices: { NoticeCards.Notice }, -- live notice cards: bonked, slime back home, base locked (contract/notice-cards.md)
	plotFull: boolean, -- carrying a slime in my own full plot: the carry card asks to sell or merge (contract/notice-cards.md)
	stealAway: string?, -- FEATURES.StealAlerts: "While you were away N slimes were stolen by ..." from the saved steal log; nil = none (CONTRACT.md §17)
	hotbar: { string }?, -- saved hotbar order (HotbarOrder, CONTRACT.md §5.1): 9 slot keys, "" = empty; nil = never set
	boards: { [string]: number }, -- my own value on each global board, by Leaderboards stat (CONTRACT.md §5.1)
	boardRanks: { [string]: number }, -- my rank on each board from the last refresh; -n = deeper than #n; absent = not ranked yet
	vat: VatView, -- the plot's merge vat (VatState, CONTRACT.md §21)
	exclusiveShop: ExclusiveShopView?, -- FEATURES.ExclusiveShop (nil when off; contract/exclusive-shop.md §5)
}

export type ExclusiveShopView = {
	owned: { [string]: boolean }, -- Exclusive seat ids this player owns
	passes: { [string]: boolean }, -- Config.EXCLUSIVE_SHOP.passes keys: owned or not
	starterClaimed: boolean,
	credits: { brew: number, hatch: number }, -- paid skips saved for later
	offlineDouble: { cash: number, available: boolean }?, -- the last welcome-back payout "Double it" can repeat
	paidRandomAllowed: boolean, -- false where paid random items are restricted: hide ServerLuckPotion
	featured: { string }, -- this week's featured Exclusive seat ids (ExclusiveRotation)
	trails: { [string]: boolean }, -- owned carry trail ids
	trail: string?, -- the equipped carry trail id; nil = none
	batSkins: { [string]: boolean }, -- owned Bat skin ids
	batSkin: string?, -- the equipped Bat skin id; nil = the default Bat
	lockBreak: { plot: number, untilTime: number }?, -- an active lock break: the plot index and when it ends
	lockBreakCredits: number, -- paid lock breaks that found no locked base to open (used with UseCredit "lockBreak")
	giftCredits: { string }, -- unsent gifts (cosmetic product keys) to send with SendGift
}

export type VatView = {
	ids: { string }, -- slime ids in the vat, spot order (each also in `slimes`, still on its pad)
	tier: number?, -- the rarity it takes; nil while empty
	endsAt: number?, -- unix seconds the brew is done; nil = not brewing
	startedAt: number?, -- unix seconds the brew started
	seconds: number?, -- how long a brew of `tier` takes now (Quick Brew applied); nil while empty
}

export type LeaderboardEntry = { rank: number, userId: number, name: string, value: number }

-- Which board a payload is for (Leaderboards.BOARDS).
export type LeaderboardStat = "TotalEarned" | "WeeklyEarned" | "Steals" | "Dex" | "Merges"

-- Payload of the `Leaderboard` RemoteEvent: one board per call.
export type Leaderboard = { stat: LeaderboardStat, entries: { LeaderboardEntry } }

return {}
