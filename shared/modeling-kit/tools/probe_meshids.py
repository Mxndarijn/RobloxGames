import os,json,time,requests,sys
K=os.environ["ROBLOX_OPEN_CLOUD_API_KEY"];H={"x-api-key":K}
U,P="10770917350","135787188192378"
ids=json.load(open(sys.argv[1]))
lua="local IS=game:GetService('InsertService');local out={}\n"
for n,v in ids.items():
  lua+=f"do local ok,m=pcall(function() return IS:LoadAsset({v['assetId']}) end) if not ok then table.insert(out,'{n} ERR '..tostring(m)) else for _,d in m:GetDescendants() do if d:IsA('MeshPart') then table.insert(out,'{n} '..d.Name..' '..d.MeshId..' '..tostring(d.Size)..' tex='..d.TextureID) end end end end\n"
lua+="return table.concat(out,'\\n')"
r=requests.post(f"https://apis.roblox.com/cloud/v2/universes/{U}/places/{P}/luau-execution-session-tasks",headers=H,json={"script":lua})
r.raise_for_status();path=r.json()["path"]
for i in range(60):
  time.sleep(3);t=requests.get("https://apis.roblox.com/cloud/v2/"+path,headers=H).json()
  if t.get("state") in("COMPLETE","FAILED","CANCELLED"):print(t.get("state"),json.dumps(t.get("output"),indent=1),t.get("error"));break
