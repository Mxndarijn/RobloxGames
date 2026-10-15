--!strict
-- Jolt HUD: shows Speed / Stage (player attributes), Wins (leaderstats) and a
-- temporary popup on Remotes.WinEvent. Read-only: never writes server state.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local POPUP_SECONDS = 3

local player = Players.LocalPlayer

local gui = Instance.new("ScreenGui")
gui.Name = "JoltSpeedHud"
gui.ResetOnSpawn = false

local panel = Instance.new("Frame")
panel.Name = "Stats"
panel.AnchorPoint = Vector2.new(0, 0.5)
panel.Position = UDim2.new(0, 10, 0.5, 0)
panel.Size = UDim2.fromOffset(180, 100)
panel.BackgroundColor3 = Color3.new(0, 0, 0)
panel.BackgroundTransparency = 0.4
panel.Parent = gui

local layout = Instance.new("UIListLayout")
layout.SortOrder = Enum.SortOrder.LayoutOrder
layout.Parent = panel

local function makeLabel(name: string, order: number): TextLabel
	local label = Instance.new("TextLabel")
	label.Name = name
	label.LayoutOrder = order
	label.Size = UDim2.fromScale(1, 1 / 3)
	label.BackgroundTransparency = 1
	label.TextColor3 = Color3.new(1, 1, 1)
	label.TextScaled = true
	label.TextXAlignment = Enum.TextXAlignment.Left
	label.Parent = panel
	return label
end

local speedLabel = makeLabel("Speed", 1)
local stageLabel = makeLabel("Stage", 2)
local winsLabel = makeLabel("Wins", 3)

local popup = Instance.new("TextLabel")
popup.Name = "WinPopup"
popup.AnchorPoint = Vector2.new(0.5, 0.5)
popup.Position = UDim2.fromScale(0.5, 0.35)
popup.Size = UDim2.fromOffset(360, 100)
popup.BackgroundColor3 = Color3.fromRGB(255, 200, 40)
popup.TextColor3 = Color3.new(0, 0, 0)
popup.TextScaled = true
popup.Visible = false
popup.Parent = gui

gui.Parent = player:WaitForChild("PlayerGui")

local function numberAttribute(name: string): number
	local value = player:GetAttribute(name)
	return if type(value) == "number" then value else 0
end

local function bindAttribute(name: string, label: TextLabel)
	local function refresh()
		label.Text = string.format(" %s: %d", name, math.floor(numberAttribute(name)))
	end
	player:GetAttributeChangedSignal(name):Connect(refresh)
	refresh()
end

bindAttribute("Speed", speedLabel)
bindAttribute("Stage", stageLabel)

winsLabel.Text = " Wins: 0"
task.spawn(function()
	local leaderstats = player:WaitForChild("leaderstats", 30)
	local wins = leaderstats and leaderstats:WaitForChild("Wins", 30)
	if not (wins and wins:IsA("IntValue")) then
		warn("JoltSpeedHud: leaderstats.Wins not found")
		return
	end
	local function refresh()
		winsLabel.Text = ` Wins: {wins.Value}`
	end
	wins.Changed:Connect(refresh)
	refresh()
end)

local popupToken = 0
task.spawn(function()
	local remotes = ReplicatedStorage:WaitForChild("Remotes")
	local winEvent = remotes:WaitForChild("WinEvent") :: RemoteEvent
	winEvent.OnClientEvent:Connect(function(totalWins: number)
		popupToken += 1
		local token = popupToken
		popup.Text = `YOU WIN!\nTotal wins: {totalWins}`
		popup.Visible = true
		task.delay(POPUP_SECONDS, function()
			if token == popupToken then
				popup.Visible = false
			end
		end)
	end)
end)
