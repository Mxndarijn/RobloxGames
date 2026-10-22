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
	LoadingScreen draws it; this script only wires it to LoadingGate.
]]

local ContentProvider = game:GetService("ContentProvider")
local MaterialService = game:GetService("MaterialService")
local Players = game:GetService("Players")
local ReplicatedFirst = game:GetService("ReplicatedFirst")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local LoadingGate = require(script:WaitForChild("LoadingGate"))
local LoadingScreen = require(script:WaitForChild("LoadingScreen"))

local BATCH = 40 -- assets per PreloadAsync call: keeps the bar moving

ReplicatedFirst:RemoveDefaultLoadingScreen()

local player = Players.LocalPlayer
local screen = LoadingScreen.build()
screen.setStatus(LoadingGate.LABELS.place)
local camera = workspace.CurrentCamera
screen.layout(if camera then camera.ViewportSize.Y else 720)
screen.gui.Parent = player:WaitForChild("PlayerGui")

local state: LoadingGate.Status = {
	gameLoaded = game:IsLoaded(),
	worldReady = false,
	preloaded = 0,
	preloadTotal = 0,
	preloadDone = false,
}
local skipped = false
screen.skip.Activated:Connect(function()
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
	screen.setProgress(view.progress)
	screen.setStatus(view.label)
	screen.setSkip(view.canSkip)
	screen.layout(screen.gui.AbsoluteSize.Y)
	if view.lift or skipped then
		break
	end
	task.wait(0.1)
end

screen.fade(TweenService)
task.wait(LoadingScreen.FADE)
screen.gui:Destroy()
