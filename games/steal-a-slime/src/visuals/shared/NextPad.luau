--!strict
--[[
	NextPad (pure)

	The hint on the next pad you can buy on your own plot (client only, see client/NextPadMarker): a soft mint
	outline on the pad and a Goo price tag over it. Mint "Buy pad $X" when you can afford it, else a glass
	"Next pad $X" with the price in gold. This module holds the look and the text; it touches no Roblox API.
]]

local Shared = if script then (script.Parent.Parent :: any).Shared else nil
local Format = if Shared then require(Shared.NumberFormat) else require("../../shared/NumberFormat")

local NextPad = {}

NextPad.POLL = 0.5 -- seconds between checks of the plot's attributes and your cash
NextPad.LOOK = table.freeze({
	tagHeight = 5, -- studs above the pad's centre
	tagW = 176, -- px
	tagH = 42,
	textSize = 22,
	stroke = 3, -- Ink outline round the tag
	textStroke = 2, -- Ink outline round white text
	maxDistance = 140, -- studs: readable across your own plot
	fillTransparency = 0.72, -- the outline's mint fill over the pad
	glassTransparency = 0.25, -- the tag's Ink glass when you can't afford it yet
})

export type Tag = { verb: string, price: string, text: string, affordable: boolean }

-- What the tag says for a pad costing `cost` while you hold `cash`; nil when there is no pad left to buy.
function NextPad.tag(cost: number?, cash: number?): Tag?
	if type(cost) ~= "number" or cost < 0 then
		return nil
	end
	local affordable = type(cash) == "number" and cash >= cost
	local price = Format.cash(cost)
	local verb = if affordable then "Buy pad" else "Next pad"
	return { verb = verb, price = price, text = `{verb} {price}`, affordable = affordable }
end

return table.freeze(NextPad)
