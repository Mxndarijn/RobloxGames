if workspace:GetAttribute("VidMuted") then return {already=true} end
local function mute(s) if s:IsA("Sound") or s:IsA("SoundGroup") then s.Volume = 0; s:GetPropertyChangedSignal("Volume"):Connect(function() if s.Volume ~= 0 then s.Volume = 0 end end) end end
local n=0
for _, d in game:GetDescendants() do if pcall(mute, d) then n+=1 end end
game.DescendantAdded:Connect(function(d) pcall(mute, d) end)
workspace:SetAttribute("VidMuted", true)
return {muted=n}
