--!strict
--[[
	PadStyle (v17): locked plot pads look "not available" with ONLY a colour + material change on the existing
	Pad_<j> / Stand parts (no new parts, no meshes; shape, size and the red rectangle stay as they are).
	Locked = the plot colour desaturated toward grey and darkened, in Slate; unlocked = the stored base look.
	Pure maths on 0..255 triples so the Lune tests can pin it; WorldView applies it on the Unlocked attribute.
]]

local PadStyle = {}

PadStyle.LOCKED_MATERIAL = "Slate"
PadStyle.GREY = table.freeze({ 96, 98, 104 })
PadStyle.GREY_MIX = 0.72 -- 0 = base colour, 1 = grey
PadStyle.DARKEN = 0.7 -- brightness multiplier on the greyed colour

export type Rgb = { number }

local function channel(base: number, grey: number): number
	return math.floor((base + (grey - base) * PadStyle.GREY_MIX) * PadStyle.DARKEN + 0.5)
end

function PadStyle.lockedColor(base: Rgb): Rgb
	return { channel(base[1], PadStyle.GREY[1]), channel(base[2], PadStyle.GREY[2]), channel(base[3], PadStyle.GREY[3]) }
end

-- Colour (0..255) and material name for a pad given its stored base look and unlock state.
function PadStyle.look(base: Rgb, baseMaterial: string, unlocked: boolean): (Rgb, string)
	if unlocked then
		return base, baseMaterial
	end
	return PadStyle.lockedColor(base), PadStyle.LOCKED_MATERIAL
end

return PadStyle
