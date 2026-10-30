--!strict
--[[
	BoardFace (Instance builders, no Roblox API at load time)

	The layout shared by the light board faces: the Hall of Fame leaderboards (Props.leaderboardBoard, their rows
	from the server's Props.fillLeaderboard and the client's ui/WorldLeaderboard) and the Upcoming Events board
	(server/EventBoardView). Spacing comes from BoardFace.CHROME, in canvas px.

	  BoardFace.pad(frame, x, y) -> UIPadding     x px left and right, y px top and bottom
	  BoardFace.placeHeader(header)               the title bar at the top of the padded face
	  BoardFace.row(k, count, palette) -> Frame   one of `count` leaderboard row cards "Row_<k>" (Rank, Name, Value)
]]

local BoardFace = {}

-- Spacing on the light board faces (the Hall of Fame boards and the Upcoming Events board), in canvas px: the same
-- numbers as the menu cards (ui/Layout.PANEL_CHROME). The title bar is inset by its outline, so `pad` reaches its
-- visible edge; cards and rows are measured to their frames, and their outlines (2 to 5 px) draw outside that.
-- Heights are fractions of the padded face.
BoardFace.CHROME = table.freeze({
	pad = 20, -- board edge -> title bar, rows and cards
	gutter = 12, -- title bar -> list, and between event cards
	inset = 12, -- a card's or row's edge -> its text, icon or timer (left and right)
	insetY = 8, -- an event card's edge -> its contents (top and bottom)
	pillInset = 10, -- an event card's timer pill -> its text (left and right)
	rowGap = 4, -- between leaderboard rows
	youGap = 6, -- last leaderboard row -> the "You" line
	headerStroke = 4, -- the title bar's ink outline (drawn outside the bar)
	header = 0.14, -- title bar height
	you = 0.085, -- the "You" line's height
	text = 0.86, -- a leaderboard row's text, of the row's height
})

-- Row label columns { x, width } as fractions of the row's padded width.
BoardFace.COLUMNS = table.freeze({
	Rank = table.freeze({ 0, 0.12 }),
	Name = table.freeze({ 0.15, 0.52 }),
	Value = table.freeze({ 0.68, 0.32 }),
})

export type Palette = { RowAlt: { number }, Text: { number }, Value: { number }, Rank: { { number } } }

local function rgb(c: { number }): Color3
	return Color3.fromRGB(c[1], c[2], c[3])
end

function BoardFace.pad(frame: GuiObject, x: number, y: number): UIPadding
	local padding = frame:FindFirstChildOfClass("UIPadding") or Instance.new("UIPadding")
	padding.PaddingLeft, padding.PaddingRight = UDim.new(0, x), UDim.new(0, x)
	padding.PaddingTop, padding.PaddingBottom = UDim.new(0, y), UDim.new(0, y)
	padding.Parent = frame
	return padding
end

-- The title bar at the top of its padded face, inset by its own outline (drawn outside the bar), so the outline
-- lands on the face's padding edge.
function BoardFace.placeHeader(header: GuiObject)
	local chrome = BoardFace.CHROME
	local stroke = chrome.headerStroke
	header.Position = UDim2.fromOffset(stroke, stroke)
	header.Size = UDim2.new(1, -2 * stroke, chrome.header, -stroke)
end

-- One leaderboard row card "Row_<k>", unparented: a rounded card padded `inset` px left and right, with the rank
-- and name left-aligned and the value right-aligned, all at the same text height. The server's rows and the
-- client's both come from here, so every row has the same layout.
function BoardFace.row(k: number, count: number, palette: Palette): Frame
	local chrome = BoardFace.CHROME
	local row = Instance.new("Frame")
	row.Name = `Row_{k}`
	row.LayoutOrder = k
	-- Offsets are whole px: Roblox truncates fractions, so round the gap share up and let the list end short.
	row.Size = UDim2.new(1, 0, 1 / count, -math.ceil(chrome.rowGap * (count - 1) / count))
	row.BackgroundColor3 = rgb(palette.RowAlt) -- one rounded card per row; the client tints the top three
	row.BackgroundTransparency = 0
	row.BorderSizePixel = 0
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0.3, 0)
	corner.Parent = row
	BoardFace.pad(row, chrome.inset, 0)
	local top = (1 - chrome.text) / 2
	local colors = { Rank = palette.Rank[k] or palette.Text, Name = palette.Text, Value = palette.Value }
	for _, name in { "Rank", "Name", "Value" } do
		local col = BoardFace.COLUMNS[name]
		local label = Instance.new("TextLabel")
		label.Name = name
		label.BackgroundTransparency = 1
		label.Font = Enum.Font.FredokaOne
		label.TextScaled = true
		label.TextTruncate = Enum.TextTruncate.AtEnd
		label.TextColor3 = rgb(colors[name])
		label.TextXAlignment = if name == "Value" then Enum.TextXAlignment.Right else Enum.TextXAlignment.Left
		label.Text = ""
		label.Position = UDim2.fromScale(col[1], top)
		label.Size = UDim2.fromScale(col[2], chrome.text)
		label.Parent = row
	end
	return row
end

return table.freeze(BoardFace)
