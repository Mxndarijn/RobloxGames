--!strict
--[[
	SpeciesModel

	The SlimeDex preview of one species: its fully vertex-coloured mesh, worn with Color white like the server's
	SlimeMesh and turned by MeshAssets.IMPORT_YAW so the slime faces -Z (the SlimePreview camera looks at its
	front). Species meshes are Model assets only the server can load (InsertService): a missing kit is asked for
	through `want` (KitCache, RequestKits) and the server copies it into this player's kit folder
	(PlayerGui[Constants.SLIME_KITS_FOLDER]) as "slime_<id>" (WorldView). Until it is there the builder gives nil
	and the card falls back to the generated model or the procedural ball.
]]

local SpeciesModel = {}

-- `kits` returns the player's kit folder (nil while it is missing); `importYaw` is MeshAssets.IMPORT_YAW;
-- `want` (optional) is told about every species whose kit is not there yet.
function SpeciesModel.builder(
	kits: () -> Instance?,
	importYaw: number,
	want: ((speciesId: string) -> ())?
): (speciesId: string) -> Model?
	return function(speciesId: string): Model?
		local folder = kits()
		local template = if folder then folder:FindFirstChild(`slime_{speciesId}`) else nil
		if template == nil or not template:IsA("BasePart") then
			if want then
				want(speciesId)
			end
			return nil
		end
		local model = Instance.new("Model")
		model.Name = `Dex_{speciesId}`
		local part = template:Clone() :: BasePart
		part.Name = "Mesh"
		part.Anchored = true
		part.Color = Color3.new(1, 1, 1)
		part.CFrame = CFrame.Angles(0, math.rad(importYaw), 0)
		part.Parent = model
		model.PrimaryPart = part
		return model
	end
end

export type GreyDeps = {
	kits: () -> Instance?, -- the player's kit folder (nil while it is missing)
	importYaw: number, -- MeshAssets.IMPORT_YAW
	-- Yields: a copy of the kit mesh with every vertex colour washed grey (SpeciesModel.greyMesh), nil on failure.
	makeGrey: (template: BasePart) -> BasePart?,
	spawn: (fn: () -> ()) -> (), -- runs makeGrey off the caller's thread (task.spawn)
	ready: () -> (), -- a grey mesh was made: the open menu remounts its previews
}

-- A species the player has not found (or does not have) as a menu shows it: its own mesh in grey, so it reads
-- as that slime. The grey copy is made once per species, the first time it is asked for while the kit is in the
-- kit folder; until then (and after a failed copy) the builder gives nil and the preview falls back to the kit
-- mesh tinted grey. Asking for a missing kit is the plain builder's job.
function SpeciesModel.greyBuilder(deps: GreyDeps): (speciesId: string) -> Model?
	local made: { [string]: BasePart | boolean } = {} -- the grey template, true while it is being made, false on failure
	return function(speciesId: string): Model?
		local entry = made[speciesId]
		if entry == nil then
			local folder = deps.kits()
			local template = if folder then folder:FindFirstChild(`slime_{speciesId}`) else nil
			if template and template:IsA("BasePart") then
				made[speciesId] = true
				deps.spawn(function()
					local ok, part = pcall(deps.makeGrey, template :: BasePart)
					made[speciesId] = if ok and part then part else false
					if ok and part then
						deps.ready()
					end
				end)
			end
			return nil
		end
		if type(entry) == "boolean" then
			return nil
		end
		local model = Instance.new("Model")
		model.Name = `Dex_{speciesId}`
		local part = (entry :: BasePart):Clone()
		part.Name = "Mesh"
		part.Anchored = true
		part.Color = Color3.new(1, 1, 1)
		part.CFrame = CFrame.Angles(0, math.rad(deps.importYaw), 0)
		part.Parent = model
		model.PrimaryPart = part
		return model
	end
end

-- The makeGrey for greyBuilder: rebuilds the kit's mesh as an EditableMesh with every vertex colour put through
-- `greyOf` (SlimePreview.greyOf), so the slime keeps its shape and markings but loses its colour. Tinting the
-- part cannot do this: a part's Color multiplies the vertex colours. Yields; errors when the mesh can't be read.
function SpeciesModel.greyMesh(assetService: any, greyOf: (Color3) -> Color3): (template: BasePart) -> BasePart?
	return function(template: BasePart): BasePart?
		if not template:IsA("MeshPart") then
			return nil
		end
		local mesh = assetService:CreateEditableMeshAsync(Content.fromUri((template :: MeshPart).MeshId))
		for _, id in mesh:GetColors() do
			mesh:SetColor(id, greyOf(mesh:GetColor(id)))
		end
		local part = assetService:CreateMeshPartAsync(Content.fromObject(mesh)) :: MeshPart
		part.Size = template.Size
		part.Material = template.Material
		return part
	end
end

return table.freeze(SpeciesModel)
