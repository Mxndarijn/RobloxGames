--!strict
--[[
	ObbyAvatar (pure, contract/obby.md §3)

	While a player is on an Obby run their R15 character wears the standard body scales (Config.OBBY.AVATAR_SCALES):
	the course's gaps, ceilings and beams are tuned for that avatar, and a tall or wide one would not fit. Their own
	scales come back when the run ends. The adapter (server/ObbyAvatarView) reads each player's scale values every
	obby tick, before the tick's teleports, and writes what `decide` returns.

	Per player it remembers the character it normalised and that character's own values (only the ones that were not
	standard, so a normalised value is never kept as the original). It writes only values that differ from what they
	should be, so it never applies twice. A new character during a run (a respawn) is normalised again; once the run
	ends only the character it normalised gets its values back (a new character already wears its own).
]]

local Shared = if script then (game:GetService("ReplicatedStorage") :: any).Shared else nil
local Config = if Shared then require(Shared.Config) else require("../shared/Config")

local STANDARD: { [string]: number } = Config.OBBY.AVATAR_SCALES
local EPSILON = 1e-4

-- Scale name -> value (the Humanoid's NumberValues; a missing name is not there to read or write).
export type Scales = { [string]: number }

type Entry = { character: any, original: Scales }

export type State = { [number]: Entry } -- userId -> the character normalised and its own scales

local ObbyAvatar = {}

ObbyAvatar.STANDARD = STANDARD

function ObbyAvatar.new(): State
	return {}
end

local function same(a: number, b: number): boolean
	return math.abs(a - b) < EPSILON
end

local function isEmpty(t: Scales): boolean
	return next(t) == nil
end

-- What to write on `userId`'s character this tick, or nil. `running`: they are on a run. `character`: their character
-- now (any value that changes on a respawn; nil = none). `current`: its scale values, nil when it can't be scaled
-- (R6, no Humanoid, automatic scaling off).
function ObbyAvatar.decide(state: State, userId: number, running: boolean, character: any?, current: Scales?): Scales?
	local entry = state[userId]
	if not running then
		state[userId] = nil
		if entry and character ~= nil and entry.character == character and current and not isEmpty(entry.original) then
			local writes: Scales = {}
			for name, value in entry.original do
				if current[name] ~= nil and not same(current[name], value) then
					writes[name] = value
				end
			end
			return if isEmpty(writes) then nil else writes
		end
		return nil
	end
	if character == nil or current == nil then
		state[userId] = nil -- nothing to scale; a new character starts fresh
		return nil
	end
	local e: Entry = if entry and entry.character == character then entry else { character = character, original = {} }
	state[userId] = e
	local writes: Scales = {}
	for name, standard in STANDARD do
		local value = current[name]
		if value ~= nil and not same(value, standard) then
			-- Not standard, and this module only ever writes standard: the player's own value (also one the engine
			-- set after we normalised, like a late appearance load).
			e.original[name] = value
			writes[name] = standard
		end
	end
	return if isEmpty(writes) then nil else writes
end

-- A player left: nothing to put back (their character goes with them).
function ObbyAvatar.forget(state: State, userId: number)
	state[userId] = nil
end

return ObbyAvatar
