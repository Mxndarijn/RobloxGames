--!strict
--[[
	World (pure)

	Every piece of live server gameplay state in one table: sessions (one per
	loaded player), plot assignment, wild slimes, carries, escapes and the
	Slime Rain clock. The systems (Spawner, Carry, StealService, Income,
	MergeVat, Rebirth, Actions, ...) are plain functions over this table.

	Side effects the Roblox adapter must perform (toasts, escape bounces) are
	queued in `world.outbox`; the adapter drains it. Models are not events:
	the adapter reconciles them from `Scene.describe(world)`.

	No Roblox APIs: runs unchanged under Lune.
]]

local Shared = if script then (game:GetService("ReplicatedStorage") :: any).Shared else nil
local Config = if Shared then require(Shared.Config) else require("../shared/Config")
local BossChoreo = if Shared then require(Shared.BossChoreo) else require("../shared/BossChoreo")
local BossFight = if Shared then require(Shared.BossFight) else require("../shared/BossFight")
local CycleModifier = if Shared then require(Shared.CycleModifier) else require("../shared/CycleModifier")
local Genome = if Shared then require(Shared.Genome) else require("../shared/Genome")
local ParadeLane = if Shared then require(Shared.ParadeLane) else require("../shared/ParadeLane")
local PlayerData = if Shared then require(Shared.PlayerData) else require("../shared/PlayerData")
local Progression = if Shared then require(Shared.Progression) else require("../shared/Progression")
local Rng = if Shared then require(Shared.Rng) else require("../shared/Rng")
local Steal = if Shared then require(Shared.Steal) else require("../shared/Steal")
local StealAlert = if Shared then require(Shared.StealAlert) else require("../shared/StealAlert")
local TutorialProgress = if Shared then require(Shared.TutorialProgress) else require("../shared/TutorialProgress")
local WelcomeBack = if Shared then require(Shared.WelcomeBack) else require("../shared/WelcomeBack")
local Validate = if Shared then require(Shared.Validate) else require("../shared/Validate")
local VatState = if Shared then require(Shared.VatState) else require("../shared/VatState")
local Lib = if script then (game:GetService("ReplicatedStorage") :: any).Lib else nil
local MovementGuard = if Lib
	then require(Lib.anticheat.MovementGuard)
	else require("../../../../shared/luau/src/anticheat/MovementGuard")
local Suspicion = if Lib
	then require(Lib.anticheat.Suspicion)
	else require("../../../../shared/luau/src/anticheat/Suspicion")

type Slime = Genome.Slime

export type CarryKind = "wild" | "stolen"

export type CarryState = {
	slimeId: string,
	kind: CarryKind,
	ownerUserId: number?, -- victim, only for stolen slimes
	timer: Steal.Carry,
	slime: Slime, -- wild: the wild genome; stolen: the entry in the owner's data
	boss: boolean?, -- the hauled boss (contract/boss-event.md): boss carry slow, a slap drops it on the spot
}

-- A lock break (contract/exclusive-shop.md §11): its buyer passes plot `plot`'s locked door until `untilTime`, while
-- `ownerId` still owns that plot.
export type LockBreakPass = { plot: number, ownerId: number, untilTime: number }

export type Session = {
	userId: number,
	name: string,
	plotIndex: number,
	data: PlayerData.Data,
	lockUntil: number,
	lockStartedAt: number, -- when the current lock began (State.lockStartedAt, CONTRACT.md §9.3)
	locked: boolean, -- lock state at the last tick, to push State on expiry
	lockPadSince: number?, -- server time the owner stepped onto their lock pad (LockPad.step); nil = not on it
	limiter: Validate.Limiter,
	carry: CarryState?,
	lastSlapAt: number,
	lastDropAt: number, -- when this player last dropped a slime (Config.DROP_PICKUP_COOLDOWN), runtime only
	incomeRemainder: number,
	dirty: boolean,
	lastPushAt: number,
	stealWaitSince: number?, -- tutorial Steal step: since when no other plot had a slime to steal, runtime only
	friends: number?, -- friends in this server (Friends.refresh), runtime only
	friendIds: { [number]: boolean }?, -- user ids of those friends (Friends.refresh; PlotGuests), runtime only
	blessedUntil: number?, -- when the co-op ritual's Blessed bonus (data.ritualBonus) ends (RitualService), runtime only
	mvpUntil: number?, -- when the Boss Champion boost (data.mvpBonus) ends (BossCredit), runtime only
	egg: { slime: Slime, at: number }?, -- newest Mystery Egg hatch (State.egg, never saved)
	home: boolean?, -- standing in their own HomeZone (the adapter sets it); warms their Mystery Eggs, runtime only
	eggsReady: { [string]: boolean }?, -- Mystery Egg ids whose "ready to hatch" toast went out, runtime only
	cashPadHinted: boolean?, -- FEATURES.CashPads: the "walk over the gold pads" hint went out this session, runtime only
	welcome: WelcomeBack.Report?, -- away time, offline cash and slimes grown, read at join for the welcome card (never saved)
	offlineRate: number?, -- the offline rate the join payout used (Income.applyOffline), runtime only
	offlinePaid: number?, -- the join payout's cash (Income.applyOffline; a pass top-up adds to it), runtime only
	passes: { [string]: boolean }?, -- FEATURES.ExclusiveShop: Game Passes owned, by Config.EXCLUSIVE_SHOP.passes key (PurchaseService), runtime only
	hatchTarget: string?, -- FEATURES.ExclusiveShop: the egg the next HatchNow receipt is for (AimHatch), runtime only
	paidRandomAllowed: boolean?, -- FEATURES.ExclusiveShop: PolicyService allows paid random items; nil = not checked yet (false), runtime only
	lockBreakAim: { plot: number, ownerId: number, at: number }?, -- FEATURES.ExclusiveShop: the locked base the next LockBreak receipt opens (AimLockBreak), runtime only
	lockBreak: LockBreakPass?, -- FEATURES.ExclusiveShop: this player's running lock break (LockBreak), runtime only
	giftAim: { item: string, targetId: number, at: number }?, -- FEATURES.ExclusiveShop: who the next Gift_<item> receipt is for (AimGift), runtime only
	breatherUntil: number?, -- the end of the breather lock SlimeGuard gave this base after a steal (lockUntil equal to it = in the breather), runtime only
	boardRanks: { [string]: number }?, -- my rank per global board stat from the last refresh (-n = deeper than #n, Leaderboard.sessionRanks); runtime only
	coilHeld: boolean?, -- the SpeedCoil Tool is equipped (WorldView sets it each tick); runtime only
	openShop: string?, -- the shop id the player has open (Request OpenShop), runtime only
	awayLog: { StealAlert.Entry }?, -- FEATURES.StealAlerts: the saved thefts read at join, for the join notice (never saved)
	bossStunUntil: number?, -- hit by a boss attack: no bat hits or slaps until then (BossEvent), runtime only
	bossSlow: { factor: number, untilTime: number }?, -- in a boss goo puddle: walk speed x factor until then, runtime only
}

export type Wild = {
	slime: Slime,
	price: number, -- 0 = free drop
	spawnedAt: number,
	expiresAt: number,
	angle: number, -- landing spot around the crater (Fountain.roll)
	radius: number,
	position: any?, -- set when a carrier drops it somewhere else (adapter-defined)
	returning: ParadeLane.Return?, -- FEATURES.Parade: its walk back to the lane after a drop (contract/slime-walk.md)
	boss: boolean?, -- the boss of the boss event (server/BossEvent); never counts in Spawner.wildCount
	move: BossChoreo.Move?, -- the boss: its current move (BossChoreo; model attribute BossMove)
	rare: number?, -- tier, on announced Legendary+ fountain drops (model attribute RareSpawn)
	smashedAt: number?, -- a wild Mystery Egg that was dropped: when it smashed (contract/mystery-egg.md 40.7)
	choreo: { seed: number }?, -- FEATURES.SlimeChoreo: seed of its lane beats (ParadeChoreo); nil once it leaves the lane
}

-- SlimeGuard (CONTRACT.md §41): one player's movement check, suspicion points and where they are.
-- Another player's jar a character is in and since when; `guest` once they were let in there (PlotGuests),
-- `flagged` once they were reported as an intruder there.
export type PlotVisit = { index: number, since: number, guest: boolean?, flagged: boolean? }
export type GuardEntry = {
	track: MovementGuard.Track,
	suspicion: Suspicion.State,
	lastMax: number, -- last tick's allowed flat speed
	carry: { slimeId: string, x: number, z: number, maxSpeed: number }?, -- where the current stolen carry began
	plot: PlotVisit?, -- another player's jar the character is in (SlimeGuard.trackPlot)
	logMinute: number,
	logCount: number,
}
-- A completed steal (SlimeGuard.recordSteal), kept so a kick can undo it.
export type StealRecord = {
	thiefId: number,
	victimId: number,
	slimeId: string,
	name: string,
	at: number,
	undone: boolean,
}
-- Drops since the last Epic+ / Legendary+ (Spawner pity, CONTRACT.md §8.7).
export type Pity = { sinceEpic: number, sinceLegendary: number }

export type Event = {
	type: "Notify" | "Escaped" | "Rain" | "Effect" | "Rare" | "Drained" | "Badge" | "PvpEvent", -- Drained: a lane slime left down the goo drain (FEATURES.Parade)
	userId: number?, -- Notify / PvpEvent target; nil = everyone
	text: string?,
	kind: string?, -- "info" | "good" | "bad"
	sound: string?,
	itemId: string?, -- Notify: ItemIcons registry id the toast is about (client falls back to text matching)
	slimeId: string?,
	ownerUserId: number?,
	carrierUserId: number?,
	reason: string?, -- Escaped: "slap" | "drop" | "left" | "unsaved" | "guard" (SlimeGuard)
	active: boolean?,
	effect: string?, -- Effect: Effects.KINDS name ("Collect" | "Steal" | "Merge" | "Rebirth")
	plotIndex: number?, -- Effect: plot whose MergeVat is the target
	badge: string?, -- Badge: Config.BADGES key just reached (userId = the player)
	tier: number?, -- Rare: the drop's tier (workspace RareSpawn* attributes)
	payload: { [string]: any }?, -- PvpEvent: the remote payload (CONTRACT.md §26.1)
}

-- A spit attack's `burst` (Config.BOSS.MOVES): its puddle bursts into a ring `delay` s after it lands.
export type BossBurst = { delay: number?, radius: number?, speed: number?, push: number? }
export type BossSpit = { x: number, z: number, landAt: number, seconds: number, slow: number, burst: BossBurst? }
export type BossPuddle = {
	x: number,
	z: number,
	untilAt: number,
	slow: number,
	burstAt: number?, -- a rune puddle: server time its ring starts
	burst: BossBurst?,
	struck: { [number]: boolean }, -- players its ring already hit
}

-- The running boss event: the pure fight and the wild boss slime once it has arrived.
export type BossEvent = {
	fight: BossFight.State,
	slimeId: string?,
	lastStepAt: number,
	rng: Rng.Rng, -- the boss's own choices (where it strolls), apart from world.rng
	nextAttackAt: number, -- server time its next attack may wind up (math.huge while one runs)
	attackIndex: number, -- rotation through BossAttacks.available
	struck: { [string]: boolean }, -- "<userId>:<part>" the current attack move already hit (a part: a ring's wave)
	struckMove: number, -- the move number `struck` is for
	targets: { { number } }, -- spit: plaza spots picked at the windup (they land there)
	spits: { BossSpit }, -- spit blobs in the air
	puddles: { BossPuddle }, -- goo puddles on the ground
	guards: { { x: number, z: number, alive: boolean } }, -- the guards of the current rise
	rainAt: number?, -- a guards `rain` attack: server time of its next goo drop volley while it floats
	lastHit: { userId: number, points: number, at: number }?, -- the latest counted bat hit (clients squash it, pop points)
}

export type AdminEvent = {
	def: { id: string, label: string, icon: string },
	endsAt: number,
	modifier: CycleModifier.Modifier,
}

-- A Mystery Egg hatch whose show is playing (contract/mystery-egg.md §40.6), by the hatched slime's id.
export type Hatch = {
	at: number, -- server time of the hatch (model attribute HatchedAt)
	kind: string, -- egg kind id (HatchedFrom)
	lucky: boolean, -- a lucky egg or a full lucky meter (HatchLucky)
	tier: number, -- the hatched slime's tier (HatchTier on the egg model while the show's wobble plays)
	userId: number, -- who hatched it
	text: string, -- the owner's toast, sent at the reveal
	announce: string?, -- the server toast, sent at the reveal (HATCH_ANNOUNCE_TIER+)
	sound: string,
	told: boolean, -- the toasts went out
}

-- A Lucky Charm upgrade whose show is playing (contract/lucky-charm.md), by the slime's id.
export type Lucky = {
	at: number, -- server time of the deposit (model attribute LuckyAt)
	before: Genome.Slime, -- the slime as it was caught (the pad shows it until MORPH_SECONDS)
	userId: number, -- the owner
	text: string, -- the owner's Notify, sent at the morph
	told: boolean, -- the Notify went out
}

export type World = {
	sessions: { [number]: Session },
	plots: { [number]: number }, -- plotIndex -> userId
	plotCount: number,
	wild: { [string]: Wild },
	carriedBy: { [string]: number }, -- slimeId -> carrier userId
	escaping: { [string]: number }, -- slimeId -> time its bounce home ends
	rng: Rng.Rng,
	eggRng: Rng.Rng, -- FEATURES.MysteryEggs rolls, apart from `rng` so the fountain's slime sequence doesn't shift
	lucky: { [string]: Lucky }, -- Lucky Charm shows that are playing, runtime only (LuckyShow.step forgets them)
	shineRng: Rng.Rng, -- shine rolls (Config.SHINES), apart from `rng` for the same reason
	weather: { id: string, changeAt: number }?, -- the live WeatherService state (nil = FEATURES.Weather off: always Clear)
	hatches: { [string]: Hatch }, -- Mystery Egg hatches whose show is playing, runtime only (MysteryEgg.step forgets them)
	newId: () -> string,
	canSave: (userId: number) -> boolean, -- the adapter's save check (World.canSave)
	startedAt: number,
	nextSpawnAt: number,
	slideFreeAt: number, -- FEATURES.Parade: the next free fountain-slide slot (Spawner.slot): drops never stack
	lastSecondAt: number,
	raining: boolean,
	rainForcedUntil: number?, -- seconds since start (Progression.rainStatus)
	nextBossAt: number, -- server time of the next boss arrival (server/BossEvent)
	boss: BossEvent?, -- the running boss event, nil between bosses
	bossIndex: number, -- position in Config.BOSS.ROTATION of the next boss (1-based)
	modifier: CycleModifier.Modifier, -- FEATURES.CycleModifier: active dawn / dusk modifier
	modifierPhase: number, -- DayNight.phase it was rolled for (-1 = not yet)
	modifierEndsAt: number?, -- server time the phase ends
	modifierSeed: number,
	adminEvent: AdminEvent?, -- FEATURES.AdminEvents: overrides `modifier` until endsAt (Spawner.stepModifier)
	potionUntil: number, -- FEATURES.Consumables: server-wide Luck Potion ends at this time (0 = none)
	pity: Pity,
	lastTierAt: { [number]: number }, -- per GUARANTEE_SECONDS rarity: server time of its last drop of at least that rarity
	fountainTier: number, -- FEATURES.FountainTiers: best rank tier seen on this server (FountainTiers), 1 = Meadow, only ever rises
	outbox: { Event },
	guard: { [number]: GuardEntry }, -- SlimeGuard per player, runtime only
	stealLedger: { StealRecord }, -- SlimeGuard: completed steals of the last UNDO_SECONDS, runtime only
	guardMode: ("off" | "watch" | "enforce")?, -- tests: overrides FEATURES.SlimeGuard / SLIME_GUARD.ENFORCE
}

export type Options = {
	now: number,
	seed: number?,
	eggSeed: number?, -- the hatch generator's own seed; nil = derived from `seed` (tests)
	newId: (() -> string)?,
	canSave: ((userId: number) -> boolean)?, -- false while this server can't write that player's save; default: always
	plotCount: number?,
}

local World = {}

World.ESCAPE_BOUNCE_SECONDS = 1.5

function World.new(options: Options): World
	local counter = 0
	local world: World = {
		sessions = {},
		plots = {},
		plotCount = options.plotCount or 8,
		wild = {},
		carriedBy = {},
		escaping = {},
		rng = Rng.new(options.seed or 1),
		eggRng = Rng.new(options.eggSeed or (options.seed or 1) + 7919),
		shineRng = Rng.new((options.seed or 1) + 104729),
		hatches = {},
		lucky = {},
		newId = options.newId or function()
			counter += 1
			return `s{counter}`
		end,
		canSave = options.canSave or function(_userId: number): boolean
			return true
		end,
		startedAt = options.now,
		nextSpawnAt = options.now,
		slideFreeAt = options.now,
		lastSecondAt = options.now,
		raining = false,
		rainForcedUntil = nil,
		nextBossAt = options.now + Config.BOSS.FIRST_AT,
		boss = nil,
		bossIndex = 1,
		modifier = CycleModifier.NONE,
		modifierPhase = -1,
		modifierEndsAt = nil,
		modifierSeed = options.seed or 1,
		adminEvent = nil,
		potionUntil = 0,
		pity = { sinceEpic = 0, sinceLegendary = 0 },
		lastTierAt = {},
		fountainTier = 1,
		outbox = {},
		guard = {},
		stealLedger = {},
		guardMode = nil,
	}
	return world
end

function World.session(world: World, userId: number): Session?
	return world.sessions[userId]
end

--[[
	True when this server saves `userId`'s progress. A read-only session (a save from a newer version) or one
	another server took over keeps its stored record, so a slime moved into or out of it in memory would be
	duplicated or lost: thefts need both players to be saveable.
]]
function World.canSave(world: World, userId: number): boolean
	return world.canSave(userId)
end

function World.markDirty(session: Session?)
	if session then
		session.dirty = true
	end
end

function World.markAllDirty(world: World)
	for _, session in world.sessions do
		session.dirty = true
	end
end

function World.emit(world: World, event: Event)
	table.insert(world.outbox, event)
end

-- Queues a toast for one player (`userId`) or everyone (`nil`).
function World.notify(world: World, userId: number?, text: string, kind: string, sound: string?, itemId: string?)
	World.emit(world, { type = "Notify", userId = userId, text = text, kind = kind, sound = sound, itemId = itemId })
end

-- Queues an Effects.play burst (CONTRACT.md §5.4). The adapter resolves the
-- target: slimeId -> the slime's Body, plotIndex -> MergeVat, else userId's root.
function World.effect(world: World, effect: string, target: { userId: number?, slimeId: string?, plotIndex: number? })
	World.emit(world, {
		type = "Effect",
		effect = effect,
		userId = target.userId,
		slimeId = target.slimeId,
		plotIndex = target.plotIndex,
	})
end

-- Advances the session's tutorial past `step` (TutorialProgress.complete).
function World.tutorial(world: World, session: Session, step: string)
	local changed, finished = TutorialProgress.complete(session.data, step)
	if changed then
		session.dirty = true
	end
	if finished then
		World.notify(world, session.userId, "Tutorial complete! You're a slime tycoon now.", "good", nil)
	end
end

function World.drain(world: World): { Event }
	local events = world.outbox
	world.outbox = {}
	return events
end

-- The lowest free plot, nil when full. Every joining player gets one automatically.
function World.freePlot(world: World): number?
	for index = 1, world.plotCount do
		if world.plots[index] == nil then
			return index
		end
	end
	return nil
end

-- Slimes that can't be merged, sold or stolen right now.
function World.isBusy(world: World, slimeId: string): boolean
	return world.carriedBy[slimeId] ~= nil or world.escaping[slimeId] ~= nil
end

function World.busySet(world: World): { [string]: boolean }
	local set = {}
	for id in world.carriedBy do
		set[id] = true
	end
	for id in world.escaping do
		set[id] = true
	end
	return set
end

-- Ids of slimes that pay nothing right now (being carried away).
function World.carriedSet(world: World): { [string]: boolean }
	local set = {}
	for id in world.carriedBy do
		set[id] = true
	end
	return set
end

-- The slime that follows this player as a pet (Player attribute PetSlimeId): the
-- favourite, or the best slime. A slime a thief is carrying away is skipped, so a
-- stolen pet stops following its owner; it comes back if it escapes home. A Mystery
-- Egg never rides the cloud, not even a favourited one: the best hatched slime does.
function World.pet(world: World, session: Session): Slime?
	local skip = World.carriedSet(world)
	for _, slime in session.data.slimes do
		if slime.egg then
			skip[slime.id] = true
		end
	end
	return Progression.keeper(session.data, skip)
end

-- The session that owns a pad slime, and the slime itself.
function World.ownerOf(world: World, slimeId: string): (Session?, Slime?)
	for _, session in world.sessions do
		local slime = PlayerData.findSlime(session.data, slimeId)
		if slime then
			return session, slime
		end
	end
	return nil, nil
end

-- The slimes that earn nothing right now: carried away by a thief, or brewing in the owner's vat.
function World.incomeSkip(world: World, session: Session): { [string]: boolean }
	local skip = VatState.lockedSet(session.data)
	for id in world.carriedBy do
		skip[id] = true
	end
	return skip
end

function World.incomeOf(world: World, session: Session): number
	return PlayerData.incomePerSecond(session.data, World.incomeSkip(world, session))
end

return World
