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
local CycleModifier = if Shared then require(Shared.CycleModifier) else require("../shared/CycleModifier")
local Genome = if Shared then require(Shared.Genome) else require("../shared/Genome")
local PlayerData = if Shared then require(Shared.PlayerData) else require("../shared/PlayerData")
local Rng = if Shared then require(Shared.Rng) else require("../shared/Rng")
local Steal = if Shared then require(Shared.Steal) else require("../shared/Steal")
local TutorialProgress = if Shared then require(Shared.TutorialProgress) else require("../shared/TutorialProgress")
local Validate = if Shared then require(Shared.Validate) else require("../shared/Validate")

type Slime = Genome.Slime

export type CarryKind = "wild" | "stolen"

export type CarryState = {
	slimeId: string,
	kind: CarryKind,
	ownerUserId: number?, -- victim, only for stolen slimes
	timer: Steal.Carry,
	slime: Slime, -- wild: the wild genome; stolen: the entry in the owner's data
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
	egg: { slime: Slime, at: number }?, -- newest Mystery Egg hatch for the reveal banner (never saved)
}

export type Wild = {
	slime: Slime,
	price: number, -- 0 = free drop
	spawnedAt: number,
	expiresAt: number,
	angle: number, -- landing spot around the crater (Fountain.roll)
	radius: number,
	position: any?, -- set when a carrier drops it somewhere else (adapter-defined)
	boss: boolean?, -- the Boss Slime (Spawner.spawnBoss)
	rare: number?, -- tier, on announced Legendary+ fountain drops (model attribute RareSpawn)
}

-- Drops since the last Epic+ / Legendary+ (Spawner pity, CONTRACT.md §8.7).
export type Pity = { sinceEpic: number, sinceLegendary: number }

export type Event = {
	type: "Notify" | "Escaped" | "Rain" | "Effect" | "Rare" | "Drained" | "Badge", -- Drained: a lane slime left down the goo drain (FEATURES.Parade)
	userId: number?, -- Notify target; nil = everyone
	text: string?,
	kind: string?, -- "info" | "good" | "bad"
	sound: string?,
	itemId: string?, -- Notify: ItemIcons registry id the toast is about (client falls back to text matching)
	slimeId: string?,
	ownerUserId: number?,
	carrierUserId: number?,
	active: boolean?,
	effect: string?, -- Effect: Effects.KINDS name ("Collect" | "Steal" | "Merge" | "Rebirth")
	plotIndex: number?, -- Effect: plot whose MergeVat is the target
	badge: string?, -- Badge: Config.BADGES key just reached (userId = the player)
	tier: number?, -- Rare: the drop's tier (workspace RareSpawn* attributes)
}

export type AdminEvent = {
	def: { id: string, label: string, icon: string },
	endsAt: number,
	modifier: CycleModifier.Modifier,
}

export type World = {
	sessions: { [number]: Session },
	plots: { [number]: number }, -- plotIndex -> userId
	plotCount: number,
	wild: { [string]: Wild },
	carriedBy: { [string]: number }, -- slimeId -> carrier userId
	escaping: { [string]: number }, -- slimeId -> time its bounce home ends
	revenge: { [number]: { [number]: number } }, -- FEATURES.Revenge: victim userId -> thief userId -> window end (server/Revenge)
	rng: Rng.Rng,
	newId: () -> string,
	startedAt: number,
	nextSpawnAt: number,
	lastSecondAt: number,
	raining: boolean,
	rainForcedUntil: number?, -- seconds since start (Progression.rainStatus)
	rainWarned: boolean, -- the heads-up for the next rain went out
	nextBossAt: number, -- server time of the next Boss Slime (FEATURES.BossSlime)
	bossActive: boolean, -- last Spawner.boss values, so a change pushes State to everyone
	bossEndsAt: number?,
	modifier: CycleModifier.Modifier, -- FEATURES.CycleModifier: active dawn / dusk modifier
	modifierPhase: number, -- DayNight.phase it was rolled for (-1 = not yet)
	modifierEndsAt: number?, -- server time the phase ends
	modifierSeed: number,
	adminEvent: AdminEvent?, -- FEATURES.AdminEvents: overrides `modifier` until endsAt (Spawner.stepModifier)
	pity: Pity,
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
		revenge = {},
		rng = Rng.new(options.seed or 1),
		newId = options.newId or function()
			counter += 1
			return `s{counter}`
		end,
		startedAt = options.now,
		nextSpawnAt = options.now,
		lastSecondAt = options.now,
		raining = false,
		rainForcedUntil = nil,
		rainWarned = false,
		nextBossAt = options.now + Config.BOSS_FIRST_AT,
		bossActive = false,
		bossEndsAt = nil,
		modifier = CycleModifier.NONE,
		modifierPhase = -1,
		modifierEndsAt = nil,
		modifierSeed = options.seed or 1,
		adminEvent = nil,
		pity = { sinceEpic = 0, sinceLegendary = 0 },
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
