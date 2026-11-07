"""python adshot.py <out.jpg> <spec.json>: pose the player, set camera/look/dof, shoot. Game time stays frozen.
spec: {cam:[x,y,z], at:[x,y,z], fov, dof:[f,r,i], char:{pos:[..], face:[..], anim:"VidCheer", t:0.4} | null, lua:"..."}"""
import sys, json, drv
out, spec = sys.argv[1], json.load(open(sys.argv[2])) if sys.argv[2].endswith(".json") else json.loads(sys.argv[2])
s = drv.session()
lua = ["local c = game.Players.LocalPlayer.Character local hrp = c.HumanoidRootPart"]
ch = spec.get("char")
if ch:
    p, f = ch["pos"], ch.get("face", [ch["pos"][0], ch["pos"][1], ch["pos"][2] - 1])
    lua.append("hrp.Anchored = true hrp.CFrame = CFrame.lookAt(Vector3.new(%f,%f,%f), Vector3.new(%f,%f,%f))" % (p[0], p[1], p[2], f[0], p[1], f[2]))
    lua.append("""for _, d in c:GetDescendants() do if d:IsA("BasePart") or d:IsA("Decal") then d.LocalTransparencyModifier = 0 end end
for _, tr in c.Humanoid.Animator:GetPlayingAnimationTracks() do
	if tr.Name == %r then tr:AdjustWeight(1, 0) tr.TimePosition = %f * tr.Length tr:AdjustSpeed(0) else tr:AdjustWeight(0.001, 0) end
end""" % (ch.get("anim", "VidIdle"), ch.get("t", 0.3)))
else:
    lua.append("hrp.Anchored = true hrp.CFrame = CFrame.new(-60, 4, -60)")
lua.append(spec.get("lua", ""))
cam, at = spec["cam"], spec["at"]
dof = spec.get("dof", [0, 0, 0])
lua.append("""workspace:SetAttribute("VCamPos", Vector3.new(%f,%f,%f)) workspace:SetAttribute("VCamAt", Vector3.new(%f,%f,%f))
workspace:SetAttribute("VFov", %s) workspace:SetAttribute("VDof", Vector3.new(%f,%f,%f))
task.wait(%s) return {}""" % (*cam, *at, spec.get("fov", 62), *dof, spec.get("wait", 1.5)))
print(s.luau(drv.SID, "\n".join(lua), datamodel="Client", timeout=120)[1])
drv.shot(s, out)
s.close()
