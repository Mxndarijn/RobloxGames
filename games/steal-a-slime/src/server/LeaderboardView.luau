--!strict
--[[
	LeaderboardView (Roblox adapter)

	The player list `leaderstats` (Leaderboard.STATS) and the global boards (Leaderboards.BOARDS): `refresh` reads
	the top Config.LEADERBOARD_SIZE of each board's OrderedDataStore (in memory mode: this server's players), fills
	that board's world prop, sends it to every client on the Leaderboard remote and dresses the podium from the
	podium board (Top Earners). A player who joins later gets the latest boards right away. Ranking rules live in
	Leaderboard (pure).
]]

local DataStoreService = game:GetService("DataStoreService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)
local Leaderboard = require(script.Parent.Leaderboard)
local Leaderboards = require(ReplicatedStorage.Shared.Leaderboards)
local NameCache = require(script.Parent.NameCache)
local OrderedBoard = require(ReplicatedStorage.Lib.ranking.OrderedBoard)
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

-- True while a deeper GetSortedAsync page leaves enough budget for the next refreshes.
local function budgetLeft(): boolean
	local ok, budget = pcall(function()
		return DataStoreService:GetRequestBudgetForRequestType(Enum.DataStoreRequestType.GetSortedAsync)
	end)
	return ok and budget > Config.LEADERBOARD_RANK_RESERVE
end

--[[
	One board's pages, best first, joined: the top LEADERBOARD_PAGE of its store, then (within the request budget)
	more pages until every player in this server has a rank or LEADERBOARD_RANK_DEPTH entries are read. In memory
	mode: this server's players, the whole board. Returns the items and whether the whole board was read; nil when
	the first read failed.
]]
local function readPages(view: LeaderboardView, def: Leaderboards.Board, week: number): ({ any }?, boolean)
	local open = view.boardStore
	if not open then
		return Leaderboard.pageFromSessions(view.world.sessions :: any, def.stat, week), true
	end
	local store = open(Leaderboards.storeName(def, week))
	if not store then
		return nil, false
	end
	local ok, pages = pcall(function()
		return store:GetSortedAsync(false, Config.LEADERBOARD_PAGE)
	end)
	if not ok then
		return nil, false
	end
	local items: { any } = {}
	local function take(): boolean
		local got, page = pcall(function()
			return pages:GetCurrentPage()
		end)
		if not got or type(page) ~= "table" then
			return false
		end
		for _, item in page do
			table.insert(items, item)
		end
		return true
	end
	if not take() then
		return nil, false
	end
	local wanted: { [number]: boolean } = {}
	for userId in view.world.sessions do
		wanted[userId] = true
	end
	while not pages.IsFinished and #items < Config.LEADERBOARD_RANK_DEPTH do
		if OrderedBoard.allFound(OrderedBoard.ranks(items, wanted), wanted) or not budgetLeft() then
			break
		end
		local advanced = pcall(function()
			pages:AdvanceToNextPageAsync()
		end)
		if not advanced or not take() then
			break
		end
	end
	return items, pages.IsFinished
end

-- Stores each session's rank on `def` (Leaderboard.sessionRanks) and marks the ones that changed for a State push.
local function rankSessions(view: LeaderboardView, def: Leaderboards.Board, items: { any }, finished: boolean)
	local ranks = Leaderboard.sessionRanks(items, view.world.sessions :: any, finished)
	for userId, session in view.world.sessions do
		local mine = session.boardRanks or {}
		session.boardRanks = mine
		if mine[def.stat] ~= ranks[userId] then
			mine[def.stat] = ranks[userId]
			World.markDirty(session)
		end
	end
end

-- Fetches every board and pushes each to everyone (yields on the OrderedDataStores).
function LeaderboardView.refresh(view: LeaderboardView)
	local week = WeeklyEvents.weekIndex(os.time())
	for _, def in Leaderboards.BOARDS do
		local page, finished = readPages(view, def, week)
		if page then
			rankSessions(view, def, page, finished)
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
