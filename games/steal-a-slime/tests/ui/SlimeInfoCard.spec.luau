--!strict
-- Slime labels (contract/slime-labels.md): one floating tag per loose slime (a rarity pill, the outlined name, the
-- income and a Buy chip), bottom edge above the mesh top at the same height for every slime, culled by distance; a
-- goo-dipped sign in front of the pad's cork stand for a pad slime; both re-rendered only on label attribute changes.
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
		it(`{count} rows fill the tag top to bottom without overlap`, function()
			local rows = SlimeInfoCard.rows(count)
			expect(#rows).toBe(count)
			local y = 0
			for _, r in rows do
				expect(math.abs(r.y - y) < EPS).toBe(true)
				expect(r.h > 0).toBe(true)
				y += r.h
			end
			expect(math.abs(y - 1) < EPS).toBe(true)
			expect(rows[1].name).toBe("Rarity") -- the rarity pill on top, the name under it
			expect(rows[2].name).toBe("Title")
			for i, r in rows do
				if i ~= 2 then
					expect(rows[2].h > r.h).toBe(true) -- the name row is the largest
				end
			end
		end)
	end
	it("the tag grows with the price row and keeps a pixel floor so it stays readable far away", function()
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
		expect(gui.SizeOffset.Y).toBe(0.5) -- bottom edge on the anchor, so the tag is all above the mesh top
		expect(gui.Archivable).toBe(false)
		expect(gui.LightInfluence).toBe(0)
	end)
	it("shows the rarity on a pill of its colour, the name outlined in Ink and the income in mint", function()
		local Theme = UiHarness.ui("Widgets").Theme
		local gui = SlimeInfoCard.build()
		local v = view()
		SlimeInfoCard.render(gui, v, 4.5)
		expect(gui.Enabled).toBe(true)
		expect(gui.StudsOffsetWorldSpace.Y).toBe(4.5)
		local rows = rowsOf(gui)
		expect(#rows).toBe(3)
		local c = Config.RARITIES[3].color
		local pill = rows[1]
		expect(pill.Text).toBe(Config.RARITIES[3].name)
		expect(pill.BackgroundTransparency).toBe(0)
		expect(pill.BackgroundColor3).toBe(roblox.Color3.fromRGB(c[1], c[2], c[3]))
		expect(pill:FindFirstChild("Stroke").Color).toBe(Theme.Ink)
		expect(pill:FindFirstChild("Fit").AspectRatio).toBe(SlimeInfoCard.pillAspect(pill.Text))
		expect(rows[2].Text).toBe("Lop")
		expect(rows[2].TextColor3).toBe(roblox.Color3.new(1, 1, 1))
		expect(rows[2]:FindFirstChild("Stroke").Color).toBe(Theme.Ink)
		expect(rows[3].Text).toBe("+$1.25K/s")
		expect(rows[3].TextColor3).toBe(Theme.Good)
		expect(gui.Size).toBe(SlimeInfoCard.size(3))
		expect(gui:FindFirstChild("Card").BackgroundTransparency).toBe(1)
	end)
	it("writes Ink on a bright rarity pill and outlined white on a deep one", function()
		local Theme = UiHarness.ui("Widgets").Theme
		local Widgets = UiHarness.ui("Widgets")
		for tier = 1, Config.MAX_TIER - 1 do
			local fill, _, ink, strokeHidden = SlimeInfoCard.pillLook(view({ tier = tier }))
			if Widgets.isBright(fill) then
				expect(ink).toBe(Theme.Ink)
				expect(strokeHidden).toBe(1)
			else
				expect(ink).toBe(Theme.Text)
				expect(strokeHidden).toBe(0)
			end
		end
	end)
	it("fills Secret's pill with a rainbow instead of one colour", function()
		local gui = SlimeInfoCard.build()
		SlimeInfoCard.render(gui, view({ tier = Config.MAX_TIER }), 3)
		local fill = rowsOf(gui)[1]:FindFirstChild("Fill").Color.Keypoints
		expect(#fill > 3).toBe(true)
		SlimeInfoCard.render(gui, view({ tier = 2 }), 3)
		expect(#rowsOf(gui)[1]:FindFirstChild("Fill").Color.Keypoints).toBe(2) -- plain again: white, no tint
	end)
	it("sizes a pill to its text", function()
		expect(SlimeInfoCard.pillAspect("Legendary") > SlimeInfoCard.pillAspect("Rare")).toBe(true)
		expect(SlimeInfoCard.pillAspect("") >= 1).toBe(true) -- an empty pill is still round
	end)
	it("adds the Buy chip in gold on Ink, inside the tag", function()
		local Theme = UiHarness.ui("Widgets").Theme
		local gui = SlimeInfoCard.build()
		SlimeInfoCard.render(gui, view({ price = 500 }), 3)
		local rows = rowsOf(gui)
		expect(#rows).toBe(4)
		expect(rows[4].Text).toBe("Buy $500")
		expect(rows[4].TextColor3).toBe(Theme.Gold)
		expect(rows[4].BackgroundColor3).toBe(Theme.Ink)
		expect(gui.Size).toBe(SlimeInfoCard.size(4))
		for _, label in rows do
			-- pills hang from their centre (AnchorPoint 0.5), text rows from their top
			local top = label.Position.Y.Scale - label.AnchorPoint.Y * label.Size.Y.Scale
			local height = label.Size.Y.Scale
			expect(top >= -EPS and top + height <= 1 + EPS).toBe(true)
			expect(label.Size.X.Scale).toBe(1)
			expect(label.TextScaled).toBe(true)
		end
	end)
	it("drops the price row again and hides without a view", function()
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
	it("puts one card on each tagged slime's Body, on its TagAnchor, at LabelHeight", function()
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
					-- the TagAnchor on the Body: SlimeLifeRunner moves it after the drawn slime
					local anchor = body:FindFirstChild(Constants.TAG_ANCHOR)
					expect(anchor ~= nil and anchor:IsA("Attachment")).toBe(true)
					expect(child.Adornee).toBe(anchor)
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
	it("waits for a Body that replicates after the tag, and hides a card until the server names the slime", function()
		local late = UiHarness.Instance.new("Model")
		late:SetAttribute(Constants.LABEL_NAME_ATTRIBUTE, "Lop")
		local unnamed = slimeModel({ [Constants.LABEL_INCOME_ATTRIBUTE] = 5 })
		local stop = SlimeInfoCard.start({ collection = fakeCollection({ late, unnamed }), tag = Constants.SLIME_TAG })
		expect(#late:GetChildren()).toBe(0)
		local body = UiHarness.Instance.new("Part")
		body.Name = "Body"
		body.Parent = late
		UiHarness.fire(late, "ChildAdded", body)
		local card = body:FindFirstChild(SlimeInfoCard.NAME)
		expect(card ~= nil).toBe(true)
		expect(unnamed:FindFirstChild("Body"):FindFirstChild(SlimeInfoCard.NAME)).toBeNil() -- no view, no tag built
		stop()
		expect(body:FindFirstChild(SlimeInfoCard.NAME)).toBeNil()
	end)
end)

local SlimePadSign = UiHarness.ui("SlimePadSign")

-- A plot with one pad (PadIndex `index`) and a slime model resting in its Slimes folder.
local function plotWithSlime(index: number, attrs: { [string]: any }): (any, any, any)
	local plot = UiHarness.Instance.new("Model")
	plot.Name = "Plot_1"
	local pad = UiHarness.Instance.new("Part")
	pad.Name = `Pad_{index}`
	pad.Size = roblox.Vector3.new(8, 2.4, 8)
	pad.CFrame = roblox.CFrame.new(10, 2.2, 20)
	pad:SetAttribute(Constants.PAD_INDEX_ATTRIBUTE, index)
	pad.Parent = plot
	local folder = UiHarness.Instance.new("Folder")
	folder.Name = "Slimes"
	folder.Parent = plot
	local model = slimeModel(attrs)
	model.Parent = folder
	return plot, pad, model
end

describe("SlimePadSign", function()
	it(
		"is a sign on a stake in front of the stand that never collides, is never queried and is never cloned",
		function()
			local sign = SlimePadSign.build()
			expect(sign.ClassName).toBe("Part")
			expect(sign.Anchored).toBe(true)
			expect(sign.CanCollide).toBe(false)
			expect(sign.CanQuery).toBe(false)
			expect(sign.CanTouch).toBe(false)
			expect(sign.Archivable).toBe(false)
			expect(sign:FindFirstChild("Face").Face).toBe(roblox.Enum.NormalId.Front)
			local stake = sign:FindFirstChild("Stake")
			expect(stake ~= nil and stake.CanCollide == false and stake.CanQuery == false).toBe(true)
			expect(math.abs(stake.Size.Y - SlimePadSign.SIZE.centreY) < 1e-4).toBe(true) -- floor to the plank's middle
			local _, pad = plotWithSlime(2, {})
			local at = SlimePadSign.cframe(pad)
			local s = SlimePadSign.SIZE
			-- CFrames are float32: compare positions to 1e-4.
			local here = pad.CFrame:PointToObjectSpace(at.Position)
			expect(math.abs(here.Z + s.front + s.thickness / 2) < 1e-4).toBe(true) -- -Z: towards the plot entrance
			expect(math.abs(here.Y - (s.centreY - pad.Size.Y / 2)) < 1e-4).toBe(true)
			expect(math.abs(here.X) < 1e-4).toBe(true)
		end
	)
	it(
		"is a wooden plank with an Ink edge dipped in goo of the rarity colour, with the name, income and a goo tube",
		function()
			local Theme = UiHarness.ui("Widgets").Theme
			local sign = SlimePadSign.build()
			expect(sign.Material).toBe(roblox.Enum.Material.WoodPlanks)
			local v = view({ tier = 3, growth = 46 })
			SlimePadSign.render(sign, v)
			local board = sign:FindFirstChild("Face"):FindFirstChild("Board")
			expect(board.BackgroundTransparency).toBe(1) -- the wood shows through
			expect(board:FindFirstChild("Stroke").Color).toBe(Theme.Ink)
			local band = board:FindFirstChild("Band")
			local c = Config.RARITIES[3].color
			local goo = band:FindFirstChild("Goo").Color.Keypoints
			expect(goo[2].Value).toBe(roblox.Color3.fromRGB(c[1], c[2], c[3]))
			-- the lip and the drips continue the band's bottom colour, so there is no seam
			for i = 1, SlimePadSign.LIP.scallops do
				expect(band:FindFirstChild(`Lip{i}`).BackgroundColor3).toBe(goo[#goo].Value)
			end
			for i, d in SlimePadSign.DRIPS do
				local drip = band:FindFirstChild(`Drip{i}`)
				expect(drip.BackgroundColor3).toBe(goo[#goo].Value)
				-- the drips run down the ends, outside the text
				local l = SlimePadSign.LAYOUT
				expect(d.x < l.inset or d.x > 1 - l.inset).toBe(true)
			end
			expect(band:FindFirstChild("Rarity").Text).toBe(Config.RARITIES[3].name)
			local title = board:FindFirstChild("Title")
			expect(title.Text).toBe("Lop")
			expect(title:FindFirstChild("Stroke").Color).toBe(Theme.Ink)
			expect(board:FindFirstChild("Income").Text).toBe("+$1.25K/s")
			expect(board:FindFirstChild("Income").TextColor3).toBe(Theme.Good)
			expect(board:FindFirstChild("Growth").Text).toBe("46%")
			expect(board:FindFirstChild("Track").BackgroundColor3).toBe(Theme.Ink)
			local fill = board:FindFirstChild("Track"):FindFirstChild("Fill")
			expect(math.abs(fill.Size.X.Scale - 0.46) < EPS).toBe(true)
			expect(fill.Visible).toBe(true)
			SlimePadSign.render(sign, view({ growth = 0 }))
			expect(fill.Visible).toBe(false)
			expect(board:FindFirstChild("Growth").Text).toBe("0%")
		end
	)
	it("runs a rainbow along a Secret's band, its goo sampled where it hangs", function()
		local sign = SlimePadSign.build()
		SlimePadSign.render(sign, view({ tier = Config.MAX_TIER }))
		local band = sign:FindFirstChild("Face"):FindFirstChild("Board"):FindFirstChild("Band")
		expect(band:FindFirstChild("Goo").Rotation).toBe(0)
		local first = band:FindFirstChild("Drip1").BackgroundColor3
		local last = band:FindFirstChild(`Drip{#SlimePadSign.DRIPS}`).BackgroundColor3
		expect(first ~= last).toBe(true)
	end)
	it("writes Ink on bright goo and outlined white on deep goo", function()
		local Widgets = UiHarness.ui("Widgets")
		for tier = 1, Config.MAX_TIER do
			local v = view({ tier = tier })
			local ink, strokeHidden = SlimePadSign.bandInk(v)
			local bright = SlimeLabel.isRainbow(v) or Widgets.isBright(SlimePadSign.rgb(v.rarityColor))
			expect(ink).toBe(if bright then Widgets.Theme.Ink else roblox.Color3.new(1, 1, 1))
			expect(strokeHidden).toBe(if bright then 1 else 0)
		end
	end)
	it("finds the pad by PadIndex, nil without one", function()
		local _, pad, model = plotWithSlime(3, {})
		expect(SlimePadSign.findPad(model, 3)).toBe(pad)
		expect(SlimePadSign.findPad(model, 4)).toBeNil()
		expect(SlimePadSign.findPad(slimeModel({}), 3)).toBeNil()
		local plot = pad.Parent
		model.Parent = plot -- parented to the plot itself, no Slimes folder
		expect(SlimePadSign.findPad(model, 3)).toBe(pad)
	end)
end)

describe("SlimeInfoCard.start on a pad", function()
	local function padAttrs(pad: number?): { [string]: any }
		return {
			[Constants.LABEL_NAME_ATTRIBUTE] = "Lop",
			[Constants.LABEL_TIER_ATTRIBUTE] = 2,
			[Constants.LABEL_INCOME_ATTRIBUTE] = 40,
			[Constants.LABEL_HEIGHT_ATTRIBUTE] = 3.25,
			[Constants.LABEL_PAD_ATTRIBUTE] = pad,
		}
	end
	it("swaps the floating tag for a sign on the pad, and back when the slime leaves it", function()
		local _, pad, model = plotWithSlime(1, padAttrs(1))
		local signs = UiHarness.Instance.new("Folder")
		local stop = SlimeInfoCard.start({
			collection = fakeCollection({ model }),
			tag = Constants.SLIME_TAG,
			signParent = signs,
		})
		expect(model:FindFirstChild("Body"):FindFirstChild(SlimeInfoCard.NAME)).toBeNil() -- a pad slime builds no tag
		local sign = signs:FindFirstChild(SlimePadSign.NAME)
		expect(sign ~= nil).toBe(true)
		expect(sign.CFrame).toBe(SlimePadSign.cframe(pad))
		model:SetAttribute(Constants.LABEL_INCOME_ATTRIBUTE, 2500)
		UiHarness.fire(model, "AttributeChanged", Constants.LABEL_INCOME_ATTRIBUTE)
		expect(signs:FindFirstChild(SlimePadSign.NAME)).toBe(sign) -- same plank, new text
		expect(sign:FindFirstChild("Face"):FindFirstChild("Board"):FindFirstChild("Income").Text).toBe("+$2.5K/s")
		model:SetAttribute(Constants.LABEL_PAD_ATTRIBUTE, nil)
		UiHarness.fire(model, "AttributeChanged", Constants.LABEL_PAD_ATTRIBUTE)
		expect(#signs:GetChildren()).toBe(0)
		expect(model:FindFirstChild("Body"):FindFirstChild(SlimeInfoCard.NAME).Enabled).toBe(true)
		stop()
	end)
	it("finds the pad once the model moves into its plot (AncestryChanged)", function()
		local plot, _, model = plotWithSlime(1, padAttrs(1))
		model.Parent = nil
		local signs = UiHarness.Instance.new("Folder")
		local stop = SlimeInfoCard.start({
			collection = fakeCollection({ model }),
			tag = Constants.SLIME_TAG,
			signParent = signs,
		})
		expect(#signs:GetChildren()).toBe(0)
		model.Parent = plot:FindFirstChild("Slimes")
		UiHarness.fire(model, "AncestryChanged", model, model.Parent)
		expect(#signs:GetChildren()).toBe(1)
		-- the tag built while the pad was still unfindable is kept, hidden
		expect(model:FindFirstChild("Body"):FindFirstChild(SlimeInfoCard.NAME).Enabled).toBe(false)
		stop()
	end)
	it("keeps the tag when the pad part is not there, and removes the sign with the tag", function()
		local _, _, model = plotWithSlime(1, padAttrs(5))
		local signs = UiHarness.Instance.new("Folder")
		local collection = fakeCollection({ model })
		local stop = SlimeInfoCard.start({ collection = collection, tag = Constants.SLIME_TAG, signParent = signs })
		expect(model:FindFirstChild("Body"):FindFirstChild(SlimeInfoCard.NAME).Enabled).toBe(true)
		expect(#signs:GetChildren()).toBe(0)
		model:SetAttribute(Constants.LABEL_PAD_ATTRIBUTE, 1)
		UiHarness.fire(model, "AttributeChanged", Constants.LABEL_PAD_ATTRIBUTE)
		expect(#signs:GetChildren()).toBe(1)
		collection.fire("removed", model)
		expect(#signs:GetChildren()).toBe(0)
		stop()
	end)
	it("builds the tag only when a pad slime is carried, and drops a tagless slime without error", function()
		local _, _, model = plotWithSlime(1, padAttrs(1))
		local signs = UiHarness.Instance.new("Folder")
		local collection = fakeCollection({ model })
		local stop = SlimeInfoCard.start({ collection = collection, tag = Constants.SLIME_TAG, signParent = signs })
		local body = model:FindFirstChild("Body")
		expect(body:FindFirstChild(SlimeInfoCard.NAME)).toBeNil()
		expect(body:FindFirstChild(Constants.TAG_ANCHOR) ~= nil).toBe(true) -- other readers still find the anchor
		model:SetAttribute(Constants.LABEL_PAD_ATTRIBUTE, nil) -- picked up: no longer on a pad
		UiHarness.fire(model, "AttributeChanged", Constants.LABEL_PAD_ATTRIBUTE)
		local tag = body:FindFirstChild(SlimeInfoCard.NAME)
		expect(tag ~= nil and tag.Enabled).toBe(true)
		expect(tag.Adornee).toBe(body:FindFirstChild(Constants.TAG_ANCHOR))
		model:SetAttribute(Constants.LABEL_PAD_ATTRIBUTE, 1) -- placed back: hidden, not rebuilt
		UiHarness.fire(model, "AttributeChanged", Constants.LABEL_PAD_ATTRIBUTE)
		expect(body:FindFirstChild(SlimeInfoCard.NAME)).toBe(tag)
		expect(tag.Enabled).toBe(false)
		local _, _, other = plotWithSlime(2, padAttrs(2))
		collection.fire("added", other)
		collection.fire("removed", other) -- never had a tag
		expect(#signs:GetChildren()).toBe(1)
		stop()
	end)
end)
