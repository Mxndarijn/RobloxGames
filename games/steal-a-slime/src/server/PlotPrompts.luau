--!strict
--[[
	PlotPrompts (pure)

	What each plot's owner-only prompts and lock / pad attributes should say
	right now (CONTRACT.md §8.4-§8.5), so WorldView only copies values onto
	Instances:
	  * LockPrompt on LockButton: "Lock base" (disabled while a lock runs), ObjectText "<name>'s base: OPEN" / "... LOCKED m:ss";
	  * BuyPadPrompt on the lowest locked pad: "Buy pad $<cost>" ("Build floor <f> $<cost>" on a floor's first pad),
	    "Pad <j> of <max>";
	  * FriendsPrompt on LockButton (FEATURES.FriendsInBase): "Allow friends" / "Block friends", ObjectText
	    "Friends: blocked" / "Friends can enter", and the plot attribute FriendsAllowed;
	  * MergePrompt on MergeVat: "Manage vat" (the owner's client opens the merge vat menu), "Merge vat";
	  * plot attributes Locked / PadsUnlocked / NextPadCost.
	A free plot gets everything disabled and ShowOnlyToUserId = nil.
	Each prompt carries its text as Localize messages (`action`, `object`, for WorldText) and their English
	(`actionText`, `objectText`).
]]

local Shared = if script then (game:GetService("ReplicatedStorage") :: any).Shared else nil
local Config = if Shared then require(Shared.Config) else require("../shared/Config")
local Economy = if Shared then require(Shared.Economy) else require("../shared/Economy")
local Steal = if Shared then require(Shared.Steal) else require("../shared/Steal")
local PlotGuests = if script then require(script.Parent.PlotGuests) else require("./PlotGuests")
local World = if script then require(script.Parent.World) else require("./World")
local WorldText = if script then require(script.Parent.WorldText) else require("./WorldText")
local Lib = if script then (game:GetService("ReplicatedStorage") :: any).Lib else nil
local Localize = if Lib then require(Lib.locale.Localize) else require("../../../../shared/luau/src/locale/Localize")

type Message = Localize.Message
export type Prompt = { action: Message, object: Message, actionText: string, objectText: string, enabled: boolean }

export type Plot = {
	ownerUserId: number?, -- ShowOnlyToUserId on every prompt; nil = free plot
	locked: boolean,
	friendsAllowed: boolean, -- the owner's friends switch is on (and FEATURES.FriendsInBase)
	padsUnlocked: number, -- 0 on a free plot
	nextPadCost: number?,
	lock: Prompt,
	friends: Prompt,
	buyPad: Prompt & { pad: number }, -- pad the prompt sits on
	merge: Prompt,
}

local PlotPrompts = {}

-- "m:ss" for a countdown.
function PlotPrompts.clock(seconds: number): string
	local s = math.max(0, math.ceil(seconds))
	return string.format("%d:%02d", s // 60, s % 60)
end

local function msg(key: string, args: Localize.Args?): Message
	return Localize.msg(key, args)
end

local function prompt(action: Message, object: Message, enabled: boolean): Prompt
	return {
		action = action,
		object = object,
		actionText = WorldText.english(action),
		objectText = WorldText.english(object),
		enabled = enabled,
	}
end

local function padPrompt(action: Message, object: Message, enabled: boolean, pad: number): Prompt & { pad: number }
	local out: any = prompt(action, object, enabled)
	out.pad = pad
	return out
end

-- The vat prompt's text: it opens the merge vat menu (CONTRACT.md §21).
function PlotPrompts.mergeText(): Message
	return msg("world.prompt.manage_vat")
end

-- The FriendsPrompt for a switch that is `on`; `enabled` false hides it (free plot, or the feature off).
function PlotPrompts.friendsPrompt(on: boolean, enabled: boolean): Prompt
	return prompt(
		msg(if on then "world.prompt.block_friends" else "world.prompt.allow_friends"),
		msg(if on then "world.prompt.friends_can_enter" else "world.prompt.friends_blocked"),
		enabled
	)
end

function PlotPrompts.describe(world: World.World, plotIndex: number, now: number): Plot
	local userId = world.plots[plotIndex]
	local session = userId and world.sessions[userId]
	if not session then
		return {
			ownerUserId = nil,
			locked = false,
			friendsAllowed = false,
			padsUnlocked = 0,
			nextPadCost = nil,
			lock = prompt(msg("world.prompt.lock_base"), msg("world.prompt.free_plot"), false),
			friends = PlotPrompts.friendsPrompt(false, false),
			buyPad = padPrompt(
				msg("world.prompt.buy_pad"),
				msg("world.prompt.free_plot"),
				false,
				Config.PADS_START + 1
			),
			merge = prompt(PlotPrompts.mergeText(), msg("world.prompt.merge_vat"), false),
		}
	end

	local data = session.data
	local friendsOn = PlotGuests.enabled(nil)
	local friendsAllowed = friendsOn and data.allowFriends == true
	local locked = Steal.isLocked(session.lockUntil, now)
	local remaining = Steal.lockRemaining(session.lockUntil, now)
	local status = if locked
		then msg("world.prompt.status_locked", { time = PlotPrompts.clock(remaining) })
		else msg("world.prompt.status_open")

	local padCost = Economy.padCost(data.padsUnlocked)
	local padNeed = Economy.padRebirths(data.padsUnlocked)
	local padLocked = padNeed ~= nil and data.rebirths < padNeed
	local nextPad = math.min(data.padsUnlocked + 1, Config.PADS_MAX)
	local floor = Economy.floorOf(nextPad)
	local firstOfFloor = floor > 1 and nextPad == (floor - 1) * Config.PADS_PER_FLOOR + 1
	local buyAction = if padLocked
		then msg("world.prompt.pad_rebirth", { count = padNeed })
		elseif padCost and firstOfFloor then msg(
			"world.prompt.build_floor_price",
			{ floor = floor, price = `${Economy.formatNumber(padCost)}` }
		)
		elseif padCost then msg("world.prompt.buy_pad_price", { price = `${Economy.formatNumber(padCost)}` })
		else msg("world.prompt.all_pads_unlocked")
	return {
		ownerUserId = session.userId,
		locked = locked,
		friendsAllowed = friendsAllowed,
		padsUnlocked = data.padsUnlocked,
		nextPadCost = padCost,
		lock = prompt(
			msg("world.prompt.lock_base"),
			msg("world.prompt.base_status", { name = session.name, status = status }),
			not locked
		),
		friends = PlotPrompts.friendsPrompt(friendsAllowed, friendsOn),
		buyPad = padPrompt(
			buyAction,
			msg("world.prompt.pad_of", { pad = nextPad, max = Config.PADS_MAX }),
			padCost ~= nil and not padLocked,
			nextPad
		),
		merge = prompt(PlotPrompts.mergeText(), msg("world.prompt.merge_vat"), true),
	}
end

return PlotPrompts
