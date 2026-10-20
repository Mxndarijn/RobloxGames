--!strict
--[[
	PvpRules (pure, FEATURES.PvP, CONTRACT.md §26, docs/PVP.md)

	The fairness core of the PvP ladder: prices, rank gating, ownership (Goo Trap charges included), control limits,
	the cooldown registry, who may be targeted, and the knockback clamp. No Roblox APIs:
	positions are any table with X / Y / Z (a Vector3 works), so Lune tests it directly.

	GUARANTEE: no PvP item ever reduces Humanoid health. Nothing in this module or in Config.PVP_TOOLS has a
	damage field (Validate.pvpTools asserts it at load), knockback is a capped push with a capped arc, and the
	landing point is clamped inside the map. Control is bounded: at most Config.PVP.CONTROL_MAX_SECONDS (slows
	SLOW_MAX_SECONDS), then Config.PVP.CONTROL_IMMUNITY_SECONDS of immunity.

	There are no safe zones: PvP works everywhere, on everyone.
	With the flag off every gate answers "no" (price / ownership helpers stay pure and still work).
]]

local Config = if script then require(script.Parent.Config) else require("./Config")
local Economy = if script then require(script.Parent.Economy) else require("./Economy")

export type Vec = { X: number, Y: number, Z: number }
export type Pvp = {
	tiers: { [string]: number }, -- Knockback / Blaster -> best owned tier
	traps: { [string]: number }, -- Goo Trap id -> charges held
	fun: { [string]: boolean },
}
-- What PvpRules reads from PlayerData.Data.
export type Data = { cash: number, rebirths: number, pvp: Pvp? }
-- Per-player runtime state (server/PvpService keeps one per session; never saved).
export type State = {
	controlUntil: number, -- time the current control / slow ends
	immuneUntil: number, -- no new control before this
	cooldowns: { [string]: number }, -- tool id -> time it is ready again
}
export type Fighter = {
	position: Vec,
	state: State?,
	rebirths: number?,
	carrying: boolean?, -- a thief with a stolen slime in their arms
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
-- Lines owned as a stack of charges (one per buy, used up), not as a best tier.
PvpRules.CHARGE_LINE = "Trap"

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
	return { tiers = {}, traps = {}, fun = {} }
end

-- A tool used up per use and bought as charges (the Goo Traps).
function PvpRules.usesCharges(tool: Config.PvpTool): boolean
	return tool.kind == "tool" and tool.line == PvpRules.CHARGE_LINE
end

-- Price in cash: factor x Economy.rebirthCost(gate), never below PRICE_MIN (one charge for a trap).
function PvpRules.price(id: string): number
	local tool = BY_ID[id]
	if not tool then
		return 0
	end
	local factor = if tool.kind == "fun"
		then PVP.PRICE_FACTOR_FUN
		elseif PvpRules.usesCharges(tool) then PVP.PRICE_FACTOR_TRAP
		else PVP.PRICE_FACTOR_TOOL
	return math.max(PVP.PRICE_MIN, math.floor(factor * Economy.rebirthCost(tool.rebirths)))
end

function PvpRules.isUnlocked(data: Data, id: string): boolean
	local tool = BY_ID[id]
	return tool ~= nil and data.rebirths >= tool.rebirths
end

-- Charges held of a trap id (0 for anything else).
function PvpRules.charges(data: Data, id: string): number
	local pvp = data.pvp
	local n = if pvp and pvp.traps then pvp.traps[id] else nil
	return if type(n) == "number" and n > 0 then math.floor(n) else 0
end

-- Uses one charge of a trap id. False when there is none.
function PvpRules.useCharge(data: Data, id: string): boolean
	local n = PvpRules.charges(data, id)
	local pvp = data.pvp
	if n <= 0 or not pvp then
		return false
	end
	if n > 1 then
		pvp.traps[id] = n - 1
	else
		pvp.traps[id] = nil
	end
	return true
end

-- Best owned tier of a line (0 = none). Traps: the highest tier with a charge.
function PvpRules.bestTier(data: Data, line: string): number
	local pvp = data.pvp
	if not pvp then
		return 0
	end
	if line == PvpRules.CHARGE_LINE then
		local best = 0
		for _, tool in Config.PVP_TOOLS do
			if tool.line == line and PvpRules.charges(data, tool.id) > 0 then
				best = math.max(best, tool.tier)
			end
		end
		return best
	end
	return pvp.tiers[line] or 0
end

-- The owned tool of a line (the best tier replaces the lower ones), or nil.
function PvpRules.bestTool(data: Data, line: string): Config.PvpTool?
	local tier = PvpRules.bestTier(data, line)
	return if tier > 0 then PvpRules.toolAt(line, tier) else nil
end

-- Owned = bought (a trap: a charge left), or superseded by a higher glove / blaster tier of the same line.
function PvpRules.owns(data: Data, id: string): boolean
	local tool = BY_ID[id]
	if not tool or not data.pvp then
		return false
	end
	if tool.kind == "fun" then
		return data.pvp.fun[id] == true
	end
	if PvpRules.usesCharges(tool) then
		return PvpRules.charges(data, id) > 0
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
	if PvpRules.usesCharges(tool) then
		if PvpRules.charges(data, tool.id) >= PVP.TRAP_MAX_HELD then
			return false, `you can only hold {PVP.TRAP_MAX_HELD}`
		end
	elseif PvpRules.owns(data, tool.id) then
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

-- Pays and records the item (a higher tier replaces the lower ones of its line; a trap adds one charge).
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
	elseif PvpRules.usesCharges(tool) then
		pvp.traps[tool.id] = PvpRules.charges(data, tool.id) + 1
	else
		pvp.tiers[tool.line] = tool.tier
	end
	return true, nil
end

function PvpRules.newState(): State
	return { controlUntil = 0, immuneUntil = 0, cooldowns = {} }
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

--[[
	A stacking slow (Goo Squirter): a running slow that started at `startedAt` and ends at `untilTime` is extended by
	`add` seconds, but never past startedAt + SLOW_MAX_SECONDS; immunity moves with its end. Returns the new end
	(= untilTime when nothing could be added).
]]
function PvpRules.extendSlow(state: State, startedAt: number, untilTime: number, add: number, now: number): number
	if add ~= add or add <= 0 or now >= untilTime then
		return untilTime
	end
	local newEnd = math.min(startedAt + PVP.SLOW_MAX_SECONDS, untilTime + add)
	if newEnd > untilTime then
		state.controlUntil = math.max(state.controlUntil, newEnd)
		state.immuneUntil = math.max(state.immuneUntil, newEnd + PVP.CONTROL_IMMUNITY_SECONDS)
	end
	return math.max(newEnd, untilTime)
end

-- Cooldown registry. Unknown tools are never ready.
function PvpRules.ready(state: State, id: string, now: number): boolean
	local tool = BY_ID[id]
	return tool ~= nil and now >= (state.cooldowns[id] or -math.huge)
end

-- Starts the cooldown: `seconds` (default the tool's), never below MIN_COOLDOWN.
function PvpRules.markUsed(state: State, id: string, now: number, seconds: number?)
	local tool = BY_ID[id]
	if tool then
		state.cooldowns[id] = now + math.max(seconds or tool.cooldown, PVP.MIN_COOLDOWN)
	end
end

export type TargetContext = {
	now: number,
	toolId: string,
	enabled: boolean?, -- FEATURES.PvP override (tests)
	data: Data?, -- the attacker's save: when given, they must own the tool and have its rank
}

--[[
	May `attacker` use `ctx.toolId` on `target`? Returns (ok, reason). Anyone may be hit anywhere, except:
	  * the flag is off; the tool is unknown (or not owned / its rank not reached, when ctx.data is given)
	  * the tool is cooling down
	  * a non-cosmetic tool without a target, or one that controls / slows a target under control or immunity
	Cosmetic fun items may have no target (a self effect).
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
	if not tool.cosmetic then
		if not target then
			return false, "no target"
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
