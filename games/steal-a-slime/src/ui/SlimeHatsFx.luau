--!strict
--[[
	SlimeHatsFx (client, contract/exclusive-shop.md §15)

	Exclusive slime hats: every slime standing on a pad wears the hat its owner's plot shows (Plot_<i> attribute
	SlimeHat, the owner's worn hat id). The hat belongs to the pad: a slime that leaves its pad (carried, stolen) loses
	it. The hat is a clone of the server's template (ReplicatedStorage.SlimeHatMeshes, MeshSwap.publishHatTemplates),
	scaled to the slime's width, welded on top of its visible `Mesh` (the Body is a taller invisible box; a model
	without a Mesh uses the Body), Archivable false so a FollowPets clone never copies it.
	A hat without an uploaded template shows nothing. Cosmetic only: no collision, no queries.

	Pure helpers (`want`, `fit`) are tested under Lune (tests/ui/SlimeHatsFx.spec.luau). `start` returns `tick`
	(called from the client's frame loop, which rechecks at most every RECHECK seconds) and `destroy`.
]]

local SlimeHatsFx = {}

SlimeHatsFx.HAT_NAME = "ExclusiveHat"
SlimeHatsFx.PAD_STATE = "Pad"
SlimeHatsFx.RECHECK = 0.5 -- seconds between sweeps
SlimeHatsFx.WIDTH = 0.55 -- hat width over the slime mesh's width (measured in Studio on a pad slime)
SlimeHatsFx.SINK = 0.2 -- share of the mesh's height the hat sits below its top (the slime's dome is round)

-- The hat mesh a slime should wear: its owner's plot hat (by Config.EXCLUSIVE_SHOP.hats id) while it stands on a pad.
-- `plotHats`: owner userId -> worn hat id. Returns the kit mesh name, or nil.
function SlimeHatsFx.want(
	ownerId: any,
	state: any,
	isEgg: boolean,
	plotHats: { [number]: string },
	hats: { any }
): string?
	if type(ownerId) ~= "number" or state ~= SlimeHatsFx.PAD_STATE or isEgg then
		return nil
	end
	local id = plotHats[ownerId]
	if not id then
		return nil
	end
	for _, def in hats do
		if def.id == id then
			return def.mesh
		end
	end
	return nil
end

-- The hat's size and its offset up from the slime mesh's centre, for a mesh of `bodySize` and a template of
-- `hatSize` (x, y, z as numbers): one uniform scale so the hat is WIDTH of the mesh wide.
function SlimeHatsFx.fit(bodySize: { number }, hatSize: { number }): ({ number }, number)
	local width = math.max(bodySize[1], bodySize[3]) * SlimeHatsFx.WIDTH
	local scale = width / math.max(hatSize[1], hatSize[3], 1e-3)
	local size = { hatSize[1] * scale, hatSize[2] * scale, hatSize[3] * scale }
	local up = bodySize[2] / 2 - bodySize[2] * SlimeHatsFx.SINK + size[2] / 2
	return size, up
end

export type Options = {
	collection: CollectionService,
	tag: string, -- Constants.SLIME_TAG
	plots: Instance, -- workspace.Plots
	templates: () -> Instance?, -- ReplicatedStorage.SlimeHatMeshes (nil until the server made it)
	hats: { any }, -- Config.EXCLUSIVE_SHOP.hats
	hatAttribute: string, -- Constants.PLOT_SLIME_HAT_ATTRIBUTE
	clock: () -> number,
}

function SlimeHatsFx.start(opts: Options)
	local last = -math.huge
	local worn: { [Model]: BasePart } = {}

	local function remove(model: Model)
		local hat = worn[model]
		if hat then
			hat:Destroy()
			worn[model] = nil
		end
	end

	local function plotHats(): { [number]: string }
		local out: { [number]: string } = {}
		for _, plot in opts.plots:GetChildren() do
			local owner, hat = plot:GetAttribute("OwnerUserId"), plot:GetAttribute(opts.hatAttribute)
			if type(owner) == "number" and owner ~= 0 and type(hat) == "string" then
				out[owner] = hat
			end
		end
		return out
	end

	local function sweep()
		local hats = plotHats()
		local folder = opts.templates()
		local seen: { [Model]: boolean } = {}
		for _, inst in opts.collection:GetTagged(opts.tag) do
			if not inst:IsA("Model") then
				continue
			end
			local model = inst :: Model
			local visible = model:FindFirstChild("Mesh")
			local body = if visible and visible:IsA("BasePart") then visible else model:FindFirstChild("Body")
			local mesh = SlimeHatsFx.want(
				model:GetAttribute("OwnerUserId"),
				model:GetAttribute("State"),
				model:GetAttribute("EggKind") ~= nil,
				hats,
				opts.hats
			)
			local template = if mesh and folder then folder:FindFirstChild(mesh) else nil
			if not (body and body:IsA("BasePart") and template and template:IsA("BasePart")) then
				remove(model)
				continue
			end
			seen[model] = true
			local current = worn[model]
			if current and current:GetAttribute("Mesh") == mesh and current.Parent == body then
				continue
			end
			remove(model)
			local b, t = body.Size, template.Size
			local size, up = SlimeHatsFx.fit({ b.X, b.Y, b.Z }, { t.X, t.Y, t.Z })
			local hat = template:Clone() :: BasePart
			hat.Name = SlimeHatsFx.HAT_NAME
			hat.Archivable = false
			hat:SetAttribute("Mesh", mesh)
			hat.Size = Vector3.new(size[1], size[2], size[3])
			hat.CFrame = body.CFrame * CFrame.new(0, up, 0)
			hat.Anchored = false
			hat.CanCollide = false
			hat.CanQuery = false
			hat.CanTouch = false
			hat.Massless = true
			local weld = Instance.new("WeldConstraint")
			weld.Part0 = body
			weld.Part1 = hat
			weld.Parent = hat
			hat.Parent = body
			worn[model] = hat
		end
		for model in worn do
			if not seen[model] then
				remove(model)
			end
		end
	end

	return {
		tick = function()
			local now = opts.clock()
			if now - last < SlimeHatsFx.RECHECK then
				return
			end
			last = now
			sweep()
		end,
		destroy = function()
			for model in worn do
				remove(model)
			end
		end,
	}
end

return table.freeze(SlimeHatsFx)
