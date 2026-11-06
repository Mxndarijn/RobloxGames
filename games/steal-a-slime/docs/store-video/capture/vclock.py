import os,sys
root=sys.argv[1]; n=0
H=('local __vclock = function() local v = workspace:GetAttribute("VClock") if type(v) == "number" then return v end return os.clock() end '
   'local __vserver = function() local v = workspace:GetAttribute("VServer") if type(v) == "number" then return v end return workspace:GetServerTimeNow() end')
for dp,_,fs in os.walk(root):
    for f in fs:
        if not f.endswith('.luau'): continue
        p=os.path.join(dp,f); s=open(p,encoding='utf8',newline='').read()
        if 'os.clock()' not in s and 'GetServerTimeNow()' not in s: continue
        s=s.replace('os.clock()','__vclock()').replace('workspace:GetServerTimeNow()','__vserver()').replace('(workspace :: any):GetServerTimeNow()','__vserver()')
        lines=s.split('\n'); i=0
        while i<len(lines) and lines[i].startswith('--!'): i+=1
        lines.insert(i,H); s='\n'.join(lines)
        open(p,'w',encoding='utf8',newline='').write(s); n+=1
print('patched',n)
