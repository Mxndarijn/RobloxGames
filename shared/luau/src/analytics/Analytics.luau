--!strict
--[[
	Analytics: a safe front for Roblox AnalyticsService events, server only.

		local tracker = Analytics.new({
			sink = AnalyticsSink.new(AnalyticsService),   -- or Analytics.recorder() in specs / Studio
			now = os.clock,
			newId = function() return HttpService:GenerateGUID(false) end,
			playerCount = function() return #Players:GetPlayers() end,
			catalog = {
				onboarding = { "Joined", "ClaimedPlot", "FirstBuy" },
				funnels = { Shop = { "Opened", "Viewed", "Bought" } },
				events = { "Stole", "Merged" },
				currencies = { "Coins" },
				progressions = { "Rebirth" },
			},
		})
		tracker:onboarding(player, "ClaimedPlot")
		tracker:source(player, "Coins", 25, balance, "Gameplay", "Income", nil, true) -- batched
		RunService.Heartbeat:Connect(function() tracker:update() end)
		Players.PlayerRemoving:Connect(function(p) tracker:forget(p) end)        -- flushes first

	What it adds on top of AnalyticsService:
	- A catalog. Every onboarding step, funnel step, event name, currency and progression path is declared up
	  front, so names stay stable between versions and stay under Roblox's caps (100 event names, 10 funnels,
	  10 currencies). Step numbers come from the order in the catalog.
	- A rate budget. Roblox allows 120 + 20 * players requests per minute per server; the tracker spends at most
	  `budgetShare` of that and drops (and counts) what does not fit.
	- Batching. `count` and economy calls with `batch = true` add up per player and per name / fields, and go out
	  once every `batchSeconds` (and on `flush` / `forget`), so frequent things such as income ticks cost one
	  request a minute instead of one a second. A batch that does not fit the budget waits for the next update.
	- Once per session onboarding steps (Roblox ignores repeats anyway, but they still cost budget).
	- Funnel sessions: `startFunnel` makes a fresh session id and logs step 1; `funnelStep` logs a later step in
	  the open session.
	- Custom fields as a plain list: `{ "Tier - Rare", "Rank - 3" }` becomes CustomField01 / 02 / 03.

	Expected failures (unknown name, bad amount, over budget) return `(false, reason)` and call `onDrop`; nothing
	here throws during play. Only a bad setup errors.
]]

export type Fields = { string }
export type FieldMap = { [string]: string }

export type Sink = {
	custom: (key: any, name: string, value: number?, fields: FieldMap?) -> (),
	economy: (
		key: any,
		flow: string,
		currency: string,
		amount: number,
		balance: number,
		transaction: string,
		sku: string?,
		fields: FieldMap?
	) -> (),
	funnel: (key: any, funnel: string, sessionId: string, step: number, stepName: string, fields: FieldMap?) -> (),
	onboarding: (key: any, step: number, stepName: string, fields: FieldMap?) -> (),
	progression: (key: any, path: string, status: string, level: number, levelName: string?, fields: FieldMap?) -> (),
}

export type Catalog = {
	onboarding: { string }?,
	funnels: { [string]: { string } }?,
	events: { string }?,
	currencies: { string }?,
	progressions: { string }?,
}

export type Options = {
	sink: Sink,
	catalog: Catalog,
	now: () -> number,
	newId: (() -> string)?,
	playerCount: (() -> number)?,
	batchSeconds: number?,
	budgetShare: number?,
	onDrop: ((reason: string, kind: string, name: string) -> ())?,
}

export type Stats = { sent: number, dropped: number, reasons: { [string]: number } }

export type Tracker = {
	onboarding: (self: Tracker, key: any, stepName: string, fields: Fields?) -> (boolean, string?),
	startFunnel: (self: Tracker, key: any, funnel: string, fields: Fields?) -> (boolean, string?),
	funnelStep: (self: Tracker, key: any, funnel: string, stepName: string, fields: Fields?) -> (boolean, string?),
	event: (self: Tracker, key: any, name: string, value: number?, fields: Fields?) -> (boolean, string?),
	count: (self: Tracker, key: any, name: string, amount: number?, fields: Fields?) -> (boolean, string?),
	source: (
		self: Tracker,
		key: any,
		currency: string,
		amount: number,
		balance: number,
		transaction: string,
		sku: string?,
		fields: Fields?,
		batch: boolean?
	) -> (boolean, string?),
	spend: (
		self: Tracker,
		key: any,
		currency: string,
		amount: number,
		balance: number,
		transaction: string,
		sku: string?,
		fields: Fields?,
		batch: boolean?
	) -> (boolean, string?),
	progression: (
		self: Tracker,
		key: any,
		path: string,
		status: string,
		level: number,
		levelName: string?,
		fields: Fields?
	) -> (boolean, string?),
	update: (self: Tracker, now: number?) -> (),
	flush: (self: Tracker, key: any) -> (),
	forget: (self: Tracker, key: any) -> (),
	stats: (self: Tracker) -> Stats,
}

local FIELD_KEYS = table.freeze({ "CustomField01", "CustomField02", "CustomField03" })
local STATUSES = table.freeze({ Start = true, Complete = true, Fail = true, Custom = true })
local MAX_FUNNELS = 10
local MAX_EVENTS = 100
local MAX_CURRENCIES = 10
local MAX_STEPS = 100

local Analytics = {}
Analytics.__index = Analytics

-- Turns a list of up to three strings into AnalyticsService custom fields. Extra entries are ignored.
function Analytics.fields(list: Fields?): FieldMap?
	if list == nil or #list == 0 then
		return nil
	end
	local out: FieldMap = {}
	for i = 1, math.min(#list, #FIELD_KEYS) do
		out[FIELD_KEYS[i]] = tostring(list[i])
	end
	return out
end

local function toSet(list: { string }?, cap: number, what: string): { [string]: number }
	local set: { [string]: number } = {}
	if list == nil then
		return set
	end
	if #list > cap then
		error(`Analytics.new: at most {cap} {what}, got {#list}`, 3)
	end
	for i, name in list do
		if type(name) ~= "string" or name == "" then
			error(`Analytics.new: {what} entry {i} must be a non-empty string`, 3)
		end
		if set[name] then
			error(`Analytics.new: {what} entry {name} is listed twice`, 3)
		end
		set[name] = i
	end
	return set
end

local function validAmount(n: any): boolean
	return type(n) == "number" and n == n and n > 0 and n < math.huge
end

local function fieldsKey(list: Fields?): string
	if list == nil then
		return ""
	end
	local parts = {}
	for i = 1, math.min(#list, #FIELD_KEYS) do
		parts[i] = tostring(list[i])
	end
	return table.concat(parts, "\0")
end

function Analytics.new(options: Options): Tracker
	if type(options) ~= "table" or type(options.sink) ~= "table" or type(options.now) ~= "function" then
		error("Analytics.new: options need sink and now", 2)
	end
	local catalog = options.catalog or {}
	local funnels: { [string]: { [string]: number } } = {}
	local funnelCount = 0
	for name, steps in catalog.funnels or {} do
		funnelCount += 1
		funnels[name] = toSet(steps, MAX_STEPS, `{name} funnel steps`)
	end
	-- The onboarding funnel is one of Roblox's 10 funnels.
	local onboardingSteps = toSet(catalog.onboarding, MAX_STEPS, "onboarding steps")
	if funnelCount + (if catalog.onboarding then 1 else 0) > MAX_FUNNELS then
		error(`Analytics.new: at most {MAX_FUNNELS} funnels including onboarding`, 2)
	end
	local batchSeconds = options.batchSeconds or 60
	local share = options.budgetShare or 0.8
	if batchSeconds <= 0 or share <= 0 or share > 1 then
		error("Analytics.new: batchSeconds must be > 0 and budgetShare in (0, 1]", 2)
	end
	local idCounter = 0
	local self = setmetatable({
		sink = options.sink,
		now = options.now,
		newId = options.newId or function()
			idCounter += 1
			return `f{idCounter}`
		end,
		playerCount = options.playerCount or function()
			return 1
		end,
		onDrop = options.onDrop,
		batchSeconds = batchSeconds,
		share = share,
		onboardingSteps = onboardingSteps,
		funnels = funnels,
		events = toSet(catalog.events, MAX_EVENTS, "events"),
		currencies = toSet(catalog.currencies, MAX_CURRENCIES, "currencies"),
		progressions = toSet(catalog.progressions, MAX_EVENTS, "progressions"),
		players = {},
		tokens = nil :: number?,
		refilledAt = 0,
		counts = { sent = 0, dropped = 0, reasons = {} },
	}, Analytics)
	return (self :: any) :: Tracker
end

type Batch = {
	kind: string,
	name: string,
	amount: number,
	balance: number?,
	transaction: string?,
	sku: string?,
	fields: Fields?,
	since: number,
}

type PlayerState = {
	onboarded: { [string]: boolean },
	sessions: { [string]: string },
	batches: { [string]: Batch },
}

local function state(self: any, key: any): PlayerState
	local s = self.players[key]
	if s == nil then
		s = { onboarded = {}, sessions = {}, batches = {} }
		self.players[key] = s
	end
	return s
end

local function drop(self: any, reason: string, kind: string, name: string): (boolean, string?)
	local counts = self.counts
	counts.dropped += 1
	counts.reasons[reason] = (counts.reasons[reason] or 0) + 1
	if self.onDrop then
		self.onDrop(reason, kind, name)
	end
	return false, reason
end

-- Takes one request from the per-minute budget. Refills smoothly at the allowed rate for the current player count.
local function spendToken(self: any): boolean
	local now = self.now()
	local perMinute = (120 + 20 * math.max(0, self.playerCount())) * self.share
	if self.tokens == nil then
		self.tokens = perMinute
		self.refilledAt = now
	end
	local elapsed = math.max(0, now - self.refilledAt)
	self.tokens = math.min(perMinute, self.tokens + elapsed * perMinute / 60)
	self.refilledAt = now
	if self.tokens < 1 then
		return false
	end
	self.tokens -= 1
	return true
end

local function send(self: any, kind: string, name: string, call: () -> ()): (boolean, string?)
	if not spendToken(self) then
		return drop(self, "OverBudget", kind, name)
	end
	self.counts.sent += 1
	call()
	return true
end

function Analytics.onboarding(self: any, key: any, stepName: string, fields: Fields?): (boolean, string?)
	local step = self.onboardingSteps[stepName]
	if step == nil then
		return drop(self, "UnknownStep", "onboarding", tostring(stepName))
	end
	local s = state(self, key)
	if s.onboarded[stepName] then
		return false, "Repeat"
	end
	local ok, reason = send(self, "onboarding", stepName, function()
		self.sink.onboarding(key, step, stepName, Analytics.fields(fields))
	end)
	if ok then
		s.onboarded[stepName] = true
	end
	return ok, reason
end

function Analytics.startFunnel(self: any, key: any, funnel: string, fields: Fields?): (boolean, string?)
	local steps = self.funnels[funnel]
	if steps == nil then
		return drop(self, "UnknownFunnel", "funnel", tostring(funnel))
	end
	local first: string? = nil
	for name, index in steps do
		if index == 1 then
			first = name
		end
	end
	if first == nil then
		return drop(self, "UnknownStep", "funnel", funnel)
	end
	local sessionId = self.newId()
	state(self, key).sessions[funnel] = sessionId
	local stepName: string = first
	return send(self, "funnel", funnel, function()
		self.sink.funnel(key, funnel, sessionId, 1, stepName, Analytics.fields(fields))
	end)
end

function Analytics.funnelStep(
	self: any,
	key: any,
	funnel: string,
	stepName: string,
	fields: Fields?
): (boolean, string?)
	local steps = self.funnels[funnel]
	if steps == nil then
		return drop(self, "UnknownFunnel", "funnel", tostring(funnel))
	end
	local step = steps[stepName]
	if step == nil then
		return drop(self, "UnknownStep", "funnel", `{funnel}.{tostring(stepName)}`)
	end
	local sessionId = state(self, key).sessions[funnel]
	if sessionId == nil then
		return drop(self, "NoSession", "funnel", `{funnel}.{stepName}`)
	end
	return send(self, "funnel", funnel, function()
		self.sink.funnel(key, funnel, sessionId, step, stepName, Analytics.fields(fields))
	end)
end

function Analytics.event(self: any, key: any, name: string, value: number?, fields: Fields?): (boolean, string?)
	if self.events[name] == nil then
		return drop(self, "UnknownEvent", "custom", tostring(name))
	end
	if value ~= nil and (type(value) ~= "number" or value ~= value or math.abs(value) == math.huge) then
		return drop(self, "BadValue", "custom", name)
	end
	return send(self, "custom", name, function()
		self.sink.custom(key, name, value, Analytics.fields(fields))
	end)
end

-- Adds `amount` (default 1) to a batched custom event; sent as one event with the summed value per batch window.
function Analytics.count(self: any, key: any, name: string, amount: number?, fields: Fields?): (boolean, string?)
	if self.events[name] == nil then
		return drop(self, "UnknownEvent", "custom", tostring(name))
	end
	local n = amount or 1
	if not validAmount(n) then
		return drop(self, "BadValue", "custom", name)
	end
	local s = state(self, key)
	local id = `c\0{name}\0{fieldsKey(fields)}`
	local batch = s.batches[id]
	if batch == nil then
		s.batches[id] = { kind = "custom", name = name, amount = n, fields = fields, since = self.now() }
	else
		batch.amount += n
	end
	return true
end

local function economy(
	self: any,
	flow: string,
	key: any,
	currency: string,
	amount: number,
	balance: number,
	transaction: string,
	sku: string?,
	fields: Fields?,
	batch: boolean?
): (boolean, string?)
	if self.currencies[currency] == nil then
		return drop(self, "UnknownCurrency", "economy", tostring(currency))
	end
	if not validAmount(amount) then
		return drop(self, "BadValue", "economy", currency)
	end
	if type(balance) ~= "number" or balance ~= balance or math.abs(balance) == math.huge then
		return drop(self, "BadValue", "economy", currency)
	end
	if type(transaction) ~= "string" or transaction == "" then
		return drop(self, "BadValue", "economy", currency)
	end
	if batch then
		local s = state(self, key)
		local id = `{flow}\0{currency}\0{transaction}\0{sku or ""}\0{fieldsKey(fields)}`
		local pending = s.batches[id]
		if pending == nil then
			s.batches[id] = {
				kind = flow,
				name = currency,
				amount = amount,
				balance = balance,
				transaction = transaction,
				sku = sku,
				fields = fields,
				since = self.now(),
			}
		else
			pending.amount += amount
			pending.balance = balance
		end
		return true
	end
	return send(self, "economy", currency, function()
		self.sink.economy(key, flow, currency, amount, balance, transaction, sku, Analytics.fields(fields))
	end)
end

-- Coins in. `amount` is positive; `balance` is the balance after the change.
function Analytics.source(
	self: any,
	key: any,
	currency: string,
	amount: number,
	balance: number,
	transaction: string,
	sku: string?,
	fields: Fields?,
	batch: boolean?
): (boolean, string?)
	return economy(self, "Source", key, currency, amount, balance, transaction, sku, fields, batch)
end

-- Coins out. `amount` is positive (the cost); `balance` is the balance after the change.
function Analytics.spend(
	self: any,
	key: any,
	currency: string,
	amount: number,
	balance: number,
	transaction: string,
	sku: string?,
	fields: Fields?,
	batch: boolean?
): (boolean, string?)
	return economy(self, "Sink", key, currency, amount, balance, transaction, sku, fields, batch)
end

function Analytics.progression(
	self: any,
	key: any,
	path: string,
	status: string,
	level: number,
	levelName: string?,
	fields: Fields?
): (boolean, string?)
	if self.progressions[path] == nil then
		return drop(self, "UnknownProgression", "progression", tostring(path))
	end
	if not STATUSES[status] then
		return drop(self, "BadStatus", "progression", path)
	end
	if type(level) ~= "number" or level ~= level or level < 0 or level == math.huge then
		return drop(self, "BadValue", "progression", path)
	end
	return send(self, "progression", path, function()
		self.sink.progression(key, path, status, level, levelName, Analytics.fields(fields))
	end)
end

-- Sends one batch. Returns false when the budget is empty so the batch can wait.
local function sendBatch(self: any, key: any, batch: Batch): boolean
	if not spendToken(self) then
		return false
	end
	self.counts.sent += 1
	local fields = Analytics.fields(batch.fields)
	if batch.kind == "custom" then
		self.sink.custom(key, batch.name, batch.amount, fields)
	else
		self.sink.economy(
			key,
			batch.kind,
			batch.name,
			batch.amount,
			batch.balance :: number,
			batch.transaction :: string,
			batch.sku,
			fields
		)
	end
	return true
end

local function flushPlayer(self: any, key: any, s: PlayerState, now: number?)
	for id, batch in s.batches do
		if now == nil or now - batch.since >= self.batchSeconds then
			if sendBatch(self, key, batch) then
				s.batches[id] = nil
			elseif now == nil then
				s.batches[id] = nil
				drop(self, "OverBudget", batch.kind, batch.name)
			end
		end
	end
end

-- Sends the batches whose window has passed. Call it often (every Heartbeat is fine; it is cheap).
function Analytics.update(self: any, now: number?)
	local t = now or self.now()
	for key, s in self.players do
		flushPlayer(self, key, s, t)
	end
end

-- Sends every pending batch of `key` now (what does not fit the budget is dropped and counted).
function Analytics.flush(self: any, key: any)
	local s = self.players[key]
	if s then
		flushPlayer(self, key, s, nil)
	end
end

-- Flushes and then forgets everything about `key` (call on PlayerRemoving).
function Analytics.forget(self: any, key: any)
	self:flush(key)
	self.players[key] = nil
end

function Analytics.stats(self: any): Stats
	return { sent = self.counts.sent, dropped = self.counts.dropped, reasons = table.clone(self.counts.reasons) }
end

export type Recorded = { kind: string, key: any, args: { any } }
export type Recorder = Sink & { events: { Recorded }, limit: number }

-- A sink that keeps the last `limit` calls in `events` (newest last). For specs, and for Studio, where Roblox
-- drops real AnalyticsService events.
function Analytics.recorder(limit: number?): Recorder
	local rec = { events = {}, limit = limit or 500 }
	local function push(kind: string, key: any, ...: any)
		table.insert(rec.events, { kind = kind, key = key, args = table.pack(...) })
		if #rec.events > rec.limit then
			table.remove(rec.events, 1)
		end
	end
	function rec.custom(key, ...)
		push("custom", key, ...)
	end
	function rec.economy(key, ...)
		push("economy", key, ...)
	end
	function rec.funnel(key, ...)
		push("funnel", key, ...)
	end
	function rec.onboarding(key, ...)
		push("onboarding", key, ...)
	end
	function rec.progression(key, ...)
		push("progression", key, ...)
	end
	return (rec :: any) :: Recorder
end

return table.freeze(Analytics)
