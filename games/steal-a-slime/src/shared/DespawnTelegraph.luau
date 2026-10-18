--!strict
--[[
	DespawnTelegraph (pure, FEATURES.DespawnTelegraph)

	Timing for the wild slime despawn warning. A wild slime still lives until
	`expiresAt` (Fountain.wildLifetime after it spawned); for the last
	DESPAWN_TELEGRAPH_SECONDS before that its model carries the attribute
	DespawnAt (Constants.DESPAWN_AT_ATTRIBUTE) = expiresAt, in server time.

	The client plays the shrink / poof from DespawnAt (no text, blink or fade). The server never removes early: it
	removes only once shouldRemove(now, expiresAt) is true.

	Client FX data and helpers (Visuals DespawnTelegraphFx reads these):
	  DespawnTelegraph.FX
	    frozen knobs: poof textures, burst counts, slime-green colours,
	    shrink target
	  DespawnTelegraph.shrinkFactor(progress, shrinkTo)
	    model scale factor: 1 at progress 0, shrinkTo at progress 1
	  DespawnTelegraph.fallbackSizeXYZ(x, y, z, factor)
	    one part's size for the Size fallback (when Model:ScaleTo fails)

	No Roblox APIs at load time (sizes are plain numbers so Lune can test them).
]]

local Config = if script then require(script.Parent.Config) else require("./Config")

local DespawnTelegraph = {}

local GOO = Config.RARITIES[1].color -- Common slime green

DespawnTelegraph.FX = table.freeze({
	texture = "rbxasset://textures/particles/sparkles_main.dds", -- same as Effects SPARK
	smokeTexture = "rbxasset://textures/particles/smoke_main.dds", -- same as Effects SMOKE
	count = 28, -- sparkle burst
	smokeCount = 6, -- soft puff under the sparkles
	color = table.freeze({ GOO[1], GOO[2], GOO[3] }), -- RGB 0..255, burst end
	colorBright = table.freeze({ 140, 255, 150 }), -- brighter goo, burst start
	shrinkTo = 0.55, -- model scale factor at DespawnAt
})

-- Server time the warning begins.
function DespawnTelegraph.warnStartsAt(expiresAt: number, warnSeconds: number): number
	return expiresAt - warnSeconds
end

-- True from warnStartsAt (inclusive) up to expiresAt (exclusive).
function DespawnTelegraph.inWarnWindow(now: number, expiresAt: number, warnSeconds: number): boolean
	return now >= DespawnTelegraph.warnStartsAt(expiresAt, warnSeconds) and now < expiresAt
end

-- Value of the DespawnAt model attribute: expiresAt inside the warn window
-- when enabled, else nil (attribute cleared).
function DespawnTelegraph.attributeValue(now: number, expiresAt: number, warnSeconds: number, enabled: boolean): number?
	if enabled and DespawnTelegraph.inWarnWindow(now, expiresAt, warnSeconds) then
		return expiresAt
	end
	return nil
end

-- The server removes the wild slime only at expiresAt.
function DespawnTelegraph.shouldRemove(now: number, expiresAt: number): boolean
	return now >= expiresAt
end

-- 0 at the start of the window, 1 at despawnAt (drives the shrink).
function DespawnTelegraph.progress(now: number, despawnAt: number, warnSeconds: number): number
	if warnSeconds <= 0 then
		return 1
	end
	return math.clamp(1 - (despawnAt - now) / warnSeconds, 0, 1)
end

-- Model scale factor over the window: 1 at progress 0, shrinkTo at 1
-- (progress clamped to 0..1).
function DespawnTelegraph.shrinkFactor(progress: number, shrinkTo: number): number
	return 1 - (1 - shrinkTo) * math.clamp(progress, 0, 1)
end

-- Size fallback for one part: every axis times factor. Plain numbers so it
-- runs under Lune; the client wraps the result in Vector3.new.
function DespawnTelegraph.fallbackSizeXYZ(x: number, y: number, z: number, factor: number): (number, number, number)
	return x * factor, y * factor, z * factor
end

return DespawnTelegraph
