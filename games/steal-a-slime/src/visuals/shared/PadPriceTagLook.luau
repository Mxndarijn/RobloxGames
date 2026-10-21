--!strict
--[[
	PadPriceTagLook (pure): what the floating price tag over the owner's next buyable pad says and how it sits.
	The client module (visuals/client/PadPriceTag) builds the Instances.

	PadPriceTagLook.view(actionText, cost, cash) -> { title, price, affordable }?
	  actionText: the BuyPadPrompt's text ("Buy pad $625" / "Build floor 2 $30K"), cost: the plot's NextPadCost,
	  cash: the player's cash. nil when there is nothing to buy (no cost).
]]

local PadPriceTagLook = {}

PadPriceTagLook.HEIGHT = 5.5 -- studs above the pad's top (over a resting slime)
PadPriceTagLook.SIZE = { 6, 2.2 } -- billboard size, studs
PadPriceTagLook.MAX_DISTANCE = 120 -- readable across the jar and from the plot edge
PadPriceTagLook.RING_DIAMETER = 8.4 -- the glow ring round the cork stand (its foot is 7.8)
PadPriceTagLook.GOOD = { 120, 235, 150 } -- price colour when the player can pay
PadPriceTagLook.SHORT = { 255, 214, 120 } -- price colour while saving up

export type View = { title: string, price: string, affordable: boolean }

-- Splits "Build floor 2 $30K" into "BUILD FLOOR 2" and "$30K".
function PadPriceTagLook.view(actionText: string?, cost: number?, cash: number?): View?
	if type(cost) ~= "number" or type(actionText) ~= "string" then
		return nil
	end
	local title, price = string.match(actionText, "^(.-)%s*(%$%S+)$")
	return {
		title = string.upper(title or actionText),
		price = price or "",
		affordable = (cash or 0) >= cost,
	}
end

return table.freeze(PadPriceTagLook)
