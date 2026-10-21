-- SlimeCam recorder / replayer (Client datamodel, run through execute_luau by tools/slimecam/capture.py).
-- Dev tool only: installs _G.SlimeCam. Records, every rendered frame, the exact pose of the slimes near the camera
-- (every part's CFrame, Size and LocalTransparencyModifier, every Bone's Transform, the tag anchor, the emote
-- bubbles), the local character and the camera. Then it replays: clones of the recorded models are posed frame by
-- frame (the live slimes are taken out of the world on this client), so screen_capture can grab each frame from
-- the real renderer, frame-perfect, however slow the capture is.
local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")

local cam = {}
_G.SlimeCam = cam

local recording = false
local frames = {} -- [k] = { camera = CFrame, fov = number, models = { [index] = pose } }
local tracked = {} -- list of { model, parts = { BasePart }, bones = { Bone }, kind = "slime" | "character" }
local byModel = {}
local radius = 70

local function partsOf(model)
	local parts, bones = {}, {}
	for _, d in model:GetDescendants() do
		if d:IsA("BasePart") then
			table.insert(parts, d)
		elseif d:IsA("Bone") then
			table.insert(bones, d)
		end
	end
	return parts, bones
end

local function track(model, kind)
	if byModel[model] then
		return byModel[model]
	end
	local parts, bones = partsOf(model)
	local t = { model = model, parts = parts, bones = bones, kind = kind, index = #tracked + 1 }
	table.insert(tracked, t)
	byModel[model] = t
	return t
end

local function emotesNow()
	-- SlimeEmotes: BillboardGuis in PlayerGui adorned to a slime's SkinRoot
	local out = {}
	local gui = Players.LocalPlayer:FindFirstChild("PlayerGui")
	if not gui then
		return out
	end
	for _, d in gui:GetDescendants() do
		if d:IsA("BillboardGui") and d.Enabled and d.Adornee then
			local label = d:FindFirstChildWhichIsA("TextLabel", true)
			if label and label.Text ~= "" then
				table.insert(out, { adornee = d.Adornee, offset = d.StudsOffset, text = label.Text })
			end
		end
	end
	return out
end

local function sample()
	local camera = workspace.CurrentCamera
	local cp = camera.CFrame.Position
	for _, m in CollectionService:GetTagged("Slime") do
		local body = m:IsA("Model") and (m.PrimaryPart or m:FindFirstChild("Body"))
		if body and (body.Position - cp).Magnitude < radius then
			track(m, "slime")
		end
	end
	local char = Players.LocalPlayer.Character
	if char then
		track(char, "character")
	end
	local L = game:GetService("Lighting")
	local f = { camera = camera.CFrame, fov = camera.FieldOfView, models = {}, emotes = {}, clock = L.ClockTime }
	for _, t in tracked do
		if t.model.Parent then
			local pose = { cf = {}, size = {}, ltm = {}, bone = {} }
			for i, p in t.parts do
				if p.Parent then
					pose.cf[i] = p.CFrame
					pose.size[i] = p.Size
					pose.ltm[i] = p.LocalTransparencyModifier
				end
			end
			for i, b in t.bones do
				pose.bone[i] = b.Transform
			end
			local body = t.model.PrimaryPart or t.model:FindFirstChild("Body")
			local anchor = body and body:FindFirstChild("TagAnchor")
			if anchor and anchor:IsA("Attachment") then
				pose.tag = anchor.WorldPosition
			elseif body then
				pose.tag = body.Position
			end
			pose.label = t.model:GetAttribute("LabelHeight")
			f.models[t.index] = pose
		end
	end
	for _, e in emotesNow() do
		local owner = e.adornee:FindFirstAncestorWhichIsA("Model")
		local t = owner and byModel[owner]
		if t then
			local idx = table.find(t.parts, e.adornee)
			if idx then
				table.insert(f.emotes, { model = t.index, part = idx, offset = e.offset, text = e.text })
			end
		end
	end
	table.insert(frames, f)
end

local conn
function cam.start(r)
	radius = r or radius
	frames, tracked, byModel = {}, {}, {}
	recording = true
	conn = RunService.RenderStepped:Connect(function()
		if recording then
			task.defer(sample)
		end
	end)
	return true
end

function cam.stop()
	recording = false
	if conn then
		conn:Disconnect()
		conn = nil
	end
	return #frames
end

-- Replay ------------------------------------------------------------------------------------------------------

local stage -- Folder of clones
local clones = {} -- [index] = { parts, bones, tag = Attachment, label = TextLabel }
local hidden = {} -- live slime models taken out on this client, with their parent
local guis = {}

local function strip(clone)
	for _, d in clone:GetDescendants() do
		if
			d:IsA("BaseScript")
			or d:IsA("ProximityPrompt")
			or d:IsA("JointInstance")
			or d:IsA("WeldConstraint")
			or d:IsA("BillboardGui")
			or d:IsA("SurfaceGui")
		then
			d:Destroy()
		elseif d:IsA("BasePart") then
			d.Anchored = true
			d.CanCollide = false
			d.CanQuery = false
			d.CanTouch = false
		end
	end
	for _, tag in CollectionService:GetTags(clone) do
		CollectionService:RemoveTag(clone, tag)
	end
end

local function makeTag(parent, text)
	local att = Instance.new("Attachment")
	att.Name = "CamTag"
	att.Parent = workspace.Terrain
	local gui = Instance.new("BillboardGui")
	gui.Size = UDim2.new(0, 160, 0, 36)
	gui.SizeOffset = Vector2.new(0, 0.5)
	gui.AlwaysOnTop = true
	gui.Adornee = att
	gui.Parent = parent
	local label = Instance.new("TextLabel")
	label.BackgroundTransparency = 1
	label.Size = UDim2.fromScale(1, 1)
	label.Font = Enum.Font.FredokaOne
	label.TextScaled = true
	label.TextColor3 = Color3.new(1, 1, 1)
	label.TextStrokeTransparency = 0.2
	label.Text = text
	label.Parent = gui
	return att, gui
end

function cam.prepare(opts)
	opts = opts or {}
	stage = Instance.new("Folder")
	stage.Name = "SlimeCamStage"
	stage.Parent = workspace
	-- the stand-in tags render from PlayerGui (a BillboardGui under a workspace Folder does not)
	local tagGuiParent = Instance.new("Folder")
	tagGuiParent.Name = "SlimeCamTags"
	tagGuiParent.Parent = Players.LocalPlayer:FindFirstChild("PlayerGui") or stage
	cam.tagFolder = tagGuiParent
	for _, t in tracked do
		local m = t.model
		for _, d in m:GetDescendants() do
			pcall(function()
				d.Archivable = true
			end)
		end
		m.Archivable = true
		local ok, clone = pcall(function()
			return m:Clone()
		end)
		if ok and clone then
			strip(clone)
			clone.Parent = stage
			local parts, bones = partsOf(clone)
			local entry = { parts = parts, bones = bones }
			if t.kind == "slime" and opts.tags ~= false then
				local name = m:GetAttribute("LabelName") or m:GetAttribute("Species") or ""
				entry.tag = makeTag(tagGuiParent, tostring(name))
			end
			clones[t.index] = entry
		end
		-- the live one leaves the world on this client while we replay
		if t.kind == "slime" and m.Parent then
			table.insert(hidden, { m, m.Parent })
			m.Parent = nil
		elseif t.kind == "character" then
			for _, p in t.parts do
				p.LocalTransparencyModifier = 1
			end
		end
	end
	-- every other live slime out too (they would walk through the shot), and any that spawns while we capture
	for _, m in CollectionService:GetTagged("Slime") do
		if m.Parent and not byModel[m] then
			table.insert(hidden, { m, m.Parent })
			m.Parent = nil
		end
	end
	cam.addedConn = CollectionService:GetInstanceAddedSignal("Slime"):Connect(function(m)
		task.defer(function()
			if m.Parent and not stage:IsAncestorOf(m) then
				table.insert(hidden, { m, m.Parent })
				m.Parent = nil
			end
		end)
	end)
	local pg = Players.LocalPlayer:FindFirstChild("PlayerGui")
	if pg and opts.ui ~= true then
		for _, g in pg:GetChildren() do
			if g:IsA("ScreenGui") and g.Enabled then
				g.Enabled = false
				table.insert(guis, g)
			end
		end
	end
	workspace.CurrentCamera.CameraType = Enum.CameraType.Scriptable
	cam.snapLight()
	return #frames
end

-- The look of the sky and light, frozen for the replay: weather / night scripts keep changing it while the slow
-- capture runs, which would flicker from frame to frame.
local LIGHT_PROPS = {
	Lighting = {
		"ClockTime",
		"Brightness",
		"Ambient",
		"OutdoorAmbient",
		"ColorShift_Top",
		"ColorShift_Bottom",
		"ExposureCompensation",
		"EnvironmentDiffuseScale",
		"EnvironmentSpecularScale",
		"FogColor",
		"FogEnd",
		"FogStart",
	},
	Atmosphere = { "Density", "Offset", "Color", "Decay", "Glare", "Haze" },
	ColorCorrectionEffect = { "Enabled", "Brightness", "Contrast", "Saturation", "TintColor" },
	BloomEffect = { "Enabled", "Intensity", "Size", "Threshold" },
	SunRaysEffect = { "Enabled", "Intensity", "Spread" },
	BlurEffect = { "Enabled", "Size" },
	DepthOfFieldEffect = { "Enabled", "FarIntensity", "FocusDistance", "InFocusRadius", "NearIntensity" },
	Clouds = { "Enabled", "Cover", "Density", "Color" },
	ParticleEmitter = { "Enabled" },
}
local lightSnap = {}
function cam.snapLight()
	lightSnap = {}
	local roots = { game:GetService("Lighting"), workspace.CurrentCamera, workspace.Terrain }
	local function take(inst)
		local props = LIGHT_PROPS[inst.ClassName]
		if inst == roots[1] then
			props = LIGHT_PROPS.Lighting
		end
		if props and not (inst.ClassName == "ParticleEmitter" and not inst:IsDescendantOf(workspace.CurrentCamera)) then
			local vals = {}
			for _, name in props do
				local ok, v = pcall(function()
					return (inst :: any)[name]
				end)
				if ok then
					vals[name] = v
				end
			end
			table.insert(lightSnap, { inst, vals })
		end
	end
	for _, root in roots do
		take(root)
		for _, d in root:GetDescendants() do
			take(d)
		end
	end
end
function cam.applyLight()
	for _, e in lightSnap do
		for name, v in e[2] do
			pcall(function()
				(e[1] :: any)[name] = v
			end)
		end
	end
end

local emoteGuis = {}
function cam.pose(k)
	local f = frames[k]
	if not f then
		return false
	end
	for index, entry in clones do
		local pose = f.models[index]
		local present = pose ~= nil
		for i, p in entry.parts do
			if present and pose.cf[i] then
				p.CFrame = pose.cf[i]
				p.Size = pose.size[i]
				p.LocalTransparencyModifier = pose.ltm[i]
			else
				p.LocalTransparencyModifier = 1
			end
		end
		if present then
			for i, b in entry.bones do
				if pose.bone[i] then
					b.Transform = pose.bone[i]
				end
			end
		end
		if entry.tag then
			if present and pose.tag then
				entry.tag.WorldPosition = pose.tag + Vector3.new(0, pose.label or 2.5, 0)
			else
				entry.tag.WorldPosition = Vector3.new(0, -1000, 0)
			end
		end
	end
	for _, g in emoteGuis do
		g:Destroy()
	end
	table.clear(emoteGuis)
	for _, e in f.emotes do
		local entry = clones[e.model]
		local part = entry and entry.parts[e.part]
		if part then
			local gui = Instance.new("BillboardGui")
			gui.Size = UDim2.new(0, 46, 0, 46)
			gui.StudsOffset = e.offset
			gui.AlwaysOnTop = true
			gui.Adornee = part
			local label = Instance.new("TextLabel")
			label.BackgroundTransparency = 1
			label.Size = UDim2.fromScale(1, 1)
			label.TextScaled = true
			label.Text = e.text
			label.Parent = gui
			gui.Parent = stage
			table.insert(emoteGuis, gui)
		end
	end
	cam.applyLight()
	local camera = workspace.CurrentCamera
	camera.CameraType = Enum.CameraType.Scriptable
	camera.CFrame = f.camera
	camera.FieldOfView = f.fov
	return true
end

function cam.finish()
	if cam.addedConn then
		cam.addedConn:Disconnect()
		cam.addedConn = nil
	end
	if stage then
		stage:Destroy()
		stage = nil
	end
	if cam.tagFolder then
		cam.tagFolder:Destroy()
		cam.tagFolder = nil
	end
	for _, h in hidden do
		pcall(function()
			h[1].Parent = h[2]
		end)
	end
	hidden = {}
	for _, g in guis do
		g.Enabled = true
	end
	guis = {}
	clones = {}
	for _, t in tracked do
		if t.kind == "character" then
			for _, p in t.parts do
				p.LocalTransparencyModifier = 0
			end
		end
	end
	workspace.CurrentCamera.CameraType = Enum.CameraType.Custom
	return true
end

return true
