--!strict
--[[
	PodiumAvatars (pure)

	The plaza's Podium_1..3 show the leaderboard's top three as NPC rigs
	wearing their avatar. Roblox calls sit behind an injected adapter
	(PodiumRigs is the real one) so Lune can cover the logic:

	* `request(board)` debounces: the latest board wins, applied after DEBOUNCE.
	* A slot rebuilds only when its userId changes, or to retry a fallback rig;
	  a new stat value only rewrites the label.
	* Descriptions are cached per userId; a failed fetch is not cached (the
	  next refresh retries it). Fetch failure -> default rig; rig failure or
	  empty slot -> placeholder.
	* A hidden entry ("Show me on leaderboards" off: `hidden`, or userId 0) gets
	  the default rig and PlayerSettings.HIDDEN_NAME; no avatar fetch, no
	  display-name lookup.
]]

local Shared = if script then (game:GetService("ReplicatedStorage") :: any).Shared else nil
local Economy = if Shared then require(Shared.Economy) else require("../shared/Economy")
local PlayerSettings = if Shared then require(Shared.PlayerSettings) else require("../shared/PlayerSettings")
local Types = if Shared then require(Shared.Types) else require("../shared/Types")

local PodiumAvatars = {}

PodiumAvatars.SLOTS = 3
PodiumAvatars.DEBOUNCE = 2
PodiumAvatars.FETCH_TRIES = 2

export type Adapter = {
	fetchDescription: (userId: number) -> any, -- may error / yield
	buildRig: (description: any?) -> any, -- nil = default avatar; may error
	placeholder: () -> any,
	displayName: (userId: number, fallback: string) -> string,
	mount: (rank: number, rig: any, text: string) -> (),
	setLabel: (rig: any, text: string) -> (),
	destroy: (rig: any) -> (),
	delay: (seconds: number, fn: () -> ()) -> (),
	warn: (message: string) -> (),
}

type Slot = { userId: number?, rig: any, fallback: boolean, text: string }

export type Podiums = {
	adapter: Adapter,
	cache: { [number]: any },
	slots: { [number]: Slot },
	pending: Types.Leaderboard?,
	scheduled: boolean,
	busy: boolean,
	request: (self: Podiums, board: Types.Leaderboard?) -> (),
	apply: (self: Podiums, board: Types.Leaderboard?) -> (),
}

-- Billboard text: "<display name>\n$<total earned>", or "" for an empty slot (the adapter shows no label).
function PodiumAvatars.labelText(displayName: string?, value: number?): string
	if not displayName then
		return ""
	end
	return `{displayName}\n${Economy.formatNumber(value or 0)}`
end

-- A label's two lines, the name and the stat (the name board puts them on the band and under it).
function PodiumAvatars.splitLabel(text: string): (string, string)
	local name, stat = string.match(text, "^(.-)\n(.*)$")
	return name or text, stat or ""
end

local function entryAt(board: Types.Leaderboard?, rank: number): Types.LeaderboardEntry?
	if not board then
		return nil
	end
	for _, entry in board.entries do
		if entry.rank == rank then
			return entry
		end
	end
	return nil
end

local Podiums = {}
Podiums.__index = Podiums

function PodiumAvatars.new(adapter: Adapter): Podiums
	local self = setmetatable({
		adapter = adapter,
		cache = {},
		slots = {},
		pending = nil,
		scheduled = false,
		busy = false,
	}, Podiums)
	return self :: any
end

-- Cached description, or nil after FETCH_TRIES failures (not cached).
local function description(self: Podiums, userId: number): any?
	local cached = self.cache[userId]
	if cached ~= nil then
		return cached
	end
	for _ = 1, PodiumAvatars.FETCH_TRIES do
		local ok, result = pcall(self.adapter.fetchDescription, userId)
		if ok and result ~= nil then
			self.cache[userId] = result
			return result
		end
	end
	self.adapter.warn(`[PodiumAvatars] no avatar for {userId}, using the default rig`)
	return nil
end

-- True for an entry of a player who hides themselves: never look up their avatar or name.
function PodiumAvatars.isHidden(entry: Types.LeaderboardEntry?): boolean
	return entry ~= nil and (entry.hidden == true or entry.userId == 0)
end

-- (rig, fallback?) for a user (the default rig for a hidden one), or the placeholder for an empty slot.
local function build(self: Podiums, userId: number?, hidden: boolean): (any, boolean)
	if userId then
		local desc = if hidden then nil else description(self, userId)
		local ok, rig = pcall(self.adapter.buildRig, desc)
		if ok and rig ~= nil then
			return rig, desc == nil and not hidden
		end
		self.adapter.warn(`[PodiumAvatars] rig build failed for {userId}: {rig}`)
	end
	local ok, rig = pcall(self.adapter.placeholder)
	return if ok then rig else nil, userId ~= nil
end

local function release(self: Podiums, slot: Slot?)
	if slot and slot.rig ~= nil then
		pcall(self.adapter.destroy, slot.rig)
	end
end

function Podiums.apply(self: Podiums, board: Types.Leaderboard?)
	for rank = 1, PodiumAvatars.SLOTS do
		local entry = entryAt(board, rank)
		local hidden = PodiumAvatars.isHidden(entry)
		local userId = if hidden then 0 elseif entry then entry.userId else nil
		local slot = self.slots[rank]
		local name = if hidden
			then PlayerSettings.HIDDEN_NAME
			elseif entry then self.adapter.displayName(entry.userId, entry.name)
			else nil
		local text = PodiumAvatars.labelText(name, if entry then entry.value else nil)
		local fresh = slot == nil or slot.userId ~= userId or (slot.fallback and userId ~= nil)
		if fresh then
			release(self, slot)
			local rig, fallback = build(self, userId, hidden)
			if rig ~= nil then
				local ok, err = pcall(function()
					self.adapter.mount(rank, rig, text)
					return nil
				end)
				if not ok then
					self.adapter.warn(`[PodiumAvatars] mount {rank} failed: {err}`)
				end
			end
			self.slots[rank] = { userId = userId, rig = rig, fallback = fallback, text = text }
		elseif slot and slot.text ~= text then
			slot.text = text
			if slot.rig ~= nil then
				pcall(self.adapter.setLabel, slot.rig, text)
			end
		end
	end
end

-- Debounced: called on every leaderboard refresh; the latest board wins.
function Podiums.request(self: Podiums, board: Types.Leaderboard?)
	self.pending = board
	if self.scheduled then
		return
	end
	self.scheduled = true
	local function flush()
		if self.busy then
			self.adapter.delay(PodiumAvatars.DEBOUNCE, flush)
			return
		end
		self.scheduled = false
		self.busy = true
		local ok, err = pcall(function()
			self:apply(self.pending)
			return nil
		end)
		self.busy = false
		if not ok then
			self.adapter.warn(`[PodiumAvatars] refresh failed: {err}`)
		end
	end
	self.adapter.delay(PodiumAvatars.DEBOUNCE, flush)
end

return PodiumAvatars
