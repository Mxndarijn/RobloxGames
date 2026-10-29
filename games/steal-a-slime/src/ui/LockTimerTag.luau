--!strict
--[[
	LockTimerTag

	Shows other players how long a locked base stays locked: a red goo pill "LOCKED 1:42" floating over each locked
	plot's LockButton (plot attributes OwnerUserId and LockUntil). The owner never sees it on their own base (they
	have the lock card).

	Seen through glass, not through walls: on every `tick` (the client's 10 Hz loop) a ray from the camera to the
	tag skips see-through parts (Transparency at least SEE_THROUGH: the jar glass, the drop tube) and characters, and
	anything else in between hides the tag. Past MAX_DISTANCE studs it is hidden too.

	The guis live in PlayerGui (Folder FOLDER) with the LockButton as Adornee, so nothing in the shared world changes.
	Pure helpers (shows, text, seeThrough) are tested under Lune (tests/ui/LockTimerTag.spec.luau); `start` returns
	{ tick, destroy }: `destroy` removes the tags.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local LabelFit = require(ReplicatedStorage:WaitForChild("Lib"):WaitForChild("ui"):WaitForChild("LabelFit"))
local NumberFormat = require(ReplicatedStorage:WaitForChild("Lib"):WaitForChild("core"):WaitForChild("NumberFormat"))
local SlimeKeyCard = require(script.Parent.SlimeKeyCard)
local Widgets = require(script.Parent.Widgets)

local Theme = Widgets.Theme
local create = Widgets.create

local LockTimerTag = {}

LockTimerTag.FOLDER = "LockTimerTags"
LockTimerTag.SEE_THROUGH = 0.3 -- a part at least this transparent doesn't hide the tag (glass)
LockTimerTag.MAX_DISTANCE = 90 -- studs: hidden beyond
LockTimerTag.PHONE_MAX_DISTANCE = 60 -- studs, on a phone-sized screen: several bases' timers stack up there
LockTimerTag.MAX_SKIPS = 8 -- see-through parts one sight ray may pass before it gives up (and hides the tag)
LockTimerTag.SIZE = table.freeze({
	w = 150,
	h = 44,
	textSize = 22,
	stroke = 3,
	lift = 1.5, -- studs above the LockButton's barrel
})

-- Whether player `me` sees a plot's timer: someone else's base with a lock still running.
function LockTimerTag.shows(ownerUserId: number?, me: number, lockUntil: number?, now: number): boolean
	return type(ownerUserId) == "number" and ownerUserId ~= 0 and ownerUserId ~= me and (lockUntil or 0) > now
end

-- The tag's text for `remaining` seconds of lock.
function LockTimerTag.text(remaining: number): string
	return `LOCKED {NumberFormat.clock(remaining)}`
end

-- Whether a part this transparent lets you see the tag through it (glass does, walls don't).
function LockTimerTag.seeThrough(transparency: number): boolean
	return transparency >= LockTimerTag.SEE_THROUGH
end

export type Options = {
	plots: Instance, -- workspace.Plots
	playerGui: Instance,
	me: number, -- the local player's UserId
	now: () -> number, -- server time (workspace:GetServerTimeNow)
	camera: () -> Camera?,
	characters: () -> { Instance }, -- every player's character, ignored by the sight ray
}

export type Handle = { tick: () -> (), destroy: () -> () }

type Tag = { gui: BillboardGui, label: TextLabel }

function LockTimerTag.start(opts: Options): Handle
	local folder = create("Folder", { Name = LockTimerTag.FOLDER, Parent = opts.playerGui })
	local tags: { [Instance]: Tag } = {}
	local S = LockTimerTag.SIZE

	local function tagFor(plot: Instance, button: BasePart): Tag
		local tag = tags[plot]
		if tag and tag.gui.Adornee == button then
			return tag
		end
		if tag then
			tag.gui:Destroy()
		end
		local gui = create("BillboardGui", {
			Name = `LockTimer_{plot.Name}`,
			Adornee = button,
			Size = UDim2.fromOffset(S.w, S.h),
			AlwaysOnTop = true, -- the sight ray decides what hides it, so glass doesn't wash it out
			MaxDistance = LockTimerTag.MAX_DISTANCE,
			LightInfluence = 0,
			Enabled = false,
			Parent = folder,
		})
		LabelFit.mark(gui, { phoneDistance = LockTimerTag.PHONE_MAX_DISTANCE })
		local pill = create("Frame", {
			Name = "Pill",
			BackgroundColor3 = Theme.Bad,
			Size = UDim2.fromScale(1, 1),
			Parent = gui,
		}, { Widgets.pill() :: Instance, Widgets.stroke(Theme.Ink, S.stroke) })
		Widgets.shade(pill)
		local label = Widgets.label({
			Name = "Time",
			Font = Theme.Font,
			TextSize = S.textSize,
			TextXAlignment = Enum.TextXAlignment.Center,
			Size = UDim2.fromScale(1, 1),
			ZIndex = 2,
			Parent = pill,
		})
		Widgets.inkOn(label, Theme.Bad)
		local made: Tag = { gui = gui, label = label }
		tags[plot] = made
		return made
	end

	-- True when nothing solid stands between the camera and `target` (see-through parts and `ignore` don't count).
	local function inSight(from: Vector3, target: Vector3, ignore: { Instance }): boolean
		local params = RaycastParams.new()
		params.FilterType = Enum.RaycastFilterType.Exclude
		local skip = table.clone(ignore)
		params.FilterDescendantsInstances = skip
		for _ = 1, LockTimerTag.MAX_SKIPS do
			local hit = workspace:Raycast(from, target - from, params)
			if not hit then
				return true
			end
			if not LockTimerTag.seeThrough(hit.Instance.Transparency) then
				return false
			end
			table.insert(skip, hit.Instance)
			params.FilterDescendantsInstances = skip
		end
		return false
	end

	local function update()
		local camera = opts.camera()
		local now = opts.now()
		local characters = opts.characters()
		for _, plot in opts.plots:GetChildren() do
			local button = plot:FindFirstChild("LockButton", true)
			local owner = plot:GetAttribute("OwnerUserId")
			local lockUntil = plot:GetAttribute("LockUntil")
			local show = button ~= nil
				and button:IsA("BasePart")
				and LockTimerTag.shows(
					if type(owner) == "number" then owner else nil,
					opts.me,
					if type(lockUntil) == "number" then lockUntil else nil,
					now
				)
			if not show then
				local tag = tags[plot]
				if tag then
					tag.gui.Enabled = false
				end
				continue
			end
			local part = button :: BasePart
			local tag = tagFor(plot, part)
			local others = if part.Parent then part.Parent:GetChildren() else {}
			local offset = SlimeKeyCard.offsetOver(part, others, S.lift)
			tag.gui.StudsOffsetWorldSpace = offset
			local text = LockTimerTag.text((lockUntil :: number) - now)
			if tag.label.Text ~= text then
				tag.label.Text = text
			end
			local visible = false
			if camera then
				local target = part.CFrame:PointToWorldSpace(offset)
				local from = camera.CFrame.Position
				if (target - from).Magnitude <= LockTimerTag.MAX_DISTANCE then
					local ignore = table.clone(characters)
					table.insert(ignore, part)
					table.insert(ignore, folder)
					visible = inSight(from, target, ignore)
				end
			end
			tag.gui.Enabled = visible
		end
	end

	return {
		tick = update,
		destroy = function()
			folder:Destroy()
			table.clear(tags)
		end,
	}
end

return LockTimerTag
