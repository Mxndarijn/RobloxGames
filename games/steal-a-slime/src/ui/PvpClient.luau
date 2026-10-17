--!strict
--[[
	PvpClient (FEATURES.PvP, docs/PVP-CLIENT.md)

	The ONE client adapter for the v22 PvP contract (CONTRACT.md §26.1). Pure: no Roblox APIs, no Instances;
	everything Roblox-side is injected (`now`, `send`), so Lune tests drive it
	(tests/ui/PvpClient.spec.luau). The views (PvpHud) only read its queries. The client never decides an
	outcome: it shows what the server last said and forwards taps as Request actions.

	Reads (all optional, all `any`: the server owns the shapes; Types.PvpView is the real one):
	  :applyState(state)   state.pvp = { rank, owned = {[id]=true}, best = {Knockback=id?, Trap=id?, Blaster=id?},
	                       equipped = id?, cooldowns = {[id]=endsAt}, shieldUntil = number?, safeZone = string? }
	                       (safeZone is "Spawn" | "Shop" | "Fountain");
	                       state.pvp == nil (flag off server-side) = empty PvP data, every query answers "nothing".
	  :applyEvent(ev)      PvpEvent kinds "Cooldown" {itemId, duration, startedAt}, "Shield" {endsAt?},
	                       "SafeZone" {zone, inside}; "Effect" / "TrapPlaced" / "TrapCleared" are only forwarded to
	                       :onEffect listeners (no FX in this PR).
	  :setShieldAttribute(v)  the Player attribute "PvpShieldUntil" (fallback for the shield).
	Times are server time; `now()` is the same clock (real: workspace:GetServerTimeNow()).

	Queries: rank, owns, best, equipped, hotbarSlots, cooldown(id) -> (fraction left 0..1, seconds left),
	shield() -> (active, seconds left), safeZone() -> string?. Pure helpers: unlockedAt(rank), isUnlocked(id, rank).

	Cooldown rule (CONTRACT.md §26.1: the event starts the ring, State.pvp.cooldowns[id] = endsAt is fallback AND
	resync). A "Cooldown" event records endsAt = startedAt + duration and the ring length `duration` (else the
	catalog cooldown). On every state snapshot, per event-recorded id:
	  - the snapshot lists the id -> its endsAt replaces the event's (resync: shorter or longer; a stale event cannot
	    keep a ring alive after the state says it ended); the event's `duration` is kept for the ring length;
	  - the snapshot omits the id -> the event is dropped (the cooldown is over), UNLESS it started less than
	    EVENT_GRACE seconds ago (the snapshot may have been built before that event: a newer event is not killed).
	Ids never seen in an event just follow state.pvp.cooldowns. Past = 0. Never NaN / negative.
	Shield rule: a "Shield" event (until the next snapshot) > state.pvp.shieldUntil > the attribute.
	Safe zone: server only (state.pvp.safeZone / "SafeZone" event); never a client position check.

	Commands go through the injected send(action, ...) (the real one is init.client's Request path) with the
	contract action names. send may return (false, reason) synchronously (a refusal); that comes back as
	false, reason and starts nothing locally: a cooldown only ever comes from the server.

	Catalog: Config.PVP_TOOLS, nothing else; item data is read from it only. Rank gates go through
	Shared.PvpRules.isUnlocked (one rule, no copy); the UI still never decides an outcome. Field names are main's
	Config: id, name, line, tier, rebirths, cooldown, kind, cosmetic, push, control, radius, slowSeconds, and
	`slow` (a fraction, 0.3) / `traps` (CONTRACT.md §26.1's slowPercent / count / rearm text is not what main
	ships; a trap's cooldown IS its rearm). effectSlowPercent / effectCount read those two.

	BASE_SLAP: display-only rank 0 of the Knockback line ("Base slap", free). It is not a PVP_TOOLS entry and
	NOT a hotbar slot: the SLAP! button stays the way to slap. The shop (PR 2) lists it as the line's first rank.
]]

local Shared = if script then game:GetService("ReplicatedStorage"):WaitForChild("Shared") :: any else nil
local Config = if Shared then require(Shared:WaitForChild("Config")) else require("../shared/Config")
local Constants = if Shared then require(Shared:WaitForChild("Constants")) else require("../shared/Constants")
local PvpRules = if Shared then require(Shared:WaitForChild("PvpRules")) else require("../shared/PvpRules")

export type Tool = {
	id: string,
	name: string,
	line: string, -- "Knockback" | "Trap" | "Blaster" | "Fun"
	tier: number,
	rebirths: number,
	cooldown: number,
	kind: string, -- "tool" | "fun"
	cosmetic: boolean,
	[string]: any,
}
export type Slot = { id: string, name: string, line: string, tier: number, keybind: string? }
export type Options = {
	now: (() -> number)?,
	send: ((action: string, ...any) -> (any, any))?,
	flag: boolean?, -- override Config.FEATURES.PvP (enabled() only; nothing is built here either way)
}

local PvpClient = {}

PvpClient.EQUIP_ACTION = "EquipPvpItem"
PvpClient.USE_ACTION = "UsePvpItem"
PvpClient.EVENT_NAME = Constants.PVP_EVENT
PvpClient.MAX_KEYBINDS = 9
PvpClient.EVENT_GRACE = 1 -- s: a Cooldown event younger than this survives a snapshot that omits its id
PvpClient.LINES = table.freeze({ "Knockback", "Trap", "Blaster" })

-- Rank 0 of the Knockback line, for the shop only (PR 2). Not in the catalog, not a hotbar slot, not buyable.
PvpClient.BASE_SLAP = table.freeze({
	id = "BaseSlap",
	name = "Base slap",
	line = "Knockback",
	tier = 0,
	rebirths = 0,
	free = true,
})

-- Effect params for UI text (main's Config names). slowPercent: Blaster `slow` (0.3) as 30; effectCount: Trap `traps`.
-- nil when the tool has neither.
function PvpClient.effectSlowPercent(t: any): number?
	return if type(t.slow) == "number" then t.slow * 100 else nil
end
function PvpClient.effectCount(t: any): number?
	return t.traps
end

local LINE_ORDER: { [string]: number } = { Knockback = 1, Trap = 2, Blaster = 3, Fun = 4 }

local function isNumber(v: any): boolean
	return type(v) == "number" and v == v and v > -math.huge and v < math.huge
end

-- Catalog (list or id-keyed map) -> a list in ladder order (line, tier, gate, id) and an id map.
local function normalize(raw: any): ({ Tool }, { [string]: Tool })
	local list: { Tool } = {}
	for _, entry in raw do
		if type(entry) == "table" and type(entry.id) == "string" then
			table.insert(list, entry)
		end
	end
	table.sort(list, function(a, b)
		local la, lb = LINE_ORDER[a.line] or 9, LINE_ORDER[b.line] or 9
		if la ~= lb then
			return la < lb
		end
		if a.tier ~= b.tier then
			return a.tier < b.tier
		end
		if a.rebirths ~= b.rebirths then
			return a.rebirths < b.rebirths
		end
		return a.id < b.id
	end)
	local byId: { [string]: Tool } = {}
	for _, t in list do
		byId[t.id] = t
	end
	return list, byId
end

-- Config.PVP_TOOLS in ladder order.
function PvpClient.catalog(): { Tool }
	return (normalize(Config.PVP_TOOLS))
end

-- Locks: items the player can buy / use at `rank` rebirths (PvpRules.isUnlocked), ladder order.
function PvpClient.unlockedAt(rank: number): { Tool }
	local out = {}
	if not isNumber(rank) then
		return out
	end
	for _, t in PvpClient.catalog() do
		if PvpClient.isUnlocked(t.id, rank) then
			table.insert(out, t)
		end
	end
	return out
end

function PvpClient.isUnlocked(id: string, rank: number): boolean
	return isNumber(rank) and PvpRules.isUnlocked({ cash = 0, rebirths = rank }, id)
end

function PvpClient.new(opts: Options?)
	local o: Options = opts or {}
	local now: () -> number = o.now or function()
		return 0
	end
	local send = o.send
	local list, byId = normalize(Config.PVP_TOOLS)

	local pvp: { [string]: any } = {} -- state.pvp ({} = flag off / no data)
	local attrShield: number? = nil
	local eventShield: { endsAt: number? }? = nil -- last "Shield" event since the snapshot
	local eventZone: { zone: string? }? = nil -- last "SafeZone" event since the snapshot
	local eventCooldowns: { [string]: { startedAt: number, duration: number, endsAt: number } } = {}
	local changedFns: { [number]: () -> () } = {}
	local effectFns: { [number]: (any) -> () } = {}
	local nextId = 0

	local self = {}

	local function connect(map: { [number]: any }, fn: any): () -> ()
		nextId += 1
		local id = nextId
		map[id] = fn
		return function()
			map[id] = nil
		end
	end
	local function fire()
		for _, fn in table.clone(changedFns) do
			fn()
		end
	end

	-- `changed` signal: fn() after every applyState / applyEvent / setShieldAttribute. Returns a disconnect.
	function self.onChanged(fn: () -> ()): () -> ()
		return connect(changedFns, fn)
	end
	-- Effect / TrapPlaced / TrapCleared events, forwarded as received (FX is a later PR).
	function self.onEffect(fn: (any) -> ()): () -> ()
		return connect(effectFns, fn)
	end

	function self.enabled(): boolean
		if o.flag ~= nil then
			return o.flag
		end
		return Config.FEATURES.PvP == true
	end

	function self.catalog(): { Tool }
		return list
	end
	function self.tool(id: string): Tool?
		return byId[id]
	end

	function self.applyState(state: any)
		local p = if type(state) == "table" then state.pvp else nil
		pvp = if type(p) == "table" then p else {}
		eventShield = nil -- the snapshot is newer than any earlier event
		eventZone = nil
		local cds = pvp.cooldowns
		for id, ev in table.clone(eventCooldowns) do
			local at = if type(cds) == "table" then cds[id] else nil
			if isNumber(at) then
				ev.endsAt = at -- resync to the state
			elseif now() - ev.startedAt >= PvpClient.EVENT_GRACE then
				eventCooldowns[id] = nil -- the state no longer lists it: over
			end
		end
		fire()
	end

	function self.applyEvent(ev: any)
		if type(ev) ~= "table" then
			return
		end
		local kind = ev.kind
		if kind == "Cooldown" then
			if type(ev.itemId) == "string" and isNumber(ev.startedAt) and isNumber(ev.duration) then
				local duration = math.max(ev.duration, 0)
				eventCooldowns[ev.itemId] =
					{ startedAt = ev.startedAt, duration = duration, endsAt = ev.startedAt + duration }
			end
		elseif kind == "Shield" then
			eventShield = { endsAt = if isNumber(ev.endsAt) then ev.endsAt else nil }
		elseif kind == "SafeZone" then
			if type(ev.zone) == "string" then
				if ev.inside == true then
					eventZone = { zone = ev.zone }
				elseif self.safeZone() == ev.zone then
					eventZone = { zone = nil } -- left the zone we were in
				end
			end
		elseif kind == "Effect" or kind == "TrapPlaced" or kind == "TrapCleared" then
			for _, fn in table.clone(effectFns) do
				fn(ev)
			end
			return
		else
			return
		end
		fire()
	end

	function self.setShieldAttribute(v: any)
		attrShield = if isNumber(v) then v else nil
		fire()
	end

	-- Queries ------------------------------------------------------------------------

	function self.rank(): number
		return if isNumber(pvp.rank) then pvp.rank else 0
	end

	function self.owns(id: string): boolean
		local owned = pvp.owned
		return type(owned) == "table" and owned[id] == true and byId[id] ~= nil
	end

	-- The best owned tool of a line, as the snapshot says (the server applies the supersede rule).
	function self.best(line: string): string?
		local b = pvp.best
		local id = if type(b) == "table" then b[line] else nil
		if type(id) == "string" and byId[id] ~= nil and byId[id].line == line then
			return id
		end
		return nil
	end

	function self.equipped(): string?
		local id = pvp.equipped
		return if type(id) == "string" then id else nil
	end

	-- Hotbar order: best Knockback, best Trap, best Blaster, then owned Fun items by rank gate, then id.
	-- Keybinds "1".."9" for the first nine; later slots have none (tap only).
	function self.hotbarSlots(): { Slot }
		local ids: { string } = {}
		for _, line in PvpClient.LINES do
			local id = self.best(line)
			if id then
				table.insert(ids, id)
			end
		end
		local fun: { Tool } = {}
		for _, t in list do
			if t.line == "Fun" and self.owns(t.id) then
				table.insert(fun, t)
			end
		end
		table.sort(fun, function(a, b)
			if a.rebirths ~= b.rebirths then
				return a.rebirths < b.rebirths
			end
			return a.id < b.id
		end)
		for _, t in fun do
			table.insert(ids, t.id)
		end
		local slots: { Slot } = {}
		for i, id in ids do
			local t = byId[id]
			table.insert(slots, {
				id = id,
				name = t.name,
				line = t.line,
				tier = t.tier,
				keybind = if i <= PvpClient.MAX_KEYBINDS then tostring(i) else nil,
			})
		end
		return slots
	end

	-- (fraction of the cooldown left 0..1, seconds left). 0, 0 when ready.
	function self.cooldown(id: string): (number, number)
		local t = byId[id]
		local endsAt: number?, duration: number? = nil, nil
		local ev = eventCooldowns[id]
		if ev then
			endsAt, duration = ev.endsAt, ev.duration
		else
			local cds = pvp.cooldowns
			local at = if type(cds) == "table" then cds[id] else nil
			if isNumber(at) then
				endsAt, duration = at, if t then t.cooldown else nil
			end
		end
		if endsAt == nil then
			return 0, 0
		end
		local left = endsAt - now()
		if not isNumber(left) or left <= 0 then
			return 0, 0
		end
		if not isNumber(duration) or (duration :: number) <= 0 then
			return 0, left -- unknown length: a ring cannot be drawn, the seconds still count
		end
		return math.clamp(left / (duration :: number), 0, 1), left
	end

	-- (active, seconds left).
	function self.shield(): (boolean, number)
		local untilAt: number?
		if eventShield then
			untilAt = eventShield.endsAt
		elseif isNumber(pvp.shieldUntil) then
			untilAt = pvp.shieldUntil
		else
			untilAt = attrShield
		end
		if untilAt == nil then
			return false, 0
		end
		local left = untilAt - now()
		if not isNumber(left) or left <= 0 then
			return false, 0
		end
		return true, left
	end

	function self.safeZone(): string?
		if eventZone then
			return eventZone.zone
		end
		local z = pvp.safeZone
		return if type(z) == "string" and z ~= "" then z else nil
	end

	-- Commands -----------------------------------------------------------------------

	local function dispatch(action: string, ...: any): (boolean, string?)
		if send == nil then
			return false, "offline"
		end
		local ok, reason = send(action, ...)
		if ok == false then
			return false, if type(reason) == "string" then reason else "refused"
		end
		return true, nil
	end

	-- Equip `id` into the hand slot (nil = unequip). The server answers with a fresh snapshot.
	function self.equip(id: string?): (boolean, string?)
		return dispatch(PvpClient.EQUIP_ACTION, id)
	end

	-- Use the equipped item `id`; `targetUserId` for targeted items, `aim` (a Vector3) for aimed / placed ones.
	function self.use(id: string, targetUserId: number?, aim: any?): (boolean, string?)
		return dispatch(PvpClient.USE_ACTION, id, targetUserId, aim)
	end

	-- Tap on a slot: equip it; tapping the equipped slot uses it (no target).
	function self.activate(id: string): (boolean, string?)
		if self.equipped() == id then
			return self.use(id, nil, nil)
		end
		return self.equip(id)
	end

	-- Number key 1..9: equip that slot; the key of the equipped slot unequips (like the Roblox backpack).
	function self.pressKey(n: number): (boolean, string?)
		local slot = self.hotbarSlots()[n]
		if slot == nil or n > PvpClient.MAX_KEYBINDS then
			return false, "no slot"
		end
		if self.equipped() == slot.id then
			return self.equip(nil)
		end
		return self.equip(slot.id)
	end

	return self
end

return PvpClient
