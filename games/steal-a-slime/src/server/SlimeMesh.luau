--!strict
--[[
	SlimeMesh (owner: Phoenix): optional mesh look on top of Archer's ModelFactory.

	SlimeMesh.new({ factory, loadAsset, assetId?, warn? }) -> SlimeMesh
	SlimeMesh.load(self) -> "Mesh" | "Procedural"   -- once, at server start
	SlimeMesh.build(self, slimeData) -> Model        -- same contract as ModelFactory.build

	load() fetches the uploaded slime package (default Config.SLIME_MESH_ASSET_ID)
	through `loadAsset` (InsertService:LoadAsset in a live server) inside a pcall
	and keeps its first MeshPart as a template. Any failure (no asset access, no
	MeshPart, Lune) leaves the factory's procedural look.

	build() always starts from factory.build, so the CONTRACT.md §4 shape is
	untouched (unparented Slime_<id>, Body PrimaryPart, bottom pivot, attributes,
	tag). With a template it adds a welded MeshPart "Mesh" fitted to Body's box,
	coloured and textured like Body (genome colour + mutation material), and hides
	the Body ball. Tier rim / crown / halo, mutation parts, eyes, mouth and pattern
	stay. If dressing errors the slime is rebuilt procedurally.

	Typed slimes (v28 `species`) also get the Species attribute and, when
	unmutated, their SlimeLooks material on Body and Mesh (both looks).

	Per-type kits (SlimeLooks.get(species).kit, uploaded in MeshAssets): load() also
	fetches each kit mesh by its assetId. slime_base / slime_ears / slime_horns /
	slime_wobble are whole bodies (native 3 studs, fitted uniformly into Body's box);
	slime_acc_* are small accessories added on top of a slime_base body. A kit that
	fails to load or dress falls back to the shared package mesh, then to the
	procedural ball. Kits are cloned per slime, so they are not world mesh slots
	(WorldLayout.MESH_SLOT_BUDGET counts MeshAsset tags only).

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
}

export type SlimeMesh = {
	deps: Deps,
	template: MeshPart?,
	kits: { [string]: MeshPart },
	look: Look,
}

local SlimeMesh = {}

SlimeMesh.MESH_NAME = "Mesh"
SlimeMesh.ACCESSORY_NAME = "Accessory"
-- Share of an accessory's height sunk into the body so it sits on the surface.
SlimeMesh.ACCESSORY_SINK = 0.25

-- The body kit and optional accessory kit for a SlimeLooks kit name: slime_acc_*
-- sit on a slime_base body, every other kit is the body itself.
function SlimeMesh.plan(kit: string?): (string?, string?)
	if not kit then
		return nil, nil
	end
	if string.sub(kit, 1, 10) == "slime_acc_" then
		return "slime_base", kit
	end
	return kit, nil
end

function SlimeMesh.new(deps: Deps): SlimeMesh
	return { deps = deps, template = nil, kits = {}, look = "Procedural" }
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
	local failed: { string } = {}
	local pending = #SlimeLooks.KITS
	for _, kit in SlimeLooks.KITS do
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
			else
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

-- kit: a MeshAssets name; its native size is fitted uniformly into Body's box
-- (never stretched). nil = the shared package, stretched to the box as before.
local function dress(model: Model, template: MeshPart, kit: string?)
	local body = model.PrimaryPart :: BasePart
	local mesh = template:Clone()
	mesh.Name = SlimeMesh.MESH_NAME
	if kit then
		local fitted = MeshAssets.fit(kit, { body.Size.X, body.Size.Y, body.Size.Z })
		mesh.Size = Vector3.new(fitted[1], fitted[2], fitted[3])
	else
		mesh.Size = body.Size
	end
	mesh.CFrame = body.CFrame
	mesh.Color = body.Color
	mesh.Material = body.Material
	mesh.Transparency = 0
	mesh.Anchored = false
	mesh.Massless = true
	mesh.CanCollide = false
	mesh.CanTouch = false
	mesh.CanQuery = false
	mesh.CastShadow = true
	for _, child in mesh:GetChildren() do
		child:Destroy() -- no scripts / welds from the package
	end
	local weld = Instance.new("WeldConstraint")
	weld.Part0 = body
	weld.Part1 = mesh
	weld.Parent = mesh
	mesh.Parent = model
	-- Body stays the PrimaryPart and the prompt / raycast target, just invisible.
	body.Transparency = 1
	body.CastShadow = false
end

-- An accessory kit (leaf / crown / crystal) on top of the body, sunk a little
-- into it and scaled with the slime (native sizes are for a 3 stud slime).
local function addAccessory(model: Model, template: MeshPart, kit: string)
	local body = model.PrimaryPart :: BasePart
	local native = (MeshAssets.get(kit) :: MeshAssets.Entry).size :: { number }
	local scale = body.Size.Y / Config.SLIME_BASE_DIAMETER
	local acc = template:Clone()
	acc.Name = SlimeMesh.ACCESSORY_NAME
	acc.Size = Vector3.new(native[1] * scale, native[2] * scale, native[3] * scale)
	local lift = body.Size.Y / 2 + acc.Size.Y * (0.5 - SlimeMesh.ACCESSORY_SINK)
	acc.CFrame = body.CFrame * CFrame.new(0, lift, 0)
	acc.Color = body.Color
	acc.Material = body.Material
	acc.Transparency = 0
	acc.Anchored = false
	acc.Massless = true
	acc.CanCollide = false
	acc.CanTouch = false
	acc.CanQuery = false
	for _, child in acc:GetChildren() do
		child:Destroy()
	end
	local weld = Instance.new("WeldConstraint")
	weld.Part0 = body
	weld.Part1 = acc
	weld.Parent = acc
	acc.Parent = model
end

-- The type's material on Body and Mesh; a mutation keeps its own material.
local function applySpecies(model: Model, slimeData: Types.SlimeData)
	local look = SlimeLooks.get(slimeData.species)
	if not look then
		return
	end
	model:SetAttribute(Constants.SPECIES_ATTRIBUTE, look.id)
	if slimeData.mutation ~= "None" then
		return
	end
	local material = (Enum.Material :: any)[look.material]
	for _, name in { "Body", SlimeMesh.MESH_NAME, SlimeMesh.ACCESSORY_NAME } do
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
	local bodyKit, accKit = SlimeMesh.plan(look and look.kit)
	local attempts: { { template: MeshPart, kit: string? } } = {}
	local kitTemplate = if bodyKit then self.kits[bodyKit] else nil
	if bodyKit and kitTemplate then
		table.insert(attempts, { template = kitTemplate, kit = bodyKit })
	end
	if self.template then
		table.insert(attempts, { template = self.template, kit = nil })
	end
	for _, attempt in attempts do
		local ok, err = pcall(dress :: any, model, attempt.template, attempt.kit)
		if ok then
			local accTemplate = if accKit and attempt.kit then self.kits[accKit] else nil
			if accKit and accTemplate then
				local accOk, accErr = pcall(addAccessory :: any, model, accTemplate, accKit)
				if not accOk then
					report(self, `slime accessory {accKit} failed for {slimeData.id} ({accErr}); body only`)
				end
			end
			return finish(self, model, slimeData)
		end
		report(self, `slime mesh dress failed for {slimeData.id} ({err}); using fallback look`)
		model:Destroy()
		model = self.deps.factory.build(slimeData)
	end
	return finish(self, model, slimeData)
end

return SlimeMesh
