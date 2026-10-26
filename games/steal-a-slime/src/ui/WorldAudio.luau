--!strict
--[[
	WorldAudio (client, FEATURES.Audio)

	World sounds from replicated attributes; the rules and timings are in ui/WorldAudioLogic. It watches:
	  * the Boss Slime model (Boss = true): its BossMove (the windup, each stomp and landing), BossSpits (a goo
	    splat where each spit lands), BossRunes (a slam where each rune bursts) and BossHitAt (a squish per bat hit)
	  * Mystery Egg hatch shows: HatchedAt on an egg model (a wobble per rock, the crack), then the hatched slime (the
	    pop), at the egg
	  * the ritual circle (Map.RitualCircle): a spot taken, the ritual done, and a looped hum at the orb while it
	    charges, fading in and out
	  * a looped water bed at the plaza fountain (Map.Volcano.Pool)
	One-shots go through SoundController (SFX group), 3D at the spot; ones farther than WORLD.CULL_DISTANCE from the
	camera are skipped. The looped beds are 3D Sounds in the Music group, so the Music slider covers them.

	  local stop, tick = WorldAudio.start(ctx)    tick(now) from the client's 10 Hz loop, `now` = server time
]]

local CollectionService = game:GetService("CollectionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local SoundService = game:GetService("SoundService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local BossAttacks = require(Shared:WaitForChild("BossAttacks"))
local BossChoreo = require(Shared:WaitForChild("BossChoreo"))
local Config = require(Shared:WaitForChild("Config"))
local Constants = require(Shared:WaitForChild("Constants"))

local AudioLogic = require(script.Parent.AudioLogic)
local SoundController = require(script.Parent.SoundController)
local WorldAudioLogic = require(script.Parent.WorldAudioLogic)

local WorldAudio = {}

WorldAudio.RITUAL_NAME = "RitualCircle"
WorldAudio.FOUNTAIN_NAME = "Volcano"
WorldAudio.FOUNTAIN_PARTS = table.freeze({ "Pool", "BasinRim" }) -- the first one found hosts the water

type PlayOptions = SoundController.PlayOptions

export type Context = {
	play: ((name: string, opts: PlayOptions?) -> boolean)?, -- default SoundController.play
	playVariant: ((group: string, opts: PlayOptions?) -> boolean)?, -- default SoundController.playVariant
	config: any?, -- default Config
}

-- Where a timed cue plays: at a part (it follows it) or a fixed point, heard within `range` studs.
type Host = { part: BasePart?, pos: Vector3, range: number, variant: boolean? }

local function musicGroup(): SoundGroup
	local g = SoundService:FindFirstChild("Music")
	if g and g:IsA("SoundGroup") then
		return g
	end
	local made = Instance.new("SoundGroup")
	made.Name = "Music"
	made.Parent = SoundService
	return made
end

local function loop(name: string, id: string, parent: Instance, minDistance: number, maxDistance: number): Sound
	local s = Instance.new("Sound")
	s.Name = name
	s.SoundId = id
	s.Looped = true
	s.Volume = 0
	s.RollOffMode = Enum.RollOffMode.InverseTapered
	s.RollOffMinDistance = minDistance
	s.RollOffMaxDistance = maxDistance
	s.SoundGroup = musicGroup()
	s.Parent = parent
	return s
end

local function bodyOf(model: Model): BasePart?
	local p = model.PrimaryPart or model:FindFirstChild("Body")
	return if p and p:IsA("BasePart") then p else nil
end

function WorldAudio.start(ctx: Context?): (() -> (), (now: number) -> ())
	local c: Context = ctx or {}
	local cfg = (c.config or Config).AUDIO.WORLD
	local playFn = c.play or SoundController.play
	local variantFn = c.playVariant or SoundController.playVariant
	local conns: { RBXScriptConnection } = {}
	local watched: { [Instance]: RBXScriptConnection } = {}
	local schedule = WorldAudioLogic.newSchedule()
	local hosts: { [string]: Host } = {}
	local lastLook = -math.huge
	local lastClock = os.clock()

	local function near(pos: Vector3): boolean
		local camera = workspace.CurrentCamera
		return camera == nil or WorldAudioLogic.audible((camera.CFrame.Position - pos).Magnitude, cfg)
	end

	local function play(name: string, host: Host)
		local part = host.part
		local live = part ~= nil and part.Parent ~= nil
		local pos = if live then (part :: BasePart).Position else host.pos
		if not near(pos) then
			return
		end
		local opts: PlayOptions = { at = if live then part else pos, maxDistance = host.range }
		if host.variant then
			variantFn(name, opts)
		else
			playFn(name, opts)
		end
	end

	local function queue(cues: { WorldAudioLogic.Cue }, now: number, host: (cue: WorldAudioLogic.Cue) -> Host)
		for _, cue in cues do
			if hosts[cue.key] == nil and schedule.seen[cue.key] == nil then
				hosts[cue.key] = host(cue)
			end
		end
		WorldAudioLogic.schedule(schedule, cues, now, cfg)
	end

	-- The boss: found by its Boss attribute, re-looked for every FIND_EVERY seconds.
	local boss: Model? = nil
	local seenMove: any, seenSpits: any, seenRunes: any, seenHitAt: any = nil, nil, nil, nil

	local function findBoss(): Model?
		for _, m in CollectionService:GetTagged(Constants.SLIME_TAG) do
			if m:IsA("Model") and m:GetAttribute(Constants.BOSS_ATTRIBUTE) == true and m:IsDescendantOf(workspace) then
				return m
			end
		end
		return nil
	end

	local function bossStep(model: Model, now: number)
		local pivot = model:GetPivot().Position
		local body = bodyOf(model)
		local function atBoss(): Host
			return { part = body, pos = pivot, range = cfg.BOSS_MAX_DISTANCE }
		end
		local function onFloor(cue: WorldAudioLogic.Cue): Host
			if cue.x and cue.z then
				return { pos = Vector3.new(cue.x, pivot.Y, cue.z), range = cfg.BOSS_MAX_DISTANCE }
			end
			return atBoss()
		end
		local moveText = model:GetAttribute(Constants.BOSS_MOVE_ATTRIBUTE)
		if moveText ~= seenMove then
			seenMove = moveText
			local move = BossChoreo.decode(moveText)
			if move then
				local species = model:GetAttribute(Constants.SPECIES_ATTRIBUTE)
				local attack = if type(species) == "string" then BossAttacks.get(species, move.slot) else nil
				queue(WorldAudioLogic.moveCues(move, attack), now, atBoss)
			end
		end
		local spits = model:GetAttribute(Constants.BOSS_SPITS_ATTRIBUTE)
		if spits ~= seenSpits then
			seenSpits = spits
			queue(WorldAudioLogic.spitCues(spits), now, onFloor)
		end
		local runes = model:GetAttribute(Constants.BOSS_RUNES_ATTRIBUTE)
		if runes ~= seenRunes then
			seenRunes = runes
			queue(WorldAudioLogic.runeCues(runes), now, onFloor)
		end
		local hitAt = model:GetAttribute(Constants.BOSS_HIT_AT_ATTRIBUTE)
		if hitAt ~= seenHitAt then
			seenHitAt = hitAt
			if type(hitAt) == "number" and now - hitAt <= cfg.LATE_SECONDS then
				play("BossHit", { part = body, pos = pivot, range = cfg.BOSS_MAX_DISTANCE, variant = true })
			end
		end
	end

	-- Mystery Egg hatch shows: HatchedAt on the egg (the rocks and the crack), then on the hatched slime (the pop).
	local function hatchSeen(model: Model)
		local hatchedAt = model:GetAttribute(Constants.HATCHED_AT_ATTRIBUTE)
		local id = model:GetAttribute("SlimeId")
		if type(hatchedAt) ~= "number" or type(id) ~= "string" then
			return
		end
		local now = workspace:GetServerTimeNow()
		local pos = model:GetPivot().Position
		local function atEgg(): Host
			return { pos = pos, range = cfg.EGG_MAX_DISTANCE }
		end
		if model:GetAttribute(Constants.EGG_KIND_ATTRIBUTE) ~= nil then
			queue(WorldAudioLogic.hatchCues(id, hatchedAt), now, atEgg)
		else
			queue(WorldAudioLogic.popCues(id, hatchedAt, now), now, atEgg)
		end
	end

	local function added(instance: Instance)
		if not instance:IsA("Model") or watched[instance] then
			return
		end
		local model = instance :: Model
		watched[model] = model:GetAttributeChangedSignal(Constants.HATCHED_AT_ATTRIBUTE):Connect(function()
			hatchSeen(model)
		end)
		hatchSeen(model)
	end

	local function removed(instance: Instance)
		local conn = watched[instance]
		if conn then
			conn:Disconnect()
			watched[instance] = nil
		end
	end

	table.insert(conns, CollectionService:GetInstanceAddedSignal(Constants.SLIME_TAG):Connect(added))
	table.insert(conns, CollectionService:GetInstanceRemovedSignal(Constants.SLIME_TAG):Connect(removed))
	for _, model in CollectionService:GetTagged(Constants.SLIME_TAG) do
		added(model)
	end

	-- The ritual circle and its hum.
	type Ritual = { model: Model, orb: BasePart, spots: { BasePart }, hum: Sound?, level: number }
	local ritual: Ritual? = nil
	local ritualLook: WorldAudioLogic.RitualLook? = nil

	local function dropRitual()
		if ritual and ritual.hum then
			ritual.hum:Destroy()
		end
		ritual, ritualLook = nil, nil
	end

	local function findRitual(): Ritual?
		local map = workspace:FindFirstChild(Constants.MAP_FOLDER)
		local model = map and map:FindFirstChild(WorldAudio.RITUAL_NAME)
		if not (model and model:IsA("Model")) then
			return nil
		end
		local orb = model:FindFirstChild("Orb")
		if not (orb and orb:IsA("BasePart")) then
			return nil
		end
		local spots = {}
		local i = 1
		while true do
			local spot = model:FindFirstChild(`Spot_{i}`)
			if not (spot and spot:IsA("BasePart")) then
				break
			end
			table.insert(spots, spot)
			i += 1
		end
		local hum = if WorldAudioLogic.loopId(cfg.RITUAL_HUM_ID)
			then loop("RitualHum", cfg.RITUAL_HUM_ID, orb, cfg.RITUAL_HUM_MIN_DISTANCE, cfg.RITUAL_HUM_MAX_DISTANCE)
			else nil
		return { model = model, orb = orb, spots = spots, hum = hum, level = 0 }
	end

	local function ritualStep(r: Ritual, dt: number)
		local phase = r.model:GetAttribute(Constants.RITUAL_PHASE_ATTRIBUTE)
		local taken = {}
		for i, spot in r.spots do
			taken[i] = spot:GetAttribute(Constants.RITUAL_TAKEN_ATTRIBUTE) == true
		end
		local look: WorldAudioLogic.RitualLook =
			{ phase = if type(phase) == "string" then phase else nil, taken = taken }
		for _, cue in WorldAudioLogic.ritualCues(ritualLook, look) do
			local part = if cue.spot then r.spots[cue.spot] else r.orb
			play(cue.name, { part = part, pos = part.Position, range = cfg.RITUAL_MAX_DISTANCE })
		end
		ritualLook = look
		local hum = r.hum
		if hum then
			r.level = AudioLogic.fadeStep(
				r.level,
				if WorldAudioLogic.humOn(look) then 1 else 0,
				dt,
				cfg.RITUAL_HUM_FADE_SECONDS
			)
			hum.Volume = r.level * cfg.RITUAL_HUM_VOLUME
			if r.level > 0 and not hum.IsPlaying then
				hum:Play()
			elseif r.level == 0 and hum.IsPlaying then
				hum:Stop()
			end
		end
	end

	-- The fountain's water bed: plays all the time, 3D rolloff keeps it to the plaza.
	local fountain: Sound? = nil
	local function findFountain()
		if fountain and fountain.Parent then
			return
		end
		if fountain then
			fountain:Destroy()
			fountain = nil
		end
		if not WorldAudioLogic.loopId(cfg.FOUNTAIN_ID) then
			return
		end
		local map = workspace:FindFirstChild(Constants.MAP_FOLDER)
		local model = map and map:FindFirstChild(WorldAudio.FOUNTAIN_NAME)
		if not model then
			return
		end
		for _, name in WorldAudio.FOUNTAIN_PARTS do
			local part = model:FindFirstChild(name)
			if part and part:IsA("BasePart") then
				local s =
					loop("FountainWater", cfg.FOUNTAIN_ID, part, cfg.FOUNTAIN_MIN_DISTANCE, cfg.FOUNTAIN_MAX_DISTANCE)
				s.Volume = cfg.FOUNTAIN_VOLUME
				s:Play()
				fountain = s
				return
			end
		end
	end

	local function tick(now: number)
		local clock = os.clock()
		local dt = math.min(clock - lastClock, 1)
		lastClock = clock
		if clock - lastLook >= cfg.FIND_EVERY then
			lastLook = clock
			if
				not (boss and boss:IsDescendantOf(workspace) and boss:GetAttribute(Constants.BOSS_ATTRIBUTE) == true)
			then
				boss = findBoss()
				local b = boss
				-- What the boss already shows when it is found never cues: only what changes after.
				seenMove = if b then b:GetAttribute(Constants.BOSS_MOVE_ATTRIBUTE) else nil
				seenSpits = if b then b:GetAttribute(Constants.BOSS_SPITS_ATTRIBUTE) else nil
				seenRunes = if b then b:GetAttribute(Constants.BOSS_RUNES_ATTRIBUTE) else nil
				seenHitAt = if b then b:GetAttribute(Constants.BOSS_HIT_AT_ATTRIBUTE) else nil
			end
			if ritual and not ritual.model:IsDescendantOf(workspace) then
				dropRitual()
			end
			if not ritual then
				ritual = findRitual()
			end
			findFountain()
		end
		if boss then
			bossStep(boss, now)
		end
		if ritual then
			ritualStep(ritual, dt)
		end
		for _, cue in WorldAudioLogic.due(schedule, now, cfg) do
			local host = hosts[cue.key]
			if host then
				play(cue.name, host)
			end
		end
		for key in hosts do
			if schedule.seen[key] == nil then
				hosts[key] = nil
			end
		end
	end

	local function stop()
		for _, conn in conns do
			conn:Disconnect()
		end
		for _, conn in watched do
			conn:Disconnect()
		end
		table.clear(watched)
		dropRitual()
		if fountain then
			fountain:Destroy()
			fountain = nil
		end
		boss = nil
	end

	return stop, tick
end

return WorldAudio
