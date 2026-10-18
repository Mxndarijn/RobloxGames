--!strict
--[[
	LeaderboardView (Roblox adapter)

	The player list `leaderstats` (Leaderboard.STATS) and the global board: `refresh` reads the top
	Config.LEADERBOARD_SIZE from the OrderedDataStore (in memory mode: this server's players), fills the
	LeaderboardBoard prop, sends it to every client on the Leaderboard remote and dresses the podiums. A player
	who joins later gets the latest board right away. Ranking rules live in Leaderboard (pure).
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)
local Leaderboard = require(script.Parent.Leaderboard)
local PodiumAvatars = require(script.Parent.PodiumAvatars)
local PodiumRigs = require(script.Parent.PodiumRigs)
local Types = require(ReplicatedStorage.Shared.Types)
local World = require(script.Parent.World)
local WorldProps = require(script.Parent.WorldProps)

export type LeaderboardView = {
	world: World.World,
	orderedStore: OrderedDataStore?,
	remote: RemoteEvent,
	latest: Types.Leaderboard?,
	names: { [number]: string },
	podiums: PodiumAvatars.Podiums,
}

local LeaderboardView = {}

function LeaderboardView.new(world: World.World, orderedStore: OrderedDataStore?, remote: RemoteEvent): LeaderboardView
	pcall(WorldProps.fillBoard, nil) -- "No entries yet" until the first refresh
	return {
		world = world,
		orderedStore = orderedStore,
		remote = remote,
		latest = nil,
		names = {},
		podiums = PodiumAvatars.new(PodiumRigs.adapter()),
	}
end

function LeaderboardView.createStats(player: Player)
	local folder = Instance.new("Folder")
	folder.Name = "leaderstats"
	for _, name in Leaderboard.STATS do
		local stat = Instance.new("IntValue")
		stat.Name = name
		stat.Parent = folder
	end
	folder.Parent = player
end

function LeaderboardView.updateStats(player: Player, session: World.Session)
	local folder = player:FindFirstChild("leaderstats")
	if not folder then
		return
	end
	for name, value in Leaderboard.stats(session.data) do
		local stat = folder:FindFirstChild(name)
		if stat and stat:IsA("IntValue") and stat.Value ~= value then
			stat.Value = value
		end
	end
end

local function nameOf(view: LeaderboardView, userId: number): string
	local player = Players:GetPlayerByUserId(userId)
	if player then
		return player.DisplayName
	end
	if not view.names[userId] then
		local ok, name = pcall(function()
			return Players:GetNameFromUserIdAsync(userId)
		end)
		view.names[userId] = if ok and type(name) == "string" then name else `Player {userId}`
	end
	return view.names[userId]
end

-- Fetches the board and pushes it to everyone (yields on the OrderedDataStore).
function LeaderboardView.refresh(view: LeaderboardView)
	local ok, page
	local store = view.orderedStore
	if store then
		ok, page = pcall(function()
			return store:GetSortedAsync(false, Config.LEADERBOARD_SIZE):GetCurrentPage()
		end)
	else
		ok, page = true, Leaderboard.pageFromSessions(view.world.sessions :: any) -- memory mode: this server only
	end
	if not ok or type(page) ~= "table" then
		return
	end
	local board = Leaderboard.fromPage(page, function(userId: number): string
		return nameOf(view, userId)
	end)
	view.latest = board
	-- Fill the world board first so clients re-render (own-row highlight) after it replicates.
	local filled, err = pcall(WorldProps.fillBoard :: any, board)
	if not filled then
		warn(`[Server] leaderboard board fill failed: {err}`)
	end
	view.remote:FireAllClients(board)
	view.podiums:request(board)
end

-- A newcomer gets the latest board without waiting for the next refresh.
function LeaderboardView.sendLatest(view: LeaderboardView, player: Player)
	if view.latest then
		view.remote:FireClient(player, view.latest)
	end
end

return LeaderboardView
