--!strict
-- Slime info card layout (contract/slime-labels.md): one card per tagged slime, rows stacked inside the card,
-- bottom edge above the mesh top, culled by distance, re-rendered only on label attribute changes.
local roblox = require("@lune/roblox") :: any

local Config = require("../../src/shared/Config")
local Constants = require("../../src/shared/Constants")
local SlimeLabel = require("../../src/shared/SlimeLabel")
local TestRunner = require("../TestRunner")
local UiHarness = require("./UiHarness")

local describe, it, expect = TestRunner.describe, TestRunner.it, TestRunner.expect

local SlimeInfoCard = UiHarness.ui("SlimeInfoCard")
local EPS = 1e-6

local function view(overrides: { [string]: any }?): SlimeLabel.View
	local a: { [string]: any } = { name = "Lop", tier = 3, income = 1250 }
	for k, v in overrides or {} do
		a[k] = v
	end
	return assert(SlimeLabel.view(a :: any))
end

local function slimeModel(attrs: { [string]: any }): any
	local model = UiHarness.Instance.new("Model")
	model.Name = "Slime"
	local body = UiHarness.Instance.new("Part")
	body.Name = "Body"
	body.Parent = model
	model.PrimaryPart = body
	for k, v in attrs do
		model:SetAttribute(k, v)
	end
	return model
end

-- A CollectionService stand-in whose added / removed signals the spec fires by hand.
local function fakeCollection(tagged: { any }): any
	local handlers: { [string]: { (any) -> () } } = { added = {}, removed = {} }
	local function sig(kind: string): any
		return {
			Connect = function(_self: any, fn: (any) -> ())
				table.insert(handlers[kind], fn)
				return {
					Disconnect = function()
						local i = table.find(handlers[kind], fn)
						if i then
							table.remove(handlers[kind], i)
						end
					end,
				}
			end,
		}
	end
	return {
		GetInstanceAddedSignal = function()
			return sig("added")
		end,
		GetInstanceRemovedSignal = function()
			return sig("removed")
		end,
		GetTagged = function()
			return tagged
		end,
		fire = function(kind: string, model: any)
			for _, fn in table.clone(handlers[kind]) do
				fn(model)
			end
		end,
		count = function(kind: string): number
			return #handlers[kind]
		end,
	}
end

local function rowsOf(gui: any): { any }
	local card = gui:FindFirstChild("Card")
	local out = {}
	for _, spec in SlimeInfoCard.ROWS do
		local label = card:FindFirstChild(spec.name)
		if label.Visible then
			table.insert(out, label)
		end
	end
	return out
end

describe("SlimeInfoCard rows", function()
	for _, count in { 3, 4 } do
		it(`{count} rows fill the card top to bottom without overlap`, function()
			local rows = SlimeInfoCard.rows(count)
			expect(#rows).toBe(count)
			local y = 0
			for _, r in rows do
				expect(math.abs(r.y - y) < EPS).toBe(true)
				expect(r.h > 0).toBe(true)
				y += r.h
			end
			expect(math.abs(y - 1) < EPS).toBe(true)
			expect(rows[1].name).toBe("Name")
			expect(rows[1].h > rows[2].h).toBe(true) -- the name row is the largest
		end)
	end
	it("the card grows with the extra row and keeps a pixel floor so it stays readable far away", function()
		local three, four = SlimeInfoCard.size(3), SlimeInfoCard.size(4)
		expect(four.Y.Scale > three.Y.Scale).toBe(true)
		expect(four.Y.Offset > three.Y.Offset).toBe(true)
		expect(four.X).toBe(three.X)
		expect(three.X.Scale > 0 and three.X.Offset > 0).toBe(true)
		expect(three.Y.Scale > 0 and three.Y.Offset > 0).toBe(true)
	end)
end)

describe("SlimeInfoCard render", function()
	it("is culled by distance, drawn above its anchor and never cloned", function()
		local gui = SlimeInfoCard.build()
		expect(gui.ClassName).toBe("BillboardGui")
		expect(gui.MaxDistance).toBe(SlimeInfoCard.SIZE.maxDistance)
		expect(gui.MaxDistance > 0 and gui.MaxDistance < math.huge).toBe(true)
		expect(gui.SizeOffset.Y).toBe(0.5) -- bottom edge on the anchor, so the card is all above the mesh top
		expect(gui.Archivable).toBe(false)
		expect(gui.LightInfluence).toBe(0)
	end)
	it("shows name in the rarity colour, rarity, income and no extra row", function()
		local gui = SlimeInfoCard.build()
		local v = view()
		SlimeInfoCard.render(gui, v, 4.5)
		expect(gui.Enabled).toBe(true)
		expect(gui.StudsOffsetWorldSpace.Y).toBe(4.5)
		local rows = rowsOf(gui)
		expect(#rows).toBe(3)
		expect(rows[1].Text).toBe("Lop")
		local c = Config.RARITIES[3].color
		expect(rows[1].TextColor3).toBe(roblox.Color3.fromRGB(c[1], c[2], c[3]))
		expect(string.find(rows[2].Text, Config.RARITIES[3].name, 1, true) ~= nil).toBe(true)
		expect(rows[3].Text).toBe("+$1.25K/s")
		expect(gui.Size).toBe(SlimeInfoCard.size(3))
		expect(gui:FindFirstChild("Card"):FindFirstChild("Stroke").Color).toBe(roblox.Color3.fromRGB(c[1], c[2], c[3]))
	end)
	it("adds the mutation tag and the extra row, inside the card", function()
		local gui = SlimeInfoCard.build()
		SlimeInfoCard.render(gui, view({ mutations = "Glow", growth = 46 }), 3)
		local rows = rowsOf(gui)
		expect(#rows).toBe(4)
		expect(string.find(rows[2].Text, "Glow", 1, true) ~= nil).toBe(true)
		expect(rows[4].Text).toBe("Growth 46%")
		expect(gui.Size).toBe(SlimeInfoCard.size(4))
		for _, label in rows do
			local top, height = label.Position.Y.Scale, label.Size.Y.Scale
			expect(top >= -EPS and top + height <= 1 + EPS).toBe(true)
			expect(label.Size.X.Scale).toBe(1)
			expect(label.TextScaled).toBe(true)
		end
	end)
	it("drops the extra row again and hides without a view", function()
		local gui = SlimeInfoCard.build()
		SlimeInfoCard.render(gui, view({ price = 500 }), 3)
		expect(#rowsOf(gui)).toBe(4)
		SlimeInfoCard.render(gui, view(), 3)
		expect(#rowsOf(gui)).toBe(3)
		SlimeInfoCard.render(gui, nil, 3)
		expect(gui.Enabled).toBe(false)
	end)
end)

describe("SlimeInfoCard.start", function()
	local function attrs(): { [string]: any }
		return {
			[Constants.LABEL_NAME_ATTRIBUTE] = "Lop",
			[Constants.LABEL_TIER_ATTRIBUTE] = 2,
			[Constants.LABEL_INCOME_ATTRIBUTE] = 40,
			[Constants.LABEL_HEIGHT_ATTRIBUTE] = 3.25,
		}
	end
	it("puts one card on each tagged slime's Body, anchored at LabelHeight", function()
		local a, b = slimeModel(attrs()), slimeModel(attrs())
		local collection = fakeCollection({ a })
		local stop = SlimeInfoCard.start({ collection = collection, tag = Constants.SLIME_TAG })
		collection.fire("added", b)
		collection.fire("added", b) -- a second add of the same model makes no second card
		for _, model in { a, b } do
			local body = model:FindFirstChild("Body")
			local cards = 0
			for _, child in body:GetChildren() do
				if child.Name == SlimeInfoCard.NAME then
					cards += 1
					expect(child.Adornee).toBe(body)
					expect(child.StudsOffsetWorldSpace.Y).toBe(3.25)
				end
			end
			expect(cards).toBe(1)
		end
		stop()
		expect(a:FindFirstChild("Body"):FindFirstChild(SlimeInfoCard.NAME)).toBeNil()
		expect(collection.count("added")).toBe(0)
	end)
	it("re-renders on a label attribute change only, and leaves with the tag", function()
		local model = slimeModel(attrs())
		local collection = fakeCollection({})
		local stop = SlimeInfoCard.start({ collection = collection, tag = Constants.SLIME_TAG })
		collection.fire("added", model)
		local gui = model:FindFirstChild("Body"):FindFirstChild(SlimeInfoCard.NAME)
		local income = gui:FindFirstChild("Card"):FindFirstChild("Income")
		expect(income.Text).toBe("+$40/s")
		model:SetAttribute(Constants.LABEL_INCOME_ATTRIBUTE, 2500)
		UiHarness.fire(model, "AttributeChanged", "Riding") -- not a label attribute: untouched
		expect(income.Text).toBe("+$40/s")
		UiHarness.fire(model, "AttributeChanged", Constants.LABEL_INCOME_ATTRIBUTE)
		expect(income.Text).toBe("+$2.5K/s")
		collection.fire("removed", model)
		expect(model:FindFirstChild("Body"):FindFirstChild(SlimeInfoCard.NAME)).toBeNil()
		stop()
	end)
	it("skips models without a Body and hides a card until the server names the slime", function()
		local bare = UiHarness.Instance.new("Model")
		local unnamed = slimeModel({ [Constants.LABEL_INCOME_ATTRIBUTE] = 5 })
		local stop = SlimeInfoCard.start({ collection = fakeCollection({ bare, unnamed }), tag = Constants.SLIME_TAG })
		expect(#bare:GetChildren()).toBe(0)
		expect(unnamed:FindFirstChild("Body"):FindFirstChild(SlimeInfoCard.NAME).Enabled).toBe(false)
		stop()
	end)
end)
