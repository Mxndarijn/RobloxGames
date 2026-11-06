--!strict
--[[
	SlimeLabelText: a SlimeLabel.View in the player's language, for the slime tag (SlimeInfoCard) and the pad sign
	(SlimePadSign). The server keeps the name ("BOSS Lop", "Brewed Lop") and the status row as JSON Localize
	messages next to the English attributes (SlimeLabel nameMessage / statusMessage); this decodes them and draws
	them with ui/Text. A view without messages comes back as it is (plain species names stay as they are).
]]

local Text = require(script.Parent.Text)

local SlimeLabelText = {}

local function decode(json: any): any
	if type(json) ~= "string" or json == "" then
		return nil
	end
	local ok, value = pcall(function()
		return game:GetService("HttpService"):JSONDecode(json)
	end)
	return if ok and type(value) == "table" and type(value.key) == "string" then value else nil
end

function SlimeLabelText.view<V>(view: V): V
	local v = view :: any
	local name, status = decode(v.nameMessage), decode(v.statusMessage)
	if name == nil and status == nil then
		return view
	end
	local out = table.clone(v)
	if name then
		out.name = Text.text(name)
	end
	if status then
		out.income = Text.text(status)
	end
	return out :: any
end

return table.freeze(SlimeLabelText)
