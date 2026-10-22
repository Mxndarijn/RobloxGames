--!strict
--[[
	BossTelegraph (client, contract/boss-event.md "Attacks")

	Draws what the fighting boss is about to do and is doing, from its model's attributes, with the same geometry
	the server checks (Shared.BossAttacks):
	  windup   a pulsing red outline: the stomp's ring, the cone's wedge, the charge's lane, the spit's landing spots
	  attack   the goo ring running out, the wedge flashing, the lane flashing, the spits flying in an arc
	  dazed    stars circling over its head
	  a hit    "+3" pops over the boss for the player who landed it
	Local parts only (one pooled set in a local folder); nothing replicates. `tick(camera)` once a frame from the
	visuals client's loop.
]]

local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local BossArea = require(Shared:WaitForChild("BossArea"))
local BossAttacks = require(Shared:WaitForChild("BossAttacks"))
local BossChoreo = require(Shared:WaitForChild("BossChoreo"))
local Config = require(Shared:WaitForChild("Config"))
local Constants = require(Shared:WaitForChild("Constants"))

local BOSS = Config.BOSS

local BossTelegraph = {}

BossTelegraph.SEGMENTS = 40 -- parts round a full circle
BossTelegraph.MAX_DISTANCE = 220 -- studs from the camera: further away nothing is drawn
BossTelegraph.RESCAN = 0.5 -- seconds between looks for the boss model
BossTelegraph.POP_SECONDS = 0.8

local RED = Color3.fromRGB(235, 60, 45)
local GOO = Color3.fromRGB(110, 210, 90)
local STAR = Color3.fromRGB(255, 220, 80)

type Pool = { parts: { BasePart }, used: number }

local function newPart(folder: Instance, shape: Enum.PartType): Part
	local p = Instance.new("Part")
	p.Anchored = true
	p.CanCollide = false
	p.CanQuery = false
	p.CanTouch = false
	p.CastShadow = false
	p.Material = Enum.Material.Neon
	p.Shape = shape
	p.Size = Vector3.one
	p.Transparency = 1
	p.Parent = folder
	return p
end

function BossTelegraph.start()
	local folder = Instance.new("Folder")
	folder.Name = "BossTelegraph"
	folder.Parent = workspace
	local blocks: Pool = { parts = {}, used = 0 }
	local balls: Pool = { parts = {}, used = 0 }

	local function take(pool: Pool, shape: Enum.PartType): BasePart
		pool.used += 1
		local p = pool.parts[pool.used]
		if not p then
			p = newPart(folder, shape)
			pool.parts[pool.used] = p
		end
		return p
	end
	local function block(cf: CFrame, size: Vector3, color: Color3, transparency: number)
		local p = take(blocks, Enum.PartType.Block)
		p.CFrame, p.Size, p.Color, p.Transparency = cf, size, color, transparency
	end
	local function ball(at: Vector3, size: number, color: Color3, transparency: number)
		local p = take(balls, Enum.PartType.Ball)
		p.CFrame, p.Size, p.Color, p.Transparency = CFrame.new(at), Vector3.one * size, color, transparency
	end

	-- An arc of `radius` round `centre` (flat on the ground at its Y), from angle a0 to a1 (radians, 0 = +X).
	local function arc(centre: Vector3, radius: number, a0: number, a1: number, width: number, color: Color3, t: number)
		local n = math.max(3, math.ceil(BossTelegraph.SEGMENTS * math.abs(a1 - a0) / (2 * math.pi)))
		local chord = 2 * radius * math.sin(math.abs(a1 - a0) / n / 2) + 0.1
		for i = 0, n - 1 do
			local a = a0 + (a1 - a0) * (i + 0.5) / n
			local at = centre + Vector3.new(math.cos(a) * radius, 0, math.sin(a) * radius)
			local tangent = Vector3.new(-math.sin(a), 0, math.cos(a))
			block(CFrame.lookAt(at, at + tangent), Vector3.new(width, 0.15, chord), color, t)
		end
	end
	local function line(from: Vector3, to: Vector3, width: number, color: Color3, t: number)
		local length = (to - from).Magnitude
		if length < 1e-3 then
			return
		end
		block(CFrame.lookAt((from + to) / 2, to), Vector3.new(width, 0.15, length), color, t)
	end

	local boss: Model? = nil
	local nextScan = 0
	local lastHitAt: number? = nil
	local pops: { { gui: BillboardGui, label: TextLabel, at: number } } = {}

	local function findBoss(): Model?
		for _, m in CollectionService:GetTagged(Constants.SLIME_TAG) do
			if m:IsA("Model") and m:GetAttribute(Constants.BOSS_ATTRIBUTE) == true and m:IsDescendantOf(workspace) then
				return m
			end
		end
		return nil
	end

	local function popHit(model: Model, points: number)
		local gui = Instance.new("BillboardGui")
		gui.Size = UDim2.fromOffset(120, 50)
		gui.AlwaysOnTop = true
		gui.StudsOffsetWorldSpace = Vector3.new(0, 10, 0)
		gui.Adornee = model.PrimaryPart
		local label = Instance.new("TextLabel")
		label.Size = UDim2.fromScale(1, 1)
		label.BackgroundTransparency = 1
		label.Font = Enum.Font.FredokaOne
		label.TextScaled = true
		label.Text = `+{points}`
		label.TextColor3 = if points > 1 then STAR else Color3.new(1, 1, 1)
		label.TextStrokeTransparency = 0.2
		label.Parent = gui
		gui.Parent = folder
		table.insert(pops, { gui = gui, label = label, at = os.clock() })
	end

	local function spots(text: any): { { number } }
		local out = {}
		if type(text) ~= "string" then
			return out
		end
		for _, item in string.split(text, ";") do
			local values = {}
			for _, v in string.split(item, ",") do
				table.insert(values, tonumber(v) or 0)
			end
			table.insert(out, values)
		end
		return out
	end

	local function draw(model: Model, now: number, serverNow: number)
		local move = BossChoreo.decode(model:GetAttribute(Constants.BOSS_MOVE_ATTRIBUTE))
		local y = model:GetPivot().Position.Y + 0.15
		-- Spit landing spots and spits in the air (the windup picks them; the attack throws them).
		for _, t in spots(model:GetAttribute(Constants.BOSS_TARGETS_ATTRIBUTE)) do
			local pulse = 0.35 + 0.25 * math.sin(now * 10)
			arc(Vector3.new(t[1], y, t[2]), BOSS.PUDDLE_RADIUS, 0, 2 * math.pi, 0.5, RED, pulse)
		end
		if move then
			local bx, bz = BossChoreo.world(move, serverNow)
			for _, s in spots(model:GetAttribute(Constants.BOSS_SPITS_ATTRIBUTE)) do
				local landAt = s[3]
				local k = 1 - math.clamp((landAt - serverNow) / BOSS.SPIT_FLIGHT, 0, 1)
				local from, to = Vector3.new(bx, y + 6, bz), Vector3.new(s[1], y, s[2])
				ball(from:Lerp(to, k) + Vector3.new(0, 10 * 4 * k * (1 - k), 0), 1.6, GOO, 0)
				arc(to, BOSS.PUDDLE_RADIUS, 0, 2 * math.pi, 0.5, RED, 0.3)
			end
		end
		if not move then
			return
		end
		local species = model:GetAttribute(Constants.SPECIES_ATTRIBUTE)
		local attack = if type(species) == "string" then BossAttacks.get(species, move.slot) else nil
		local bx, bz, hx, hz = BossChoreo.world(move, serverNow)
		local centre = Vector3.new(bx, y, bz)
		local since = serverNow - move.at
		if (move.kind == "windup" or move.kind == "attack") and attack then
			local warn = move.kind == "windup"
			local pulse = if warn then 0.55 - 0.3 * (0.5 + 0.5 * math.sin(now * (8 + 10 * since))) else 0.15
			if attack.kind == "ring" then
				local radius = attack.radius or 20
				if warn then
					arc(centre, radius, 0, 2 * math.pi, 0.6, RED, pulse)
				else
					local r = (attack.speed or 20) * (since - BOSS.RING_DELAY)
					if r > 0 and r <= radius then
						arc(
							Vector3.new(move.fx + move.ox, y, move.fz + move.oz),
							r,
							0,
							2 * math.pi,
							BOSS.RING_WIDTH,
							GOO,
							0.1
						)
					end
				end
			elseif attack.kind == "cone" then
				local radius = attack.radius or 18
				local half = math.rad((attack.angle or 90) / 2)
				local a = math.atan2(hz, hx)
				arc(centre, radius, a - half, a + half, if warn then 0.6 else 1.5, RED, pulse)
				for _, side in { a - half, a + half } do
					line(centre, centre + Vector3.new(math.cos(side), 0, math.sin(side)) * radius, 0.5, RED, pulse)
				end
			elseif attack.kind == "charge" then
				local fx, fz = move.fx, move.fz
				local ex, ez
				if warn then
					ex, ez = BossAttacks.chargeEnd(fx, fz, move.hx, move.hz, attack)
				else
					ex, ez = move.tx, move.tz
				end
				local from = Vector3.new(fx + move.ox, y, fz + move.oz)
				local to = Vector3.new(ex + move.ox, y, ez + move.oz)
				line(from, to, (attack.width or 8) + 2 * BossArea.BODY_RADIUS, RED, if warn then pulse + 0.2 else 0.4)
			end
		elseif move.kind == "dazed" then
			local top = centre + Vector3.new(0, model:GetExtentsSize().Y + 1, 0)
			for i = 0, 2 do
				local a = now * 3 + i * 2 * math.pi / 3
				ball(top + Vector3.new(math.cos(a) * 3, 0.4 * math.sin(now * 6 + i), math.sin(a) * 3), 1, STAR, 0)
			end
		end
	end

	local self = {}

	function self.tick(camera: Camera)
		blocks.used, balls.used = 0, 0
		local now = os.clock()
		if now >= nextScan or (boss and not boss:IsDescendantOf(workspace)) then
			nextScan = now + BossTelegraph.RESCAN
			boss = findBoss()
		end
		local model = boss
		if model and (model:GetPivot().Position - camera.CFrame.Position).Magnitude <= BossTelegraph.MAX_DISTANCE then
			draw(model, now, workspace:GetServerTimeNow())
			local hitAt = model:GetAttribute(Constants.BOSS_HIT_AT_ATTRIBUTE)
			if type(hitAt) == "number" and hitAt ~= lastHitAt then
				local fresh = lastHitAt ~= nil
				lastHitAt = hitAt
				local by = model:GetAttribute(Constants.BOSS_HIT_BY_ATTRIBUTE)
				local points = model:GetAttribute(Constants.BOSS_HIT_POINTS_ATTRIBUTE)
				local me = Players.LocalPlayer
				if fresh and me and by == me.UserId and type(points) == "number" then
					popHit(model, points)
				end
			end
		end
		for i = #pops, 1, -1 do
			local pop = pops[i]
			local k = (now - pop.at) / BossTelegraph.POP_SECONDS
			if k >= 1 then
				pop.gui:Destroy()
				table.remove(pops, i)
			else
				pop.gui.StudsOffsetWorldSpace = Vector3.new(0, 10 + 4 * k, 0)
				pop.label.TextTransparency = k * k
				pop.label.TextStrokeTransparency = 0.2 + 0.8 * k * k
			end
		end
		for _, pool in { blocks, balls } do
			for i = pool.used + 1, #pool.parts do
				local p = pool.parts[i]
				if p.Transparency ~= 1 then
					p.Transparency = 1
				end
			end
		end
	end

	return self
end

return BossTelegraph
