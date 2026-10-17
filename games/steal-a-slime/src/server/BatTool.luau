--!strict
--[[
	BatTool (CONTRACT.md §26 "Bat"; LIVE for everyone, NOT behind FEATURES.PvP)

	The default melee Tool every player has instead of the old on-screen Slap button. `Tool.Activated` (tap on mobile,
	click on desktop) fires on the server; the CLIENT SENDS NO TARGET and no remote is used. `BatTool.swing` takes the
	swinger's own position and look vector, picks the nearest carrying thief in reach and in front (BatRules.pickTarget),
	and routes the hit into the same StealService.slap the button used (reach SLAP_REACH, shared cooldown
	Session.lastSlapAt with the Squeaky Hammer, drop + bounce home + notifications + StealAlerts FX), then adds a knockback
	push (PvpKnockbackRules.plan / PvpLaunch through the injectable mover; the victim's client applies the launch from the
	PvpEvent "Knockback" effect). Swinging at nothing or at a non-thief does nothing with FEATURES.PvP off; with it ON a
	non-thief on the swinger's own plot is pushed under the glove rules (no damage, ever; Humanoid health is never touched). A whiff never spends the slap cooldown; swings are only rate limited to Config.BAT.SWING_GAP.

	The Tool: one per player (give() replaces any old copy), given on every spawn, CanBeDropped = false, single
	collision-free handle Part (a few parts per player, only while equipped, never in the world part budget).
	The model / icon hookup is shared/BatModel (MESH_ID / ICON_ID): change it there only.
]]

local Shared = if script then (game:GetService("ReplicatedStorage") :: any).Shared else nil
local BatModel = if Shared then require(Shared.BatModel) else require("../shared/BatModel")
local BatRules = if Shared then require(Shared.BatRules) else require("../shared/BatRules")
local Config = if Shared then require(Shared.Config) else require("../shared/Config")
local PvpKnockbackRules = if Shared then require(Shared.PvpKnockbackRules) else require("../shared/PvpKnockbackRules")
local PvpRules = if Shared then require(Shared.PvpRules) else require("../shared/PvpRules")
local PvpService = if script then require(script.Parent.PvpService) else require("./PvpService")
local StealService = if script then require(script.Parent.StealService) else require("./StealService")
local World = if script then require(script.Parent.World) else require("./World")

type Vec = PvpRules.Vec

-- Pose of a character: root position and horizontal look vector. nil = no character.
export type Env = {
	pose: (userId: number) -> (Vec?, Vec?),
	-- (userId, push, landing) -> moved; same shape as PvpKnockback.Mover. nil = no knockback, the slap still lands.
	mover: ((userId: number, push: Vec, landing: Vec) -> boolean)?,
	-- Is this world position inside the session's own plot (its HomeZone)? nil = no plot, so no non-thief hits (PvP on).
	onOwnPlot: ((session: World.Session, position: Vec) -> boolean)?,
}

local BatTool = {}

local env: Env? = nil
local lastSwing: { [number]: number } = {}

-- The Bat as a Knockback "tool" for PvpKnockbackRules.plan / the PvpEvent itemId.
local KNOCK_TOOL = { id = "Bat", push = Config.BAT.PUSH, reach = Config.SLAP_REACH } :: any

function BatTool.setEnv(newEnv: Env?)
	env = newEnv
	lastSwing = {}
end

-- The current env (a probe swaps its own and restores this one).
function BatTool.getEnv(): Env?
	return env
end

function BatTool.forget(userId: number)
	lastSwing[userId] = nil
end

-- Knockback push + FX (PvP limits: capped push, map bounds, control immunity). False = nobody was pushed.
local function knock(
	e: Env,
	session: World.Session,
	target: World.Session,
	origin: Vec,
	targetPosition: Vec,
	now: number,
	pvp: boolean
): boolean
	local state = PvpService.state(target) -- nil with FEATURES.PvP off
	if not e.mover or (state and not PvpRules.canControl(state, now)) then
		return false
	end
	if pvp and (PvpRules.inSafeZone(origin) or PvpRules.inSafeZone(targetPosition)) then
		return false -- with PvP on nobody is launched in or out of a safe zone (the glove rule)
	end
	local landing, push = PvpKnockbackRules.plan(KNOCK_TOOL, origin, targetPosition)
	if not e.mover(target.userId, push, landing) then
		return false
	end
	if state then
		PvpRules.applyControl(state, Config.PVP.KNOCKBACK_CONTROL_SECONDS, now)
	end
	PvpService.fireEffect({
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

local function isThief(s: World.Session): boolean
	return s.carry ~= nil and s.carry.kind == "stolen"
end

--[[
	One swing by `session`. Returns (hit, reason): hit = something was hit. `flag` overrides FEATURES.PvP (tests).
	  * A carrying thief in reach (any flag): StealService.slap (reach, shared cooldown, drop, bounce home, notifications,
	    StealAlerts FX), then the knockback. Exactly one drop and one push per hit.
	  * Flag OFF, anything else: nothing happens (no damage, no push), (false, "nothing in reach").
	  * Flag ON, a non-thief: the PvP melee rules (PvpRules.canTarget's): only on the swinger's OWN plot, never from or into a
	    safe zone, not a shielded (new) player, not a controlled / immune one, and the shared slap cooldown; the effect is the
	    knockback only. No damage ever. A thief is always tried first.
	A whiff never spends the slap cooldown. Never errors for a swing at nothing.
]]
function BatTool.swing(world: World.World, session: World.Session, now: number, flag: boolean?): (boolean, string?)
	local e = env
	if not e then
		return false, "no bat"
	end
	local last = lastSwing[session.userId]
	if last and now - last < Config.BAT.SWING_GAP then
		return false, "too fast"
	end
	lastSwing[session.userId] = now
	local origin, look = e.pose(session.userId)
	if not origin or not look then
		return false, "can't find you"
	end
	local pvp = PvpService.enabled(flag)
	local thieves: { BatRules.Candidate } = {}
	local others: { BatRules.Candidate } = {}
	local positions: { [number]: Vec } = {}
	for userId, other in world.sessions do
		if userId ~= session.userId then
			local position = e.pose(userId)
			if position then
				positions[userId] = position
				local entry = { userId = userId, position = position, carrying = true }
				if isThief(other) then
					table.insert(thieves, entry)
				elseif pvp and e.onOwnPlot and e.onOwnPlot(session, position) then
					table.insert(others, entry)
				end
			end
		end
	end
	local targetId, distance = BatRules.pickTarget(origin, look, thieves, session.userId)
	if targetId then
		local target = world.sessions[targetId]
		local ok, reason = StealService.slap(world, session, targetId, distance, now)
		if not ok then
			return false, reason
		end
		knock(e, session, target, origin, positions[targetId], now, pvp)
		return true, nil
	end
	targetId = BatRules.pickTarget(origin, look, others, session.userId)
	local target = if targetId then world.sessions[targetId] else nil
	if not targetId or not target then
		return false, "nothing in reach"
	end
	local targetPosition = positions[targetId]
	if now - session.lastSlapAt < Config.SLAP_COOLDOWN then
		return false, "slap on cooldown"
	end
	local state = PvpService.state(target)
	if
		PvpRules.inSafeZone(origin)
		or PvpRules.inSafeZone(targetPosition)
		or PvpRules.isShielded(state, now, target.data.rebirths)
	then
		return false, "safe zone or shield"
	end
	if not knock(e, session, target, origin, targetPosition, now, pvp) then
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
	buildHandle().Parent = tool
	tool.Activated:Connect(onSwing)
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
