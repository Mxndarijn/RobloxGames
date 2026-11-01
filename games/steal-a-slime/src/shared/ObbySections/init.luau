--!strict
--[[
	ObbySections (pure, contract/obby-sections.md §1, §2)

	The registry of obby section ideas: one module per idea in this folder (ObbySections/<Id>.luau, built with Kit).
	`ALL` lists the ideas in idea-number order (ObbyCourse.pick walks this order, so it must be stable); `byId[id]`
	finds one. IDS is every idea on the ideas page; a module that is not written yet is skipped, so ideas can land one
	by one without touching this file.
]]

local Kit = if script then require(script.Kit) else require("@self/Kit")

-- Every idea id in idea-number order (the PascalCase of its name on the ideas page).
local IDS = {
	"CrusherAlley", -- 1
	"MeltingFloor", -- 2
	"GooRides", -- 3
	"BounceChain", -- 4
	"Updraft", -- 5
	"IceSlide", -- 6
	"Climb", -- 8
	"MerryGoRound", -- 9
	"GlowMemory", -- 10
	"TwoRoads", -- 11
	"RisingGoo", -- 12
	"RollingBlobs", -- 14
	"VineSwing", -- 15
	"SpeedStrip", -- 16
	"LightsOut", -- 17
	"BeatPads", -- 18
	"KeyRun", -- 20
	"GeyserField", -- 21
	"StickyWalls", -- 22
	"ArrowMaze", -- 23
	"CollapsingBridge", -- 24
	"SlidingMaze", -- 25
	"AimTheCannon", -- 26
	"MoonJump", -- 28
	"ClueDoors", -- 29
}

-- The idea module `id`, or nil when it isn't written yet. A module that exists but fails to load still errors.
local function load(id: string): Kit.Idea?
	if script then
		local child = script:FindFirstChild(id)
		return if child then (require :: any)(child) else nil
	end
	local ok, result = pcall(require :: any, `@self/{id}`)
	if ok then
		return result
	elseif string.find(tostring(result), "could not resolve", 1, true) then
		return nil
	end
	error(result, 0)
end

local ALL: { Kit.Idea } = {}
local byId: { [string]: Kit.Idea } = {}
for _, id in IDS do
	local idea = load(id)
	if idea then
		assert(idea.id == id, `obby idea module {id} has id {idea.id}`)
		assert(#idea.variants > 0 or idea.generator ~= nil, `obby idea {id} has no variants`)
		table.insert(ALL, idea)
		byId[id] = idea
	end
end
table.sort(ALL, function(a, b)
	return a.idea < b.idea
end)

local ObbySections = {}

ObbySections.IDS = table.freeze(IDS)
ObbySections.ALL = table.freeze(ALL)
ObbySections.byId = table.freeze(byId)
ObbySections.Kit = Kit

-- Display name of idea `id` (the id itself when it is unknown).
function ObbySections.nameOf(id: string): string
	local idea = byId[id]
	return if idea then idea.name else id
end

return table.freeze(ObbySections)
