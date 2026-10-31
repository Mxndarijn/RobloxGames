--!strict
--[[
	SlimeGuardView (Roblox adapter, FEATURES.SlimeGuard, CONTRACT.md §41)

	The Roblox side of SlimeGuard, once per view tick per player (ServerLoop): reads the character's root,
	opens the guard's window for respawns, server moves (WorldView.takeServerMove) and PvP / boss launches,
	feeds the position and finds the other player's jar the character is in. It never moves a character.
	Reports become `[SlimeGuard]` log lines; a kick-level report with ENFORCE on kicks the player. No gameplay
	rules here.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local BaseShapes = require(ReplicatedStorage.Visuals.BaseShapes)
local Carry = require(script.Parent.Carry)
local Constants = require(ReplicatedStorage.Shared.Constants)
local JarInside = require(ReplicatedStorage.Shared.JarInside)
local PvpLaunch = require(script.Parent.PvpLaunch)
local PvpService = require(script.Parent.PvpService)
local SlimeGuard = require(script.Parent.SlimeGuard)
local World = require(script.Parent.World)
local WorldView = require(script.Parent.WorldView)

local KICK_MESSAGE = "You were removed from this server. Please rejoin."

-- The walls of plot `plot`'s base (BaseShapes, CONTRACT.md §44): the jar unless the plot says otherwise.
local function guardOf(plot: Instance): JarInside.Jar
	local base = plot:GetAttribute(Constants.PLOT_BASE_ATTRIBUTE)
	return BaseShapes.get(if type(base) == "string" then base else nil).guard
end

local SlimeGuardView = {}

local characters: { [number]: Model } = {}

function SlimeGuardView.forget(userId: number)
	characters[userId] = nil
end

-- Logs a report and kicks on a kick-level report with ENFORCE on.
function SlimeGuardView.handle(world: World.World, player: Player, report: SlimeGuard.Report?, now: number)
	if not report then
		return
	end
	if SlimeGuard.shouldLog(world, player.UserId, now) then
		warn(
			`[SlimeGuard] {player.Name} ({player.UserId}) {report.detail} -> {string.format("%.1f", report.points)} points,`
				.. ` {report.level}{if report.enforced then "" else " (watch mode)"}`
		)
	end
	if report.enforced and report.level == "kick" then
		player:Kick(KICK_MESSAGE)
	end
end

-- The index of another owned player's jar the root is in, or nil.
local function insidePlot(world: World.World, session: World.Session, root: BasePart): number?
	local was = SlimeGuard.currentPlot(world, session.userId)
	for index = 1, world.plotCount do
		local ownerId = world.plots[index]
		local owner = if ownerId and ownerId ~= session.userId then World.session(world, ownerId) else nil
		local plot = if owner then WorldView.plot(index) else nil
		local base = plot and plot:FindFirstChild("Base")
		if owner and base and base:IsA("BasePart") then
			local p = base.CFrame:PointToObjectSpace(root.Position)
			local y = p.Y + base.Size.Y / 2
			if JarInside.inside(p.X, y, p.Z, guardOf(plot :: Instance), SlimeGuard.floorsOf(owner), was == index) then
				return index
			end
		end
	end
	return nil
end

function SlimeGuardView.step(world: World.World, player: Player, session: World.Session, now: number)
	if SlimeGuard.mode(world) == "off" then
		return
	end
	local userId = player.UserId
	local character = player.Character
	local root = WorldView.rootPart(player)
	if not character or not root then
		return
	end
	if characters[userId] ~= character or WorldView.takeServerMove(userId) then
		characters[userId] = character
		SlimeGuard.serverMoved(world, userId, now)
	end
	local state = PvpService.state(session)
	-- An Obby run: trampolines, slime cannons and fans throw the runner up fast (contract/obby.md). The course
	-- hangs in the sky away from every base, and the run has its own section and time checks.
	if PvpLaunch.guardActive(userId, state and state.controlUntil, now) or session.obbyRun then
		SlimeGuard.launchWindow(world, userId, now)
	end

	local p = root.Position
	local report = SlimeGuard.observe(world, session, p.X, p.Y, p.Z, now, Carry.targetWalkSpeed(session, now))
	SlimeGuardView.handle(world, player, report, now)
	if player.Parent == nil then
		return -- kicked
	end

	local intruded = SlimeGuard.trackPlot(world, session, insidePlot(world, session, root), now)
	if intruded then
		local serverPut = SlimeGuard.inWindow(world, userId, now)
		SlimeGuardView.handle(world, player, SlimeGuard.intruded(world, session, intruded, now, serverPut), now)
	end
end

-- Before a HomeZone deposit: false when the stolen slime arrived too fast and (ENFORCE on) went home instead.
function SlimeGuardView.depositAllowed(world: World.World, player: Player, session: World.Session, now: number): boolean
	local root = WorldView.rootPart(player)
	if not root then
		return true
	end
	local ok, report = SlimeGuard.depositCheck(world, session, root.Position.X, root.Position.Z, now)
	SlimeGuardView.handle(world, player, report, now)
	return ok and player.Parent ~= nil
end

return SlimeGuardView
