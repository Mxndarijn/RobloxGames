--!strict
--[[
	SlimeAudioLogic (pure): which slime sounds play (ui/SlimeAudio plays them). A full plot holds about 30 slimes,
	so every hop can't squish: cues queue up and `pick` lets through the nearest ones within a budget.

	  SlimeAudioLogic.ATTRIBUTES                    client-only model attributes ui/SlimeActor writes (os.clock times)
	  SlimeAudioLogic.new() -> State
	  SlimeAudioLogic.offer(state, cue)             queue one cue for the next pick
	  SlimeAudioLogic.pick(state, now, cfg, roll) -> { Cue }   what plays now, nearest first; empties the queue
	  SlimeAudioLogic.forget(state, key)            a slime is gone
	  SlimeAudioLogic.stateCue(prev, state) -> "pickup" | "putdown" | nil   from a change of the model's State
	  SlimeAudioLogic.speedFor(size, cfg) -> PlaybackSpeed (bigger slimes lower)

	Budget (`cfg` = Config.AUDIO.SLIME): nothing past MAX_DISTANCE; one cue per slime per frame (the most important);
	pickup / put-down always play; a squish or blip waits SLIME_GAP after that slime's last sound, at most
	MAX_PER_SECOND of them in any second; a blip only plays BLIP_CHANCE of the time and BLIP_GAP apart.
	`roll` returns 0..1.
]]

local SlimeAudioLogic = {}

SlimeAudioLogic.ATTRIBUTES = table.freeze({
	land = "LifeLandAt", -- a hop or a pad fidget landed
	blip = "LifeBlipAt", -- a pad fidget started or an emote bubble came up
	arrive = "LifeArriveAt", -- a slime moved to another pad landed there
})

export type Kind = "land" | "blip" | "pickup" | "putdown"

export type Cue = {
	key: any, -- the slime (its model)
	kind: Kind,
	distance: number, -- studs from the camera
	size: number?, -- the model's Size attribute (pitch)
	at: any?, -- where it plays (the adapter's part); passed through untouched
}

export type State = {
	queue: { Cue },
	lastAt: { [any]: number }, -- per slime: its last sound
	played: { number }, -- times of squishes / blips in the last second
	blipAt: number, -- the last blip on any slime
}

-- Higher wins when one slime offers several cues in one frame.
local RANK: { [string]: number } = { pickup = 4, putdown = 3, land = 2, blip = 1 }

function SlimeAudioLogic.new(): State
	return { queue = {}, lastAt = {}, played = {}, blipAt = -math.huge }
end

function SlimeAudioLogic.offer(state: State, cue: Cue)
	table.insert(state.queue, cue)
end

function SlimeAudioLogic.forget(state: State, key: any)
	state.lastAt[key] = nil
end

local function important(kind: Kind): boolean
	return kind == "pickup" or kind == "putdown"
end

function SlimeAudioLogic.pick(state: State, now: number, cfg: any, roll: () -> number): { Cue }
	local queue = state.queue
	state.queue = {}
	-- one cue per slime: the most important, then the nearest offer of it
	local best: { [any]: Cue } = {}
	for _, cue in queue do
		local had = best[cue.key]
		if not had or RANK[cue.kind] > RANK[had.kind] then
			best[cue.key] = cue
		end
	end
	local list: { Cue } = {}
	for _, cue in best do
		if cue.distance <= cfg.MAX_DISTANCE then
			table.insert(list, cue)
		end
	end
	table.sort(list, function(a, b)
		if important(a.kind) ~= important(b.kind) then
			return important(a.kind)
		end
		return a.distance < b.distance
	end)
	local recent: { number } = {}
	for _, t in state.played do
		if now - t < 1 then
			table.insert(recent, t)
		end
	end
	state.played = recent
	local out: { Cue } = {}
	for _, cue in list do
		local ok
		if important(cue.kind) then
			ok = true
		else
			local last = state.lastAt[cue.key]
			ok = (last == nil or now - last >= cfg.SLIME_GAP) and #state.played < cfg.MAX_PER_SECOND
			if ok and cue.kind == "blip" then
				ok = now - state.blipAt >= cfg.BLIP_GAP and roll() < cfg.BLIP_CHANCE
				if ok then
					state.blipAt = now
				end
			end
			if ok then
				table.insert(state.played, now)
			end
		end
		if ok then
			state.lastAt[cue.key] = now
			table.insert(out, cue)
		end
	end
	return out
end

function SlimeAudioLogic.stateCue(prev: string?, state: string?): Kind?
	if state == "Carried" and prev ~= "Carried" and prev ~= nil then
		return "pickup"
	end
	if prev == "Carried" and state ~= nil and state ~= "Carried" then
		return "putdown"
	end
	return nil
end

function SlimeAudioLogic.speedFor(size: number?, cfg: any): number
	local s = if type(size) == "number" and size == size then size else 1
	return math.clamp(cfg.SPEED_AT_SIZE_1 - cfg.SPEED_PER_SIZE * (s - 1), cfg.SPEED_MIN, cfg.SPEED_MAX)
end

return SlimeAudioLogic
