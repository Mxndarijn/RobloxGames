--!strict
--[[
	LoadingGate (pure)

	Decides what the join loading screen shows and when it lifts. The adapter
	(ReplicatedFirst Loading script) feeds it the join's status each tick:

	  gameLoaded   game:IsLoaded() (the place has replicated)
	  worldReady   workspace WorldMeshesReady (MeshSwap dressed Map / Plots)
	  preloaded    assets ContentProvider has answered for, of preloadTotal
	  preloadDone  the preload pass has finished (or failed)

	step() returns the bar's target, the label and whether the screen may
	lift: once everything is ready, or at MAX_WAIT whatever is still loading,
	and never before MIN_SHOW (no one-frame flash). canSkip turns true at
	SKIP_AFTER so a slow connection is never stuck behind the screen. The
	label is a tip that changes every TIP_EVERY seconds, then DONE; `key` is
	its Strings key, which the adapter translates once the UI's Text module
	can load (this screen runs before Shared, so the English stays here as the
	fallback; tests/LoadingGate.spec checks it matches the catalog).

	glide() moves the drawn bar toward that target every frame, so it slides
	instead of jumping, and keeps creeping a little while a stage waits.
]]

local LoadingGate = {}

LoadingGate.MAX_WAIT = 25 -- seconds after the script starts: the screen lifts even if something never loads
LoadingGate.MIN_SHOW = 1 -- seconds the screen stays up at least
LoadingGate.SKIP_AFTER = 6 -- seconds before the skip button shows

-- Share of the bar each stage fills, in order.
LoadingGate.WEIGHTS = table.freeze({ gameLoaded = 0.2, worldReady = 0.3, preload = 0.5 })

LoadingGate.GLIDE = 5 -- per second: how fast the drawn bar closes the gap to its target
LoadingGate.GLIDE_DONE = 14 -- the same once everything is ready, so the bar fills before the fade
LoadingGate.CREEP = 0.01 -- bar share per second the bar keeps moving while a stage waits
LoadingGate.CREEP_LEAD = 0.08 -- how far the creep may run ahead of the real progress

LoadingGate.TIP_EVERY = 4 -- seconds each tip shows
LoadingGate.TIPS = table.freeze({
	"Lock your base to stop thieves",
	"Steal slimes from other bases",
	"Rarer slimes earn more cash",
	"Merge two slimes in the vat",
	"Run the obby for a cash boost",
})
-- The Strings key of each tip (same order as TIPS).
LoadingGate.TIP_KEYS = table.freeze({
	"hud.loading.tip_lock",
	"hud.loading.tip_steal",
	"hud.loading.tip_rarer",
	"hud.loading.tip_merge",
	"hud.loading.tip_obby",
})
LoadingGate.DONE = "Ready!"
LoadingGate.DONE_KEY = "hud.loading.ready"
LoadingGate.SKIP_KEY = "hud.loading.skip"

export type Status = {
	gameLoaded: boolean,
	worldReady: boolean,
	preloaded: number,
	preloadTotal: number,
	preloadDone: boolean,
}

-- `label` in English, `key` its Strings key.
export type View = { progress: number, label: string, key: string, lift: boolean, canSkip: boolean }

-- The tip on screen `elapsed` seconds in, starting from tip number `first` (1-based, wraps), and its key.
function LoadingGate.tip(elapsed: number, first: number?): (string, string)
	local tips = LoadingGate.TIPS
	local index = ((first or 1) - 1 + math.floor(math.max(elapsed, 0) / LoadingGate.TIP_EVERY)) % #tips
	return tips[index + 1], LoadingGate.TIP_KEYS[index + 1]
end

function LoadingGate.step(status: Status, elapsed: number, firstTip: number?): View
	local w = LoadingGate.WEIGHTS
	local progress = 0
	if status.gameLoaded then
		progress += w.gameLoaded
	end
	if status.worldReady then
		progress += w.worldReady
	end
	local share = if status.preloadDone
		then 1
		elseif status.preloadTotal > 0 then math.clamp(status.preloaded / status.preloadTotal, 0, 1)
		else 0
	progress += w.preload * share

	local ready = status.gameLoaded and status.worldReady and status.preloadDone
	local label, key = LoadingGate.DONE, LoadingGate.DONE_KEY
	if not ready then
		label, key = LoadingGate.tip(elapsed, firstTip)
	end
	return {
		progress = if ready then 1 else math.min(progress, 0.99),
		label = label,
		key = key,
		lift = elapsed >= LoadingGate.MIN_SHOW and (ready or elapsed >= LoadingGate.MAX_WAIT),
		canSkip = elapsed >= LoadingGate.SKIP_AFTER,
	}
end

-- The drawn bar `dt` seconds after it showed `shown`, heading for `target` (step's progress). It never moves
-- back, never shows full before the target is 1, and creeps on while the target waits.
function LoadingGate.glide(shown: number, target: number, dt: number): number
	local done = target >= 1
	local goal = if done then 1 else math.min(target, 0.99)
	local rate = if done then LoadingGate.GLIDE_DONE else LoadingGate.GLIDE
	local nextShown = shown + math.max(0, goal - shown) * (1 - math.exp(-rate * dt))
	if not done then
		local creep = math.min(shown + LoadingGate.CREEP * dt, target + LoadingGate.CREEP_LEAD, 0.99)
		nextShown = math.max(nextShown, creep)
	end
	return math.clamp(math.max(shown, nextShown), 0, 1)
end

return table.freeze(LoadingGate)
