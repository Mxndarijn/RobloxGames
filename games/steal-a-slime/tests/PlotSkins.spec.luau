--!strict
-- Plot skins unlocked by SlimeDex sets (gaps #15, CONTRACT.md §15): unlock thresholds, the equip
-- remote, the save field, the per-plot visuals and the mesh budget. FEATURES.PlotSkins is off.
local fs = require("@lune/fs")
local roblox = require("@lune/roblox") :: any

local Actions = require("../src/server/Actions")
local Config = require("../src/shared/Config")
local Constants = require("../src/shared/Constants")
local MeshAssets = require("../src/shared/MeshAssets")
local PlayerData = require("../src/shared/PlayerData")
local PlotSkins = require("../src/shared/PlotSkins")
local RanchProps = require("../src/visuals/shared/RanchProps")
local Remotes = require("../src/shared/Remotes")
local SaveData = require("../src/shared/SaveData")
local ServerFixtures = require("./ServerFixtures")
local Snapshot = require("../src/server/Snapshot")
local SpeciesDex = require("../src/shared/SpeciesDex")
local StaticWorld = require("../scripts/StaticWorld")
local TestRunner = require("./TestRunner")
local Validate = require("../src/shared/Validate")
local WorldBudget = require("./WorldBudget.spec")
local WorldLayout = require("../src/visuals/shared/WorldLayout")

local describe, it, expect = TestRunner.describe, TestRunner.it, TestRunner.expect
local T0 = ServerFixtures.T0
local Color3, Vector3 = roblox.Color3, roblox.Vector3

local function skin(id: string): Config.PlotSkin
	return PlotSkins.get(id) :: Config.PlotSkin
end

-- A profile that found `count` species entries of `tier`.
local function withSet(tier: number, count: number): PlayerData.Data
	local data = PlayerData.new()
	local n = 0
	for _, entry in SpeciesDex.ENTRIES do
		if entry.tier == tier and n < count then
			data.found[entry.id] = true
			n += 1
		end
	end
	return data
end

-- Species in a tier's set, and how many unlock its skin (75 %).
local function size(tier: number): number
	return SpeciesDex.tierSize(tier)
end
local function need(tier: number): number
	return math.ceil(size(tier) * 0.75)
end

local ctx: Actions.Context = {
	distanceBetween = function()
		return 2
	end,
	positionOf = function()
		return nil
	end,
	features = { PlotSkins = true },
}
local offCtx: Actions.Context = { distanceBetween = ctx.distanceBetween, positionOf = ctx.positionOf }

local function equip(world: any, userId: number, id: any, c: Actions.Context?)
	world.sessions[userId].limiter = {}
	return Actions.handle(world, userId, "EquipPlotSkin", { id }, T0 + 100, c or ctx)
end

describe("plot skins: config", function()
	it("is behind FEATURES.PlotSkins, default off", function()
		expect(Config.FEATURES.PlotSkins).toBe(false)
	end)
	it("lists 3 unlockable skins after classic, each tied to a Dex tier at 75 %", function()
		expect(Config.PLOT_SKINS[1].id).toBe("classic")
		expect(Config.PLOT_SKINS[1].set).toBeNil()
		expect(Config.PLOT_SKIN_DEFAULT).toBe("classic")
		expect(#Config.PLOT_SKINS).toBe(4)
		local ids = {}
		for i, s in Config.PLOT_SKINS do
			expect(ids[s.id]).toBeNil()
			ids[s.id] = true
			if i > 1 then
				expect(s.set ~= nil and s.set >= 1 and s.set <= Config.MAX_TIER).toBe(true)
				expect(s.threshold).toBe(0.75)
				expect(s.floor ~= nil and s.fence ~= nil).toBe(true)
				local entry = MeshAssets.get(s.decor :: string)
				expect(entry ~= nil and entry.meshId ~= nil and entry.size ~= nil).toBe(true)
			end
		end
	end)
	it("keeps the skin palettes warm and bright (no near-black floors)", function()
		for _, s in Config.PLOT_SKINS do
			if s.floor then
				expect(math.max(s.floor.color[1], s.floor.color[2], s.floor.color[3]) >= 140).toBe(true)
			end
		end
	end)
end)

describe("plot skins: unlock thresholds", function()
	it("a Dex set is its tier's species entries, and the sets add up to the Dex", function()
		local total = 0
		for tier = 1, Config.MAX_TIER do
			expect(PlotSkins.setSize(tier)).toBe(size(tier))
			expect(size(tier) > 0).toBe(true)
			total += size(tier)
		end
		expect(total).toBe(SpeciesDex.TOTAL)
	end)
	it("unlocks at ceil(75 % of the set) keys: one short is locked, exactly enough is unlocked", function()
		local needed = PlotSkins.needed(skin("mushroom"))
		expect(needed).toBe(need(1))
		expect(PlotSkins.unlocked(withSet(1, needed - 1), skin("mushroom"))).toBe(false)
		expect(PlotSkins.unlocked(withSet(1, needed), skin("mushroom"))).toBe(true)
		expect(PlotSkins.unlocked(withSet(1, size(1)), skin("mushroom"))).toBe(true)
	end)
	it("counts only the skin's own tier", function()
		expect(PlotSkins.unlocked(withSet(2, size(2)), skin("mushroom"))).toBe(false)
		expect(PlotSkins.unlocked(withSet(2, need(2)), skin("candy"))).toBe(true)
		expect(PlotSkins.unlocked(withSet(3, need(3)), skin("crystal"))).toBe(true)
		expect(PlotSkins.unlocked(withSet(3, need(3)), skin("candy"))).toBe(false)
	end)
	it("counts species, not bonus entries", function()
		local data = withSet(1, need(1) - 1)
		data.found.glitch = true -- an event Secret
		data.found.nope = true
		expect(PlotSkins.owned(data, 1)).toBe(need(1) - 1)
		expect(PlotSkins.unlocked(data, skin("mushroom"))).toBe(false)
	end)
	it("classic is always unlocked, and view() reports progress with classic first", function()
		local data = withSet(1, 2)
		local view = PlotSkins.view(data)
		expect(#view).toBe(#Config.PLOT_SKINS)
		expect(view[1].id).toBe("classic")
		expect(view[1].unlocked and view[1].equipped).toBe(true)
		expect(view[2].owned).toBe(2)
		expect(view[2].needed).toBe(need(1))
		expect(view[2].total).toBe(size(1))
		expect(view[2].unlocked).toBe(false)
		expect(view[2].setName).toBe("Common")
		expect(math.abs(view[2].fraction - 2 / size(1)) < 1e-9).toBe(true)
		expect(view[3].owned).toBe(0)
	end)
end)

describe("plot skins: equip", function()
	it("PlotSkins.equip refuses unknown and locked skins and leaves the profile alone", function()
		local data = withSet(1, 1)
		local ok, why = PlotSkins.equip(data, "nope")
		expect(ok).toBe(false)
		expect(why).toBe("unknown plot skin")
		ok, why = PlotSkins.equip(data, "mushroom")
		expect(ok).toBe(false)
		expect(why).toBe("plot skin is locked")
		expect(data.plotSkin).toBe("classic")
		expect(PlotSkins.equip(data, 42 :: any)).toBe(false)
	end)
	it("equips an unlocked skin, and classic always", function()
		local data = withSet(1, need(1))
		expect(PlotSkins.equip(data, "mushroom")).toBe(true)
		expect(data.plotSkin).toBe("mushroom")
		expect(PlotSkins.current(data)).toBe("mushroom")
		expect(PlotSkins.equip(data, "classic")).toBe(true)
		expect(data.plotSkin).toBe("classic")
	end)
	it("current() never shows a skin the profile has not unlocked", function()
		local data = PlayerData.new()
		data.plotSkin = "crystal"
		expect(PlotSkins.current(data)).toBe("classic")
		data.plotSkin = "bogus"
		expect(PlotSkins.current(data)).toBe("classic")
	end)
	it("is a rate-limited Request action", function()
		expect(Remotes.ACTIONS.EquipPlotSkin.args[1]).toBe("string")
		expect(Validate.ACTIONS.EquipPlotSkin ~= nil).toBe(true)
	end)
	it("the Request refuses a locked skin, and equips an unlocked one", function()
		local world = ServerFixtures.world()
		local session = ServerFixtures.join(world, 1, {}, 0)
		local res = equip(world, 1, "mushroom")
		expect(res.ok).toBe(false)
		expect(res.message).toBe("plot skin is locked")
		expect(session.data.plotSkin).toBe("classic")
		for key in withSet(1, need(1)).found do
			session.data.found[key] = true
		end
		res = equip(world, 1, "mushroom")
		expect(res.ok).toBe(true)
		expect(session.data.plotSkin).toBe("mushroom")
		expect(Snapshot.build(world, session, T0).plotSkin).toBeNil() -- flag off: not in State
	end)
	it("the Request rejects bad arguments and unknown ids", function()
		local world = ServerFixtures.world()
		ServerFixtures.join(world, 1, {}, 0)
		expect(equip(world, 1, nil).ok).toBe(false)
		expect(equip(world, 1, 12).ok).toBe(false)
		expect(equip(world, 1, "../x").ok).toBe(false)
		expect(equip(world, 1, "bogus").message).toBe("unknown plot skin")
	end)
	it("with the flag off the Request is refused, even for an unlocked skin", function()
		local world = ServerFixtures.world()
		local session = ServerFixtures.join(world, 1, {}, 0)
		for key in withSet(1, size(1)).found do
			session.data.found[key] = true
		end
		local res = equip(world, 1, "mushroom", offCtx)
		expect(res.ok).toBe(false)
		expect(res.message).toBe("plot skins are off")
		expect(session.data.plotSkin).toBe("classic")
	end)
	it("flag off: State carries no plot skin fields", function()
		local world = ServerFixtures.world()
		local session = ServerFixtures.join(world, 1, {}, 0)
		local state = Snapshot.build(world, session, T0)
		expect(state.plotSkin).toBeNil()
		expect(state.plotSkins).toBeNil()
	end)
end)

describe("plot skins: save", function()
	it("writes plotSkin at the current SAVE_VERSION", function()
		local data = withSet(2, need(2))
		data.plotSkin = "candy"
		local out = SaveData.serialize(data, T0)
		expect(out.plotSkin).toBe("candy")
		expect(out.version).toBe(Config.SAVE_VERSION)
	end)
	it("round-trips an unlocked skin", function()
		local data = withSet(2, need(2))
		data.plotSkin = "candy"
		local back = SaveData.deserialize(SaveData.serialize(data, T0))
		expect(back.plotSkin).toBe("candy")
	end)
	it("migrates saves from before plot skins (v1, v3, v4, v5 without the field) to classic", function()
		expect(SaveData.deserialize({ Cash = 5, Rebirths = 0, Slimes = {} }).plotSkin).toBe("classic")
		expect(SaveData.deserialize({ version = 3, cash = 10 }).plotSkin).toBe("classic")
		expect(SaveData.deserialize({ version = 4, cash = 10 }).plotSkin).toBe("classic")
		local v5 = SaveData.serialize(PlayerData.new(), T0)
		v5.plotSkin = nil
		expect(SaveData.deserialize(v5).plotSkin).toBe("classic")
		expect(SaveData.deserialize(nil).plotSkin).toBe("classic")
	end)
	it("loads unknown, garbage or not-unlocked skins as classic", function()
		local stored = SaveData.serialize(PlayerData.new(), T0)
		for _, bad in { "crystal", "bogus", 7, true, "", {} } do
			stored.plotSkin = bad
			expect(SaveData.deserialize(stored).plotSkin).toBe("classic")
		end
	end)
	it("SaveData.migratePlotSkin is pure and defaults to classic", function()
		local data = withSet(3, need(3))
		expect(SaveData.migratePlotSkin({ plotSkin = "crystal" }, data)).toBe("crystal")
		expect(SaveData.migratePlotSkin({ plotSkin = "candy" }, data)).toBe("classic")
		expect(SaveData.migratePlotSkin(nil, data)).toBe("classic")
	end)
end)

-- The static world (Lune): plots and the Map.Decor mailbox slots.
local world = StaticWorld.build()
local plots, decor
for _, root in world do
	if root.Name == Constants.PLOTS_FOLDER then
		plots = root
	elseif root.Name == WorldLayout.MAP_NAME then
		decor = root:FindFirstChild("Decor")
	end
end
local PlotDecor = StaticWorld.visual("PlotDecor")

local function fakeTemplates(): any
	local folder = plots:Clone() -- any Folder-like parent; emptied below
	folder:ClearAllChildren()
	for _, s in Config.PLOT_SKINS do
		if s.decor then
			local mesh = (plots :: any):FindFirstChild("Plot_1"):FindFirstChild("Base"):Clone()
			mesh.Name = s.decor
			mesh.Size = Vector3.new(5, 6, 4)
			mesh.Parent = folder
		end
	end
	return folder
end

local function look(plot: any): { [string]: any }
	local out = {}
	for _, d in plot:GetDescendants() do
		if d:IsA("BasePart") then
			out[d:GetFullName()] = { d.Color, d.Material, d.Transparency }
		end
	end
	return out
end

describe("plot skins: visuals applied per plot", function()
	it("paints one plot's floor, fence and decor and leaves the others as built", function()
		local p1, p2 = plots:FindFirstChild("Plot_1"), plots:FindFirstChild("Plot_2")
		local slot = decor:FindFirstChild("Mailbox_1")
		local classic1, classic2 = look(p1), look(p2)
		local templates = fakeTemplates()
		for _, s in Config.PLOT_SKINS do
			if s.id == "classic" then
				continue
			end
			PlotDecor.applySkin(p1, s.id, slot, templates)
			local base = p1:FindFirstChild("Base")
			local floor = s.floor :: any
			expect(base.Color).toBe(Color3.fromRGB(floor.color[1], floor.color[2], floor.color[3]))
			expect(base.Material.Name).toBe(floor.material)
			local tinted = 0
			for _, name in { "Fence", "Gate" } do
				for _, d in p1:FindFirstChild(name):GetDescendants() do
					if d:IsA("BasePart") and d.Transparency < 1 then
						tinted += 1
						expect(d.Color ~= classic1[d:GetFullName()][1]).toBe(true)
					end
				end
			end
			expect(tinted > 0).toBe(true)
			local mesh = slot:FindFirstChild(PlotDecor.SKIN_DECOR_NAME)
			expect(mesh ~= nil and mesh:GetAttribute("Skin") == s.decor).toBe(true)
			expect(slot.Transparency).toBe(1)
			-- every other plot is untouched
			expect(look(p2)).toEqual(classic2)
		end
		-- back to classic: everything as built, the decor gone
		PlotDecor.applySkin(p1, "classic", slot, templates)
		expect(slot:FindFirstChild(PlotDecor.SKIN_DECOR_NAME)).toBeNil()
		expect(look(p1)).toEqual(classic1)
	end)
	it("is idempotent and swaps the decor when the skin changes", function()
		local p1, slot = plots:FindFirstChild("Plot_1"), decor:FindFirstChild("Mailbox_1")
		local templates = fakeTemplates()
		PlotDecor.applySkin(p1, "candy", slot, templates)
		local first = slot:FindFirstChild(PlotDecor.SKIN_DECOR_NAME)
		PlotDecor.applySkin(p1, "candy", slot, templates)
		expect(slot:FindFirstChild(PlotDecor.SKIN_DECOR_NAME)).toBe(first)
		PlotDecor.applySkin(p1, "crystal", slot, templates)
		expect(slot:FindFirstChild(PlotDecor.SKIN_DECOR_NAME):GetAttribute("Skin")).toBe("plot_skin_crystal")
		PlotDecor.applySkin(p1, "classic", slot, templates)
	end)
	it("stands the decor on the mailbox's bottom at its scale, one decor child per slot", function()
		local p1, slot = plots:FindFirstChild("Plot_1"), decor:FindFirstChild("Mailbox_1")
		local templates = fakeTemplates()
		PlotDecor.applySkin(p1, "mushroom", slot, templates)
		local mesh = slot:FindFirstChild(PlotDecor.SKIN_DECOR_NAME)
		local mailbox = (MeshAssets.get("ranch_mailbox") :: any).size
		local scale = slot.Size.Y / mailbox[2]
		expect(math.abs(mesh.Size.Y - 6 * scale) < 1e-6).toBe(true)
		local bottomSlot = slot.CFrame.Position.Y - slot.Size.Y / 2
		expect(math.abs(mesh.CFrame.Position.Y - mesh.Size.Y / 2 - bottomSlot) < 1e-6).toBe(true)
		local n = 0
		for _, c in slot:GetChildren() do
			if c.Name == PlotDecor.SKIN_DECOR_NAME then
				n += 1
			end
		end
		expect(n).toBe(1)
		PlotDecor.applySkin(p1, "classic", slot, templates)
	end)
	it("a missing template keeps the slot as built (no decor, no hidden mailbox)", function()
		local p1, slot = plots:FindFirstChild("Plot_1"), decor:FindFirstChild("Mailbox_1")
		local before = slot.Transparency
		PlotDecor.applySkin(p1, "candy", slot, nil)
		expect(slot:FindFirstChild(PlotDecor.SKIN_DECOR_NAME)).toBeNil()
		expect(slot.Transparency).toBe(before)
		PlotDecor.applySkin(p1, "classic", slot, nil)
	end)
	it("flag off: the server never writes the PlotSkin attribute and the client skips plots without it", function()
		for _, plot in plots:GetChildren() do
			expect(plot:GetAttribute(Constants.PLOT_SKIN_ATTRIBUTE)).toBeNil()
		end
		local view = fs.readFile("src/server/WorldView.luau")
		expect(string.find(view, "if Config.FEATURES.PlotSkins then\n\t\t\t\tsetIfChanged(", 1, true) ~= nil).toBe(true)
		local client = fs.readFile("src/visuals/client/PlotVisuals.luau")
		expect(string.find(client, "if id == nil then\n\t\treturn\n\tend", 1, true) ~= nil).toBe(true)
		local server = fs.readFile("src/server/MeshSwap.luau")
		expect(string.find(server, "if not Config.FEATURES.PlotSkins then\n\t\treturn 0", 1, true) ~= nil).toBe(true)
	end)
end)

describe("plot skins: mesh budget", function()
	it("adds no world mesh slot: the skin decors are not placed, WorldLayout is unchanged by the skins", function()
		local names = {}
		for _, s in Config.PLOT_SKINS do
			if s.decor then
				names[s.decor] = true
			end
		end
		for _, prop in WorldLayout.RANCH_PROPS do
			expect(names[prop.mesh]).toBeNil()
		end
		local function scan(node: any)
			local a = node.attributes or {}
			expect(names[a.MeshAsset]).toBeNil()
			expect(names[a.BorderMesh]).toBeNil()
			for _, c in node.children or {} do
				scan(c)
			end
		end
		for _, root in WorldLayout.build() do
			scan(root)
		end
		for name in names do
			expect(RanchProps.INTENTIONALLY_UNPLACED[name] ~= nil).toBe(true)
		end
	end)
	it("replaces the per-plot mailbox slot: one slot a plot, 8 plots, nothing extra", function()
		local mailboxes = 0
		for _, prop in WorldLayout.RANCH_PROPS do
			if prop.mesh == "ranch_mailbox" then
				mailboxes += 1
			end
		end
		expect(mailboxes).toBe(Config.PLOT_COUNT)
		-- every plot wearing a skin: still one visible mesh in that slot, so the count is the same
		expect(WorldBudget.uploaded.total).toBe(
			WorldBudget.uploaded.fence
				+ WorldBudget.uploaded.posts
				+ WorldBudget.uploaded.decor
				+ WorldBudget.uploaded.border
		)
	end)
	it("keeps the parts under 1400 even with a skin decor part on every plot", function()
		expect(WorldBudget.uploaded.parts + Config.PLOT_COUNT < WorldLayout.PART_BUDGET).toBe(true)
		expect(WorldBudget.current.parts + Config.PLOT_COUNT < WorldLayout.PART_BUDGET).toBe(true)
	end)
end)
