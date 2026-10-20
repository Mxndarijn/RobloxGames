--!strict
--[[
	PvpBlaster (FEATURES.PvP, CONTRACT.md §26.6)

	The `Blaster` line handler for PvpService.registerLine (GooBlaster1-3). PvpService has already checked the flag,
	ownership, equipped item, cooldown and the attacker's new-player shield. The server owns the shot: each goo blob
	leaves the attacker's server position and flies a ballistic arc (Shared.PvpBlasterRules) toward the aim, clamped
	to the tool's range; the first non-shielded player the arc passes (at fire time) is hit. The client only sends
	the aim and draws the same arc from the PvpEvent "Effect".

	  Squirter  rapid fire: `shots` per tank, `shotGap` apart; the cooldown (the refill) starts after the last shot.
	            Each hit stacks a little slow (PvpSlow.stack, capped by SLOW_MAX_SECONDS).
	  Blaster   `blobs` in a fan `spreadDeg` apart; each player is hit at most once per shot.
	  Cannon    one big lob: everyone within `splash` of the impact is slowed and a slowing pool stays `poolSeconds`.
	Every player a blob, a splash, a pool or a splat hits is caught when carrying a stolen slime (PvpService.catchThief,
	immunity or not). A blob that hits nobody leaves a slippery splat (SPLAT_*). Pools and splats are server-side zones
	(no Instance) stepped in the per-player WorldView tick; they slow whoever walks in (not the shooter, not shielded
	players, immunity respected). No Humanoid health is ever changed.
]]

local Shared = if script then (game:GetService("ReplicatedStorage") :: any).Shared else nil
local Config = if Shared then require(Shared.Config) else require("../shared/Config")
local PvpBlasterRules = if Shared then require(Shared.PvpBlasterRules) else require("../shared/PvpBlasterRules")
local PvpRules = if Shared then require(Shared.PvpRules) else require("../shared/PvpRules")
local PvpTrapRules = if Shared then require(Shared.PvpTrapRules) else require("../shared/PvpTrapRules")
local PvpService = if script then require(script.Parent.PvpService) else require("./PvpService")
local PvpSlow = if script then require(script.Parent.PvpSlow) else require("./PvpSlow")
local World = if script then require(script.Parent.World) else require("./World")

type Session = World.Session
type Vec = PvpRules.Vec

local PvpBlaster = {}

local PVP = Config.PVP

-- A slowing patch of goo on the ground (a missed blob's splat, a Cannon pool).
export type Zone = {
	owner: number,
	itemId: string,
	position: Vec,
	radius: number,
	untilTime: number,
	slow: number,
	seconds: number,
}
type Tank = { left: number, lastShot: number }

local zones: { [Session]: { Zone } } = setmetatable({}, { __mode = "k" }) :: any
local tanks: { [Session]: Tank } = setmetatable({}, { __mode = "k" }) :: any

function PvpBlaster.zones(session: Session): { Zone }
	return zones[session] or {}
end

-- Shots left in the Squirter tank (the full tank when none was fired).
function PvpBlaster.shotsLeft(session: Session, tool: Config.PvpTool): number
	local tank = tanks[session]
	return if tank then tank.left else tool.shots or 1
end

local function out(ctx: PvpService.Context?, position: Vec): any
	local convert = ctx and ctx.toVector3
	return if convert then convert(position) else position
end

local function addZone(owner: Session, zone: Zone)
	local list = zones[owner] or {}
	zones[owner] = list
	table.insert(list, zone)
	while #list > PVP.SPLAT_MAX do
		table.remove(list, 1)
	end
end

-- Slows `victim` with the shot's tool; returns the slow seconds (0 = immune) and whether a thief was caught.
local function hitPlayer(call: PvpService.UseCall, victim: Session): (number, boolean)
	local tool, now = call.tool, call.now
	local state = PvpService.state(victim)
	if not state then
		return 0, false
	end
	local applied = 0
	if tool.shots then
		applied =
			PvpSlow.stack(victim, state, now, tool.slow or 0, tool.slowMax or tool.slow or 0, tool.slowSeconds or 0)
	else
		applied = PvpRules.applySlow(state, tool.slowSeconds or 0, now)
		if applied > 0 then
			PvpSlow.slow(victim, now, PvpBlasterRules.slowFactor(tool.slow), now + applied)
		end
	end
	local caught = PvpService.catchThief(call.world, victim, call.session, now) ~= nil
	return applied, caught
end

local function ground(ctx: PvpService.Context, point: Vec): Vec
	local below = ctx.groundBelow
	local hit = if below then below(point) else nil
	return hit or point
end

-- One blob along `arc`. `skip` = players already hit by this shot. Fires its Effect.
local function blob(
	call: PvpService.UseCall,
	arc: PvpBlasterRules.Arc,
	candidates: { PvpBlasterRules.Candidate },
	skip: { [number]: boolean }
)
	local tool, world, now = call.tool, call.world, call.now
	local open = {}
	for _, candidate in candidates do
		if not skip[candidate.id] then
			table.insert(open, candidate)
		end
	end
	local hit, t = PvpBlasterRules.firstHit(arc, open)
	local flight = t or arc.flight
	local stop = if hit then PvpBlasterRules.pointAt(arc, flight) else arc.to
	local impact = if hit then hit.position else stop
	local target: Session? = nil
	local slowed = 0
	if hit then
		skip[hit.id] = true
		target = world.sessions[hit.id]
		if target then
			slowed = hitPlayer(call, target)
		end
	end
	local splat: { radius: number, seconds: number }? = nil
	if tool.splash then
		local spot = ground(call.ctx, stop)
		for _, other in PvpBlasterRules.within(impact, tool.splash, candidates) do
			local victim = world.sessions[other.id]
			if victim and not skip[other.id] then
				skip[other.id] = true
				local seconds = hitPlayer(call, victim)
				PvpService.fireEffect(world, {
					attacker = call.session.userId,
					target = other.id,
					itemId = tool.id,
					effect = "Slow",
					splash = true,
					position = out(call.ctx, other.position),
					duration = seconds,
				}, now, true)
			end
		end
		if tool.pool and tool.poolSeconds then
			addZone(call.session, {
				owner = call.session.userId,
				itemId = tool.id,
				position = spot,
				radius = tool.pool,
				untilTime = now + flight + tool.poolSeconds,
				slow = tool.slow or 0,
				seconds = math.min(tool.slowSeconds or 1, PVP.SPLAT_SLOW_SECONDS * 2),
			})
			splat = { radius = tool.pool, seconds = tool.poolSeconds }
		end
		impact = spot
	elseif not hit then
		impact = ground(call.ctx, stop)
		addZone(call.session, {
			owner = call.session.userId,
			itemId = tool.id,
			position = impact,
			radius = PVP.SPLAT_RADIUS,
			untilTime = now + flight + PVP.SPLAT_SECONDS,
			slow = PVP.SPLAT_SLOW,
			seconds = PVP.SPLAT_SLOW_SECONDS,
		})
		splat = { radius = PVP.SPLAT_RADIUS, seconds = PVP.SPLAT_SECONDS }
	end
	PvpService.fireEffect(world, {
		attacker = call.session.userId,
		target = if target then target.userId else nil,
		itemId = tool.id,
		effect = "Slow",
		from = out(call.ctx, arc.from),
		to = out(call.ctx, stop),
		flight = flight,
		position = out(call.ctx, impact),
		duration = if target then slowed else PVP.SPLAT_SECONDS,
		splat = splat,
	}, now, true)
end

local function handler(call: PvpService.UseCall): (boolean, string?, number?)
	local tool, now = call.tool, call.now
	local positionOf = call.ctx.positionOf
	if not positionOf then
		return false, "can't fire right now"
	end
	local origin = call.position
	local aim: any = call.targetPosition or call.aim
	if aim == nil then
		return false, "no aim"
	end
	if not PvpBlasterRules.direction(origin, aim) then
		return false, "bad aim"
	end
	local tank = tanks[call.session]
	if tool.shots then
		if not tank then
			tank = { left = tool.shots, lastShot = -math.huge }
			tanks[call.session] = tank
		end
		if now - tank.lastShot < (tool.shotGap or 0) then
			return false, "too fast"
		end
	end
	local candidates: { PvpBlasterRules.Candidate } = {}
	for userId, other in call.world.sessions do
		if other ~= call.session and not PvpService.isShielded(other, now) then
			local position = positionOf(userId)
			if position then
				table.insert(candidates, { id = userId, position = position })
			end
		end
	end
	local skip: { [number]: boolean } = {}
	for _, point in PvpBlasterRules.fan(tool, origin, aim) do
		local arc = PvpBlasterRules.arc(tool, origin, point)
		if arc then
			blob(call, arc, candidates, skip)
		end
	end
	if tank then
		tank.lastShot = now
		tank.left -= 1
		if tank.left > 0 then
			return true, nil, 0 -- still shots in the tank: no cooldown yet
		end
		tanks[call.session] = nil
	end
	return true, nil -- a miss still spends the shot
end

--[[
	Per-player tick (WorldView.updatePlayer, flag on only): expires old splats / pools and slows `victim` at
	`position` when it walks into one it did not make. Returns the slow seconds applied (0 = none).
]]
function PvpBlaster.tick(
	world: World.World,
	victim: Session,
	position: any?,
	now: number,
	ctx: PvpService.Context?
): number
	if next(zones) == nil then
		return 0
	end
	for owner, list in zones do
		for i = #list, 1, -1 do
			if now >= list[i].untilTime then
				table.remove(list, i)
			end
		end
		if #list == 0 then
			zones[owner] = nil
		end
	end
	local state = PvpService.state(victim)
	if not position or not state or PvpService.isShielded(victim, now) then
		return 0
	end
	for _, list in zones do
		for _, zone in list do
			if zone.owner ~= victim.userId and PvpTrapRules.within(zone.position, zone.radius, position) then
				PvpService.catchThief(world, victim, world.sessions[zone.owner], now)
				if not PvpRules.canControl(state, now) then
					return 0
				end
				local applied = PvpRules.applySlow(state, zone.seconds, now)
				if applied > 0 then
					PvpSlow.slow(victim, now, PvpBlasterRules.slowFactor(zone.slow), now + applied)
					PvpService.fireEffect(world, {
						attacker = zone.owner,
						target = victim.userId,
						itemId = zone.itemId,
						effect = "Slow",
						splash = true,
						position = out(ctx, position),
						duration = applied,
					}, now, true)
					return applied
				end
			end
		end
	end
	return 0
end

local function clear(_world: World.World, session: Session)
	zones[session] = nil
	tanks[session] = nil
end
PvpBlaster.clear = clear

-- Registers the Blaster line. Harmless with the flag off (PvpService.use refuses first).
function PvpBlaster.register()
	PvpService.registerLine("Blaster", handler)
	PvpService.onCleanup(clear)
end

return PvpBlaster
