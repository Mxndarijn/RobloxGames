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


# ---- smooth character motion: heading eases towards its target (no snaps), legs follow the real speed ----
class Walker:
    def __init__(self, tau=0.12):
        self.w0 = 1.0 / tau  # critically damped spring: the turn speeds up, then settles; no first-frame jump
        self.yaw, self.vel, self.last_t, self.dist, self.prev = None, 0.0, None, 0.0, None
    def step(self, t, pos, target_yaw, idle_w=None):
        if self.last_t is None or t < self.last_t:
            self.yaw, self.vel, self.dist, self.prev = target_yaw, 0.0, 0.0, pos
            dt = 0.0
        else:
            dt = t - self.last_t
        self.last_t = t
        n = 8  # sub-steps per frame
        for _ in range(n if dt > 0 else 0):
            h = dt / n
            d = (target_yaw - self.yaw + 180) % 360 - 180
            self.vel += (self.w0 * self.w0 * d - 2 * self.w0 * self.vel) * h
            self.yaw += self.vel * h
        moved = math.hypot(pos[0] - self.prev[0], pos[2] - self.prev[2])
        self.prev = pos
        self.dist += moved
        speed = moved / dt if dt > 0 else 0
        w = min(1.0, speed / 9.0) if idle_w is None else 1 - idle_w  # full run from 9 studs/s
        phase = self.dist / 16.0 * 1.0  # run anim at speed 1 covers ~16 studs per second of track time
        return puppet(pos, self.yaw, phase, w)

def heading(a, b): return math.degrees(math.atan2(b[2] - a[2], b[0] - a[0]))
def bez(p0, p1, p2, u): return [(1 - u) ** 2 * p0[i] + 2 * (1 - u) * u * p1[i] + u * u * p2[i] for i in range(3)]
def ease_out(u): u = max(0, min(1, u)); return 1 - (1 - u) ** 2
def ease_in(u): u = max(0, min(1, u)); return u * u

def lerp(a, b, u): return [a[i] + (b[i] - a[i]) * u for i in range(3)]
def smooth(u): u = max(0, min(1, u)); return u * u * (3 - 2 * u)

# ---- S1: the steal (hook) ----
import json, os
IDS = json.load(open(os.path.join(os.path.dirname(__file__), "ids.json")))
def slime_of(owner, tier): return [x for x in IDS if x["owner"] == owner and x["tier"] == tier][0]
CELESTIAL = slime_of(-2001, 8)["id"]
DOOR = [79.0, 4.0, 79.5]
NEAR = [101.2, 4.0, 79.4]
_W1 = Walker(tau=0.09)
def accel_then_cruise(x, a=0.3):
    """0..1 distance fraction: speeds up over the first `a` of the time, then steady; continuous speed"""
    x = max(0.0, min(1.0, x))
    f = x * x / (2 * a) if x < a else x - a / 2
    return f / (1 - a / 2)
MID, OUT = [91.0, 4.0, 85.5], [78.0, 4.0, 80.0]
def s1_char(t):
    """run in (slowing down), stop at the slime, grab, turn round on the spot, run out along a curve"""
    if t < 1.35:
        return lerp(DOOR, NEAR, ease_out(t / 1.35)), heading(DOOR, NEAR)
    if t < 1.65:
        return NEAR, heading(DOOR, NEAR)
    if t < 2.0:
        return NEAR, heading(NEAR, bez(NEAR, MID, OUT, 0.08))  # turn first, standing
    u = accel_then_cruise((t - 2.0) / 1.6)
    p = bez(NEAR, MID, OUT, u)
    return p, heading(p, bez(NEAR, MID, OUT, min(1.0, u + 0.06)))
def s1_client(t, k):
    p, yaw = s1_char(t)
    return _W1.step(t, p, yaw)
def s1_server(t, k):
    if k == int(1.45 * 30):
        return "workspace:SetAttribute('VidReq', '[[\"grab\",\"%s\"]]')" % CELESTIAL
    return ""
def s1_cam(t):
    u = smooth(t / 3.6)
    pos = lerp([113, 10, 92], [107, 8.5, 89], u)
    at = lerp([95, 4.5, 79], [86, 5.5, 83], smooth((t - 1.6) / 2.0))
    return pos, at
SHOTS["s1"] = {"dof": (18, 18, 0.12), "dur": 3.6, "cam": s1_cam, "setup_client": PUPPET_SETUP, "client_frame": s1_client, "server_frame": s1_server}

SHOTS["test"] = {"dur": 2.0, "keys": [(0, [-30, 8, 100], [0, 4, 140]), (2.0, [-14, 7, 108], [0, 4, 140])]}

# ---- S2: catch a wild Legendary on the lane ----
_WILD_ALL = json.load(open(os.path.join(os.path.dirname(__file__), "wild.json")))
_W = ([x for x in _WILD_ALL if x["id"].startswith(os.environ.get("WILD_ID", "-"))] or _WILD_ALL)[0]  # WILD_ID = id prefix
WILD = _W["id"]
P0, H = (_W["p"][0], _W["p"][2]), tuple(_W["h"])
PERP = (-H[1], H[0]) if (-H[1] * 0 + H[0] * 1) > 0 else (H[1], -H[0])
G = (P0[0] + H[0] * 3.0 + PERP[0] * 5.0, P0[1] + H[1] * 3.0 + PERP[1] * 5.0)   # where the thief stands to grab
S0 = (G[0] + PERP[0] * 16, G[1] + PERP[1] * 16)
_W2 = Walker(tau=0.09)
def s2_char(t):
    S, Gp = [S0[0], 4.0, S0[1]], [G[0], 4.0, G[1]]
    slime = [P0[0] + H[0] * 2.0, 4.0, P0[1] + H[1] * 2.0]
    if t < 1.2:
        p = lerp(S, Gp, ease_out(t / 1.2))
        return p, (heading(S, Gp) if t < 0.85 else heading(Gp, slime))  # turns towards the slime as it slows
    if t < 1.55:
        return Gp, heading(Gp, slime)
    away = [Gp[0] + (S[0] - Gp[0]) * 1.6, 4.0, Gp[2] + (S[2] - Gp[2]) * 1.6]
    if t < 1.8:
        return Gp, heading(Gp, away)  # turn on the spot first
    p = lerp(Gp, away, accel_then_cruise((t - 1.8) / 1.4) * 0.75)
    return p, heading(Gp, away)
def s2_client(t, k):
    p, yaw = s2_char(t)
    return _W2.step(t, p, yaw)
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
SHOTS["s2"] = {"dof": (20, 22, 0.12), "dur": 3.2, "cam": s2_cam, "setup_client": PUPPET_SETUP, "client_frame": s2_client, "server_frame": s2_server}

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
SHOTS["s2b"] = {"dof": (20, 20, 0.1), "dur": 2.6, "cam": home_cam, "setup_client": PUPPET_SETUP, "client_frame": home_client, "server_frame": home_server}

# ---- S3: rare slimes on show, orbit inside my base ----
def s3_cam(t):
    # slow orbit: 40 degrees over the shot, a little further out than v1 (110 degrees at r 9 strobed)
    a = math.radians(-55 + 40 * (0.15 * smooth(t / 3.6) + 0.85 * (t / 3.6)))
    c = (0, 140)
    r = 10
    pos = [c[0] + math.sin(a) * r, 6.0, c[1] + math.cos(a) * r]
    la = a + math.radians(25)
    at = [c[0] + math.sin(la) * 22, 4.2, c[1] + math.cos(la) * 22]
    return pos, at
SHOTS["s3"] = {"dof": (12, 10, 0.15), "dur": 3.6, "cam": s3_cam, "hidechar": True}

# ---- S4: merge vat finishes a brew, the result appears on the first input's pad ----
VAT_EVAL = "return function(world, player, now) local s = world.sessions[player.UserId] local v = s.data.vat v.endsAt = now() + 1.8 v.startedAt = now() - 3598 s.dirty = true require(script.World).markAllDirty(world) return {ends = v.endsAt} end"
def s4_server(t, k):
    if k == 0:
        return "workspace:SetAttribute('VidReq', [==[%s]==])" % json.dumps([["eval", VAT_EVAL]])
    if k == int(2.25 * 30):
        return "workspace:SetAttribute('VidReq', '[[\"req\",\"VatCollect\"]]')"
    return ""
def s4_cam(t):
    # vat and the first input's pad (pad 1, next to the vat) in one frame: a slow push-in, no whip pan
    u = smooth(t / 3.6)
    pos = lerp([-1, 8, 136], [2, 7.2, 132], u)
    at = lerp([12, 4.2, 121], [16, 4.2, 125], smooth((t - 1.2) / 1.6))
    return pos, at
SHOTS["s4"] = {"dof": (15, 16, 0.1), "dur": 3.6, "cam": s4_cam, "hidechar": True, "server_frame": s4_server,
               "pre_req": '[["req","VatStart"]]', "pre_wait": 3}

# ---- S6: end shot, pull back from the low base view up to the whole map with all eight jar bases
def s6_cam(t):
    u = smooth(t / 4.4)
    up = smooth(t / 4.4) ** 0.6  # eases in from the cut, then rises ahead of the pull-back to clear the fountain
    p0, p1 = [20, 11, 42], [0, 208, -220]
    pos = [p0[0] + (p1[0] - p0[0]) * u, p0[1] + (p1[1] - p0[1]) * up, p0[2] + (p1[2] - p0[2]) * u]
    at = lerp([56, 9, 106], [3, 0, 12], u)
    return pos, at
SHOTS["s6"] = {"dur": 4.4, "cam": s6_cam, "hidechar": True,
               "setup_client": "local hrp = game.Players.LocalPlayer.Character.HumanoidRootPart hrp.Anchored = true hrp.CFrame = CFrame.new(-60, 4, -60) return {}"}
