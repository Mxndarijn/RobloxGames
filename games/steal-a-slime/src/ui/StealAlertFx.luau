--!strict
--[[
	StealAlertFx (client, FEATURES.StealAlerts, CONTRACT.md §17)

	The v21 full steal alerts, drawn on top of the HUD banner:

	* Owner: a red screen-edge flash and repeat alarms when a theft starts, a direction
	  arrow on the screen edge plus a red outline (seen through walls) on the thief while
	  they carry my slime. (The "while you were away" toast from `State.stealAway` is gone
	  with all toasts, B6.)
	* Thief (and everyone watching): a short Trail on any player whose Player attribute
	  `Stealing` is set.
	* Bat hit: a hit effect (flash, "BONK!" pop, burst) on the player whose `SlapHitAt` changes.
	* Thief Radar (contract/exclusive-shop.md §13): the players in my base (State.exclusiveShop.radar) get a calmer
	  yellow outline, and while no theft runs the arrow points at the first of them, labelled "Visitor".

	Only Instances that are not parts: Frames, a BillboardGui (the BONK! pop), Highlights, a Trail with two
	Attachments, a ParticleEmitter. The maths is Shared.StealAlert (tests/StealAlert.spec).
	Studio only: the SlimeUI attribute `PcwStealAlert` = true fakes one theft (flash held at
	its peak, arrow pointing right) and the notice, for the pc-watcher proof shot.
]]

local Debris = game:GetService("Debris")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local SoundService = game:GetService("SoundService")
local TweenService = game:GetService("TweenService")

local EffectPrefs = require(ReplicatedStorage:WaitForChild("Visuals"):WaitForChild("EffectPrefs"))
local PlayerSettings = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("PlayerSettings"))

local Layout = require(script.Parent.Layout)
local SoundController = require(script.Parent.SoundController)
local Sounds = require(script.Parent.Sounds)
local StealAlertLayout = require(script.Parent.StealAlertLayout)
local Widgets = require(script.Parent.Widgets)

local Theme = Widgets.Theme
local create = Widgets.create

local RED = Theme.Bad -- the Goo danger pink: flash, thief arrow, trail
local TRAIL_POLL = 0.2 -- seconds between trail / slap-attribute sweeps

local StealAlertFx = {}

-- ctx: Config, Constants, StealAlert and EdgeArrow (Shared modules), serverNow, playerName.
function StealAlertFx.new(gui: ScreenGui, ctx: { [string]: any })
	local Config = ctx.Config
	local Constants = ctx.Constants
	local StealAlert = ctx.StealAlert
	local EdgeArrow = ctx.EdgeArrow
	local cfg = Config.STEAL_ALERT
	local isStudio = RunService:IsStudio()

	local root = create("Frame", {
		Name = "StealAlertFx",
		Size = UDim2.fromScale(1, 1),
		BackgroundTransparency = 1,
		Active = false,
		ZIndex = Layout.ZINDEX.Banners,
		Parent = gui,
	})
	local flashStroke = create("UIStroke", {
		Color = RED,
		Thickness = StealAlertLayout.FLASH,
		Transparency = 1,
		ApplyStrokeMode = Enum.ApplyStrokeMode.Border,
	})
	create("Frame", {
		Name = "Flash",
		Size = UDim2.fromScale(1, 1),
		BackgroundTransparency = 1,
		ZIndex = Layout.ZINDEX.Banners,
		Parent = root,
	}, { flashStroke })

	-- Up-pointing arrow from three bars (a text glyph is not on the proven UI glyph list).
	local function bar(name: string, size: Vector2, position: Vector2, rotation: number): Frame
		return create("Frame", {
			Name = name,
			AnchorPoint = Vector2.new(0.5, 0.5),
			Size = UDim2.fromOffset(size.X, size.Y),
			Position = UDim2.fromOffset(position.X, position.Y),
			Rotation = rotation,
			BackgroundColor3 = RED,
			BorderSizePixel = 0,
			ZIndex = Layout.ZINDEX.Banners + 1,
		}, { Widgets.stroke(Theme.Ink, Widgets.KIT.stroke) })
	end
	local arrow = create("Frame", {
		Name = "ThiefArrow",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Size = UDim2.fromOffset(44, 44),
		BackgroundTransparency = 1,
		Visible = false,
		ZIndex = Layout.ZINDEX.Banners + 1,
		Parent = root,
	}, {
		bar("Shaft", Vector2.new(8, 28), Vector2.new(22, 28), 0),
		bar("HeadLeft", Vector2.new(8, 22), Vector2.new(14, 13), 45),
		bar("HeadRight", Vector2.new(8, 22), Vector2.new(30, 13), -45),
	})
	local arrowLabel = create("TextLabel", {
		Name = "ThiefLabel",
		AnchorPoint = Vector2.new(0.5, 0),
		Size = UDim2.fromOffset(StealAlertLayout.LABEL_W, StealAlertLayout.LABEL_H),
		Visible = false,
		ZIndex = Layout.ZINDEX.Banners + 1,
		BackgroundTransparency = 1,
		Text = "Thief",
		TextSize = 16,
		Font = Theme.Font,
		TextColor3 = Theme.Text,
		TextStrokeTransparency = 0,
		TextStrokeColor3 = Theme.Ink,
		Parent = root,
	})

	-- Current theft(s) of my slimes: thief UserId (nil in the Studio fake) and when it began.
	local theft: { thiefId: number?, startedAt: number, played: number }? = nil
	-- Everyone carrying one of my slimes right now (the arrow follows `theft.thiefId`, the first of them).
	local thiefIds: { number } = {}
	-- The ping (an outline, no sign) on each thief's character, and on Thief Radar visitors in my base.
	local pings: { [Model]: Highlight } = {}
	local pingKinds: { [Model]: string } = {}
	local radarIds: { number } = {}
	local sweepClock = 0
	local screen: Layout.Screen? = nil
	local bannerHeight: () -> number = function()
		return 0
	end
	local lastSlap: { [Player]: number } = {}
	local menuOpen = false -- an overlay is open: the arrow steps aside (the flash and alarm still play)

	local function debugOn(): boolean
		return isStudio and gui:GetAttribute("PcwStealAlert") == true
	end

	-- Silent with the Steal alarm setting off (the flash and the arrow still show).
	local function playAlarm()
		if not PlayerSettings.on(Players.LocalPlayer, "stealAlarm") then
			return
		end
		if SoundController.play("Alarm") then
			return
		end
		local id = Sounds.resolve("Alarm")
		if not id then
			return
		end
		local sound = Instance.new("Sound")
		sound.SoundId = id
		SoundService:PlayLocalSound(sound)
		Debris:AddItem(sound, 5)
	end

	-- `kind` "thief": the red outline; "radar" (a visitor the Thief Radar shows): a yellow outline, no fill.
	local function addPing(character: Model, kind: string)
		local radar = kind == "radar"
		local tint = if radar then Theme.Warn else Theme.Thief
		pingKinds[character] = kind
		pings[character] = create("Highlight", {
			Name = "StealHighlight",
			Adornee = character,
			FillColor = tint,
			FillTransparency = if radar then 1 else StealAlertLayout.PING_FILL_TRANSPARENCY,
			OutlineColor = tint,
			DepthMode = Enum.HighlightDepthMode.AlwaysOnTop,
			Parent = character,
		})
	end

	-- Keeps exactly one ping on each wanted character ("thief" or "radar"); each is made once and stays until that
	-- player is done (a radar visitor who starts a theft becomes a thief ping).
	local function syncPings(wanted: { [Model]: string })
		for character, outline in pings do
			if wanted[character] ~= pingKinds[character] or outline.Parent ~= character then
				outline:Destroy()
				pings[character] = nil
				pingKinds[character] = nil
			end
		end
		for character, kind in wanted do
			if not pings[character] then
				addPing(character, kind)
			end
		end
	end

	local function characterOf(userId: number): Model?
		local player = Players:GetPlayerByUserId(userId)
		return if player then player.Character else nil
	end

	local function thiefCharacter(): Model?
		local id = theft and theft.thiefId
		return if id then characterOf(id) else nil
	end

	local function hideArrow()
		arrow.Visible = false
		arrowLabel.Visible = false
	end

	-- Trail on every player with the Stealing attribute (their own client sees it too).
	local function syncTrail(player: Player)
		local character = player.Character
		local rootPart = character and character:FindFirstChild("HumanoidRootPart")
		if not character or not rootPart or not rootPart:IsA("BasePart") then
			return
		end
		local trail = rootPart:FindFirstChild("StealTrail")
		if player:GetAttribute(Constants.STEALING_ATTRIBUTE) ~= true then
			if trail then
				trail:Destroy()
				local a = rootPart:FindFirstChild("StealTrailA")
				local b = rootPart:FindFirstChild("StealTrailB")
				if a then
					a:Destroy()
				end
				if b then
					b:Destroy()
				end
			end
			return
		end
		if trail then
			return
		end
		local a = create("Attachment", { Name = "StealTrailA", Position = Vector3.new(0, 1.2, 0), Parent = rootPart })
		local b = create("Attachment", { Name = "StealTrailB", Position = Vector3.new(0, -1.2, 0), Parent = rootPart })
		create("Trail", {
			Name = "StealTrail",
			Attachment0 = a,
			Attachment1 = b,
			Lifetime = cfg.TRAIL_LIFETIME,
			Color = ColorSequence.new(RED, Theme.Warn), -- danger pink fading to warm orange
			Transparency = NumberSequence.new(0.1, 1),
			WidthScale = NumberSequence.new(1, 0),
			LightEmission = 0.4,
			FaceCamera = true,
			Parent = rootPart,
		})
	end

	-- Hit effect: white flash on the character, a "BONK!" pop and a small burst.
	-- Skipped on someone else with "Other players' effects" off.
	local function slapFx(player: Player)
		local me = Players.LocalPlayer
		if player ~= me and not EffectPrefs.showOthers(me) then
			return
		end
		local character = player.Character
		local rootPart = character and character:FindFirstChild("HumanoidRootPart")
		if not character or not rootPart or not rootPart:IsA("BasePart") then
			return
		end
		local seconds = cfg.SLAP_FX_SECONDS
		local flash = create("Highlight", {
			Name = "SlapFlash",
			Adornee = character,
			FillColor = Color3.new(1, 1, 1),
			FillTransparency = 0.1,
			OutlineColor = RED,
			DepthMode = Enum.HighlightDepthMode.AlwaysOnTop,
			Parent = character,
		})
		TweenService:Create(flash, TweenInfo.new(seconds), { FillTransparency = 1, OutlineTransparency = 1 }):Play()
		Debris:AddItem(flash, seconds + 0.1)

		local label = create("TextLabel", {
			Size = UDim2.fromScale(1, 1),
			BackgroundTransparency = 1,
			Text = "BONK!",
			TextSize = 30,
			Font = Theme.Font,
			TextColor3 = Theme.Gold,
			TextStrokeTransparency = 0,
			TextStrokeColor3 = RED,
		})
		local pop = create("BillboardGui", {
			Name = "SlapPop",
			Adornee = rootPart,
			AlwaysOnTop = true,
			Size = UDim2.fromOffset(120, 50),
			MaxDistance = 120, -- studs: a short pop, noise farther away
			LightInfluence = 0,
			StudsOffset = Vector3.new(0, 3, 0),
			Parent = character,
		}, { label })
		TweenService:Create(pop, TweenInfo.new(seconds, Enum.EasingStyle.Quad), { StudsOffset = Vector3.new(0, 6, 0) })
			:Play()
		TweenService:Create(label, TweenInfo.new(seconds), { TextTransparency = 1, TextStrokeTransparency = 1 }):Play()
		Debris:AddItem(pop, seconds + 0.1)

		local attachment = create("Attachment", { Name = "SlapBurst", Parent = rootPart })
		local emitter = create("ParticleEmitter", {
			Enabled = false,
			Lifetime = NumberRange.new(0.25, 0.45),
			Speed = NumberRange.new(14, 22),
			SpreadAngle = Vector2.new(180, 180),
			Size = NumberSequence.new(0.7, 0),
			Color = ColorSequence.new(Theme.Gold, RED),
			LightEmission = 0.6,
			Parent = attachment,
		})
		emitter:Emit(10)
		Debris:AddItem(attachment, 1)
	end

	local function sweep()
		for _, player in Players:GetPlayers() do
			syncTrail(player)
			local hit = player:GetAttribute(Constants.SLAP_HIT_ATTRIBUTE)
			if type(hit) == "number" then
				local before = lastSlap[player]
				lastSlap[player] = hit
				-- First sight of an old value (late join) is not a new slap.
				if before ~= nil and hit ~= before and math.abs(ctx.serverNow() - hit) < 3 then
					slapFx(player)
				end
			elseif lastSlap[player] == nil then
				lastSlap[player] = -1
			end
		end
	end
	Players.PlayerRemoving:Connect(function(player)
		lastSlap[player] = nil
	end)

	local self = {}

	-- The current Layout.screen and the shown banner stack height: the arrow stays under the
	-- banners / right of the nav, and the flash thins on phones.
	function self.layout(s: Layout.Screen, bannerH: () -> number)
		screen = s
		bannerHeight = bannerH
		flashStroke.Thickness = StealAlertLayout.flashThickness(s)
	end

	-- An open overlay (MenuState.noticesVisible) hides the arrow and its label until it closes.
	function self.setMenuOpen(isOpen: boolean)
		menuOpen = isOpen
	end

	-- Every State push: start / end the theft alert and show the join notice once.
	function self.update(state: any)
		if not (StealAlert.enabled() or debugOn()) then
			return
		end
		thiefIds = StealAlert.thieves(state.slimes)
		local shop = state.exclusiveShop
		radarIds = if type(shop) == "table" and type(shop.radar) == "table" then shop.radar else {}
		local thiefId = thiefIds[1]
		if thiefId ~= nil then
			if theft == nil or theft.thiefId ~= thiefId then
				theft = { thiefId = thiefId, startedAt = os.clock(), played = 0 }
			end
		elseif not debugOn() then
			theft = nil
		end
	end

	-- RenderStepped: flash, repeat alarms, arrow + ping; every TRAIL_POLL the trail / slap sweep.
	function self.step(dt: number)
		local debug = debugOn()
		if not (StealAlert.enabled() or debug) then
			return
		end
		sweepClock += dt
		if sweepClock >= TRAIL_POLL then
			sweepClock = 0
			sweep()
		end
		if debug and theft == nil then
			theft = { thiefId = nil, startedAt = os.clock(), played = cfg.ALARM_REPEATS }
		elseif not debug and theft and theft.thiefId == nil then
			theft = nil
		end
		-- The pings follow the thefts alone; the arrow below only decides whether it also shows.
		local wanted: { [Model]: string } = {}
		if not debug then
			for _, id in radarIds do
				local visitor = characterOf(id)
				if visitor then
					wanted[visitor] = "radar"
				end
			end
		end
		if theft and not debug then
			for _, id in thiefIds do
				local thief = characterOf(id)
				if thief then
					wanted[thief] = "thief"
				end
			end
		end
		syncPings(wanted)
		local character = thiefCharacter()
		local visitor = if theft == nil and radarIds[1] ~= nil then characterOf(radarIds[1]) else nil
		arrowLabel.Text = if theft == nil and visitor then "Visitor" else "Thief"
		if theft == nil then
			flashStroke.Transparency = 1
			if visitor then
				character = visitor -- the radar's arrow: no flash, no alarm
			else
				hideArrow()
				return
			end
		end
		if theft then
			local elapsed = os.clock() - theft.startedAt
			-- Studio fake: hold the flash at its peak so the frame shows it.
			local flashAt = if debug then cfg.FLASH_SECONDS / (4 * cfg.FLASH_PULSES) else elapsed
			flashStroke.Transparency = 1 - StealAlert.flashAlpha(flashAt)
			local due = StealAlert.alarmDue(elapsed)
			if due > theft.played then
				theft.played = due
				playAlarm()
			end
		end

		local camera = workspace.CurrentCamera
		if not camera then
			hideArrow()
			return
		end
		local cameraPos, look = camera.CFrame.Position, camera.CFrame.LookVector
		local target: Vector3? = nil
		local rootPart = character and character:FindFirstChild("HumanoidRootPart")
		if rootPart and rootPart:IsA("BasePart") then
			target = rootPart.Position
		elseif debug then
			target = cameraPos + camera.CFrame.RightVector * 80 + Vector3.new(look.X, 0, look.Z) * 20
		end
		if not target then
			hideArrow()
			return
		end
		local _, distance = StealAlert.bearing(
			{ x = cameraPos.X, z = cameraPos.Z },
			{ x = target.X, z = target.Z },
			{ x = look.X, z = look.Z }
		)
		if distance < cfg.PING_HIDE_STUDS and not debug then
			hideArrow() -- close enough to see them (the outline stays)
			return
		end
		if not screen or menuOpen then
			hideArrow()
			return
		end
		-- GUI design px: screen px (inset applied) over the UIScale.
		local scale = if screen.scale > 0 then screen.scale else 1
		local rect = StealAlertLayout.arrowRect(screen, bannerHeight())
		local rel = camera.CFrame:PointToObjectSpace(target)
		local spot = camera:WorldToScreenPoint(target)
		if rel.Z < 0 and EdgeArrow.inside({ x = spot.X / scale, y = spot.Y / scale }, rect) and not debug then
			hideArrow() -- on screen: the ping marks them
			return
		end
		local ahead = camera:WorldToScreenPoint(cameraPos + look * 10)
		local dx, dy = EdgeArrow.direction({ x = rel.X, y = rel.Y, z = rel.Z })
		local placed = EdgeArrow.place({ x = ahead.X / scale, y = ahead.Y / scale }, dx, dy, rect)
		arrow.Position = UDim2.fromOffset(placed.x, placed.y)
		arrow.Rotation = placed.angle + 90 -- the glyph points up
		arrow.Visible = true
		arrowLabel.Position = UDim2.fromOffset(placed.x, placed.y + StealAlertLayout.LABEL_DROP)
		arrowLabel.Visible = true
	end

	RunService.RenderStepped:Connect(self.step)
	return self
end

return StealAlertFx
