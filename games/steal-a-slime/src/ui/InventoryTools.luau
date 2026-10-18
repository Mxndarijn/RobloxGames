--!strict
--[[
	InventoryTools (S3): the client's view of the Tools the server gave the player (BatTool, the Speed Coil, ...)
	and the default Roblox backpack bar it replaces. Roblox owns Tools; this only lists the Backpack + the
	character's held Tool and equips / unequips through the Humanoid (what the default backpack did).
	The server still unequips while carrying (CONTRACT.md §8.10) and decides everything else.
]]

local StarterGui = game:GetService("StarterGui")
local UserInputService = game:GetService("UserInputService")

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

-- A click or tap that no GUI took (the world) uses the item in hand: `onUse` gets the screen point and decides
-- if anything is held. Touch uses TouchTap, so dragging the camera or the thumbstick never fires an item.
function InventoryTools.bindUse(onUse: (screen: Vector2 | Vector3) -> ())
	UserInputService.InputBegan:Connect(function(input: InputObject, processed: boolean)
		if not processed and input.UserInputType == Enum.UserInputType.MouseButton1 then
			onUse(input.Position)
		end
	end)
	UserInputService.TouchTap:Connect(function(positions: { Vector2 }, processed: boolean)
		if not processed and positions[1] then
			onUse(positions[1])
		end
	end)
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
