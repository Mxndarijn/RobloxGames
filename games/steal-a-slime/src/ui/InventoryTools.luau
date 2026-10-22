--!strict
--[[
	InventoryTools (S3): the client's view of the Tools the server gave the player (BatTool, the Speed Coil, ...)
	and the default Roblox backpack bar it replaces. Roblox owns Tools; this only lists the Backpack + the
	character's held Tool and equips / unequips through the Humanoid (what the default backpack did).
	The server still unequips while carrying (CONTRACT.md §8.10) and decides everything else.
]]

local GuiService = game:GetService("GuiService")
local StarterGui = game:GetService("StarterGui")
local UserInputService = game:GetService("UserInputService")

local InputKind = require(script.Parent.InputKind)

local InventoryTools = {}

export type Provider = {
	list: () -> { { name: string, equipped: boolean } },
	setEquipped: (name: string, on: boolean) -> (),
	unequipAll: () -> (),
	onChanged: (cb: () -> ()) -> (),
	destroy: () -> (),
}

-- Hides Roblox's own backpack bar (StarterGui:SetCoreGuiEnabled fails until the core scripts register: retry).
function InventoryTools.hideDefaultBackpack(tries: number?)
	local ok = pcall(function()
		StarterGui:SetCoreGuiEnabled(Enum.CoreGuiType.Backpack, false)
	end)
	local left = (tries or 20) - 1
	if not ok and left > 0 then
		task.delay(0.5, InventoryTools.hideDefaultBackpack, left)
	end
end

-- Number keys 1-9 (not while typing in a TextBox / when another script used the key).
function InventoryTools.bindKeys(slotFor: (Enum.KeyCode) -> number?, onSlot: (number) -> ())
	UserInputService.InputBegan:Connect(function(input: InputObject, processed: boolean)
		if processed or input.UserInputType ~= Enum.UserInputType.Keyboard then
			return
		end
		local n = slotFor(input.KeyCode)
		if n then
			onSlot(n)
		end
	end)
end

-- Gamepad bumpers: L1 -> -1 (previous hotbar slot), R1 -> +1 (next). Not while typing / when a GUI took the button.
function InventoryTools.bindBumpers(onStep: (step: number) -> ())
	UserInputService.InputBegan:Connect(function(input: InputObject, processed: boolean)
		if processed then
			return
		end
		if input.KeyCode == Enum.KeyCode.ButtonL1 then
			onStep(-1)
		elseif input.KeyCode == Enum.KeyCode.ButtonR1 then
			onStep(1)
		end
	end)
end

-- The bag key on a keyboard or gamepad (not while typing in a TextBox / when another script used the key).
function InventoryTools.bindBag(isBagKey: (Enum.KeyCode) -> boolean, onBag: () -> ())
	UserInputService.InputBegan:Connect(function(input: InputObject, processed: boolean)
		if processed then
			return
		end
		local kind = input.UserInputType
		if kind ~= Enum.UserInputType.Keyboard and kind ~= Enum.UserInputType.Gamepad1 then
			return
		end
		if isBagKey(input.KeyCode) then
			onBag()
		end
	end)
end

-- A touch held this long fires TouchLongPress (Begin): the press counts as held for that long already.
InventoryTools.LONG_PRESS_SECONDS = 0.5

--[[
	A click or tap that no GUI took (the world) uses the item in hand. `onPress` gets the screen point (and the
	seconds the press was already held: a touch long press) when it goes down, `onRelease` when it comes up; the
	inventory decides whether the item fires on the press or on the release (a hold: a glove's power punch, the
	Goo Cannon's aim). Touch uses TouchTap / TouchLongPress, so dragging the camera or the thumbstick never fires an item.
]]
function InventoryTools.bindUse(
	onPress: (screen: Vector2 | Vector3, alreadyHeld: number?) -> (),
	onRelease: (screen: Vector2 | Vector3) -> ()
)
	-- A gamepad has no pointer: R2 aims from the true screen centre (InputKind.screenCentre) (a Tool such as the Bat gets Tool.Activated from R2
	-- itself; onPress ignores it because only a consumable or a PvP item is used from here).
	local function centre(): Vector2?
		local camera = workspace.CurrentCamera
		return if camera then InputKind.screenCentre(camera.ViewportSize, GuiService:GetGuiInset()) else nil
	end
	UserInputService.InputBegan:Connect(function(input: InputObject, processed: boolean)
		if processed then
			return
		end
		if input.UserInputType == Enum.UserInputType.MouseButton1 then
			onPress(input.Position)
		elseif input.KeyCode == Enum.KeyCode.ButtonR2 then
			local at = centre()
			if at then
				onPress(at)
			end
		end
	end)
	UserInputService.InputEnded:Connect(function(input: InputObject)
		if input.UserInputType == Enum.UserInputType.MouseButton1 then
			onRelease(input.Position)
		elseif input.KeyCode == Enum.KeyCode.ButtonR2 then
			local at = centre()
			if at then
				onRelease(at)
			end
		end
	end)
	UserInputService.TouchTap:Connect(function(positions: { Vector2 }, processed: boolean)
		if not processed and positions[1] then
			onPress(positions[1])
			onRelease(positions[1])
		end
	end)
	UserInputService.TouchLongPress:Connect(
		function(positions: { Vector2 }, state: Enum.UserInputState, processed: boolean)
			local at = positions[1]
			if processed or not at then
				return
			end
			if state == Enum.UserInputState.Begin then
				onPress(at, InventoryTools.LONG_PRESS_SECONDS)
			elseif state == Enum.UserInputState.End then
				onRelease(at)
			end
		end
	)
end

function InventoryTools.new(player: Player): Provider
	local connections: { RBXScriptConnection } = {}
	local callbacks: { () -> () } = {}
	local watched: { [Instance]: boolean } = {}

	local function changed()
		for _, cb in callbacks do
			cb()
		end
	end

	local function watch(container: Instance?)
		if not container or watched[container] then
			return
		end
		watched[container] = true
		table.insert(connections, container.ChildAdded:Connect(changed))
		table.insert(connections, container.ChildRemoved:Connect(changed))
	end

	local function bindCharacter(character: Model?)
		watch(character)
		watch(player:FindFirstChildOfClass("Backpack"))
		changed()
	end
	table.insert(
		connections,
		player.CharacterAdded:Connect(function(character)
			-- the Backpack is recreated on every respawn
			watched = {}
			bindCharacter(character)
		end)
	)
	table.insert(
		connections,
		player.ChildAdded:Connect(function(child)
			if child:IsA("Backpack") then
				watch(child)
				changed()
			end
		end)
	)
	bindCharacter(player.Character)

	local function humanoid(): Humanoid?
		local character = player.Character
		return if character then character:FindFirstChildOfClass("Humanoid") else nil
	end

	local function find(name: string): Tool?
		local character = player.Character
		local backpack = player:FindFirstChildOfClass("Backpack")
		for _, container in { character :: Instance?, backpack :: Instance? } do
			local tool = if container then container:FindFirstChild(name) else nil
			if tool and tool:IsA("Tool") then
				return tool
			end
		end
		return nil
	end

	local self = {} :: Provider
	function self.list()
		local out = {}
		local character = player.Character
		local backpack = player:FindFirstChildOfClass("Backpack")
		for _, container in { backpack :: Instance?, character :: Instance? } do
			if container then
				for _, child in container:GetChildren() do
					if child:IsA("Tool") then
						table.insert(out, { name = child.Name, equipped = (container :: Instance) == character })
					end
				end
			end
		end
		return out
	end
	function self.setEquipped(name: string, on: boolean)
		local hum, tool = humanoid(), find(name)
		if not hum or not tool or hum.Health <= 0 then
			return
		end
		if on then
			hum:EquipTool(tool)
		elseif tool.Parent == player.Character then
			hum:UnequipTools()
		end
	end
	function self.unequipAll()
		local hum = humanoid()
		if hum then
			hum:UnequipTools()
		end
	end
	function self.onChanged(cb: () -> ())
		table.insert(callbacks, cb)
	end
	function self.destroy()
		for _, c in connections do
			c:Disconnect()
		end
		table.clear(callbacks)
	end
	return self
end

return InventoryTools
