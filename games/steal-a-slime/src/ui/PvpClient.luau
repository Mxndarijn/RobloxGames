--!strict
--[[
	PvpClient (FEATURES.PvP, docs/PVP-CLIENT.md)

	The ONE client adapter for the v22 PvP contract (pvp-update.md "PvP remote contract"). Pure: no Roblox
	APIs, no Instances; everything Roblox-side is injected (`now`, `send`, `catalog`), so Lune tests drive it
	(tests/ui/PvpClient.spec.luau). The views (PvpHud) only read its queries. The client never decides an
	outcome: it shows what the server last said and forwards taps as Request actions.

	Reads (all optional, all `any`: the server owns the shapes):
	  :applyState(state)   state.pvp = { rank, owned = {[id]=true}, best = {Knockback=id?, Trap=id?, Blaster=id?},
	                       equipped = id?, cooldowns = {[id]=endsAt}, shieldUntil = number?, safeZone = string? };
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

	Catalog: Config.PVP_TOOLS (Gojo's PR A) when it exists, else STUB_CATALOG (same ids). Item data is read from
	the catalog only; nothing per-item is hardcoded outside the stub. The server's data always wins; the stub exists
	for tests and the Studio preview (PcwPvpStub).
	Field names follow CONTRACT.md §26.1: id, name, line, tier, rebirths, cooldown, kind, cosmetic, push, control,
	slowPercent, slowSeconds, radius, count, rearm. NOTE: #241's Config currently still names slow (0.3) / traps
	(and no rearm); the stub follows §26.1. effectSlowPercent / effectCount below read both spellings.

	BASE_SLAP: display-only rank 0 of the Knockback line ("Base slap", free). It is not a PVP_TOOLS entry and
	NOT a hotbar slot: the SLAP! button stays the way to slap. The shop (PR 2) lists it as the line's first rank.
]]

local Shared = if script then game:GetService("ReplicatedStorage"):WaitForChild("Shared") :: any else nil
local Config = if Shared then require(Shared:WaitForChild("Config")) else require("../shared/Config")

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
	catalog: any?, -- list or map of Tool; default Config.PVP_TOOLS, else STUB_CATALOG
	flag: boolean?, -- override Config.FEATURES.PvP (enabled() only; nothing is built here either way)
}

local PvpClient = {}

PvpClient.EQUIP_ACTION = "EquipPvpItem"
PvpClient.USE_ACTION = "UsePvpItem"
PvpClient.EVENT_NAME = "PvpEvent" -- the fallback of Constants.PVP_EVENT
PvpClient.MAX_KEYBINDS = 9
PvpClient.EVENT_GRACE = 1 -- s: a Cooldown event younger than this survives a snapshot that omits its id
PvpClient.LINES = table.freeze({ "Knockback", "Trap", "Blaster" })

local function tool(
	id: string,
	name: string,
	line: string,
	tier: number,
	rebirths: number,
	cooldown: number,
	extra: { [string]: any }
): Tool
	local t: any = {
		id = id,
		name = name,
		line = line,
		tier = tier,
		rebirths = rebirths,
		cooldown = cooldown,
		kind = if line == "Fun" then "fun" else "tool",
		cosmetic = false,
	}
	for key, value in extra do
		t[key] = value
	end
	return table.freeze(t)
end

-- Stub of the ladder for tests / the Studio preview, with the CONTRACT.md §26.1 field names (ids are save keys,
-- never renamed): Trap count / control / radius / rearm (cooldown = rearm); Blaster slowPercent (a percent number)
-- / slowSeconds / cooldown; Knockback push / cooldown 1.5. #241's Config still says slow (0.3) / traps; see header.
PvpClient.STUB_CATALOG = table.freeze({
	tool("KnockGlove1", "Bonk Glove", "Knockback", 1, 1, 1.5, { push = 5 }),
	tool("KnockGlove2", "Bounce Glove", "Knockback", 2, 5, 1.5, { push = 6 }),
	tool("KnockGlove3", "Boom Glove", "Knockback", 3, 8, 1.5, { push = 7 }),
	tool("KnockGlove4", "Thunder Glove", "Knockback", 4, 12, 1.5, { push = 7.5 }),
	tool("KnockGlove5", "Royal Glove", "Knockback", 5, 20, 1.5, { push = 8 }),
	tool("GooTrap1", "Goo Puddle", "Trap", 1, 3, 30, { count = 1, control = 1, radius = 3, rearm = 30 }),
	tool("GooTrap2", "Sticky Trap", "Trap", 2, 6, 25, { count = 2, control = 1.5, radius = 3.5, rearm = 25 }),
	tool("GooTrap3", "Mega Trap", "Trap", 3, 10, 20, { count = 2, control = 2, radius = 4, rearm = 20 }),
	tool("GooBlaster1", "Goo Squirter", "Blaster", 1, 7, 12, { slowPercent = 30, slowSeconds = 2 }),
	tool("GooBlaster2", "Goo Blaster", "Blaster", 2, 12, 11, { slowPercent = 40, slowSeconds = 2.5 }),
	tool("GooBlaster3", "Goo Cannon", "Blaster", 3, 20, 10, { slowPercent = 50, slowSeconds = 3 }),
	tool("FunConfetti", "Confetti Popper", "Fun", 1, 0, 5, { cosmetic = true }),
	tool("FunBalloon", "Goo Balloon", "Fun", 1, 1, 3, { cosmetic = true }),
	tool("FunBubbles", "Bubble Wand", "Fun", 1, 3, 4, { cosmetic = true }),
	tool("FunBouncePad", "Bounce Pad", "Fun", 1, 5, 10, { control = 1.2 }),
	tool("FunSqueaky", "Squeaky Hammer", "Fun", 1, 6, 3, {}),
	tool("FunHatLauncher", "Slime Hat Launcher", "Fun", 1, 7, 8, { cosmetic = true }),
	tool("FunDanceBomb", "Dance Bomb", "Fun", 1, 8, 45, { control = 2 }),
	tool("FunFireworks", "Goo Fireworks", "Fun", 1, 10, 20, { cosmetic = true }),
}) :: { Tool }

-- Rank 0 of the Knockback line, for the shop only (PR 2). Not in the catalog, not a hotbar slot, not buyable.
PvpClient.BASE_SLAP = table.freeze({
	id = "BaseSlap",
	name = "Base slap",
	line = "Knockback",
	tier = 0,
	rebirths = 0,
	free = true,
})

-- Effect params for UI text, tolerating #241's current names and §26.1's: slowPercent (30) or slow (0.3);
-- count or traps. nil when the tool has neither.
function PvpClient.effectSlowPercent(t: any): number?
	if type(t.slowPercent) == "number" then
		return t.slowPercent
	end
	return if type(t.slow) == "number" then t.slow * 100 else nil
end
function PvpClient.effectCount(t: any): number?
	return t.count or t.traps
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

-- The server's catalog when it ships one (Config.PVP_TOOLS), else the stub.
function PvpClient.defaultCatalog(): { Tool }
	local real = (Config :: any).PVP_TOOLS
	if type(real) == "table" and next(real) ~= nil then
		return (normalize(real))
	end
	return PvpClient.STUB_CATALOG
end

-- Locks: items the player can buy / use at `rank` rebirths (rebirths <= rank), ladder order.
function PvpClient.unlockedAt(rank: number, catalog: any?): { Tool }
	local list = normalize(catalog or PvpClient.defaultCatalog())
	local out = {}
	for _, t in list do
		if isNumber(rank) and t.rebirths <= rank then
			table.insert(out, t)
		end
	end
	return out
end

function PvpClient.isUnlocked(id: string, rank: number, catalog: any?): boolean
	local _, byId = normalize(catalog or PvpClient.defaultCatalog())
	local t = byId[id]
	return t ~= nil and isNumber(rank) and t.rebirths <= rank
end

-- A plausible state.pvp for `rank` (tests, Studio preview): the best unlocked tool per line owned, every
-- unlocked fun item, the best knockback glove equipped, nothing on cooldown, no shield, no zone.
function PvpClient.stubState(rank: number, catalog: any?): { [string]: any }
	local unlocked = PvpClient.unlockedAt(rank, catalog)
	local owned: { [string]: boolean } = {}
	local best: { [string]: string } = {}
	for _, t in unlocked do
		owned[t.id] = true
		if t.line ~= "Fun" then
			best[t.line] = t.id -- ladder order: the last (highest tier) wins
		end
	end
	return {
		rank = rank,
		owned = owned,
		best = best,
		equipped = best.Knockback,
		cooldowns = {},
		shieldUntil = nil,
		safeZone = nil,
	}
end

function PvpClient.new(opts: Options?)
	local o: Options = opts or {}
	local now: () -> number = o.now or function()
		return 0
	end
	local send = o.send
	local list, byId = normalize(o.catalog or PvpClient.defaultCatalog())

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

	-- The best owned tool of a line: the snapshot's `best` first, else the highest owned tier of the catalog.
	function self.best(line: string): string?
		local b = pvp.best
		local id = if type(b) == "table" then b[line] else nil
		if type(id) == "string" and byId[id] ~= nil and byId[id].line == line then
			return id
		end
		local found: Tool? = nil
		for _, t in list do
			if t.line == line and self.owns(t.id) and (found == nil or t.tier > found.tier) then
				found = t
			end
		end
		return if found then found.id else nil
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
