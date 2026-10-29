--!strict
--[[
	TutorialProgress

	The server-owned tutorial step (CONTRACT.md §2 Tutorial, contract/tutorial.md). Steps are 1-based and match
	the UI's Tutorial.STEPS order. Only the current step's action finishes it (a later step's action does not skip
	ahead); after any action every step the player has already done (`isDone`, from saved data) is skipped.
	`data.tutorialStep` is 0 once finished or skipped. The tutorial teaches the loop and shows the places a player
	comes back to; it pays nothing. Pure: no Roblox APIs.
]]

local Config = if script then require(script.Parent.Config) else require("./Config")

local TutorialProgress = {}

-- Fields `isDone` reads; all optional so bare `{ tutorialStep = n }` tables work.
-- Callers pass PlayerData.Data, so the functions below take `any` and read through this.
export type Progress = {
	tutorialStep: number,
	stats: { caught: number?, merges: number?, locks: number? }?,
	padsUnlocked: number?,
	upgrades: { [string]: number }?,
	consumables: { held: { [string]: number }? }?,
	pvp: { tiers: { [string]: number }?, traps: { [string]: number }?, fun: { string }? }?,
}

TutorialProgress.STEPS =
	table.freeze({ "Grab", "Deposit", "Lock", "Leaderboard", "Guide", "BuyPad", "Merge", "BuyItem" })

-- The active step (1..#STEPS) or nil when finished.
function TutorialProgress.current(data: { tutorialStep: number }): number?
	local step = data.tutorialStep
	if step >= 1 and step <= #TutorialProgress.STEPS then
		return step
	end
	return nil
end

-- The active step's name (State.tutorialStepId, Player attribute TutorialStepId) or nil.
function TutorialProgress.currentId(data: { tutorialStep: number }): string?
	local step = TutorialProgress.current(data)
	return if step then TutorialProgress.STEPS[step] else nil
end

function TutorialProgress.indexOf(name: string): number?
	return table.find(TutorialProgress.STEPS, name)
end

local function anyPositive(map: { [string]: number }?): boolean
	local entries: { [string]: number } = map or {}
	for _, n in entries do
		if type(n) == "number" and n > 0 then
			return true
		end
	end
	return false
end

-- True when the player owns anything from the Item Shop or the Upgrade Shop.
local function ownsShopItem(progress: Progress): boolean
	local pvp = progress.pvp
	return anyPositive(progress.upgrades)
		or anyPositive(progress.consumables and progress.consumables.held)
		or (pvp ~= nil and (anyPositive(pvp.tiers) or anyPositive(pvp.traps) or #(pvp.fun or {}) > 0))
end

-- True if the saved data shows the player already did step `name`. Leaderboard and Guide leave no trace in the
-- save, so they only finish by doing them.
function TutorialProgress.isDone(data: any, name: string): boolean
	local progress: Progress = data
	local stats = progress.stats
	if name == "Grab" or name == "Deposit" then
		return (if stats then stats.caught or 0 else 0) > 0
	elseif name == "Lock" then
		return (if stats then stats.locks or 0 else 0) > 0
	elseif name == "BuyPad" then
		return (progress.padsUnlocked or 0) > Config.PADS_START
	elseif name == "Merge" then
		return (if stats then stats.merges or 0 else 0) > 0
	elseif name == "BuyItem" then
		return ownsShopItem(progress)
	end
	return false
end

--[[
	Records that the player did `name`'s action. Returns (changed, finished):
	changed when the step moved forward, finished when that ended the tutorial.
]]
function TutorialProgress.complete(data: any, name: string): (boolean, boolean)
	local step = TutorialProgress.current(data)
	local index = TutorialProgress.indexOf(name)
	if not step or not index or index < step then
		return false, false
	end
	local before = data.tutorialStep
	if index == step then
		step += 1
	end
	while
		not data.tutorialReplay
		and step <= #TutorialProgress.STEPS
		and TutorialProgress.isDone(data, TutorialProgress.STEPS[step])
	do
		step += 1
	end
	data.tutorialStep = if step > #TutorialProgress.STEPS then 0 else step
	if data.tutorialStep == 0 then
		data.tutorialReplay = nil
	end
	return data.tutorialStep ~= before, data.tutorialStep == 0
end

-- Ends the tutorial at the player's request. Returns false when it was already over.
function TutorialProgress.skip(data: any): boolean
	if TutorialProgress.current(data) == nil then
		return false
	end
	data.tutorialStep = 0
	data.tutorialReplay = nil
	return true
end

-- Starts the tutorial again from the first step (Settings menu). During the replay every step waits for its own
-- action, even one the save shows as done. Returns false while the tutorial is still running.
function TutorialProgress.restart(data: any): boolean
	if TutorialProgress.current(data) ~= nil then
		return false
	end
	data.tutorialStep = 1
	data.tutorialReplay = true
	return true
end

return table.freeze(TutorialProgress)
