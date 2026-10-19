--!strict
--[[
	ServerContext (Roblox adapter)

	Builds the one `ctx` (Actions.Context, which carries PvpService.Context) the server entry hands to Actions,
	the PvP lines, BatTool.swing and WorldView.updatePlayer: world queries measured fresh from the characters
	(distances, positions, shop and plot-prompt access, home-zone tests, the Bat's pose), the PvP launch and the
	ShopEvent sender. Hat Launcher friends (`areFriends`) and the Weather Totem (`requestWeather`) are added by
	the entry once those services exist.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Actions = require(script.Parent.Actions)
local PlotPadGuard = require(script.Parent.PlotPadGuard)
local PvpLaunch = require(script.Parent.PvpLaunch)
local Rng = require(ReplicatedStorage.Shared.Rng)
local ShopGuard = require(script.Parent.ShopGuard)
local World = require(script.Parent.World)
local WorldProps = require(script.Parent.WorldProps)
local WorldView = require(script.Parent.WorldView)

local ServerContext = {}

ServerContext.GROUND_PROBE = 60 -- studs: how far below a Goo Blaster blob's end its splat looks for the ground

local function rootOf(userId: number): BasePart?
	return WorldView.rootPart(Players:GetPlayerByUserId(userId))
end

local function alive(player: Player?): boolean
	local character = player and player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	return humanoid ~= nil and humanoid.Health > 0
end

-- Distance from `userId`'s root to `part` and whether the character is alive; distance nil = no root or no part.
local function access(userId: number, part: BasePart?): { distance: number?, alive: boolean }
	local player = Players:GetPlayerByUserId(userId)
	local root = WorldView.rootPart(player)
	if not root or not part then
		return { distance = nil, alive = alive(player) }
	end
	return { distance = (root.Position - part.Position).Magnitude, alive = alive(player) }
end

function ServerContext.new(world: World.World, shopEvent: RemoteEvent, now: () -> number): Actions.Context
	return {
		distanceBetween = function(a: number, b: number): number
			local ra, rb = rootOf(a), rootOf(b)
			if not ra or not rb then
				return math.huge
			end
			return (ra.Position - rb.Position).Magnitude
		end,
		positionOf = function(userId: number): Vector3?
			local root = rootOf(userId)
			return root and root.Position
		end,
		-- World shops (CONTRACT.md §27): distance to the stand's Counter, measured for every OpenShop / purchase.
		shopAccess = function(userId: number, shopId: string): ShopGuard.Access
			return access(userId, WorldProps.shopCounter(shopId))
		end,
		-- Owner-only plot prompts: distance to the part the owner's prompt `kind` sits on (their own plot).
		plotPadAccess = function(userId: number, kind: string): PlotPadGuard.Access
			local session = World.session(world, userId)
			local part = session and session.plotIndex and WorldView.plotPromptPart(session.plotIndex, kind)
			return access(userId, part or nil)
		end,
		shopEvent = function(userId: number, payload: { [string]: any })
			local player = Players:GetPlayerByUserId(userId)
			if player then
				payload.serverTime = now()
				shopEvent:FireClient(player, payload)
			end
		end,
		rng = Rng.new(Random.new():NextInteger(1, 2147483646)),
		onOwnPlot = function(session: World.Session, userId: number): boolean
			local player = Players:GetPlayerByUserId(userId)
			return player ~= nil and WorldView.inHomeZone(player, session.plotIndex)
		end,
		pointOnOwnPlot = function(session: World.Session, point): boolean
			return WorldView.pointInHomeZone(Vector3.new(point.X, point.Y, point.Z), session.plotIndex)
		end,
		-- Knockback gloves, Fun items and the Bat: the server only launches; the look is client FX from PvpEvent.
		launch = function(userId: number, push, _landing): boolean
			return PvpLaunch.launch(userId, push, now())
		end,
		pose = function(userId: number)
			local root = rootOf(userId)
			if not root then
				return nil, nil
			end
			local look = root.CFrame.LookVector
			local p = root.Position
			return { X = p.X, Y = p.Y, Z = p.Z }, { X = look.X, Y = 0, Z = look.Z }
		end,
		toVector3 = function(position)
			return Vector3.new(position.X, position.Y, position.Z)
		end,
		slimePosition = function(slimeId: string)
			local p = WorldView.slimePosition(slimeId)
			return p and { X = p.X, Y = p.Y, Z = p.Z }
		end,
		-- Goo Blaster splats: the first solid surface up to GROUND_PROBE studs below the blob's end (characters ignored).
		groundBelow = function(point)
			local params = RaycastParams.new()
			params.FilterType = Enum.RaycastFilterType.Exclude
			local characters = {}
			for _, player in Players:GetPlayers() do
				if player.Character then
					table.insert(characters, player.Character)
				end
			end
			params.FilterDescendantsInstances = characters
			local origin = Vector3.new(point.X, point.Y + 1, point.Z)
			local hit = workspace:Raycast(origin, Vector3.new(0, -ServerContext.GROUND_PROBE, 0), params)
			return hit and { X = hit.Position.X, Y = hit.Position.Y, Z = hit.Position.Z }
		end,
	}
end

return ServerContext
