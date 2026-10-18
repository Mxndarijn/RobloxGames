--!strict
--[[
	RareAnnounce

	Rare-spawn rules for Legendary+ wild drops (CONTRACT §8.6 / §8.7). Pure (tests/ui/RareAnnounce.spec.luau).

	Legendary+ drops are contracted: workspace `RareSpawnId` / `RareSpawnTier`
	/ `RareSpawnAt` (set together per drop) and a Notify with sound "Rare"
	("A LEGENDARY <name> spilled from the fountain!"). The Notify text is used
	when it arrives; the attributes alone give a generic banner. The boss event has its own
	State field (`State.boss`, Panels/BossMeter).
]]

export type Drop = { tier: number?, at: number, text: string? } -- at = server time of the drop
export type Banner = { text: string, kind: "drop" }

local RareAnnounce = {}

-- How long a Legendary+ drop banner stays up.
RareAnnounce.DROP_SECONDS = 10
RareAnnounce.DROP_SOUND = "Rare"
-- Secret drops (Config.SECRET_TIER) ring their own sound and get a bigger banner mark.
RareAnnounce.SECRET_SOUND = "Secret"
RareAnnounce.SECRET_TIER = 7

-- "drop" for a Legendary+ drop Notify, else nil.
function RareAnnounce.classify(text: any, sound: any): "drop"?
	if type(text) ~= "string" then
		return nil
	end
	local lower = string.lower(text)
	if
		sound == RareAnnounce.DROP_SOUND
		or sound == RareAnnounce.SECRET_SOUND
		or string.find(lower, "spilled from the fountain", 1, true)
	then
		return "drop"
	end
	return nil
end

-- Drop from the workspace RareSpawn* attributes, nil when unset / malformed.
function RareAnnounce.dropFromAttributes(tier: any, at: any): Drop?
	if type(at) ~= "number" then
		return nil
	end
	return { tier = if type(tier) == "number" then tier else nil, at = at, text = nil }
end

-- Banner for the latest Legendary+ drop; `tierNames[tier]` names the rarity.
function RareAnnounce.dropBanner(drop: Drop?, now: number, tierNames: { string }): Banner?
	if drop == nil or now - drop.at >= RareAnnounce.DROP_SECONDS or now < drop.at - 5 then
		return nil
	end
	local mark = if drop.tier == RareAnnounce.SECRET_TIER then "🌌 SECRET 🌌" else "✨"
	if drop.text then
		return { text = `{mark} {drop.text}`, kind = "drop" }
	end
	local name = if drop.tier and tierNames[drop.tier] then string.upper(tierNames[drop.tier]) else "RARE"
	return { text = `{mark} A {name} slime spilled from the fountain! Grab it!`, kind = "drop" }
end

return table.freeze(RareAnnounce)
