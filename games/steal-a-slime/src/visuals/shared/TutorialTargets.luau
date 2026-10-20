--!strict
--[[
	TutorialTargets (pure)

	Which wild slime the Grab step's guide leads to, and its label. The
	client (visuals/client/TutorialArrow) reads the wild slimes into plain
	records; this picks the closest one the player can afford (free slimes
	always count) through GuideTarget, so the guide keeps its pick while
	slimes walk side by side. When nothing is affordable it leads to the
	cheapest slime with "Need $X".

	  TutorialTargets.grab(wild, cash, from, currentKey?) -> (Wild?, string?)
	  TutorialTargets.priceLabel(price, cash) -> string
]]

local ReplicatedStorage = if script then (game :: any):GetService("ReplicatedStorage") else nil
local Economy = if script then require(script.Parent.Parent.Shared.Economy) else require("../../shared/Economy")
local GuideTarget = if script
	then require(ReplicatedStorage.Lib.guide.GuideTarget)
	else require("../../../../../shared/luau/src/guide/GuideTarget")

export type Wild = { key: string, x: number, z: number, price: number, value: any }

local TutorialTargets = {}

function TutorialTargets.priceLabel(price: number, cash: number): string
	if price <= 0 then
		return "Grab"
	elseif price <= cash then
		return `Buy ${Economy.formatNumber(price)}`
	end
	return `Need ${Economy.formatNumber(price)}`
end

function TutorialTargets.grab(
	wild: { Wild },
	cash: number,
	from: GuideTarget.Point,
	currentKey: string?
): (Wild?, string?)
	local affordable: { GuideTarget.Candidate<Wild> } = {}
	local cheapest: Wild? = nil
	for _, slime in wild do
		if slime.price <= 0 or slime.price <= cash then
			table.insert(affordable, { key = slime.key, x = slime.x, z = slime.z, value = slime })
		end
		if cheapest == nil or slime.price < cheapest.price then
			cheapest = slime
		end
	end
	local picked = GuideTarget.pick(affordable, from, currentKey)
	local slime = if picked then picked.value else cheapest
	if slime == nil then
		return nil, nil
	end
	return slime, TutorialTargets.priceLabel(slime.price, cash)
end

return table.freeze(TutorialTargets)
