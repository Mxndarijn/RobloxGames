--!strict
--[[
	GuideView (adapter, client)

	Leads the local player to a target with:
	  * a ground trail: flat neon chevrons along the route, each snapped to
	    the ground under it and tilted to the surface, scrolling toward the
	    target (layout from GuideTrail)
	  * a pulsing ring on the ground under the target
	  * a bobbing marker over the target with a label and the distance
	  * a Highlight outline on the target
	  * a screen-edge pointer while the target is off screen (GuideEdge)

	The ring, marker, highlight and edge pointer sit on the target; the
	trail leads to a goal next to it. The goal is the `goal` given to
	setTarget, else (with `approach` on) the WorldPosition of a descendant
	Attachment named "GuideGoal", else a free spot on a ring just outside
	the target's footprint, grounded with a raycast and closest to the
	player (GuideRoute). It is picked again when the target changes or its
	pivot moves more than `goalMoved` studs. With `approach` off the goal is
	the ground under the target, pushed out toward the player.

	With `usePathfinding` on, the trail follows a PathfindingService route
	(a path that ends more than a few studs from the goal counts as failed).
	The player's progress along it only moves forward, and a new path is
	computed when there is none, when the player is more than `offRoute`
	studs from the rest of the route, when the goal moved more than
	`goalMoved` studs, or every `routeRefresh` seconds. A failed compute
	keeps the last good route for this target; without one no ground arrows
	show (the rest of the guide does) and it retries after 1, 2, 4 s.
	`straightFallback` draws a straight line instead while there is no
	route; `usePathfinding = false` always draws the straight line. While
	`shouldPath` returns false no path is computed (say, while the player
	is somewhere the target can't be walked to); the last good route, if
	any, stays. Within
	`arriveDistance` studs of the goal the ground arrows fade out.

	Everything is client-only: the parts and the Highlight under one Folder
	"Guide" in workspace, the label (BillboardGui "GuideLabel") and the edge
	pointer (ScreenGui "GuideEdge") in PlayerGui; destroy() removes them all.

	  local guide = GuideView.new(options?)
	  guide:setTarget(target: PVInstance?, label: string?, goal: Vector3?)   -- nil target clears
	  guide:setTrail(trail: GuideTrail.Options?)   -- replaces the trail options
	  guide:setEdgeHidden(hidden)
	  guide:clear()
	  guide:step(dt)        -- called on RenderStepped unless autoStep = false
	  guide:destroy()

	Options (all optional): color, trail (GuideTrail.Options), arrowSize
	(Vector2 width x depth), arrowThickness, arrowTransparency, hover,
	arrowTemplate (a BasePart or Model cloned per arrow, pointing along -Z),
	usePathfinding, routeRefresh (safety refresh, s), offRoute, goalMoved,
	straightFallback, approach, approachDirections, approachMargin,
	arriveDistance, agentParams (a table, or a function returning one,
	called per path compute; merged over DEFAULTS.agentParams), showRing,
	showMarker, showHighlight, showEdgePointer, edgeMargin, getIgnore (extra
	Instances the ground raycast skips), getOrigin (default: local
	HumanoidRootPart), shouldPath (() -> boolean, default: always),
	distanceText (studs -> string?), autoStep,
	playerGui, clearLabels (lift the marker above the target's own enabled
	BillboardGuis, GuideMarker; default off).
]]

local PathfindingService = game:GetService("PathfindingService")
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")

local GuideEdge = if script then require(script.Parent.GuideEdge) else require("./GuideEdge")
local GuideMarker = if script then require(script.Parent.GuideMarker) else require("./GuideMarker")
local GuideRoute = if script then require(script.Parent.GuideRoute) else require("./GuideRoute")
local GuideTrail = if script then require(script.Parent.GuideTrail) else require("./GuideTrail")
local LabelFit = if script then require(script.Parent.Parent.ui.LabelFit) else require("../ui/LabelFit")

export type Options = {
	color: Color3?,
	trail: GuideTrail.Options?,
	arrowSize: Vector2?,
	arrowThickness: number?,
	arrowTransparency: number?,
	hover: number?,
	arrowTemplate: (BasePart | Model)?,
	usePathfinding: boolean?,
	routeRefresh: number?,
	offRoute: number?,
	goalMoved: number?,
	straightFallback: boolean?,
	approach: boolean?,
	approachDirections: number?,
	approachMargin: number?,
	arriveDistance: number?,
	agentParams: ({ [string]: any } | () -> { [string]: any })?,
	showRing: boolean?,
	showMarker: boolean?,
	showHighlight: boolean?,
	showEdgePointer: boolean?,
	edgeMargin: number?,
	getIgnore: (() -> { Instance })?,
	getOrigin: (() -> Vector3?)?,
	shouldPath: (() -> boolean)?,
	distanceText: ((studs: number) -> string?)?,
	autoStep: boolean?,
	playerGui: Instance?,
	clearLabels: boolean?,
}

export type Guide = {
	-- `goal`: where the trail ends (default: picked next to the target); the ring, marker and highlight stay on the target.
	setTarget: (self: Guide, target: PVInstance?, label: string?, goal: Vector3?) -> (),
	-- Replaces the trail options (GuideTrail.Options; nil restores the defaults).
	setTrail: (self: Guide, trail: GuideTrail.Options?) -> (),
	clear: (self: Guide) -> (),
	step: (self: Guide, dt: number) -> (),
	-- Hides the screen-edge pointer while `hidden` (say, while a menu covers the screen); the rest keeps going.
	setEdgeHidden: (self: Guide, hidden: boolean) -> (),
	destroy: (self: Guide) -> (),
}

local GuideView = {}

GuideView.DEFAULTS = table.freeze({
	color = Color3.fromRGB(255, 226, 60),
	arrowSize = Vector2.new(2.4, 1.4),
	arrowThickness = 0.5,
	arrowTransparency = 0.1,
	hover = 0.5, -- above the collision ground: visual floors (CanQuery off) often sit a little higher
	routeRefresh = 5,
	offRoute = 6,
	goalMoved = 6,
	arriveDistance = 10,
	approachDirections = 12,
	approachMargin = 4,
	edgeMargin = 56,
	agentParams = table.freeze({ AgentRadius = 2, AgentHeight = 5, AgentCanJump = true }),
})

local RAY_UP = 8 -- studs above the route point a ground ray starts
local RAY_DOWN = 30
local APPROACH_UP = 3 -- studs above the target's base an approach ray starts (below most roofs and overhangs)
local CLEARANCE = Vector3.new(3, 4.5, 3) -- free space an approach spot needs above the ground
local IGNORE_REFRESH = 1 -- seconds between re-reads of the ignore list
local MARKER_SIZE = Vector2.new(2.4, 1.8)

type Piece = { parts: { BasePart }, offsets: { CFrame }, base: { number }, alpha: number }

local function defaultDistanceText(studs: number): string?
	return if studs >= 20 then `{math.floor(studs + 0.5)}m` else nil
end

local function plain(p: BasePart, color: Color3)
	p.Anchored = true
	p.CanCollide = false
	p.CanQuery = false
	p.CanTouch = false
	p.CastShadow = false
	p.Material = Enum.Material.Neon
	p.Color = color
end

-- Two neon arms forming a chevron in the XZ plane, tip toward -Z.
local function chevronModel(name: string, width: number, depth: number, thickness: number, color: Color3): Model
	local model = Instance.new("Model")
	model.Name = name
	local tip = Vector3.new(0, 0, -depth / 2)
	for _, side in { -1, 1 } do
		local tail = Vector3.new(side * width / 2, 0, depth / 2)
		local arm = Instance.new("Part")
		arm.Name = if side < 0 then "ArmL" else "ArmR"
		plain(arm, color)
		arm.Size = Vector3.new(thickness, 0.12, (tail - tip).Magnitude + thickness * 0.5)
		arm.CFrame = CFrame.lookAt((tip + tail) / 2, tail)
		arm.Parent = model
	end
	model.WorldPivot = CFrame.new()
	return model
end

local function piece(model: Instance, pivot: CFrame): Piece
	local parts, offsets, base = {}, {}, {}
	local all = if model:IsA("BasePart") then { model :: Instance } else {}
	for _, d in model:GetDescendants() do
		table.insert(all, d)
	end
	for _, d in all do
		if d:IsA("BasePart") then
			d.Anchored = true
			d.CanCollide = false
			d.CanQuery = false
			d.CanTouch = false
			table.insert(parts, d)
			table.insert(offsets, pivot:ToObjectSpace(d.CFrame))
			table.insert(base, d.Transparency)
		end
	end
	return { parts = parts, offsets = offsets, base = base, alpha = -1 }
end

local function setAlpha(p: Piece, alpha: number)
	local rounded = math.floor(alpha * 20 + 0.5) / 20
	if rounded == p.alpha then
		return
	end
	p.alpha = rounded
	for i, part in p.parts do
		part.Transparency = 1 - rounded * (1 - p.base[i])
	end
end

local function footprint(target: PVInstance): (CFrame, Vector3)
	if target:IsA("Model") then
		return target:GetBoundingBox()
	elseif target:IsA("BasePart") then
		return target.CFrame, target.Size
	end
	return target:GetPivot(), Vector3.new(4, 4, 4)
end

local function toPoint(v: Vector3): GuideRoute.Point
	return { x = v.X, y = v.Y, z = v.Z }
end

local function toVector(p: GuideRoute.Point): Vector3
	return Vector3.new(p.x, p.y, p.z)
end

local function flatDistance(a: Vector3, b: Vector3): number
	return Vector3.new(a.X - b.X, 0, a.Z - b.Z).Magnitude
end

-- Half extent of an oriented box along a world direction.
local function halfAlong(box: CFrame, size: Vector3, direction: Vector3): number
	return math.abs(box.RightVector:Dot(direction)) * size.X / 2
		+ math.abs(box.UpVector:Dot(direction)) * size.Y / 2
		+ math.abs(box.LookVector:Dot(direction)) * size.Z / 2
end

local function edgePointer(color: Color3): (ScreenGui, Frame, Frame)
	local gui = Instance.new("ScreenGui")
	gui.Name = "GuideEdge"
	gui.ResetOnSpawn = false
	gui.IgnoreGuiInset = true
	gui.DisplayOrder = 5
	gui.Enabled = false
	local pointer = Instance.new("Frame")
	pointer.Name = "Pointer"
	pointer.AnchorPoint = Vector2.new(0.5, 0.5)
	pointer.Size = UDim2.fromOffset(48, 48)
	pointer.BackgroundColor3 = Color3.fromRGB(25, 25, 30)
	pointer.BackgroundTransparency = 0.25
	pointer.Parent = gui
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0.5, 0)
	corner.Parent = pointer
	local stroke = Instance.new("UIStroke")
	stroke.Color = color
	stroke.Thickness = 2
	stroke.Parent = pointer
	local chevron = Instance.new("Frame")
	chevron.Name = "Chevron"
	chevron.BackgroundTransparency = 1
	chevron.Size = UDim2.fromScale(1, 1)
	chevron.Parent = pointer
	for _, side in { -1, 1 } do
		local arm = Instance.new("Frame")
		arm.Name = if side < 0 then "ArmUp" else "ArmDown"
		arm.AnchorPoint = Vector2.new(0.5, 0.5)
		arm.Size = UDim2.fromOffset(18, 5)
		arm.Position = UDim2.new(0.5, 2, 0.5, side * 6)
		arm.Rotation = -side * 45
		arm.BackgroundColor3 = color
		arm.BorderSizePixel = 0
		arm.Parent = chevron
	end
	return gui, pointer, chevron
end

function GuideView.new(options: Options?): Guide
	local o: Options = options or {}
	local D = GuideView.DEFAULTS
	local color = o.color or D.color
	local trailOptions: GuideTrail.Options? = o.trail
	local arrowSize = o.arrowSize or D.arrowSize
	local thickness = o.arrowThickness or D.arrowThickness
	local arrowTransparency = o.arrowTransparency or D.arrowTransparency
	local hover = o.hover or D.hover
	local usePathfinding = o.usePathfinding ~= false
	local shouldPath = o.shouldPath
	local straightFallback = o.straightFallback == true
	local approach = o.approach ~= false
	local arriveDistance = o.arriveDistance or D.arriveDistance
	local edgeMargin = o.edgeMargin or D.edgeMargin
	local distanceText = o.distanceText or defaultDistanceText
	local goalMoved = o.goalMoved or D.goalMoved
	local routeOptions: GuideRoute.Options = {
		directions = o.approachDirections or D.approachDirections,
		margin = o.approachMargin or D.approachMargin,
		offRoute = o.offRoute or D.offRoute,
		goalMoved = goalMoved,
		safetyRefresh = o.routeRefresh or D.routeRefresh,
	}
	local player = Players.LocalPlayer

	local folder = Instance.new("Folder")
	folder.Name = "Guide"

	-- arrow pool, grown to the trail's maxCount
	local arrows: { Piece } = {}
	local function fillPool()
		local maxCount = if trailOptions and trailOptions.maxCount
			then trailOptions.maxCount
			else GuideTrail.DEFAULTS.maxCount
		for i = #arrows + 1, maxCount do
			local model: Instance
			if o.arrowTemplate then
				model = o.arrowTemplate:Clone()
			else
				model = chevronModel(`Arrow_{i}`, arrowSize.X, arrowSize.Y, thickness, color)
				for _, d in model:GetChildren() do
					(d :: BasePart).Transparency = arrowTransparency
				end
			end
			local pivot = if model:IsA("Model") then model:GetPivot() else (model :: BasePart).CFrame
			local p = piece(model, pivot)
			setAlpha(p, 0)
			model.Parent = folder
			arrows[i] = p
		end
	end
	fillPool()

	-- ring under the target
	local ring = Instance.new("Part")
	ring.Name = "Ring"
	ring.Shape = Enum.PartType.Cylinder
	plain(ring, color)
	ring.Transparency = 1
	ring.Parent = folder

	-- marker over the target: a V pointing down, turned to the camera
	local marker = chevronModel("Marker", MARKER_SIZE.X, MARKER_SIZE.Y, thickness, color)
	for _, d in marker:GetChildren() do
		local arm = d :: BasePart
		-- stand the chevron up: tip toward -Y instead of -Z
		arm.CFrame = CFrame.Angles(-math.pi / 2, 0, 0) * arm.CFrame
		arm.Size = Vector3.new(arm.Size.X, thickness, arm.Size.Z)
	end
	local markerPiece = piece(marker, CFrame.new())
	setAlpha(markerPiece, 0)
	marker.Parent = folder
	local anchor = Instance.new("Part")
	anchor.Name = "LabelAnchor"
	anchor.Size = Vector3.new(0.2, 0.2, 0.2)
	anchor.Transparency = 1
	plain(anchor, color)
	anchor.Parent = folder
	local billboard = Instance.new("BillboardGui")
	billboard.Name = "GuideLabel"
	billboard.Adornee = anchor
	billboard.AlwaysOnTop = false -- it floats above the target, so the world rarely covers it
	billboard.LightInfluence = 0
	billboard.Size = UDim2.fromOffset(220, 56)
	billboard.StudsOffsetWorldSpace = Vector3.new(0, 1.8, 0)
	billboard.MaxDistance = 400
	LabelFit.mark(billboard) -- smaller pixels on a phone when the game runs Lib.ui.LabelFitView
	billboard.Enabled = false
	billboard.ResetOnSpawn = false
	local text = Instance.new("TextLabel")
	text.Name = "Text"
	text.BackgroundTransparency = 1
	text.Size = UDim2.fromScale(1, 1)
	text.Font = Enum.Font.FredokaOne
	text.TextSize = 28
	text.RichText = true
	text.TextColor3 = Color3.new(1, 1, 1)
	text.TextStrokeColor3 = Color3.new(0, 0, 0)
	text.TextStrokeTransparency = 0.2
	text.TextYAlignment = Enum.TextYAlignment.Bottom
	text.Parent = billboard

	local highlight = Instance.new("Highlight")
	highlight.Name = "Outline"
	highlight.FillColor = color
	highlight.FillTransparency = 0.8
	highlight.OutlineColor = color
	highlight.DepthMode = Enum.HighlightDepthMode.AlwaysOnTop
	highlight.Enabled = false
	highlight.Parent = folder

	local edgeGui, pointer, pointerChevron = edgePointer(color)
	local playerGui = o.playerGui or (player and player:FindFirstChildOfClass("PlayerGui"))
	if o.showEdgePointer ~= false then
		edgeGui.Parent = playerGui
	end
	billboard.Parent = playerGui -- with the edge pointer; Adornee puts it over the target

	local target: PVInstance? = nil
	local label: string? = nil
	local edgeHidden = false
	local phase = 0
	local clock = 0
	local givenGoal: Vector3? = nil -- the goal passed to setTarget
	local goalAttachment: Attachment? = nil -- the target's "GuideGoal" Attachment (approach)
	local goal: Vector3? = nil -- the picked goal next to the target
	local goalAnchor: Vector3? = nil -- the target's position when `goal` was picked
	local route: { GuideRoute.Point }? = nil -- last good pathfinding route for `target`
	local routeGoal: Vector3? = nil -- the goal `route` was computed for
	local along = 0 -- the player's progress along `route`, in ground-plane studs
	local attemptAt = -math.huge
	local failures = 0
	local computing = false
	local generation = 0 -- bumps on every target change so late routes are dropped
	local rayParams = RaycastParams.new()
	rayParams.FilterType = Enum.RaycastFilterType.Exclude
	rayParams.RespectCanCollide = true
	local overlapParams = OverlapParams.new()
	overlapParams.FilterType = Enum.RaycastFilterType.Exclude
	overlapParams.RespectCanCollide = true
	local ignoreAt = -math.huge
	local ownLabels: { BillboardGui } = {} -- the target's BillboardGuis (clearLabels), re-read with the ignore list
	local destroyed = false
	local connection: RBXScriptConnection? = nil

	local guide = {} :: any

	local function origin(): Vector3?
		if o.getOrigin then
			return o.getOrigin()
		end
		local character = player and player.Character
		local root = character and character:FindFirstChild("HumanoidRootPart")
		return if root and root:IsA("BasePart") then root.Position else nil
	end

	local function refreshIgnore()
		local list: { Instance } = { folder }
		if target then
			table.insert(list, target)
		end
		for _, other in Players:GetPlayers() do
			if other.Character then
				table.insert(list, other.Character)
			end
		end
		if o.getIgnore then
			for _, instance in o.getIgnore() do
				table.insert(list, instance)
			end
		end
		rayParams.FilterDescendantsInstances = list
		overlapParams.FilterDescendantsInstances = list
		ignoreAt = clock
		ownLabels = {}
		local current = target
		local findGoal = approach
			and current ~= nil
			and not (goalAttachment ~= nil and goalAttachment:IsDescendantOf(current))
		if findGoal then
			goalAttachment = nil
		end
		if current and (o.clearLabels or findGoal) then
			for _, d in current:GetDescendants() do
				if o.clearLabels and d:IsA("BillboardGui") then
					table.insert(ownLabels, d)
				elseif findGoal and not goalAttachment and d.Name == "GuideGoal" and d:IsA("Attachment") then
					goalAttachment = d
				end
			end
		end
	end

	-- The target's own labels as GuideMarker reads them: the enabled ones the camera is close enough to draw.
	local function labelsSeenFrom(camera: Camera): { GuideMarker.Label }
		local out: { GuideMarker.Label } = {}
		local eye = camera.CFrame
		for _, gui in ownLabels do
			local adornee = gui.Adornee or gui.Parent
			local at: Vector3? = if adornee and adornee:IsA("Attachment")
				then adornee.WorldPosition
				elseif adornee and adornee:IsA("BasePart") then adornee.Position
				else nil
			if gui.Enabled and gui.Parent and at then
				local spot = at + gui.StudsOffsetWorldSpace
				local depth = (spot - eye.Position):Dot(eye.LookVector)
				if depth > 0 and depth <= gui.MaxDistance then
					table.insert(out, {
						y = spot.Y,
						scaleY = gui.Size.Y.Scale,
						offsetY = gui.Size.Y.Offset,
						sizeOffsetY = gui.SizeOffset.Y,
						pxPerStud = GuideMarker.pxPerStud(camera.ViewportSize.Y, camera.FieldOfView, depth),
					})
				end
			end
		end
		return out
	end

	local function ground(position: Vector3): RaycastResult?
		return workspace:Raycast(position + Vector3.new(0, RAY_UP, 0), Vector3.new(0, -RAY_DOWN, 0), rayParams)
	end

	local function agentParams(): { [string]: any }
		local given: any = o.agentParams
		local extra = if type(given) == "function" then given() else given
		local params = table.clone(D.agentParams) :: { [string]: any }
		if type(extra) == "table" then
			for k, v in extra do
				params[k] = v
			end
		end
		return params
	end

	local function requestRoute(from: Vector3, to: Vector3)
		computing = true
		attemptAt = clock
		local mine = generation
		task.spawn(function()
			local ok, points = pcall(function(): { GuideRoute.Point }?
				local path = PathfindingService:CreatePath(agentParams())
				path:ComputeAsync(from, to)
				if path.Status ~= Enum.PathStatus.Success and path.Status ~= Enum.PathStatus.ClosestNoPath then
					return nil
				end
				local out = {}
				for _, waypoint in path:GetWaypoints() do
					table.insert(out, toPoint(waypoint.Position))
				end
				return out
			end)
			if destroyed or mine ~= generation then
				return
			end
			computing = false
			if ok and points and #points >= 2 and GuideRoute.reaches(points, toPoint(to)) then
				route, routeGoal, along, failures = points, to, 0, 0
			else
				failures += 1
				if not ok then
					warn(`[GuideView] path: {points}`)
				end
			end
		end)
	end

	-- A free spot next to the target, closest to the player; nil when none is found.
	local function approachSpot(box: CFrame, size: Vector3, from: Vector3): Vector3?
		local axis = Vector3.new(box.RightVector.X, 0, box.RightVector.Z)
		if axis.Magnitude < 0.1 then
			axis = Vector3.new(box.LookVector.X, 0, box.LookVector.Z)
		end
		axis = if axis.Magnitude < 0.1 then Vector3.xAxis else axis.Unit
		local other = Vector3.new(-axis.Z, 0, axis.X)
		local baseY = box.Position.Y - halfAlong(box, size, Vector3.yAxis)
		local shape: GuideRoute.Footprint = {
			x = box.Position.X,
			z = box.Position.Z,
			axisX = axis.X,
			axisZ = axis.Z,
			halfA = halfAlong(box, size, axis),
			halfB = halfAlong(box, size, other),
		}
		local spots: { GuideRoute.Point } = {}
		for _, candidate in GuideRoute.approachCandidates(shape, baseY, routeOptions) do
			local hit = workspace:Raycast(
				Vector3.new(candidate.x, baseY + APPROACH_UP, candidate.z),
				Vector3.new(0, -RAY_DOWN, 0),
				rayParams
			)
			if hit then
				local room = CFrame.new(hit.Position + Vector3.new(0, 0.5 + CLEARANCE.Y / 2, 0))
				if #workspace:GetPartBoundsInBox(room, CLEARANCE, overlapParams) == 0 then
					table.insert(spots, toPoint(hit.Position))
				end
			end
		end
		local best = GuideRoute.pickApproach(spots, toPoint(from), baseY, routeOptions)
		return if best then toVector(best) else nil
	end

	-- The ground under the target, pushed out of its footprint toward the player.
	local function frontSpot(box: CFrame, size: Vector3, from: Vector3): Vector3
		local to = box.Position
		local floor = ground(to)
		local flat = Vector3.new(from.X - to.X, 0, from.Z - to.Z)
		local front = if flat.Magnitude > 0.01 then flat.Unit * (math.max(size.X, size.Z) / 2 + 2) else Vector3.zero
		return (if floor then floor.Position else to) + front
	end

	local function currentGoal(box: CFrame, size: Vector3, from: Vector3): Vector3
		if givenGoal then
			return givenGoal
		end
		if approach and goalAttachment then
			return goalAttachment.WorldPosition
		end
		local picked = goal
		if picked and goalAnchor and (box.Position - goalAnchor).Magnitude <= goalMoved then
			return picked
		end
		local spot = (if approach then approachSpot(box, size, from) else nil) or frontSpot(box, size, from)
		goal, goalAnchor = spot, box.Position
		return spot
	end

	local function hideAll()
		for _, arrow in arrows do
			setAlpha(arrow, 0)
		end
		ring.Transparency = 1
		setAlpha(markerPiece, 0)
		billboard.Enabled = false
		highlight.Enabled = false
		highlight.Adornee = nil
		edgeGui.Enabled = false
		folder.Parent = nil
	end

	function guide.setTarget(_self: Guide, newTarget: PVInstance?, newLabel: string?, newGoal: Vector3?)
		label = newLabel
		if newGoal ~= givenGoal then
			givenGoal = newGoal
			goal, goalAnchor = nil, nil
		end
		if newTarget == target then
			return
		end
		target = newTarget
		generation += 1
		route, routeGoal, along = nil, nil, 0
		goal, goalAnchor, goalAttachment = nil, nil, nil
		attemptAt, failures, computing = -math.huge, 0, false
		if not newTarget then
			hideAll()
			return
		end
		folder.Parent = workspace
		refreshIgnore()
		highlight.Adornee = newTarget
		highlight.Enabled = o.showHighlight ~= false
	end

	function guide.setTrail(_self: Guide, trail: GuideTrail.Options?)
		trailOptions = trail
		fillPool()
	end

	function guide.setEdgeHidden(_self: Guide, hidden: boolean)
		edgeHidden = hidden
		if hidden then
			edgeGui.Enabled = false
		end
	end

	function guide.clear(self: Guide)
		self:setTarget(nil)
	end

	function guide.step(_self: Guide, dt: number)
		clock += dt
		local current = target
		if not current then
			return
		end
		if not current:IsDescendantOf(workspace) then
			guide:setTarget(nil)
			return
		end
		local from = origin()
		if not from then
			for _, arrow in arrows do -- keep the target; the trail comes back with the character
				setAlpha(arrow, 0)
			end
			return
		end
		if clock - ignoreAt >= IGNORE_REFRESH then
			refreshIgnore()
		end
		local boxCFrame, boxSize = footprint(current)
		local to = boxCFrame.Position
		local goalAt = currentGoal(boxCFrame, boxSize, from)

		-- route
		local here = toPoint(from)
		local path: { GuideTrail.Point }? = nil
		if usePathfinding then
			local off, moved = 0, 0
			local known = route
			if known then
				along = GuideRoute.advance(known, here, along, routeOptions)
				off = GuideRoute.offRoute(known, here, along)
				moved = if routeGoal then (goalAt - routeGoal).Magnitude else 0
			end
			local again = GuideRoute.shouldRecompute({
				hasRoute = known ~= nil,
				computing = computing,
				failures = failures,
				sinceAttempt = clock - attemptAt,
				offRoute = off,
				goalMoved = moved,
				paused = shouldPath ~= nil and not shouldPath(),
			}, routeOptions)
			if again then
				requestRoute(from, goalAt)
			end
			if known then
				path = GuideRoute.ahead(known, along, here)
			end
		end
		if not path and (not usePathfinding or straightFallback) then
			path = { here, toPoint(goalAt) }
		end

		-- trail, faded out near the goal
		phase = GuideTrail.advance(phase, dt, trailOptions)
		local layout = if path then GuideTrail.layout(path, phase, trailOptions) else {}
		local arrive = GuideRoute.arrival(flatDistance(from, goalAt), arriveDistance)
		local moveParts: { BasePart } = {}
		local moveFrames: { CFrame } = {}
		for i, arrow in arrows do
			local placed = layout[i]
			local hit = placed and ground(Vector3.new(placed.x, placed.y, placed.z))
			if placed and hit then
				local up = hit.Normal
				local forward = Vector3.new(placed.dirX, 0, placed.dirZ)
				forward = (forward - up * forward:Dot(up)).Unit
				local back = -forward
				local frame = CFrame.fromMatrix(hit.Position + up * hover, up:Cross(back), up, back)
				for k, part in arrow.parts do
					table.insert(moveParts, part)
					table.insert(moveFrames, frame * arrow.offsets[k])
				end
				setAlpha(arrow, placed.alpha * arrive)
			else
				setAlpha(arrow, 0)
			end
		end
		if #moveParts > 0 then
			workspace:BulkMoveTo(moveParts, moveFrames, Enum.BulkMoveMode.FireCFrameChanged)
		end

		-- ring
		if o.showRing ~= false then
			local floor = ground(to)
			local base = if floor then floor.Position else to - Vector3.new(0, boxSize.Y / 2, 0)
			local pulse = 0.5 + 0.5 * math.sin(clock * 3)
			local diameter = (math.max(boxSize.X, boxSize.Z) + 1.5) * (1 + 0.08 * pulse)
			ring.Size = Vector3.new(0.1, diameter, diameter)
			ring.CFrame = CFrame.new(base + Vector3.new(0, hover, 0)) * CFrame.Angles(0, 0, math.pi / 2)
			ring.Transparency = 0.55 + 0.2 * pulse
		end

		-- marker and label
		local camera = workspace.CurrentCamera
		local distance = flatDistance(from, to)
		if o.showMarker ~= false and camera then
			local baseY = to.Y + boxSize.Y / 2
			if o.clearLabels then
				baseY = GuideMarker.top(baseY, labelsSeenFrom(camera), 1)
			end
			local top = Vector3.new(to.X, baseY + 1.6 + 0.3 * math.sin(clock * 4), to.Z)
			local eye = camera.CFrame.Position
			local facing = Vector3.new(eye.X, top.Y, eye.Z)
			local frame = if (facing - top).Magnitude > 0.01 then CFrame.lookAt(top, facing) else CFrame.new(top)
			local parts, frames = {}, {}
			for k, part in markerPiece.parts do
				table.insert(parts, part)
				table.insert(frames, frame * markerPiece.offsets[k])
			end
			workspace:BulkMoveTo(parts, frames, Enum.BulkMoveMode.FireCFrameChanged)
			setAlpha(markerPiece, 1)
			anchor.CFrame = frame
			local extra = distanceText(distance)
			local line = label or ""
			if extra then
				line = if line ~= "" then `{line}\n<font size="20">{extra}</font>` else extra
			end
			text.Text = line
			billboard.Enabled = line ~= ""
		end

		-- screen-edge pointer
		if o.showEdgePointer ~= false and not edgeHidden and camera and edgeGui.Parent then
			local point = camera:WorldToViewportPoint(to)
			local size = camera.ViewportSize
			local placed = GuideEdge.place(point.X, point.Y, point.Z > 0, size.X, size.Y, edgeMargin)
			edgeGui.Enabled = placed.visible
			if placed.visible then
				pointer.Position = UDim2.fromOffset(placed.x, placed.y)
				pointerChevron.Rotation = placed.angle
			end
		end
	end

	function guide.destroy(_self: Guide)
		destroyed = true
		if connection then
			connection:Disconnect()
			connection = nil
		end
		folder:Destroy()
		edgeGui:Destroy()
		billboard:Destroy()
	end

	if o.autoStep ~= false then
		connection = RunService.RenderStepped:Connect(function(dt: number)
			local ok, err = pcall(guide.step, guide, dt)
			if not ok then
				warn(`[GuideView] {err}`)
			end
		end)
	end

	return guide :: Guide
end

return table.freeze(GuideView)
