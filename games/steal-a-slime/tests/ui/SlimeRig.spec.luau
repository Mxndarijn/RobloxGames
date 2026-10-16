--!strict
-- The slime rig (src/visuals/shared/SlimeRig, v28 #17): Motor6Ds from Body
-- to FaceRoot / SkinRoot, an Animator, welds moved onto the roots; the
-- animation ids (MeshAssets / uploaded.json) and the procedural fallback.
local fs = require("@lune/fs")
local serde = require("@lune/serde")

local MeshAssets = require("../../src/shared/MeshAssets")
local SlimeAnim = require("../../src/ui/SlimeAnim")
local SlimeLife = require("../../src/ui/SlimeLife")
local TestRunner = require("../TestRunner")
local UiHarness = require("./UiHarness")

local describe, it, expect = TestRunner.describe, TestRunner.it, TestRunner.expect

local SlimeRig = UiHarness.ui("../visuals/shared/SlimeRig")
local new = UiHarness.Instance.new

local function part(model: any, name: string, body: any?): any
	local p = new("Part")
	p.Name = name
	p.Parent = model
	if body then
		local weld = new("WeldConstraint")
		weld.Part0 = body
		weld.Part1 = p
		weld.Parent = p
	end
	return p
end

local function slime(): (any, any)
	local model = new("Model")
	local body = part(model, "Body")
	part(model, "EyeWhite1", body)
	part(model, "MouthMid", body)
	part(model, "TierRim", body)
	part(model, "Mesh", body)
	return model, body
end

local function read(path: string): string
	return fs.readFile(path)
end

describe("SlimeRig.attach", function()
	it("joins FaceRoot and SkinRoot to Body with Motor6Ds", function()
		local model, body = slime()
		SlimeRig.attach(model, body)
		local motors = {}
		for _, inst in UiHarness.descendants(model) do
			if inst:IsA("Motor6D") then
				motors[inst.Name] = inst
			end
		end
		expect(motors.FaceRoot ~= nil and motors.SkinRoot ~= nil).toBe(true)
		for name, motor in motors do
			expect(motor.Part0 == body).toBe(true)
			expect(motor.Part1.Name).toBe(name)
			expect(motor.Parent == body).toBe(true)
		end
	end)

	it("adds an AnimationController with an Animator", function()
		local model, body = slime()
		expect(SlimeRig.isRigged(model)).toBe(false)
		SlimeRig.attach(model, body)
		expect(SlimeRig.isRigged(model)).toBe(true)
		expect(SlimeRig.animator(model) ~= nil).toBe(true)
		expect(SlimeRig.animator(model).Parent.ClassName).toBe("AnimationController")
	end)

	it("holds the face to FaceRoot and every other decoration to SkinRoot, none to Body", function()
		local model, body = slime()
		SlimeRig.attach(model, body)
		local face, skin = model:FindFirstChild("FaceRoot"), model:FindFirstChild("SkinRoot")
		local expected = { EyeWhite1 = face, MouthMid = face, TierRim = skin, Mesh = skin }
		for name, root in expected do
			local weld = model:FindFirstChild(name):FindFirstChildWhichIsA("WeldConstraint")
			expect(weld.Part0 == root).toBe(true)
			expect(weld.Part1.Name).toBe(name)
		end
		expect(SlimeRig.anchorFor(model, body) == skin).toBe(true)
	end)

	it("makes invisible, massless, non-colliding roots", function()
		local model, body = slime()
		SlimeRig.attach(model, body)
		for _, name in { "FaceRoot", "SkinRoot" } do
			local root = model:FindFirstChild(name)
			expect(root.Transparency).toBe(1)
			expect(root.Massless).toBe(true)
			expect(root.CanCollide).toBe(false)
			expect(root.Anchored).toBe(false)
		end
	end)

	it("sorts face parts by name", function()
		expect(SlimeRig.isFacePart("EyeWhite2")).toBe(true)
		expect(SlimeRig.isFacePart("MouthL")).toBe(true)
		expect(SlimeRig.isFacePart("CrownBand")).toBe(false)
		expect(SlimeRig.isFacePart("Mesh")).toBe(false)
	end)

	it("is wired into the factory and the mesh look", function()
		expect(
			string.find(read("src/visuals/shared/ModelFactory.luau"), "SlimeRig.attach(model, body)", 1, true) ~= nil
		).toBe(true)
		expect(string.find(read("src/server/SlimeMesh.luau"), "anchorFor(model, body)", 1, true) ~= nil).toBe(true)
	end)
end)

describe("animation ids", function()
	it("are in MeshAssets and match uploaded.json", function()
		local uploaded = serde.decode("json", read("../../shared/modeling-kit/uploaded.json")) :: any
		for _, name in SlimeAnim.NAMES do
			local id = MeshAssets.animationId(name)
			expect(id ~= nil).toBe(true)
			expect(uploaded[name].assetType).toBe("Animation")
			expect(id).toBe(`rbxassetid://{uploaded[name].assetId}`)
		end
		expect(MeshAssets.animationId("SlimeBlink")).toBeNil()
	end)

	it("every animation has a KeyframeSequence in animations/", function()
		for _, name in SlimeAnim.NAMES do
			expect(string.find(read(`animations/{name}.rbxmx`), 'class="KeyframeSequence"', 1, true) ~= nil).toBe(true)
		end
	end)
end)

describe("procedural fallback", function()
	it("SlimeAnim.ids is nil when any id is missing", function()
		expect(SlimeAnim.ids(function()
			return nil
		end)).toBeNil()
		expect(SlimeAnim.ids(function(name: string)
			return if name == "SlimeHop" then nil else "rbxassetid://1"
		end)).toBeNil()
		expect(SlimeAnim.ids(function(name: string)
			return `rbxassetid://{#name}`
		end) ~= nil).toBe(true)
	end)

	it("the runner only animates with ids and an Animator, and falls back to the LifeRoot rig", function()
		local src = read("src/ui/SlimeLifeRunner.client.luau")
		expect(string.find(src, "SlimeAnim.ids(MeshAssets.animationId)", 1, true) ~= nil).toBe(true)
		expect(string.find(src, "if animationIds then", 1, true) ~= nil).toBe(true)
		expect(string.find(src, "pcall(acquire, model)", 1, true) ~= nil).toBe(true)
		-- no Size writes in the animated path
		local anim = string.match(src, "local function stepAnim.-\nend\n") :: string
		expect(string.find(anim, ".Size", 1, true)).toBeNil()
	end)

	it("SlimeLife still poses slimes without any asset", function()
		local params = SlimeLife.params(3, "Wild")
		local clock = SlimeLife.newClock(params, 0, function()
			return 0.5
		end)
		local pose = SlimeLife.pose(params, clock, 1)
		expect(pose.sy > 0.5 and pose.sy < 1.5).toBe(true)
	end)
end)
