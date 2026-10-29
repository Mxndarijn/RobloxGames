--!strict
--[[
	AdminMenu (client, contract/admin-menu.md §5)

	Builds the Admin panel the first time a State carries `admin` (the server only sends it to players who get the
	menu), registers it as a menu card and toggles it with F2 or the "/admin" chat command. Players without the menu
	never build it: no instances, no key binding, no chat command.
]]

local AdminMenu = {}

AdminMenu.KEY = Enum.KeyCode.F2
AdminMenu.CHAT_COMMAND = "/admin"
AdminMenu.PANEL_KEY = "Admin"

export type Options = {
	gui: Instance,
	ctx: any,
	input: UserInputService?,
	chat: TextChatService?,
	build: (gui: Instance, ctx: any) -> any, -- Panels/Admin.new
	addPanel: (key: string, panel: any) -> (), -- registers the card with the menu manager
	toggle: () -> (),
}

-- Returns `update(state)` and a stop function that disconnects everything it made.
function AdminMenu.start(options: Options): ((state: any) -> (), () -> ())
	local panel: any = nil
	local conns: { RBXScriptConnection } = {}
	local made: { Instance } = {}

	local function bind()
		local input = options.input
		if input then
			table.insert(
				conns,
				input.InputBegan:Connect(function(event: InputObject, processed: boolean)
					if not processed and event.KeyCode == AdminMenu.KEY then
						options.toggle()
					end
				end)
			)
		end
		local chat = options.chat
		if chat then
			pcall(function()
				local command = Instance.new("TextChatCommand")
				command.Name = "AdminMenuCommand"
				command.PrimaryAlias = AdminMenu.CHAT_COMMAND
				command.Parent = chat
				table.insert(made, command)
				table.insert(
					conns,
					command.Triggered:Connect(function()
						options.toggle()
					end)
				)
			end)
		end
	end

	local function update(state: any)
		if type(state) ~= "table" or type(state.admin) ~= "table" then
			return
		end
		if panel == nil then
			panel = options.build(options.gui, options.ctx)
			options.addPanel(AdminMenu.PANEL_KEY, panel)
			bind()
		end
		panel.update(state)
	end

	local function stop()
		for _, conn in conns do
			conn:Disconnect()
		end
		for _, inst in made do
			inst:Destroy()
		end
		table.clear(conns)
		table.clear(made)
	end

	return update, stop
end

return AdminMenu
