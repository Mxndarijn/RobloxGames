--!strict
--[[
	GameLogic

	Pure rules for the Speed Escape course: speed gain while moving, checkpoint
	progression, win handling and save-data sanitizing. No Roblox services are
	used, so this module runs unchanged on the server and under Lune.
]]

export type Config = {
	baseSpeed: number, -- WalkSpeed for a fresh player
	maxSpeed: number, -- hard cap on WalkSpeed
	speedPerSecond: number, -- WalkSpeed gained per full second of movement
	winCooldown: number, -- seconds between two wins for the same player
}

export type PartialConfig = {
	baseSpeed: number?,
	maxSpeed: number?,
	speedPerSecond: number?,
	winCooldown: number?,
}

export type SaveData = {
	Wins: number,
	Speed: number,
}

export type WinState = {
	wins: number,
	stage: number,
	lastWinAt: number?,
}

local GameLogic = {}

GameLogic.DEFAULT_CONFIG = table.freeze({
	baseSpeed = 16,
	maxSpeed = 200,
	speedPerSecond = 1,
	winCooldown = 2,
}) :: Config

GameLogic.FIRST_STAGE = 1

local function resolve(config: PartialConfig?): Config
	local d = GameLogic.DEFAULT_CONFIG
	if not config then
		return d
	end
	return {
		baseSpeed = config.baseSpeed or d.baseSpeed,
		maxSpeed = config.maxSpeed or d.maxSpeed,
		speedPerSecond = config.speedPerSecond or d.speedPerSecond,
		winCooldown = config.winCooldown or d.winCooldown,
	}
end

local function isFiniteNumber(value: unknown): boolean
	return type(value) == "number" and value == value and value ~= math.huge and value ~= -math.huge
end

local function clampWith(speed: unknown, cfg: Config): number
	if not isFiniteNumber(speed) then
		return cfg.baseSpeed
	end
	return math.clamp(speed :: number, cfg.baseSpeed, cfg.maxSpeed)
end

-- Clamps `speed` into [baseSpeed, maxSpeed]; non-numbers / NaN become baseSpeed.
function GameLogic.clampSpeed(speed: unknown, config: PartialConfig?): number
	return clampWith(speed, resolve(config))
end

--[[
	Advances speed by one frame. `movingTime` accumulates seconds spent moving;
	every full second adds `speedPerSecond`. Returns (newSpeed, newMovingTime).
	Time stops accumulating while idle or once the cap is reached.
]]
function GameLogic.tickSpeed(
	speed: number,
	movingTime: number,
	dt: number,
	isMoving: boolean,
	config: PartialConfig?
): (number, number)
	local cfg = resolve(config)
	local current = clampWith(speed, cfg)
	local accumulated = if isFiniteNumber(movingTime) and movingTime > 0 then movingTime else 0
	if not isMoving or not isFiniteNumber(dt) or dt <= 0 or current >= cfg.maxSpeed then
		return current, accumulated
	end
	accumulated += dt
	local wholeSeconds = math.floor(accumulated)
	if wholeSeconds > 0 then
		accumulated -= wholeSeconds
		current = math.min(cfg.maxSpeed, current + wholeSeconds * cfg.speedPerSecond)
	end
	if current >= cfg.maxSpeed then
		accumulated = 0
	end
	return current, accumulated
end

--[[
	Checkpoint progression: only moves forward. Returns (newStage, changed).
	Invalid indices are ignored.
]]
function GameLogic.advanceStage(currentStage: number, checkpointIndex: unknown): (number, boolean)
	local stage = if isFiniteNumber(currentStage) then math.max(GameLogic.FIRST_STAGE, currentStage) else 1
	if not isFiniteNumber(checkpointIndex) then
		return stage, false
	end
	local index = math.floor(checkpointIndex :: number)
	if index > stage then
		return index, true
	end
	return stage, false
end

-- True when enough time has passed since the player's last win.
function GameLogic.canWin(lastWinAt: number?, now: number, config: PartialConfig?): boolean
	if lastWinAt == nil then
		return true
	end
	return now - lastWinAt >= resolve(config).winCooldown
end

--[[
	Applies a WinPad touch. Returns (accepted, newState); on acceptance wins
	is incremented, the stage resets and the cooldown starts. The input state
	is never mutated.
]]
function GameLogic.applyWin(state: WinState, now: number, config: PartialConfig?): (boolean, WinState)
	if not GameLogic.canWin(state.lastWinAt, now, config) then
		return false, state
	end
	return true,
		{
			wins = math.max(0, math.floor(state.wins)) + 1,
			stage = GameLogic.FIRST_STAGE,
			lastWinAt = now,
		}
end

-- Normalises anything read from a DataStore into valid SaveData.
function GameLogic.sanitizeSaveData(raw: unknown, config: PartialConfig?): SaveData
	local wins, speed = 0, nil
	if type(raw) == "table" then
		local data = raw :: { [any]: any }
		if isFiniteNumber(data.Wins) then
			wins = math.max(0, math.floor(data.Wins))
		end
		speed = data.Speed
	end
	return {
		Wins = wins,
		Speed = GameLogic.clampSpeed(speed, config),
	}
end

return table.freeze(GameLogic)
