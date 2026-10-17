--!strict
--[[
	PopupQueue

	One modal at a time (v18). Pure (tests/ui/PopupQueue.spec.luau);
	init.client opens what `update` returns.

	The tutorial card (Tutorial.fromState(state) ~= nil) blocks every queued
	popup: a new player no longer gets the daily reward on top of step 1
	(v15 playtest). The daily popup is queued on its availability edge
	(Daily.shouldAutoOpen), dropped again when the claim goes away, and opens
	once the tutorial is finished. Opening it by hand (HUD Daily) is not
	queued. The welcome-back card (State.welcomeBack, once per join) queues the same
	way and goes first; while it is on screen (`busy`) the daily popup waits.
]]

local Daily = if script then require(script.Parent.Daily) else require("./Daily")
local Tutorial = if script then require(script.Parent.Tutorial) else require("./Tutorial")

export type Name = "Welcome" | "Daily"
export type Queue = {
	enqueue: (name: Name) -> (),
	remove: (name: Name) -> (),
	has: (name: Name) -> boolean,
	queued: () -> { Name },
	blocker: (state: any) -> string?,
	update: (state: any, busy: boolean?) -> Name?,
}

local PopupQueue = {}

-- Queued popups open in this order.
PopupQueue.ORDER = table.freeze({ "Welcome", "Daily" } :: { Name })

local function dailyAvailable(state: any): boolean
	return type(state) == "table" and type(state.daily) == "table" and state.daily.available == true
end

-- What keeps queued popups closed right now ("Tutorial"), nil when free.
function PopupQueue.blocker(state: any): string?
	return if Tutorial.fromState(state) ~= nil then "Tutorial" else nil
end

function PopupQueue.new(): Queue
	local pending: { [string]: boolean } = {}
	local dailyWas: boolean? = nil
	local welcomeWas = false

	local self = {} :: Queue

	function self.enqueue(name: Name)
		pending[name] = true
	end

	function self.remove(name: Name)
		pending[name] = nil
	end

	function self.has(name: Name): boolean
		return pending[name] == true
	end

	function self.queued(): { Name }
		local out = {}
		for _, name in PopupQueue.ORDER do
			if pending[name] then
				table.insert(out, name)
			end
		end
		return out
	end

	self.blocker = PopupQueue.blocker

	-- Feed every State snapshot; returns the popup to open now (taken off
	-- the queue), or nil. `busy` = a queued popup is on screen: nothing else opens
	-- over it, the next one follows once it closes.
	function self.update(state: any, busy: boolean?): Name?
		local welcome = type(state) == "table" and type(state.welcomeBack) == "table"
		if welcome and not welcomeWas then
			pending.Welcome = true
		end
		welcomeWas = welcome
		local available = dailyAvailable(state)
		if Daily.shouldAutoOpen(dailyWas, available) then
			pending.Daily = true
		elseif not available then
			pending.Daily = nil
		end
		dailyWas = available

		if busy or PopupQueue.blocker(state) ~= nil then
			return nil
		end
		for _, name in PopupQueue.ORDER do
			if pending[name] then
				pending[name] = nil
				return name
			end
		end
		return nil
	end

	return self
end

return table.freeze(PopupQueue)
