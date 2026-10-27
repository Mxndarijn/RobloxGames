--!strict
--[[
	CashPadService (pure, FEATURES.CashPads, contract/cash-pads.md)

	What happens when a player steps on a cash pad (CashPadView reports the touch). The plot owner collects the
	pad's pile into cash (CashPads.collect) and gets the "Collect" burst; anyone else gets nothing and a
	"Not your cash" toast at most once per NAG_SECONDS. A touch on an empty pad, an unowned plot or with the
	flag off does nothing. `nags` (userId -> next allowed toast time) is runtime state the caller owns.
]]

local Shared = if script then (game:GetService("ReplicatedStorage") :: any).Shared else nil
local CashPads = if Shared then require(Shared.CashPads) else require("../shared/CashPads")
local Config = if Shared then require(Shared.Config) else require("../shared/Config")
local World = if script then require(script.Parent.World) else require("./World")

type World = World.World

export type Nags = { [number]: number }

local CashPadService = {}

CashPadService.NAG_SECONDS = 4 -- a visitor sees "Not your cash" at most this often

-- Returns the cash paid to `userId` (0 for anyone but the owner, or an empty pad).
function CashPadService.touch(
	world: World,
	nags: Nags,
	userId: number,
	plotIndex: number,
	pad: number,
	now: number,
	features: { [string]: any }?
): number
	if not CashPads.enabled(features) or pad < 1 or pad > Config.PADS_MAX then
		return 0
	end
	local ownerId = world.plots[plotIndex]
	local owner = if ownerId then World.session(world, ownerId) else nil
	if not owner or pad > owner.data.padsUnlocked then
		return 0
	end
	if ownerId ~= userId then
		if CashPads.pile(owner.data, pad) >= 1 and now >= (nags[userId] or 0) then
			nags[userId] = now + CashPadService.NAG_SECONDS
			World.notify(world, userId, "Not your cash! Only the owner can collect it.", "bad", nil)
		end
		return 0
	end
	local paid = CashPads.collect(owner.data, pad)
	if paid > 0 then
		World.markDirty(owner)
		World.effect(world, "Collect", { userId = userId })
	end
	return paid
end

-- Forgets a player who left (their nag timer).
function CashPadService.forget(nags: Nags, userId: number)
	nags[userId] = nil
end

return CashPadService
