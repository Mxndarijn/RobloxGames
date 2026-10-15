--!strict
--[[
	TutorialProgress

	The server-owned tutorial step (CONTRACT.md §2 Tutorial, §9.2). Steps are
	1-based and match the UI's Tutorial.STEPS order. Only the current step's
	action finishes it (a later step's action no longer skips ahead); after
	any action every step the player has already done (`isDone`, from saved
	data) is skipped. `data.tutorialStep` is 0 once finished. Pure: no Roblox APIs.
]]

local Config = if script then require(script.Parent.Config) else require("./Config")

local TutorialProgress = {}

-- Fields `isDone` reads; all optional so bare `{ tutorialStep = n }` tables work.
-- Callers pass PlayerData.Data, so the functions below take `any` and read through this.
export type Progress = {
	tutorialStep: number,
	stats: { caught: number?, merges: number?, locks: number? }?,
	padsUnlocked: number?,
	totalStolen: number?,
	rebirths: number?,
}

-- v13 inserted "BuyPad" as step 4 (CONTRACT.md §8.3); SaveData remaps older saves.
TutorialProgress.STEPS = table.freeze({ "Grab", "Deposit", "Lock", "BuyPad", "Merge", "Steal", "Rebirth" })

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

-- True if the saved data shows the player already did step `name` (CONTRACT.md §9.2).
function TutorialProgress.isDone(data: any, name: string): boolean
	local progress: Progress = data
	local stats = progress.stats
	local caught = if stats then stats.caught or 0 else 0
	local rebirths = progress.rebirths or 0
	if name == "Grab" or name == "Deposit" then
		return caught > 0
	elseif name == "Lock" then
		return (if stats then stats.locks or 0 else 0) > 0
	elseif name == "BuyPad" then
		return (progress.padsUnlocked or 0) > Config.PADS_START
	elseif name == "Merge" then
		return (if stats then stats.merges or 0 else 0) > 0
	elseif name == "Steal" then
		return (progress.totalStolen or 0) > 0 or rebirths > 0 -- solo servers can't steal
	elseif name == "Rebirth" then
		return rebirths > 0
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
	while step <= #TutorialProgress.STEPS and TutorialProgress.isDone(data, TutorialProgress.STEPS[step]) do
		step += 1
	end
	data.tutorialStep = if step > #TutorialProgress.STEPS then 0 else step
	return data.tutorialStep ~= before, data.tutorialStep == 0
end

return table.freeze(TutorialProgress)
