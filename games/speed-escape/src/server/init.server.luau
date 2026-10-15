--!strict
-- Server entry point: builds the course, grows WalkSpeed while moving, tracks
-- checkpoints / wins and persists Wins + Speed. Rules live in Shared.GameLogic;
-- the course itself comes from Shared.StageGenerator.

local DataStoreService = game:GetService("DataStoreService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local StarterPlayer = game:GetService("StarterPlayer")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Constants = require(Shared:WaitForChild("Constants"))
local GameLogic = require(Shared:WaitForChild("GameLogic"))
local StageGenerator = require(Shared:WaitForChild("StageGenerator"))

type PlayerState = {
	wins: IntValue,
	speed: number,
	movingTime: number,
	stage: number,
	respawnPart: BasePart?,
	lastWinAt: number?,
	loaded: boolean, -- false until data load finished (successfully or not)
	canSaveRemote: boolean, -- false if the DataStore read failed: never overwrite unknown data
	finalSaved: boolean,
}

local SPAWN_OFFSET = Vector3.new(0, 4, 0)
-- Falling this far below the course surface sends the player back to their checkpoint.
local FALL_RESET_DEPTH = 30
local SAVE_RETRIES = 3

---------------------------------------------------------------------------
-- Course
---------------------------------------------------------------------------

-- Built before any player is handled; characters are teleported onto course.spawn on spawn.
local course = StageGenerator.build(workspace, { stageCount = Constants.STAGE_COUNT })
local fallResetY = course.spawn.Position.Y - FALL_RESET_DEPTH

-- New characters start with the jump StageGenerator's gap maths assumes.
StarterPlayer.CharacterUseJumpPower = true
StarterPlayer.CharacterJumpPower = Constants.JUMP_POWER
StarterPlayer.CharacterWalkSpeed = GameLogic.DEFAULT_CONFIG.baseSpeed

---------------------------------------------------------------------------
-- Remotes
---------------------------------------------------------------------------

local remotes = ReplicatedStorage:FindFirstChild(Constants.REMOTES_FOLDER)
if not remotes then
	remotes = Instance.new("Folder")
	remotes.Name = Constants.REMOTES_FOLDER
	remotes.Parent = ReplicatedStorage
end

local winEvent = Instance.new("RemoteEvent")
winEvent.Name = Constants.WIN_EVENT
winEvent.Parent = remotes

---------------------------------------------------------------------------
-- Persistence: DataStore with an in-memory fallback
---------------------------------------------------------------------------

local memoryStore: { [string]: GameLogic.SaveData } = {}
local dataStore: DataStore? = nil

do
	local ok, storeOrErr = pcall(function()
		return DataStoreService:GetDataStore(Constants.DATASTORE_NAME)
	end)
	if ok then
		-- Studio without API access hands out a store but every request fails, so probe once.
		local probeOk, probeErr = pcall(function()
			return storeOrErr:GetAsync("__probe")
		end)
		if probeOk then
			dataStore = storeOrErr
		else
			storeOrErr = probeErr
		end
	end
	if dataStore then
		ReplicatedStorage:SetAttribute(Constants.DATASTORE_MODE_ATTRIBUTE, "datastore")
	else
		ReplicatedStorage:SetAttribute(Constants.DATASTORE_MODE_ATTRIBUTE, "memory")
		warn(
			`[SpeedEscape] DataStore "{Constants.DATASTORE_NAME}" unavailable ({storeOrErr}). `
				.. "Using IN-MEMORY storage: progress will NOT persist after this server shuts down. "
				.. "(Publish the place and enable Studio API access to use DataStores.)"
		)
	end
end

local function keyFor(player: Player): string
	return `Player_{player.UserId}`
end

-- Returns (data, remoteOk). remoteOk is false when the DataStore read failed.
local function loadData(player: Player): (GameLogic.SaveData, boolean)
	local key = keyFor(player)
	local store = dataStore
	if store then
		local ok, result = pcall(function()
			return store:GetAsync(key)
		end)
		if ok then
			return GameLogic.sanitizeSaveData(result), true
		end
		warn(`[SpeedEscape] Load failed for {player.Name}: {result}. Progress this session will not be saved remotely.`)
		return GameLogic.sanitizeSaveData(memoryStore[key]), false
	end
	return GameLogic.sanitizeSaveData(memoryStore[key]), true
end

local function saveData(player: Player, state: PlayerState)
	local key = keyFor(player)
	local data = GameLogic.sanitizeSaveData({ Wins = state.wins.Value, Speed = state.speed })
	memoryStore[key] = data

	local store = dataStore
	if not store or not state.canSaveRemote then
		return
	end
	for attempt = 1, SAVE_RETRIES do
		local ok, err = pcall(function()
			store:SetAsync(key, data, { player.UserId })
		end)
		if ok then
			return
		end
		warn(`[SpeedEscape] Save failed for {player.Name} (attempt {attempt}/{SAVE_RETRIES}): {err}`)
		if attempt < SAVE_RETRIES then
			task.wait(attempt)
		end
	end
end

---------------------------------------------------------------------------
-- Players
---------------------------------------------------------------------------

local states: { [Player]: PlayerState } = {}

local function getHumanoid(player: Player): Humanoid?
	local character = player.Character
	return character and character:FindFirstChildOfClass("Humanoid")
end

local function applySpeed(player: Player, state: PlayerState)
	player:SetAttribute("Speed", state.speed)
	local humanoid = getHumanoid(player)
	if humanoid then
		humanoid.WalkSpeed = state.speed
	end
end

local function setStage(player: Player, state: PlayerState, stage: number)
	state.stage = stage
	player:SetAttribute("Stage", stage)
end

local function teleport(character: Model, part: BasePart)
	local root = character:FindFirstChild("HumanoidRootPart")
	if root and root:IsA("BasePart") then
		root.AssemblyLinearVelocity = Vector3.zero
	end
	character:PivotTo(part.CFrame + SPAWN_OFFSET)
end

local function onCharacterAdded(player: Player, character: Model)
	local state = states[player]
	if not state then
		return
	end
	character:WaitForChild("HumanoidRootPart", 10)
	local humanoid = character:WaitForChild("Humanoid", 10) :: Humanoid?
	if not humanoid or player.Character ~= character then
		return
	end
	-- Speed survives respawns (never below baseSpeed); jump stays at the course's design value.
	humanoid.WalkSpeed = GameLogic.clampSpeed(state.speed)
	humanoid.UseJumpPower = true
	humanoid.JumpPower = Constants.JUMP_POWER
	-- Defer so we run after the engine has placed the character at a spawn.
	task.defer(function()
		if player.Character == character and character.Parent then
			teleport(character, state.respawnPart or course.spawn)
		end
	end)
end

local function onPlayerAdded(player: Player)
	local leaderstats = Instance.new("Folder")
	leaderstats.Name = "leaderstats"
	local wins = Instance.new("IntValue")
	wins.Name = "Wins"
	wins.Parent = leaderstats
	leaderstats.Parent = player

	local state: PlayerState = {
		wins = wins,
		speed = GameLogic.DEFAULT_CONFIG.baseSpeed,
		movingTime = 0,
		stage = GameLogic.FIRST_STAGE,
		respawnPart = nil,
		lastWinAt = nil,
		loaded = false,
		canSaveRemote = false,
		finalSaved = false,
	}
	states[player] = state
	setStage(player, state, GameLogic.FIRST_STAGE)
	applySpeed(player, state)

	player.CharacterAdded:Connect(function(character)
		onCharacterAdded(player, character)
	end)
	if player.Character then
		task.spawn(onCharacterAdded, player, player.Character)
	end

	local data, remoteOk = loadData(player)
	if states[player] ~= state then
		return -- left while loading
	end
	wins.Value = data.Wins
	-- Keep any speed earned while the load was in flight.
	state.speed = math.max(state.speed, data.Speed)
	state.canSaveRemote = remoteOk
	state.loaded = true
	applySpeed(player, state)
end

local activeSaves = 0

local function finalSave(player: Player, state: PlayerState)
	if state.finalSaved or not state.loaded then
		return
	end
	state.finalSaved = true
	activeSaves += 1
	saveData(player, state)
	activeSaves -= 1
end

local function onPlayerRemoving(player: Player)
	local state = states[player]
	states[player] = nil
	if state then
		finalSave(player, state)
	end
end

---------------------------------------------------------------------------
-- Course interaction
---------------------------------------------------------------------------

local function playerFromHit(hit: BasePart): (Player?, Model?)
	local character = hit:FindFirstAncestorOfClass("Model")
	local player = character and Players:GetPlayerFromCharacter(character)
	if not player or not character then
		return nil, nil
	end
	local humanoid = character:FindFirstChildOfClass("Humanoid")
	if not humanoid or humanoid.Health <= 0 then
		return nil, nil
	end
	return player, character
end

for _, checkpoint in course.checkpoints do
	checkpoint.Touched:Connect(function(hit)
		local player = playerFromHit(hit)
		local state = player and states[player]
		if not player or not state then
			return
		end
		local stage, changed = GameLogic.advanceStage(state.stage, checkpoint:GetAttribute("StageIndex"))
		if changed then
			setStage(player, state, stage)
			state.respawnPart = checkpoint
		end
	end)
end

course.finish.Touched:Connect(function(hit)
	local player, character = playerFromHit(hit)
	local state = player and states[player]
	if not player or not character or not state then
		return
	end
	local accepted, result = GameLogic.applyWin({
		wins = state.wins.Value,
		stage = state.stage,
		lastWinAt = state.lastWinAt,
	}, os.clock())
	if not accepted then
		return
	end
	state.lastWinAt = result.lastWinAt
	state.wins.Value = result.wins
	state.respawnPart = nil
	setStage(player, state, result.stage)
	winEvent:FireClient(player, result.wins)
	teleport(character, course.spawn)
end)

---------------------------------------------------------------------------
-- Speed growth
---------------------------------------------------------------------------

RunService.Heartbeat:Connect(function(dt)
	for player, state in states do
		local humanoid = getHumanoid(player)
		local moving = humanoid ~= nil and humanoid.Health > 0 and humanoid.MoveDirection.Magnitude > 0
		local speed, movingTime = GameLogic.tickSpeed(state.speed, state.movingTime, dt, moving)
		state.movingTime = movingTime
		if speed ~= state.speed then
			state.speed = speed
			applySpeed(player, state)
		end

		local character = player.Character
		local root = character and character:FindFirstChild("HumanoidRootPart")
		if character and root and root:IsA("BasePart") and root.Position.Y < fallResetY then
			teleport(character, state.respawnPart or course.spawn)
		end
	end
end)

---------------------------------------------------------------------------
-- Lifecycle
---------------------------------------------------------------------------

Players.PlayerAdded:Connect(onPlayerAdded)
Players.PlayerRemoving:Connect(onPlayerRemoving)
for _, player in Players:GetPlayers() do
	task.spawn(onPlayerAdded, player)
end

game:BindToClose(function()
	for player, state in states do
		task.spawn(finalSave, player, state)
	end
	-- Also waits for saves already started by PlayerRemoving.
	local deadline = os.clock() + 25
	while activeSaves > 0 and os.clock() < deadline do
		task.wait(0.1)
	end
end)
