--!strict
--[[
	GrabBlock (pure)

	Why the local player can't grab a slime right now, so its GrabPrompt shows the reason instead of a key
	(ui/GrabBlockCard). The server's Carry.grab refuses the same cases; this is only what the prompt shows.

	  * carrying: you already hold a slime (any wild grab or steal);
	  * plotFull: no free pad to bring a wild slime home to (not the boss: its haul doesn't take a pad);
	  * money: a wild slime's price is more than your cash.

	Someone else carrying the slime needs no reason: the server turns its prompt off.
]]

export type Reason = "carrying" | "plotFull" | "money"

export type Me = {
	carrying: boolean,
	freePad: boolean,
	cash: number,
}

export type Target = {
	state: string?, -- the slime model's State attribute: "Wild" or "Pad"
	price: number?, -- a wild slime's price (0 = free)
	boss: boolean,
}

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
	if target.state ~= "Wild" or target.boss then
		return nil
	end
	if not me.freePad then
		return "plotFull"
	end
	if (target.price or 0) > me.cash then
		return "money"
	end
	return nil
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
