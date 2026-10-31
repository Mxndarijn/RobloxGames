--!strict
--[[
	PodiumRigs: the Roblox adapter for PodiumAvatars. Builds R15 rigs from
	HumanoidDescriptions and stands them on workspace Podium_<rank> parts
	(the plaza mesh slots), root-anchored, non-colliding, facing the fountain like
	the podium. Rigs live in workspace.PodiumAvatars.

	The name and total earned sit on the podium itself: a barn-red trophy plate with a brass rim on the front
	(name in butter, the stat in white under it) and a brass rank medallion over it, where the mesh has its star.
	The plate covers the modelled rank numeral. Plates live in workspace.PodiumPlates; WorldLayout.podiumPlate
	places them.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local GooBoard = require(ReplicatedStorage.Shared.GooBoard)
local GooPalette = require(ReplicatedStorage.Shared.GooPalette)
local PodiumAvatars = require(script.Parent.PodiumAvatars)
local WorldLayout = require(ReplicatedStorage.Visuals.WorldLayout)

local PodiumRigs = {}

local FOLDER = "PodiumAvatars"
local PLATES = "PodiumPlates"

local function folder(name: string): Folder
	local existing = workspace:FindFirstChild(name)
	if existing and existing:IsA("Folder") then
		return existing
	end
	local made = Instance.new("Folder")
	made.Name = name
	made.Parent = workspace
	return made
end

local function podium(rank: number): BasePart?
	local part = workspace:FindFirstChild(`Podium_{rank}`, true)
	return if part and part:IsA("BasePart") then part else nil
end

-- The plate's look. A SurfaceGui is studs-sized: its text shrinks with distance like the podium does (world-labels
-- guide), so it hides past `maxDistance`, where the text is too small to read anyway. Text boxes are fractions of
-- the plate; `rim` is the brass border in canvas pixels at `pixelsPerStud`.
PodiumRigs.PLATE = table.freeze({
	pixelsPerStud = 100,
	maxDistance = 60,
	lightInfluence = 0.4,
	rim = 12,
	name = table.freeze({ x = 0.06, y = 0.1, w = 0.88, h = 0.42, outline = 4 }),
	value = table.freeze({ x = 0.15, y = 0.56, w = 0.7, h = 0.32, outline = 4 }),
	rank = table.freeze({ x = 0.2, y = 0.15, w = 0.6, h = 0.7 }),
	ring = 0.9, -- the Ink ring's size, a fraction of the medallion
	rankStroke = 6,
})

local DEPS: GooBoard.Deps = { Instance = Instance, Enum = Enum, UDim = UDim, UDim2 = UDim2, Color3 = Color3 }

local function rgb(c: { number }): Color3
	return Color3.fromRGB(c[1], c[2], c[3])
end

-- An anchored decor part on a podium: no collisions, queries or touches (the podium mesh already collides).
local function decorPart(name: string, color: { number }, parent: Instance): Part
	local part = Instance.new("Part")
	part.Name = name
	part.Anchored = true
	part.CanCollide = false
	part.CanQuery = false
	part.CanTouch = false
	part.Material = Enum.Material.SmoothPlastic
	part.Color = rgb(color)
	part.TopSurface = Enum.SurfaceType.Smooth
	part.BottomSurface = Enum.SurfaceType.Smooth
	part.Parent = parent
	return part
end

local function surface(part: BasePart, face: Enum.NormalId): SurfaceGui
	local look = PodiumRigs.PLATE
	local gui = Instance.new("SurfaceGui")
	gui.Name = "Face"
	gui.Face = face
	gui.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
	gui.PixelsPerStud = look.pixelsPerStud
	gui.MaxDistance = look.maxDistance
	gui.LightInfluence = look.lightInfluence
	gui.Parent = part
	return gui
end

local function place(label: GuiObject, box: { x: number, y: number, w: number, h: number })
	label.Position = UDim2.fromScale(box.x, box.y)
	label.Size = UDim2.fromScale(box.w, box.h)
end

-- Builds podium `rank`'s plate and medallion once (returns the plate's text canvas), or nil without the podium.
local function plate(rank: number): Instance?
	local plates = folder(PLATES)
	local model = plates:FindFirstChild(`PodiumPlate_{rank}`)
	if model then
		return model:FindFirstChild("Plate", true)
	end
	local base = podium(rank)
	local boxes = base and WorldLayout.podiumPlate(rank, base.Size.X, base.Size.Y, base.Size.Z)
	if not (base and boxes) then
		return nil
	end
	local look = PodiumRigs.PLATE
	local made = Instance.new("Model")
	made.Name = `PodiumPlate_{rank}`

	-- the plate: a red board whose front (its -Z face) is turned to the slot's +Z, the podium front
	local p = boxes.plate
	local board = decorPart("Plate", GooPalette.PodiumRed, made)
	board.Size = Vector3.new(p.w, p.h, p.d)
	board.CFrame = base.CFrame * CFrame.new(p.x, p.y, p.z) * CFrame.Angles(0, math.pi, 0)
	local canvas = surface(board, Enum.NormalId.Front)
	local rim = Instance.new("Frame")
	rim.Name = "Rim"
	rim.BackgroundTransparency = 1
	rim.Size = UDim2.fromScale(1, 1)
	rim.Parent = canvas
	local stroke = Instance.new("UIStroke")
	stroke.Color = rgb(GooPalette.Brass)
	stroke.Thickness = look.rim
	stroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	stroke.Parent = rim
	place(GooBoard.text(canvas, DEPS, "Name", GooPalette.Butter, look.name.outline), look.name)
	place(GooBoard.text(canvas, DEPS, "Value", GooPalette.White, look.value.outline), look.value)

	-- the medallion: a brass disc (a cylinder's axis is its X; a -90 degree turn points it out of the front), the rank on
	-- its +X end in Ink
	local m = boxes.medal
	local medal = decorPart("Medal", GooPalette.Brass, made)
	medal.Shape = Enum.PartType.Cylinder
	medal.Size = Vector3.new(m.d, m.h, m.w)
	medal.CFrame = base.CFrame * CFrame.new(m.x, m.y, m.z) * CFrame.Angles(0, -math.pi / 2, 0)
	local face = surface(medal, Enum.NormalId.Right)
	local ring = Instance.new("Frame") -- an Ink ring just inside the disc's edge
	ring.Name = "Ring"
	ring.BackgroundTransparency = 1
	ring.AnchorPoint = Vector2.new(0.5, 0.5)
	ring.Position = UDim2.fromScale(0.5, 0.5)
	ring.Size = UDim2.fromScale(look.ring, look.ring)
	ring.Parent = face
	local round = Instance.new("UICorner")
	round.CornerRadius = UDim.new(0.5, 0)
	round.Parent = ring
	local ringStroke = Instance.new("UIStroke")
	ringStroke.Color = rgb(GooPalette.Ink)
	ringStroke.Thickness = look.rankStroke
	ringStroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	ringStroke.Parent = ring
	local number = GooBoard.text(face, DEPS, "Rank", GooPalette.Ink)
	number.Text = tostring(rank)
	place(number, look.rank)

	made.Parent = plates
	return board
end

-- Writes `text` ("name\nstat") on podium `rank`'s plate; an empty text (empty podium) leaves a blank plate.
local function label(rank: number, text: string)
	local board = plate(rank)
	local canvas = board and board:FindFirstChild("Face")
	if not canvas then
		return
	end
	local name, value = PodiumAvatars.splitLabel(text)
	local nameLabel = canvas:FindFirstChild("Name") :: TextLabel
	local valueLabel = canvas:FindFirstChild("Value") :: TextLabel
	nameLabel.Text = name
	valueLabel.Text = value
end

-- Statue: only the root is anchored, so the Humanoid still builds the scaled R15 joints and layered clothing; no
-- collisions/queries/touches, no default nameplate or scripts.
local function freeze(rig: Model)
	for _, inst in rig:GetDescendants() do
		if inst:IsA("BasePart") then
			inst.Anchored = inst.Name == "HumanoidRootPart"
			inst.CanCollide = false
			inst.CanQuery = false
			inst.CanTouch = false
		elseif inst:IsA("Humanoid") then
			inst.DisplayDistanceType = Enum.HumanoidDisplayDistanceType.None
			inst.HealthDisplayType = Enum.HumanoidHealthDisplayType.AlwaysOff
		elseif inst:IsA("Script") or inst:IsA("LocalScript") then
			inst:Destroy()
		end
	end
end

-- The lowest foot bottom of an R15 rig in world Y, or nil when it has no feet.
local function feetBottom(rig: Model): number?
	local low: number? = nil
	for _, name in { "LeftFoot", "RightFoot" } do
		local foot = rig:FindFirstChild(name)
		if foot and foot:IsA("BasePart") then
			local y = foot.Position.Y - foot.Size.Y / 2
			low = if low then math.min(low, y) else y
		end
	end
	return low
end

-- Grey block stand-in for an empty slot or when every rig call failed.
local function placeholder(): Model
	local rig = Instance.new("Model")
	rig.Name = "PodiumPlaceholder"
	local body = Instance.new("Part")
	body.Name = "Head"
	body.Size = Vector3.new(2, 4, 1)
	body.Color = Color3.fromRGB(150, 150, 160)
	body.Material = Enum.Material.SmoothPlastic
	body.Transparency = 0.5
	body.Parent = rig
	rig.PrimaryPart = body
	return rig
end

function PodiumRigs.adapter(): PodiumAvatars.Adapter
	return {
		fetchDescription = function(userId: number): any
			return Players:GetHumanoidDescriptionFromUserIdAsync(userId)
		end,
		buildRig = function(description: any?): any
			local desc = description or Instance.new("HumanoidDescription")
			return Players:CreateHumanoidModelFromDescriptionAsync(desc, Enum.HumanoidRigType.R15)
		end,
		placeholder = placeholder,
		displayName = function(userId: number, fallback: string): string
			local player = Players:GetPlayerByUserId(userId)
			return if player then player.DisplayName else fallback
		end,
		mount = function(rank: number, rig: any, text: string)
			local model = rig :: Model
			local base = podium(rank)
			if not base then
				model:Destroy()
				return
			end
			label(rank, text) -- the plate first: it shows even when placing the rig fails
			model.Name = `PodiumRig_{rank}`
			-- In the workspace before anchoring/placing, so the rig is scaled and its clothing wrapped first.
			model.Parent = folder(FOLDER)
			freeze(model)
			-- Stand on the middle of the podium's flat top (off the slot's centre: WorldLayout.podiumTopCentre), turned
			-- like its front. The kit front is the slot's +Z (MeshAssets, kit fronts face +Z) and a character looks
			-- along its own -Z, so the rig gets half a turn.
			local dx, dz = WorldLayout.podiumTopCentre(rank, base.Size.X, base.Size.Z)
			local top = base.CFrame * CFrame.new(dx, base.Size.Y / 2, dz) * CFrame.Angles(0, math.pi, 0)
			model:PivotTo(top)
			local box, size = model:GetBoundingBox()
			local lift = PodiumAvatars.standLift(top.Position.Y, feetBottom(model), box.Position.Y - size.Y / 2)
			model:PivotTo(top + Vector3.new(0, lift, 0))
		end,
		setLabel = function(rank: number, text: string)
			label(rank, text)
		end,
		destroy = function(rig: any)
			(rig :: Instance):Destroy()
		end,
		delay = function(seconds: number, fn: () -> ())
			task.delay(seconds, fn)
		end,
		warn = function(message: string)
			warn(message)
		end,
	}
end

return PodiumRigs
