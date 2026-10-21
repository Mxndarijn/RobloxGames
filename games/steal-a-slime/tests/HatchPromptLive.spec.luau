--!nocheck
-- The owner's HatchPrompt on a Mystery Egg, through the REAL server Script (tools/livetest/Runtime,
-- memory store): on only once the egg is ready, and the client prompt hider never turns it on for a
-- not-ready egg (a stolen egg changes owner while it is still incubating).
local fs = require("@lune/fs")
local process = require("@lune/process")

local Runtime = require("../tools/livetest/Runtime")
local TestRunner = require("./TestRunner")

local describe, it, expect = TestRunner.describe, TestRunner.it, TestRunner.expect

local path = `{process.env.TMPDIR or "/tmp"}/steal-a-slime-hatch-prompt-{os.time()}.rbxlx`
local built = process.exec("rojo", { "build", "-o", path })
assert(built.ok, `rojo build failed: {built.stderr}`)
local rt = Runtime.new(path, {})
fs.removeFile(path)
rt.workspace:SetAttribute("DataStoreMode", "Memory")
local replicated = rt.game:GetService("ReplicatedStorage")
local Constants = rt:require(replicated.Shared.Constants)
local server = rt.game:GetService("ServerScriptService"):FindFirstChild("Server")
server.Source = server.Source .. "\n_G.__hatchPrompt = { world = world }\n"
rt:boot()
rt:advance(1)
rt:addPlayer(3003, "Owner")
rt:addPlayer(3004, "Thief")
rt:advance(2)
-- selene: allow(global_usage)
local world = _G.__hatchPrompt.world
local owner = world.sessions[3003]
local thief = world.sessions[3004]
assert(owner and thief, "players did not load")

local egg = {
	id = "egg1",
	name = "Egg",
	tier = 3,
	color = { 220, 200, 160 },
	size = 1,
	pattern = "Plain",
	eyes = "Round",
	mouth = "Smile",
	pad = 2,
	species = "blorp",
	egg = { kind = "speckled", hatchAt = 1e12 }, -- incubating, far from ready
}
table.insert(owner.data.slimes, egg)
rt:advance(1)

local function hatchPrompt()
	for _, d in rt.workspace:GetDescendants() do
		if
			d.Name == Constants.HATCH_PROMPT_NAME
			and d.Parent
			and d.Parent.Parent
			and d.Parent.Parent.Name == "Slime_egg1"
		then
			return d
		end
	end
	return nil
end
local function read()
	local p = hatchPrompt()
	return if p then { p.Enabled, p:GetAttribute(Constants.PROMPT_OWNER_ATTRIBUTE) or 0 } else nil
end

local incubating = read()
egg.egg.hatchAt = 0 -- its time has come
rt:advance(1)
local ready = read()
-- The thief takes it to their own pad, where it incubates again.
for i, s in owner.data.slimes do
	if s.id == "egg1" then
		table.remove(owner.data.slimes, i)
		break
	end
end
egg.egg.hatchAt = 1e12
egg.pad = 1
table.insert(thief.data.slimes, egg)
rt:advance(1)
local stolen = read()

-- Client side: PromptHide for the thief, run over the same prompt as it changes owner.
local PromptHide = rt:require(rt.game:GetService("StarterPlayer").StarterPlayerScripts.UI.PromptHide)
local hidden = {}
local apply = PromptHide.applier({
	root = rt.workspace,
	localUserId = 3004,
	attribute = Constants.PROMPT_HIDE_ATTRIBUTE,
	ownerAttribute = Constants.PROMPT_OWNER_ATTRIBUTE,
}, hidden)
local p = hatchPrompt()
p:SetAttribute(Constants.PROMPT_OWNER_ATTRIBUTE, 3003) -- what the thief saw on the owner's ready egg
p.Enabled = true
apply(p)
local thiefSawReady = p.Enabled
p.Enabled = false -- the server state after the steal: not ready, no owner tag
p:SetAttribute(Constants.PROMPT_OWNER_ATTRIBUTE, nil)
apply(p)
local thiefSeesStolen = p.Enabled

describe("Mystery Egg HatchPrompt", function()
	it("is off and untagged while the egg incubates", function()
		expect(incubating).toEqual({ false, 0 })
	end)
	it("is on and owner-only once the egg is ready", function()
		expect(ready).toEqual({ true, 3003 })
	end)
	it("goes off and untagged again on the thief's pad while it incubates", function()
		expect(stolen).toEqual({ false, 0 })
	end)
	it("the thief's client never turns Hatch on for the stolen, not-ready egg", function()
		expect(thiefSawReady).toBe(false)
		expect(thiefSeesStolen).toBe(false)
		expect(#rt.errors).toBe(0)
	end)
end)
