--!strict
--[[
	LeaderboardView (Roblox adapter)

	The player list `leaderstats` (Leaderboard.STATS) and the global boards (Leaderboards.BOARDS): `refresh` reads
	the top Config.LEADERBOARD_SIZE of each board's OrderedDataStore (in memory mode: this server's players), fills
	that board's world prop, sends it to every client on the Leaderboard remote and dresses the podium from the
	podium board (Top Earners). A player who joins later gets the latest boards right away. Ranking rules live in
	Leaderboard (pure).
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)
local Leaderboard = require(script.Parent.Leaderboard)
local Leaderboards = require(ReplicatedStorage.Shared.Leaderboards)
local NameCache = require(script.Parent.NameCache)
local PodiumAvatars = require(script.Parent.PodiumAvatars)
local PodiumRigs = require(script.Parent.PodiumRigs)
local Types = require(ReplicatedStorage.Shared.Types)
local WeeklyEvents = require(ReplicatedStorage.Shared.WeeklyEvents)
local World = require(script.Parent.World)
local WorldProps = require(script.Parent.WorldProps)

export type LeaderboardView = {
	world: World.World,
	boardStore: ((name: string) -> OrderedDataStore?)?, -- nil in memory mode
	remote: RemoteEvent,
	latest: { [string]: Types.Leaderboard }, -- by stat
	names: { [number]: string },
	podiums: PodiumAvatars.Podiums,
}

local LeaderboardView = {}

function LeaderboardView.new(
	world: World.World,
	boardStore: ((name: string) -> OrderedDataStore?)?,
	remote: RemoteEvent
): LeaderboardView
	for _, def in Leaderboards.BOARDS do
		pcall(WorldProps.fillBoard, { stat = def.stat, entries = {} }) -- "No entries yet" until the first refresh
	end
	return {
		world = world,
		boardStore = boardStore,
		remote = remote,
		latest = {},
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
	return NameCache.resolve(view.names, userId, function(id: number): string
		return Players:GetNameFromUserIdAsync(id)
	end)
end

-- One board's page: the top of its store, or this server's players in memory mode. nil when the read failed.
local function readPage(view: LeaderboardView, def: Leaderboards.Board, week: number): { any }?
	local open = view.boardStore
	if not open then
		return Leaderboard.pageFromSessions(view.world.sessions :: any, def.stat, week)
	end
	local store = open(Leaderboards.storeName(def, week))
	if not store then
		return nil
	end
	local ok, page = pcall(function()
		return store:GetSortedAsync(false, Config.LEADERBOARD_SIZE):GetCurrentPage()
	end)
	return if ok and type(page) == "table" then page else nil
end

-- Fetches every board and pushes each to everyone (yields on the OrderedDataStores).
function LeaderboardView.refresh(view: LeaderboardView)
	local week = WeeklyEvents.weekIndex(os.time())
	for _, def in Leaderboards.BOARDS do
		local page = readPage(view, def, week)
		if page then
			local board = Leaderboard.fromPage(page, function(userId: number): string
				return nameOf(view, userId)
			end, def.stat)
			view.latest[def.stat] = board
			-- Fill the world board first so clients re-render (own-row highlight) after it replicates.
			local filled, err = pcall(WorldProps.fillBoard :: any, board)
			if not filled then
				warn(`[Server] {def.stat} board fill failed: {err}`)
			end
			view.remote:FireAllClients(board)
			if def.podium then
				view.podiums:request(board)
			end
		end
	end
end

-- A newcomer gets the latest boards without waiting for the next refresh.
function LeaderboardView.sendLatest(view: LeaderboardView, player: Player)
	for _, def in Leaderboards.BOARDS do
		local board = view.latest[def.stat]
		if board then
			view.remote:FireClient(player, board)
		end
	end
end

return LeaderboardView
