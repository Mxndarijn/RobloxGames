--!strict
--[[
	SlideTopWatch (Roblox adapter, owner: Phoenix)

	SlideTopWatch.step(character, root, now)

	Bug #9: nobody stays on top of the slide's solid fill. The fill's roof is a steep ridge (server/FountainColliders), and
	this is the backstop: a character whose root is on a fill's roof (Shared.SlideTopGuard.onTop) for SlideTopGuard.DWELL
	seconds is put on the ground just beside the slide (SlideTopGuard.nudge, away from the fountain), velocity cleared.
	Checked at 5 Hz per character, called from WorldView.enforceLocks; behind FEATURES.SlideCollision. Never harms.

	SlideTopWatch.stepStrays(now)

	The same check for every other unanchored Humanoid model directly under Workspace (an NPC or a test dummy,
	not a player character), called from the server's player loop. Without it, a Humanoid dropped exactly on the ridge
	stays balanced there (both faces < 89 degrees, so a Humanoid stands on either): the pc-watcher probe
	bug09_slide_stand / slide_walk cannot_stand_on drops R15 dummies, not players.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)
local SlideColliders = require(ReplicatedStorage.Shared.SlideColliders)
local SlideTopGuard = require(ReplicatedStorage.Shared.SlideTopGuard)
local WorldLayout = require(ReplicatedStorage.Visuals.WorldLayout)

local SlideTopWatch = {}

SlideTopWatch.GROUND_Y = 0 -- nominal plaza ground under the slide

local fills: { SlideColliders.Spec }? = nil
local cx, cz = 0, 0
local state: { [Model]: { last: number, since: number? } } = setmetatable({}, { __mode = "k" }) :: any

local function load(): { SlideColliders.Spec }
	if not fills then
		local list = {}
		local sx, sz = 0, 0
		for _, spec in SlideColliders.build(WorldLayout.SLIDE_PATH, true) do
			if spec.kind == "Fill" then
				table.insert(list, spec)
				sx += spec.centre[1]
				sz += spec.centre[3]
			end
		end
		cx, cz = sx / math.max(#list, 1), sz / math.max(#list, 1)
		fills = list
	end
	return fills :: { SlideColliders.Spec }
end

-- True when the character was moved.
function SlideTopWatch.step(character: Model, root: BasePart, now: number): boolean
	if not Config.FEATURES.SlideCollision then
		return false
	end
	local s = state[character]
	if not s then
		s = { last = -math.huge, since = nil }
		state[character] = s
	end
	if now - s.last < SlideTopGuard.INTERVAL then
		return false
	end
	s.last = now
	local specs = load()
	local p = root.Position
	local spec = SlideTopGuard.onTop(specs, p.X, p.Y, p.Z, SlideTopWatch.GROUND_Y)
	if not spec then
		s.since = nil
		return false
	end
	if not s.since then
		s.since = now
		return false
	end
	if now - s.since < SlideTopGuard.DWELL then
		return false
	end
	s.since = nil
	local x, z = SlideTopGuard.nudge(specs, spec, p.X, p.Z, cx, cz)
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = { character }
	local hit = workspace:Raycast(Vector3.new(x, p.Y + 2, z), Vector3.new(0, -(p.Y + 2 + 50), 0), params)
	if not hit then
		return false -- no ground there: leave it, the next check tries again
	end
	character:PivotTo(CFrame.new(x, hit.Position.Y + 4, z))
	root.AssemblyLinearVelocity = Vector3.zero
	return true
end

-- Non-player Humanoid models directly under Workspace, tracked by ChildAdded (no per-tick scan of the map).
local strays: { [Model]: true } = setmetatable({}, { __mode = "k" }) :: any
local watching = false

local function consider(inst: Instance)
	if inst:IsA("Model") and inst:FindFirstChildOfClass("Humanoid") then
		strays[inst] = true
	end
end

local function watch()
	if watching then
		return
	end
	watching = true
	for _, child in workspace:GetChildren() do
		consider(child)
	end
	workspace.ChildAdded:Connect(function(child)
		consider(child)
		-- a dummy is often parented before its Humanoid is: look again once it is built
		task.defer(consider, child)
	end)
end

-- Number of models moved.
function SlideTopWatch.stepStrays(now: number): number
	if not Config.FEATURES.SlideCollision then
		return 0
	end
	watch()
	local moved = 0
	for model in strays do
		if model.Parent ~= workspace then
			strays[model] = nil
			continue
		end
		if Players:GetPlayerFromCharacter(model) then
			continue -- players go through WorldView.enforceLocks
		end
		local root = model:FindFirstChild("HumanoidRootPart")
		if root and root:IsA("BasePart") and not root.Anchored then
			if SlideTopWatch.step(model, root, now) then
				moved += 1
			end
		end
	end
	return moved
end

return SlideTopWatch
