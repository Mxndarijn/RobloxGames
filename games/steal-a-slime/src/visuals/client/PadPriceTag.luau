--!strict
--[[
	PadPriceTag (VisualsClient module)

	A floating price tag over the local player's next buyable pad, for this player only: "BUY PAD / $625" (or
	"BUILD FLOOR 2 / $30K") above the pad that carries the enabled BuyPadPrompt, with a soft glow ring round the
	cork stand, so the next pad is easy to spot across the jar. Green while the player can pay, gold while saving
	up. Gone once every cash pad is bought (the prompt is disabled then; rebirths add the rest).
	Reads attributes and the prompt only; never fires remotes. Local changes only. Text and numbers live in
	Visuals.PadPriceTagLook.

	PadPriceTag.start() -> cleanup
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Constants = require(Shared:WaitForChild("Constants"))
local Look = require(ReplicatedStorage:WaitForChild("Visuals"):WaitForChild("PadPriceTagLook"))

local PadPriceTag = {}

PadPriceTag.FOLDER = "PadPriceTag"
PadPriceTag.POLL = 0.25

local function rgb(c: { number }): Color3
	return Color3.fromRGB(c[1], c[2], c[3])
end

local function cash(player: Player): number
	local stats = player:FindFirstChild("leaderstats")
	local value = stats and stats:FindFirstChild("Cash")
	return if value and value:IsA("ValueBase") then tonumber((value :: any).Value) or 0 else 0
end

-- The local player's pad with the enabled BuyPadPrompt, its plot and the prompt (nil when none).
local function target(player: Player): (BasePart?, Instance?, ProximityPrompt?)
	local plots = workspace:FindFirstChild(Constants.PLOTS_FOLDER)
	for _, plot in if plots then plots:GetChildren() else {} do
		if plot:GetAttribute("OwnerUserId") == player.UserId then
			for _, pad in plot:GetChildren() do
				local prompt = pad:FindFirstChild(Constants.BUY_PAD_PROMPT_NAME)
				if pad:IsA("BasePart") and prompt and prompt:IsA("ProximityPrompt") and prompt.Enabled then
					return pad, plot, prompt
				end
			end
		end
	end
	return nil, nil, nil
end

type Built = { folder: Folder, ring: BasePart, gui: BillboardGui, title: TextLabel, price: TextLabel }

local function build(): Built
	local folder = Instance.new("Folder")
	folder.Name = PadPriceTag.FOLDER
	local ring = Instance.new("Part")
	ring.Name = "Ring"
	ring.Shape = Enum.PartType.Cylinder
	ring.Size = Vector3.new(0.12, Look.RING_DIAMETER, Look.RING_DIAMETER)
	ring.Material = Enum.Material.Neon
	ring.Transparency = 0.45
	ring.Anchored = true
	ring.CanCollide = false
	ring.CanQuery = false
	ring.CanTouch = false
	ring.CastShadow = false
	ring.Parent = folder
	local gui = Instance.new("BillboardGui")
	gui.Name = "Tag"
	gui.Size = UDim2.fromScale(Look.SIZE[1], Look.SIZE[2])
	gui.LightInfluence = 0
	gui.MaxDistance = Look.MAX_DISTANCE
	gui.AlwaysOnTop = false
	gui.Parent = ring
	local card = Instance.new("Frame")
	card.Name = "Card"
	card.Size = UDim2.fromScale(1, 1)
	card.BackgroundColor3 = Color3.fromRGB(30, 18, 51)
	card.BackgroundTransparency = 0.15
	card.Parent = gui
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0.25, 0)
	corner.Parent = card
	local function text(name: string, y: number, h: number): TextLabel
		local label = Instance.new("TextLabel")
		label.Name = name
		label.BackgroundTransparency = 1
		label.Font = Enum.Font.FredokaOne
		label.TextScaled = true
		label.TextColor3 = Color3.fromRGB(255, 255, 255)
		label.Position = UDim2.fromScale(0.06, y)
		label.Size = UDim2.fromScale(0.88, h)
		label.Parent = card
		return label
	end
	local title = text("Title", 0.08, 0.38)
	local price = text("Price", 0.46, 0.46)
	return { folder = folder, ring = ring, gui = gui, title = title, price = price }
end

function PadPriceTag.start(): () -> ()
	local player = Players.LocalPlayer
	local built = build()
	local running = true
	task.spawn(function()
		while running do
			local pad, plot, prompt = target(player)
			local cost = if plot then plot:GetAttribute(Constants.PLOT_NEXT_PAD_COST_ATTRIBUTE) else nil
			local view = if prompt then Look.view(prompt.ActionText, cost :: number?, cash(player)) else nil
			if pad and view then
				local top = pad.CFrame * CFrame.new(0, pad.Size.Y / 2, 0)
				built.ring.CFrame = top * CFrame.new(0, 0.08, 0) * CFrame.Angles(0, 0, math.pi / 2)
				built.gui.StudsOffsetWorldSpace = Vector3.new(0, Look.HEIGHT, 0)
				local color = rgb(if view.affordable then Look.GOOD else Look.SHORT)
				built.ring.Color = color
				built.title.Text = view.title
				built.price.Text = view.price
				built.price.TextColor3 = color
				built.folder.Parent = workspace
			else
				built.folder.Parent = nil
			end
			task.wait(PadPriceTag.POLL)
		end
	end)
	return function()
		running = false
		built.folder:Destroy()
	end
end

return PadPriceTag
