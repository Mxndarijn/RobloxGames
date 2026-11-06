import drv, json, subprocess, sys, time
s = drv.session()
def req(cmds):
    s.luau(drv.SID, "workspace:SetAttribute('VidRes', '') workspace:SetAttribute('VidReq', [==[" + json.dumps(cmds) + "]==]) return {}", datamodel="Server")
    for i in range(60):
        time.sleep(1)
        ok, d, _ = s.luau(drv.SID, "return {r = workspace:GetAttribute('VidRes')}", datamodel="Server")
        if d and d.get("r"): return json.loads(d["r"])
s.luau(drv.SID, "workspace:SetAttribute('VClock', nil) workspace:SetAttribute('VServer', nil) return {}", datamodel="Server")
print(req([["req","Admin","vidSpawn","0_6_-"],["req","Admin","vidSpawn","0_6_-"],["req","Admin","vidSpawn","0_6_-"]]))
r = req([["eval", """return function(world, player, now)
  local s = world.sessions[player.UserId]
  local new = {}
  for _, sl in s.data.slimes do
    if sl.pad == 7 then sl.pad = 20 end
  end
  for _, sl in s.data.slimes do
    if sl.tier == 6 and sl.pad and sl.pad >= 9 then table.insert(new, sl) end
  end
  table.sort(new, function(a, b) return a.pad < b.pad end)
  new[1].pad = 7
  s.dirty = true require(script.World).markAllDirty(world)
  return {new[1].id, new[2].id, new[3].id}
end"""]])
print(r)
ids = json.loads(r[0].split(" -> true ", 1)[1])
print(req([["req","VatAdd",i] for i in ids]))
s.close()
