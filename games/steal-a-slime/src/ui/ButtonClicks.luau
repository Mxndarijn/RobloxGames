--!strict
--[[
	ButtonClicks

	Every GuiButton under `root` (the game's own ScreenGui, not PlayerGui, so Roblox's touch jump button
	stays quiet) plays the "click" sound when pressed, so the HUD and every menu click without each panel
	wiring it. Buttons made later (panels built on demand, list rows) are picked up
	through DescendantAdded.

	`play` is injected (SoundController.play in the client, a stub in tests/ui/ButtonClicks.spec.luau).
	start() returns a cleanup that disconnects everything it made.
]]

local ButtonClicks = {}

ButtonClicks.SOUND = "click"

function ButtonClicks.start(root: Instance, play: (string) -> any): () -> ()
	local conns: { [Instance]: RBXScriptConnection } = setmetatable({}, { __mode = "k" }) :: any
	local function watch(inst: Instance)
		if conns[inst] == nil and inst:IsA("GuiButton") then
			conns[inst] = (inst :: GuiButton).Activated:Connect(function()
				play(ButtonClicks.SOUND)
			end)
		end
	end
	for _, inst in root:GetDescendants() do
		watch(inst)
	end
	local added = root.DescendantAdded:Connect(watch)
	return function()
		added:Disconnect()
		for inst, conn in conns do
			conn:Disconnect()
			conns[inst] = nil
		end
	end
end

return ButtonClicks
