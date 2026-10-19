--!strict
-- v28 slime audit (docs/slime-audit-v28.md): every roster type has a look
-- (colour, material, kit mesh) and resolves idle / wobble / move, and the
-- visuals client really plays those procedural states.
local fs = require("@lune/fs")

local Config = require("../src/shared/Config")
local Constants = require("../src/shared/Constants")
local Fixtures = require("./Fixtures")
local Genome = require("../src/shared/Genome")
local MeshAssets = require("../src/shared/MeshAssets")
local Rng = require("../src/shared/Rng")
local SlimeLooks = require("../src/shared/SlimeLooks")
local SlimeMesh = require("../src/server/SlimeMesh")
local SlimeRoster = require("../src/shared/SlimeRoster")
local TestRunner = require("./TestRunner")

local describe, it, expect = TestRunner.describe, TestRunner.it, TestRunner.expect

local CONTROLLER = "src/visuals/client/init.client.luau"

describe("SlimeLooks roster audit", function()
	it("gives every roster type a colour, a body material and a kit mesh name", function()
		for _, entry in SlimeRoster.ROSTER do
			local look = SlimeLooks.get(entry.id)
			expect(look ~= nil).toBe(true)
			local l = look :: SlimeLooks.Look
			expect(l.id).toBe(entry.id)
			expect(#l.color).toBe(3)
			for _, c in l.color do
				expect(c == math.floor(c) and c >= 0 and c <= 255).toBe(true)
			end
			expect(SlimeLooks.isMaterial(l.material)).toBe(true)
			expect(table.find(SlimeLooks.KITS, l.kit) ~= nil).toBe(true)
		end
	end)

	it("resolves idle, wobble and move for every roster type", function()
		expect(SlimeLooks.ANIM_STATES).toEqual({ "idle", "wobble", "move" })
		for _, entry in SlimeRoster.ROSTER do
			for _, state in SlimeLooks.ANIM_STATES do
				local anim = SlimeLooks.anim(entry.id, state)
				expect(anim ~= nil).toBe(true)
				local a = anim :: SlimeLooks.Anim
				expect(a.state).toBe(state)
				expect(a.frequency > 0 and a.amplitude > 0).toBe(true)
				-- Procedural fallback needs no asset; a real animation needs a real id.
				if a.source == "Animation" then
					expect(string.match(a.animationId or "", "^rbxassetid://%d+$") ~= nil).toBe(true)
				else
					expect(a.source).toBe("Procedural")
				end
			end
		end
	end)

	it("returns nothing for unknown types or states", function()
		expect(SlimeLooks.get("nope")).toBeNil()
		expect(SlimeLooks.get(nil)).toBeNil()
		expect(SlimeLooks.anim("nope", "idle")).toBeNil()
		expect(SlimeLooks.anim("gummy", "dance")).toBeNil()
	end)

	it("has the visuals client play each procedural state with the same numbers", function()
		local src = fs.readFile(CONTROLLER)
		local function has(needle: string): boolean
			return string.find(src, needle, 1, true) ~= nil
		end
		expect(has("CollectionService:GetInstanceAddedSignal(Constants.SLIME_TAG)")).toBe(true)
		local idle = SlimeLooks.anim("gummy", "idle") :: SlimeLooks.Anim
		local wobble = SlimeLooks.anim("gummy", "wobble") :: SlimeLooks.Anim
		local move = SlimeLooks.anim("gummy", "move") :: SlimeLooks.Anim
		expect(has(`math.sin(t * {idle.frequency}) * 0.5 + 0.5) * {idle.amplitude} * size`)).toBe(true)
		expect(has(`math.sin(t * {wobble.frequency}) * {wobble.amplitude}`)).toBe(true)
		expect(has(`if state == "{move.slimeState}" then`)).toBe(true)
		expect(has(`math.abs(math.sin(t * {move.frequency})) * {move.amplitude} * size`)).toBe(true)
	end)

	it("only names uploaded species kits that are in MeshAssets, with a size and an offset", function()
		for _, kit in SlimeLooks.KITS do
			local entry = MeshAssets.get(kit) :: MeshAssets.Entry
			expect(entry ~= nil).toBe(true)
			expect(entry.assetId ~= nil and (entry.assetId :: number) > 0).toBe(true)
			expect(#(entry.size :: { number })).toBe(3)
			expect(#(entry.offset :: { number })).toBe(3)
			expect(table.find(MeshAssets.NAMES, kit)).toBeNil() -- worn by SlimeMesh, never a world slot
		end
		expect(Config.SLIME_MESH_ASSET_ID > 0).toBe(true)
	end)
end)

describe("SlimeLooks wiring", function()
	it("gives generated typed slimes their type's colour", function()
		local rng = Rng.new(28)
		local typed = 0
		for i = 1, 200 do
			local slime = Genome.generate(rng, { id = `s{i}` })
			if slime.species then
				typed += 1
				local look = SlimeLooks.get(slime.species) :: SlimeLooks.Look
				expect(slime.color).toEqual({ look.color[1], look.color[2], look.color[3] })
			end
		end
		expect(typed > 0).toBe(true)
	end)

	it("tags a typed slime model with its Species attribute", function()
		local attrs: { [string]: any } = {}
		local model = {
			SetAttribute = function(_, name: string, value: any)
				attrs[name] = value
			end,
			FindFirstChild = function(): any
				return nil
			end,
		}
		local mesh = SlimeMesh.new({
			factory = {
				build = function(): any
					return model
				end,
			} :: any,
			loadAsset = function(): any
				error("no asset")
			end,
			warn = function() end,
		})
		local slime = Fixtures.slime("a", 3, { species = "moo" })
		expect(SlimeMesh.build(mesh, slime)).toBe(model :: any)
		expect(attrs[Constants.SPECIES_ATTRIBUTE]).toBe("moo")
	end)

	it("hands every loaded species kit to onKit (the SlimeDex copies them for the client)", function()
		local handed: { [string]: any } = {}
		local function fakeMesh(): any
			local m = {}
			function m.Clone()
				return fakeMesh()
			end
			return m
		end
		local mesh = SlimeMesh.new({
			factory = { build = function(): any end } :: any,
			loadAsset = function(assetId: number): any
				if assetId == (MeshAssets.get("slime_moo") :: any).assetId then
					error("this one fails")
				end
				return {
					FindFirstChildWhichIsA = function()
						return fakeMesh()
					end,
					Destroy = function() end,
				}
			end,
			spawn = function(fn: () -> ())
				fn()
			end,
			warn = function() end,
			onKit = function(kit: string, template: any)
				handed[kit] = template
			end,
		})
		SlimeMesh.load(mesh)
		expect(handed.slime_gummy ~= nil).toBe(true)
		expect(handed.slime_gummy).toBe(mesh.kits.slime_gummy)
		expect(handed.slime_moo).toBeNil() -- a kit that failed to load is not handed on
	end)
end)
