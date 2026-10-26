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

return table.freeze(SpeciesModel)
