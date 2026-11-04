--!strict
--[[
	ShopPreview

	What the Exclusive shop's stage shows for the selected item (docs/shop-preview-proposal.html, option A): the
	item's real 3D model turning on the turntable instead of its icon, or a bundle's items side by side.

	  * `of(detail, config)` (pure): the preview for an ExclusiveShopView.Detail, or nil to keep the icon.
	    Clouds carry a slime at their seat height, hats sit on a slime,
	    lock stoppers, Bat skins and base-skin decor turn on their own. A plot base is built whole from its mesh
	    slot plan (`basePieces`: all floors and the roof, classic tints, glass see-through) and turns. A trail
	    streams behind a slime running round the turntable (`trailFrame`: a ViewportFrame can't draw Trails or
	    ParticleEmitters, so the ribbon is thin parts and the particles are camera-facing decals, moved each frame
	    from CarryTrail's own numbers). Passes and boosts keep their icon.
	  * `new(stage, ctx)` (Roblox): a ViewportFrame and an item row over the stage. `set(preview)` swaps what
	    it shows (the mesh loads in its own thread; `ctx.onShown(true)` once it is up, so the panel hides the
	    icon medal under it), `tick(now)` turns the model, `setActive(false)` drops it while the shop is shut.

	Models are clones of the templates the server publishes in ReplicatedStorage (seats, hats, skin decor), the
	same parts the world uses, so the preview looks like the item in game. Meshes without a published template
	(lock stoppers, Bat skins) load once per client through `ctx.loadMesh`.
]]

local MeshAssets = if script
	then require(game:GetService("ReplicatedStorage"):WaitForChild("Shared"):WaitForChild("MeshAssets"))
	else require("../shared/MeshAssets")
local BaseShapes = if script
	then require(game:GetService("ReplicatedStorage"):WaitForChild("Visuals"):WaitForChild("BaseShapes"))
	else require("../visuals/shared/BaseShapes")
local CarryTrail = if script
	then require(game:GetService("ReplicatedStorage"):WaitForChild("Visuals"):WaitForChild("CarryTrail"))
	else require("../visuals/shared/CarryTrail")

export type Pose = "seat" | "hat" | "stopper" | "bat" | "decor"

-- One mesh of a plot base, placed like server/MeshSwap places it in its slot (plot-local studs).
export type Piece = {
	mesh: string,
	size: { number }, -- the mesh's size, fitted uniformly into its slot box
	pos: { number }, -- the slot box's centre
	drop: number, -- how far the mesh sits below the box centre (it stands on the box's bottom)
	rgb: { number }?, -- the classic skin's tint for the piece's role; nil = the mesh's own colours
	glass: boolean,
}

-- One frame of a trail preview, in the turntable's studs (y up, the turning axis at x = z = 0).
export type TrailSegment = { a: { number }, b: { number }, height: number, rgb: { number }, transparency: number }
export type TrailParticle = {
	pos: { number },
	size: number,
	rgb: { number },
	transparency: number,
	rotation: number,
}
export type TrailFrame = {
	slime: { number }, -- the runner's centre
	heading: { number }, -- the way it runs (unit, horizontal)
	ribbon: { TrailSegment },
	particles: { TrailParticle },
}

export type Preview = {
	key: string, -- what is shown; a new key rebuilds the stage
	kind: "model" | "items" | "base" | "trail",
	base: string?, -- kind "base": Config.PLOT_BASES id
	floors: number?, -- kind "base": the floors built (#Config.BASE_FLOORS)
	trail: string?, -- kind "trail": EXCLUSIVE_SHOP.trails id
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
	margin = 1.06, -- framing room around the model
	depth = 0.5, -- share of the turning radius added for the side that turns towards the camera
	slimeColor = { 110, 226, 120 }, -- the slime that wears a hat or rides a cloud
	riderShare = 0.4, -- rider width over the cloud's width
	riderSink = 0.2, -- share of the rider sunk into the seat
	hatShare = 0.85, -- hat width over the slime's width (the preview's ball slime has no dome to hide a brim)
	hatSink = 0.22, -- share of the slime's height the hat sits below its top
	batTilt = 24, -- degrees a Bat skin leans
	itemsMax = 4, -- bundle items shown side by side
	itemGap = 6,
	itemShare = 0.62, -- bundle item size per stage height
	baseYaw = 180, -- degrees: a base's slots turn half round like in the world (BaseShapes slotNode)
	glassTransparency = 0.8, -- a base's glass, as WorldLayout.JAR_GLASS_MESH_TRANSPARENCY
})

-- The trail preview: a slime runs round the turntable and its trail streams behind it.
ShopPreview.TRAIL = table.freeze({
	radius = 2.2, -- studs: the runner's circle
	lap = 3.6, -- seconds per lap
	slime = 1.7, -- studs: the runner's width
	bob = 0.12, -- studs the runner hops
	hops = 2.5, -- hops per second
	scale = 0.85, -- CarryTrail numbers are for a player; the runner is a little smaller
	stretch = 2.6, -- the ribbon lives this many times CarryTrail's lifetime (the preview runs slower than a player)
	segments = 14, -- ribbon pieces
	thickness = 0.05,
	restTime = 2.3, -- seconds: the frame reduced motion shows
	camera = 0.3, -- extra studs round the circle the camera keeps in view
	pitch = 30, -- degrees the camera looks down, so the circle reads as a circle
})

local TRAIL = ShopPreview.TRAIL

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
	elseif kind == "plotBase" then
		if type(id) ~= "string" or BaseShapes.looks(id) == nil then
			return nil
		end
		return { key = `plotBase:{id}`, kind = "base", base = id, floors = #(config.BASE_FLOORS or { 1 }) }
	elseif kind == "trail" then
		if CarryTrail.def(id) == nil then
			return nil
		end
		return { key = `trail:{id}`, kind = "trail", trail = id }
	elseif kind == "product" then
		local items = bundleItems(config, id)
		return if items then { key = `items:{id}`, kind = "items", items = items } else nil
	end
	return nil
end

-- The box of a slot's mesh in a slot plan: its own, or its first skin variant's (BaseShapes slotNode does the same).
local function slotBox(boxes: any, mesh: string): any?
	local box = boxes[mesh]
	if box then
		return box
	end
	for name, b in boxes do
		if string.sub(name, 1, #mesh + 1) == mesh .. "@" then
			return b
		end
	end
	return nil
end

-- Every uploaded mesh of plot base `base` with all `floors` floors built (the top one wears the roof), placed like
-- the world does (pure; tests). Pieces shown only while a floor is covered or on top follow that rule; floor 1's
-- door-shut look is left out (the preview shows the base open), and skin-only meshes the classic skin lacks too.
function ShopPreview.basePieces(base: string, floors: number): { Piece }
	local looks = BaseShapes.looks(base)
	local out: { Piece } = {}
	if looks == nil then
		return out
	end
	for _, slot in looks.slots do
		local top = slot.floor == floors
		local shown = if slot.show == "top" then top elseif slot.show == "covered" then not top else slot.floor <= floors
		local box = slotBox(looks.boxes, slot.mesh)
		if shown and slot.name ~= "StopperShut" and box and MeshAssets.meshId(slot.mesh) then
			local k = slot.scale or 1
			local o, c = slot.offset, box.centre
			local fitted, _, drop = MeshAssets.fit(slot.mesh, { box.size[1] * k, box.size[2] * k, box.size[3] * k })
			table.insert(out, {
				mesh = slot.mesh,
				size = fitted,
				pos = { o[1] + c[1] * k, o[2] + c[2] * k, o[3] + c[3] * k },
				drop = drop,
				rgb = if slot.role and not slot.glass then BaseShapes.tint(base, "classic", slot.role) else nil,
				glass = slot.glass == true,
			})
		end
	end
	return out
end

-- A repeatable random number in [0, 1) for particle `k`'s draw `j` (pure: the same frame every time).
local function hash(k: number, j: number): number
	local x = math.sin(k * 12.9898 + j * 78.233) * 43758.5453
	return x - math.floor(x)
end

local function lerp(a: number, b: number, u: number): number
	return a + (b - a) * u
end

-- A NumberKey sequence (CarryTrail) at `u` in 0..1.
local function numberAt(seq: { { t: number, v: number } }, u: number): number
	if u <= seq[1].t then
		return seq[1].v
	end
	for i = 2, #seq do
		local a, b = seq[i - 1], seq[i]
		if u <= b.t then
			return lerp(a.v, b.v, (u - a.t) / math.max(b.t - a.t, 1e-6))
		end
	end
	return seq[#seq].v
end

-- A ColorKey sequence (CarryTrail, 0..255) at `u` in 0..1.
local function colorAt(seq: { { t: number, rgb: { number } } }, u: number): { number }
	if u <= seq[1].t then
		return seq[1].rgb
	end
	for i = 2, #seq do
		local a, b = seq[i - 1], seq[i]
		if u <= b.t then
			local w = (u - a.t) / math.max(b.t - a.t, 1e-6)
			return { lerp(a.rgb[1], b.rgb[1], w), lerp(a.rgb[2], b.rgb[2], w), lerp(a.rgb[3], b.rgb[3], w) }
		end
	end
	return seq[#seq].rgb
end

-- Where the runner is at time `t`: its centre and the way it runs (pure).
function ShopPreview.runner(t: number): ({ number }, { number })
	local a = t / TRAIL.lap * math.pi * 2
	local hop = math.abs(math.sin(t * TRAIL.hops * math.pi)) * TRAIL.bob
	local pos = { TRAIL.radius * math.cos(a), TRAIL.slime / 2 + hop, TRAIL.radius * math.sin(a) }
	return pos, { -math.sin(a), 0, math.cos(a) }
end

-- The trail `look` (CarryTrail.look) at time `t`: the runner, the ribbon behind it and the live particles (pure;
-- tests). Every number is CarryTrail's, scaled by TRAIL.scale to the runner; particle k is born at k / rate with its
-- own repeatable spread, speed and lifetime, and moves as a ParticleEmitter would (drag, then acceleration).
function ShopPreview.trailFrame(look: any, t: number): TrailFrame
	local s = TRAIL.scale
	local slime, heading = ShopPreview.runner(t)
	local tr = look.trail
	local span = tr.lifetime * TRAIL.stretch
	local midY = (tr.top + tr.bottom) / 2 * s
	local tall = (tr.top - tr.bottom) * s
	local ribbon: { TrailSegment } = {}
	local prev: { number }? = nil
	for i = 0, TRAIL.segments do
		local u = i / TRAIL.segments
		local p = ShopPreview.runner(t - u * span)
		local here = { p[1], slime[2] + midY, p[3] }
		if prev then
			table.insert(ribbon, {
				a = prev,
				b = here,
				height = tall * numberAt(tr.width, u),
				rgb = colorAt(tr.colors, u),
				transparency = numberAt(tr.transparency, u),
			})
		end
		prev = here
	end

	local pl = look.particles
	local particles: { TrailParticle } = {}
	local first = math.floor((t - pl.lifetime[2]) * pl.rate)
	for k = math.max(first, 0), math.floor(t * pl.rate) do
		local born = k / pl.rate
		local life = lerp(pl.lifetime[1], pl.lifetime[2], hash(k, 1))
		local age = t - born
		if age >= 0 and age < life then
			local u = age / life
			local at, run = ShopPreview.runner(born)
			-- the runner's frame when it was born: back = -run, right = up x back
			local back = { -run[1], 0, -run[3] }
			local right = { -back[3], 0, back[1] }
			local o = pl.offset
			local origin = {
				at[1] + (right[1] * o[1] + back[1] * o[3]) * s,
				at[2] + o[2] * s,
				at[3] + (right[3] * o[1] + back[3] * o[3]) * s,
			}
			local cone = math.rad(pl.spread) * hash(k, 2)
			local around = math.pi * 2 * hash(k, 3)
			local side, up = math.sin(cone) * math.cos(around), math.sin(cone) * math.sin(around)
			local speed = lerp(pl.speed[1], pl.speed[2], hash(k, 4)) * s
			local v = {
				(back[1] * math.cos(cone) + right[1] * side) * speed,
				up * speed,
				(back[3] * math.cos(cone) + right[3] * side) * speed,
			}
			local moved = if pl.drag > 0 then (1 - math.exp(-pl.drag * age)) / pl.drag else age
			local fall = 0.5 * age * age * s
			table.insert(particles, {
				pos = {
					origin[1] + v[1] * moved + pl.accel[1] * fall,
					origin[2] + v[2] * moved + pl.accel[2] * fall,
					origin[3] + v[3] * moved + pl.accel[3] * fall,
				},
				size = numberAt(pl.size, u) * s * 2,
				rgb = colorAt(pl.colors, u),
				transparency = numberAt(pl.transparency, u),
				rotation = lerp(pl.rotation[1], pl.rotation[2], hash(k, 5))
					+ lerp(pl.rotSpeed[1], pl.rotSpeed[2], hash(k, 6)) * age,
			})
		end
	end
	return { slime = slime, heading = heading, ribbon = ribbon, particles = particles }
end

-- Where a rider slime sits on a seat `seatSize` big (studs, X Y Z) whose seat height is `seat`: the rider's
-- diameter and the height of its centre over the seat mesh's bottom (pure; tests).
function ShopPreview.rider(seatSize: { number }, seat: number): (number, number)
	local diameter = math.max(seatSize[1], seatSize[3]) * STYLE.riderShare
	return diameter, seat + diameter / 2 - diameter * STYLE.riderSink
end

-- A hat `hatSize` (studs, X Y Z) on a round slime `diameter` across: its scale and the height of its centre over
-- the slime's centre (pure; tests).
function ShopPreview.hat(diameter: number, hatSize: { number }): (number, number)
	local scale = diameter * STYLE.hatShare / math.max(hatSize[1], hatSize[3], 1e-3)
	return scale, diameter / 2 - diameter * STYLE.hatSink + hatSize[2] * scale / 2
end

-- Camera distance that fits a model whose turning circle is `radius` and height `height` in a STYLE.fov view
-- of aspect `aspect` (width / height) (pure; tests).
function ShopPreview.distance(radius: number, height: number, aspect: number): number
	local half = math.rad(STYLE.fov / 2)
	local byHeight = (height / 2) / math.tan(half)
	local byWidth = radius / (math.tan(half) * math.max(aspect, 0.1))
	return (math.max(byHeight, byWidth) + radius * STYLE.depth) * STYLE.margin
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

local finish: (m: Model) -> Model

-- Fits `part` into a model posed for `preview`, standing on y = 0, centred on the turning axis.
local function compose(preview: Preview, part: BasePart, ctx: Context): Model
	local m = Instance.new("Model")
	m.Name = "ShopPreview"
	part.Anchored = true
	part.CanCollide = false
	part.CastShadow = false
	-- The model's own vertex colours (a MeshPart's Color multiplies them; templates keep the default grey).
	part.Color = Color3.new(1, 1, 1)
	local size = part.Size
	local pose = preview.pose
	-- Kit meshes face the camera after the import turn, like the slime's eyes.
	local face = CFrame.Angles(0, math.rad(MeshAssets.IMPORT_YAW), 0)
	if pose == "bat" then
		part.CFrame = CFrame.Angles(0, 0, math.rad(STYLE.batTilt)) * face
	else
		part.CFrame = CFrame.new(0, size.Y / 2, 0) * face
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
			local scale, up = ShopPreview.hat(b.X, { size.X, size.Y, size.Z })
			part.Size = size * scale
			part.CFrame = body.CFrame * CFrame.new(0, up, 0) * face
		end
		slime.Parent = m
	end
	return finish(m)
end

-- A plot base from its pieces: every mesh loaded at once (one load per mesh, shared by the floors that repeat it),
-- placed and tinted. Yields; nil when no piece loads.
local function composeBase(pieces: { Piece }, ctx: Context): Model?
	local loaded: { [string]: BasePart | false } = {}
	local waiting = 0
	local me = coroutine.running()
	local parked = false
	for _, piece in pieces do
		if loaded[piece.mesh] == nil then
			loaded[piece.mesh] = false
			waiting += 1
			task.spawn(function()
				local part = ctx.loadMesh(piece.mesh)
				loaded[piece.mesh] = part or false
				waiting -= 1
				if waiting == 0 and parked then
					task.spawn(me) -- the last load wakes the builder
				end
			end)
		end
	end
	if waiting > 0 then
		parked = true
		coroutine.yield()
	end
	local m = Instance.new("Model")
	m.Name = "ShopPreview"
	local face = CFrame.Angles(0, math.rad(MeshAssets.IMPORT_YAW), 0)
	local turn = CFrame.Angles(0, math.rad(STYLE.baseYaw), 0)
	local any = false
	for _, piece in pieces do
		local source = loaded[piece.mesh]
		if source then
			local part = (source :: BasePart):Clone()
			part.Anchored = true
			part.CanCollide = false
			part.CastShadow = false
			part.Size = Vector3.new(piece.size[1], piece.size[2], piece.size[3])
			part.Color = if piece.rgb
				then Color3.fromRGB(piece.rgb[1], piece.rgb[2], piece.rgb[3])
				else Color3.new(1, 1, 1)
			if piece.glass then
				part.Transparency = STYLE.glassTransparency
			end
			part.CFrame = CFrame.new(piece.pos[1], piece.pos[2], piece.pos[3])
				* turn
				* CFrame.new(0, -piece.drop, 0)
				* face
			part.Parent = m
			any = true
		end
	end
	for _, source in loaded do
		if source then
			source:Destroy()
		end
	end
	if not any then
		m:Destroy()
		return nil
	end
	return finish(m)
end

-- The trail stage: the runner, an invisible box round its circle (so the camera frames the whole run) and pools of
-- ribbon parts and particle cards that `trailStep` moves.
type TrailStage = { model: Model, slime: Model, ribbon: { BasePart }, cards: { BasePart }, decals: { Decal } }

local function composeTrail(look: any, ctx: Context): TrailStage
	local m = Instance.new("Model")
	m.Name = "ShopPreview"
	local slime = ctx.slime(STYLE.slimeColor)
	local body = slime.PrimaryPart :: BasePart
	slime:ScaleTo(TRAIL.slime / body.Size.X)
	slime.Parent = m
	local reach = TRAIL.radius + TRAIL.slime / 2 + TRAIL.camera
	local bounds = Instance.new("Part")
	bounds.Name = "Bounds"
	bounds.Transparency = 1
	bounds.Anchored = true
	bounds.CanCollide = false
	bounds.Size = Vector3.new(reach * 2, TRAIL.slime + TRAIL.bob + 0.6, reach * 2)
	bounds.CFrame = CFrame.new(0, bounds.Size.Y / 2, 0)
	bounds.Parent = m
	local ribbon: { BasePart } = {}
	for i = 1, TRAIL.segments do
		local p = Instance.new("Part")
		p.Name = `Ribbon{i}`
		p.Anchored = true
		p.CanCollide = false
		p.CastShadow = false
		p.Material = Enum.Material.SmoothPlastic
		p.Transparency = 1
		p.Parent = m
		table.insert(ribbon, p)
	end
	local cards: { BasePart } = {}
	local decals: { Decal } = {}
	local most = math.ceil(CarryTrail.alive(look.particles)) + 2
	for i = 1, most do
		local p = Instance.new("Part")
		p.Name = `Card{i}`
		p.Anchored = true
		p.CanCollide = false
		p.CastShadow = false
		p.Transparency = 1
		p.Size = Vector3.new(1, 1, 0.05)
		p.Parent = m
		local d = Instance.new("Decal")
		d.Face = Enum.NormalId.Front
		d.Texture = look.particles.texture
		d.Transparency = 1
		d.Parent = p
		table.insert(cards, p)
		table.insert(decals, d)
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
	return { model = m, slime = slime, ribbon = ribbon, cards = cards, decals = decals }
end

-- A 0..255 colour that may hold fractions (blended keys) as a Color3.
local function color(rgb: { number }): Color3
	local function byte(x: number): number
		return math.clamp(math.floor(x + 0.5), 0, 255)
	end
	return Color3.fromRGB(byte(rgb[1]), byte(rgb[2]), byte(rgb[3]))
end

local function v3(p: { number }): Vector3
	return Vector3.new(p[1], p[2], p[3])
end

-- Moves the trail stage to frame `f`; cards face `eye` (the camera).
local function trailStep(stage: TrailStage, f: TrailFrame, eye: Vector3)
	local at = v3(f.slime)
	stage.slime:PivotTo(CFrame.lookAt(at, at + v3(f.heading)))
	for i, part in stage.ribbon do
		local seg = f.ribbon[i]
		if seg then
			local a, b = v3(seg.a), v3(seg.b)
			local length = (b - a).Magnitude
			if length > 1e-3 then
				part.Size = Vector3.new(TRAIL.thickness, math.max(seg.height, 0.05), length)
				part.CFrame = CFrame.lookAt((a + b) / 2, b)
				part.Color = color(seg.rgb)
				part.Transparency = seg.transparency
			else
				part.Transparency = 1
			end
		else
			part.Transparency = 1
		end
	end
	for i, card in stage.cards do
		local p = f.particles[i]
		local decal = stage.decals[i]
		if p then
			local pos = v3(p.pos)
			card.Size = Vector3.new(p.size, p.size, 0.05)
			card.CFrame = CFrame.lookAt(pos, eye) * CFrame.Angles(0, 0, math.rad(p.rotation))
			decal.Color3 = color(p.rgb)
			decal.Transparency = p.transparency
		else
			decal.Transparency = 1
		end
	end
end

-- Recentres `m` on the turning axis, feet on y = 0, and gives it a pivot at the origin.
finish = function(m: Model): Model
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
	local trail: { stage: TrailStage, look: any }? = nil
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
		local pitch = math.rad(if trail then TRAIL.pitch else STYLE.pitch)
		camera.CFrame = CFrame.lookAt(target + Vector3.new(0, math.sin(pitch) * d, math.cos(pitch) * d), target)
	end

	local function clear()
		token += 1
		trail = nil
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
		local function show(m: Model)
			m.Parent = world
			shown = m
			frame()
			self.tick(os.clock())
			viewport.Visible = true
			ctx.onShown(true)
		end
		if preview.kind == "trail" then
			local def = CarryTrail.def(preview.trail)
			if def == nil then
				return
			end
			local look = CarryTrail.look(def)
			local built = composeTrail(look, ctx)
			trail = { stage = built, look = look }
			show(built.model)
			return
		end
		local mine = token
		if preview.kind == "base" then
			task.spawn(function()
				local m = composeBase(ShopPreview.basePieces(preview.base :: string, preview.floors or 1), ctx)
				if mine ~= token then
					if m then
						m:Destroy()
					end
					return
				end
				if m then
					show(m)
				end
			end)
			return
		end
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
			show(compose(preview, part :: BasePart, ctx))
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
		if trail then
			local t = if ctx.reducedMotion() then TRAIL.restTime else now
			trailStep(trail.stage, ShopPreview.trailFrame(trail.look, t), camera.CFrame.Position)
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
