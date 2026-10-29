--!strict
--[[
	AdminCommands (pure, contract/admin-menu.md §3)

	The one list of admin menu commands: which tab shows each, whether it is a cheat (test save only) or an admin
	tool (any server, admins only), its button label, and how its number argument is bounded. The server runs them
	(server/AdminService); the client draws the rows State.admin sends.
]]

local Config = if script then require(script.Parent.Config) else require("./Config")

export type Level = "cheat" | "admin"
export type Tab = "Me" | "Items" | "Spawn" | "World"
export type Command = {
	id: string,
	tab: Tab,
	level: Level,
	label: string,
	-- The number argument: nil = the command takes none; `default` is used when the request sends none.
	amount: { min: number, max: number, default: number }?,
}

local AdminCommands = {}

AdminCommands.TABS = table.freeze({ "Me", "Items", "Spawn", "World" } :: { Tab })

AdminCommands.MAX_CASH = 1e15
AdminCommands.MAX_SKIP_SECONDS = 86400
AdminCommands.MAX_WAVE = 20

local function cmd(id: string, tab: Tab, level: Level, label: string, amount: { [string]: number }?): Command
	return table.freeze({
		id = id,
		tab = tab,
		level = level,
		label = label,
		amount = if amount then table.freeze(amount) :: any else nil,
	})
end

AdminCommands.LIST = table.freeze({
	cmd("cashAdd", "Me", "cheat", "Add cash", { min = 1, max = AdminCommands.MAX_CASH, default = 1e6 }),
	cmd("cashSet", "Me", "cheat", "Set cash", { min = 0, max = AdminCommands.MAX_CASH, default = 0 }),
	cmd("skipTime", "Me", "cheat", "Skip time", { min = 1, max = AdminCommands.MAX_SKIP_SECONDS, default = 600 }),
	cmd("setRebirths", "Me", "cheat", "Rebirths", { min = 0, max = Config.MAX_REBIRTHS, default = 0 }),
	cmd("setPads", "Me", "cheat", "Unlocked pads", { min = 1, max = Config.PADS_MAX, default = Config.PADS_MAX }),
	cmd("setGrowth", "Me", "cheat", "Pad slime growth", { min = 0, max = 100, default = 100 }),
	cmd("fillDex", "Me", "cheat", "Full SlimeDex"),
	cmd("skipTutorial", "Me", "cheat", "Skip tutorial"),
	cmd("resetSave", "Me", "cheat", "Reset my save"),
	cmd("goHome", "Me", "admin", "Go home"),
	cmd("goHub", "Me", "admin", "Go to the hub"),
	cmd("grantProduct", "Items", "cheat", "Grant"),
	cmd("grantCosmetics", "Items", "cheat", "Every Exclusive cosmetic"),
	cmd("unlockSkins", "Items", "cheat", "Every plot skin"),
	cmd("unlockSeats", "Items", "cheat", "Every free cloud seat"),
	cmd("giveConsumable", "Items", "cheat", "Give", { min = 1, max = Config.CONSUMABLE_HELD_MAX, default = 5 }),
	cmd("spawnSlime", "Spawn", "cheat", "Spawn on a pad", { min = 1, max = Config.MAX_TIER, default = 1 }),
	cmd("hatchEggs", "Spawn", "cheat", "Hatch my eggs now"),
	cmd("spawnWave", "Spawn", "admin", "Spawn wave", { min = 1, max = AdminCommands.MAX_WAVE, default = 8 }),
	cmd("dropEgg", "Spawn", "admin", "Drop a Mystery Egg"),
	cmd("luckEvent", "World", "admin", "Luck event", {
		min = Config.ADMIN_EVENT_MIN_SECONDS / 60,
		max = Config.ADMIN_EVENT_MAX_SECONDS / 60,
		default = Config.ADMIN_EVENT_DEFAULT_SECONDS / 60,
	}),
	cmd("slimeRain", "World", "admin", "Slime rain"),
	cmd("nextWeather", "World", "admin", "Next weather"),
	cmd("startBoss", "World", "admin", "Start the boss"),
} :: { Command })

local byId: { [string]: Command } = {}
for _, command in AdminCommands.LIST do
	byId[command.id] = command
end

function AdminCommands.get(id: any): Command?
	return if type(id) == "string" then byId[id] else nil
end

-- The command's number for `amount` (the default when nil), whole and inside its bounds; nil for a command that
-- takes none.
function AdminCommands.clamp(command: Command, amount: number?): number?
	local bounds = command.amount
	if not bounds then
		return nil
	end
	local value = if type(amount) == "number" and amount == amount then amount else bounds.default
	return math.clamp(math.floor(value), bounds.min, bounds.max)
end

-- Why `command` can't run here, or nil when it can: cheats need a test save.
function AdminCommands.lockedReason(command: Command, cheats: boolean): string?
	if command.level == "cheat" and not cheats then
		return "cheats only work on a test save"
	end
	return nil
end

return AdminCommands
