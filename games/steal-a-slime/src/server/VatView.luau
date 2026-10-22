--!strict
--[[
	VatView (CONTRACT.md §21)

	How a plot's merge vat looks in the world, from the owner's `data.vat` (VatState):
	  * each slime in the vat sits as a small copy on one of the vat's three spots (no prompts, no collision);
	  * its own pad model stays and turns see-through (VatView.FADE), so the pad stays taken;
	  * the pad sign and floating tag say "In vat" while it waits and "IN VAT" while it brews (`labelStatus`);
	  * a tag over the vat: "Merge vat" and a pill with the load, the time left or "Ready" (`tagLine`).
	A slime a thief is carrying away leaves its spot. `tagLine`, `labelStatus` and `spotOffset` are pure
	(tests/VatView.spec.luau); `sync` makes the plot match and only touches Roblox APIs when called.
]]

local Shared = if script then (game:GetService("ReplicatedStorage") :: any).Shared else nil
local Genome = if Shared then require(Shared.Genome) else require("../shared/Genome")
local GooPalette = if Shared then require(Shared.GooPalette) else require("../shared/GooPalette")
local VatState = if Shared then require(Shared.VatState) else require("../shared/VatState")
local StealGhost = if script then require(script.Parent.StealGhost) else require("./StealGhost")

local VatView = {}

VatView.FADE = 0.6 -- extra transparency on a pad slime whose real self is in the vat
VatView.SPOT_WIDTH = 1.6 -- studs: the widest side of a slime on a vat spot (pad slimes are about 2.6)
VatView.SPOT_RADIUS = 2.2 -- studs from the vat's centre to each spot
VatView.SPOT_LIFT = 0.15 -- studs above the goo
VatView.TAG_NAME = "VatTag"
VatView.SPOTS_NAME = "VatSpots"
VatView.FADED_ATTRIBUTE = "VatFaded" -- on a faded part: its own transparency before the fade
VatView.TAG = table.freeze({ w = 220, h = 74, title = 30, titleSize = 26, gap = 4, line = 30, lineSize = 20, lift = 2 })

export type Line = { text: string, color: "Mint" | "Gold" | "MutedWell" }

-- What the vat's pill says at server time `now`.
function VatView.tagLine(data: any, now: number): Line
	local ids = VatState.ids(data)
	if VatState.isBrewing(data) then
		if VatState.isReady(data, now) then
			return { text = "Ready", color = "Gold" }
		end
		local s = math.max(0, math.ceil(VatState.timeLeft(data, now)))
		return { text = string.format("Brewing %d:%02d", s // 60, s % 60), color = "Mint" }
	end
	local tier = VatState.tier(data)
	if not tier then
		return { text = "Move slimes in", color = "MutedWell" }
	end
	return { text = `{#ids}/{VatState.SIZE} {Genome.rarity(tier).name}`, color = "Mint" }
end

-- The status line of a pad slime that is in the vat (it replaces the income line on its sign and tag); nil otherwise.
function VatView.labelStatus(data: any, id: string): string?
	if not VatState.contains(data, id) then
		return nil
	end
	return if VatState.isBrewing(data) then "IN VAT" else "In vat"
end

-- Spot `i`'s offset from the vat's centre on the goo (x, z), the three spots in a triangle.
function VatView.spotOffset(i: number): (number, number)
	local angle = math.rad(90 + (i - 1) * 120)
	return math.cos(angle) * VatView.SPOT_RADIUS, math.sin(angle) * VatView.SPOT_RADIUS
end

local function rgb(c: { number }): Color3
	return Color3.fromRGB(c[1], c[2], c[3])
end

local function stroke(parent: Instance, color: Color3, thickness: number, transparency: number, contextual: boolean)
	local s = Instance.new("UIStroke")
	s.Color = color
	s.Thickness = thickness
	s.Transparency = transparency
	s.ApplyStrokeMode = if contextual then Enum.ApplyStrokeMode.Contextual else Enum.ApplyStrokeMode.Border
	s.LineJoinMode = Enum.LineJoinMode.Round
	s.Parent = parent
end

-- The vat's top centre: the vat mesh's top when it has one, else the disc's.
local function vatTop(vat: BasePart): CFrame
	local mesh = vat:FindFirstChild("VatMesh")
	if mesh and mesh:IsA("BasePart") then
		return CFrame.new(mesh.Position + Vector3.new(0, mesh.Size.Y / 2, 0))
	elseif mesh and mesh:IsA("Model") then
		local box, size = mesh:GetBoundingBox()
		return CFrame.new(box.Position + Vector3.new(0, size.Y / 2, 0))
	end
	return CFrame.new(vat.Position + Vector3.new(0, vat.Size.Y / 2, 0))
end

local function buildTag(vat: BasePart): BillboardGui
	local T = VatView.TAG
	local gui = Instance.new("BillboardGui")
	gui.Name = VatView.TAG_NAME
	gui.Adornee = vat
	gui.Size = UDim2.fromOffset(T.w, T.h)
	gui.SizeOffset = Vector2.new(0, 0.5)
	gui.StudsOffsetWorldSpace = Vector3.new(0, vatTop(vat).Position.Y - vat.Position.Y + T.lift, 0)
	gui.MaxDistance = 120
	gui.LightInfluence = 0
	local head = Instance.new("TextLabel")
	head.Name = "Title"
	head.BackgroundTransparency = 1
	head.Size = UDim2.new(1, 0, 0, T.title)
	head.Font = Enum.Font.FredokaOne
	head.TextSize = T.titleSize
	head.TextColor3 = rgb(GooPalette.White)
	head.Text = "Merge vat"
	stroke(head, rgb(GooPalette.Ink), 2.5, 0, true)
	head.Parent = gui
	local pill = Instance.new("TextLabel")
	pill.Name = "Line"
	pill.AnchorPoint = Vector2.new(0.5, 0)
	pill.Position = UDim2.new(0.5, 0, 0, T.title + T.gap)
	pill.Size = UDim2.fromOffset(0, T.line)
	pill.AutomaticSize = Enum.AutomaticSize.X
	pill.BackgroundColor3 = rgb(GooPalette.Ink)
	pill.Font = Enum.Font.FredokaOne
	pill.TextSize = T.lineSize
	local c = Instance.new("UICorner")
	c.CornerRadius = UDim.new(1, 0)
	c.Parent = pill
	stroke(pill, rgb(GooPalette.Mint), 2, 0.55, false)
	local pad = Instance.new("UIPadding")
	pad.PaddingLeft = UDim.new(0, 14)
	pad.PaddingRight = UDim.new(0, 14)
	pad.Parent = pill
	pill.Parent = gui
	gui.Parent = vat
	return gui
end

-- Fades (or restores) every part of a pad slime model. The part's own transparency is kept in an attribute.
function VatView.fade(model: Model, on: boolean)
	for _, d in model:GetDescendants() do
		if d:IsA("BasePart") or d:IsA("Decal") then
			local inst = d :: any
			local saved = d:GetAttribute(VatView.FADED_ATTRIBUTE)
			if on and saved == nil then
				d:SetAttribute(VatView.FADED_ATTRIBUTE, inst.Transparency)
				inst.Transparency = StealGhost.fade(inst.Transparency, VatView.FADE)
			elseif not on and type(saved) == "number" then
				inst.Transparency = saved
				d:SetAttribute(VatView.FADED_ATTRIBUTE, nil)
			end
		end
	end
end

-- A small copy of a pad slime for a vat spot (no prompts, labels or collision; the pad fade undone).
local function spotCopy(model: Model, at: CFrame, parent: Instance, id: string): Model
	local copy = StealGhost.build(model, at, parent, 0)
	copy.Name = id
	for _, d in copy:GetDescendants() do
		local saved = d:GetAttribute(VatView.FADED_ATTRIBUTE)
		if type(saved) == "number" then
			(d :: any).Transparency = saved
			d:SetAttribute(VatView.FADED_ATTRIBUTE, nil)
		end
	end
	local size = copy:GetExtentsSize()
	local widest = math.max(size.X, size.Z, 0.01)
	copy:ScaleTo(copy:GetScale() * VatView.SPOT_WIDTH / widest)
	local box, scaled = copy:GetBoundingBox()
	copy:PivotTo(copy:GetPivot() + (at.Position - box.Position) + Vector3.new(0, scaled.Y / 2, 0))
	return copy
end

export type PlotCache = { spots: { [number]: { id: string, model: Model } }, faded: { [string]: Model } }

local caches: { [number]: PlotCache } = {}

--[[
	Makes plot `plotIndex`'s vat match `data` (nil = a free plot). `modelOf(id)` gives a pad slime's model;
	`carried[id]` marks slimes a thief is carrying away.
]]
function VatView.sync(
	plot: Instance,
	plotIndex: number,
	data: any?,
	now: number,
	modelOf: (id: string) -> Model?,
	carried: { [string]: any }
)
	local vat = plot:FindFirstChild("MergeVat")
	if not vat or not vat:IsA("BasePart") then
		return
	end
	local cache = caches[plotIndex]
	if not cache then
		cache = { spots = {}, faded = {} }
		caches[plotIndex] = cache
	end
	local ids: { string } = if data then VatState.ids(data) else {}
	local inVat: { [string]: boolean } = {}
	for _, id in ids do
		inVat[id] = true
	end

	-- See-through pad copies.
	for id, model in cache.faded do
		if not inVat[id] or modelOf(id) ~= model then
			if model.Parent then
				VatView.fade(model, false)
			end
			cache.faded[id] = nil
		end
	end
	for _, id in ids do
		local model = modelOf(id)
		if model and not cache.faded[id] and not carried[id] then
			VatView.fade(model, true)
			cache.faded[id] = model
		elseif model and cache.faded[id] and carried[id] then
			VatView.fade(model, false)
			cache.faded[id] = nil
		end
	end

	-- Small slimes on the spots.
	local folder = vat:FindFirstChild(VatView.SPOTS_NAME)
	if not folder then
		local made = Instance.new("Folder")
		made.Name = VatView.SPOTS_NAME
		made.Parent = vat
		folder = made
	end
	local top = vatTop(vat)
	for i = 1, VatState.SIZE do
		local id = ids[i]
		local have = cache.spots[i]
		local wants = id ~= nil and not carried[id]
		if have and (not wants or have.id ~= id or not have.model.Parent) then
			have.model:Destroy()
			cache.spots[i] = nil
		end
		if wants and cache.spots[i] == nil then
			local source = modelOf(id :: string)
			if source then
				local x, z = VatView.spotOffset(i)
				local at = top * CFrame.new(x, VatView.SPOT_LIFT, z)
				cache.spots[i] = { id = id :: string, model = spotCopy(source, at, folder :: Instance, id :: string) }
			end
		end
	end

	-- The tag over the vat.
	local tag = vat:FindFirstChild(VatView.TAG_NAME) or buildTag(vat)
	local line = (tag :: Instance):FindFirstChild("Line") :: TextLabel?
	if line then
		local view = if data then VatView.tagLine(data, now) else { text = "", color = "MutedWell" }
		line.Text = view.text
		line.Visible = view.text ~= ""
		line.TextColor3 = rgb((GooPalette :: any)[view.color])
	end
	(tag :: BillboardGui).Enabled = data ~= nil
end

return VatView
