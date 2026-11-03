--!strict
--[[
	ObbySignFade (VisualsClient module)

	Fades out the obby's picture sign banners the local runner has walked past, on this client only, so a banner
	behind the runner never hangs between the third-person camera and them; it fades back in once they are before it
	again (a reset to the start, a walk back). Which banners hide is visuals/shared/ObbyBannerFade (course x of the
	root against each banner's rest x, Config.OBBY.BANNER_FADE). Outside the obby world every banner shows.

	A memory section's route fades the same way: every course part with an OBBY_REVEAL attribute (its course x line:
	Glow Memory's lit safe tiles hide at the entry sign, Remember It's clue board at the board) shows only while the
	local runner is before that line and hides once past it (Config.OBBY.ROUTE_REVEAL), so each runner sees the route
	until they pass it and gets it back after a fall or reset to the start. Other runners' views are their own.

	It finds the built course (ObbyCourseView) at most every FIND_EVERY seconds and caches each banner (a `banner`
	part with its SignGui), its course x and the shown transparency of the part, its booster adornments and every
	picture shape, so a frame without a fade in progress touches nothing. A banner stays a ghost (no collision, no
	queries) either way; its booster flames stop while it is hidden. `tick(dt)` runs once a frame; `start()` returns
	{ tick, stop } and `stop` shows every banner again.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Visuals = ReplicatedStorage:WaitForChild("Visuals")
local Constants = require(Shared:WaitForChild("Constants"))
local ObbyBannerFade = require(Visuals:WaitForChild("ObbyBannerFade"))
local ObbyLook = require(Visuals:WaitForChild("ObbyLook"))

local ObbySignFade = {}

ObbySignFade.FIND_EVERY = 0.5 -- seconds between looks for a (re)built course
ObbySignFade.BANNER = "banner" -- the banner look's part name (visuals/shared/ObbyParts)
ObbySignFade.GUI = "SignGui"

type Prop = { inst: any, key: string, base: number }
type Banner = {
	part: BasePart,
	x: number,
	tune: ObbyBannerFade.Tune,
	hidden: boolean,
	alpha: number,
	props: { Prop },
	guis: { SurfaceGui },
	flames: { ParticleEmitter },
}

export type Controller = { tick: (dt: number) -> (), stop: () -> () }

-- Every transparency the banner draws with, at its shown value.
local function propsOf(part: BasePart): ({ Prop }, { SurfaceGui }, { ParticleEmitter })
	local props: { Prop } = { { inst = part, key = "Transparency", base = part.Transparency } }
	local guis: { SurfaceGui } = {}
	local flames: { ParticleEmitter } = {}
	local function add(inst: any, key: string)
		table.insert(props, { inst = inst, key = key, base = inst[key] })
	end
	for _, d in part:GetDescendants() do
		if d:IsA("HandleAdornment") or d:IsA("UIStroke") then
			add(d, "Transparency")
		elseif d:IsA("GuiObject") then
			add(d, "BackgroundTransparency")
			if d:IsA("TextLabel") or d:IsA("TextButton") or d:IsA("TextBox") then
				add(d, "TextTransparency")
				add(d, "TextStrokeTransparency")
			elseif d:IsA("ImageLabel") or d:IsA("ImageButton") then
				add(d, "ImageTransparency")
			end
		elseif d:IsA("SurfaceGui") then
			table.insert(guis, d)
		elseif d:IsA("ParticleEmitter") then
			table.insert(flames, d)
		end
	end
	return props, guis, flames
end

-- The course's banners and route parts, their course x from `frame` (the Course model's ObbyFrame).
local function scan(course: Instance, frame: CFrame): { Banner }
	local out: { Banner } = {}
	for _, child in course:GetChildren() do
		if not child:IsA("BasePart") then
			continue
		end
		local x: number?, tune = nil, ObbyBannerFade.BANNER
		local reveal = child:GetAttribute(Constants.OBBY_REVEAL)
		if type(reveal) == "number" then
			x, tune = reveal, ObbyBannerFade.ROUTE
		elseif child.Name == ObbySignFade.BANNER and child:FindFirstChild(ObbySignFade.GUI) then
			local base = child:GetAttribute(Constants.OBBY_BASE)
			local at = if typeof(base) == "CFrame" then base.Position else child.Position
			x = frame:PointToObjectSpace(at).X
		end
		if x then
			local props, guis, flames = propsOf(child)
			table.insert(out, {
				part = child,
				x = x,
				tune = tune,
				hidden = false,
				alpha = 0,
				props = props,
				guis = guis,
				flames = flames,
			})
		end
	end
	return out
end

local function paint(b: Banner)
	for _, p in b.props do
		p.inst[p.key] = ObbyBannerFade.transparency(p.base, b.alpha)
	end
	local drawn = b.alpha < 1
	for _, gui in b.guis do
		if gui.Enabled ~= drawn then
			gui.Enabled = drawn
		end
	end
end

local function localRoot(): BasePart?
	local character = Players.LocalPlayer and Players.LocalPlayer.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	return if root and root:IsA("BasePart") then root else nil
end

function ObbySignFade.start(): Controller
	local course: Instance? = nil
	local frame = CFrame.identity
	local banners: { Banner } = {}
	local nextFind = 0

	local function showAll()
		for _, b in banners do
			if b.part.Parent ~= nil and (b.alpha ~= 0 or b.hidden) then
				b.alpha, b.hidden = 0, false
				paint(b)
				for _, f in b.flames do
					f.Enabled = true
				end
			end
		end
	end

	local function tick(dt: number)
		if course == nil or course.Parent == nil then
			local clock = os.clock()
			if clock < nextFind then
				return
			end
			nextFind = clock + ObbySignFade.FIND_EVERY
			local folder = workspace:FindFirstChild(Constants.OBBY_FOLDER)
			local found = folder and folder:FindFirstChild(Constants.OBBY_COURSE)
			banners = {}
			course = found
			if not found then
				return
			end
			local frameAttr = found:GetAttribute(Constants.OBBY_FRAME)
			frame = if typeof(frameAttr) == "CFrame" then frameAttr else CFrame.identity
			banners = scan(found, frame)
		end
		if #banners == 0 then
			return
		end
		local root = if ObbyLook.isInside() then localRoot() else nil
		local rootX = if root then frame:PointToObjectSpace(root.Position).X else nil
		for _, b in banners do
			local hidden = ObbyBannerFade.hidden(b.hidden, rootX, b.x, b.tune)
			if hidden ~= b.hidden then
				b.hidden = hidden
				for _, f in b.flames do
					f.Enabled = not hidden
				end
			end
			local alpha = ObbyBannerFade.step(b.alpha, hidden, dt, b.tune)
			if alpha ~= b.alpha then
				b.alpha = alpha
				paint(b)
			elseif alpha > 0 and b.part.Transparency ~= ObbyBannerFade.transparency(b.props[1].base, alpha) then
				paint(b) -- ObbyFx puts a part back at rest on a reset; keep this runner's fade
			end
		end
	end

	return {
		tick = tick,
		stop = function()
			showAll()
			banners = {}
			course = nil
		end,
	}
end

return ObbySignFade
