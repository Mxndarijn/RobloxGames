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

	Pure apart from the injected functions: Lune tests cover the fallback paths.
]]

-- Shared lives in ReplicatedStorage, not next to ServerScriptService.Server.
local Shared = if script then (game:GetService("ReplicatedStorage") :: any).Shared else nil
local Config = if Shared then require(Shared.Config) else require("../shared/Config")
local Types = if Shared then require(Shared.Types) else require("../shared/Types")

export type Look = "Mesh" | "Procedural"

export type Deps = {
	factory: { build: (Types.SlimeData) -> Model },
	loadAsset: (assetId: number) -> Instance,
	assetId: number?,
	warn: ((string) -> ())?,
}

export type SlimeMesh = {
	deps: Deps,
	template: MeshPart?,
	look: Look,
}

local SlimeMesh = {}

SlimeMesh.MESH_NAME = "Mesh"

function SlimeMesh.new(deps: Deps): SlimeMesh
	return { deps = deps, template = nil, look = "Procedural" }
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
	return self.look
end

local function dress(model: Model, template: MeshPart)
	local body = model.PrimaryPart :: BasePart
	local mesh = template:Clone()
	mesh.Name = SlimeMesh.MESH_NAME
	mesh.Size = body.Size
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

function SlimeMesh.build(self: SlimeMesh, slimeData: Types.SlimeData): Model
	local model = self.deps.factory.build(slimeData)
	local template = self.template
	if not template then
		return model
	end
	local ok, err = pcall(dress :: any, model, template)
	if ok then
		return model
	end
	report(self, `slime mesh dress failed for {slimeData.id} ({err}); using procedural`)
	model:Destroy()
	return self.deps.factory.build(slimeData)
end

return SlimeMesh
