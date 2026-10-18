--!strict
-- Writes the Top Earners board face for rhr (B2): the board model's own SurfaceGui, filled by the same
-- WorldLeaderboard.render the client runs, laid on a cream Frame the size of the skin's face (12.62 x 11.25
-- studs at PixelsPerStud 40), so `rhr ui <outDir>/board.rbxmx` shows what a player reads on the board.
-- rhr draws ScreenGuis, not a SurfaceGui on a part, so the SurfaceGui's Content frame is moved into a
-- ScreenGui. Run from games/steal-a-slime:  lune run ../../tools/pr-gate/rhr_board.luau <outDir>
local fs = require("@lune/fs")
local luau = require("@lune/luau")
local process = require("@lune/process")
local roblox = require("@lune/roblox") :: any

local outDir = process.args[1] or "rhr-out"
fs.writeDir(outDir)

-- A module with Roblox datatypes as globals; its "./X" requires load from the same folder.
local cache: { [string]: any } = {}
local function load(dir: string, name: string): any
	local key = `{dir}/{name}`
	if cache[key] == nil then
		local env: { [string]: any } = { script = nil }
		for k, v in roblox do
			if string.match(k, "^%u") then
				env[k] = v
			end
		end
		env.require = function(path: string): any
			local sibling = string.match(path, "^%./([%w_]+)$")
			if sibling then
				return load(dir, sibling)
			end
			-- Anything else is a pure module (Config, Constants ...): plain require, path made relative to this file.
			local parts = string.split(`{dir}/{path}`, "/")
			local out: { string } = {}
			for _, part in parts do
				if part == ".." then
					table.remove(out)
				elseif part ~= "." then
					table.insert(out, part)
				end
			end
			return (require :: any)(`../../games/steal-a-slime/{table.concat(out, "/")}`)
		end
		cache[key] =
			luau.load(fs.readFile(`{key}.luau`), { debugName = name, environment = env, injectGlobals = true })()
	end
	return cache[key]
end

local Props = load("src/visuals/shared", "Props")
local WorldLeaderboard = load("src/ui", "WorldLeaderboard")

local board = Props.leaderboardBoard()
local surface = board.Board.BoardGui
local content = surface.Content
-- What a player sees: the server's own fill first, then the client's render over it (my row = rank 5).
local entries = {
	{ rank = 1, userId = 1, name = "SlimeKing", value = 1.2e6 },
	{ rank = 2, userId = 2, name = "GooLord", value = 860e3 },
	{ rank = 3, userId = 3, name = "Mxndarijn", value = 512e3 },
	{ rank = 4, userId = 4, name = "Pinky", value = 240e3 },
	{ rank = 5, userId = 5, name = "Me", value = 98e3 },
	{ rank = 6, userId = 6, name = "Blorp", value = 41e3 },
	{ rank = 7, userId = 7, name = "Niels", value = 12.5e3 },
}
WorldLeaderboard.render(surface, WorldLeaderboard.rows({ entries = entries }, 5))

local W, H =
	math.round(board.Board.Size.X * surface.PixelsPerStud), math.round(board.Board.Size.Y * surface.PixelsPerStud)
local gui = roblox.Instance.new("ScreenGui")
gui.Name = "BoardFace"
gui.IgnoreGuiInset = true
local face = roblox.Instance.new("Frame")
face.Name = "Face"
face.Size = roblox.UDim2.fromOffset(W, H)
face.BackgroundColor3 = roblox.Color3.fromRGB(table.unpack(Props.BOARD_PALETTE.Face))
face.BorderSizePixel = 0
face.Parent = gui
content.Parent = face
fs.writeFile(`{outDir}/board.rbxmx`, roblox.serializeModel({ gui }, true))
print(`wrote {outDir}/board.rbxmx ({W}x{H})`)
