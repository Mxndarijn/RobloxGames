--!strict
--[[
	LoadingGate (pure)

	Decides what the join loading screen shows and when it lifts. The adapter
	(ReplicatedFirst Loading script) feeds it the join's status each tick:

	  gameLoaded   game:IsLoaded() (the place has replicated)
	  worldReady   workspace WorldMeshesReady (MeshSwap dressed Map / Plots)
	  preloaded    assets ContentProvider has answered for, of preloadTotal
	  preloadDone  the preload pass has finished (or failed)

	step() returns the bar fraction, the label and whether the screen may
	lift: once everything is ready, or at MAX_WAIT whatever is still loading,
	and never before MIN_SHOW (no one-frame flash). canSkip turns true at
	SKIP_AFTER so a slow connection is never stuck behind the screen.
]]

local LoadingGate = {}

LoadingGate.MAX_WAIT = 25 -- seconds after the script starts: the screen lifts even if something never loads
LoadingGate.MIN_SHOW = 1 -- seconds the screen stays up at least
LoadingGate.SKIP_AFTER = 6 -- seconds before the skip button shows

-- Share of the bar each stage fills, in order.
LoadingGate.WEIGHTS = table.freeze({ gameLoaded = 0.2, worldReady = 0.3, preload = 0.5 })

LoadingGate.LABELS = table.freeze({
	place = "Loading the ranch...",
	world = "Building the world...",
	assets = "Loading textures...",
	done = "Ready!",
})

export type Status = {
	gameLoaded: boolean,
	worldReady: boolean,
	preloaded: number,
	preloadTotal: number,
	preloadDone: boolean,
}

export type View = { progress: number, label: string, lift: boolean, canSkip: boolean }

function LoadingGate.step(status: Status, elapsed: number): View
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
	local label = if ready
		then LoadingGate.LABELS.done
		elseif not status.gameLoaded then LoadingGate.LABELS.place
		elseif not status.worldReady then LoadingGate.LABELS.world
		else LoadingGate.LABELS.assets
	return {
		progress = if ready then 1 else math.min(progress, 0.99),
		label = label,
		lift = elapsed >= LoadingGate.MIN_SHOW and (ready or elapsed >= LoadingGate.MAX_WAIT),
		canSkip = elapsed >= LoadingGate.SKIP_AFTER,
	}
end

return table.freeze(LoadingGate)
