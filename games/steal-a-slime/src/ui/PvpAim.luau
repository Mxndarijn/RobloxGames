--!strict
--[[
	PvpAim: what a click / tap on the world points at, for the equipped PvP item (InventoryCore.Aim). Roblox
	adapter only: one camera ray through the screen point (the local character excluded), the player whose
	character it hit, and every other player's root. InventoryCore.pvpUseRequest turns it into the request.
]]

local Players = game:GetService("Players")

local PvpAim = {}

PvpAim.RAY_LENGTH = 500 -- studs from the camera
PvpAim.FAR = 200 -- studs along the ray for `far` (an aimed shot at the sky)

local function rootOf(character: Model?): BasePart?
	local root = if character then character:FindFirstChild("HumanoidRootPart") else nil
	return if root and root:IsA("BasePart") then root else nil
end

-- `screen` = the input position in screen pixels (InputObject.Position / a TouchTap position).
function PvpAim.sample(screen: Vector2 | Vector3, carryingAttribute: string): any
	local player = Players.LocalPlayer
	local myRoot = rootOf(player.Character)
	local others = {}
	for _, other in Players:GetPlayers() do
		local root = if other ~= player then rootOf(other.Character) else nil
		if root then
			table.insert(others, {
				userId = other.UserId,
				position = root.Position,
				carrying = other:GetAttribute(carryingAttribute) ~= nil,
			})
		end
	end
	local aim: any = { self = if myRoot then myRoot.Position else nil, players = others }
	local camera = workspace.CurrentCamera
	if not camera then
		return aim
	end
	local ray = camera:ScreenPointToRay(screen.X, screen.Y)
	aim.far = ray.Origin + ray.Direction * PvpAim.FAR
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = if player.Character then { player.Character } else {}
	local hit = workspace:Raycast(ray.Origin, ray.Direction * PvpAim.RAY_LENGTH, params)
	if hit then
		aim.point = hit.Position
		local model = hit.Instance:FindFirstAncestorOfClass("Model")
		while model do
			local owner = Players:GetPlayerFromCharacter(model)
			if owner then
				aim.hovered = owner.UserId
				break
			end
			model = model:FindFirstAncestorOfClass("Model")
		end
	end
	return aim
end

return PvpAim
