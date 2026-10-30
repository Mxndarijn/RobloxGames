--!strict
-- Spacing on the in-world boards (BoardFace.CHROME, canvas px): the Hall of Fame leaderboards
-- (Props.leaderboardBoard), their rows from the server (Props.fillLeaderboard) and the client (ui/WorldLeaderboard),
-- and the plot sign's text (MascotSign). The Upcoming Events board is checked in a Studio playtest.
local BoardFace = require("../../src/visuals/shared/BoardFace")
local MascotSign = require("../../src/shared/MascotSign")
local StaticWorld = require("../../scripts/StaticWorld")
local TestRunner = require("../TestRunner")
local UiHarness = require("./UiHarness")
local WorldLayout = require("../../src/visuals/shared/WorldLayout")

local describe, it, expect = TestRunner.describe, TestRunner.it, TestRunner.expect

local Props = StaticWorld.visual("Props")
local WorldLeaderboard = UiHarness.ui("WorldLeaderboard")
local chrome = BoardFace.CHROME
local ROWS = Props.LEADERBOARD_ROWS

type Rect = { x: number, y: number, w: number, h: number }

local function udim(u: any, size: number): number
	return u.Scale * size + u.Offset
end

-- Where `gui` lands on its SurfaceGui's canvas: Position, Size, AnchorPoint and the parents' UIPaddings (lists aside).
local function rect(gui: any, canvas: Rect): Rect
	if gui:IsA("SurfaceGui") then
		return canvas
	end
	local p = rect(gui.Parent, canvas)
	local pad = gui.Parent:FindFirstChildOfClass("UIPadding")
	if pad then
		local l, r = udim(pad.PaddingLeft, p.w), udim(pad.PaddingRight, p.w)
		local t, b = udim(pad.PaddingTop, p.h), udim(pad.PaddingBottom, p.h)
		p = { x = p.x + l, y = p.y + t, w = p.w - l - r, h = p.h - t - b }
	end
	local w, h = udim(gui.Size.X, p.w), udim(gui.Size.Y, p.h)
	return {
		x = p.x + udim(gui.Position.X, p.w) - gui.AnchorPoint.X * w,
		y = p.y + udim(gui.Position.Y, p.h) - gui.AnchorPoint.Y * h,
		w = w,
		h = h,
	}
end

local function board(): (any, Rect)
	local model = Props.leaderboardBoard()
	local gui = model.Board.BoardGui
	local size = model.Board.Size
	return gui, { x = 0, y = 0, w = size.X * gui.PixelsPerStud, h = size.Y * gui.PixelsPerStud }
end

local function entries(n: number): { any }
	local out = {}
	for k = 1, n do
		table.insert(out, { rank = k, name = `P{k}`, value = 1000 - k })
	end
	return out
end

describe("Hall of Fame board spacing", function()
	it("puts the title bar's outline 20 px from the top and sides, and the rows 20 px from the sides", function()
		local gui, canvas = board()
		local content = gui.Content
		local s = chrome.headerStroke
		local header = rect(content.Header, canvas)
		expect(header.x - s).toBeCloseTo(chrome.pad, 0.5)
		expect(header.y - s).toBeCloseTo(chrome.pad, 0.5)
		expect(canvas.w - (header.x + header.w + s)).toBeCloseTo(chrome.pad, 0.5)
		local rows = rect(content.Rows, canvas)
		expect(rows.x).toBeCloseTo(chrome.pad, 0.5)
		expect(canvas.w - (rows.x + rows.w)).toBeCloseTo(chrome.pad, 0.5)
		expect(rows.y - (header.y + header.h + s)).toBeCloseTo(chrome.gutter, 0.5)
		local you = rect(content.You, canvas)
		expect(you.y - (rows.y + rows.h)).toBeCloseTo(chrome.youGap, 0.5)
		expect(canvas.h - (you.y + you.h)).toBeCloseTo(chrome.pad, 0.5)
	end)

	it("fits every row and the gaps between them in the list", function()
		local gui, canvas = board()
		Props.fillLeaderboard(gui.Parent.Parent, entries(ROWS))
		local rows = rect(gui.Content.Rows, canvas)
		local rowH = udim(gui.Content.Rows.Row_1.Size.Y, rows.h)
		local used = ROWS * rowH + (ROWS - 1) * chrome.rowGap
		expect(used <= rows.h + 0.5).toBe(true)
		expect(used >= rows.h - 5).toBe(true)
	end)

	it("lays every row out alike: rank and name left, value right, 12 px in, one text height", function()
		local gui = board()
		Props.fillLeaderboard(gui.Parent.Parent, entries(ROWS))
		local function shape(row: any): string
			local pad = row:FindFirstChildOfClass("UIPadding")
			local parts = { tostring(pad.PaddingLeft), tostring(pad.PaddingRight), tostring(row.Size) }
			for _, name in { "Rank", "Name", "Value" } do
				local label = row:FindFirstChild(name)
				table.insert(parts, `{name} {label.Position} {label.Size} {label.TextXAlignment.Name}`)
			end
			return table.concat(parts, " | ")
		end
		local first = gui.Content.Rows.Row_1
		expect(first.UIPadding.PaddingLeft.Offset).toBe(chrome.inset)
		expect(first.UIPadding.PaddingRight.Offset).toBe(chrome.inset)
		expect(first.Rank.TextXAlignment.Name).toBe("Left")
		expect(first.Rank.Position.X.Scale).toBe(0)
		expect(first.Value.TextXAlignment.Name).toBe("Right")
		expect(first.Value.Position.X.Scale + first.Value.Size.X.Scale).toBeCloseTo(1, 1e-6)
		for _, name in { "Name", "Value" } do
			local label = first:FindFirstChild(name)
			expect(label.Size.Y.Scale).toBe(first.Rank.Size.Y.Scale)
			expect(label.Position.Y.Scale).toBe(first.Rank.Position.Y.Scale)
		end
		for k = 2, ROWS do
			expect(shape(gui.Content.Rows[`Row_{k}`])).toBe(shape(first))
		end
	end)
end)

describe("WorldLeaderboard rows", function()
	local function container(): (any, any)
		local gui = UiHarness.Instance.new("SurfaceGui")
		gui.Name = "Leaderboard"
		local rows = UiHarness.Instance.new("Frame")
		rows.Name = "Rows"
		rows.Parent = gui
		return gui, rows
	end
	local function named(rows: any, name: string): { any }
		local out = {}
		for _, child in rows:GetChildren() do
			if child.Name == name then
				table.insert(out, child)
			end
		end
		return out
	end
	local one = { { rank = 1, name = "Ann", value = "$5", isMe = false } }

	it("builds its own rows with the shared row layout", function()
		local gui, rows = container()
		WorldLeaderboard.render(gui, one)
		local row = rows:FindFirstChild("Row_1")
		expect(row:GetAttribute(WorldLeaderboard.OWN_ROW)).toBe(true)
		expect(row:FindFirstChildOfClass("UIPadding").PaddingLeft.Offset).toBe(chrome.inset)
		expect(row:FindFirstChild("Rank").TextXAlignment.Name).toBe("Left")
		expect(row:FindFirstChild("Value").TextXAlignment.Name).toBe("Right")
	end)

	it("drops its own row once the server's row of that rank is there, so no rank shows twice", function()
		local gui, rows = container()
		WorldLeaderboard.render(gui, {}) -- our "No entries yet" line, before the server's rows arrive
		expect(#named(rows, "Row_1")).toBe(1)
		local server = UiHarness.Instance.new("Frame")
		server.Name = "Row_1"
		for _, name in { "Rank", "Name", "Value" } do
			local label = UiHarness.Instance.new("TextLabel")
			label.Name = name
			label.Parent = server
		end
		server.Parent = rows
		expect(#named(rows, "Row_1")).toBe(2)
		WorldLeaderboard.render(gui, one)
		local left = named(rows, "Row_1")
		expect(#left).toBe(1)
		expect(left[1]).toBe(server)
		expect(server:FindFirstChild("Name").Text).toBe("Ann")
	end)

	it("hides a server row that arrives without its labels instead of showing it beside ours", function()
		local gui, rows = container()
		local early = UiHarness.Instance.new("Frame")
		early.Name = "Row_1"
		early.Parent = rows
		WorldLeaderboard.render(gui, one)
		expect(early.Visible).toBe(false)
		local visible = 0
		for _, row in named(rows, "Row_1") do
			if row.Visible then
				visible += 1
			end
		end
		expect(visible).toBe(1)
	end)
end)

describe("Plot sign text", function()
	-- The sign's face in px (WorldLayout.NAME_BOARD at MascotSign.PIXELS_PER_STUD).
	local W = WorldLayout.NAME_BOARD.width * MascotSign.PIXELS_PER_STUD
	local H = WorldLayout.NAME_BOARD.height * MascotSign.PIXELS_PER_STUD
	local B, G = MascotSign.BOX, MascotSign.GOO
	local barY, barH = B.bar[2] * H, B.bar[4] * H

	it("starts the title 6 px or more under the goo strip and keeps the stats 8 px off the bottom", function()
		local gooBottom = (G.strip[2] + G.strip[4]) * H
		expect(barY + B.title[2] * barH - gooBottom >= 6).toBe(true)
		expect(barH - (B.stats[2] + B.stats[4]) * barH >= 8).toBe(true)
		expect(B.title[2] + B.title[4] <= B.stats[2]).toBe(true)
	end)

	it("keeps the title and stats 12 px or more from the nameplate's sides", function()
		for _, box in { B.title, B.stats } do
			expect(box[1] * W >= 12).toBe(true)
			expect((1 - box[1] - box[3]) * W >= 12).toBe(true)
		end
	end)
end)
