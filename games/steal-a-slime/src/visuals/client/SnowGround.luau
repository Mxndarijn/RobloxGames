--!strict
--[[
	SnowGround (VisualsClient module, v30 F2, FEATURES.Weather)

	Client-only ground snow: ONE anchored, non-colliding Snow-material Part flush over the Ground whose
	Transparency follows the cover level (SnowCover; builds up during Snow, melts after). Created on first snow, destroyed
	once fully melted. Heartbeat only runs while the level moves. Cost: 1 part, 0 mesh slots.

	The pc-watcher can pin the level with the client-local workspace attribute SnowCoverDebug (0..1).
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Constants = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Constants"))
local SnowCover = require(ReplicatedStorage:WaitForChild("Visuals"):WaitForChild("SnowCover"))

local SnowGround = {}

local part: Part? = nil
local connection: RBXScriptConnection? = nil
local level = 0
local snowing = false

local function forced(): number?
	local value = workspace:GetAttribute(Constants.SNOW_COVER_DEBUG_ATTRIBUTE)
	return if type(value) == "number" then math.clamp(value, 0, 1) else nil
end

local function draw()
	if not SnowCover.visible(level) then
		if part then
			part:Destroy()
			part = nil
		end
		return
	end
	if not part then
		local p = Instance.new("Part")
		p.Name = "SnowCover"
		p.Anchored = true
		p.CanCollide = false
		p.CanQuery = false
		p.CanTouch = false
		p.CastShadow = false
		p.Material = Enum.Material.Snow
		p.Color = Color3.fromRGB(248, 250, 255)
		p.Size = Vector3.new(SnowCover.SIZE[1], SnowCover.SIZE[2], SnowCover.SIZE[3])
		p.Position = Vector3.new(0, SnowCover.TOP - SnowCover.SIZE[2] / 2, 0)
		p.Parent = workspace
		part = p
	end
	(part :: Part).Transparency = SnowCover.transparency(level)
end

local function stop()
	if connection then
		connection:Disconnect()
		connection = nil
	end
end

local function run()
	if connection then
		return
	end
	connection = RunService.Heartbeat:Connect(function(dt)
		local pin = forced()
		level = if pin then pin else SnowCover.step(level, dt, snowing)
		draw()
		if pin or SnowCover.settled(level, snowing) then
			stop()
		end
	end)
end

-- Called by WeatherFx whenever the shown weather changes.
function SnowGround.setSnowing(value: boolean)
	snowing = value
	if forced() or not SnowCover.settled(level, snowing) then
		run()
	end
end

function SnowGround.start()
	workspace:GetAttributeChangedSignal(Constants.SNOW_COVER_DEBUG_ATTRIBUTE):Connect(function()
		run()
	end)
end

return SnowGround
