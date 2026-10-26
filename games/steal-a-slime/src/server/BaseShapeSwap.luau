--!strict
--[[
	BaseShapeSwap (Roblox adapter, owner: Phoenix)

	Turns a plot from one base into another (CONTRACT.md §44) when its PlotBase changes: floor 1 is static as the goo
	jar tower, so another base is built over it at runtime, and the jar is built back the same way. In order:
	1. everyone inside the old base's walls is set down on its spawn spot (nobody stays inside walls that move);
	   people outside them (the bridge, the moat, the yard) are left where they are, so a swap never moves anyone in;
	2. the upper floors and the roof colliders go (BaseFloors.clear: prompts parked, people set down);
	3. the old base's own floor-1 pieces are destroyed (only the names of its BaseShapes.floor1 nodes that no base
	   keeps, so nothing else under the plot is touched);
	4. the new base's floor-1 nodes are built: kept parts (pads 1..8, MergeVat, LockButton, ButtonLook, Bridge,
	   LockBarrier) keep their instance, prompts, meshes and client hooks and are fitted to their new node
	   (WorldBuilder.conform), the rest is created (WorldBuilder.ensure) and gets its kit meshes (MeshSwap.applyUnder).
	The caller sets the plot's PlotBase attribute and re-places the pad slimes; BaseFloors.sync then builds the new
	base's upper floors. Holds no gameplay rules.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local BaseFloors = require(script.Parent.BaseFloors)
local BaseShapes = require(ReplicatedStorage.Visuals.BaseShapes)
local Config = require(ReplicatedStorage.Shared.Config)
local Constants = require(ReplicatedStorage.Shared.Constants)
local MeshSwap = require(script.Parent.MeshSwap)
local WorldBuilder = require(ReplicatedStorage.Visuals.WorldBuilder)
local WorldLayout = require(ReplicatedStorage.Visuals.WorldLayout)

local BaseShapeSwap = {}

-- Whether plot-local (x, y, z) is inside base `old`'s walls (y on the floorTop scale): on the floor its height is
-- at, one stud of slack past the walls (BaseFloors' evacuate does the same).
function BaseShapeSwap.insideOld(old: string?, x: number, y: number, z: number): boolean
	local shape = BaseShapes.get(old)
	local floor = 0
	for f = 1, #Config.BASE_FLOORS do
		if y >= WorldLayout.floorTop(f) - 1 then
			floor = f
		end
	end
	return floor > 0 and shape.inside(floor, x, z, 1)
end

local function setDown(plot: Instance, old: string?, moved: ((userId: number) -> ())?)
	local base = plot:FindFirstChild("Base")
	if not (base and base:IsA("BasePart")) then
		return
	end
	local spot = WorldLayout.SPAWN_SPOT
	local landing = base.CFrame * CFrame.new(spot[1], base.Size.Y / 2 + 4, spot[2])
	for _, player in Players:GetPlayers() do
		local character = player.Character
		local root = character and character:FindFirstChild("HumanoidRootPart")
		if character and root and root:IsA("BasePart") then
			local p = base.CFrame:PointToObjectSpace(root.Position)
			local y = p.Y - base.Size.Y / 2 + WorldLayout.PLOT_FLOOR_TOP
			if BaseShapeSwap.insideOld(old, p.X, y, p.Z) then
				character:PivotTo(landing)
				root.AssemblyLinearVelocity = Vector3.zero
				if moved then
					moved(player.UserId) -- a server move, not a teleport (SlimeGuard)
				end
			end
		end
	end
end

-- Turns plot `plotIndex` from base `from` (nil = the plot's PlotBase) into base `to`. `moved(userId)` is told about
-- each character set down (WorldView.markServerMove). Yields only inside the mesh thread.
function BaseShapeSwap.swap(
	plot: Instance,
	plotIndex: number,
	to: string,
	from: string?,
	moved: ((userId: number) -> ())?
)
	local old = from or plot:GetAttribute(Constants.PLOT_BASE_ATTRIBUTE)
	setDown(plot, if type(old) == "string" then old else nil, moved)
	BaseFloors.clear(plot)
	local created = WorldBuilder.rebase(plot, plotIndex, if type(old) == "string" then old else nil, to)
	if #created > 0 then
		task.spawn(MeshSwap.applyUnder, created)
	end
end

return BaseShapeSwap
