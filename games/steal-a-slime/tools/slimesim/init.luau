--!strict
--[[
	SlimeSim: a headless simulation of lane slimes and a player, run through the real client motion code.

		lune run tools/slimesim [scenario] [--net studio|live] [--seconds N] [--out file.json]

	Server side: wild slimes spawn off the fountain slide every SPAWN_EVERY seconds and walk the goo lane exactly as
	WorldView does it (ParadeLane.pose + their ParadeChoreo beats, queued by LaneTraffic), stepped at 60 Hz.
	Network: the client sees each Body's pivot only when a snapshot arrives: every 2nd server frame in Studio
	("studio"), or about 20 Hz with lag and jitter like a live server ("live").
	Client side: each slime is a rigged model (UiHarness instances, SlimeRig) driven by SlimeActor + SlimeMotor at
	60 fps, with the scenario's player as the local character (cash enough to buy every slime). Every frame records
	what the frame draws: the slime's foot and facing (Body x Transform), its lift and squash, where its name tag and
	Buy card hang (adorned to the Body), its gait stage, face and emote, and the player.

	Writes the trace as JSON (default tools/slimesim/out/<scenario>.json) and prints the metrics
	(tools/slimesim/Metrics). tools/slimesim/view.py turns a trace into an HTML viewer.
	SLIMESIM_DEBUG=<slime id> prints that slime's actor internals every 6 frames.
	Dev tool only: nothing in the game requires it.
]]

local fs = require("@lune/fs")
local process = require("@lune/process")
local roblox = require("@lune/roblox") :: any
local serde = require("@lune/serde")

local Metrics = require("./slimesim/Metrics")
local Scenarios = require("./slimesim/Scenarios")
local UiHarness = require("../tests/ui/UiHarness")

local CFrame, Vector3 = roblox.CFrame, roblox.Vector3
local new = UiHarness.Instance.new

local Config = UiHarness.ui("../shared/Config")
local ParadeLane = UiHarness.ui("../shared/ParadeLane")
local ParadeChoreo = UiHarness.ui("../shared/ParadeChoreo")
local LaneTraffic = UiHarness.ui("../shared/LaneTraffic")
local SlimePersona = UiHarness.ui("../shared/SlimePersona")
local SlimeActor = UiHarness.ui("SlimeActor")
local SlimeMotor = UiHarness.ui("SlimeMotor")
local SlimeRig = UiHarness.ui("../visuals/shared/SlimeRig")
-- The two-pass frame (place, space + settle the tag, step) when this checkout has it; else the one-pass frame.
local okSpacing, SlimeSpacing = pcall(UiHarness.ui, "SlimeSpacing")
local twoPass = okSpacing and SlimeActor.settle ~= nil

local FPS = 60
local SPAWN_EVERY = 2.6 -- seconds between slimes off the slide
local SPECIES = { "bubbles", "gummy", "moo", "mochi", "froggo", "pebble", "lop", "whiskers", "bumble", "octo" }

-- Arguments
local args = process.args
local scenarioName = "beside"
local net = "studio"
local seconds = 14
local outPath: string? = nil
local i = 1
while i <= #args do
	local a = args[i]
	if a == "--net" then
		net = args[i + 1]
		i += 1
	elseif a == "--seconds" then
		seconds = tonumber(args[i + 1]) or seconds
		i += 1
	elseif a == "--out" then
		outPath = args[i + 1]
		i += 1
	else
		scenarioName = a
	end
	i += 1
end
local scenario = Scenarios[scenarioName]
assert(scenario, `unknown scenario {scenarioName}; have: {table.concat(Scenarios.names(), ", ")}`)

local function lcg(seed: number): () -> number
	local s = seed
	return function()
		s = (s * 1103515245 + 12345) % 2147483648
		return s / 2147483648
	end
end
local rand = lcg(scenario.seed or 7)

-- Server: lane wilds. t = 0 is the start of the recording; slimes spawned before it are already on the lane.
local lifetime = Config.WILD_LIFETIME
type Wild = {
	id: string,
	species: string,
	spawnedAt: number,
	expiresAt: number,
	lateral: number,
	radius: number,
	seed: number,
	plan: any,
}
local wilds: { Wild } = {}
local warmup = scenario.warmup or 40 -- seconds of lane already walked when the recording starts
local n = 0
local t0 = -warmup - ParadeLane.RIDE_SECONDS
while t0 < seconds do
	n += 1
	local species = SPECIES[(n - 1) % #SPECIES + 1]
	local w: Wild = {
		id = `s{n}`,
		species = species,
		spawnedAt = t0,
		expiresAt = t0 + lifetime,
		lateral = (rand() - 0.5) * ParadeLane.SPREAD,
		radius = Config.SLIME_BASE_DIAMETER / 2,
		seed = ParadeChoreo.seedFor(`s{n}`),
		plan = nil,
	}
	local _, walkSeconds, lead = ParadeLane.walkTimes(w.spawnedAt, w.expiresAt)
	w.plan = ParadeChoreo.plan(w.seed, SlimePersona.of(species).temper, walkSeconds, lead)
	table.insert(wilds, w)
	t0 += SPAWN_EVERY * (0.7 + 0.6 * rand())
end

local laneDrawn: { [string]: number } = {}
local function ahead(w: Wild, now: number): number
	local startAt = ParadeLane.walkTimes(w.spawnedAt, w.expiresAt)
	return ParadeChoreo.offset(w.plan, now - startAt) * ParadeLane.walkSpeed(w.expiresAt - w.spawnedAt)
end
-- The server's lane step at `now`: pivots of every walking slime (WorldView.stepLanes).
local function serverStep(now: number, dt: number): { [string]: any }
	local walkers = {}
	for _, w in wilds do
		if ParadeLane.phase(w.spawnedAt, w.expiresAt, now) == "Walk" then
			local pace = ParadeLane.walkSpeed(w.expiresAt - w.spawnedAt)
			local s = ParadeLane.distance(w.spawnedAt, w.expiresAt, now) + ahead(w, now)
			table.insert(walkers, {
				id = w.id,
				s = s,
				lateral = w.lateral,
				radius = w.radius,
				pace = pace,
				floor = s - LaneTraffic.holdLimit(w.expiresAt - ParadeLane.DRAIN_SECONDS - now, pace),
			})
		end
	end
	LaneTraffic.step(walkers, laneDrawn, dt)
	local out = {}
	for _, w in wilds do
		local phase = ParadeLane.phase(w.spawnedAt, w.expiresAt, now)
		if phase == "Walk" or phase == "Drain" then
			local drawn = laneDrawn[w.id]
			local a = if drawn and phase == "Walk"
				then drawn - ParadeLane.distance(w.spawnedAt, w.expiresAt, now)
				else ahead(w, now)
			local pose = ParadeLane.pose(w.spawnedAt, w.expiresAt, w.lateral, now, a)
			local p, h = pose.position, pose.heading
			local at = Vector3.new(p[1], p[2] + w.radius, p[3])
			out[w.id] = CFrame.lookAt(at, at + Vector3.new(h[1], 0, h[2]))
		end
	end
	return out
end

-- Network: when each server frame's snapshot reaches the client.
local netRand = lcg(99)
local function arrival(serverFrame: number, serverTime: number): number?
	if net == "studio" then
		if serverFrame % 2 ~= 0 then
			return nil
		end
		return serverTime + 0.05
	end
	-- live: ~20 Hz sends, 80-140 ms lag with jitter
	if serverFrame % 3 ~= 0 then
		return nil
	end
	return serverTime + 0.08 + netRand() * 0.06
end

-- Client: one rigged model per slime, built when its first snapshot arrives.
type Client = { w: Wild, model: any, body: any, motor: any, actor: any, cf: any? }
local clients: { [string]: Client } = {}
local byId: { [string]: Wild } = {}
for _, w in wilds do
	byId[w.id] = w
end
local function build(w: Wild, cf: any, now: number): Client
	local model = new("Model")
	model:SetAttribute("Tier", 2)
	model:SetAttribute("State", "Wild")
	model:SetAttribute("Species", w.species)
	model:SetAttribute("Size", 1)
	model:SetAttribute("Price", 20)
	model:SetAttribute(UiHarness.ui("../shared/Constants").LANE_AT_ATTRIBUTE, w.spawnedAt)
	model:SetAttribute(UiHarness.ui("../shared/Constants").LANE_UNTIL_ATTRIBUTE, w.expiresAt)
	model:SetAttribute(UiHarness.ui("../shared/Constants").CHOREO_SEED_ATTRIBUTE, w.seed)
	local body = new("Part")
	body.Name = "Body"
	body.Size = Vector3.new(w.radius * 2, w.radius * 2, w.radius * 2)
	body.Anchored = true
	body.CFrame = cf
	body.Parent = model
	model.PrimaryPart = body
	local mesh = new("MeshPart")
	mesh.Name = "Mesh"
	mesh.Size = body.Size
	mesh.CFrame = cf
	mesh.Parent = model
	local weld = new("WeldConstraint")
	weld.Part0 = body
	weld.Part1 = mesh
	weld.Parent = mesh
	SlimeRig.attach(model, body)
	local r = lcg(#w.id * 31 + 5)
	local motor = SlimeMotor.attach(model, now, r)
	local actor = SlimeActor.attach(model, motor, now, nil)
	actor.feet = new("Attachment") -- no particle effects here (the mock has no Emit); they don't move the slime
	return { w = w, model = model, body = body, motor = motor, actor = actor, cf = cf }
end

-- Run
local frames = math.floor(seconds * FPS)
local pending: { { at: number, poses: { [string]: any } } } = {}
local trace = {
	scenario = scenarioName,
	net = net,
	fps = FPS,
	seconds = seconds,
	alive = Config.FEATURES.SlimeAlive == true,
	lane = ParadeLane.drawPoints(),
	slimes = {} :: { [string]: any },
	player = {} :: { any },
}
local clientRand = lcg(5)
local serverFrame = 0
local playerPos = Vector3.new(0, 3, 0)
for f = 0, frames do
	local now = f / FPS
	-- server frame (same rate as the client here), its snapshot queued for delivery
	serverFrame += 1
	local poses = serverStep(now, 1 / FPS)
	local at = arrival(serverFrame, now)
	if at then
		table.insert(pending, { at = at, poses = poses })
	end
	-- deliver everything that has arrived (the newest wins)
	while #pending > 0 and pending[1].at <= now do
		local snap = table.remove(pending, 1) :: any
		for id, cf in snap.poses do
			local c = clients[id]
			if not c then
				c = build(byId[id], cf, now)
				clients[id] = c
			end
			c.cf = cf
		end
	end
	-- the player
	local px, pz, facing = scenario.player(now, function(id: string): any?
		local c = clients[id]
		return if c then c.body.CFrame else nil
	end, clients)
	playerPos = Vector3.new(px, 3, pz)
	table.insert(trace.player, { math.floor(px * 100) / 100, math.floor(pz * 100) / 100, facing or 0 })
	local frame = { player = playerPos, cash = 1e9, userId = 1 }
	-- client frame, as SlimeLifeRunner runs it: every actor places its slime, then (two-pass code) SlimeSpacing and
	-- settle (the tag follows the drawn slime), then the motors
	local order, items = {}, {}
	for id, c in clients do
		if c.cf then
			c.body.CFrame = c.cf
		end
		c.full = (c.body.CFrame.Position - playerPos).Magnitude < 30
		SlimeActor.update(c.actor, frame, now, now, clientRand, c.full)
		table.insert(order, id)
		table.insert(items, {
			x = c.actor.visible.X,
			z = c.actor.visible.Z,
			r = c.w.radius,
			px = c.actor.pushX or 0,
			pz = c.actor.pushZ or 0,
		})
	end
	if twoPass then
		SlimeSpacing.step(
			items,
			1 / FPS,
			if process.env.SLIMESIM_NO_SOLID then nil else { { x = playerPos.X, z = playerPos.Z, r = 1.2 } }
		)
		for k, id in order do
			SlimeActor.settle(clients[id].actor, items[k].px, items[k].pz, 1 / FPS)
		end
	end
	local debugId = process.env.SLIMESIM_DEBUG
	if debugId and clients[debugId] and f % 6 == 0 then
		local c = clients[debugId]
		local a = c.actor
		local p = c.body.CFrame.Position
		print(
			string.format(
				"%5.2f body=(%.2f,%.2f) anchor=(%.2f,%.2f) corr=(%.2f,%.2f) vis=(%.2f,%.2f) gait=%s(%.2f,%.2f) push=(%.2f,%.2f) speed=%.2f",
				now,
				p.X,
				p.Z,
				a.ax,
				a.az,
				a.corrX,
				a.corrZ,
				a.visible.X,
				a.visible.Z,
				a.gait.stage,
				a.gait.visX,
				a.gait.visZ,
				a.pushX or 0,
				a.pushZ or 0,
				a.speed
			)
				.. string.format(
					" since=%.2f gv=(%.2f,%.2f) kind=%s n=%d",
					now - a.gait.landedAt,
					a.gait.vx,
					a.gait.vz,
					tostring(a.gait.kind),
					a.gait.n
				)
		)
	end
	for _, id in order do
		local c = clients[id]
		local full = c.full
		SlimeMotor.step(c.motor, now, clientRand, c.actor.mods)
		local rec = trace.slimes[id]
		if not rec then
			rec = {
				species = c.w.species,
				gait = SlimePersona.of(c.w.species).gait,
				temper = SlimePersona.of(c.w.species).temper,
				radius = c.w.radius,
				frames = {},
			}
			trace.slimes[id] = rec
		end
		local j = c.body:FindFirstChild("SkinRoot")
		local drawn = c.body.CFrame * j.C0 * j.Transform
		local foot = drawn * CFrame.new(0, -c.w.radius, 0)
		local right = drawn.RightVector
		local yaw = math.atan2(-right.Z, right.X) -- from the right vector: stays put through a forward flip
		local m = c.actor.mods
		local b = c.body.CFrame.Position
		local tag = if twoPass then b + c.actor.tagOffset else b
		local look = c.body.CFrame.LookVector
		local mesh = c.model:FindFirstChild("Mesh")
		local function r2(x: number): number
			return math.floor(x * 1000 + 0.5) / 1000
		end
		rec.frames[f + 1] = {
			r2(foot.X),
			r2(foot.Z),
			r2(foot.Y - (b.Y - c.w.radius)), -- drawn foot x, z and lift above the Body's foot
			r2(yaw),
			r2(tag.X),
			r2(tag.Z), -- where the name tag and the Buy card hang (the TagAnchor; the Body on older code)
			r2(math.atan2(-look.X, -look.Z)), -- Body heading
			r2(mesh.Size.Y / c.body.Size.Y),
			c.actor.gait.stage,
			m.yawWeight > 0.01 and r2(m.yaw) or false,
			r2(m.yawWeight),
			c.actor.emote or false,
			full,
			r2(b.X),
			r2(b.Z), -- the replicated Body
		}
	end
end

-- Arrays with holes don't encode; give every slime a dense frame list with its first frame index.
for _, rec in trace.slimes do
	local first, list = nil, {}
	for f = 1, frames + 1 do
		local v = rec.frames[f]
		if v then
			first = first or f
			table.insert(list, v)
		elseif first then
			break
		end
	end
	rec.first = first
	rec.frames = list
end

trace.metrics = Metrics.compute(trace)
local path = outPath or `tools/slimesim/out/{scenarioName}-{net}.json`
local dir = string.match(path, "^(.*)/[^/]+$")
if dir and not fs.isDir(dir) then
	fs.writeDir(dir)
end
fs.writeFile(path, serde.encode("json", trace))
print(Metrics.report(trace.metrics))
print(`trace: {path}`)
