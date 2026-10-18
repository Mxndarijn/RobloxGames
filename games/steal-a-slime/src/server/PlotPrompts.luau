--!strict
--[[
	PlotPrompts (pure)

	What each plot's owner-only prompts and lock / pad attributes should say
	right now (CONTRACT.md §8.4-§8.5), so WorldView only copies values onto
	Instances:
	  * LockPrompt on LockButton: "Lock base $<cost>" / "Extend lock $<cost>" /
	    "Lock is maxed", ObjectText "<name>'s base: OPEN" / "... LOCKED m:ss";
	  * BuyPadPrompt on the lowest locked pad: "Buy pad $<cost>", "Pad <j> of <max>";
	  * MergePrompt on MergeVat: "Open vat" (the client opens the merge menu; FEATURES.MergeVat3) or "Auto-merge"
	    (the pair vat merges the cheapest pair), "Merge vat";
	  * plot attributes Locked / LockCost / PadsUnlocked / NextPadCost.
	A free plot gets everything disabled and ShowOnlyToUserId = nil.
]]

local Shared = if script then (game:GetService("ReplicatedStorage") :: any).Shared else nil
local Config = if Shared then require(Shared.Config) else require("../shared/Config")
local Economy = if Shared then require(Shared.Economy) else require("../shared/Economy")
local Steal = if Shared then require(Shared.Steal) else require("../shared/Steal")
local Revenge = if script then require(script.Parent.Revenge) else require("./Revenge")
local World = if script then require(script.Parent.World) else require("./World")

export type Prompt = { actionText: string, objectText: string, enabled: boolean }

export type Plot = {
	ownerUserId: number?, -- ShowOnlyToUserId on every prompt; nil = free plot
	locked: boolean,
	lockCost: number, -- 0 on a free plot
	padsUnlocked: number, -- 0 on a free plot
	nextPadCost: number?,
	lock: Prompt,
	buyPad: Prompt & { pad: number }, -- pad the prompt sits on
	merge: Prompt,
}

local PlotPrompts = {}

-- "m:ss" for a countdown.
function PlotPrompts.clock(seconds: number): string
	local s = math.max(0, math.ceil(seconds))
	return string.format("%d:%02d", s // 60, s % 60)
end

-- The vat prompt's text: with the 3-slime vat it opens the merge menu (CONTRACT.md §21.1).
function PlotPrompts.mergeText(): string
	return if Config.FEATURES.MergeVat3 then "Open vat" else "Auto-merge"
end

function PlotPrompts.describe(world: World.World, plotIndex: number, now: number): Plot
	local userId = world.plots[plotIndex]
	local session = userId and world.sessions[userId]
	if not session then
		return {
			ownerUserId = nil,
			locked = false,
			lockCost = 0,
			padsUnlocked = 0,
			nextPadCost = nil,
			lock = { actionText = "Lock base", objectText = "Free plot", enabled = false },
			buyPad = { actionText = "Buy pad", objectText = "Free plot", enabled = false, pad = Config.PADS_START + 1 },
			merge = { actionText = PlotPrompts.mergeText(), objectText = "Merge vat", enabled = false },
		}
	end

	local data = session.data
	local locked = Steal.isLocked(session.lockUntil, now)
	local remaining = Steal.lockRemaining(session.lockUntil, now)
	local cost = Economy.lockCost(World.incomeOf(world, session)) * Revenge.lockMultiplier(world, session.userId, now)
	local price = `${Economy.formatNumber(cost)}`
	local lockText = if remaining >= Config.LOCK_MAX_REMAINING - 1
		then "Lock is maxed"
		elseif locked then `Extend lock {price}`
		else `Lock base {price}`
	local status = if locked then `LOCKED {PlotPrompts.clock(remaining)}` else "OPEN"

	local padCost = Economy.padCost(data.padsUnlocked)
	local nextPad = math.min(data.padsUnlocked + 1, Config.PADS_MAX)
	return {
		ownerUserId = session.userId,
		locked = locked,
		lockCost = cost,
		padsUnlocked = data.padsUnlocked,
		nextPadCost = padCost,
		lock = { actionText = lockText, objectText = `{session.name}'s base: {status}`, enabled = true },
		buyPad = {
			actionText = if padCost then `Buy pad ${Economy.formatNumber(padCost)}` else "All pads unlocked",
			objectText = `Pad {nextPad} of {Config.PADS_MAX}`,
			enabled = padCost ~= nil,
			pad = nextPad,
		},
		merge = { actionText = PlotPrompts.mergeText(), objectText = "Merge vat", enabled = true },
	}
end

return PlotPrompts
