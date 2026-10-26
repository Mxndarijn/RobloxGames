--!strict
--[[
	SlimeMesh (owner: Phoenix): optional mesh look on top of Archer's ModelFactory.

	SlimeMesh.new({ factory, loadAsset, assetId?, warn? }) -> SlimeMesh
	SlimeMesh.load(self) -> "Mesh" | "Procedural"   -- once, at server start
	SlimeMesh.build(self, slimeData) -> Model        -- same contract as ModelFactory.build
	SlimeMesh.pendingKit(self, slimeData) -> string? -- its species kit, while that is still loading
	SlimeMesh.hasKit(self, kit) -> boolean

	load() fetches the uploaded slime package (default Config.SLIME_MESH_ASSET_ID)
	through `loadAsset` (InsertService:LoadAsset in a live server) inside a pcall
	and keeps its first MeshPart as a template. Any failure (no asset access, no
	MeshPart, Lune) leaves the factory's procedural look.

	build() always starts from factory.build, so the CONTRACT.md §4 shape is
	untouched (unparented Slime_<id>, Body PrimaryPart, bottom pivot, attributes,
	tag). With a template it adds a welded MeshPart "Mesh" fitted to Body's box,
	coloured and textured like Body (genome colour), and hides
	the Body ball. Tier rim / crown / halo, eyes, mouth and pattern
	stay. If dressing errors the slime is rebuilt procedurally.

	Typed slimes (v28 `species`) also get the Species attribute and their SlimeLooks material on Body and Mesh (both looks).

	Species meshes (SlimeLooks.get(species).kit = "slime_<id>", uploaded in
	MeshAssets with size + offset): load() also fetches each one by its assetId.
	A species mesh is fully coloured (Color white) and carries its own face,
	pattern and accessories, so the procedural ones and the ball's goo puddle are destroyed
	(isReplacedPart; nothing reads them, and hidden parts would still cost physics and
	replication); the aura / glow shells wrap it;
	it is worn at size-1 scale x the slime's size, placed from the bottom centre,
	and keeps its Bones. A kit that fails to load or dress falls back to the
	shared package mesh, then to the procedural ball. A slime built while its kit is
	still loading wears the shared mesh too; pendingKit names that kit so the caller
	can rebuild the slime once hasKit says it arrived. Kits are cloned per slime,
	so they are not world mesh slots (WorldLayout.MESH_SLOT_BUDGET counts
	MeshAsset tags only).

	Pure apart from the injected functions: Lune tests cover the fallback paths.
]]

-- Shared lives in ReplicatedStorage, not next to ServerScriptService.Server.
local Shared = if script then (game:GetService("ReplicatedStorage") :: any).Shared else nil
local Config = if Shared then require(Shared.Config) else require("../shared/Config")
local Constants = if Shared then require(Shared.Constants) else require("../shared/Constants")
local SlimeLooks = if Shared then require(Shared.SlimeLooks) else require("../shared/SlimeLooks")
local MeshAssets = if Shared then require(Shared.MeshAssets) else require("../shared/MeshAssets")
local Types = if Shared then require(Shared.Types) else require("../shared/Types")

export type Look = "Mesh" | "Procedural"

export type Deps = {
	factory: { build: (Types.SlimeData) -> Model },
	loadAsset: (assetId: number) -> Instance,
	assetId: number?,
	spawn: ((() -> ()) -> ())?, -- runs a kit fetch; default task.spawn (inline without it)
	warn: ((string) -> ())?,
	onKit: ((kit: string, mesh: MeshPart) -> ())?, -- a species kit finished loading (WorldView replicates it for the SlimeDex)
}

export type SlimeMesh = {
	deps: Deps,
	template: MeshPart?,
	kits: { [string]: MeshPart },
	failedKits: { [string]: boolean }, -- kits whose fetch failed: they never arrive
	look: Look,
}

local SlimeMesh = {}

SlimeMesh.MESH_NAME = "Mesh"

function SlimeMesh.new(deps: Deps): SlimeMesh
	return { deps = deps, template = nil, kits = {}, failedKits = {}, look = "Procedural" }
end

local function report(self: SlimeMesh, message: string)
	local log: (string) -> () = self.deps.warn or warn
	log(`[Server] {message}`)
end

function SlimeMesh.load(self: SlimeMesh): Look
	local assetId = self.deps.assetId or Config.SLIME_MESH_ASSET_ID
	local ok, result = pcall(function(): MeshPart?
		local asset = self.deps.loadAsset(assetId)
		local mesh = asset:FindFirstChildWhichIsA("MeshPart", true)
		local template = if mesh then mesh:Clone() :: MeshPart else nil
		asset:Destroy()
		return template
	end)
	if ok and result then
		self.template = result
		self.look = "Mesh"
	else
		self.template = nil
		self.look = "Procedural"
		local reason = if ok then "no MeshPart in the asset" else tostring(result)
		report(self, `slime mesh {assetId} unavailable ({reason}); using procedural slimes`)
	end
	-- LoadAsset yields: fetch the kits side by side so server start waits on the
	-- shared package only. A slime built before its kit arrives wears the shared mesh.
	local spawn: (() -> ()) -> () = self.deps.spawn
		or (if task
			then task.spawn :: any
			else function(fn: () -> ())
				fn()
			end)
	-- A kit that isn't uploaded yet (no assetId) is never fetched: its slimes keep the shared mesh.
	local uploaded: { string } = {}
	for _, kit in SlimeLooks.KITS do
		local entry = MeshAssets.get(kit)
		if entry and entry.assetId then
			table.insert(uploaded, kit)
		else
			self.failedKits[kit] = true
		end
	end
	local failed: { string } = {}
	local pending = #uploaded
	for _, kit in uploaded do
		spawn(function()
			local entry = MeshAssets.get(kit)
			local kitOk, kitMesh = pcall(function(): MeshPart?
				local asset = self.deps.loadAsset((entry :: MeshAssets.Entry).assetId :: number)
				local mesh = asset:FindFirstChildWhichIsA("MeshPart", true)
				local template = if mesh then mesh:Clone() :: MeshPart else nil
				asset:Destroy()
				return template
			end)
			if kitOk and kitMesh then
				self.kits[kit] = kitMesh
				if self.deps.onKit then
					self.deps.onKit(kit, kitMesh)
				end
			else
				self.failedKits[kit] = true
				table.insert(failed, kit)
			end
			pending -= 1
			if pending == 0 and #failed > 0 then
				report(self, `slime kit meshes unavailable ({table.concat(failed, ", ")}); using the shared slime mesh`)
			end
		end)
	end
	return self.look
end

-- The rig's SkinRoot (src/visuals/shared/SlimeRig) when the factory made one,
-- so a mesh look moves with the SlimeIdle / Hop animations; else Body.
local function anchorFor(model: Model, body: BasePart): BasePart
	local skin = model:FindFirstChild("SkinRoot")
	return if skin and skin:IsA("BasePart") then skin else body
end

-- Procedural parts a species mesh replaces and dress() destroys (it carries its own face, pattern and accessories). The goo
-- puddle is sized for the ball and would stand out under the mesh's foot as a thick disc.
-- Tier rim and aura stay, refitted to the mesh (fitToMesh).
local REPLACED_PREFIXES = {
	"Puddle",
	"Eye",
	"Iris",
	"Pupil",
	"Lid",
	"Lash",
	"Brow",
	"Blush",
	"Cheek",
	"Mouth",
	"Smile",
	"Tongue",
	"Fang",
	"Happy",
	"Shine",
	"Glint",
	"Gloss",
	"Spot",
	"Stripe",
	"Belly",
	"Leaf",
	"Sprout",
	"Horn",
	"Crown",
	"Halo",
}

function SlimeMesh.isReplacedPart(name: string): boolean
	for _, prefix in REPLACED_PREFIXES do
		if string.sub(name, 1, #prefix) == prefix then
			return true
		end
	end
	return false
end

-- A species mesh (MeshAssets entry with an `offset`): native size is for a size-1 slime
-- (Config.SLIME_BASE_DIAMETER wide), placed by its bbox centre relative to the slime's bottom
-- centre, so wings, tails and rings stick out instead of shrinking the body. Its vertex colours
-- are the look: Color stays white. Uploaded meshes arrive turned MeshAssets.IMPORT_YAW from the
-- kit's documented axes (the same turn MeshSwap gives world props); without it the face is at
-- the back.
local function speciesFit(body: BasePart, entry: MeshAssets.Entry): (Vector3, CFrame)
	local native = entry.size :: { number }
	local offset = entry.offset :: { number }
	local scale = body.Size.X / Config.SLIME_BASE_DIAMETER
	local bottom = body.CFrame * CFrame.new(0, -body.Size.Y / 2, 0)
	return Vector3.new(native[1] * scale, native[2] * scale, native[3] * scale),
		bottom * CFrame.new(offset[1] * scale, offset[2] * scale, offset[3] * scale) * CFrame.Angles(
			0,
			math.rad(MeshAssets.IMPORT_YAW),
			0
		)
end

-- Under a species mesh the aura shell wraps the mesh.
-- x the mesh body: its height or its narrow footprint side, so wings and tails don't blow the shell up
SlimeMesh.SHELLS = table.freeze({ Aura = 1.15 }) :: { [string]: number }

-- Moves a welded decoration: its WeldConstraint keeps the offset it had when it was enabled.
local function repose(model: Model, part: BasePart, size: Vector3, cframe: CFrame)
	local welds: { WeldConstraint } = {}
	for _, weld in model:GetDescendants() do
		if weld:IsA("WeldConstraint") and (weld.Part0 == part or weld.Part1 == part) and weld.Enabled then
			weld.Enabled = false
			table.insert(welds, weld)
		end
	end
	part.Size = size
	part.CFrame = cframe
	for _, weld in welds do
		weld.Enabled = true
	end
end

local function fitToMesh(model: Model, body: BasePart, mesh: MeshPart)
	local bottom = body.CFrame * CFrame.new(0, -body.Size.Y / 2, 0)
	local centre = bottom:PointToObjectSpace(mesh.CFrame.Position)
	local side = math.max(mesh.Size.Y, math.min(mesh.Size.X, mesh.Size.Z))
	for name, k in SlimeMesh.SHELLS do
		local shell = model:FindFirstChild(name)
		if shell and shell:IsA("BasePart") then
			local s = side * k
			-- Never below the ground: a flat, wide mesh gets its shell lifted.
			local at = bottom * CFrame.new(centre.X, math.max(centre.Y, s / 2), centre.Z)
			repose(model, shell, Vector3.new(s, s, s), at)
		end
	end
end

-- kit: a MeshAssets name. A species kit is worn at its own scale (speciesFit); any other kit is
-- fitted uniformly into Body's box (never stretched). nil = the shared package, stretched to the box.
local function dress(model: Model, template: MeshPart, kit: string?)
	local body = model.PrimaryPart :: BasePart
	local mesh = template:Clone()
	mesh.Name = SlimeMesh.MESH_NAME
	local entry = if kit then MeshAssets.get(kit) else nil
	local species = entry ~= nil and entry.offset ~= nil and entry.size ~= nil
	if species then
		local size, cframe = speciesFit(body, entry :: MeshAssets.Entry)
		mesh.Size = size
		mesh.CFrame = cframe
		mesh.Color = Color3.new(1, 1, 1)
	else
		if kit then
			local fitted = MeshAssets.fit(kit, { body.Size.X, body.Size.Y, body.Size.Z })
			mesh.Size = Vector3.new(fitted[1], fitted[2], fitted[3])
		else
			mesh.Size = body.Size
		end
		mesh.CFrame = body.CFrame
		mesh.Color = body.Color
	end
	mesh.Material = body.Material
	mesh.Transparency = 0
	mesh.Anchored = false
	mesh.Massless = true
	mesh.CanCollide = false
	mesh.CanTouch = false
	mesh.CanQuery = false
	mesh.CastShadow = true
	for _, child in mesh:GetChildren() do
		if not child:IsA("Bone") then
			child:Destroy() -- no scripts / welds from the package; a species rig keeps its bones
		end
	end
	local weld = Instance.new("WeldConstraint")
	weld.Part0 = anchorFor(model, body)
	weld.Part1 = mesh
	weld.Parent = mesh
	mesh.Parent = model
	-- Body stays the PrimaryPart and the prompt / raycast target, just invisible.
	body.Transparency = 1
	body.CastShadow = false
	if species then
		-- Each part's weld lives inside it, so Destroy takes the weld along.
		for _, part in model:GetDescendants() do
			if part:IsA("BasePart") and part ~= mesh and SlimeMesh.isReplacedPart(part.Name) then
				part:Destroy()
			end
		end
		fitToMesh(model, body, mesh)
	end
end

-- The type's material on Body and Mesh.
local function applySpecies(model: Model, slimeData: Types.SlimeData)
	local look = SlimeLooks.get(slimeData.species)
	if not look then
		return
	end
	model:SetAttribute(Constants.SPECIES_ATTRIBUTE, look.id)
	local material = (Enum.Material :: any)[look.material]
	for _, name in { "Body", SlimeMesh.MESH_NAME } do
		local part = model:FindFirstChild(name)
		if part and part:IsA("BasePart") then
			part.Material = material
		end
	end
end

local function finish(self: SlimeMesh, model: Model, slimeData: Types.SlimeData): Model
	local ok, err = pcall(applySpecies :: any, model, slimeData)
	if not ok then
		report(self, `slime type look failed for {slimeData.id} ({err})`)
	end
	return model
end

function SlimeMesh.build(self: SlimeMesh, slimeData: Types.SlimeData): Model
	local model = self.deps.factory.build(slimeData)
	local look = SlimeLooks.get(slimeData.species)
	local kit = look and look.kit
	local attempts: { { template: MeshPart, kit: string? } } = {}
	local kitTemplate = if kit then self.kits[kit] else nil
	if kit and kitTemplate then
		table.insert(attempts, { template = kitTemplate, kit = kit })
	end
	if self.template then
		table.insert(attempts, { template = self.template, kit = nil })
	end
	for _, attempt in attempts do
		local ok, err = pcall(dress :: any, model, attempt.template, attempt.kit)
		if ok then
			return finish(self, model, slimeData)
		end
		report(self, `slime mesh dress failed for {slimeData.id} ({err}); using fallback look`)
		model:Destroy()
		model = self.deps.factory.build(slimeData)
	end
	return finish(self, model, slimeData)
end

-- The species kit `slimeData` wears once it has loaded, while it is still loading; nil when it is in, failed or
-- the slime has no kit. A slime built while this is set wears the shared mesh: rebuild it once hasKit(kit).
function SlimeMesh.pendingKit(self: SlimeMesh, slimeData: Types.SlimeData): string?
	local look = SlimeLooks.get(slimeData.species)
	local kit = look and look.kit
	if kit and not self.kits[kit] and not self.failedKits[kit] then
		return kit
	end
	return nil
end

function SlimeMesh.hasKit(self: SlimeMesh, kit: string): boolean
	return if self.kits[kit] then true else false
end

return SlimeMesh
