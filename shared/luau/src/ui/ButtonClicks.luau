--!strict
--[[
	ButtonClicks (adapter, client)

	Every GuiButton under `root` plays a click sound when pressed, so the HUD and every menu click without each
	panel wiring it. Pass the game's own ScreenGui, not PlayerGui, so Roblox's touch jump button stays quiet.
	Buttons made later (panels built on demand, list rows) are picked up through DescendantAdded. A button
	carrying one of the skip attributes stays quiet, checked on each press: by default `HoldConfirm` (a
	hold-to-confirm button, where a tap does nothing) and `ClickMuted` (a disabled button).

	`play(soundName)` is injected (the game's sound player, a stub in specs), and so is `enabled` (optional, a
	settings switch): while it returns false no button clicks. `options` overrides the sound name ("click") and
	the skip attributes. start() returns a cleanup that disconnects everything it made.
]]

local ButtonClicks = {}

ButtonClicks.SOUND = "click"
ButtonClicks.SKIP_ATTRIBUTES = table.freeze({ "HoldConfirm", "ClickMuted" })

export type Options = { sound: string?, skipAttributes: { string }? }

local function muted(inst: Instance, skip: { string }): boolean
	for _, attr in skip do
		if inst:GetAttribute(attr) ~= nil then
			return true
		end
	end
	return false
end

function ButtonClicks.start(
	root: Instance,
	play: (string) -> any,
	enabled: (() -> boolean)?,
	options: Options?
): () -> ()
	local sound = (options and options.sound) or ButtonClicks.SOUND
	local skip = (options and options.skipAttributes) or ButtonClicks.SKIP_ATTRIBUTES
	local conns: { [Instance]: RBXScriptConnection } = setmetatable({}, { __mode = "k" }) :: any
	local function watch(inst: Instance)
		if conns[inst] == nil and inst:IsA("GuiButton") then
			conns[inst] = (inst :: GuiButton).Activated:Connect(function()
				if not muted(inst, skip) and (enabled == nil or enabled()) then
					play(sound)
				end
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

return table.freeze(ButtonClicks)
