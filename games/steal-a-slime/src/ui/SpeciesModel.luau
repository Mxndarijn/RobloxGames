--!strict
--[[
	SpeciesModel

	The SlimeDex preview of one species: its fully vertex-coloured mesh, worn with Color white like the server's
	SlimeMesh and turned by MeshAssets.IMPORT_YAW so the slime faces -Z (the SlimePreview camera looks at its
	front). Species meshes are Model assets only the server can load (InsertService), so the server copies each
	loaded kit MeshPart into ReplicatedStorage[Constants.SLIME_KITS_FOLDER] as "slime_<id>" (WorldView). A kit
	that is not there (yet) gives nil and the card falls back to the procedural preview.
]]

local SpeciesModel = {}

-- `kits` returns the replicated kit folder (nil while it is missing); `importYaw` is MeshAssets.IMPORT_YAW.
function SpeciesModel.builder(kits: () -> Instance?, importYaw: number): (speciesId: string) -> Model?
	return function(speciesId: string): Model?
		local folder = kits()
		local template = if folder then folder:FindFirstChild(`slime_{speciesId}`) else nil
		if template == nil or not template:IsA("BasePart") then
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

return table.freeze(SpeciesModel)
