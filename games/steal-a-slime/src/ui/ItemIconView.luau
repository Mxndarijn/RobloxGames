--!strict
--[[
	ItemIconView

	Draws one ItemIcons spec as a square icon, the same everywhere items show
	(shop rows, codes, goals, appraise ...):

	  * a rounded tile: vertical gradient in the item's colour, a darker
	    stroke and a bold glyph. Always built; it is the placeholder and the
	    backdrop of the other two;
	  * a UI-drawn scene (ItemIconArt) for specs with source "drawn" (and as the
	    fallback of a model spec that has a recipe): static
	    frames over the tile, no viewport, outside the live cap;
	  * an ImageLabel when the spec has an uploaded `image`;
	  * a ViewportFrame with the real 3D model (a
	    kit mesh) when the spec has a `model`. Live viewports are lazy (only
	    while `setActive(true)`: the owner calls it when the icon is on
	    screen), capped at MAX_LIVE at once across the whole UI (the extra
	    icons keep the tile) and released on setActive(false) / destroy, so a
	    long list never holds more than the cap. A failing builder falls back
	    to image, then tile.
]]

local ItemIconArt = require(script.Parent.ItemIconArt)
local SlimePreview = require(script.Parent.SlimePreview)
local Widgets = require(script.Parent.Widgets)

local create = Widgets.create

local ItemIconView = {}

-- At most this many ViewportFrames render item models at once, all icons together.
ItemIconView.MAX_LIVE = 12

-- builder(viewport, spec) -> mounted. Tests and init.client swap these.
ItemIconView.builders = {
	mesh = function(): boolean
		return false -- ItemIconView.meshBuilder(MeshAssets) from init.client
	end,
} :: { [string]: (Instance, any) -> boolean }

local live = 0

function ItemIconView.liveCount(): number
	return live
end

-- Test hook: forget live viewports (a test that leaks handles).
function ItemIconView.resetLive()
	live = 0
end

local function rgb(c: { number }): Color3
	return Color3.fromRGB(c[1], c[2], c[3])
end

-- Mesh builder over MeshAssets (name -> meshId) and AssetService; false when
-- the mesh is not uploaded or fails to load, so the icon keeps its tile.
function ItemIconView.meshBuilder(meshAssets: any, assetService: any): (Instance, any) -> boolean
	local templates: { [string]: any } = {}
	return function(viewport: Instance, spec: any): boolean
		local meshId = meshAssets.meshId(spec.model.mesh)
		if not meshId then
			return false
		end
		local template = templates[meshId]
		if template == nil then
			local ok, result = pcall(function()
				return assetService:CreateMeshPartAsync(meshId)
			end)
			template = if ok and result then result else false
			templates[meshId] = template
		end
		if not template then
			return false
		end
		local model = Instance.new("Model")
		local part = template:Clone()
		part.Anchored = true
		part.Parent = model
		model.PrimaryPart = part
		return SlimePreview.mountModel(viewport, model, nil)
	end
end

-- props: Name, Size (square px, default 48), Position, AnchorPoint, ZIndex, Parent, LayoutOrder.
-- `registry` is ItemIcons.build(Config). Returns the handle.
function ItemIconView.new(props: { [string]: any }, registry: any)
	local size: number = props.Size or 48
	local z: number = props.ZIndex or 1
	local root = create("Frame", {
		Name = props.Name or "ItemIcon",
		Size = UDim2.fromOffset(size, size),
		Position = props.Position,
		AnchorPoint = props.AnchorPoint,
		LayoutOrder = props.LayoutOrder or 0,
		BackgroundTransparency = 1,
		ZIndex = z,
	})
	local tile = create("Frame", {
		Name = "Tile",
		Size = UDim2.fromScale(1, 1),
		BackgroundColor3 = Color3.new(1, 1, 1),
		ZIndex = z,
		Parent = root,
	}, { Widgets.corner(math.max(4, math.floor(size * 0.22))) })
	local gradient = create("UIGradient", { Rotation = 90, Parent = tile })
	local stroke = Widgets.stroke(Color3.new(0, 0, 0), size >= 40 and 2 or 1)
	stroke.Parent = tile
	local glyph = Widgets.label({
		Name = "Glyph",
		Font = Widgets.Theme.Font,
		TextSize = math.floor(size * 0.52),
		TextXAlignment = Enum.TextXAlignment.Center,
		TextTruncate = Enum.TextTruncate.None,
		TextColor3 = Color3.new(1, 1, 1),
		TextStrokeColor3 = Color3.new(0, 0, 0),
		TextStrokeTransparency = 0.55,
		Size = UDim2.fromScale(1, 1),
		ZIndex = z + 1,
		Parent = tile,
	})
	local art = create("Frame", {
		Name = "Art",
		BackgroundTransparency = 1,
		Size = UDim2.fromScale(1, 1),
		Visible = false,
		ZIndex = z + 1,
		Parent = root,
	})
	local picture = create("ImageLabel", {
		Name = "Picture",
		BackgroundTransparency = 1,
		Size = UDim2.fromScale(1, 1),
		ScaleType = Enum.ScaleType.Fit,
		Visible = false,
		ZIndex = z + 2,
		Parent = root,
	})
	local viewport = create("ViewportFrame", {
		Name = "Preview",
		BackgroundTransparency = 1,
		Size = UDim2.fromScale(1, 1),
		Visible = false,
		ZIndex = z + 2,
		Parent = root,
	})
	if props.Parent then
		root.Parent = props.Parent
	end

	local self: any = { instance = root, tile = tile, glyph = glyph, picture = picture, art = art, viewport = viewport }
	local spec: any = registry.resolve(nil)
	local active = false
	local mounted = false
	local frameColor: Color3? = nil

	local function unmount()
		if mounted then
			SlimePreview.unmount(viewport)
			mounted = false
			live -= 1
		end
		viewport.Visible = false
	end

	local function refresh()
		local model = spec.model
		local image = spec.image
		-- The picture is the icon (and the fallback of a model that is not mounted); a working model sits above it.
		if image then
			picture.Image = `rbxassetid://{image}`
		end
		-- A real picture carries its own shading: the colour tile behind it only whispers.
		tile.BackgroundTransparency = if image then 0.82 else 0
		stroke.Transparency = if image then 0.7 else 0
		-- A drawn scene is the icon for "drawn" specs and the fallback of a model that is not mounted.
		local drawn = image == nil and art:GetAttribute("ArtId") == spec.id
		art.Visible = drawn
		glyph.Visible = image == nil and not drawn
		if model and active then
			if not mounted and live < ItemIconView.MAX_LIVE then
				local builder = ItemIconView.builders[model.kind]
				local ok = builder ~= nil and builder(viewport, spec)
				if ok then
					mounted = true
					live += 1
				end
			end
		elseif mounted then
			unmount()
		end
		viewport.Visible = mounted
		picture.Visible = image ~= nil and not mounted
		if mounted then
			glyph.Visible = false
			art.Visible = false
		end
		self.source = if mounted then "model" elseif image then "image" elseif drawn then "drawn" else "placeholder"
	end

	function self.set(id: string?)
		unmount()
		spec = registry.resolve(id)
		local c = rgb(spec.color)
		gradient.Color = ColorSequence.new(c:Lerp(Color3.new(1, 1, 1), 0.25), c:Lerp(Color3.new(0, 0, 0), 0.3))
		stroke.Color = frameColor or c:Lerp(Color3.new(0, 0, 0), 0.55)
		glyph.Text = spec.glyph
		root:SetAttribute("ItemId", spec.id)
		art:ClearAllChildren()
		art:SetAttribute("ArtId", nil)
		if
			spec.image == nil
			and (spec.source == "drawn" or spec.model ~= nil)
			and ItemIconArt.draw(art, spec.id, z + 1)
		then
			art:SetAttribute("ArtId", spec.id)
		end
		self.spec = spec
		refresh()
	end

	-- Overrides the tile stroke colour (nil = the item's own darker tint).
	function self.setFrame(color: Color3?)
		frameColor = color
		stroke.Color = color or rgb(spec.color):Lerp(Color3.new(0, 0, 0), 0.55)
	end

	function self.setActive(on: boolean)
		if on ~= active then
			active = on
			refresh()
		end
	end

	function self.destroy()
		unmount()
		root:Destroy()
	end

	self.set(props.Id)
	return self
end

return ItemIconView
