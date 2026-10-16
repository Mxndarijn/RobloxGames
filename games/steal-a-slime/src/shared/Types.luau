--!strict
--[[
	Types

	Payload types that cross the network (CONTRACT.md §3–§5). Type-only apart
	from the re-export of the slime genome; loads under Lune.

	All timestamps are server time: `workspace:GetServerTimeNow()` on both
	sides, so the client can compute countdowns without extra remotes.
]]

local Genome = if script then require(script.Parent.Genome) else require("./Genome")

-- The full slimeData shape (= Genome.Slime). Passed to ModelFactory.build.
export type SlimeData = Genome.Slime

-- Return value of every `Request` invoke.
export type RequestResult = { ok: boolean, message: string?, appraisal: Appraisal? }

-- Result of a successful Appraise (shared/Appraise): what was rerolled, before and after.
export type Appraisal = {
	slimeId: string,
	kind: "mutation" | "size",
	cost: number,
	beforeMutation: string,
	afterMutation: string,
	beforeMutations: { string }?, -- every mutation (FEATURES.MutationStacking); beforeMutation is the primary
	afterMutations: { string }?,
	beforeSize: number,
	afterSize: number,
}

export type NotifyKind = "info" | "good" | "bad" | "badge"

export type SlimeView = {
	slime: SlimeData,
	income: number, -- cash/sec incl. rebirth multiplier (0 while stolenBy ~= nil)
	sellPrice: number,
	appraiseCost: number?, -- Appraise price (FEATURES.Appraise); nil when the feature is off
	stolenBy: number?, -- UserId of the player currently carrying it away
}

export type CarryView = {
	slime: SlimeData,
	kind: "wild" | "stolen",
	ownerUserId: number?, -- victim, only when kind == "stolen"
	startedAt: number,
	escapeAt: number?, -- only when kind == "stolen"
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
export type CodesView = { boostMult: number, boostEndsAt: number, redeemed: number }

export type DailyView = { available: boolean, streak: number, amount: number, day: number }

-- Keys are the UI's ShopCatalog item ids. price nil = maxed / owned.
export type ShopView = {
	LockUpgrade: { price: number?, level: number, maxLevel: number },
	SpeedCoil: { price: number?, owned: boolean },
	MysteryEgg: { price: number }?, -- FEATURES.MysteryEgg only
}

-- State.egg: the newest hatch, for the reveal banner (never saved).
export type EggView = {
	enabled: boolean,
	price: number,
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
	done: boolean,
}
export type DexRewardView = { count: number, reward: number, bonus: number, claimed: boolean }
export type BossView = {
	active: boolean, -- the Boss Slime is in the world (wild or carried)
	endsAt: number?, -- server time it expires, when active
}

export type ModifierView = {
	name: string, -- Config.MODIFIERS name; "None" = quiet phase
	label: string,
	luck: number,
	mutation: number,
	endsAt: number?, -- server time the dawn / dusk phase ends
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
	rebirthCost: number,
	canRebirth: boolean,
	rebirthSlime: { id: string, name: string, tier: number, color: { number }, owned: boolean }?, -- v29: species the next rebirth also needs (nil at max)
	padsUnlocked: number,
	padsMax: number,
	nextPadCost: number?, -- nil when every pad is unlocked
	slimes: { SlimeView },
	favoriteId: string?,
	lockUntil: number,
	lockStartedAt: number, -- v16: server time the current lock began (CONTRACT.md §9.3)
	lockCost: number,
	lockDuration: number,
	carrying: CarryView?,
	rain: RainView,
	dex: { string }, -- discovered Genome.dexKey values, sorted
	dexTotal: number,
	daily: DailyView,
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
	dexRewards: { DexRewardView },
	dexBonus: number,
	stats: StatsView,
	boss: BossView,
	modifier: ModifierView, -- FEATURES.CycleModifier
	egg: EggView, -- FEATURES.MysteryEgg
}

export type LeaderboardEntry = { rank: number, userId: number, name: string, value: number }

-- Payload of the `Leaderboard` RemoteEvent.
export type Leaderboard = { stat: "TotalEarned", entries: { LeaderboardEntry } }

return {}
