--!strict
--[[
	Loading (ReplicatedFirst LocalScript)

	The join loading screen. Replaces Roblox's default screen at once, then
	holds the player behind a covering screen until the place has replicated,
	the server has dressed the world in its kit meshes (WorldMeshesReady), and
	ContentProvider has fetched the world's meshes, the terrain ColorMaps and
	the HUD's images. Without it the world showed grey primitives and
	untextured terrain that filled in over the first seconds. LoadingGate
	decides the bar, the label and when to lift; the screen never holds a
	player longer than LoadingGate.MAX_WAIT and offers a skip button.
]]

local ContentProvider = game:GetService("ContentProvider")
local MaterialService = game:GetService("MaterialService")
local Players = game:GetService("Players")
local ReplicatedFirst = game:GetService("ReplicatedFirst")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local LoadingGate = require(script:WaitForChild("LoadingGate"))

local LOOK = require(script:WaitForChild("LoadingLook"))
local BATCH = 40 -- assets per PreloadAsync call: keeps the bar moving

ReplicatedFirst:RemoveDefaultLoadingScreen()

local player = Players.LocalPlayer
local gui = Instance.new("ScreenGui")
gui.Name = "LoadingScreen"
gui.IgnoreGuiInset = true
gui.ResetOnSpawn = false
gui.DisplayOrder = LOOK.displayOrder
gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling

local bg = Instance.new("Frame")
bg.Name = "Background"
bg.Size = UDim2.fromScale(1, 1)
bg.BackgroundColor3 = LOOK.bg
bg.BorderSizePixel = 0
bg.Parent = gui

local function label(name: string, text: string, size: number, color: Color3, y: number): TextLabel
	local l = Instance.new("TextLabel")
	l.Name = name
	l.AnchorPoint = Vector2.new(0.5, 0.5)
	l.Position = UDim2.new(0.5, 0, 0.5, y)
	l.Size = UDim2.fromOffset(600, size + 8)
	l.BackgroundTransparency = 1
	l.Font = LOOK.font
	l.Text = text
	l.TextSize = size
	l.TextColor3 = color
	l.Parent = bg
	return l
end

label("Title", "Steal a Slime", LOOK.titleSize, LOOK.text, -60)
local status = label("Status", LoadingGate.LABELS.place, LOOK.labelSize, LOOK.muted, 50)

local barBack = Instance.new("Frame")
barBack.Name = "Bar"
barBack.AnchorPoint = Vector2.new(0.5, 0.5)
barBack.Position = UDim2.new(0.5, 0, 0.5, 14)
barBack.Size = LOOK.barSize
barBack.BackgroundColor3 = LOOK.barBack
barBack.BorderSizePixel = 0
barBack.Parent = bg
Instance.new("UICorner", barBack).CornerRadius = UDim.new(1, 0)
local fill = Instance.new("Frame")
fill.Name = "Fill"
fill.Size = UDim2.fromScale(0, 1)
fill.BackgroundColor3 = LOOK.bar
fill.BorderSizePixel = 0
fill.Parent = barBack
Instance.new("UICorner", fill).CornerRadius = UDim.new(1, 0)

local skip = Instance.new("TextButton")
skip.Name = "Skip"
skip.AnchorPoint = Vector2.new(0.5, 0.5)
skip.Position = UDim2.new(0.5, 0, 0.5, 100)
skip.Size = UDim2.fromOffset(120, 36)
skip.BackgroundColor3 = LOOK.barBack
skip.Font = LOOK.font
skip.Text = "Skip"
skip.TextSize = LOOK.labelSize
skip.TextColor3 = LOOK.text
skip.Visible = false
skip.Parent = bg
Instance.new("UICorner", skip).CornerRadius = UDim.new(0, 10)

gui.Parent = player:WaitForChild("PlayerGui")

local state: LoadingGate.Status = {
	gameLoaded = game:IsLoaded(),
	worldReady = false,
	preloaded = 0,
	preloadTotal = 0,
	preloadDone = false,
}
local skipped = false
skip.Activated:Connect(function()
	skipped = true
end)

-- Instances whose content (mesh, texture, image, ColorMap) ContentProvider should fetch now.
local function collect(): { Instance }
	local out: { Instance } = {}
	for _, v in MaterialService:GetDescendants() do
		if v:IsA("MaterialVariant") then
			table.insert(out, v)
		end
	end
	for _, rootName in { "Map", "Plots" } do
		local root = workspace:FindFirstChild(rootName)
		if root then
			for _, d in root:GetDescendants() do
				if d:IsA("MeshPart") or d:IsA("Decal") or d:IsA("Texture") or d:IsA("SurfaceAppearance") then
					table.insert(out, d)
				end
			end
		end
	end
	local playerGui = player:FindFirstChild("PlayerGui")
	if playerGui then
		for _, d in playerGui:GetDescendants() do
			if d:IsA("ImageLabel") or d:IsA("ImageButton") then
				table.insert(out, d)
			end
		end
	end
	return out
end

task.spawn(function()
	if not game:IsLoaded() then
		game.Loaded:Wait()
	end
	state.gameLoaded = true

	-- Shared has replicated once the game is loaded
	local Constants = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Constants")) :: any
	local attribute = Constants.WORLD_MESHES_READY_ATTRIBUTE
	while workspace:GetAttribute(attribute) ~= true and not skipped do
		task.wait(0.1)
	end
	state.worldReady = true

	local items = collect()
	state.preloadTotal = #items
	for i = 1, #items, BATCH do
		if skipped then
			break
		end
		local batch = table.move(items, i, math.min(i + BATCH - 1, #items), 1, {})
		pcall(ContentProvider.PreloadAsync, ContentProvider, batch)
		state.preloaded = math.min(i + BATCH - 1, #items)
	end
	state.preloadDone = true
end)

local started = os.clock()
while true do
	local view = LoadingGate.step(state, os.clock() - started)
	fill.Size = UDim2.fromScale(view.progress, 1)
	status.Text = view.label
	skip.Visible = view.canSkip
	if view.lift or skipped then
		break
	end
	task.wait(0.1)
end

local info = TweenInfo.new(LOOK.fade)
TweenService:Create(bg, info, { BackgroundTransparency = 1 }):Play()
for _, d in bg:GetDescendants() do
	if d:IsA("TextLabel") or d:IsA("TextButton") then
		TweenService:Create(d, info, { TextTransparency = 1, BackgroundTransparency = 1 }):Play()
	elseif d:IsA("Frame") then
		TweenService:Create(d, info, { BackgroundTransparency = 1 }):Play()
	end
end
task.wait(LOOK.fade)
gui:Destroy()
