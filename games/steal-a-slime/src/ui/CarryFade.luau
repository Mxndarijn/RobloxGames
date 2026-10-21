--!strict
--[[
	CarryFade

	A slime you are stealing turns see-through for you, the same fade a Move gives your own slime
	(SlimeMove.FADE), so it doesn't block your view while you run it home. Client-only: other players see it as
	normal. Wild slimes you carry stay solid.

	The server sets Player attribute `Carrying` (Constants.CARRYING_ATTRIBUTE) to the carried slime's id; the slime
	model carries `SlimeId` and `OwnerUserId` (the victim while it is being stolen). `CarryFade.wants` is the rule
	(tests/ui/CarryFade.spec.luau); `start` applies it in the live game and returns a cleanup function.
]]

local SlimeMove = require(script.Parent.SlimeMove)

local CarryFade = {}

CarryFade.FADE = SlimeMove.FADE
CarryFade.ID_ATTRIBUTE = "SlimeId"
CarryFade.OWNER_ATTRIBUTE = "OwnerUserId"

-- Should this slime model be faded for the local player? Only the slime they carry, and only when it belongs to
-- someone else (a steal). `ownerUserId` is the model's OwnerUserId attribute (nil or 0 on a wild slime).
function CarryFade.wants(carryingId: any, modelId: any, ownerUserId: any, localUserId: number): boolean
	if type(carryingId) ~= "string" or carryingId ~= modelId then
		return false
	end
	return type(ownerUserId) == "number" and ownerUserId ~= 0 and ownerUserId ~= localUserId
end

local function fadeable(inst: Instance): boolean
	return inst:IsA("BasePart") or inst:IsA("Decal")
end

export type Deps = {
	player: Player,
	carryingAttribute: string,
	slimeTag: string,
	collection: CollectionService,
}

function CarryFade.start(deps: Deps): () -> ()
	local player = deps.player
	local faded: Model? = nil
	local touched: { Instance } = {}
	local addedConn: RBXScriptConnection? = nil
	local conns: { RBXScriptConnection } = {}

	local function restore()
		for _, inst in touched do
			(inst :: any).LocalTransparencyModifier = 0
		end
		table.clear(touched)
		if addedConn then
			addedConn:Disconnect()
			addedConn = nil
		end
		faded = nil
	end

	local function fade(inst: Instance)
		if fadeable(inst) then
			(inst :: any).LocalTransparencyModifier = CarryFade.FADE
			table.insert(touched, inst)
		end
	end

	local function refresh()
		local carryingId = player:GetAttribute(deps.carryingAttribute)
		local target: Model? = nil
		if type(carryingId) == "string" then
			for _, inst in deps.collection:GetTagged(deps.slimeTag) do
				if
					inst:IsA("Model")
					and CarryFade.wants(
						carryingId,
						inst:GetAttribute(CarryFade.ID_ATTRIBUTE),
						inst:GetAttribute(CarryFade.OWNER_ATTRIBUTE),
						player.UserId
					)
				then
					target = inst
					break
				end
			end
		end
		if target == faded then
			return
		end
		restore()
		if target then
			faded = target
			for _, d in target:GetDescendants() do
				fade(d)
			end
			-- Mesh swaps and rigs can add parts while it is carried.
			addedConn = target.DescendantAdded:Connect(fade)
		end
	end

	table.insert(conns, player:GetAttributeChangedSignal(deps.carryingAttribute):Connect(refresh))
	-- The slime model may stream in after the attribute is set.
	table.insert(
		conns,
		deps.collection:GetInstanceAddedSignal(deps.slimeTag):Connect(function()
			if faded == nil and player:GetAttribute(deps.carryingAttribute) ~= nil then
				refresh()
			end
		end)
	)
	refresh()

	return function()
		for _, c in conns do
			c:Disconnect()
		end
		table.clear(conns)
		restore()
	end
end

return CarryFade
