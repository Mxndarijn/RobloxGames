-- Server datamodel: destroys every watcher seat clone (PcwSeat from slime_seat, PcwPad from pad_seat), so only
-- the real slimes WorldView renders are left. Returns the number removed.
local n = 0
for _, m in game:GetService("CollectionService"):GetTagged("Slime") do
	if m:GetAttribute("PcwSeat") or m:GetAttribute("PcwPad") then
		m:Destroy()
		n += 1
	end
end
return { removed = n }
