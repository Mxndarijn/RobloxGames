"""python still.py <out.jpg> <t> <cam offset x,y,z> <look offset x,y,z> [fov] [dof f,r,i]: pose the obby jumper at t, shoot"""
import sys, drv, shots
out, t = sys.argv[1], float(sys.argv[2])
o = [float(v) for v in sys.argv[3].split(",")]; a = [float(v) for v in sys.argv[4].split(",")]
fov = sys.argv[5] if len(sys.argv) > 5 else "70"
dof = sys.argv[6] if len(sys.argv) > 6 else "0,0,0"
s = drv.session()
w = shots.Walker(0.08)
k = 0
while k / 30 <= t:  # warm the walker so heading is the same as in the clip
    lua = shots.s5_client(k / 30, k); k += 1
p = shots.s5_body(t)[0]
pos = ",".join("%.3f" % (p[i] + o[i]) for i in range(3)); at = ",".join("%.3f" % (p[i] + a[i]) for i in range(3))
body = "game.Players.LocalPlayer.Character.HumanoidRootPart.Anchored = true " + lua + """
workspace:SetAttribute("VCamPos", Vector3.new(%s)) workspace:SetAttribute("VCamAt", Vector3.new(%s))
workspace:SetAttribute("VFov", %s) workspace:SetAttribute("VDof", Vector3.new(%s))
task.wait(1.2)
return {}""" % (pos, at, fov, dof)
print(s.luau(drv.SID, body, datamodel="Client")[1])
drv.shot(s, out)
s.close()
