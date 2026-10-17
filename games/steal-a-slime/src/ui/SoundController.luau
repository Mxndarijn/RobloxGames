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

	-- Compact settings: a small "Sound" button (bottom-left, HUD text style) opens a panel
	-- with a mute toggle and SFX / Music sliders (5% steps, mouse or touch drag).
	function self.mountToggle(gui: ScreenGui)
		local UserInputService = game:GetService("UserInputService")
		local function style(obj: GuiObject, radius: number)
			obj.BackgroundColor3 = Color3.fromRGB(30, 30, 40)
			obj.BackgroundTransparency = 0.35
			local corner = Instance.new("UICorner")
			corner.CornerRadius = UDim.new(0, radius)
			corner.Parent = obj
		end
		local function label(parent: Instance, text: string, size: UDim2, pos: UDim2, align: Enum.TextXAlignment)
			local l = Instance.new("TextLabel")
			l.BackgroundTransparency = 1
			l.Size = size
			l.Position = pos
			l.Text = text
			l.TextColor3 = Color3.new(1, 1, 1)
			l.TextSize = 13
			l.Font = Enum.Font.GothamBold
			l.TextXAlignment = align
			l.Parent = parent
			return l
		end

		local button = Instance.new("TextButton")
		button.Name = "MuteToggle"
		button.AnchorPoint = Vector2.new(0, 1)
		button.Position = UDim2.new(0, 8, 1, -8)
		button.Size = UDim2.fromOffset(84, 28)
		button.TextColor3 = Color3.new(1, 1, 1)
		button.TextSize = 14
		button.Font = Enum.Font.GothamBold
		button.Parent = gui
		style(button, 8)

		local panel = Instance.new("Frame")
		panel.Name = "SoundPanel"
		panel.AnchorPoint = Vector2.new(0, 1)
		panel.Position = UDim2.new(0, 8, 1, -42)
		panel.Size = UDim2.fromOffset(200, 122)
		panel.Visible = false
		panel.Parent = gui
		style(panel, 8)

		local mute = Instance.new("TextButton")
		mute.Name = "Mute"
		mute.Position = UDim2.fromOffset(8, 8)
		mute.Size = UDim2.new(1, -16, 0, 28)
		mute.TextColor3 = Color3.new(1, 1, 1)
		mute.TextSize = 13
		mute.Font = Enum.Font.GothamBold
		mute.Parent = panel
		style(mute, 6)

		local refreshers: { () -> () } = {}
		local dragging: { [string]: boolean } = {}
		local function slider(kind: "sfx" | "music", title: string, y: number)
			local row = Instance.new("Frame")
			row.Name = title
			row.BackgroundTransparency = 1
			row.Position = UDim2.fromOffset(8, y)
			row.Size = UDim2.new(1, -16, 0, 34)
			row.Parent = panel
			label(row, title, UDim2.new(0.6, 0, 0, 14), UDim2.fromOffset(0, 0), Enum.TextXAlignment.Left)
			local pct = label(row, "", UDim2.new(0.4, 0, 0, 14), UDim2.fromScale(0.6, 0), Enum.TextXAlignment.Right)
			-- Track is 24px tall for fat-finger touch; the visible bar is a thin child.
			local track = Instance.new("TextButton")
			track.Name = "Track"
			track.Text = ""
			track.AutoButtonColor = false
			track.BackgroundTransparency = 1
			track.Position = UDim2.fromOffset(0, 14)
			track.Size = UDim2.new(1, 0, 0, 20)
			track.Parent = row
			local bar = Instance.new("Frame")
			bar.AnchorPoint = Vector2.new(0, 0.5)
			bar.Position = UDim2.fromScale(0, 0.5)
			bar.Size = UDim2.new(1, 0, 0, 6)
			bar.BackgroundColor3 = Color3.fromRGB(70, 70, 90)
			bar.BorderSizePixel = 0
			bar.Parent = track
			local fill = Instance.new("Frame")
			fill.BackgroundColor3 = Color3.fromRGB(110, 210, 140)
			fill.BorderSizePixel = 0
			fill.Size = UDim2.fromScale(0, 1)
			fill.Parent = bar
			for _, f in { bar, fill } do
				local c = Instance.new("UICorner")
				c.CornerRadius = UDim.new(0, 3)
				c.Parent = f
			end
			local function value(): number
				return settings()[kind]
			end
			local function refresh()
				fill.Size = UDim2.fromScale(AudioLogic.volumeToAlpha(value()), 1)
				pct.Text = AudioLogic.percentText(value())
			end
			table.insert(refreshers, refresh)
			local function setFromX(x: number)
				local v = AudioLogic.volumeFromPixel(x, track.AbsolutePosition.X, track.AbsoluteSize.X)
				if v ~= value() then
					self.setVolume(kind, v)
				end
			end
			track.InputBegan:Connect(function(input: InputObject)
				if
					input.UserInputType == Enum.UserInputType.MouseButton1
					or input.UserInputType == Enum.UserInputType.Touch
				then
					dragging[kind] = true
					setFromX(input.Position.X)
				end
			end)
			UserInputService.InputChanged:Connect(function(input: InputObject)
				if
					dragging[kind]
					and (
						input.UserInputType == Enum.UserInputType.MouseMovement
						or input.UserInputType == Enum.UserInputType.Touch
					)
				then
					setFromX(input.Position.X)
				end
			end)
			UserInputService.InputEnded:Connect(function(input: InputObject)
				if
					input.UserInputType == Enum.UserInputType.MouseButton1
					or input.UserInputType == Enum.UserInputType.Touch
				then
					if dragging[kind] then
						dragging[kind] = false
						self.play("click")
					end
				end
			end)
			player
				:GetAttributeChangedSignal(if kind == "sfx" then "AudioSfxVolume" else "AudioMusicVolume")
				:Connect(refresh)
		end
		slider("sfx", "SFX", 44)
		slider("music", "Music / Ambience", 82)

		local function refresh()
			local text = if settings().muted then "Sound: off" else "Sound: on"
			button.Text = text
			mute.Text = if settings().muted then "Unmute" else "Mute all"
			for _, r in refreshers do
				r()
			end
		end
		player:GetAttributeChangedSignal("AudioMuted"):Connect(refresh)
		refresh()
		button.Activated:Connect(function()
			panel.Visible = not panel.Visible
			self.play("click")
		end)
		mute.Activated:Connect(function()
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
