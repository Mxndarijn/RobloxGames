--!strict
--[[
	AdminEventsService (server, FEATURES.AdminEvents, CONTRACT.md §12)

	Applies a live event to the World and carries it across servers. Entry points:
	`command` (a chat line from a player; ignored unless they are an admin) and `receive`
	(a MessagingService payload; re-validated, the sender must be an admin, rate-limited).
	Luck events override the dawn / dusk modifier until they end (Spawner.stepModifier);
	rain reuses Spawner.forceRain. The messaging transport is injected so tests need no Roblox.
]]

local Shared = if script then (game:GetService("ReplicatedStorage") :: any).Shared else nil
local AdminShared = if Shared then require(Shared.AdminEvents) else require("../shared/AdminEvents")
local Config = if Shared then require(Shared.Config) else require("../shared/Config")
local Spawner = if script then require(script.Parent.Spawner) else require("./Spawner")
local World = if script then require(script.Parent.World) else require("./World")

export type Transport = {
	publish: (topic: string, data: any) -> (),
}

export type Service = {
	world: World.World,
	creatorId: number?,
	transport: Transport?,
	limiter: AdminShared.Limiter,
	seen: { [string]: boolean },
	counter: number,
}

local AdminEventsService = {}

function AdminEventsService.new(world: World.World, creatorId: number?, transport: Transport?): Service
	return {
		world = world,
		creatorId = creatorId,
		transport = transport,
		limiter = AdminShared.limiter(),
		seen = {},
		counter = 0,
	}
end

-- Starts the event on this server (the validated payload only).
function AdminEventsService.apply(service: Service, payload: AdminShared.Payload, now: number)
	local world = service.world
	local def = AdminShared.def(payload.id)
	if not def then
		return
	end
	if def.id == "rain" then
		Spawner.forceRain(world, now)
	else
		world.adminEvent = {
			def = { id = def.id, label = def.label, icon = def.icon }, -- table props are invariant: a full Def would not fit World.AdminEvent.def
			endsAt = now + payload.seconds,
			modifier = {
				name = "Admin_" .. def.id,
				label = def.label,
				weight = 0,
				luck = def.luck,
			},
		}
		Spawner.stepModifier(world, now)
	end
	World.notify(world, nil, AdminShared.announce(def, payload.seconds), "good", "WeeklyEvent")
	World.markAllDirty(world)
end

-- A cross-server message. Returns true when it started an event here.
function AdminEventsService.receive(service: Service, raw: any, now: number): boolean
	local payload = AdminShared.validate(raw, service.creatorId)
	if not payload or service.seen[payload.nonce] then
		return false
	end
	service.seen[payload.nonce] = true
	if not AdminShared.allow(service.limiter, now) then
		return false
	end
	AdminEventsService.apply(service, payload, now)
	return true
end

-- A player's chat line. Non-admins and non-commands do nothing at all (no reply either).
-- Returns a status string for the admin, nil otherwise.
function AdminEventsService.command(service: Service, userId: number, text: string, now: number): string?
	if not AdminShared.isAdmin(userId, service.creatorId) then
		return nil
	end
	local id, seconds = AdminShared.parse(text)
	if not id or not seconds then
		return nil
	end
	if not AdminShared.allow(service.limiter, now) then
		return "Event cooldown: wait a few seconds."
	end
	service.counter += 1
	local payload = AdminShared.payload(id, seconds, userId, `{userId}-{math.floor(now * 1000)}-{service.counter}`)
	service.seen[payload.nonce] = true
	local sent = false
	if service.transport then
		-- The publishing server also receives its own message, but `seen` drops it; apply locally.
		sent = pcall(service.transport.publish, Config.ADMIN_EVENT_TOPIC, payload)
	end
	AdminEventsService.apply(service, payload, now)
	return if sent then "Event started in all servers." else "Event started here (cross-server send failed)."
end

-- Roblox only: subscribes to the topic (pcall; Studio / throttling may refuse) and returns the transport.
function AdminEventsService.start(service: Service, now: () -> number)
	local ok, MessagingService = pcall(function()
		return game:GetService("MessagingService")
	end)
	if not ok then
		return
	end
	service.transport = {
		publish = function(topic, data)
			(MessagingService :: any):PublishAsync(topic, data)
		end,
	}
	task.spawn(function()
		pcall(function()
			(MessagingService :: any):SubscribeAsync(Config.ADMIN_EVENT_TOPIC, function(message: any)
				AdminEventsService.receive(service, message.Data, now())
			end)
		end)
	end)
end

return AdminEventsService
