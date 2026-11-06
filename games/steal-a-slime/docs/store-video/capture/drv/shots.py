import math
SHOTS = {}

PUPPET_SETUP = """
local c = game.Players.LocalPlayer.Character
for _, d in c:GetDescendants() do if d:IsA("BasePart") or d:IsA("Decal") then d.LocalTransparencyModifier = 0 end end
local a = c:FindFirstChild("Animate") if a then a.Disabled = true end
local hum = c.Humanoid
hum.AutoRotate = false
hum.WalkSpeed = 0
for _, t in hum.Animator:GetPlayingAnimationTracks() do t:Stop(0) end
local function load(name, id)
	local an = Instance.new("Animation") an.Name = name an.AnimationId = id
	local tr = hum.Animator:LoadAnimation(an) tr.Looped = true tr:Play(0, if name == "VidRun" then 1 else 0.001) tr:AdjustSpeed(0)
	return tr.Length
end
local l1 = load("VidRun", "rbxassetid://913376220")
local l2 = load("VidIdle", "rbxassetid://507766388")
workspace:SetAttribute("VHideBB", true)
return {run = l1, idle = l2}
"""

def puppet(pos, yaw_deg, run_phase, run_w):
    """Client lua: put the character at pos facing yaw, run track at phase (seconds), weights."""
    yaw = math.radians(yaw_deg)
    look = (pos[0] + math.cos(yaw), pos[1], pos[2] + math.sin(yaw))
    return """
local c = game.Players.LocalPlayer.Character
local hrp = c.HumanoidRootPart
hrp.CFrame = CFrame.lookAt(Vector3.new(%f,%f,%f), Vector3.new(%f,%f,%f))
hrp.AssemblyLinearVelocity = Vector3.zero hrp.AssemblyAngularVelocity = Vector3.zero
for _, t in c.Humanoid.Animator:GetPlayingAnimationTracks() do
	if t.Name == "VidRun" then t:AdjustWeight(math.max(%f, 0.001), 0) t.TimePosition = %f %% t.Length t:AdjustSpeed(0)
	elseif t.Name == "VidIdle" then t:AdjustWeight(math.max(%f, 0.001), 0) t.TimePosition = %f %% t.Length t:AdjustSpeed(0) end
end
""" % (pos[0], pos[1], pos[2], look[0], look[1], look[2], run_w, run_phase, 1 - run_w, run_phase * 0.3)

def lerp(a, b, u): return [a[i] + (b[i] - a[i]) * u for i in range(3)]
def smooth(u): u = max(0, min(1, u)); return u * u * (3 - 2 * u)

# ---- S1: the steal (hook) ----
import json, os
IDS = json.load(open(os.path.join(os.path.dirname(__file__), "ids.json")))
def slime_of(owner, tier): return [x for x in IDS if x["owner"] == owner and x["tier"] == tier][0]
CELESTIAL = slime_of(-2001, 8)["id"]
DOOR = [79.0, 4.0, 79.5]
NEAR = [101.2, 4.0, 79.4]
def s1_char(t):
    if t < 1.25:
        u = t / 1.25
        return lerp(DOOR, NEAR, u), 0, t * 1.1, 1.0          # yaw 0 = +x
    if t < 1.75:
        return NEAR, 0 if t < 1.55 else 0 + (t - 1.55) / 0.2 * 180 * 0, 1.25 * 1.1, max(0, 1 - (t - 1.25) / 0.15)
    if t < 2.0:
        u = smooth((t - 1.75) / 0.25)
        return NEAR, 180 * u, 1.25 * 1.1, 0.0
    u = min((t - 2.0) / 1.6, 1)
    MID, OUT = [91.0, 4.0, 85.0], [78.0, 4.0, 80.0]
    if u < 0.5:
        p = lerp(NEAR, MID, u / 0.5); d = [MID[0] - NEAR[0], MID[2] - NEAR[2]]
    else:
        p = lerp(MID, OUT, (u - 0.5) / 0.5); d = [OUT[0] - MID[0], OUT[2] - MID[2]]
    yaw = math.degrees(math.atan2(d[1], d[0]))
    if t < 2.15: yaw = 180 + (yaw - 180) * (t - 2.0) / 0.15
    return p, yaw, (t - 2.0) * 1.0, min(1, (t - 2.0) / 0.12)
def s1_client(t, k):
    p, yaw, ph, w = s1_char(t)
    return puppet(p, yaw, ph, w)
def s1_server(t, k):
    if k == int(1.45 * 30):
        return "workspace:SetAttribute('VidReq', '[[\"grab\",\"%s\"]]')" % CELESTIAL
    return ""
def s1_cam(t):
    u = smooth(t / 3.6)
    pos = lerp([113, 10, 92], [107, 8.5, 89], u)
    at = lerp([95, 4.5, 79], [86, 5.5, 83], smooth((t - 1.6) / 2.0))
    return pos, at
SHOTS["s1"] = {"dur": 3.6, "cam": s1_cam, "setup_client": PUPPET_SETUP, "client_frame": s1_client, "server_frame": s1_server}

SHOTS["test"] = {"dur": 2.0, "keys": [(0, [-30, 8, 100], [0, 4, 140]), (2.0, [-14, 7, 108], [0, 4, 140])]}

# ---- S2: catch a wild Legendary on the lane ----
_W = [x for x in json.load(open(os.path.join(os.path.dirname(__file__), "wild.json"))) if x["id"].startswith("ad0e78e1")][0]
WILD = _W["id"]
P0, H = (_W["p"][0], _W["p"][2]), tuple(_W["h"])
PERP = (-H[1], H[0]) if (-H[1] * 0 + H[0] * 1) > 0 else (H[1], -H[0])
G = (P0[0] + H[0] * 3.0 + PERP[0] * 5.0, P0[1] + H[1] * 3.0 + PERP[1] * 5.0)   # where the thief stands to grab
S0 = (G[0] + PERP[0] * 16, G[1] + PERP[1] * 16)
S2_LUA = """
local t = %(t)f
local function smooth(u) u = math.clamp(u, 0, 1) return u * u * (3 - 2 * u) end
local m = workspace:FindFirstChild("Slime_%(id)s", true)
local c = game.Players.LocalPlayer.Character
local hrp = c.HumanoidRootPart
local S = Vector3.new(%(sx)f, 4, %(sz)f)
local G = Vector3.new(%(gx)f, 4, %(gz)f)
local sp = m and m:GetPivot().Position or G
sp = Vector3.new(sp.X, 4, sp.Z)
local pos, look, w, ph
if t < 1.2 then
	pos = S:Lerp(G, t / 1.2)
	look = G + (G - S)
	w, ph = 1, t * 1.1
elseif t < 1.6 then
	pos = G
	look = sp
	w, ph = math.max(0, 1 - (t - 1.2) / 0.15), 1.2 * 1.1
else
	local tt = t - 1.6
	local dir = (S - G).Unit
	pos = G + dir * (tt * 11)
	local f = smooth(tt / 0.25)
	look = pos + (sp - G).Unit:Lerp(dir, f)
	w, ph = math.min(1, tt / 0.12), tt * 0.9
end
hrp.CFrame = CFrame.lookAt(pos, Vector3.new(look.X, pos.Y, look.Z))
hrp.AssemblyLinearVelocity = Vector3.zero hrp.AssemblyAngularVelocity = Vector3.zero
for _, tr in c.Humanoid.Animator:GetPlayingAnimationTracks() do
	if tr.Name == "VidRun" then tr:AdjustWeight(math.max(w, 0.001), 0) tr.TimePosition = ph %% tr.Length tr:AdjustSpeed(0)
	elseif tr.Name == "VidIdle" then tr:AdjustWeight(math.max(1 - w, 0.001), 0) tr.TimePosition = (t * 0.3) %% tr.Length tr:AdjustSpeed(0) end
end
"""
def s2_client(t, k): return S2_LUA % {"t": t, "id": WILD, "sx": S0[0], "sz": S0[1], "gx": G[0], "gz": G[1]}
def s2_server(t, k):
    if k == int(1.3 * 30):
        return "workspace:SetAttribute('VidReq', '[[\"grab\",\"%s\"]]')" % WILD
    return ""
def s2_cam(t):
    back = 22 - 4 * smooth(t / 1.4) + 10 * smooth((t - 1.6) / 1.6)
    side = 5
    base = (G[0] + PERP[0] * back + H[0] * side, G[1] + PERP[1] * back + H[1] * side)
    pos = [base[0], 7.5 + 1.5 * smooth((t - 1.6) / 1.6), base[1]]
    at = [G[0] - PERP[0] * 3, 4.5, G[1] - PERP[1] * 3]
    return pos, at
SHOTS["s2"] = {"dur": 3.2, "cam": s2_cam, "setup_client": PUPPET_SETUP, "client_frame": s2_client, "server_frame": s2_server}

# ---- S2b: drop-off at home, slime lands on pad 5 ----
HOME_LUA = """
local t = %(t)f
local function smooth(u) u = math.clamp(u, 0, 1) return u * u * (3 - 2 * u) end
local c = game.Players.LocalPlayer.Character
local hrp = c.HumanoidRootPart
local A, B = Vector3.new(1, 4, 96), Vector3.new(-7, 4, 124)
local pos, look, w, ph
if t < 1.25 then
	pos = A:Lerp(B, t / 1.25) look = B + (B - A) w, ph = 1, t * 1.1
else
	pos = B
	local f = smooth((t - 1.5) / 0.5)
	local fwd = (B - A).Unit
	local toCam = (Vector3.new(-19, 4, 129) - B).Unit
	look = B + fwd:Lerp(toCam, f)
	w, ph = math.max(0, 1 - (t - 1.25) / 0.15), 1.25 * 1.1
end
hrp.CFrame = CFrame.lookAt(pos, Vector3.new(look.X, pos.Y, look.Z))
hrp.AssemblyLinearVelocity = Vector3.zero hrp.AssemblyAngularVelocity = Vector3.zero
for _, tr in c.Humanoid.Animator:GetPlayingAnimationTracks() do
	if tr.Name == "VidRun" then tr:AdjustWeight(math.max(w, 0.001), 0) tr.TimePosition = ph %% tr.Length tr:AdjustSpeed(0)
	elseif tr.Name == "VidIdle" then tr:AdjustWeight(math.max(1 - w, 0.001), 0) tr.TimePosition = (t * 0.3) %% tr.Length tr:AdjustSpeed(0) end
end
"""
def home_client(t, k): return HOME_LUA % {"t": t}
def home_server(t, k):
    if k == int(1.6 * 30):
        return "workspace:SetAttribute('VidReq', '[[\"deposit\"]]')"
    return ""
def home_cam(t):
    u = smooth(t / 2.6)
    return lerp([15, 7.5, 140], [12, 8.5, 134], u), lerp([-6, 4.5, 116], [-12, 4.5, 126], u)
SHOTS["s2b"] = {"dur": 2.6, "cam": home_cam, "setup_client": PUPPET_SETUP, "client_frame": home_client, "server_frame": home_server}

# ---- S3: rare slimes on show, orbit inside my base ----
def s3_cam(t):
    a = math.radians(-70 + 110 * smooth(t / 3.6) * 0.15 + 110 * (t / 3.6) * 0.85)
    c = (0, 140)
    r = 9
    pos = [c[0] + math.sin(a) * r, 6.0, c[1] + math.cos(a) * r]
    la = a + math.radians(25)
    at = [c[0] + math.sin(la) * 22, 4.2, c[1] + math.cos(la) * 22]
    return pos, at
SHOTS["s3"] = {"dur": 3.6, "cam": s3_cam, "hidechar": True}

# ---- S4: merge vat finishes a brew, the result appears on the first input's pad ----
VAT_EVAL = "return function(world, player, now) local s = world.sessions[player.UserId] local v = s.data.vat v.endsAt = now() + 1.8 v.startedAt = now() - 3598 s.dirty = true require(script.World).markAllDirty(world) return {ends = v.endsAt} end"
def s4_server(t, k):
    if k == 0:
        return "workspace:SetAttribute('VidReq', [==[%s]==])" % json.dumps([["eval", VAT_EVAL]])
    if k == int(2.25 * 30):
        return "workspace:SetAttribute('VidReq', '[[\"req\",\"VatCollect\"]]')"
    return ""
def s4_cam(t):
    pos = lerp([3, 9, 112], [-7, 7.5, 125], smooth((t - 0.6) / 2.2))
    a0 = math.atan2(119 - pos[2], 11 - pos[0]); a1 = math.atan2(142 - pos[2], -22 - pos[0])
    u = smooth((t - 1.2) / 1.1)
    a = a0 + (a1 - a0) * u
    d0 = math.hypot(11 - pos[0], 119 - pos[2]); d1 = math.hypot(-22 - pos[0], 142 - pos[2])
    d = d0 + (d1 - d0) * u
    at = [pos[0] + math.cos(a) * d, 4.0, pos[2] + math.sin(a) * d]
    return pos, at
SHOTS["s4"] = {"dur": 3.6, "cam": s4_cam, "hidechar": True, "server_frame": s4_server,
               "pre_req": '[["req","VatStart"]]', "pre_wait": 3}

# ---- S6: end crane over the whole map ----
def s6_cam(t):
    u = smooth(t / 4.2)
    a = math.radians(200 + 70 * (t / 4.2))
    r = 70 + 150 * u
    h = 18 + 190 * u
    pos = [math.cos(a) * r, h, math.sin(a) * r]
    at = [0, 6 - 6 * u, 0]
    return pos, at
SHOTS["s6"] = {"dur": 4.2, "cam": s6_cam, "hidechar": True}
