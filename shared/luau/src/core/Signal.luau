--!strict
--[[
	Signal: a small pure-Lua event.

		local changed = Signal.new()
		local conn = changed:connect(function(value) print(value) end)
		changed:fire(5)
		conn:disconnect()
		changed:once(function() end)
		changed:destroy() -- disconnects everything; later connects are inert

	Handlers run synchronously in connection order. A handler connected during a fire is not called by that fire;
	one disconnected during a fire is not called if it has not run yet.
]]

export type Connection = {
	connected: boolean,
	disconnect: (self: Connection) -> (),
}

export type Signal = {
	connect: (self: Signal, handler: (...any) -> ()) -> Connection,
	once: (self: Signal, handler: (...any) -> ()) -> Connection,
	fire: (self: Signal, ...any) -> (),
	connectionCount: (self: Signal) -> number,
	destroy: (self: Signal) -> (),
}

type Slot = { connection: Connection, handler: (...any) -> () }

type SignalState = Signal & { slots: { Slot }, destroyed: boolean }

local Signal = {}
Signal.__index = Signal

function Signal.new(): Signal
	local self = setmetatable({ slots = {}, destroyed = false }, Signal)
	return (self :: any) :: Signal
end

local function removeSlot(state: SignalState, connection: Connection)
	for i, slot in state.slots do
		if slot.connection == connection then
			table.remove(state.slots, i)
			return
		end
	end
end

function Signal.connect(self: Signal, handler: (...any) -> ()): Connection
	if type(handler) ~= "function" then
		error("Signal:connect expects a function", 2)
	end
	local state = self :: SignalState
	local connection: Connection
	connection = {
		connected = not state.destroyed,
		disconnect = function(_: any)
			if connection.connected then
				connection.connected = false
				removeSlot(state, connection)
			end
		end,
	}
	if not state.destroyed then
		table.insert(state.slots, { connection = connection, handler = handler })
	end
	return connection
end

-- Like connect, but disconnects itself before the handler's first call.
function Signal.once(self: Signal, handler: (...any) -> ()): Connection
	local connection: Connection
	connection = self:connect(function(...)
		connection:disconnect()
		handler(...)
	end)
	return connection
end

function Signal.fire(self: Signal, ...: any)
	local state = self :: SignalState
	local snapshot = table.clone(state.slots)
	for _, slot in snapshot do
		if slot.connection.connected then
			slot.handler(...)
		end
	end
end

function Signal.connectionCount(self: Signal): number
	return #(self :: SignalState).slots
end

function Signal.destroy(self: Signal)
	local state = self :: SignalState
	state.destroyed = true
	for _, slot in state.slots do
		slot.connection.connected = false
	end
	table.clear(state.slots)
end

return table.freeze(Signal)
