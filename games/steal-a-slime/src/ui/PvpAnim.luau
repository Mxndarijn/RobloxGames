--!strict
--[[
	PvpAnim (client, CONTRACT.md §26.3): procedural Bat / PvP item animations on the R15 characters.

	Poses come from ui/PvpAnimLogic and are written into the joints' Transform (Motor6D, or AnimationConstraint on
	avatars with Roblox's joint upgrade) on top of what the Animator
	played this frame (Stepped runs after the Animator), so the walk and idle keep playing underneath. A joint the
	Animator did not touch still holds our last write: that offset is taken off again before the new one goes on,
	so nothing accumulates. No animation asset, no remote of its own.

	What plays:
	  * the hold pose of every player whose `PvpEquipped` attribute is set (faded in / out),
	  * `play(userId, kind)` / `playItem(userId, itemId)`: the local player's own uses (Inventory), other players'
	    from PvpEvent (ui/PvpEffects) and the victim's `hit`,
	  * the Bat swing: the local player's own on Tool.Activated, everyone else's when their `BatSwingAt` changes.
	Only characters within PvpAnimLogic.RANGE of the camera and on screen are posed; the Stepped connection exists
	only while something is held or playing. `start` returns the handle; `handle.stop()` disconnects everything.
]]

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")

local Logic = require(script.Parent.PvpAnimLogic)

local PvpAnim = {}

export type Options = {
	tools: { any }, -- Config.PVP_TOOLS
	equippedAttribute: string, -- Constants.PVP_EQUIPPED_ATTRIBUTE
	batSwingAttribute: string, -- Constants.BAT_SWING_ATTRIBUTE
	batName: string, -- Config.BAT.TOOL_NAME
	swingGap: number, -- Config.BAT.SWING_GAP
}
export type Handle = {
	play: (userId: number?, kind: string) -> (),
	playItem: (userId: number?, itemId: string?) -> (),
	activeCount: () -> number,
	stop: () -> (),
}

type Rig = {
	player: Player,
	character: Model?,
	motors: { [string]: any }, -- Motor6D, or AnimationConstraint on avatars with the joint upgrade (both have Transform)
	written: { [string]: CFrame }, -- what we wrote last frame
	offsets: { [string]: CFrame }, -- the offset inside it
	weight: number, -- hold pose 0..1
	hold: Logic.Pose?, -- the last hold pose (kept while it fades out)
	clip: string?,
	startedAt: number,
}

local IDENTITY = CFrame.new()
local EPSILON = 1e-4

local function same(a: CFrame, b: CFrame): boolean
	return (a.Position - b.Position).Magnitude < EPSILON
		and a.LookVector:Dot(b.LookVector) > 1 - EPSILON
		and a.UpVector:Dot(b.UpVector) > 1 - EPSILON
end

local function offsetOf(angles: Logic.Angles?): CFrame
	if not angles then
		return IDENTITY
	end
	return CFrame.new(0, angles.py or 0, 0) * CFrame.Angles(angles.rx or 0, angles.ry or 0, angles.rz or 0)
end

function PvpAnim.start(opts: Options): Handle
	local rigs: { [Player]: Rig } = {}
	local conns: { RBXScriptConnection } = {}
	local stepConn: RBXScriptConnection? = nil
	local hookedTools: { [Instance]: boolean } = setmetatable({}, { __mode = "k" }) :: any
	local localPlayer = Players.LocalPlayer
	local lastLocalSwing = -math.huge

	local function rigOf(player: Player): Rig
		local rig = rigs[player]
		if not rig then
			rig = {
				player = player,
				character = nil,
				motors = {},
				written = {},
				offsets = {},
				weight = 0,
				hold = nil,
				clip = nil,
				startedAt = 0,
			}
			rigs[player] = rig
		end
		return rig :: Rig
	end

	local function motorsOf(rig: Rig, character: Model)
		if rig.character == character then
			return
		end
		rig.character = character
		rig.motors, rig.written, rig.offsets = {}, {}, {}
		for _, name in Logic.JOINTS do
			local motor = character:FindFirstChild(name, true)
			if motor and (motor:IsA("Motor6D") or motor:IsA("AnimationConstraint")) then
				rig.motors[name] = motor
			end
		end
	end

	-- Takes our offsets back off every joint (the character went out of range or the pose ended).
	local function release(rig: Rig)
		for name, written in rig.written do
			local motor = rig.motors[name]
			if motor and motor.Parent and same(motor.Transform, written) then
				motor.Transform = written * rig.offsets[name]:Inverse()
			end
		end
		rig.written, rig.offsets = {}, {}
	end

	local function visible(character: Model): boolean
		local root = character:FindFirstChild("HumanoidRootPart")
		local camera = workspace.CurrentCamera
		if not root or not root:IsA("BasePart") or not camera then
			return false
		end
		if (camera.CFrame.Position - root.Position).Magnitude > Logic.RANGE then
			return false
		end
		local _, onScreen = camera:WorldToViewportPoint(root.Position)
		return onScreen
	end

	local ensureStep: () -> ()

	local function step(dt: number)
		local now = os.clock()
		for player, rig in rigs do
			local character = player.Character
			local itemId = player:GetAttribute(opts.equippedAttribute)
			local hold = Logic.holdFor(itemId, opts.tools)
			rig.hold = hold or rig.hold
			rig.weight = Logic.approach(rig.weight, if hold and character then 1 else 0, dt)
			local anim = if rig.clip then Logic.pose(rig.clip, now - rig.startedAt) else nil
			if rig.clip and not anim then
				rig.clip = nil
			end
			if character and character ~= rig.character then
				motorsOf(rig, character)
			end
			if not character or not visible(character) then
				release(rig)
			else
				local pose = Logic.combine(rig.hold, rig.weight, anim)
				for name, motor in rig.motors do
					local angles = pose[name]
					local wrote = rig.written[name]
					if angles or wrote then
						local current = motor.Transform
						local base = if wrote and same(current, wrote)
							then wrote * rig.offsets[name]:Inverse()
							else current
						if angles then
							local offset = offsetOf(angles)
							local value = base * offset
							motor.Transform = value
							rig.written[name], rig.offsets[name] = value, offset
						else
							motor.Transform = base
							rig.written[name], rig.offsets[name] = nil, nil
						end
					end
				end
			end
			if rig.weight == 0 and rig.clip == nil and next(rig.written) == nil then
				rigs[player] = nil
			end
		end
		if next(rigs) == nil and stepConn then
			stepConn:Disconnect()
			stepConn = nil
		end
	end

	ensureStep = function()
		if not stepConn then
			stepConn = RunService.Stepped:Connect(function(_time: number, dt: number)
				local ok, err = pcall(step, dt)
				if not ok then
					warn(`[PvpAnim] {err}`)
				end
			end)
		end
	end

	local function play(userId: number?, kind: string)
		local player = if userId then Players:GetPlayerByUserId(userId) else nil
		if not player or not Logic.CLIPS[kind] then
			return
		end
		local rig = rigOf(player)
		rig.clip = kind
		rig.startedAt = os.clock()
		ensureStep()
	end

	local function watchPlayer(player: Player)
		table.insert(
			conns,
			player:GetAttributeChangedSignal(opts.equippedAttribute):Connect(function()
				rigOf(player)
				ensureStep()
			end)
		)
		if player ~= localPlayer then
			table.insert(
				conns,
				player:GetAttributeChangedSignal(opts.batSwingAttribute):Connect(function()
					play(player.UserId, "swing")
				end)
			)
		end
		if player:GetAttribute(opts.equippedAttribute) ~= nil then
			rigOf(player)
			ensureStep()
		end
	end

	-- The local Bat swings at once on its own click (the server's BatSwingAt is for everyone else).
	local function hookTool(tool: Instance)
		if hookedTools[tool] or not tool:IsA("Tool") or tool.Name ~= opts.batName then
			return
		end
		hookedTools[tool] = true
		table.insert(
			conns,
			tool.Activated:Connect(function()
				local now = os.clock()
				if now - lastLocalSwing >= opts.swingGap then
					lastLocalSwing = now
					play(localPlayer.UserId, "swing")
				end
			end)
		)
	end
	local function watchCharacter(character: Model)
		for _, child in character:GetChildren() do
			hookTool(child)
		end
		table.insert(conns, character.ChildAdded:Connect(hookTool))
	end

	for _, player in Players:GetPlayers() do
		watchPlayer(player)
	end
	table.insert(conns, Players.PlayerAdded:Connect(watchPlayer))
	table.insert(
		conns,
		Players.PlayerRemoving:Connect(function(player: Player)
			rigs[player] = nil
		end)
	)
	if localPlayer.Character then
		watchCharacter(localPlayer.Character)
	end
	table.insert(conns, localPlayer.CharacterAdded:Connect(watchCharacter))

	local handle = {}
	handle.play = play
	function handle.playItem(userId: number?, itemId: string?)
		local kind = Logic.kindFor(itemId, opts.tools)
		if kind then
			play(userId, kind)
		end
	end
	function handle.activeCount(): number
		local n = 0
		for _, rig in rigs do
			if rig.clip then
				n += 1
			end
		end
		return n
	end
	function handle.stop()
		for _, c in conns do
			c:Disconnect()
		end
		table.clear(conns)
		for _, rig in rigs do
			release(rig)
		end
		table.clear(rigs)
		if stepConn then
			stepConn:Disconnect()
			stepConn = nil
		end
	end
	return handle :: Handle
end

return PvpAnim
