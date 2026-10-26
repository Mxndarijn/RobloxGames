--!strict
--[[
	SoundController (client, FEATURES.Audio, CONTRACT.md §2 Extras)

	One place for UI / gameplay SFX, the music and the ranch ambience. Creates the SoundGroups
	"SFX" and "Music" under SoundService and plays registry sounds through them. It runs the
	looped layers from AudioLogic.layerTargets: a music track (day, night, or the boss track
	during a boss fight), the day (birds) / night bed and a weather bed (rain, snow wind), each
	crossfaded. At night an owl call plays now and then, during rain a thunder clap.
	One-shots play flat (UI) or as 3D sounds at a point (`opts.at`), throttled per name.
	Settings (mute, SFX / music volume) live in LocalPlayer attributes AudioMuted /
	AudioSfxVolume / AudioMusicVolume. They are saved server-side (save v6 `settings`):
	`load` applies State.settings once on join, the UI sends changes (SetAudioSettings).

	SoundController.play(name, opts?) is static: it returns false when no controller is
	active (flag off or not built yet) so callers keep their legacy sound path.
]]

local SoundService = game:GetService("SoundService")
local TweenService = game:GetService("TweenService")

local AudioLogic = require(script.Parent.AudioLogic)
local Sounds = require(script.Parent.Sounds)

local SoundController = {}

export type PlayOptions = {
	at: (Vector3 | BasePart)?, -- 3D sound at this point / part; nil = flat (UI) sound
	volume: number?, -- scale on top of the SFX group (default 1)
	speed: number?, -- PlaybackSpeed (default 1)
	maxDistance: number?, -- 3D only: heard within this many studs (default AUDIO.SFX_3D_MAX_DISTANCE)
}

-- What the controller reads from the world: the current weather id (nil = no weather beds).
export type Context = { weather: (() -> string?)? }

local active: any = nil

function SoundController.play(name: string, opts: PlayOptions?): boolean
	if active == nil then
		return false
	end
	return active.play(name, opts)
end

function SoundController.playVariant(group: string, opts: PlayOptions?): boolean
	if active == nil then
		return false
	end
	return active.playVariant(group, opts)
end

-- The boss track replaces the day / night music while `on` (State.boss during the fight and the haul).
function SoundController.setBoss(on: boolean)
	if active then
		active.setBoss(on)
	end
end

function SoundController.new(config: any, player: Player, dayNight: any, ctx: Context?)
	local RunService = game:GetService("RunService")
	local Lighting = game:GetService("Lighting")
	local cfg = config.AUDIO
	local self = {}

	local function group(name: string): SoundGroup
		local g = SoundService:FindFirstChild(name)
		if g and g:IsA("SoundGroup") then
			return g
		end
		local created = Instance.new("SoundGroup")
		created.Name = name
		created.Parent = SoundService
		return created
	end
	local sfxGroup, musicGroup = group("SFX"), group("Music")

	local function settings(): AudioLogic.Settings
		return AudioLogic.sanitize({
			muted = player:GetAttribute("AudioMuted"),
			sfx = player:GetAttribute("AudioSfxVolume"),
			music = player:GetAttribute("AudioMusicVolume"),
		}, cfg)
	end
	local function apply()
		local s = settings()
		sfxGroup.Volume = AudioLogic.groupVolume(s, "SFX")
		musicGroup.Volume = AudioLogic.groupVolume(s, "Music")
	end
	for _, attr in { "AudioMuted", "AudioSfxVolume", "AudioMusicVolume" } do
		player:GetAttributeChangedSignal(attr):Connect(apply)
	end
	apply()

	function self.setMuted(muted: boolean)
		player:SetAttribute("AudioMuted", muted)
	end
	function self.setVolume(kind: "sfx" | "music", v: number)
		player:SetAttribute(
			if kind == "sfx" then "AudioSfxVolume" else "AudioMusicVolume",
			AudioLogic.clampVolume(v, 0)
		)
	end
	-- Applies the saved values (State.settings, already clean on the server) to the attributes.
	function self.load(saved: any)
		local s = AudioLogic.sanitize({
			muted = saved.muted,
			sfx = saved.sfxVolume,
			music = saved.musicVolume,
		}, cfg)
		player:SetAttribute("AudioMuted", s.muted)
		player:SetAttribute("AudioSfxVolume", s.sfx)
		player:SetAttribute("AudioMusicVolume", s.music)
	end
	function self.settings()
		return settings()
	end

	local rng = Random.new()
	local function roll(): number
		return rng:NextNumber()
	end

	-- A 3D sound needs a host in the world: the part itself, or a temporary attachment at the point.
	local function host(at: Vector3 | BasePart): (Instance, Instance?)
		if typeof(at) == "Instance" then
			return at, nil
		end
		local a = Instance.new("Attachment")
		a.Name = "SfxAt"
		a.WorldPosition = at :: Vector3
		a.Parent = workspace.Terrain
		return a, a
	end

	-- Throttled per name (AudioLogic.allowSfx). A throttled play still returns true so callers don't fall
	-- back to their legacy sound path. The Sound goes when it ends, or after SFX_MAX_SECONDS if it never does.
	local sfxState = AudioLogic.newSfxState()
	function self.play(name: string, opts: PlayOptions?): boolean
		local id = AudioLogic.resolveSfx(cfg, name)
		if not id then
			return false
		end
		if not AudioLogic.allowSfx(sfxState, name, os.clock(), cfg) then
			return true
		end
		local o: PlayOptions = opts or {}
		for _, extra in Sounds.LAYERS[name] or {} do
			self.play(extra, opts)
		end
		local sound = Instance.new("Sound")
		sound.SoundId = id
		sound.SoundGroup = sfxGroup
		sound.Volume = (o.volume or 1) * (Sounds.VOLUME[name] or 1)
		sound.PlaybackSpeed = (o.speed or 1) * (Sounds.SPEED[name] or 1)
		local temp: Instance? = nil
		if o.at ~= nil then
			sound.RollOffMode = Enum.RollOffMode.InverseTapered
			sound.RollOffMinDistance = cfg.SFX_3D_MIN_DISTANCE
			sound.RollOffMaxDistance = o.maxDistance or cfg.SFX_3D_MAX_DISTANCE
			local parent
			parent, temp = host(o.at)
			sound.Parent = parent
		else
			sound.Parent = SoundService
		end
		local done = false
		local function finish()
			if not done then
				done = true
				AudioLogic.releaseSfx(sfxState, name)
				sound:Destroy()
				if temp then
					temp:Destroy()
				end
			end
		end
		sound.Ended:Once(finish)
		task.delay(cfg.SFX_MAX_SECONDS, finish)
		local trim = Sounds.TRIM[name]
		if trim then
			-- Library files with long tails: fade out over the last SFX_TRIM_FADE seconds of the trim.
			local fade = math.min(cfg.SFX_TRIM_FADE, trim)
			task.delay((trim - fade) / sound.PlaybackSpeed, function()
				if not done then
					TweenService:Create(sound, TweenInfo.new(fade / sound.PlaybackSpeed), { Volume = 0 }):Play()
					task.delay(fade / sound.PlaybackSpeed, finish)
				end
			end)
		end
		sound:Play()
		return true
	end
	-- One of a variant list (Sounds.VARIANTS) with a little pitch variation, so repeats don't sound identical.
	function self.playVariant(groupName: string, opts: PlayOptions?): boolean
		local list = Sounds.VARIANTS[groupName]
		local name = if list then AudioLogic.pick(list, roll) else nil
		local o: PlayOptions = table.clone(opts or {})
		o.speed = (o.speed or 1) * AudioLogic.jitter(1, cfg.SFX_SPEED_JITTER, roll)
		return self.play(name or groupName, o)
	end

	-- Looped layers (AudioLogic.layerTargets): the music track, the day / night bed and a weather bed, each faded
	-- to its target over its own fade time. A layer that fades out pauses, so music resumes where it was.
	local bossOn = false
	function self.setBoss(on: boolean)
		bossOn = on
	end
	type LayerState = { sound: Sound, level: number, volume: number, fade: number }
	local layers: { [string]: LayerState } = {}
	local function layerSound(key: string, id: string): Sound
		local sound = Instance.new("Sound")
		sound.Name = "Layer_" .. key
		sound.SoundId = id
		sound.Looped = true
		sound.Volume = 0
		sound.SoundGroup = musicGroup
		sound.Parent = SoundService
		return sound
	end

	-- Random one-shots over a bed: the owl at night, thunder during rain.
	local function oneshot(name: string, id: string?, volume: number): Sound?
		if not id then
			return nil
		end
		local sound = Instance.new("Sound")
		sound.Name = name
		sound.SoundId = id
		sound.Volume = volume
		sound.SoundGroup = musicGroup
		sound.Parent = SoundService
		return sound
	end
	local owl = oneshot("Ambient_night_oneshot", AudioLogic.oneshotId(cfg), cfg.NIGHT_ONESHOT_VOLUME)
	local thunderIds: { string } = {}
	for _, name in cfg.THUNDER do
		local id = AudioLogic.resolveSfx(cfg, name)
		if id then
			table.insert(thunderIds, id)
		end
	end
	local thunder = oneshot("Ambient_thunder", thunderIds[1], cfg.THUNDER_VOLUME)
	local thunderSpec: AudioLogic.OneshotSpec =
		{ min = cfg.THUNDER_MIN_SECONDS, max = cfg.THUNDER_MAX_SECONDS, minLevel = cfg.NIGHT_ONESHOT_MIN_LEVEL }
	local owlTimer: number? = nil
	local thunderTimer: number? = nil
	local nightLevel = 0

	local function ambientStep(dt: number)
		local weather = if ctx and ctx.weather then ctx.weather() else nil
		local clock = Lighting.ClockTime
		local targets = AudioLogic.layerTargets({ clockTime = clock, boss = bossOn, weather = weather }, cfg, dayNight)
		for key, t in targets do
			if not layers[key] then
				layers[key] = { sound = layerSound(key, t.id), level = 0, volume = t.volume, fade = t.fade }
			end
		end
		for key, layer in layers do
			local t = targets[key]
			if t then
				layer.volume, layer.fade = t.volume, t.fade
			end
			layer.level = AudioLogic.fadeStep(layer.level, if t then 1 else 0, dt, layer.fade)
			local sound = layer.sound
			sound.Volume = layer.level * layer.volume
			if layer.level > 0 and not sound.IsPlaying then
				sound:Resume()
			elseif layer.level == 0 and sound.IsPlaying then
				sound:Pause()
			end
		end
		-- The owl waits for the night to fade in, with or without a night bed.
		nightLevel = AudioLogic.fadeStep(
			nightLevel,
			if AudioLogic.isNight(clock, dayNight) then 1 else 0,
			dt,
			cfg.AMBIENT_FADE_SECONDS
		)
		if owl then
			local fire
			owlTimer, fire = AudioLogic.oneshotStep(owlTimer, dt, nightLevel, cfg, roll)
			if fire and not owl.IsPlaying then
				owl.PlaybackSpeed = AudioLogic.oneshotSpeed(cfg, roll)
				owl.TimePosition = 0
				owl:Play()
			end
		end
		if thunder then
			local rain = layers.weather_Rain
			local fire
			thunderTimer, fire =
				AudioLogic.oneshotStep(thunderTimer, dt, if rain then rain.level else 0, cfg, roll, thunderSpec)
			if fire and not thunder.IsPlaying then
				thunder.SoundId = AudioLogic.pick(thunderIds, roll) or thunderIds[1]
				thunder.PlaybackSpeed = AudioLogic.oneshotSpeed(cfg, roll)
				thunder.TimePosition = 0
				thunder:Play()
			end
		end
	end
	local ambientConn = RunService.Heartbeat:Connect(ambientStep)

	function self.destroy()
		ambientConn:Disconnect()
		for _, layer in layers do
			layer.sound:Destroy()
		end
		for _, sound in { owl, thunder } do
			if sound then
				sound:Destroy()
			end
		end
		if active == self then
			active = nil
		end
	end

	active = self
	return self
end

return SoundController
