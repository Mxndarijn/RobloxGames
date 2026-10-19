--!strict
--[[
	BatTool (CONTRACT.md §26 "Bat"; LIVE for everyone, NOT behind FEATURES.PvP)

	The default melee Tool every player has instead of the old on-screen Slap button. `Tool.Activated` (tap on mobile,
	click on desktop) fires on the server; the CLIENT SENDS NO TARGET and no remote is used. `BatTool.swing` takes the
	swinger's own position and look vector, picks the nearest carrying thief in reach and in front (BatRules.pickTarget),
	and routes the hit into the same StealService.slap the button used (reach SLAP_REACH, slap cooldown
	Session.lastSlapAt, drop + bounce home + notifications + StealAlerts FX), then adds a knockback
	push (PvpKnockbackRules.plan / PvpLaunch through `ctx.launch`; the victim's client applies the launch from the
	PvpEvent "Knockback" effect). Swinging at nothing or at a non-thief does nothing with FEATURES.PvP off; with it ON a
	non-thief on the swinger's own plot is pushed under the glove rules (no damage, ever; Humanoid health is never touched). A whiff never spends the slap cooldown; swings are only rate limited to Config.BAT.SWING_GAP.

	The Tool: one per player (give() replaces any old copy), given on every spawn, CanBeDropped = false, single
	collision-free handle Part (a few parts per player, only while equipped, never in the world part budget).
	The model / icon / swing sound hookup is shared/BatModel (MESH_ID / ICON_ID / SWING_SOUND): change it there only.
	Every click plays the swing (the BatSwingAt attribute every client animates + a whoosh), hit or miss.
]]

local Shared = if script then (game:GetService("ReplicatedStorage") :: any).Shared else nil
local BatModel = if Shared then require(Shared.BatModel) else require("../shared/BatModel")
local BossEvent = if script then require(script.Parent.BossEvent) else require("./BossEvent")
local BatRules = if Shared then require(Shared.BatRules) else require("../shared/BatRules")
local Config = if Shared then require(Shared.Config) else require("../shared/Config")
local Constants = if Shared then require(Shared.Constants) else require("../shared/Constants")
local PvpKnockbackRules = if Shared then require(Shared.PvpKnockbackRules) else require("../shared/PvpKnockbackRules")
local PvpRules = if Shared then require(Shared.PvpRules) else require("../shared/PvpRules")
local PvpService = if script then require(script.Parent.PvpService) else require("./PvpService")
local StealService = if script then require(script.Parent.StealService) else require("./StealService")
local World = if script then require(script.Parent.World) else require("./World")

type Vec = PvpRules.Vec

local BatTool = {}

local lastSwing: { [number]: number } = {}

-- The Bat as a Knockback "tool" for PvpKnockbackRules.plan / the PvpEvent itemId.
local KNOCK_TOOL = { id = "Bat", push = Config.BAT.PUSH, reach = Config.SLAP_REACH } :: any

function BatTool.forget(userId: number)
	lastSwing[userId] = nil
end

-- Knockback push + FX (PvP limits: capped push, map bounds, control immunity). False = nobody was pushed.
local function knock(
	world: World.World,
	ctx: PvpService.Context,
	session: World.Session,
	target: World.Session,
	origin: Vec,
	targetPosition: Vec,
	now: number
): boolean
	local state = PvpService.state(target) -- nil with FEATURES.PvP off
	local launch = ctx.launch -- nil = no knockback, the slap still lands
	if not launch or (state and not PvpRules.canControl(state, now)) then
		return false
	end
	local landing, push = PvpKnockbackRules.plan(KNOCK_TOOL, origin, targetPosition)
	if not launch(target.userId, push, landing) then
		return false
	end
	if state then
		PvpRules.applyControl(state, Config.PVP.KNOCKBACK_CONTROL_SECONDS, now)
	end
	PvpService.fireEffect(world, {
		attacker = session.userId,
		target = target.userId,
		itemId = KNOCK_TOOL.id,
		effect = "Knockback",
		position = targetPosition,
		push = PvpKnockbackRules.horizontal(push),
		velocity = PvpKnockbackRules.velocity(push),
		duration = Config.PVP.FX_SECONDS,
	}, now, true) -- the Bat is live: force the client FX on whatever FEATURES.PvP says
	return true
end

-- A slap target: a thief carrying a stolen slime, or the boss carrier (the slap drops the boss on the spot).
local function isThief(s: World.Session): boolean
	return s.carry ~= nil and (s.carry.kind == "stolen" or s.carry.boss == true)
end

-- The fighting boss in reach and in front: its Body position from `ctx.slimePosition`, reach Config.BOSS.HIT_REACH.
local function bossInReach(
	world: World.World,
	ctx: PvpService.Context,
	session: World.Session,
	origin: Vec,
	look: Vec
): boolean
	local id = BossEvent.bossId(world)
	if not id or BossEvent.phase(world) ~= "fight" or not ctx.slimePosition then
		return false
	end
	local position = ctx.slimePosition(id)
	if not position then
		return false
	end
	local candidate = { userId = -1, position = position, carrying = true }
	return BatRules.pickTarget(origin, look, { candidate }, session.userId, Config.BOSS.HIT_REACH) ~= nil
end

--[[
	One swing by `session`. Returns (hit, reason): hit = something was hit. `ctx.pose` gives every character's root
	and look (nil = no bat), `ctx.pointOnOwnPlot` the own-plot test (nil = no non-thief hits). `flag` overrides
	FEATURES.PvP (tests).
	  * The boss carrier in reach (any flag): BossEvent.slapCarrier drops the boss on the spot, then the knockback.
	  * The fighting boss in reach (Config.BOSS.HIT_REACH, in front): BossEvent.hit fills the goo meter.
	  * A carrying thief in reach (any flag): StealService.slap (reach, shared cooldown, drop, bounce home, notifications,
	    StealAlerts FX), then the knockback. Exactly one drop and one push per hit.
	  * Flag OFF, anything else: nothing happens (no damage, no push), (false, "nothing in reach").
	  * Flag ON, a non-thief: only on the swinger's OWN plot, never by or on a player under the new-player shield, not a
	    controlled / immune one, and the shared slap cooldown; the effect is the knockback only. No damage ever. A thief
	    is always tried first.
	A whiff never spends the slap cooldown. Never errors for a swing at nothing.
]]
function BatTool.swing(
	world: World.World,
	session: World.Session,
	now: number,
	ctx: PvpService.Context,
	flag: boolean?
): (boolean, string?)
	local pose, onOwnPlot = ctx.pose, ctx.pointOnOwnPlot
	if not pose then
		return false, "no bat"
	end
	local last = lastSwing[session.userId]
	if last and now - last < Config.BAT.SWING_GAP then
		return false, "too fast"
	end
	lastSwing[session.userId] = now
	local origin, look = pose(session.userId)
	if not origin or not look then
		return false, "can't find you"
	end
	local pvp = PvpService.enabled(flag)
	local thieves: { BatRules.Candidate } = {}
	local others: { BatRules.Candidate } = {}
	local offPlot: { BatRules.Candidate } = {}
	local positions: { [number]: Vec } = {}
	for userId, other in world.sessions do
		if userId ~= session.userId then
			local position = pose(userId)
			if position then
				positions[userId] = position
				local entry = { userId = userId, position = position, carrying = true }
				if isThief(other) then
					table.insert(thieves, entry)
				elseif pvp and onOwnPlot and onOwnPlot(session, position) then
					table.insert(others, entry)
				elseif pvp then
					table.insert(offPlot, entry)
				end
			end
		end
	end
	local targetId, distance = BatRules.pickTarget(origin, look, thieves, session.userId)
	if targetId and BossEvent.isCarrier(world.sessions[targetId]) then
		local target = world.sessions[targetId]
		local spot = positions[targetId]
		local ok, reason = BossEvent.slapCarrier(
			world,
			session,
			target,
			distance,
			now,
			if ctx.toVector3 then ctx.toVector3(spot) else spot
		)
		if not ok then
			return false, reason
		end
		knock(world, ctx, session, target, origin, spot, now)
		return true, nil
	end
	if targetId then
		local target = world.sessions[targetId]
		local ok, reason = StealService.slap(world, session, targetId, distance, now)
		if not ok then
			return false, reason
		end
		knock(world, ctx, session, target, origin, positions[targetId], now)
		return true, nil
	end
	if bossInReach(world, ctx, session, origin, look) then
		return BossEvent.hit(world, session, now)
	end
	targetId = BatRules.pickTarget(origin, look, others, session.userId)
	local target = if targetId then world.sessions[targetId] else nil
	if not targetId or not target then
		if BatRules.pickTarget(origin, look, offPlot, session.userId) then
			return false, "not on your plot"
		end
		return false, "nothing in reach"
	end
	local targetPosition = positions[targetId]
	if now - session.lastSlapAt < Config.SLAP_COOLDOWN then
		return false, "slap on cooldown"
	end
	if PvpService.isShielded(target, now) or PvpService.isShielded(session, now) then
		return false, "shielded"
	end
	if not knock(world, ctx, session, target, origin, targetPosition, now) then
		return false, "can't push right now"
	end
	session.lastSlapAt = now
	return true, nil
end

---------------------------------------------------------------------------
-- The Tool (Roblox only; never called under Lune)
---------------------------------------------------------------------------

local meshTemplate: any = nil
local meshTried = false

-- One CreateMeshPartAsync per server (it yields); every Bat clones it. nil = use the placeholder block.
local function meshHandle(): any
	if not meshTried and BatModel.MESH_ID then
		meshTried = true
		local ok, mesh = pcall(function()
			return (game:GetService("AssetService") :: any):CreateMeshPartAsync(BatModel.MESH_ID, {
				CollisionFidelity = Enum.CollisionFidelity.Box,
				RenderFidelity = Enum.RenderFidelity.Automatic,
			})
		end)
		if ok and mesh then
			meshTemplate = mesh
		end
	end
	return if meshTemplate then meshTemplate:Clone() else nil
end

local function buildHandle(): any
	local handle: any = meshHandle()
	if not handle then
		handle = Instance.new("Part")
		handle.Material = Enum.Material.Wood
		handle.Color = Color3.new(BatModel.COLOR[1], BatModel.COLOR[2], BatModel.COLOR[3])
	end
	handle.Name = "Handle"
	handle.Size = Vector3.new(BatModel.SIZE[1], BatModel.SIZE[2], BatModel.SIZE[3])
	handle.CanCollide = false
	handle.CanQuery = false
	handle.CanTouch = false
	handle.Massless = true
	handle.CastShadow = false
	return handle
end

-- The swing everyone sees: the Player attribute BatSwingAt (server time) makes every client play the procedural swing
-- (ui/PvpAnim; the swinger's own client already played it on Activated), plus a whoosh from the handle. Played for
-- every click, hit or miss, at most once per Config.BAT.SWING_GAP.
local function playSwing(tool: any, whoosh: any)
	local character = tool.Parent
	local players: any = game:GetService("Players")
	local player = if character then players:GetPlayerFromCharacter(character) else nil
	if player then
		player:SetAttribute(Constants.BAT_SWING_ATTRIBUTE, workspace:GetServerTimeNow())
	end
	pcall(function() -- the Lune live-boot Sound stand-in has no Play
		whoosh:Play()
	end)
end

-- A fresh Bat Tool for `player`; swings go to BatTool.swing through `onSwing`.
function BatTool.build(onSwing: () -> ()): any
	local tool = Instance.new("Tool")
	tool.Name = Config.BAT.TOOL_NAME
	tool.ToolTip = "Hit a thief to make them drop your slime"
	tool.CanBeDropped = false
	tool.RequiresHandle = true
	local icon = BatModel.ICON_ID
	if icon then
		tool.TextureId = icon
	end
	local grip = BatModel.GRIP
	tool.Grip = CFrame.new(grip.pos[1], grip.pos[2], grip.pos[3])
		* CFrame.Angles(math.rad(grip.rotDeg[1]), math.rad(grip.rotDeg[2]), math.rad(grip.rotDeg[3]))
	local handle = buildHandle()
	handle.Parent = tool
	local whoosh = Instance.new("Sound")
	whoosh.Name = "Swing"
	whoosh.SoundId = BatModel.SWING_SOUND
	whoosh.Volume = 0.6
	whoosh.RollOffMaxDistance = 60
	whoosh.Parent = handle
	local lastLook = -math.huge
	tool.Activated:Connect(function()
		local at = os.clock()
		if at - lastLook >= Config.BAT.SWING_GAP then
			lastLook = at
			playSwing(tool, whoosh)
		end
		onSwing()
	end)
	return tool
end

-- Gives `player` exactly one Bat in their Backpack (any old copy, in the Backpack or held, is removed first).
function BatTool.give(player: any, onSwing: () -> ())
	local backpack = player:FindFirstChildOfClass("Backpack") or player:WaitForChild("Backpack", 5)
	if not backpack then
		return
	end
	for _, container in { backpack, player.Character } do
		local old = container and container:FindFirstChild(Config.BAT.TOOL_NAME)
		if old and old:IsA("Tool") then
			old:Destroy()
		end
	end
	BatTool.build(onSwing).Parent = backpack
end

return BatTool
