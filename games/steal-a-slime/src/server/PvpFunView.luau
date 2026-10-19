--!strict
--[[
	PvpFunView (Roblox adapter, FEATURES.PvP, CONTRACT.md §26.8)

	The one Fun item part the server makes: the Bubble Wand's bubble around a lifted player. A collision-free ball
	welded to the character's root, an AlignPosition that floats the root `lift` studs up (the character's network
	owner simulates it, so it works for players and for server-owned rigs alike) and a ClickDetector so another
	player can pop it early (server/PvpFun decides through `onPop`). Everything is destroyed after `seconds`, on a
	pop, or with the character. No gameplay rules here.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)

local PvpFunView = {}

PvpFunView.NAME = "PvpBubble"
local BUBBLE = table.freeze({
	size = 7, -- studs across: fits an R15 character
	color = Color3.fromRGB(150, 215, 255),
	transparency = 0.35,
	responsiveness = 25, -- AlignPosition: how quickly it floats up
	maxForce = 1e6,
})

-- Floats `root` `lift` studs up inside a clickable bubble for `seconds`. `onPop(byUserId, now)` returns true when
-- a click popped it. False when there is no root to lift.
function PvpFunView.bubble(
	root: BasePart?,
	ownerUserId: number,
	seconds: number,
	lift: number,
	onPop: (byUserId: number, now: number) -> boolean,
	now: () -> number
): boolean
	if not root or not root.Parent then
		return false
	end
	local old = root.Parent:FindFirstChild(PvpFunView.NAME)
	if old then
		old:Destroy()
	end
	local ball = Instance.new("Part")
	ball.Name = PvpFunView.NAME
	ball.Shape = Enum.PartType.Ball
	ball.Size = Vector3.one * BUBBLE.size
	ball.Material = Enum.Material.ForceField
	ball.Color = BUBBLE.color
	ball.Transparency = BUBBLE.transparency
	ball.CanCollide = false
	ball.CanTouch = false
	ball.CanQuery = true -- the ClickDetector needs the mouse ray to hit it
	ball.Massless = true
	ball.CastShadow = false
	ball.CFrame = root.CFrame
	local weld = Instance.new("WeldConstraint")
	weld.Part0, weld.Part1 = ball, root
	weld.Parent = ball
	local anchor = Instance.new("Attachment")
	anchor.Name = "PvpBubbleLift"
	anchor.Parent = root
	local align = Instance.new("AlignPosition")
	align.Mode = Enum["PositionAlignmentMode"].OneAttachment -- indexed: the livetest runtime rewrites `.Position` reads
	align.Attachment0 = anchor
	align.Position = root.Position + Vector3.new(0, lift, 0)
	align.MaxForce = BUBBLE.maxForce
	align.Responsiveness = BUBBLE.responsiveness
	align.Parent = ball
	local click = Instance.new("ClickDetector")
	click.MaxActivationDistance = Config.PVP_FUN.BUBBLES.POP_RANGE
	click.Parent = ball
	ball.Parent = root.Parent

	local done = false
	local function release()
		if done then
			return
		end
		done = true
		ball:Destroy()
		anchor:Destroy()
	end
	click.MouseClick:Connect(function(player: Player)
		if player.UserId ~= ownerUserId and onPop(player.UserId, now()) then
			release()
		end
	end)
	task.delay(seconds, release)
	return true
end

return PvpFunView
