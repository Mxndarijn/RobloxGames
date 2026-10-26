--!strict
--[[
	NavTile

	The look of a left-menu tile in the Goo kit: a mint jelly square (one uniform corner, Layout.NAV.radius,
	so DexJarView's jar maths holds) with an Ink outline and a darker bottom. The open menu's tile
	wears the Gold ring and a gold label; the tile itself stays mint. init.client builds the button and its
	icon, label and badge; this module only dresses and paints the tile.
]]

local Layout = require(script.Parent.Layout)
local Widgets = require(script.Parent.Widgets)

local Theme = Widgets.Theme

local NavTile = {}

NavTile.COLOR = Theme.Good
NavTile.STROKE = table.freeze({ normal = 3, selected = 4 })

-- Gives `tile` its jelly look and returns the outline paint() recolours.
function NavTile.dress(tile: Frame): UIStroke
	tile.BackgroundColor3 = NavTile.COLOR
	Widgets.corner(Layout.NAV.radius).Parent = tile
	local stroke = Widgets.stroke(Theme.Ink, NavTile.STROKE.normal)
	stroke.Parent = tile
	Widgets.shade(tile)
	return stroke
end

-- The open menu's tile: Gold ring and gold label; every other tile: Ink ring and white label.
function NavTile.paint(tile: Frame, stroke: UIStroke, label: TextLabel, selected: boolean)
	tile.BackgroundColor3 = NavTile.COLOR
	label.TextColor3 = if selected then Theme.Gold else Theme.Text
	stroke.Color = if selected then Theme.Gold else Theme.Ink
	stroke.Thickness = if selected then NavTile.STROKE.selected else NavTile.STROKE.normal
end

return NavTile
