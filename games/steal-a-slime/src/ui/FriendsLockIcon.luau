--!strict
--[[
	FriendsLockIcon

	Shows everyone which locked bases let friends in (FEATURES.FriendsInBase, plot attribute FriendsAllowed): a
	sticker with the friend bonus icon (ItemIcons "Boost_Friend": two slimes high-fiving with a heart), a white disc
	with a pink ring, on the outer face of the shut door while the base is locked. It is what a friend walking up the
	bridge looks at. It sits on the door's look (StopperShut.Mesh), so it swings with the door; until that mesh lands
	it sits on the doorway's collider (LockBarrier.Stopper).

	With the switch off, or the base open, nothing shows. The gui lives in PlayerGui with an Adornee in the plot, so
	nothing in the shared world changes. Event driven: plot attribute changes and the door mesh landing, no frame
	loop. `start` returns a stop function that removes everything it made.
]]

local ItemIconView = require(script.Parent.ItemIconView)
local Widgets = require(script.Parent.Widgets)

local Theme = Widgets.Theme
local create = Widgets.create

local FriendsLockIcon = {}

FriendsLockIcon.ICON = "Boost_Friend"
FriendsLockIcon.FOLDER = "FriendsLockIcons"
FriendsLockIcon.SIZE = table.freeze({
	stickerStuds = 3.2, -- the sticker's square on the door face
	stickerPixelsPerStud = 50,
	stickerMaxDistance = 120,
	settleSeconds = 1, -- after a lock / open, longer than the door's swing (DoorSwing.TIMING)
	ring = 0.07, -- ring thickness, fraction of the disc
	icon = 0.78, -- icon size, fraction of the disc
})

-- Whether a plot shows the sticker for its FriendsAllowed / Locked attributes.
function FriendsLockIcon.shown(friendsAllowed: any, locked: any): boolean
	return friendsAllowed == true and locked == true
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

-- The part the sticker goes on: the shut door's mesh, else the doorway's collider before the mesh lands.
function FriendsLockIcon.doorOf(plot: Instance): BasePart?
	local slot = plot:FindFirstChild("StopperShut")
	local mesh = slot and slot:FindFirstChild("Mesh")
	if mesh and mesh:IsA("BasePart") then
		return mesh
	end
	local barrier = plot:FindFirstChild("LockBarrier")
	local stopper = barrier and barrier:FindFirstChild("Stopper")
	return if stopper and stopper:IsA("BasePart") then stopper else nil
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
	type Entry = { sticker: SurfaceGui?, conns: { RBXScriptConnection } }
	local entries: { [Instance]: Entry } = {}

	-- Puts `gui` on the face of the plot's door that looks out of the plot (the door is at the plot's -Z). False when
	-- the door or the plot's Base hasn't streamed in.
	local function stick(plot: Instance, gui: SurfaceGui): boolean
		local door = FriendsLockIcon.doorOf(plot)
		local base = plot:FindFirstChild("Base")
		if not (door and base and base:IsA("BasePart")) then
			return false
		end
		gui.Adornee = door
		-- The face is the mesh's own, so it holds through a swing; one picked while the door is mid-swing (LockMotion)
		-- is corrected once the door stops (SIZE.settleSeconds).
		gui.Face = FriendsLockIcon.faceToward(door, base.CFrame:VectorToWorldSpace(Vector3.new(0, 0, -1)))
		return true
	end

	local function stickerFor(plot: Instance): SurfaceGui?
		local gui = create("SurfaceGui", {
			Name = `{plot.Name}_Sticker`,
			SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud,
			PixelsPerStud = S.stickerPixelsPerStud,
			LightInfluence = 0,
			MaxDistance = S.stickerMaxDistance,
			AlwaysOnTop = false,
			Enabled = false,
			Parent = folder,
		}) :: SurfaceGui
		if not stick(plot, gui) then
			gui:Destroy()
			return nil
		end
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
		if shown and not entry.sticker then
			entry.sticker = stickerFor(plot)
		end
		local sticker = entry.sticker
		if sticker then
			sticker.Enabled = shown and stick(plot, sticker)
		end
	end

	local function track(plot: Instance)
		if entries[plot] or not plot:IsA("Model") then
			return
		end
		local entry: Entry = { sticker = nil, conns = {} }
		entries[plot] = entry
		for _, name in { opts.attributes.friendsAllowed, opts.attributes.locked } do
			table.insert(
				entry.conns,
				plot:GetAttributeChangedSignal(name):Connect(function()
					apply(plot)
					-- Again once the door has stopped: a lock can start while it is still swinging open.
					task.delay(S.settleSeconds, function()
						if entries[plot] == entry then
							apply(plot)
						end
					end)
				end)
			)
		end
		-- The door's mesh (or its whole slot) lands (MeshSwap) or comes back after a base swap: move the sticker onto it.
		table.insert(
			entry.conns,
			plot.DescendantAdded:Connect(function(d)
				if d.Name == "StopperShut" or (d.Name == "Mesh" and d.Parent and d.Parent.Name == "StopperShut") then
					apply(plot)
				end
			end)
		)
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
