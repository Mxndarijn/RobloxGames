-- Client datamodel (play): PvP client effects cleanup probe (ADVISORY, FEATURES.PvP, CONTRACT.md §26.1). Plays one PvpEvent "Effect" payload of every
-- kind through the client module StarterPlayerScripts.UI.PvpEffects (PvpEffects.play(payload), PvpEffects.activeCount()) and counts the Workspace
-- descendants that are BasePart / ParticleEmitter / Highlight / Beam / Trail before and after the longest effect has expired
-- (Config.PVP.FX_SECONDS, FIREWORKS_SECONDS, CONTROL_MAX_SECONDS, +1 s). Pass: net delta == 0 and activeCount() == 0 afterwards.
-- An idle drift sample (same wait, nothing played) is reported as `idle_drift` so replicated world noise can be told apart.
-- Also plays TrapPlaced (GooTrap1..3, FunBouncePad, owner = the local player) then TrapCleared and expects markerCount() == 0 (markers_cleared).
-- The shot forces FEATURES.PvP (flags field); flag_on asserts it. n/a (ok nil) while the module does not exist.
-- Checks: flag_on, fx_counts (net delta), fx_active_count (activeCount() == 0 after), markers_cleared. Nothing is left behind.
local Players = game:GetService("Players")
local RS = game:GetService("ReplicatedStorage")
local ORDER = { "flag_on", "fx_counts", "fx_active_count", "markers_cleared" }
local checks = {}
local function set(name, ok, info)
	checks[name] = { ok = ok, info = info }
end
local function finish(extra)
	local parts, all, any = {}, true, false
	for _, name in ORDER do
		local c = checks[name] or { ok = nil, info = "not run" }
		checks[name] = c
		table.insert(parts, name .. " " .. (if c.ok == true then "PASS" elseif c.ok == false then "FAIL" else "n/a"))
		if c.ok == false then
			all = false
		elseif c.ok == true then
			any = true
		end
	end
	return { ok = if not all then false elseif any then true else nil, summary = table.concat(parts, ", "), detail = { checks = checks, extra = extra } }
end

local player = Players.LocalPlayer
local scripts = player and player:FindFirstChild("PlayerScripts")
local ui = scripts and scripts:FindFirstChild("UI")
local mod = ui and ui:FindFirstChild("PvpEffects")
if not mod then
	set("fx_counts", nil, "src/ui/PvpEffects missing in this build")
	set("fx_active_count", nil, "src/ui/PvpEffects missing in this build")
	local r = finish("PvpEffects missing")
	r.summary = "PvpEffects missing (n/a)"
	return r
end
local okReq, Effects = pcall(require, mod)
if not okReq or type(Effects) ~= "table" or type(Effects.play) ~= "function" then
	set("fx_counts", false, "require failed: " .. tostring(Effects))
	return finish("require failed")
end
local Config = require(RS.Shared.Config)
local PVP = Config.PVP
set("flag_on", Config.FEATURES.PvP == true, { PvP = Config.FEATURES.PvP })

local function count()
	local n = 0
	for _, d in workspace:GetDescendants() do
		if d:IsA("BasePart") or d:IsA("ParticleEmitter") or d:IsA("Highlight") or d:IsA("Beam") or d:IsA("Trail") then
			n += 1
		end
	end
	return n
end
local function active()
	if type(Effects.activeCount) == "function" then
		local ok, v = pcall(Effects.activeCount)
		return if ok then v else nil
	end
	return nil
end

local char = player.Character
local root = char and char:FindFirstChild("HumanoidRootPart")
local base = if root then root.Position else Vector3.new(0, 5, 0)
local uid = player.UserId
local function pos(i)
	return base + Vector3.new(6 + i * 2, 0, 6) -- near the character, so the camera range check keeps every effect
end
-- (itemId, effect, extra) for every effect kind PvpService.fireEffect carries
local KINDS = {
	{ "KnockGlove1", "Knockback", { push = 5 } }, { "KnockGlove5", "Knockback", { push = 8 } },
	{ "GooTrap1", "Freeze", { duration = 1 } }, { "GooTrap3", "Freeze", { duration = PVP.CONTROL_MAX_SECONDS } },
	{ "GooBlaster1", "Slow", { duration = 2 } }, { "GooBlaster3", "Slow", { duration = 3 } },
	{ "FunBouncePad", "Bounce", { duration = 1.2 } }, { "FunDanceBomb", "Dance", { duration = 2 } },
	{ "FunConfetti", "Cosmetic", {} }, { "FunBalloon", "Cosmetic", {} }, { "FunBubbles", "Cosmetic", {} },
	{ "FunSqueaky", "Cosmetic", {} }, { "FunHatLauncher", "Cosmetic", { duration = 3 } }, { "FunFireworks", "Cosmetic", { duration = PVP.FIREWORKS_SECONDS } },
}
local longest = math.max(PVP.FX_SECONDS, PVP.FIREWORKS_SECONDS, PVP.CONTROL_MAX_SECONDS, 3)
local SETTLE = longest + PVP.FX_SECONDS + 1

local before = count()
task.wait(SETTLE)
local idleDrift = count() - before -- same wait with nothing played

local before2 = count()
local played, errors = 0, {}
for i, k in KINDS do
	local payload = { kind = "Effect", attacker = uid, target = uid, itemId = k[1], effect = k[2], position = pos(i), duration = PVP.FX_SECONDS }
	for key, v in k[3] do
		payload[key] = v
	end
	local ok, err = pcall(Effects.play, payload)
	if ok then
		played += 1
	else
		table.insert(errors, k[1] .. ": " .. tostring(err))
	end
end
local TRAPS = { "GooTrap1", "GooTrap2", "GooTrap3", "FunBouncePad" }
for i, id in TRAPS do
	local ok, err = pcall(Effects.play, { kind = "TrapPlaced", owner = uid, trapId = "pcw" .. i, itemId = id, position = pos(i + 20) })
	if not ok then
		table.insert(errors, "TrapPlaced " .. id .. ": " .. tostring(err))
	end
end
task.wait(0.3)
local markersPlaced = if type(Effects.markerCount) == "function" then Effects.markerCount() else nil
for i, id in TRAPS do
	pcall(Effects.play, { kind = "TrapCleared", owner = uid, trapId = "pcw" .. i, itemId = id, position = pos(i + 20) })
end
local peak = count()
local peakActive = active()
task.wait(SETTLE)
local after = count()
local afterActive = active()
local net = after - before2
local markersAfter = if type(Effects.markerCount) == "function" then Effects.markerCount() else nil
set("markers_cleared", if markersAfter == nil then nil else markersAfter == 0, { placed = markersPlaced, after = markersAfter })
set("fx_counts", net == 0 and #errors == 0, {
	before = before2, peak = peak, after = after, net_delta = net, idle_drift = idleDrift, played = played, of = #KINDS, errors = errors, settle_seconds = SETTLE,
})
if afterActive == nil then
	set("fx_active_count", nil, "PvpEffects.activeCount missing")
else
	set("fx_active_count", afterActive == 0, { peak = peakActive, after = afterActive })
end
return finish(nil)
