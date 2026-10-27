--!strict
--[[
	SoundCues (pure, FEATURES.Audio)

	Sounds for State changes that come with no Notify sound. Compares two State pushes and returns what to play
	(no Roblox APIs; loads under Lune, tests/ui/SoundCues.spec.luau):
	  * the boss is beaten (phase -> "won"): "BossDefeat" for everyone (the carrier hears "BossMvp" with the Boss
	    Champion Notify)
	  * a new SlimeDex species: "DexNew"
	  * the tutorial moves on a step, or finishes: "TutorialTick"
	The very first State after joining never cues (prev nil): it is how things already were.
	The boss's attacks are timed from the boss model's attributes instead (ui/WorldAudio): State can lag a second.

	  SoundCues.diff(prev, next, myName?) -> { Cue }   myName: the local player's DisplayName (State.boss.winnerName)
	  SoundCues.bossMusic(state) -> boolean           the boss track plays during the fight and the haul
	  SoundCues.watcher(myName?) -> (state) -> { Cue } keeps the previous State for you
]]

local Shared = if script then (game:GetService("ReplicatedStorage") :: any).Shared else nil
local Types = if Shared then require(Shared.Types) else require("../shared/Types")

local SoundCues = {}

export type Cue = { name: string }

local function dexFound(state: Types.State): number
	local dex = state.dex
	return if dex and type(dex.found) == "number" then dex.found else 0
end

-- The tutorial's position: its step number, or math.huge once it is finished (tutorialStep nil).
local function tutorialAt(state: Types.State): number
	return if type(state.tutorialStep) == "number" then state.tutorialStep else math.huge
end

function SoundCues.diff(prev: Types.State?, next: Types.State, _myName: string?): { Cue }
	local out: { Cue } = {}
	if prev == nil then
		return out
	end
	local was, now = prev.boss, next.boss
	if now and now.phase == "won" and (was == nil or was.phase ~= "won") then
		table.insert(out, { name = "BossDefeat" })
	end
	if dexFound(next) > dexFound(prev) then
		table.insert(out, { name = "DexNew" })
	end
	if tutorialAt(next) > tutorialAt(prev) then
		table.insert(out, { name = "TutorialTick" })
	end
	return out
end

function SoundCues.bossMusic(state: Types.State?): boolean
	local boss = state and state.boss
	return boss ~= nil and (boss.phase == "fight" or boss.phase == "haul")
end

-- A diff that remembers the last State it saw: call it with every State push.
function SoundCues.watcher(myName: string?): (state: Types.State) -> { Cue }
	local last: Types.State? = nil
	return function(state: Types.State): { Cue }
		local cues = SoundCues.diff(last, state, myName)
		last = state
		return cues
	end
end

return table.freeze(SoundCues)
