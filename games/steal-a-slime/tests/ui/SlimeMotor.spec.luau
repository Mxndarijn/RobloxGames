--!strict
-- SlimeMotor: the procedural Motor6D life of a rigged slime, the driver
-- choice (SlimeAnim.mode / verdict), the fallback when uploaded animations
-- don't load, the LOD cap and static pets.
local fs = require("@lune/fs")

local TestRunner = require("../TestRunner")
local UiHarness = require("./UiHarness")

local describe, it, expect = TestRunner.describe, TestRunner.it, TestRunner.expect

local SlimeAnim = UiHarness.ui("SlimeAnim")
local SlimeLife = UiHarness.ui("SlimeLife")
local SlimeMotor = UiHarness.ui("SlimeMotor")
local SlimeLod = UiHarness.ui("SlimeLod")
local SlimeRig = UiHarness.ui("../visuals/shared/SlimeRig")
local PetRig = UiHarness.ui("../visuals/client/PetRig")
local Config = UiHarness.ui("../shared/Config")
local new = UiHarness.Instance.new
local roblox = require("@lune/roblox") :: any
local CFrame, Vector3 = roblox.CFrame, roblox.Vector3

local function weld(body: any, p: any)
	local w = new("WeldConstraint")
	w.Part0 = body
	w.Part1 = p
	w.Parent = p
end

-- A rigged slime as the factory + SlimeMesh leave it: ball-less body, Mesh skin, a face part.
local function slime(rigged: boolean?): any
	local model = new("Model")
	model:SetAttribute("Tier", 3)
	model:SetAttribute("State", "Wild")
	local body = new("Part")
	body.Name = "Body"
	body.Size = Vector3.new(2, 2, 2)
	body.Anchored = true
	body.Parent = model
	model.PrimaryPart = body
	local mesh = new("MeshPart")
	mesh.Name = "Mesh"
	mesh.Size = Vector3.new(2, 2, 2)
	mesh.Parent = model
	weld(body, mesh)
	local eye = new("Part")
	eye.Name = "EyeWhite1"
	eye.Parent = model
	weld(body, eye)
	if rigged ~= false then
		SlimeRig.attach(model, body)
	end
	return model
end

local function rand(seed: number): () -> number
	local s = seed
	return function()
		s = (s * 1103515245 + 12345) % 2147483648
		return s / 2147483648
	end
end

local function motorOf(model: any, name: string): any
	return model:FindFirstChild("Body"):FindFirstChild(name)
end

-- Largest |Transform| change of a root while stepping `seconds` at 30 Hz.
local function travel(model: any, seconds: number): (number, number)
	local r = rand(3)
	local motor = SlimeMotor.attach(model, 0, r)
	local face = motorOf(model, "FaceRoot")
	local maxY, minY = -1e9, 1e9
	for i = 0, seconds * 30 do
		SlimeMotor.step(motor, i / 30, r)
		local y = face.Transform.Position.Y
		maxY, minY = math.max(maxY, y), math.min(minY, y)
	end
	SlimeMotor.release(motor)
	return minY, maxY
end

describe("SlimeMotor (procedural motion on the rig)", function()
	it("attaches only to a rigged slime", function()
		expect(SlimeMotor.attach(slime(false), 0, rand(1))).toBeNil()
		expect(SlimeMotor.attach(slime(true), 0, rand(1)) ~= nil).toBe(true)
	end)

	it("moves FaceRoot and SkinRoot together (one Transform), squishes the skin and never hops on its own", function()
		local model = slime()
		local r = rand(5)
		local motor = SlimeMotor.attach(model, 0, r)
		local face, skin = motorOf(model, "FaceRoot"), motorOf(model, "SkinRoot")
		local mesh = model:FindFirstChild("Mesh")
		local sizes, lifts = {}, {}
		for i = 0, 20 * 30 do
			SlimeMotor.step(motor, i / 30, r)
			expect(face.Transform == skin.Transform).toBe(true)
			sizes[mesh.Size.Y] = true
			lifts[math.floor(face.Transform.Position.Y * 20)] = true
		end
		local distinctSizes = 0
		for _ in sizes do
			distinctSizes += 1
		end
		expect(distinctSizes > 20).toBe(true)
		local minY, maxY = travel(slime(), 20)
		expect(maxY - minY < 0.3).toBe(true) -- breathing only: slimes glide (contract/slime-walk.md)
	end)

	it("looks left and right on demand (yaw of the Transform) and hops on demand", function()
		local model = slime()
		local r = rand(9)
		local motor = SlimeMotor.attach(model, 0, r)
		local face = motorOf(model, "FaceRoot")
		local function peakYaw(kind: string): number
			SlimeMotor.force(motor, kind, 100)
			local peak = 0
			for i = 0, 15 do
				SlimeMotor.step(motor, 100 + i / 30, r)
				local _, yaw = face.Transform:ToEulerAnglesYXZ()
				if math.abs(yaw) > math.abs(peak) then
					peak = yaw
				end
			end
			return peak
		end
		local left, right = peakYaw("LookLeft"), peakYaw("LookRight")
		expect(left > 0.1).toBe(true)
		expect(right < -0.1).toBe(true)
		model:SetAttribute("LifeForce", "Hop")
		local base = face.Transform.Position.Y
		local top = base
		for i = 0, 30 do
			SlimeMotor.step(motor, 200 + i / 30, r)
			top = math.max(top, face.Transform.Position.Y)
		end
		expect(model:GetAttribute("LifeForce")).toBeNil()
		expect(top - base > 0.2).toBe(true)
	end)

	it("release puts Transforms and the skin Size back", function()
		local model = slime()
		local r = rand(2)
		local motor = SlimeMotor.attach(model, 0, r)
		local mesh = model:FindFirstChild("Mesh")
		local rest = mesh.Size
		for i = 0, 40 do
			SlimeMotor.step(motor, i / 30, r)
		end
		SlimeMotor.release(motor)
		expect(motorOf(model, "FaceRoot").Transform == CFrame.new()).toBe(true)
		expect(motorOf(model, "SkinRoot").Transform == CFrame.new()).toBe(true)
		expect(mesh.Size == rest).toBe(true)
		expect(model:GetAttribute("LifeSkinSize")).toBeNil()
	end)

	it("release after the server rescaled the slime leaves the skin at the new scale, not the old one", function()
		local model = slime()
		local r = rand(4)
		local motor = SlimeMotor.attach(model, 0, r)
		local body, mesh = model:FindFirstChild("Body"), model:FindFirstChild("Mesh")
		local rest = mesh.Size
		for i = 0, 40 do
			SlimeMotor.step(motor, i / 30, r)
		end
		-- the boss's fight size (or growth): the server's ScaleTo replicates new Body and skin sizes
		body.Size = body.Size * 1.5
		mesh.Size = rest * 1.5
		SlimeMotor.release(motor)
		expect((mesh.Size - rest * 1.5).Magnitude < 1e-6).toBe(true)
	end)
end)

describe("driver choice", function()
	local ids = SlimeAnim.ids(function(name: string)
		return `rbxassetid://{#name}`
	end)

	it("ships with the uploaded animations off", function()
		expect(Config.FEATURES.SlimeAnimations).toBe(false)
	end)

	it("flag off: a rigged slime is driven by SlimeMotor, whatever the probe says", function()
		for _, verdict in { "ok", "wait", "failed" } do
			expect(SlimeAnim.mode(false, ids, true, verdict :: any, true)).toBe("motor")
		end
		expect(SlimeAnim.mode(false, nil, false, nil, false)).toBe("weld")
	end)

	it("flag on: uploaded animations only after the probe loaded; otherwise procedural", function()
		expect(SlimeAnim.mode(true, ids, true, "ok", true)).toBe("anim")
		expect(SlimeAnim.mode(true, ids, true, nil, true)).toBe("motor") -- probe not started
		expect(SlimeAnim.mode(true, ids, true, "wait", true)).toBe("motor") -- still loading: never frozen
		expect(SlimeAnim.mode(true, ids, true, "failed", true)).toBe("motor")
		expect(SlimeAnim.mode(true, nil, true, "ok", true)).toBe("motor") -- an id is missing
		expect(SlimeAnim.mode(true, ids, false, "ok", false)).toBe("weld") -- no Animator
	end)

	it("verdict: Length 0 after the timeout, or not playing, is a failed load", function()
		expect(SlimeAnim.verdict(1.25, 0.1, nil)).toBe("ok")
		expect(SlimeAnim.verdict(0, 0.5, nil)).toBe("wait")
		expect(SlimeAnim.verdict(0, SlimeAnim.LOAD_TIMEOUT, nil)).toBe("failed")
		expect(SlimeAnim.verdict(nil, SlimeAnim.LOAD_TIMEOUT + 1, nil)).toBe("failed")
		expect(SlimeAnim.verdict(2.5, SlimeAnim.LOAD_TIMEOUT + 1, false)).toBe("failed")
		expect(SlimeAnim.verdict(2.5, 0.1, true)).toBe("ok")
	end)

	it("the runner falls through anim -> motor -> weld and probes off the select loop", function()
		local src = fs.readFile("src/ui/SlimeLifeRunner.client.luau")
		expect(string.find(src, "Config.FEATURES.SlimeAnimations == true", 1, true) ~= nil).toBe(true)
		expect(string.find(src, "SlimeAnim.mode(", 1, true) ~= nil).toBe(true)
		expect(string.find(src, "pcall(acquireMotor, model)", 1, true) ~= nil).toBe(true)
		expect(string.find(src, "pcall(acquire, model)", 1, true) ~= nil).toBe(true)
		local probe = string.match(src, "local function startProbe.-\nend\n") :: string
		expect(string.find(probe, "task.spawn", 1, true) ~= nil).toBe(true)
		-- a failed probe drops animated rigs back to motors
		expect(string.find(src, 'probe == "failed" or', 1, true) ~= nil).toBe(true)
		-- a track that never plays fails the whole probe
		expect(string.find(src, 'probe = "failed"', 1, true) ~= nil).toBe(true)
	end)
end)

describe("LOD", function()
	it("at most MAX_ACTIVE slimes within 80 studs and on screen get a motor", function()
		local cands, models = {}, {}
		for i = 1, 40 do
			local m = slime()
			m:SetAttribute("SlimeId", `s{i}`)
			models[`s{i}`] = m
			table.insert(cands, {
				id = `s{i}`,
				distance = 5 + i * 2.5, -- 7.5 .. 105
				onScreen = i % 5 ~= 0,
				state = "Wild",
				tier = 3,
			})
		end
		local wanted = SlimeLife.select(cands, {})
		local r = rand(4)
		local count = 0
		for id in wanted do
			local motor = SlimeMotor.attach(models[id], 0, r)
			expect(motor ~= nil).toBe(true)
			count += 1
		end
		expect(count <= SlimeLife.MAX_ACTIVE).toBe(true)
		expect(count).toBe(SlimeLife.MAX_ACTIVE)
		for _, c in cands do
			if wanted[c.id] then
				expect(c.distance <= SlimeLife.MAX_DISTANCE).toBe(true)
				expect(c.onScreen).toBe(true)
			else
				-- nothing outside the set was touched
				expect(models[c.id]:GetAttribute("LifeSkinSize")).toBeNil()
			end
		end
	end)
end)

describe("pets stay static", function()
	it("a pet cloned mid-squash and mid-hop is reset to rest", function()
		local model = slime()
		local mesh = model:FindFirstChild("Mesh")
		local rest = mesh.Size
		local r = rand(6)
		local motor = SlimeMotor.attach(model, 0, r)
		SlimeMotor.force(motor, "Hop", 0)
		for i = 0, 12 do
			SlimeMotor.step(motor, i / 30, r)
		end
		expect(mesh.Size ~= rest).toBe(true)
		model:SetAttribute("LifeAnimating", true)
		model:SetAttribute("LifeMode", "motor")
		local pet = model:Clone()
		PetRig.stripLife(pet)
		expect(UiHarness.find(pet, "Mesh").Size == rest).toBe(true)
		expect(UiHarness.find(pet, "FaceRoot") ~= nil).toBe(true)
		for _, inst in UiHarness.descendants(pet) do
			if inst:IsA("Motor6D") then
				expect(inst.Transform == CFrame.new()).toBe(true)
			end
		end
		expect(pet:GetAttribute("LifeAnimating")).toBeNil()
		expect(pet:GetAttribute("LifeMode")).toBeNil()
		expect(UiHarness.find(pet, "AnimationController")).toBeNil()
	end)

	it("the runner only drives SLIME_TAG models, never the follow-pet clone", function()
		local src = fs.readFile("src/ui/SlimeLifeRunner.client.luau")
		expect(string.find(src, "GetInstanceAddedSignal(Constants.SLIME_TAG)", 1, true) ~= nil).toBe(true)
		expect(string.find(fs.readFile("src/visuals/client/FollowPets.luau"), "PetRig.stripLife(pet)", 1, true) ~= nil).toBe(
			true
		)
	end)
end)

describe("LOD tiers", function()
	local cfg = Config.SLIME_LOD
	local function tiers(level: number?, distances: { number }): { string }
		local out = {}
		for _, d in distances do
			table.insert(out, SlimeLod.tierFor(cfg, level, d, nil))
		end
		return out
	end

	it("has its thresholds in Config", function()
		expect(cfg.NEAR < cfg.MID).toBe(true)
		expect(cfg.NEAR_LOW < cfg.NEAR and cfg.MID_LOW < cfg.MID).toBe(true)
		expect(cfg.MID < SlimeLife.MAX_DISTANCE).toBe(true)
		expect(cfg.MID_EVERY >= 2 and cfg.MID_AMPLITUDE < 1).toBe(true)
	end)

	it("picks near / mid / far by distance, with smaller radii at low quality", function()
		local d = { 5, cfg.NEAR + 1, cfg.MID + 1, 79 }
		local normal = tiers(10, d)
		expect(normal[1]).toBe("near")
		expect(normal[2]).toBe("mid")
		expect(normal[3]).toBe("far")
		expect(normal[4]).toBe("far")
		expect(tiers(nil, d)[2]).toBe("mid")
		expect(tiers(0, d)[2]).toBe("mid") -- Automatic counts as normal
		-- the same distances one tier down at low quality
		local low = tiers(2, { cfg.NEAR_LOW + 1, cfg.MID_LOW + 1, cfg.NEAR - 1 })
		expect(low[1]).toBe("mid")
		expect(low[2]).toBe("far")
		expect(low[3]).toBe("mid")
		expect(SlimeLod.tierFor(cfg, 1, 0 / 0, nil)).toBe("far")
	end)

	it("hysteresis keeps a slime on the border in its tier", function()
		local d = cfg.NEAR * (1 + cfg.HYSTERESIS / 2)
		expect(SlimeLod.tierFor(cfg, 10, d, "near")).toBe("near")
		expect(SlimeLod.tierFor(cfg, 10, d, "mid")).toBe("mid")
		expect(SlimeLod.tierFor(cfg, 10, d, nil)).toBe("mid")
	end)

	it("reads the saved quality level safely (enum item, number, error, nothing)", function()
		expect(SlimeLod.readQuality({ SavedQualityLevel = { Value = 3 } })).toBe(3)
		expect(SlimeLod.readQuality({ SavedQualityLevel = 7 })).toBe(7)
		expect(SlimeLod.readQuality(setmetatable({}, {
			__index = function()
				error("no access")
			end,
		}))).toBeNil()
		expect(SlimeLod.readQuality({})).toBeNil()
		expect(SlimeLod.readQuality(nil)).toBeNil()
	end)

	it("mid slimes are written every MID_EVERY frames, near every frame, far never", function()
		local mid, near, far = 0, 0, 0
		for frame = 1, cfg.MID_EVERY * 10 do
			mid += if SlimeLod.due("mid", frame, 1, cfg) then 1 else 0
			near += if SlimeLod.due("near", frame, 1, cfg) then 1 else 0
			far += if SlimeLod.due("far", frame, 1, cfg) then 1 else 0
		end
		expect(mid).toBe(10)
		expect(near).toBe(cfg.MID_EVERY * 10)
		expect(far).toBe(0)
		-- slots stagger: across MID_EVERY slots exactly one slime is due per frame
		for frame = 1, 6 do
			local due = 0
			for slot = 0, cfg.MID_EVERY - 1 do
				due += if SlimeLod.due("mid", frame, slot, cfg) then 1 else 0
			end
			expect(due).toBe(1)
		end
	end)

	it("the mid tier squishes with a smaller amplitude and nothing else", function()
		local model = slime()
		local motor = SlimeMotor.attach(model, 0, rand(2))
		local face = motorOf(model, "FaceRoot")
		local mesh = model:FindFirstChild("Mesh")
		local rest = mesh.Size
		local fullLo, fullHi, midLo, midHi = 9, -9, 9, -9
		for i = 0, 200 do
			local now = i / 20
			local sy = SlimeLife.squishY(motor.params, motor.clock, now, 1)
			fullLo, fullHi = math.min(fullLo, sy), math.max(fullHi, sy)
			SlimeMotor.stepSquish(motor, now, cfg.MID_AMPLITUDE)
			midLo, midHi = math.min(midLo, mesh.Size.Y / rest.Y), math.max(midHi, mesh.Size.Y / rest.Y)
			local _, yaw = face.Transform:ToEulerAnglesYXZ()
			expect(math.abs(yaw) < 1e-6).toBe(true) -- no look
			expect(face.Transform.Position.Y <= 0.5).toBe(true) -- no hop
			expect(face.Transform == motorOf(model, "SkinRoot").Transform).toBe(true)
		end
		expect(midHi - midLo > 0.01).toBe(true)
		expect(midHi - midLo < (fullHi - fullLo) * 0.75).toBe(true)
	end)

	it("a far slime is reset to identity once, then skipped; stepping wakes it", function()
		local model = slime()
		local r = rand(8)
		local motor = SlimeMotor.attach(model, 0, r)
		local face, skin = motorOf(model, "FaceRoot"), motorOf(model, "SkinRoot")
		local mesh = model:FindFirstChild("Mesh")
		local rest = mesh.Size
		for i = 0, 40 do
			SlimeMotor.step(motor, i / 30, r)
		end
		expect(face.Transform ~= CFrame.new() or mesh.Size ~= rest).toBe(true)
		expect(SlimeMotor.park(motor)).toBe(true)
		expect(face.Transform == CFrame.new()).toBe(true)
		expect(skin.Transform == CFrame.new()).toBe(true)
		expect(mesh.Size == rest).toBe(true)
		-- skipped: a changed Transform is not overwritten by further parks
		local mark = CFrame.new(0, 7, 0)
		face.Transform = mark
		expect(SlimeMotor.park(motor)).toBe(false)
		expect(face.Transform == mark).toBe(true)
		SlimeMotor.step(motor, 5, r)
		expect(motor.parked).toBe(false)
		expect(SlimeMotor.park(motor)).toBe(true)
	end)

	it("the cap of 16 and the on-screen check hold with the LOD on", function()
		local cands = {}
		for i = 1, 40 do
			table.insert(
				cands,
				{ id = `s{i}`, distance = 5 + i * 1.8, onScreen = i % 4 ~= 0, state = "Wild", tier = 3 }
			)
		end
		local wanted = SlimeLife.select(cands, {})
		local count, counts = 0, { near = 0, mid = 0, far = 0 }
		for _, c in cands do
			if wanted[c.id] then
				count += 1
				expect(c.onScreen).toBe(true)
				local t = SlimeLod.tierFor(cfg, 10, c.distance, nil)
				counts[t] += 1
			end
		end
		expect(count).toBe(SlimeLife.MAX_ACTIVE)
		expect(counts.near + counts.mid + counts.far).toBe(16)
		expect(counts.near > 0 and counts.mid > 0).toBe(true)
	end)

	it("the runner reselects 4x a second and reads quality via the module", function()
		local src = fs.readFile("src/ui/SlimeLifeRunner.client.luau")
		expect(string.find(src, "SELECT_EVERY = 0.25", 1, true) ~= nil).toBe(true)
		expect(string.find(src, "SlimeLod.tierFor(", 1, true) ~= nil).toBe(true)
		expect(string.find(src, "SlimeMotor.park", 1, true) ~= nil).toBe(true)
		expect(string.find(src, "SlimeLod.readQuality(", 1, true) ~= nil).toBe(true)
		-- the per-frame loop sorts nothing
		local frameLoop = string.match(src, "RenderStepped:Connect.*$") :: string
		expect(string.find(frameLoop, "table.sort", 1, true)).toBeNil()
	end)
end)
