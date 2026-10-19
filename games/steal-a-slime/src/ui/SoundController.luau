--!strict
--[[
	SoundController (client, FEATURES.Audio, CONTRACT.md §2 Extras)

	One place for UI / gameplay SFX and the ranch ambience. Creates the SoundGroups
	"SFX" and "Music" under SoundService, plays registry sounds through them and
	crossfades a day (birds) / night ambience from Lighting.ClockTime; at night an owl call
	plays now and then (one-shot, random gap).
	Settings (mute, SFX / music volume) live in LocalPlayer attributes AudioMuted /
	AudioSfxVolume / AudioMusicVolume. They are saved server-side (save v6 `settings`):
	`load` applies State.settings once on join, the UI sends changes (SetAudioSettings).

	SoundController.play(name) is static: it returns false when no controller is
	active (flag off or not built yet) so callers keep their legacy sound path.
]]

local SoundService = game:GetService("SoundService")

local AudioLogic = require(script.Parent.AudioLogic)

local SoundController = {}

local active: any = nil

function SoundController.play(name: string): boolean
	if active == nil then
		return false
	end
	return active.play(name)
end

function SoundController.new(config: any, player: Player, dayNight: any)
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

	-- Throttled per name (AudioLogic.allowSfx). A throttled play still returns true so callers don't fall
	-- back to their legacy sound path. The Sound goes when it ends, or after SFX_MAX_SECONDS if it never does.
	local sfxState = AudioLogic.newSfxState()
	function self.play(name: string): boolean
		local id = AudioLogic.resolveSfx(cfg, name)
		if not id then
			return false
		end
		if not AudioLogic.allowSfx(sfxState, name, os.clock(), cfg) then
			return true
		end
		local sound = Instance.new("Sound")
		sound.SoundId = id
		sound.SoundGroup = sfxGroup
		sound.Parent = SoundService
		local done = false
		local function finish()
			if not done then
				done = true
				AudioLogic.releaseSfx(sfxState, name)
				sound:Destroy()
			end
		end
		sound.Ended:Once(finish)
		task.delay(cfg.SFX_MAX_SECONDS, finish)
		sound:Play()
		return true
	end

	-- Ambience: a level per time of day faded towards 1 / 0, driving that time's looped bed (when it has an id)
	-- and, at night, the one-shot owl (AudioLogic.oneshotStep). A call that is playing at dawn plays out.
	local levels: { [string]: number } = { day = 0, night = 0 }
	local loops: { [string]: Sound } = {}
	local function loop(key: string, id: string?): Sound?
		if not id then
			return nil
		end
		local sound = loops[key]
		if not sound then
			sound = Instance.new("Sound")
			sound.Name = "Ambient_" .. key
			sound.SoundId = id
			sound.Looped = true
			sound.Volume = 0
			sound.SoundGroup = musicGroup
			sound.Parent = SoundService
			loops[key] = sound
		end
		return sound
	end
	local rng = Random.new()
	local function roll(): number
		return rng:NextNumber()
	end
	local oneshotId = AudioLogic.oneshotId(cfg)
	local oneshot: Sound? = nil
	if oneshotId then
		local sound = Instance.new("Sound")
		sound.Name = "Ambient_night_oneshot"
		sound.SoundId = oneshotId
		sound.Volume = cfg.NIGHT_ONESHOT_VOLUME
		sound.SoundGroup = musicGroup
		sound.Parent = SoundService
		oneshot = sound
	end
	local oneshotTimer: number? = nil
	local function ambientStep(dt: number)
		local which = AudioLogic.ambientFor(Lighting.ClockTime, cfg, dayNight)
		for _, key in { "day", "night" } do
			local level = AudioLogic.fadeStep(levels[key], if key == which then 1 else 0, dt, cfg.AMBIENT_FADE_SECONDS)
			levels[key] = level
			local _, id = AudioLogic.ambientFor(if key == "day" then 12 else 0, cfg, dayNight)
			local sound = loop(key, id)
			if sound then
				sound.Volume = level * cfg.AMBIENT_VOLUME
				if level > 0 and not sound.IsPlaying then
					sound:Play()
				elseif level == 0 and sound.IsPlaying then
					sound:Pause()
				end
			end
		end
		if oneshot then
			local fire
			oneshotTimer, fire = AudioLogic.oneshotStep(oneshotTimer, dt, levels.night, cfg, roll)
			if fire and not oneshot.IsPlaying then
				oneshot.PlaybackSpeed = AudioLogic.oneshotSpeed(cfg, roll)
				oneshot.TimePosition = 0
				oneshot:Play()
			end
		end
	end
	local ambientConn = RunService.Heartbeat:Connect(ambientStep)

	function self.destroy()
		ambientConn:Disconnect()
		for _, sound in loops do
			sound:Destroy()
		end
		if oneshot then
			oneshot:Destroy()
		end
		if active == self then
			active = nil
		end
	end

	active = self
	return self
end

return SoundController
