--!strict
--[[
	RareAnnounce

	Rare-spawn banner rules: the Boss Slime and (v13, CONTRACT §8.6 / §8.7)
	Legendary+ wild drops. Pure (tests/ui/RareAnnounce.spec.luau); Hud feeds
	it and renders the banner.

	Legendary+ drops are contracted: workspace `RareSpawnId` / `RareSpawnTier`
	/ `RareSpawnAt` (set together per drop) and a Notify with sound "Rare"
	("A LEGENDARY <name> spilled from the fountain!"). The Notify text is used
	when it arrives; the attributes alone give a generic banner.

	CONTRACT §2 Extras gives no State field for the boss, so the client
	combines two signals:
	  1. World: a slime model with attribute `Boss = true`
	     (Constants.BOSS_ATTRIBUTE); its GrabPrompt ObjectText starts with
	     "BOSS ". Authoritative while the model is replicated.
	  2. Notify text heuristic (the spawn Notify uses sound "Rain"; text
	     "A BOSS SLIME slid into the plaza: <name>! ..."; the catch is "<who> caught the
	     Boss Slime!"). Covers streamed-out models. If the server wording
	     changes, only the patterns below need updating.
	A future `State.boss` / Notify kind would replace both (docs/archive/UI-CONTRACT-GAPS.md).
]]

local Format = if script then require(script.Parent.Format) else require("./Format")

export type Boss = {
	name: string?,
	expiresAt: number?, -- server time; nil = unknown (keep while the model exists)
	carried: boolean,
}
export type Drop = { tier: number?, at: number, text: string? } -- at = server time of the drop
export type Banner = { text: string, kind: "boss" | "caught" | "drop" }

local RareAnnounce = {}

RareAnnounce.OBJECT_PREFIX = "BOSS "
-- How long the "X caught the Boss Slime!" banner stays up.
RareAnnounce.CAUGHT_SECONDS = 6
-- How long a Legendary+ drop banner stays up.
RareAnnounce.DROP_SECONDS = 10
RareAnnounce.DROP_SOUND = "Rare"
-- Secret drops (Config.SECRET_TIER) ring their own sound and get a bigger banner mark.
RareAnnounce.SECRET_SOUND = "Secret"
RareAnnounce.SECRET_TIER = 7

-- "spawn" / "caught" (boss), "drop" (Legendary+) or nil for a Notify.
function RareAnnounce.classify(text: any, sound: any): ("spawn" | "caught" | "drop")?
	if type(text) ~= "string" then
		return nil
	end
	local lower = string.lower(text)
	if string.find(lower, "caught the boss slime", 1, true) then
		return "caught"
	end
	if string.find(lower, "boss slime", 1, true) then
		return "spawn"
	end
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

-- Slime name from the spawn Notify ("... slid into the plaza: Glow Globble! ..."), else nil.
function RareAnnounce.nameFromNotify(text: string): string?
	local name = string.match(text, ":%s*(.-)!")
	return if name and #name > 0 then name else nil
end

-- Prompt ObjectText "BOSS Glow Globble" -> "Glow Globble"; nil if not a boss.
function RareAnnounce.nameFromObjectText(text: any): string?
	if type(text) ~= "string" then
		return nil
	end
	local prefix = RareAnnounce.OBJECT_PREFIX
	if string.sub(text, 1, #prefix) ~= prefix then
		return nil
	end
	local name = string.sub(text, #prefix + 1)
	return if #name > 0 then name else nil
end

-- Banner for the current boss / last catch at server time `now`, or nil.
-- A catch banner wins over a (now stale) boss banner.
function RareAnnounce.banner(boss: Boss?, caught: { text: string, untilTime: number }?, now: number): Banner?
	if caught and now < caught.untilTime then
		return { text = `👑 {caught.text}`, kind = "caught" }
	end
	if boss == nil then
		return nil
	end
	local left = if boss.expiresAt then boss.expiresAt - now else nil
	if left and left <= 0 then
		return nil
	end
	local name = if boss.name then `: {boss.name}` else ""
	if boss.carried then
		return { text = `👑 BOSS SLIME{name} is being carried - chase & hit them with your bat!`, kind = "boss" }
	end
	local timer = if left then ` - {Format.formatDuration(left)}` else ""
	return { text = `👑 BOSS SLIME{name}! Grab it at the fountain{timer}`, kind = "boss" }
end

return table.freeze(RareAnnounce)
