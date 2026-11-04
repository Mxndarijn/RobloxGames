--!strict
--[[
	ShopPreview

	What the Exclusive shop's stage shows for the selected item (docs/shop-preview-proposal.html, option A): the
	item's real 3D model turning on the turntable instead of its icon, or a bundle's items side by side.

	  * `of(detail, config)` (pure): the preview for an ExclusiveShopView.Detail, or nil to keep the icon.
	    Clouds carry a slime at their seat height, hats sit on a slime the way SlimeHatsFx fits them on a pad,
	    lock stoppers, Bat skins and base-skin decor turn on their own. Plot bases (whole buildings), trails
	    (particles, which a ViewportFrame can't draw), passes and boosts keep their icon.
	  * `new(stage, ctx)` (Roblox): a ViewportFrame and an item row over the stage. `set(preview)` swaps what
	    it shows (the mesh loads in its own thread; `ctx.onShown(true)` once it is up, so the panel hides the
	    icon medal under it), `tick(now)` turns the model, `setActive(false)` drops it while the shop is shut.

	Models are clones of the templates the server publishes in ReplicatedStorage (seats, hats, skin decor), the
	same parts the world uses, so the preview looks like the item in game. Meshes without a published template
	(lock stoppers, Bat skins) load once per client through `ctx.loadMesh`.
]]

local SlimeHatsFx = if script then require(script.Parent.SlimeHatsFx) else require("./SlimeHatsFx")

export type Pose = "seat" | "hat" | "stopper" | "bat" | "decor"

export type Preview = {
	key: string, -- what is shown; a new key rebuilds the stage
	kind: "model" | "items",
	mesh: string?, -- kind "model": MeshAssets name
	folder: string?, -- ReplicatedStorage folder of the template, nil = load the mesh by its id
	pose: Pose?,
	seat: number?, -- pose "seat": studs from the seat mesh's bottom to where the slime sits
	items: { string }?, -- kind "items": ItemIcons ids, in order
}

local ShopPreview = {}

-- ReplicatedStorage folders the server fills with templates (server/MeshSwap: publishPetSeatTemplates,
-- publishHatTemplates, the plot skin decor).
ShopPreview.FOLDERS = table.freeze({
	seat = "PetCloudMeshes",
	hat = "SlimeHatMeshes",
	decor = "PlotSkinMeshes",
})

ShopPreview.STYLE = table.freeze({
	turnSeconds = 9, -- one full turn of the model
	restYaw = -30, -- degrees: the model's angle when reduced motion keeps it still
	fov = 30,
	pitch = 14, -- degrees the camera looks down
	margin = 1.12, -- framing room around the model's turning circle
	slimeColor = { 110, 226, 120 }, -- the slime that wears a hat or rides a cloud
	riderShare = 0.55, -- rider width over the cloud's width
	riderSink = 0.15, -- share of the rider sunk into the seat
	batTilt = 24, -- degrees a Bat skin leans
	itemsMax = 4, -- bundle items shown side by side
	itemGap = 6,
	itemShare = 0.62, -- bundle item size per stage height
})

local STYLE = ShopPreview.STYLE

local function find(list: { any }?, id: string): any?
	for _, def in list or {} do
		if def.id == id then
			return def
		end
	end
	return nil
end

local function model(key: string, mesh: string?, pose: Pose, folder: string?, seat: number?): Preview?
	if type(mesh) ~= "string" or mesh == "" then
		return nil
	end
	return { key = key, kind = "model", mesh = mesh, folder = folder, pose = pose, seat = seat }
end

-- ItemIcons id of an Exclusive product key ("Seat_leaf" -> "PetSeat_leaf"); cosmetics keep their key.
function ShopPreview.iconOf(productKey: string): string
	local prefix, id = string.match(productKey, "^(%a+)_(.+)$")
	if prefix == "Seat" then
		return `PetSeat_{id}`
	elseif prefix == "Skin" then
		return `PlotSkin_{id}`
	elseif prefix == "Base" then
		return `PlotBase_{id}`
	end
	return productKey
end

-- The items of bundle `key` as ItemIcons ids, or nil when `key` is not a bundle.
local function bundleItems(config: any, key: string): { string }?
	local def = config.EXCLUSIVE_SHOP and config.EXCLUSIVE_SHOP.products[key]
	local grant = def and def.grant
	if grant == nil then
		return nil
	end
	local items: { string } = {}
	if grant.kind == "pack" then
		for _, item in grant.items or {} do
			if config.EXCLUSIVE_SHOP.products[item] then
				table.insert(items, ShopPreview.iconOf(item))
			end
		end
	elseif grant.kind == "bundle" then
		for _, seat in grant.seats or {} do
			table.insert(items, `PetSeat_{seat}`)
		end
		if grant.boostMult then
			table.insert(items, "Boost_Code")
		end
	else
		return nil
	end
	while #items > STYLE.itemsMax do
		table.remove(items)
	end
	return if #items > 0 then items else nil
end

-- The stage preview for `detail` (ExclusiveShopView.detail), or nil to keep the item's icon.
function ShopPreview.of(detail: any, config: any): Preview?
	if type(detail) ~= "table" then
		return nil
	end
	local kind, id = detail.kind, detail.id
	local shop = config.EXCLUSIVE_SHOP or {}
	if kind == "seat" then
		local def = find(config.PET_SEATS, id)
		return def and model(`seat:{id}`, def.mesh, "seat", ShopPreview.FOLDERS.seat, def.seat)
	elseif kind == "hat" then
		local def = find(shop.hats, id)
		return def and model(`hat:{id}`, def.mesh, "hat", ShopPreview.FOLDERS.hat)
	elseif kind == "lockStyle" then
		local def = find(shop.lockStyles, id)
		return def and model(`lockStyle:{id}`, def.mesh, "stopper")
	elseif kind == "batSkin" then
		local def = find(shop.batSkins, id)
		return def and model(`batSkin:{id}`, def.mesh, "bat")
	elseif kind == "plotSkin" then
		local def = find(config.PLOT_SKINS, id)
		return def and model(`plotSkin:{id}`, def.decor, "decor", ShopPreview.FOLDERS.decor)
	elseif kind == "product" then
		local items = bundleItems(config, id)
		return if items then { key = `items:{id}`, kind = "items", items = items } else nil
	end
	return nil
end

-- Where a rider slime sits on a seat `seatSize` big (studs, X Y Z) whose seat height is `seat`: the rider's
-- diameter and the height of its centre over the seat mesh's bottom (pure; tests).
function ShopPreview.rider(seatSize: { number }, seat: number): (number, number)
	local diameter = math.max(seatSize[1], seatSize[3]) * STYLE.riderShare
	return diameter, seat + diameter / 2 - diameter * STYLE.riderSink
end

-- Camera distance that fits a model whose turning circle is `radius` and height `height` in a STYLE.fov view
-- of aspect `aspect` (width / height) (pure; tests).
function ShopPreview.distance(radius: number, height: number, aspect: number): number
	local half = math.rad(STYLE.fov / 2)
	local byHeight = (height / 2) / math.tan(half)
	local byWidth = radius / (math.tan(half) * math.max(aspect, 0.1))
	return (math.max(byHeight, byWidth) + radius) * STYLE.margin
end

---------------------------------------------------------------- Roblox adapter

-- Context.loadMesh over MeshAssets (name -> meshId) and AssetService: one load per mesh per client, a clone each call.
function ShopPreview.meshLoader(meshAssets: any, assetService: any): (mesh: string) -> BasePart?
	local loaded: { [string]: any } = {}
	return function(mesh: string): BasePart?
		local meshId = meshAssets.meshId(mesh)
		if not meshId then
			return nil
		end
		if loaded[meshId] == nil then
			local ok, part = pcall(function()
				return assetService:CreateMeshPartAsync(meshId)
			end)
			loaded[meshId] = if ok and part then part else false
		end
		local part = loaded[meshId]
		return if part then part:Clone() else nil
	end
end

-- Context.template over a ReplicatedStorage-like container: the published template, or nil.
function ShopPreview.templateFinder(storage: Instance): (folder: string, mesh: string) -> BasePart?
	return function(folder: string, mesh: string): BasePart?
		local holder = storage:FindFirstChild(folder)
		local template = holder and holder:FindFirstChild(mesh)
		return if template and template:IsA("BasePart") then template else nil
	end
end

export type Context = {
	template: (folder: string, mesh: string) -> BasePart?, -- a published template, nil if not there (yet)
	loadMesh: (mesh: string) -> BasePart?, -- yields; a fresh MeshPart of a kit mesh, nil if it fails
	icon: (props: { [string]: any }) -> any, -- ItemIconView.new with the registry
	slime: (colorRgb: { number }) -> Model, -- SlimePreview.build
	reducedMotion: () -> boolean,
	onShown: (shown: boolean) -> (),
}

-- Fits `part` into a model posed for `preview`, standing on y = 0, centred on the turning axis.
local function compose(preview: Preview, part: BasePart, ctx: Context): Model
	local m = Instance.new("Model")
	m.Name = "ShopPreview"
	part.Anchored = true
	part.CanCollide = false
	part.CastShadow = false
	local size = part.Size
	local pose = preview.pose
	if pose == "bat" then
		part.CFrame = CFrame.Angles(0, 0, math.rad(STYLE.batTilt))
	else
		part.CFrame = CFrame.new(0, size.Y / 2, 0)
	end
	part.Parent = m
	if pose == "seat" or pose == "hat" then
		local slime = ctx.slime(STYLE.slimeColor)
		local body = slime.PrimaryPart :: BasePart
		if pose == "seat" then
			local diameter, centre = ShopPreview.rider({ size.X, size.Y, size.Z }, preview.seat or size.Y)
			slime:ScaleTo(diameter / body.Size.X)
			slime:PivotTo(CFrame.new(0, centre, 0))
		else
			local b = body.Size
			slime:PivotTo(CFrame.new(0, b.Y / 2, 0))
			local fitted, up = SlimeHatsFx.fit({ b.X, b.Y, b.Z }, { size.X, size.Y, size.Z })
			part.Size = Vector3.new(fitted[1], fitted[2], fitted[3])
			part.CFrame = body.CFrame * CFrame.new(0, up, 0)
		end
		slime.Parent = m
	end
	-- Recentre on the turning axis, feet on y = 0.
	local box, extent = m:GetBoundingBox()
	local shift = Vector3.new(-box.Position.X, extent.Y / 2 - box.Position.Y, -box.Position.Z)
	for _, p in m:GetDescendants() do
		if p:IsA("BasePart") then
			p.CFrame = p.CFrame + shift
		end
	end
	local root = Instance.new("Part")
	root.Name = "Pivot"
	root.Transparency = 1
	root.Anchored = true
	root.CanCollide = false
	root.Size = Vector3.new(0.1, 0.1, 0.1)
	root.CFrame = CFrame.new()
	root.Parent = m
	m.PrimaryPart = root
	return m
end

function ShopPreview.new(stage: GuiObject, ctx: Context)
	local viewport = Instance.new("ViewportFrame")
	viewport.Name = "Preview"
	viewport.BackgroundTransparency = 1
	viewport.Ambient = Color3.fromRGB(205, 200, 215)
	viewport.LightColor = Color3.fromRGB(255, 252, 240)
	viewport.LightDirection = Vector3.new(-0.5, -1, -0.7)
	viewport.Visible = false
	viewport.ZIndex = stage.ZIndex + 3
	viewport.Parent = stage
	local world = Instance.new("WorldModel")
	world.Parent = viewport
	local camera = Instance.new("Camera")
	camera.FieldOfView = STYLE.fov
	camera.Parent = viewport
	viewport.CurrentCamera = camera

	local row = Instance.new("Frame")
	row.Name = "Items"
	row.BackgroundTransparency = 1
	row.AnchorPoint = Vector2.new(0.5, 1)
	row.Visible = false
	row.ZIndex = stage.ZIndex + 3
	row.Parent = stage
	local list = Instance.new("UIListLayout")
	list.FillDirection = Enum.FillDirection.Horizontal
	list.HorizontalAlignment = Enum.HorizontalAlignment.Center
	list.VerticalAlignment = Enum.VerticalAlignment.Center
	list.Padding = UDim.new(0, STYLE.itemGap)
	list.SortOrder = Enum.SortOrder.LayoutOrder
	list.Parent = row

	local self = { viewport = viewport, items = row }
	local current: Preview? = nil
	local shown: Model? = nil
	local icons: { any } = {}
	local active = false
	local token = 0
	local w, h, floorY = 1, 1, 1

	local function frame()
		local m = shown
		if m == nil then
			return
		end
		local _, extent = m:GetBoundingBox()
		local radius = math.max(extent.X, extent.Z) / 2
		local aspect = w / math.max(h, 1)
		local d = ShopPreview.distance(radius, extent.Y, aspect)
		local target = Vector3.new(0, extent.Y / 2, 0)
		local pitch = math.rad(STYLE.pitch)
		camera.CFrame = CFrame.lookAt(target + Vector3.new(0, math.sin(pitch) * d, math.cos(pitch) * d), target)
	end

	local function clear()
		token += 1
		if shown then
			shown:Destroy()
			shown = nil
		end
		for _, icon in icons do
			icon.destroy()
		end
		table.clear(icons)
		viewport.Visible = false
		row.Visible = false
		ctx.onShown(false)
	end

	local function sizeItems()
		local n = #icons
		if n == 0 then
			return
		end
		local size = math.floor(math.min(h * STYLE.itemShare, (w - STYLE.itemGap * (n + 1)) / n))
		for _, icon in icons do
			icon.instance.Size = UDim2.fromOffset(size, size)
		end
		row.Size = UDim2.fromOffset(w, size)
	end

	local function build(preview: Preview)
		if preview.kind == "items" then
			for i, id in preview.items or {} do
				local icon = ctx.icon({ Name = `Item{i}`, Id = id, Size = 48, LayoutOrder = i, Parent = row })
				icon.setActive(true)
				table.insert(icons, icon)
			end
			sizeItems()
			row.Visible = true
			ctx.onShown(true)
			return
		end
		local mine = token
		task.spawn(function()
			local mesh = preview.mesh :: string
			local part: BasePart? = nil
			if preview.folder then
				local template = ctx.template(preview.folder, mesh)
				part = if template then template:Clone() else nil
			end
			if part == nil then
				part = ctx.loadMesh(mesh)
			end
			if mine ~= token or part == nil then
				if part then
					part:Destroy()
				end
				return
			end
			local m = compose(preview, part :: BasePart, ctx)
			m.Parent = world
			shown = m
			frame()
			self.tick(os.clock())
			viewport.Visible = true
			ctx.onShown(true)
		end)
	end

	-- Shows `preview` (nil: nothing, the panel keeps its icon). The same preview again does nothing.
	function self.set(preview: Preview?)
		local key = if preview then preview.key else nil
		if current and key == current.key then
			return
		end
		clear()
		current = preview
		if preview and active then
			build(preview)
		end
	end

	-- The stage is `width` x `height` px; the turntable's middle is `floor` px from its top.
	function self.layout(width: number, height: number, floor: number)
		w, h, floorY = math.max(width, 1), math.max(height, 1), floor
		viewport.Size = UDim2.fromOffset(w, math.max(floorY, 1))
		viewport.Position = UDim2.fromOffset(0, 0)
		row.Position = UDim2.fromOffset(w // 2, floorY)
		sizeItems()
		frame()
	end

	function self.setActive(on: boolean)
		if on == active then
			return
		end
		active = on
		local keep = current
		clear()
		current = keep
		if on and keep then
			build(keep)
		end
	end

	function self.showing(): boolean
		return viewport.Visible or row.Visible
	end

	function self.tick(now: number)
		local m = shown
		if m == nil or not active then
			return
		end
		local yaw = if ctx.reducedMotion()
			then math.rad(STYLE.restYaw)
			else (now % STYLE.turnSeconds) / STYLE.turnSeconds * math.pi * 2
		m:PivotTo(CFrame.Angles(0, yaw, 0))
	end

	function self.destroy()
		clear()
		viewport:Destroy()
		row:Destroy()
	end

	return self
end

return ShopPreview
