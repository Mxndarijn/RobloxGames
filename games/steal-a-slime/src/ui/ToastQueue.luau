--!strict
--[[
	ToastQueue

	Which toasts show, in what order (v18). Pure (tests/ui/ToastQueue.spec.luau);
	Toasts.luau renders what `step` returns.

	- Merge: a push with the same kind and the same text (cash amounts aside)
	  as a live entry folds into it: "+$25" x5 -> "+$125 (x5)", "Not enough
	  cash" x3 -> "Not enough cash (x3)". A merge refreshes the entry's life.
	- Priority: 3 rare / badge / away / steal alerts, 2 other bad news, 1 routine.
	  Higher priority shows first and wins the visible slots.
	- Cap: at most `max` visible, and (given a `fit`) only as many as fit the
  toast box's height, in priority order; the rest wait. Queued routine toasts that
	  never got a slot within STALE seconds are dropped.
	- Menus: nothing shows while a menu is open (like the HUD banners,
	  MenuState.bannersVisible); entries neither age nor go stale meanwhile.
]]

local Format = if script then require(script.Parent.Format) else require("./Format")

export type Entry = {
	id: number,
	kind: string,
	priority: number,
	text: string, -- as displayed (with the merged amount / count)
	base: string, -- the first push's text
	template: string?, -- base with the cash amount cut out
	amount: number,
	count: number,
	born: number,
	shownAt: number?,
	itemId: string?, -- the first non-nil itemId pushed into this entry
}
-- Room for the stack: `height` of one entry's toast, `gap` between toasts, `room` px in total.
export type Fit = { room: number, gap: number, height: (Entry) -> number }
export type Queue = {
	push: (text: string, kind: string?, now: number, itemId: string?) -> (Entry, boolean),
	step: (now: number, menuOpen: boolean?, fit: Fit?) -> { Entry },
	size: () -> number,
}

local ToastQueue = {}

ToastQueue.MAX = 4
ToastQueue.PENDING_MAX = 12
ToastQueue.STALE = 6 -- s a routine toast may wait for a free slot
ToastQueue.LIFETIME = 3
ToastQueue.LIFETIMES = table.freeze({ rare = 7, badge = 6, away = 9 })

local MULTIPLIERS: { [string]: number } = { K = 1e3, M = 1e6, B = 1e9, T = 1e12 }

function ToastQueue.lifetime(kind: string): number
	return ToastQueue.LIFETIMES[kind] or ToastQueue.LIFETIME
end

function ToastQueue.priority(text: string, kind: string?): number
	if kind == "rare" or kind == "badge" or kind == "away" then
		return 3
	end
	if kind == "bad" then
		local lower = string.lower(text)
		if
			string.find(lower, "stol", 1, true)
			or string.find(lower, "steal", 1, true)
			or string.find(lower, "thief", 1, true)
		then
			return 3
		end
		return 2
	end
	return 1
end

-- "You earned +$25!" -> "You earned +$\1!", 25. (nil, 0) without a "+$amount".
function ToastQueue.split(text: string): (string?, number)
	local head, number, suffix, tail = string.match(text, "^(.-%+%$)(%d+%.?%d*)([KMBT]?)(.*)$")
	if not head then
		return nil, 0
	end
	return head .. "\1" .. tail, (tonumber(number) or 0) * (MULTIPLIERS[suffix] or 1)
end

local function render(entry: Entry): string
	local text = entry.base
	if entry.template then
		text = string.gsub(entry.template, "\1", Format.shortNumber(entry.amount))
	end
	if entry.count > 1 then
		text ..= ` (x{entry.count})`
	end
	return text
end

function ToastQueue.new(max: number?): Queue
	local cap = max or ToastQueue.MAX
	local entries: { Entry } = {}
	local nextId = 0
	local lastNow: number? = nil

	local self = {} :: Queue

	local function drop(entry: Entry)
		local index = table.find(entries, entry)
		if index then
			table.remove(entries, index)
		end
	end

	-- Returns the entry and whether it merged into an older one.
	function self.push(text: string, kind: string?, now: number, itemId: string?): (Entry, boolean)
		text = tostring(text)
		local k = kind or "info"
		local template, amount = ToastQueue.split(text)
		for _, entry in entries do
			if entry.kind == k and entry.template == template and (template ~= nil or entry.base == text) then
				entry.amount += amount
				entry.count += 1
				entry.text = render(entry)
				entry.shownAt = if entry.shownAt then now else nil
				entry.born = now
				entry.itemId = entry.itemId or itemId
				return entry, true
			end
		end
		nextId += 1
		local entry: Entry = {
			id = nextId,
			kind = k,
			priority = ToastQueue.priority(text, k),
			text = text,
			base = text,
			template = template,
			amount = amount,
			count = 1,
			born = now,
			shownAt = nil,
			itemId = itemId,
		}
		table.insert(entries, entry)
		while #entries > ToastQueue.PENDING_MAX do
			-- Over the backlog: lose the oldest lowest-priority entry.
			local worst = entries[1]
			for _, e in entries do
				if e.priority < worst.priority then
					worst = e
				end
			end
			drop(worst)
		end
		return entry, false
	end

	-- Advance to `now`; the entries to draw, highest priority first (then oldest).
	function self.step(now: number, menuOpen: boolean?, fit: Fit?): { Entry }
		local dt = if lastNow then math.max(0, now - lastNow) else 0
		lastNow = now
		if menuOpen then
			-- Time stands still behind a menu.
			for _, e in entries do
				e.born += dt
				if e.shownAt then
					e.shownAt += dt
				end
			end
			return {}
		end
		for i = #entries, 1, -1 do
			local e = entries[i]
			local shownAt = e.shownAt
			local expired = if shownAt
				then now - shownAt >= ToastQueue.lifetime(e.kind)
				else e.priority == 1 and now - e.born >= ToastQueue.STALE
			if expired then
				table.remove(entries, i)
			end
		end
		local order = table.clone(entries)
		table.sort(order, function(a, b)
			if a.priority ~= b.priority then
				return a.priority > b.priority
			end
			return a.id < b.id
		end)
		local visible = {}
		local used = 0
		for i = 1, math.min(cap, #order) do
			local e = order[i]
			if fit then
				used += fit.height(e) + if i > 1 then fit.gap else 0
				if used > fit.room then
					break -- this one and the lower ones wait for room
				end
			end
			e.shownAt = e.shownAt or now
			table.insert(visible, e)
		end
		return visible
	end

	function self.size(): number
		return #entries
	end

	return self
end

return table.freeze(ToastQueue)
