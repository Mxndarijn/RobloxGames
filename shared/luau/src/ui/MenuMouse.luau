--!strict
--[[
	MenuMouse (adapter, client)

	Frees the mouse while a menu is open. In first person (and with shift lock) Roblox locks the
	cursor to the screen centre, so a player can't point at a button. A visible GuiButton with
	`Modal = true` makes Roblox release the cursor until it hides again; this module owns one such
	button (zero size, transparent, never selectable, so it blocks no clicks and no gamepad focus)
	and shows it only while the game says a menu is open.

	    local mouse = MenuMouse.new(screenGui)
	    mouse.setOpen(anyMenuOpen)
	    mouse.destroy()

	The ScreenGui must be enabled for the button to count.
]]

local MenuMouse = {}

export type Handle = {
	setOpen: (open: boolean) -> (),
	isOpen: () -> boolean,
	destroy: () -> (),
}

function MenuMouse.new(parent: Instance, name: string?): Handle
	local button = Instance.new("TextButton")
	button.Name = name or "MenuMouseUnlock"
	button.Text = ""
	button.Modal = true
	button.Visible = false
	button.Active = false
	button.Selectable = false
	button.AutoButtonColor = false
	button.BackgroundTransparency = 1
	button.Size = UDim2.fromOffset(0, 0)
	button.Parent = parent

	local open = false
	local handle = {}

	function handle.setOpen(want: boolean)
		open = want
		button.Visible = want
	end

	function handle.isOpen(): boolean
		return open
	end

	function handle.destroy()
		open = false
		button:Destroy()
	end

	return table.freeze(handle) :: any
end

return table.freeze(MenuMouse)
