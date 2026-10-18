--!strict
--[[
	ToolProvider (client adapter): the Roblox Tools in the local player's Backpack and character, for games that
	show them in the hotbar as extra entries, plus the input helpers a custom hotbar needs.

	Roblox owns Tools; this only lists them and equips / unequips through the Humanoid, as the default backpack
	bar does. The server still decides what Tools a player has.
]]

local StarterGui = game:GetService("StarterGui")
local UserInputService = game:GetService("UserInputService")

export type ToolInfo = { name: string, equipped: boolean }

export type Provider = {
	list: () -> { ToolInfo },
	setEquipped: (name: string, on: boolean) -> (),
	unequipAll: () -> (),
	onChanged: (cb: () -> ()) -> (),
	destroy: () -> (),
}

export type Handle = { destroy: () -> () }

local ToolProvider = {}

local NUMBER_KEYS: { [Enum.KeyCode]: number } = {
	[Enum.KeyCode.One] = 1,
	[Enum.KeyCode.Two] = 2,
	[Enum.KeyCode.Three] = 3,
	[Enum.KeyCode.Four] = 4,
	[Enum.KeyCode.Five] = 5,
	[Enum.KeyCode.Six] = 6,
	[Enum.KeyCode.Seven] = 7,
	[Enum.KeyCode.Eight] = 8,
	[Enum.KeyCode.Nine] = 9,
}

-- Hides Roblox's own backpack bar. SetCoreGuiEnabled fails until the core scripts register, so it retries.
function ToolProvider.hideDefaultBackpack(tries: number?)
	local ok = pcall(function()
		StarterGui:SetCoreGuiEnabled(Enum.CoreGuiType.Backpack, false)
	end)
	local left = (tries or 20) - 1
	if not ok and left > 0 then
		task.delay(0.5, ToolProvider.hideDefaultBackpack, left)
	end
end

-- Number keys 1-9 call `onSlot(n)`, except while typing in a TextBox or when another script took the key.
function ToolProvider.bindNumberKeys(onSlot: (n: number) -> ()): Handle
	local conn = UserInputService.InputBegan:Connect(function(input: InputObject, processed: boolean)
		if processed or input.UserInputType ~= Enum.UserInputType.Keyboard then
			return
		end
		local n = NUMBER_KEYS[input.KeyCode]
		if n then
			onSlot(n)
		end
	end)
	return {
		destroy = function()
			conn:Disconnect()
		end,
	}
end

-- A click or tap that no GUI took (a press on the world) calls `onUse`; the game decides whether anything is held.
function ToolProvider.bindWorldPress(onUse: () -> ()): Handle
	local conn = UserInputService.InputBegan:Connect(function(input: InputObject, processed: boolean)
		if processed then
			return
		end
		local kind = input.UserInputType
		if kind == Enum.UserInputType.MouseButton1 or kind == Enum.UserInputType.Touch then
			onUse()
		end
	end)
	return {
		destroy = function()
			conn:Disconnect()
		end,
	}
end

function ToolProvider.new(player: Player): Provider
	local connections: { RBXScriptConnection } = {}
	local containerConnections: { RBXScriptConnection } = {}
	local callbacks: { () -> () } = {}

	local function changed()
		for _, cb in callbacks do
			task.spawn(cb)
		end
	end

	local function watch(container: Instance?)
		if container == nil then
			return
		end
		table.insert(containerConnections, container.ChildAdded:Connect(changed))
		table.insert(containerConnections, container.ChildRemoved:Connect(changed))
	end

	-- The Backpack is recreated on every respawn, so watching restarts with each character.
	local function rewatch()
		for _, c in containerConnections do
			c:Disconnect()
		end
		table.clear(containerConnections)
		watch(player.Character)
		watch(player:FindFirstChildOfClass("Backpack"))
		changed()
	end

	table.insert(connections, player.CharacterAdded:Connect(rewatch))
	table.insert(
		connections,
		player.ChildAdded:Connect(function(child)
			if child:IsA("Backpack") then
				rewatch()
			end
		end)
	)
	rewatch()

	local function humanoid(): Humanoid?
		local character = player.Character
		return if character then character:FindFirstChildOfClass("Humanoid") else nil
	end

	local function find(name: string): Tool?
		for _, container in { player.Character :: Instance?, player:FindFirstChildOfClass("Backpack") :: Instance? } do
			local tool = if container then container:FindFirstChild(name) else nil
			if tool and tool:IsA("Tool") then
				return tool
			end
		end
		return nil
	end

	local provider = {} :: Provider

	function provider.list(): { ToolInfo }
		local out: { ToolInfo } = {}
		local character = player.Character
		for _, container in { player:FindFirstChildOfClass("Backpack") :: Instance?, character :: Instance? } do
			if container then
				for _, child in container:GetChildren() do
					if child:IsA("Tool") then
						table.insert(out, { name = child.Name, equipped = container == character })
					end
				end
			end
		end
		table.sort(out, function(a, b)
			return a.name < b.name
		end)
		return out
	end

	function provider.setEquipped(name: string, on: boolean)
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

	function provider.unequipAll()
		local hum = humanoid()
		if hum then
			hum:UnequipTools()
		end
	end

	function provider.onChanged(cb: () -> ())
		table.insert(callbacks, cb)
	end

	function provider.destroy()
		for _, c in connections do
			c:Disconnect()
		end
		for _, c in containerConnections do
			c:Disconnect()
		end
		table.clear(connections)
		table.clear(containerConnections)
		table.clear(callbacks)
	end

	return provider
end

return table.freeze(ToolProvider)
