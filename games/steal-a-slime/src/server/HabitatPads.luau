--!strict
--[[
	HabitatPads (pure, FEATURES.Habitats, HABITATS.md)

	The server owns every pad's habitat. targets(world) gives each pad of each
	plot its habitat id: the slime resting on it (Scene state "Pad": not
	carried, not escaping home) picks it via Habitats.forSlime, anything else
	is Habitats.BASE. step() keeps a { [plot|pad]: PadState } table in
	sync and returns the pads that changed; WorldView writes them as the
	Habitat / HabitatFrom / HabitatAt attributes on Pad_<j>.
	With the flag off step() changes nothing and returns nothing.
	Never touches the World or saved data.
]]

local Shared = if script then (game:GetService("ReplicatedStorage") :: any).Shared else nil
local Config = if Shared then require(Shared.Config) else require("../shared/Config")
local Habitats = if Shared then require(Shared.Habitats) else require("../shared/Habitats")
local World = if script then require(script.Parent.World) else require("./World")

type World = World.World

export type Change = { plotIndex: number, pad: number, state: Habitats.PadState }
export type State = { [string]: Habitats.PadState }

local HabitatPads = {}

local function key(plotIndex: number, pad: number): string
	return `{plotIndex}|{pad}`
end

-- { [plotIndex]: { [pad]: habitat id } } for every plot and pad 1..PADS_MAX.
function HabitatPads.targets(world: World): { [number]: { [number]: string } }
	local out: { [number]: { [number]: string } } = {}
	for index = 1, world.plotCount do
		local pads: { [number]: string } = {}
		for pad = 1, Config.PADS_MAX do
			pads[pad] = Habitats.BASE
		end
		out[index] = pads
	end
	for _, session in world.sessions do
		local pads = out[session.plotIndex]
		if pads then
			for _, slime in session.data.slimes do
				local pad = slime.pad
				if
					pad
					and pads[pad]
					and not slime.egg
					and not world.carriedBy[slime.id]
					and not world.escaping[slime.id]
				then
					pads[pad] = Habitats.forSlime(slime)
				end
			end
		end
	end
	return out
end

function HabitatPads.new(): State
	return {}
end

-- Brings `state` up to date; returns the pads whose habitat changed (first
-- call: every pad, so join-in-progress clients read a full set).
function HabitatPads.step(state: State, world: World, now: number, enabled: boolean): { Change }
	local changes: { Change } = {}
	if not enabled then
		return changes
	end
	for index, pads in HabitatPads.targets(world) do
		for pad, target in pads do
			local k = key(index, pad)
			local prev = state[k]
			local nextState = Habitats.transition(prev, target, now)
			if nextState ~= prev then
				state[k] = nextState
				table.insert(changes, { plotIndex = index, pad = pad, state = nextState })
			end
		end
	end
	return changes
end

function HabitatPads.get(state: State, plotIndex: number, pad: number): Habitats.PadState?
	return state[key(plotIndex, pad)]
end

return HabitatPads
