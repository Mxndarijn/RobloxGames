--!strict
--[[
	SlimeAnim (v28 #17): the animated side of the slime rig, as pure logic.
	The Roblox side is SlimeLifeRunner.client.luau; tests/ui/SlimeAnim.spec.luau
	covers this under Lune.

	  SlimeAnim.NAMES                     the animations the rig plays
	  SlimeAnim.ids(lookup) -> Ids?       lookup(name) -> "rbxassetid://.." | nil;
	                                      nil unless idle and both looks exist
	                                      (then SlimeLife's procedural idle runs)
	  SlimeAnim.newSchedule(params, now, rand) -> Schedule
	  SlimeAnim.tick(sched, params, now, rand) -> { Event }
	                                      "LookLeft" | "LookRight" (slimes glide, they
	                                      never hop on their own: contract/slime-walk.md),
	                                      never more than one look, no catch-up after a
	                                      long gap (off-screen slimes)
	  SlimeAnim.newTracks(load) -> Tracks share track loading: one load(name) per
	                                      animation and rig, however often it is
	                                      acquired / released

	LOD (distance, on screen, at most SlimeLife.MAX_ACTIVE rigs) is
	SlimeLife.select with Candidate.onScreen.
]]

local SlimeLife = if script then require(script.Parent.SlimeLife) else require("./SlimeLife")

local SlimeAnim = {}

SlimeAnim.NAMES = table.freeze({
	idle = "SlimeIdleSquish",
	lookLeft = "SlimeLookLeft",
	lookRight = "SlimeLookRight",
} :: { [string]: string })
SlimeAnim.LOOK_LENGTH = 0.4
SlimeAnim.FADE = 0.15

SlimeAnim.LOAD_TIMEOUT = 3 -- seconds a track may take to report Length > 0 before it counts as failed

export type Mode = "anim" | "motor" | "weld"

export type Verdict = "ok" | "wait" | "failed"

export type Ids = { idle: string, lookLeft: string, lookRight: string }

export type Schedule = { lookAt: number }

export type Event = "LookLeft" | "LookRight"

export type Tracks = { get: (self: Tracks, key: string) -> any?, loads: number }

type Rand = () -> number

function SlimeAnim.ids(lookup: (string) -> string?): Ids?
	local ids: any = {}
	for key, name in SlimeAnim.NAMES do
		local id = lookup(name)
		if not id then
			return nil
		end
		ids[key] = id
	end
	return ids
end

-- `length` is AnimationTrack.Length (0 until the asset loaded, stays 0 when it
-- can't: wrong owner, moderation, bad data); `age` seconds since the load
-- started; `playing` (optional) IsPlaying of a track that was Played.
function SlimeAnim.verdict(length: number?, age: number, playing: boolean?): Verdict
	if length ~= nil and length > 0 and playing ~= false then
		return "ok"
	end
	if age < SlimeAnim.LOAD_TIMEOUT then
		return "wait"
	end
	return "failed"
end

function SlimeAnim.mode(flag: boolean, ids: Ids?, hasAnimator: boolean, verdict: Verdict?, rigged: boolean): Mode
	if flag and ids and hasAnimator and verdict == "ok" then
		return "anim"
	end
	return if rigged then "motor" else "weld"
end

local function between(range: { number }, rand: Rand): number
	return range[1] + rand() * (range[2] - range[1])
end

function SlimeAnim.newSchedule(params: SlimeLife.Params, now: number, rand: Rand): Schedule
	return { lookAt = now + between(params.lookEvery, rand) }
end

function SlimeAnim.tick(sched: Schedule, params: SlimeLife.Params, now: number, rand: Rand): { Event }
	local events: { Event } = {}
	if now >= sched.lookAt then
		table.insert(events, if rand() < 0.5 then "LookLeft" else "LookRight")
		sched.lookAt = now + SlimeAnim.LOOK_LENGTH + between(params.lookEvery, rand)
	end
	return events
end

function SlimeAnim.newTracks(load: (string) -> any?): Tracks
	local cache: { [string]: any } = {}
	local tracks = { loads = 0 } :: any
	function tracks.get(self: any, key: string): any?
		local track = cache[key]
		if track == nil then
			track = load(key)
			if track ~= nil then
				cache[key] = track
				self.loads += 1
			end
		end
		return track
	end
	return tracks
end

return SlimeAnim
