--!strict
--[[
	WorldAudioLogic (pure, ui/WorldAudio)

	The rules behind the world sounds, as numbers and tables (no Roblox APIs; loads under Lune,
	tests/ui/WorldAudioLogic.spec.luau). WorldAudio reads model attributes and hands the values here;
	what comes back is a list of timed cues it plays at the right moment.

	A cue: a sound name (Sounds.IDS), the server time it plays, a key (the same key is never played twice)
	and where: `x` / `z` on the floor (a spit, a rune) or nil = at the model that made it (the boss, the egg).

	  WorldAudioLogic.spots(text) -> { { number } }               "a,b,c;d,e,f" attribute lists
	  WorldAudioLogic.spitCues(text) -> { Cue }                     BossSpits: "BossGoo" when each spit lands
	  WorldAudioLogic.runeCues(text) -> { Cue }                     BossRunes: "BossSlam" when each rune bursts
	  WorldAudioLogic.moveCues(move, attack?) -> { Cue }            BossMove: the windup, and each stomp / landing
	  WorldAudioLogic.hatchCues(id, hatchedAt) -> { Cue }           Mystery Egg: each rock, then the crack
	  WorldAudioLogic.popCues(id, hatchedAt, now) -> { Cue }        the hatched slime arrives: crack (if missed) + pop
	  WorldAudioLogic.ritualCues(prev, next) -> { RitualCue }       ritual circle: a spot taken, the ritual done
	  WorldAudioLogic.loopId(id) -> string?                         a looped bed's id, nil = silent
	  WorldAudioLogic.newSchedule() / schedule(s, cues, now, cfg) / due(s, now, cfg) -> { Cue }
]]

local Shared = if script then (game:GetService("ReplicatedStorage") :: any).Shared else nil
local BossAttacks = if Shared then require(Shared.BossAttacks) else require("../shared/BossAttacks")
local BossChoreo = if Shared then require(Shared.BossChoreo) else require("../shared/BossChoreo")
local Config = if Shared then require(Shared.Config) else require("../shared/Config")
local Visuals = if script then (game:GetService("ReplicatedStorage") :: any).Visuals else nil
local EggHatchTimeline = if Shared
	then require(Visuals.EggHatchTimeline)
	else require("../visuals/shared/EggHatchTimeline")

local BOSS = Config.BOSS

local WorldAudioLogic = {}

export type Cue = {
	key: string,
	name: string,
	at: number, -- server time it plays
	x: number?, -- floor spot (world studs); nil = at the model the cue came from
	z: number?,
}

-- What WorldAudio reads from the ritual circle each look: its Phase and the Taken flag of each spot.
export type RitualLook = { phase: string?, taken: { boolean } }
export type RitualCue = { name: string, spot: number? } -- spot nil = at the orb

export type Schedule = {
	pending: { Cue },
	seen: { [string]: number }, -- key -> the server time it was due (forgotten FORGET_SECONDS later)
}

-- "1,2,3;4,5,6" -> { { 1, 2, 3 }, { 4, 5, 6 } }; junk values read as 0, anything that isn't a string as no spots.
function WorldAudioLogic.spots(text: any): { { number } }
	local out = {}
	if type(text) ~= "string" or text == "" then
		return out
	end
	for _, item in string.split(text, ";") do
		local values = {}
		for _, v in string.split(item, ",") do
			table.insert(values, tonumber(v) or 0)
		end
		table.insert(out, values)
	end
	return out
end

local function spotKey(prefix: string, x: number, z: number, at: number): string
	return string.format("%s:%.1f:%.1f:%.2f", prefix, x, z, at)
end

-- A goo splat where each spit lands, when it lands.
function WorldAudioLogic.spitCues(text: any): { Cue }
	local out = {}
	for _, s in WorldAudioLogic.spots(text) do
		if #s >= 3 then
			table.insert(
				out,
				{ key = spotKey("spit", s[1], s[2], s[3]), name = "BossGoo", at = s[3], x = s[1], z = s[2] }
			)
		end
	end
	return out
end

-- A slam where each rune puddle bursts into its ring.
function WorldAudioLogic.runeCues(text: any): { Cue }
	local out = {}
	for _, r in WorldAudioLogic.spots(text) do
		if #r >= 3 then
			table.insert(
				out,
				{ key = spotKey("rune", r[1], r[2], r[3]), name = "BossSlam", at = r[3], x = r[1], z = r[2] }
			)
		end
	end
	return out
end

--[[
	The sounds of one boss move (BossChoreo.Move), at the boss: the windup's rising telegraph as it starts, a slam
	for each wave of a ring attack (a double stomp slams twice), when a hop lands, when it drops in (arrive) and when
	it floats back down (land). `attack` is the move's definition (BossAttacks.get(species, move.slot)); without it a
	ring stomps once.
]]
function WorldAudioLogic.moveCues(move: BossChoreo.Move, attack: BossAttacks.Attack?): { Cue }
	local out = {}
	local function add(tag: string, name: string, at: number)
		table.insert(out, { key = `move:{move.n}:{tag}`, name = name, at = at })
	end
	local kind = move.kind
	if kind == "windup" then
		add("windup", "BossWindup", move.at)
	elseif kind == "attack" and attack and attack.kind == "ring" then
		for i, wave in BossAttacks.waves(move, attack) do
			add(`wave{i}`, "BossSlam", wave[1])
		end
	elseif kind == "hop" then
		add("hop", "BossSlam", move.at + BOSS.HOP_SECONDS)
	elseif kind == "arrive" then
		add("arrive", "BossSlam", move.at + BOSS.ARRIVE_FALL)
	elseif kind == "land" then
		add("land", "BossSlam", move.at + move.seconds)
	end
	return out
end

-- The egg's hatch show (EggHatchTimeline): a wobble at the start of each rock, the crack at the burst.
function WorldAudioLogic.hatchCues(id: string, hatchedAt: number): { Cue }
	local out = {}
	local each = EggHatchTimeline.WOBBLE_END / EggHatchTimeline.WOBBLES
	for n = 1, EggHatchTimeline.WOBBLES do
		table.insert(out, { key = `egg:{id}:wobble{n}`, name = "EggWobble", at = hatchedAt + (n - 1) * each })
	end
	table.insert(out, { key = `egg:{id}:crack`, name = "EggCrack", at = hatchedAt + EggHatchTimeline.BURST })
	return out
end

--[[
	The hatched slime's model reached this client: the pop, at the burst or now if it came later. Also the crack under
	the same key as hatchCues, so a client that never saw the egg still hears it (the schedule plays a key once). A
	slime that arrives more than EggHatchTimeline.LATE after the burst gets no pop (EggHatchFx draws none either).
]]
function WorldAudioLogic.popCues(id: string, hatchedAt: number, now: number): { Cue }
	local burst = hatchedAt + EggHatchTimeline.BURST
	if now - burst > EggHatchTimeline.LATE then
		return {}
	end
	local at = math.max(now, burst)
	return {
		{ key = `egg:{id}:crack`, name = "EggCrack", at = at },
		{ key = `egg:{id}:pop`, name = "EggHatch", at = at },
	}
end

-- Ritual circle changes between two looks. The first look (prev nil) never cues: it is how the circle already was.
function WorldAudioLogic.ritualCues(prev: RitualLook?, next: RitualLook): { RitualCue }
	local out = {}
	if prev == nil then
		return out
	end
	for i, taken in next.taken do
		if taken and not prev.taken[i] then
			table.insert(out, { name = "RitualSpot", spot = i })
		end
	end
	if prev.phase == "Charging" and next.phase == "Cooldown" then
		table.insert(out, { name = "RitualDone" })
	end
	return out
end

-- The ritual hum sounds while the circle charges.
function WorldAudioLogic.humOn(look: RitualLook?): boolean
	return look ~= nil and look.phase == "Charging"
end

function WorldAudioLogic.newSchedule(): Schedule
	return { pending = {}, seen = {} }
end

-- Queues every cue whose key is new. A cue already more than cfg.LATE_SECONDS past its time is dropped (someone
-- walked in mid-attack or joined mid-hatch); its key still counts as seen.
function WorldAudioLogic.schedule(s: Schedule, cues: { Cue }, now: number, cfg: any)
	for _, cue in cues do
		if s.seen[cue.key] == nil then
			s.seen[cue.key] = cue.at
			if now - cue.at <= cfg.LATE_SECONDS then
				table.insert(s.pending, cue)
			end
		end
	end
end

-- The cues due by `now`, in time order; they leave the queue. Old keys are forgotten here too.
function WorldAudioLogic.due(s: Schedule, now: number, cfg: any): { Cue }
	local out = {}
	for i = #s.pending, 1, -1 do
		local cue = s.pending[i]
		if cue.at <= now then
			table.remove(s.pending, i)
			if now - cue.at <= cfg.LATE_SECONDS then
				table.insert(out, cue)
			end
		end
	end
	table.sort(out, function(a, b)
		return a.at < b.at
	end)
	for key, at in s.seen do
		if now - at > cfg.FORGET_SECONDS then
			s.seen[key] = nil
		end
	end
	return out
end

-- A looped bed's id when it is a real "rbxassetid://<n>" (n > 0), else nil: that bed stays silent.
function WorldAudioLogic.loopId(id: any): string?
	local n = if type(id) == "string" then tonumber(string.match(id, "^rbxassetid://(%d+)$")) else nil
	return if n and n > 0 then id else nil
end

-- Whether a sound at `distance` studs from the camera is worth playing.
function WorldAudioLogic.audible(distance: number, cfg: any): boolean
	return distance <= cfg.CULL_DISTANCE
end

return table.freeze(WorldAudioLogic)
