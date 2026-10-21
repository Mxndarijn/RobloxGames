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

export type Session = {
	userId: number,
	name: string,
	plotIndex: number,
	data: PlayerData.Data,
	lockUntil: number,
	lockStartedAt: number, -- when the current lock began (State.lockStartedAt, CONTRACT.md §9.3)
	locked: boolean, -- lock state at the last tick, to push State on expiry
	limiter: Validate.Limiter,
	carry: CarryState?,
	lastSlapAt: number,
	incomeRemainder: number,
	dirty: boolean,
	lastPushAt: number,
	stealWaitSince: number?, -- tutorial Steal step: since when no other plot had a slime to steal, runtime only
	friends: number?, -- friends in this server (Friends.refresh), runtime only
	blessedUntil: number?, -- when the co-op ritual's Blessed bonus (data.ritualBonus) ends (RitualService), runtime only
	egg: { slime: Slime, at: number }?, -- newest Mystery Egg hatch (State.egg, never saved)
	home: boolean?, -- standing in their own HomeZone (the adapter sets it); warms their Mystery Eggs, runtime only
	eggsReady: { [string]: boolean }?, -- Mystery Egg ids whose "ready to hatch" toast went out, runtime only
	welcome: WelcomeBack.Report?, -- away time, offline cash and slimes grown, read at join for the welcome card (never saved)
	openShop: string?, -- FEATURES.WorldShops: the shop id the player has open (Request OpenShop), runtime only
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
	boss: boolean?, -- the boss of the boss event (server/BossEvent); never counts toward the wild cap
	move: BossChoreo.Move?, -- the boss: its current move (BossChoreo; model attribute BossMove)
	rare: number?, -- tier, on announced Legendary+ fountain drops (model attribute RareSpawn)
	choreo: { seed: number }?, -- FEATURES.SlimeChoreo: seed of its lane beats (ParadeChoreo); nil once it leaves the lane
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
	reason: string?, -- Escaped: "slap" | "drop" | "left"
	active: boolean?,
	effect: string?, -- Effect: Effects.KINDS name ("Collect" | "Steal" | "Merge" | "Rebirth")
	plotIndex: number?, -- Effect: plot whose MergeVat is the target
	badge: string?, -- Badge: Config.BADGES key just reached (userId = the player)
	tier: number?, -- Rare: the drop's tier (workspace RareSpawn* attributes)
	payload: { [string]: any }?, -- PvpEvent: the remote payload (CONTRACT.md §26.1)
}

-- The running boss event: the pure fight and the wild boss slime once it has arrived.
export type BossEvent = {
	fight: BossFight.State,
	slimeId: string?,
	lastStepAt: number,
	rng: Rng.Rng, -- the boss's own choices (where it strolls), apart from world.rng
	nextAttackAt: number, -- server time its next attack may wind up (math.huge while one runs)
	attackIndex: number, -- rotation through BossAttacks.available
	struck: { [number]: boolean }, -- players the current attack move already hit
	struckMove: number, -- the move number `struck` is for
	targets: { { number } }, -- spit: plaza spots picked at the windup (they land there)
	spits: { { x: number, z: number, landAt: number, seconds: number, slow: number } }, -- spit blobs in the air
	puddles: { { x: number, z: number, untilAt: number, slow: number } }, -- goo puddles on the ground
	guards: { { x: number, z: number, alive: boolean } }, -- the guards of the current rise
	lastHit: { userId: number, points: number, at: number }?, -- the latest counted bat hit (clients squash it, pop points)
	rewarded: boolean, -- the win's victory shower has spilled
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
	userId: number, -- who hatched it
	text: string, -- the owner's toast, sent at the reveal
	announce: string?, -- the server toast, sent at the reveal (HATCH_ANNOUNCE_TIER+)
	sound: string,
	told: boolean, -- the toasts went out
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
	hatches: { [string]: Hatch }, -- Mystery Egg hatches whose show is playing, runtime only (MysteryEgg.step forgets them)
	newId: () -> string,
	startedAt: number,
	nextSpawnAt: number,
	slideFreeAt: number, -- FEATURES.Parade: the next free fountain-slide slot (Spawner.slot): drops never stack
	lastSecondAt: number,
	raining: boolean,
	rainForcedUntil: number?, -- seconds since start (Progression.rainStatus)
	rainWarned: boolean, -- the heads-up for the next rain went out
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
	fountainTier: number, -- FEATURES.FountainTiers: best rank tier seen on this server (FountainTiers), 1 = Meadow, only ever rises
	outbox: { Event },
}

export type Options = {
	now: number,
	seed: number?,
	newId: (() -> string)?,
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
		eggRng = Rng.new((options.seed or 1) + 7919),
		hatches = {},
		newId = options.newId or function()
			counter += 1
			return `s{counter}`
		end,
		startedAt = options.now,
		nextSpawnAt = options.now,
		slideFreeAt = options.now,
		lastSecondAt = options.now,
		raining = false,
		rainForcedUntil = nil,
		rainWarned = false,
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
		fountainTier = 1,
		outbox = {},
	}
	return world
end

function World.session(world: World, userId: number): Session?
	return world.sessions[userId]
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
-- stolen pet stops following its owner; it comes back if it escapes home.
function World.pet(world: World, session: Session): Slime?
	return Progression.keeper(session.data, World.carriedSet(world))
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

function World.incomeOf(world: World, session: Session): number
	return PlayerData.incomePerSecond(session.data, World.carriedSet(world))
end

return World
