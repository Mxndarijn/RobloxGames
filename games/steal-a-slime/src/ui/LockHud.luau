--!strict
--[[
	LockHud

	Text and state for the HUD's lock block, Lock button and Buy-pad button.
	Pure (tests/ui/LockHud.spec.luau); Hud renders it. Times are server time
	(CONTRACT §5.1: lockUntil, lockCost, lockDuration, padsUnlocked, padsMax,
	nextPadCost). The server caps a lock at `maxRemaining`
	(Config.LOCK_MAX_REMAINING) and refuses to extend past it. With
	`lockStartedAt` (CONTRACT §9.3, optional) the bar is the share of the
	current lock left, so a fresh lock reads full.
]]

local Format = if script then require(script.Parent.Format) else require("./Format")

export type Level = "locked" | "low" | "open"
export type Status = { level: Level, remaining: number, title: string, sub: string, fraction: number }
export type LockButton = { text: string, enabled: boolean, maxed: boolean }
export type PadButton = { visible: boolean, text: string, enabled: boolean, urgent: boolean, hint: string? }
export type DailyButton = { visible: boolean, text: string }

local LockHud = {}

-- A lock with this little time left counts as "low" (flashes amber).
LockHud.LOW_SECONDS = 10

local function num(value: any): number
	return if type(value) == "number" and value == value then value else 0
end

function LockHud.status(lockUntil: number?, now: number, maxRemaining: number, lockStartedAt: number?): Status
	local remaining = Format.remainingSeconds(lockUntil, now)
	if remaining <= 0 then
		return {
			level = "open",
			remaining = 0,
			title = "🔓 UNLOCKED",
			sub = "Vulnerable - anyone can steal!",
			fraction = 0,
		}
	end
	local low = remaining <= LockHud.LOW_SECONDS
	return {
		level = if low then "low" else "locked",
		remaining = remaining,
		title = `🔒 LOCKED {Format.formatDuration(remaining)}`,
		sub = if low then "Lock ending - extend it!" else "Safe - thieves can't steal",
		fraction = LockHud.fraction(lockUntil :: number, now, maxRemaining, lockStartedAt),
	}
end

-- Bar fill: share of the current lock left (§9.3), else of the cap.
function LockHud.fraction(lockUntil: number, now: number, maxRemaining: number, lockStartedAt: number?): number
	local remaining = lockUntil - now
	if type(lockStartedAt) == "number" and lockStartedAt == lockStartedAt and lockUntil > lockStartedAt then
		return math.clamp(remaining / (lockUntil - lockStartedAt), 0, 1)
	end
	return if maxRemaining > 0 then math.clamp(remaining / maxRemaining, 0, 1) else 1
end

function LockHud.lockButton(state: any, now: number, maxRemaining: number): LockButton
	local cost = num(state.lockCost)
	local duration = math.floor(num(state.lockDuration))
	local remaining = Format.remainingSeconds(state.lockUntil, now)
	if maxRemaining > 0 and remaining >= maxRemaining - 1 then
		return { text = `🔒 Lock maxed\n{Format.formatDuration(maxRemaining)} cap`, enabled = false, maxed = true }
	end
	local verb = if remaining > 0 then "Extend" else "Lock"
	return {
		text = `🔒 {verb} {Format.formatCash(cost)}\n+{duration}s`,
		enabled = num(state.cash) >= cost,
		maxed = false,
	}
end

-- `compact` (phone HUD, narrower button) shortens the text.
function LockHud.padButton(state: any, compact: boolean?): PadButton
	local unlocked = num(state.padsUnlocked)
	local max = num(state.padsMax)
	-- A slime being stolen keeps its pad until the steal completes.
	local count = if type(state.slimes) == "table" then #state.slimes else 0
	local full = unlocked > 0 and count >= unlocked
	local cost = state.nextPadCost
	if type(cost) ~= "number" then
		return {
			visible = false,
			text = `All pads unlocked {unlocked}/{max}`,
			enabled = false,
			urgent = false,
			hint = if full then "Plot full - merge or sell to make room" else nil,
		}
	end
	local affordable = num(state.cash) >= cost
	return {
		visible = true,
		text = `{if compact then "Buy pad" else "Buy next pad"} {unlocked + 1}/{max}\n{Format.formatCash(cost)}`,
		enabled = affordable,
		urgent = full,
		hint = if full
			then `Plot full! Buy pad {unlocked + 1}/{max} for {Format.formatCash(cost)} (or merge / sell)`
			else nil,
	}
end

-- HUD Daily button: shown while a claim is ready, except during the
-- tutorial (the daily reward waits for it, see PopupQueue). Compact drops
-- the streak line (the popup shows it).
function LockHud.dailyButton(daily: any, tutorialActive: boolean?, compact: boolean?): DailyButton
	if type(daily) ~= "table" then
		return { visible = false, text = "Daily" }
	end
	local amount = Format.formatCash(num(daily.amount))
	return {
		visible = daily.available == true and tutorialActive ~= true,
		text = if compact then `Daily\n{amount}` else `Daily {amount}\nStreak {math.floor(num(daily.streak))}`,
	}
end

return table.freeze(LockHud)
