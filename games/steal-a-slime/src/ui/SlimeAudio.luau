--!strict
--[[
	SlimeAudio (client, FEATURES.Audio): the slimes' own sounds, 3D at the slime.
	  * a soft SlimeSquish when a hop or a pad fidget lands, pitched by size (bigger = lower);
	  * now and then a SlimeBlip when a pad fidget starts or an emote bubble comes up;
	  * SlimePickup when a slime gets carried, SlimePutdown when it is put down (its State leaves "Carried") or
	    lands after a move to another pad.
	Landings, fidgets and emotes come from client-only model attributes ui/SlimeActor writes
	(SlimeAudioLogic.ATTRIBUTES); pickup and put-down from the replicated State. Slimes the LOD draws "far"
	(LifeTier) or past MAX_DISTANCE from the camera make no squish or blip. Cues of one frame are collected and
	played together after it, nearest first, within the SlimeAudioLogic budget. Event driven: no frame loop.

	  local stop = SlimeAudio.start(opts?)   stop() disconnects everything it made
]]

local CollectionService = game:GetService("CollectionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Config"))
local Constants = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Constants"))
local SlimeAudioLogic = require(script.Parent:WaitForChild("SlimeAudioLogic"))
local SoundController = require(script.Parent:WaitForChild("SoundController"))

local SlimeAudio = {}

export type Options = {
	collection: CollectionService?,
	tag: string?, -- default Constants.SLIME_TAG
	camera: (() -> Camera?)?,
	play: ((name: string, opts: SoundController.PlayOptions) -> boolean)?, -- default SoundController.play
	playVariant: ((group: string, opts: SoundController.PlayOptions) -> boolean)?, -- default SoundController.playVariant
	clock: (() -> number)?,
	roll: (() -> number)?,
}

local ATTR = SlimeAudioLogic.ATTRIBUTES
local KIND_OF: { [string]: SlimeAudioLogic.Kind } = {
	[ATTR.land] = "land",
	[ATTR.blip] = "blip",
	[ATTR.arrive] = "putdown",
}

local function bodyOf(model: Instance): BasePart?
	local body = model:FindFirstChild("Body")
	if body and body:IsA("BasePart") then
		return body
	end
	local primary = if model:IsA("Model") then model.PrimaryPart else nil
	return primary
end

function SlimeAudio.start(opts: Options?): () -> ()
	local o: Options = opts or {}
	local cfg = Config.AUDIO.SLIME
	local collection: CollectionService = o.collection or CollectionService
	local tag = o.tag or Constants.SLIME_TAG
	local cameraOf = o.camera or function(): Camera?
		return workspace.CurrentCamera
	end
	local play = o.play or SoundController.play
	local playVariant = o.playVariant or SoundController.playVariant
	local clock = o.clock or os.clock
	local rng = Random.new()
	local roll = o.roll or function(): number
		return rng:NextNumber()
	end

	local state = SlimeAudioLogic.new()
	local lastState: { [Instance]: string? } = {}
	local conns: { [Instance]: RBXScriptConnection } = {}
	local flushQueued = false
	local stopped = false

	local function flush()
		flushQueued = false
		if stopped then
			return
		end
		for _, cue in SlimeAudioLogic.pick(state, clock(), cfg, roll) do
			local at = cue.at
			if not (at and at.Parent) then
				continue
			end
			if cue.kind == "land" then
				playVariant(
					"SlimeSquish",
					{ at = at, volume = cfg.LAND_VOLUME, speed = SlimeAudioLogic.speedFor(cue.size, cfg) }
				)
			elseif cue.kind == "blip" then
				playVariant(
					"SlimeBlip",
					{ at = at, volume = cfg.BLIP_VOLUME, speed = SlimeAudioLogic.speedFor(cue.size, cfg) }
				)
			elseif cue.kind == "pickup" then
				play("SlimePickup", { at = at, volume = cfg.CARRY_VOLUME })
			else
				play("SlimePutdown", { at = at, volume = cfg.CARRY_VOLUME })
			end
		end
	end

	local function offer(model: Instance, kind: SlimeAudioLogic.Kind)
		local body = bodyOf(model)
		local camera = cameraOf()
		if not (body and camera) then
			return
		end
		-- squishes and blips only from slimes the LOD still animates (near / mid)
		if (kind == "land" or kind == "blip") and model:GetAttribute("LifeTier") == "far" then
			return
		end
		local distance = (body.Position - camera.CFrame.Position).Magnitude
		if distance > cfg.MAX_DISTANCE then
			return
		end
		local size = model:GetAttribute("Size")
		SlimeAudioLogic.offer(state, {
			key = model,
			kind = kind,
			distance = distance,
			size = if type(size) == "number" then size else nil,
			at = body,
		})
		if not flushQueued then
			flushQueued = true
			task.defer(flush)
		end
	end

	local function watch(model: Instance)
		if conns[model] then
			return
		end
		local s = model:GetAttribute("State")
		lastState[model] = if type(s) == "string" then s else nil
		conns[model] = model.AttributeChanged:Connect(function(name: string)
			if name == "State" then
				local now = model:GetAttribute("State")
				local cur = if type(now) == "string" then now else nil
				local kind = SlimeAudioLogic.stateCue(lastState[model], cur)
				lastState[model] = cur
				if kind then
					offer(model, kind)
				end
				return
			end
			local kind = KIND_OF[name]
			if kind then
				offer(model, kind)
			end
		end)
	end

	local function unwatch(model: Instance)
		local c = conns[model]
		if c then
			c:Disconnect()
		end
		conns[model] = nil
		lastState[model] = nil
		SlimeAudioLogic.forget(state, model)
	end

	local added = collection:GetInstanceAddedSignal(tag):Connect(watch)
	local removed = collection:GetInstanceRemovedSignal(tag):Connect(unwatch)
	for _, model in collection:GetTagged(tag) do
		watch(model)
	end

	return function()
		stopped = true
		added:Disconnect()
		removed:Disconnect()
		for model in conns do
			unwatch(model)
		end
	end
end

return SlimeAudio
