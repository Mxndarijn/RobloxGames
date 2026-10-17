--!strict
--[[
	SoundController (client, FEATURES.Audio, CONTRACT.md §2 Extras)

	One place for UI / gameplay SFX and the ranch ambience. Creates the SoundGroups
	"SFX" and "Music" under SoundService, plays registry sounds through them and
	crossfades a day (birds) / night (crickets) loop from Lighting.ClockTime.
	Settings (mute, SFX / music volume) live in LocalPlayer attributes AudioMuted /
	AudioSfxVolume / AudioMusicVolume: the save schema has no settings field and
	adding one needs a SAVE_VERSION bump, so they last for the session only.

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
	function self.settings()
		return settings()
	end

	function self.play(name: string): boolean
		local id = AudioLogic.resolveSfx(cfg, name)
		if not id then
			return false
		end
		local sound = Instance.new("Sound")
		sound.SoundId = id
		sound.SoundGroup = sfxGroup
		sound.Parent = SoundService
		sound:Play()
		task.delay(5, function()
			sound:Destroy()
		end)
		return true
	end

	-- Ambience: one looped Sound per time of day, volumes faded towards 1 / 0.
	local loops: { [string]: { sound: Sound, level: number } } = {}
	local function loop(key: string, id: string?): { sound: Sound, level: number }?
		if not id then
			return nil
		end
		local l = loops[key]
		if not l then
			local sound = Instance.new("Sound")
			sound.Name = "Ambient_" .. key
			sound.SoundId = id
			sound.Looped = true
			sound.Volume = 0
			sound.SoundGroup = musicGroup
			sound.Parent = SoundService
			l = { sound = sound, level = 0 }
			loops[key] = l
		end
		return l
	end
	local function ambientStep(dt: number)
		local which = AudioLogic.ambientFor(Lighting.ClockTime, cfg, dayNight)
		for _, key in { "day", "night" } do
			local _, id = AudioLogic.ambientFor(if key == "day" then 12 else 0, cfg, dayNight)
			local l = loop(key, id)
			if l then
				l.level = AudioLogic.fadeStep(l.level, if key == which then 1 else 0, dt, cfg.AMBIENT_FADE_SECONDS)
				l.sound.Volume = l.level * cfg.AMBIENT_VOLUME
				if l.level > 0 and not l.sound.IsPlaying then
					l.sound:Play()
				elseif l.level == 0 and l.sound.IsPlaying then
					l.sound:Pause()
				end
			end
		end
	end
	local ambientConn = RunService.Heartbeat:Connect(ambientStep)

	-- Minimal mute toggle (bottom-left corner, small) in the HUD's text style.
	function self.mountToggle(gui: ScreenGui)
		local button = Instance.new("TextButton")
		button.Name = "MuteToggle"
		button.AnchorPoint = Vector2.new(0, 1)
		button.Position = UDim2.new(0, 8, 1, -8)
		button.Size = UDim2.fromOffset(84, 28)
		button.BackgroundColor3 = Color3.fromRGB(30, 30, 40)
		button.BackgroundTransparency = 0.35
		button.TextColor3 = Color3.new(1, 1, 1)
		button.TextSize = 14
		button.Font = Enum.Font.GothamBold
		button.Parent = gui
		local corner = Instance.new("UICorner")
		corner.CornerRadius = UDim.new(0, 8)
		corner.Parent = button
		local function refresh()
			button.Text = if settings().muted then "Sound: off" else "Sound: on"
		end
		player:GetAttributeChangedSignal("AudioMuted"):Connect(refresh)
		refresh()
		button.Activated:Connect(function()
			self.setMuted(not settings().muted)
			self.play("click")
		end)
	end

	function self.destroy()
		ambientConn:Disconnect()
		for _, l in loops do
			l.sound:Destroy()
		end
		if active == self then
			active = nil
		end
	end

	active = self
	return self
end

return SoundController
