--!strict
--[[
	GrabBlock (pure)

	Why the local player can't grab a slime right now, so its GrabPrompt shows the reason instead of a key
	(ui/GrabBlockCard). The server's Carry.grab refuses the same cases; this is only what the prompt shows.

	  * carrying: you already hold a slime (any wild grab or steal);
	  * dropped: you just dropped one (Config.DROP_PICKUP_COOLDOWN, any slime): "Grab in 1.2s", counting down;
	  * plotFull: no free pad to bring a wild slime home to (not the boss: its haul doesn't take a pad);
	  * money: a wild slime's price is more than your cash ("Need $1.2K more", like the shop's Buy buttons).

	Someone else carrying the slime needs no reason: the server turns its prompt off.
]]

export type Reason = "carrying" | "dropped" | "rank" | "plotFull" | "money"

export type Me = {
	carrying: boolean,
	freePad: boolean,
	cash: number,
	rebirths: number?,
	pickupBlockedUntil: number?, -- State.pickupBlockedUntil: server time the after-drop cooldown ends
	now: number?, -- the client's server time, for that countdown
}

export type Target = {
	state: string?, -- the slime model's State attribute: "Wild" or "Pad"
	price: number?, -- a wild slime's price (0 = free)
	boss: boolean,
	rebirths: number?, -- rebirths needed to grab it (GrabBlock.rebirthsFor; the GrabRebirths attribute)
}

local Config = if script then require(script.Parent.Config) else require("./Config")
local NumberFormat = if script then require(script.Parent.NumberFormat) else require("./NumberFormat")

local GrabBlock = {}

GrabBlock.TEXT = table.freeze({
	carrying = "Already carrying a slime",
	plotFull = "Plot is full, buy more pads",
	money = "Not enough money",
} :: { [string]: string })

function GrabBlock.reason(me: Me, target: Target): Reason?
	if me.carrying then
		return "carrying"
	end
	if GrabBlock.waitLeft(me) then
		return "dropped"
	end
	if target.state ~= "Wild" or target.boss then
		return nil
	end
	if (target.rebirths or 0) > (me.rebirths or 0) then
		return "rank"
	end
	if not me.freePad then
		return "plotFull"
	end
	if (target.price or 0) > me.cash then
		return "money"
	end
	return nil
end

-- Rebirths needed to grab `slime` from the fountain: CATCH_REBIRTHS by rarity; for a Mystery Egg its kind's
-- rebirths (Config.MYSTERY_EGG.KINDS, the same gate as EggKind.grabBlock).
function GrabBlock.rebirthsFor(slime: any): number
	local egg = slime.egg
	if egg then
		for _, kind in Config.MYSTERY_EGG.KINDS do
			if kind.id == egg.kind then
				return kind.rebirths
			end
		end
		return 0
	end
	return Config.CATCH_REBIRTHS[slime.tier] or 0
end

-- Seconds left of the after-drop pickup cooldown, or nil when there is none.
function GrabBlock.waitLeft(me: Me): number?
	local ends, now = me.pickupBlockedUntil, me.now
	if not ends or not now or now >= ends then
		return nil
	end
	return ends - now
end

-- The text a GrabPrompt shows for `reason` ("Rebirth 5 to grab this" for a rarity the player can't grab yet,
-- "Need $1.2K more" for a slime that costs more than `me`'s cash).
function GrabBlock.text(reason: Reason, target: Target, me: Me?): string
	if reason == "rank" then
		return `Rebirth {target.rebirths or 0} to grab this`
	end
	if reason == "dropped" then
		-- tenths, rounded up: it never reads 0.0s while the server still refuses
		local left = if me then GrabBlock.waitLeft(me) else nil
		return string.format("Grab in %.1fs", math.ceil((left or 0) * 10) / 10)
	end
	if reason == "money" and me and target.price then
		local missing = target.price - me.cash
		if missing > 0 then
			return `Need {NumberFormat.cash(missing)} more`
		end
	end
	return GrabBlock.TEXT[reason]
end

-- True when one of the first `padsUnlocked` pads has no slime on it (PlayerData.freePad over State's slimes,
-- each a SlimeView with its slime's pad).
function GrabBlock.hasFreePad(padsUnlocked: number, slimes: { any }): boolean
	local used = {}
	for _, view in slimes do
		local pad = view.slime.pad
		if pad then
			used[pad] = true
		end
	end
	for pad = 1, padsUnlocked do
		if not used[pad] then
			return true
		end
	end
	return false
end

return GrabBlock
