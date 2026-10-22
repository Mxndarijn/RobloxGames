--!strict
--[[
	FriendsLockIcon

	Shows everyone which bases let friends in (FEATURES.FriendsInBase, plot attribute FriendsAllowed), with the
	friend bonus icon (ItemIcons "Boost_Friend": two slimes high-fiving with a heart):

	  * Sticker: on the outer face of the shut stopper (LockBarrier.Stopper, the doorway's collider), a white disc
	    with a pink ring, while the base is locked. It is what a friend walking up the bridge looks at.
	  * Badge: a small goo-glass disc floating over the LockButton, while the switch is on (locked or not).

	With the switch off both are hidden, so a normal base looks as it always did. The guis live in PlayerGui with
	an Adornee in the plot, so nothing in the shared world changes. Event driven: plot attribute changes only, no
	frame loop. `start` returns a stop function that removes everything it made.
]]

local ItemIconView = require(script.Parent.ItemIconView)
local Widgets = require(script.Parent.Widgets)

local Theme = Widgets.Theme
local create = Widgets.create

local FriendsLockIcon = {}

FriendsLockIcon.ICON = "Boost_Friend"
FriendsLockIcon.FOLDER = "FriendsLockIcons"
FriendsLockIcon.SIZE = table.freeze({
	stickerStuds = 3.2, -- the sticker's square on the stopper face
	stickerPixelsPerStud = 50,
	badgeStuds = 2.2, -- the floating badge's square
	badgeLift = 4.5, -- studs above the LockButton's top
	badgeMaxDistance = 70, -- studs: hidden beyond
	stickerMaxDistance = 120,
	ring = 0.07, -- ring thickness, fraction of the disc
	icon = 0.78, -- icon size, fraction of the disc
})

export type Shown = { sticker: boolean, badge: boolean }

-- What a plot shows for its FriendsAllowed / Locked attributes.
function FriendsLockIcon.shown(friendsAllowed: any, locked: any): Shown
	local on = friendsAllowed == true
	return { sticker = on and locked == true, badge = on }
end

-- The face of `part` that points most along `direction` (world space).
function FriendsLockIcon.faceToward(part: BasePart, direction: Vector3): Enum.NormalId
	local faces = {
		{ face = Enum.NormalId.Front, normal = Vector3.new(0, 0, -1) },
		{ face = Enum.NormalId.Back, normal = Vector3.new(0, 0, 1) },
		{ face = Enum.NormalId.Right, normal = Vector3.new(1, 0, 0) },
		{ face = Enum.NormalId.Left, normal = Vector3.new(-1, 0, 0) },
		{ face = Enum.NormalId.Top, normal = Vector3.new(0, 1, 0) },
		{ face = Enum.NormalId.Bottom, normal = Vector3.new(0, -1, 0) },
	}
	local best, bestDot = Enum.NormalId.Front, -math.huge
	for _, face in faces do
		local dot = part.CFrame:VectorToWorldSpace(face.normal):Dot(direction)
		if dot > bestDot then
			best, bestDot = face.face, dot
		end
	end
	return best
end

export type Options = {
	plots: Instance, -- workspace.Plots
	playerGui: Instance,
	registry: any, -- ItemIcons.build(Config)
	attributes: { friendsAllowed: string, locked: string }, -- Constants.PLOT_FRIENDS_ALLOWED_ATTRIBUTE / PLOT_LOCKED_ATTRIBUTE
}

-- A disc (ring colour, fill colour) with the friend icon in it, filling `parent`.
local function disc(parent: Instance, fill: Color3, ring: Color3, registry: any)
	local S = FriendsLockIcon.SIZE
	local outer = create("Frame", {
		Name = "Ring",
		BackgroundColor3 = ring,
		Size = UDim2.fromScale(1, 1),
		Parent = parent,
	}, { Widgets.pill() :: Instance })
	create("Frame", {
		Name = "Fill",
		BackgroundColor3 = fill,
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromScale(1 - S.ring * 2, 1 - S.ring * 2),
		Parent = outer,
	}, { Widgets.pill() :: Instance })
	local icon = ItemIconView.new({
		Name = "Icon",
		Id = FriendsLockIcon.ICON,
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		ZIndex = 2,
		Parent = outer,
	}, registry)
	icon.instance.Size = UDim2.fromScale(S.icon, S.icon)
	return icon
end

function FriendsLockIcon.start(opts: Options): () -> ()
	local S = FriendsLockIcon.SIZE
	local folder = create("Folder", { Name = FriendsLockIcon.FOLDER, Parent = opts.playerGui })
	type Entry = { sticker: SurfaceGui?, badge: BillboardGui?, conns: { RBXScriptConnection } }
	local entries: { [Instance]: Entry } = {}

	local function stickerFor(plot: Instance): SurfaceGui?
		local barrier = plot:FindFirstChild("LockBarrier")
		local stopper = barrier and barrier:FindFirstChild("Stopper")
		local base = plot:FindFirstChild("Base")
		if not (stopper and stopper:IsA("BasePart") and base and base:IsA("BasePart")) then
			return nil
		end
		-- The door is at the plot's -Z: the sticker goes on the stopper face that looks out of the plot.
		local out = base.CFrame:VectorToWorldSpace(Vector3.new(0, 0, -1))
		local gui = create("SurfaceGui", {
			Name = `{plot.Name}_Sticker`,
			Adornee = stopper,
			Face = FriendsLockIcon.faceToward(stopper, out),
			SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud,
			PixelsPerStud = S.stickerPixelsPerStud,
			LightInfluence = 0,
			MaxDistance = S.stickerMaxDistance,
			AlwaysOnTop = false,
			Enabled = false,
			Parent = folder,
		}) :: SurfaceGui
		local px = S.stickerStuds * S.stickerPixelsPerStud
		local holder = create("Frame", {
			Name = "Sticker",
			BackgroundTransparency = 1,
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.fromScale(0.5, 0.5),
			Size = UDim2.fromOffset(px, px),
			Parent = gui,
		})
		disc(holder, Color3.new(1, 1, 1), Theme.Bad, opts.registry)
		return gui
	end

	local function badgeFor(plot: Instance): BillboardGui?
		local button = plot:FindFirstChild("LockButton")
		if not (button and button:IsA("BasePart")) then
			return nil
		end
		local gui = create("BillboardGui", {
			Name = `{plot.Name}_Badge`,
			Adornee = button,
			Size = UDim2.fromScale(S.badgeStuds, S.badgeStuds),
			StudsOffsetWorldSpace = Vector3.new(0, button.Size.Y / 2 + S.badgeLift, 0),
			LightInfluence = 0,
			MaxDistance = S.badgeMaxDistance,
			AlwaysOnTop = false,
			Enabled = false,
			Parent = folder,
		}) :: BillboardGui
		disc(gui, Theme.Bg, Theme.Ink, opts.registry)
		return gui
	end

	local function apply(plot: Instance)
		local entry = entries[plot]
		if not entry then
			return
		end
		local shown = FriendsLockIcon.shown(
			plot:GetAttribute(opts.attributes.friendsAllowed),
			plot:GetAttribute(opts.attributes.locked)
		)
		-- Built on first need: the plot's parts may stream in after the plot model.
		if shown.sticker and not entry.sticker then
			entry.sticker = stickerFor(plot)
		end
		if shown.badge and not entry.badge then
			entry.badge = badgeFor(plot)
		end
		if entry.sticker then
			entry.sticker.Enabled = shown.sticker
		end
		if entry.badge then
			entry.badge.Enabled = shown.badge
		end
	end

	local function track(plot: Instance)
		if entries[plot] or not plot:IsA("Model") then
			return
		end
		local entry: Entry = { sticker = nil, badge = nil, conns = {} }
		entries[plot] = entry
		for _, name in { opts.attributes.friendsAllowed, opts.attributes.locked } do
			table.insert(
				entry.conns,
				plot:GetAttributeChangedSignal(name):Connect(function()
					apply(plot)
				end)
			)
		end
		apply(plot)
	end

	local function untrack(plot: Instance)
		local entry = entries[plot]
		if not entry then
			return
		end
		entries[plot] = nil
		for _, c in entry.conns do
			c:Disconnect()
		end
		if entry.sticker then
			entry.sticker:Destroy()
		end
		if entry.badge then
			entry.badge:Destroy()
		end
	end

	local conns = {
		opts.plots.ChildAdded:Connect(track),
		opts.plots.ChildRemoved:Connect(untrack),
	}
	for _, plot in opts.plots:GetChildren() do
		track(plot)
	end

	return function()
		for _, c in conns do
			c:Disconnect()
		end
		for plot in table.clone(entries) do
			untrack(plot)
		end
		folder:Destroy()
	end
end

return FriendsLockIcon
