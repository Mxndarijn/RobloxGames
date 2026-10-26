--!strict
--[[
	Footsteps (client, FEATURES.Audio): steps that match the ground. Roblox's character sounds play one footstep
	loop (the Sound "Running" in HumanoidRootPart) on every floor. On a floor Config.AUDIO.SLIME.STEP_MATERIALS
	lists (Humanoid.FloorMaterial, so Terrain and parts alike) that loop is muted and a StepGrass / StepSnow variant
	plays at the character's root once per stride (FootstepsLogic); on any other floor, in the air or standing, the
	loop gets its volume back. Ground snow (SnowCover) turns grass steps into snow steps.
	Runs for the local player and for other players within OTHERS_DISTANCE of the camera.

	  local stop, step = Footsteps.start(opts?)
	  step(dt?)   from the client loop; dt defaults to the time since the last call. Works from a 0.1 s loop:
	              each call schedules the steps due before the next one.
	  stop()      restores every muted loop and cancels scheduled steps
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Config"))
local Constants = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Constants"))
local FootstepsLogic = require(script.Parent:WaitForChild("FootstepsLogic"))
local SoundController = require(script.Parent:WaitForChild("SoundController"))

local Footsteps = {}

Footsteps.RUNNING_SOUND = "Running" -- RbxCharacterSounds' footstep loop in HumanoidRootPart

export type Options = {
	players: Players?,
	camera: (() -> Camera?)?,
	play: ((group: string, opts: SoundController.PlayOptions) -> boolean)?, -- default SoundController.playVariant
	snowCover: (() -> number)?, -- 0..1 ground snow; default from the workspace weather stamps (SnowCover.levelAt)
	clock: (() -> number)?,
}

type Entry = {
	walker: FootstepsLogic.Walker,
	running: Sound?, -- the loop we muted
	volume: number, -- its volume before we muted it
	seen: boolean,
}

local function defaultSnowCover(): () -> number
	local visuals = ReplicatedStorage:FindFirstChild("Visuals")
	local module = visuals and visuals:FindFirstChild("SnowCover")
	local ok, SnowCover = pcall(function()
		return if module and module:IsA("ModuleScript") then require(module) :: any else nil
	end)
	return function(): number
		local snowing = workspace:GetAttribute(Constants.WEATHER_ATTRIBUTE) == "Snow"
		if not (Config.FEATURES.Weather and ok and SnowCover) then
			return if snowing and Config.FEATURES.Weather then 1 else 0
		end
		return SnowCover.levelAt(
			snowing,
			workspace:GetAttribute(Constants.WEATHER_STARTED_ATTRIBUTE),
			workspace:GetAttribute(Constants.SNOW_ENDED_ATTRIBUTE),
			workspace:GetServerTimeNow()
		)
	end
end

function Footsteps.start(opts: Options?): (() -> (), (dt: number?) -> ())
	local o: Options = opts or {}
	local cfg = Config.AUDIO.SLIME
	local players: Players = o.players or Players
	local cameraOf = o.camera or function(): Camera?
		return workspace.CurrentCamera
	end
	local play = o.play or SoundController.playVariant
	local snowCover = o.snowCover or defaultSnowCover()
	local clock = o.clock or os.clock
	local entries: { [Model]: Entry } = {}
	local generation = 0 -- bumped by stop(): scheduled steps of an old run don't play
	local lastAt: number? = nil

	local function unmute(entry: Entry)
		local running = entry.running
		if running and running.Parent and running.Volume == 0 then
			running.Volume = entry.volume
		end
		entry.running = nil
	end

	local function mute(entry: Entry, root: BasePart)
		if entry.running and entry.running.Parent == root then
			entry.running.Volume = 0
			return
		end
		local running = root:FindFirstChild(Footsteps.RUNNING_SOUND)
		if running and running:IsA("Sound") then
			entry.volume = if running.Volume > 0 then running.Volume else entry.volume
			running.Volume = 0
			entry.running = running
		end
	end

	local function stepFor(character: Model, humanoid: Humanoid, root: BasePart, horizon: number, isLocal: boolean)
		local entry = entries[character]
		local stride = FootstepsLogic.stride(humanoid.WalkSpeed, cfg)
		if not entry then
			entry = { walker = FootstepsLogic.new(stride, cfg), running = nil, volume = 0.65, seen = true }
			entries[character] = entry
		end
		entry.seen = true
		local set = if humanoid.Health > 0
			then FootstepsLogic.setFor(humanoid.FloorMaterial.Name, snowCover(), cfg)
			else nil
		if not set then
			unmute(entry)
			FootstepsLogic.reset(entry.walker, stride, cfg)
			return
		end
		mute(entry, root)
		local v = root.AssemblyLinearVelocity
		local speed = math.sqrt(v.X * v.X + v.Z * v.Z)
		local volume = if isLocal then cfg.STEP_VOLUME else cfg.OTHERS_STEP_VOLUME
		local gen = generation
		for _, delay in FootstepsLogic.advance(entry.walker, speed, horizon, stride, cfg) do
			local function fire()
				if gen == generation and root.Parent then
					play(set, { at = root, volume = volume })
				end
			end
			if delay < 1 / 120 then
				fire()
			else
				task.delay(delay, fire)
			end
		end
	end

	local function step(dt: number?)
		local now = clock()
		local horizon = dt or (if lastAt then now - lastAt else 0)
		lastAt = now
		horizon = math.min(horizon, 0.25) -- after a hitch, schedule no further ahead than this
		for _, entry in entries do
			entry.seen = false
		end
		local camera = cameraOf()
		local eye = if camera then camera.CFrame.Position else nil
		local localPlayer = players.LocalPlayer
		for _, p in players:GetPlayers() do
			local character = p.Character
			local humanoid = character and character:FindFirstChildOfClass("Humanoid")
			local root = character and character:FindFirstChild("HumanoidRootPart")
			if character and humanoid and root and root:IsA("BasePart") then
				local isLocal = p == localPlayer
				if isLocal or (eye and (root.Position - eye).Magnitude <= cfg.OTHERS_DISTANCE) then
					stepFor(character, humanoid, root, horizon, isLocal)
				end
			end
		end
		for character, entry in entries do
			if not entry.seen then
				unmute(entry)
				entries[character] = nil
			end
		end
	end

	local function stop()
		generation += 1
		for _, entry in entries do
			unmute(entry)
		end
		table.clear(entries)
	end

	return stop, step
end

return Footsteps
