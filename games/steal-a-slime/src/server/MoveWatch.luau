--!strict
--[[
	MoveWatch (pure, FEATURES.MoveGuardLog)

	The server's one MoveGuard.Book. Server-initiated moves (teleports, launches, respawns) call `allow` so the
	next sample of that player re-baselines; ServerLoop samples through `book`. With the flag off `allow` records
	nothing. Holds no Instances.
]]

local Shared = if script then (game:GetService("ReplicatedStorage") :: any).Shared else nil
local Config = if Shared then require(Shared.Config) else require("../shared/Config")
local MoveGuard = if Shared then require(Shared.MoveGuard) else require("../shared/MoveGuard")

local MoveWatch = {}

local book = MoveGuard.newBook()

function MoveWatch.book(): MoveGuard.Book
	return book
end

-- A server-initiated move of `userId` happened (or starts): the next sample may jump `seconds` long.
function MoveWatch.allow(userId: number, seconds: number)
	if Config.FEATURES.MoveGuardLog then
		MoveGuard.allowUser(book, userId, seconds)
	end
end

function MoveWatch.forget(userId: number)
	MoveGuard.forget(book, userId)
end

return MoveWatch
