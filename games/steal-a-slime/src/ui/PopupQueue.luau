--!strict
--[[
	PopupQueue

	When the welcome back / daily reward card (Panels/Welcome) opens by itself, and in which mode
	(contract/welcome-back.md). Pure (tests/ui/PopupQueue.spec.luau); init.client opens what `update` returns.

	- The join report (State.welcomeBack, once per join) queues "join". It takes any pending daily edge with it:
	  the join card shows the daily reward too, so closing it without claiming does not open the card again.
	- A daily availability edge (Daily.shouldAutoOpen) queues "daily", unless `dailyAuto` is false (Settings
	  "Daily popup" off); the claim going away drops it.
	- The early tutorial steps (BLOCKING_STEPS: Grab, Deposit, Lock, BuyPad) hold the card back, and so does
	  `busy` (a menu or the bag is open): the card never replaces what the player has open.
]]

local Daily = if script then require(script.Parent.Daily) else require("./Daily")
local Tutorial = if script then require(script.Parent.Tutorial) else require("./Tutorial")

export type Mode = "join" | "daily"
export type Queue = {
	pending: () -> Mode?,
	update: (state: any, busy: boolean?, dailyAuto: boolean?) -> Mode?,
}

local PopupQueue = {}

local function dailyAvailable(state: any): boolean
	return type(state) == "table" and type(state.daily) == "table" and state.daily.available == true
end

-- Tutorial steps during which the card stays closed.
PopupQueue.BLOCKING_STEPS = table.freeze({
	Grab = true,
	Deposit = true,
	Lock = true,
	BuyPad = true,
} :: { [string]: boolean })

-- What keeps the card closed right now ("Tutorial"), nil when free.
function PopupQueue.blocker(state: any): string?
	local step = Tutorial.fromState(state)
	return if step ~= nil and PopupQueue.BLOCKING_STEPS[step.id] then "Tutorial" else nil
end

function PopupQueue.new(): Queue
	local join, daily = false, false
	local dailyWas: boolean? = nil
	local welcomeWas = false

	local self = {} :: Queue

	-- The mode waiting to open, nil when nothing is queued.
	function self.pending(): Mode?
		local mode: Mode? = if join then "join" elseif daily then "daily" else nil
		return mode
	end

	-- Feed every State snapshot; returns the mode to open the card in now (taken off the queue), or nil.
	function self.update(state: any, busy: boolean?, dailyAuto: boolean?): Mode?
		local welcome = type(state) == "table" and type(state.welcomeBack) == "table"
		if welcome and not welcomeWas then
			join = true
		end
		welcomeWas = welcome
		local available = dailyAvailable(state)
		if Daily.shouldAutoOpen(dailyWas, available) then
			daily = dailyAuto ~= false
		elseif not available then
			daily = false
		end
		dailyWas = available

		if busy or PopupQueue.blocker(state) ~= nil then
			return nil
		end
		local mode: Mode? = if join then "join" elseif daily then "daily" else nil
		join, daily = false, false
		return mode
	end

	return self
end

return table.freeze(PopupQueue)
