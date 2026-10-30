--!strict
--[[
	Outbox (adapter over injected engine calls)

	Plays what the systems queued in world.outbox (World.drain), in order: Effect bursts, the slap-hit stamp
	(FEATURES.StealAlerts), the goo-drain splash, the rare-drop workspace attributes (CONTRACT.md §8.4), badge
	grants, Notify toasts, PvpEvents (CONTRACT.md §26.1) and Analytics calls (GameAnalytics). Every engine call comes in through `Deps`, so the
	routing runs under Lune with recorders. A handler that errors is logged through `safeCall` and the rest of
	the events still go out.
]]

local Shared = if script then (game:GetService("ReplicatedStorage") :: any).Shared else nil
local Config = if Shared then require(Shared.Config) else require("../shared/Config")
local Constants = if Shared then require(Shared.Constants) else require("../shared/Constants")
local Lib = if script then (game:GetService("ReplicatedStorage") :: any).Lib else nil
local SafeCall = if Lib then require(Lib.core.SafeCall) else require("../../../../shared/luau/src/core/SafeCall")
local World = if script then require(script.Parent.World) else require("./World")

-- The two RemoteEvent methods the outbox uses.
export type Remote = {
	FireClient: (self: any, player: any, ...any) -> (),
	FireAllClients: (self: any, ...any) -> (),
}

export type Deps = {
	now: () -> number,
	playerOf: (userId: number) -> any?, -- the Player in this server, nil when gone
	notify: Remote, -- Notify: (text, kind, sound, itemId)
	pvp: Remote, -- PvpEvent: (payload)
	playEffect: (event: World.Event) -> (), -- Effects.play on the event's target
	splash: () -> (), -- the goo-drain splash (FEATURES.Parade)
	grantBadge: (userId: number, badge: string) -> (), -- yields: called in its own thread
	setWorldAttribute: (name: string, value: any) -> (), -- workspace:SetAttribute
	safeCall: SafeCall.Call,
	spawn: (fn: (...any) -> (), ...any) -> (), -- task.spawn
	track: ((player: any, track: World.Track) -> ())?, -- GameAnalytics.play for the player; nil = analytics off
}

local Outbox = {}

local function fireTo(remote: Remote, deps: Deps, userId: number?, ...: any)
	if userId == nil then
		remote:FireAllClients(...)
		return
	end
	local player = deps.playerOf(userId)
	if player then
		remote:FireClient(player, ...)
	end
end

local function play(event: World.Event, deps: Deps)
	local kind = event.type
	if kind == "Effect" and event.effect then
		deps.safeCall(`Effects.play {event.effect}`, deps.playEffect, event)
	elseif kind == "Escaped" then
		if event.reason == "slap" and Config.FEATURES.StealAlerts and event.carrierUserId then
			local victim = deps.playerOf(event.carrierUserId)
			if victim then
				victim:SetAttribute(Constants.SLAP_HIT_ATTRIBUTE, deps.now())
			end
		end
	elseif kind == "Drained" then
		deps.safeCall("drain splash", deps.splash)
	elseif kind == "Rare" then
		-- Latest Legendary+ drop for client effects; At changes on every one.
		deps.setWorldAttribute(Constants.RARE_SPAWN_ID_ATTRIBUTE, event.slimeId)
		deps.setWorldAttribute(Constants.RARE_SPAWN_TIER_ATTRIBUTE, event.tier)
		deps.setWorldAttribute(Constants.RARE_SPAWN_AT_ATTRIBUTE, deps.now())
	elseif kind == "Badge" then
		if event.userId and event.badge then
			deps.spawn(deps.grantBadge, event.userId, event.badge)
		end
	elseif kind == "Notify" then
		if event.text then
			fireTo(deps.notify, deps, event.userId, event.text, event.kind or "info", event.sound, event.itemId)
		end
	elseif kind == "Analytics" then
		local track = deps.track
		if track and event.track and event.userId then
			local player = deps.playerOf(event.userId)
			if player then
				track(player, event.track)
			end
		end
	elseif kind == "PvpEvent" then
		local payload = event.payload
		if payload then
			payload.serverTime = payload.serverTime or deps.now()
			fireTo(deps.pvp, deps, event.userId, payload)
		end
	end
end

-- Drains world.outbox and plays every event. Never errors.
function Outbox.flush(world: World.World, deps: Deps)
	for _, event in World.drain(world) do
		deps.safeCall(`outbox {event.type}`, play, event, deps)
	end
end

return Outbox
