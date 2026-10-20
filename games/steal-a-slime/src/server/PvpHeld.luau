--!strict
--[[
	PvpHeld (Roblox adapter, FEATURES.PvP, CONTRACT.md §26.3)

	The equipped PvP item in the character's right hand: one Model `PvpModels.MODEL_NAME` under the character,
	each part welded to the hand. The look comes from Shared.PvpModels only: the uploaded mesh (one MeshPart from
	AssetService:CreateMeshPartAsync, cached per mesh id, fitted into the item's `size` x `held`) welded at
	RightGripAttachment * grip^-1 (Tool.Grip convention, grip.pos scaled with `held`), or, while there is none or it
	failed, the placeholder pieces on the bare RightGripAttachment.
	Every part is collision-free, Massless, CanQuery / CanTouch false and casts no shadow.

	`PvpHeld.sync(character, itemId)` is called from the per-player WorldView.updatePlayer tick: it builds, swaps
	or removes the model so the character shows exactly `itemId` (nil = nothing). No loop of its own.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local MeshAssets = require(ReplicatedStorage.Shared.MeshAssets)
local PvpModels = require(ReplicatedStorage.Shared.PvpModels)

local PvpHeld = {}

local templates: { [string]: any } = {} -- mesh id -> loaded MeshPart template
local loading: { [string]: boolean } = {} -- mesh id -> a CreateMeshPartAsync is running or failed

local function cframeOf(pos: { number }, rotDeg: { number }?): CFrame
	local r = rotDeg or { 0, 0, 0 }
	return CFrame.new(pos[1], pos[2], pos[3]) * CFrame.Angles(math.rad(r[1]), math.rad(r[2]), math.rad(r[3]))
end

-- Roblox's Cylinder runs along X; `axis` turns it to the item's Y or Z.
local AXIS_TURN: { [string]: CFrame } = {
	X = CFrame.new(),
	Y = CFrame.Angles(0, 0, math.rad(90)),
	Z = CFrame.Angles(0, math.rad(90), 0),
}

local function quiet(part: BasePart)
	part.Anchored = false
	part.CanCollide = false
	part.CanQuery = false
	part.CanTouch = false
	part.Massless = true
	part.CastShadow = false
end

local function weld(part: BasePart, hand: BasePart, c0: CFrame)
	local w = Instance.new("Weld")
	w.Part0 = hand
	w.Part1 = part
	w.C0 = c0
	w.Parent = part
end

local function placeholder(item: PvpModels.Item, hand: BasePart, base: CFrame, model: Model)
	for i, piece in item.pieces do
		local part = Instance.new("Part")
		part.Name = `Piece{i}`
		local size = piece.size
		local turn = CFrame.new()
		if piece.shape == "Ball" then
			part.Shape = Enum.PartType.Ball
		elseif piece.shape == "Cylinder" then
			part.Shape = Enum.PartType.Cylinder
			local axis = piece.axis or "Y"
			turn = AXIS_TURN[axis]
			-- a Cylinder's size is { diameter, length, diameter }; the Part's own length axis is X
			local length, across = size[2], size[1]
			size = { length, across, across }
		end
		part.Size = Vector3.new(size[1], size[2], size[3])
		part.Color = Color3.fromRGB(piece.color[1], piece.color[2], piece.color[3])
		local material = (Enum.Material :: any)[piece.material or "SmoothPlastic"]
		part.Material = material or Enum.Material.SmoothPlastic
		part.Transparency = piece.transparency or 0
		quiet(part)
		weld(part, hand, base * cframeOf(piece.pos, piece.rotDeg) * turn)
		part.Parent = model
	end
end

-- The cached template for `meshId`, or nil (then a load starts in the background; the next sync swaps it in).
local function template(meshId: string): any
	local t = templates[meshId]
	if t or loading[meshId] then
		return t
	end
	loading[meshId] = true
	task.spawn(function()
		local ok, mesh = pcall(function()
			return (game:GetService("AssetService") :: any):CreateMeshPartAsync(meshId, {
				CollisionFidelity = Enum.CollisionFidelity.Box,
				RenderFidelity = Enum.RenderFidelity.Automatic,
			})
		end)
		if ok and mesh then
			templates[meshId] = mesh
		end
	end)
	return nil
end

local function handOf(character: Model): BasePart?
	local hand = character:FindFirstChild("RightHand") or character:FindFirstChild("Right Arm")
	return if hand and hand:IsA("BasePart") then hand else nil
end

-- The hand-space CFrame of the grip point: RightGripAttachment (else the palm).
local function gripPointOf(hand: BasePart): CFrame
	local attachment = hand:FindFirstChild("RightGripAttachment")
	return if attachment and attachment:IsA("Attachment")
		then attachment.CFrame
		else CFrame.new(0, -hand.Size.Y / 2, 0) * CFrame.Angles(math.rad(-90), 0, 0)
end

-- The hand-space CFrame of the model origin: grip point * grip^-1 (PvpModels.mount: mesh or placeholder).
local function baseOf(item: PvpModels.Item, hand: BasePart, mesh: boolean, scale: number?): CFrame
	local grip = PvpModels.mount(item, mesh, scale)
	return gripPointOf(hand) * cframeOf(grip.pos, grip.rotDeg):Inverse()
end

local function build(character: Model, itemId: string, item: PvpModels.Item, hand: BasePart): Model
	local model = Instance.new("Model")
	model.Name = PvpModels.MODEL_NAME
	model:SetAttribute(PvpModels.ITEM_ATTRIBUTE, itemId)
	local meshId = PvpModels.meshId(itemId)
	local mesh = if meshId then template(meshId) else nil
	if mesh then
		local part = mesh:Clone()
		part.Name = "Mesh"
		local held = item.held or 1
		local box = { item.size[1] * held, item.size[2] * held, item.size[3] * held }
		local size, scale = MeshAssets.fit(item.mesh, box) -- one uniform scale, never stretched
		part.Size = Vector3.new(size[1], size[2], size[3])
		quiet(part)
		weld(part, hand, baseOf(item, hand, true, scale or held))
		part.Parent = model
		model:SetAttribute(PvpModels.MESH_ATTRIBUTE, true)
	else
		placeholder(item, hand, baseOf(item, hand, false), model)
	end
	model.Parent = character
	return model
end

-- Makes `character` hold exactly `itemId` (nil = nothing). Cheap when nothing changed.
function PvpHeld.sync(character: Model?, itemId: string?)
	if not character then
		return
	end
	local current = character:FindFirstChild(PvpModels.MODEL_NAME)
	local item = PvpModels.get(itemId)
	local hand = handOf(character)
	if current then
		local same = current:GetAttribute(PvpModels.ITEM_ATTRIBUTE) == itemId
		local meshId = PvpModels.meshId(itemId)
		local upgrade = same
			and meshId ~= nil
			and current:GetAttribute(PvpModels.MESH_ATTRIBUTE) ~= true
			and templates[meshId] ~= nil
		if same and item and hand and not upgrade then
			return
		end
		current:Destroy()
	end
	if itemId and item and hand then
		build(character, itemId, item, hand)
	end
end

return PvpHeld
