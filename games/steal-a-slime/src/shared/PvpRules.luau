--!strict
--[[
	PvpRules (pure, FEATURES.PvP, CONTRACT.md §26, docs/PVP.md)

	The fairness core of the v22 PvP ladder: prices, rank gating, ownership, the new-player shield, safe
	zones, control limits, the cooldown registry, who may be targeted, and the knockback clamp. No Roblox
	APIs: positions are any table with X / Y / Z (a Vector3 works), so Lune tests it directly.

	GUARANTEE: no PvP item ever reduces Humanoid health. Nothing in this module or in Config.PVP_TOOLS has a
	damage field (Validate.pvpTools asserts it at load), knockback is a capped horizontal push with a small
	arc, and the landing point is clamped inside the map. Control is bounded: at most
	Config.PVP.CONTROL_MAX_SECONDS, then Config.PVP.CONTROL_IMMUNITY_SECONDS of immunity.

	With the flag off every gate answers "no" (price / ownership helpers stay pure and still work).
]]

local Config = if script then require(script.Parent.Config) else require("./Config")
local Economy = if script then require(script.Parent.Economy) else require("./Economy")

export type Vec = { X: number, Y: number, Z: number }
export type Pvp = { tiers: { [string]: number }, fun: { [string]: boolean }, played: number }
-- What PvpRules reads from PlayerData.Data.
export type Data = { cash: number, rebirths: number, pvp: Pvp? }
-- Per-player runtime state (server/PvpService keeps one per session; never saved).
export type State = {
	joinedAt: number, -- when this session started (play time counts towards the shield)
	shieldUntil: number, -- time the new-player shield ends (0 = none)
	controlUntil: number, -- time the current control ends
	immuneUntil: number, -- no new control before this
	cooldowns: { [string]: number }, -- tool id -> time it is ready again
}
export type Fighter = {
	position: Vec,
	state: State?,
	rebirths: number?,
	carrying: boolean?, -- a thief with a slime in their arms
}

local PvpRules = {}

local PVP = Config.PVP
local BY_ID: { [string]: Config.PvpTool } = {}
local MAX_TIER: { [string]: number } = {}
for _, tool in Config.PVP_TOOLS do
	BY_ID[tool.id] = tool
	if tool.kind == "tool" then
		MAX_TIER[tool.line] = math.max(MAX_TIER[tool.line] or 0, tool.tier)
	end
end

PvpRules.LINES = table.freeze({ "Knockback", "Trap", "Blaster" })

local function enabled(override: boolean?): boolean
	if override ~= nil then
		return override
	end
	return Config.FEATURES.PvP == true
end
PvpRules.enabled = enabled

function PvpRules.tool(id: any): Config.PvpTool?
	return if type(id) == "string" then BY_ID[id] else nil
end

function PvpRules.maxTier(line: string): number
	return MAX_TIER[line] or 0
end

-- The tool of `line` at `tier`.
function PvpRules.toolAt(line: string, tier: number): Config.PvpTool?
	for _, tool in Config.PVP_TOOLS do
		if tool.line == line and tool.tier == tier then
			return tool
		end
	end
	return nil
end

function PvpRules.emptyPvp(): Pvp
	return { tiers = {}, fun = {}, played = 0 }
end

-- Price in cash: factor x Economy.rebirthCost(gate), never below PRICE_MIN.
function PvpRules.price(id: string): number
	local tool = BY_ID[id]
	if not tool then
		return 0
	end
	local factor = if tool.kind == "fun" then PVP.PRICE_FACTOR_FUN else PVP.PRICE_FACTOR_TOOL
	return math.max(PVP.PRICE_MIN, math.floor(factor * Economy.rebirthCost(tool.rebirths)))
end

function PvpRules.isUnlocked(data: Data, id: string): boolean
	local tool = BY_ID[id]
	return tool ~= nil and data.rebirths >= tool.rebirths
end

-- Best owned tier of a line (0 = none).
function PvpRules.bestTier(data: Data, line: string): number
	local pvp = data.pvp
	return if pvp then pvp.tiers[line] or 0 else 0
end

-- The owned tool of a line (the best tier replaces the lower ones), or nil.
function PvpRules.bestTool(data: Data, line: string): Config.PvpTool?
	local tier = PvpRules.bestTier(data, line)
	return if tier > 0 then PvpRules.toolAt(line, tier) else nil
end

-- Owned = bought, or superseded by a higher tier of the same line.
function PvpRules.owns(data: Data, id: string): boolean
	local tool = BY_ID[id]
	if not tool or not data.pvp then
		return false
	end
	if tool.kind == "fun" then
		return data.pvp.fun[id] == true
	end
	return (data.pvp.tiers[tool.line] or 0) >= tool.tier
end

function PvpRules.canBuy(data: Data, id: any, flag: boolean?): (boolean, string?)
	if not enabled(flag) then
		return false, "PvP is not open yet"
	end
	local tool = PvpRules.tool(id)
	if not tool then
		return false, "unknown item"
	end
	if PvpRules.owns(data, tool.id) then
		return false, "already owned"
	end
	if not PvpRules.isUnlocked(data, tool.id) then
		return false, `needs {tool.rebirths} rebirths`
	end
	if data.cash < PvpRules.price(tool.id) then
		return false, "not enough cash"
	end
	return true, nil
end

-- Pays and records the item (a higher tier replaces the lower ones of its line). Returns (ok, reason).
function PvpRules.buy(data: Data, id: any, flag: boolean?): (boolean, string?)
	local ok, reason = PvpRules.canBuy(data, id, flag)
	if not ok then
		return false, reason
	end
	local tool = BY_ID[id :: string]
	data.cash -= PvpRules.price(tool.id)
	local pvp: Pvp = data.pvp or PvpRules.emptyPvp()
	data.pvp = pvp
	if tool.kind == "fun" then
		pvp.fun[tool.id] = true
	else
		pvp.tiers[tool.line] = tool.tier
	end
	return true, nil
end

function PvpRules.newState(): State
	return { joinedAt = 0, shieldUntil = 0, controlUntil = 0, immuneUntil = 0, cooldowns = {} }
end

-- When a shield that starts at `now` ends: none once the player has rebirthed or played the full shield time.
function PvpRules.shieldEnd(played: number, rebirths: number, now: number): number
	if rebirths > 0 or played >= PVP.NEW_PLAYER_SHIELD_SECONDS then
		return 0
	end
	return now + (PVP.NEW_PLAYER_SHIELD_SECONDS - math.max(0, played))
end

-- Shielded = a shield end in the future and no rebirth yet (the first rebirth ends it).
function PvpRules.isShielded(state: State?, now: number, rebirths: number?): boolean
	if not state or (rebirths or 0) > 0 then
		return false
	end
	return now < state.shieldUntil
end

local function inDisc(zone: any, x: number, z: number): boolean
	local dx, dz = x - zone.x, z - zone.z
	return dx * dx + dz * dz <= zone.radius * zone.radius
end

-- Whether the XZ position is inside any Config.PVP.SAFE_ZONES disc (Y ignored).
function PvpRules.inSafeZone(position: Vec): boolean
	for _, zone in PVP.SAFE_ZONES do
		if inDisc(zone, position.X, position.Z) then
			return true
		end
	end
	return false
end

-- The SAFE_ZONES id (lowercase) of the first disc containing the XZ position, or nil.
function PvpRules.safeZoneAt(position: Vec): string?
	for _, zone in PVP.SAFE_ZONES do
		if inDisc(zone, position.X, position.Z) then
			return zone.id
		end
	end
	return nil
end

-- Control: false while the target is controlled or immune.
function PvpRules.canControl(state: State, now: number): boolean
	return now >= state.controlUntil and now >= state.immuneUntil
end

-- Starts control, clamped to CONTROL_MAX_SECONDS. Returns the applied seconds (0 = refused). Immunity
-- of CONTROL_IMMUNITY_SECONDS starts when the control ends.
function PvpRules.applyControl(state: State, duration: number, now: number): number
	if not PvpRules.canControl(state, now) or duration ~= duration or duration <= 0 then
		return 0
	end
	local applied = math.min(duration, PVP.CONTROL_MAX_SECONDS)
	state.controlUntil = now + applied
	state.immuneUntil = now + applied + PVP.CONTROL_IMMUNITY_SECONDS
	return applied
end

-- Slows follow the same bookkeeping with their own, longer cap.
function PvpRules.applySlow(state: State, duration: number, now: number): number
	if not PvpRules.canControl(state, now) or duration ~= duration or duration <= 0 then
		return 0
	end
	local applied = math.min(duration, PVP.SLOW_MAX_SECONDS)
	state.controlUntil = now + applied
	state.immuneUntil = now + applied + PVP.CONTROL_IMMUNITY_SECONDS
	return applied
end

-- Cooldown registry. Unknown tools are never ready.
function PvpRules.ready(state: State, id: string, now: number): boolean
	local tool = BY_ID[id]
	return tool ~= nil and now >= (state.cooldowns[id] or -math.huge)
end

function PvpRules.markUsed(state: State, id: string, now: number)
	local tool = BY_ID[id]
	if tool then
		state.cooldowns[id] = now + math.max(tool.cooldown, PVP.MIN_COOLDOWN)
	end
end

export type TargetContext = {
	now: number,
	toolId: string,
	onAttackerPlot: boolean, -- the target stands on the attacker's own plot
	enabled: boolean?, -- FEATURES.PvP override (tests)
	data: Data?, -- the attacker's save: when given, they must own the tool and have its rank
}

--[[
	May `attacker` use `ctx.toolId` on `target`? Returns (ok, reason).
	  * the flag is on; the tool exists (and the attacker owns it and has the rank, when ctx.data is given)
	  * neither player stands in a safe zone (a cosmetic with allowInSafeZone skips the attacker's check)
	  * the target is not shielded (new-player shield)
	  * non-cosmetic tools: only on the attacker's own plot, or against a thief carrying a slime
	    (cosmetic fun items are exempt from this movement rule; `target` may then be nil for a self effect)
]]
function PvpRules.canTarget(attacker: Fighter, target: Fighter?, ctx: TargetContext): (boolean, string?)
	if not enabled(ctx.enabled) then
		return false, "PvP is not open yet"
	end
	local tool = BY_ID[ctx.toolId]
	if not tool then
		return false, "unknown item"
	end
	if ctx.data then
		if not PvpRules.owns(ctx.data, tool.id) then
			return false, "not owned"
		end
		if not PvpRules.isUnlocked(ctx.data, tool.id) then
			return false, `needs {tool.rebirths} rebirths`
		end
	end
	if attacker.state and not PvpRules.ready(attacker.state, tool.id, ctx.now) then
		return false, "not ready"
	end
	if not (tool.allowInSafeZone and tool.cosmetic) and PvpRules.inSafeZone(attacker.position) then
		return false, "safe zone"
	end
	if target then
		if PvpRules.inSafeZone(target.position) then
			return false, "target is in a safe zone"
		end
		if PvpRules.isShielded(target.state, ctx.now, target.rebirths) then
			return false, "target is shielded"
		end
	end
	if not tool.cosmetic then
		if not target then
			return false, "no target"
		end
		if not (ctx.onAttackerPlot or target.carrying == true) then
			return false, "only on your plot or against a thief"
		end
		if target.state and not PvpRules.canControl(target.state, ctx.now) and (tool.control or tool.slowSeconds) then
			return false, "target is immune"
		end
	end
	return true, nil
end

export type Bounds = { minX: number, maxX: number, minZ: number, maxZ: number }

--[[
	Knockback landing: `push` is the wanted displacement. Horizontal length is capped at KNOCKBACK_MAX_PUSH,
	the vertical arc is 0..KNOCKBACK_ARC_HEIGHT, and the landing point is clamped inside `bounds` (default
	Config.PVP.MAP_BOUNDS) shrunk by KNOCKBACK_BOUNDS_MARGIN, so it never ends in the void. Returns the landing
	position and the push actually applied.
]]
function PvpRules.clampKnockback(origin: Vec, push: Vec, bounds: Bounds?): (Vec, Vec)
	local box = bounds or PVP.MAP_BOUNDS
	local margin = PVP.KNOCKBACK_BOUNDS_MARGIN
	local dx, dz = push.X, push.Z
	if dx ~= dx or dz ~= dz then
		dx, dz = 0, 0
	end
	local length = math.sqrt(dx * dx + dz * dz)
	if length > PVP.KNOCKBACK_MAX_PUSH then
		local scale = PVP.KNOCKBACK_MAX_PUSH / length
		dx, dz = dx * scale, dz * scale
	end
	local dy = push.Y
	if dy ~= dy then
		dy = 0
	end
	dy = math.clamp(dy, 0, PVP.KNOCKBACK_ARC_HEIGHT)
	local x = math.clamp(origin.X + dx, box.minX + margin, box.maxX - margin)
	local z = math.clamp(origin.Z + dz, box.minZ + margin, box.maxZ - margin)
	local landing: Vec = { X = x, Y = origin.Y, Z = z }
	return landing, { X = x - origin.X, Y = dy, Z = z - origin.Z }
end

return PvpRules
