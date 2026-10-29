--!strict
--[[
	EffectsDimmer

	"Goo effects: Low" for the particles the server makes: the server's Effects.play bursts ("Effect_<kind>"),
	the parade drain splash and shining slimes' sparkles replicate to every client at the server's Rate, so this
	client lowers that Rate on Low (EffectPrefs.dim) and puts it back on Full. Which emitters, and the maths, live in
	Visuals.EffectPrefs. Only touches Rate (locally) and the FullRate attribute on those emitters; never fires remotes.

	EffectsDimmer.start() -> cleanup
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local EffectPrefs = require(ReplicatedStorage:WaitForChild("Visuals"):WaitForChild("EffectPrefs"))
local PlayerSettings = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("PlayerSettings"))

local EffectsDimmer = {}

function EffectsDimmer.start(): () -> ()
	local player = Players.LocalPlayer
	local emitters: { [ParticleEmitter]: true } = setmetatable({}, { __mode = "k" }) :: any
	local low = EffectPrefs.isLow(player)

	local function apply(e: ParticleEmitter)
		local saved = e:GetAttribute(EffectPrefs.FULL_RATE_ATTRIBUTE)
		local rate, keep = EffectPrefs.dim(e.Rate, if type(saved) == "number" then saved else nil, low)
		e.Rate = rate
		e:SetAttribute(EffectPrefs.FULL_RATE_ATTRIBUTE, keep)
	end

	local function consider(d: Instance)
		if not d:IsA("ParticleEmitter") then
			return
		end
		local parent = d.Parent
		if not EffectPrefs.dimmable(d.Name, if parent then parent.Name else nil) then
			return
		end
		emitters[d] = true
		if low then
			apply(d)
		end
	end

	local conns: { RBXScriptConnection } = {}
	table.insert(conns, workspace.DescendantAdded:Connect(consider))
	for _, d in workspace:GetDescendants() do
		consider(d)
	end

	local entry = PlayerSettings.entry("effects")
	if entry and player then
		table.insert(
			conns,
			player:GetAttributeChangedSignal(entry.attribute):Connect(function()
				local now = EffectPrefs.isLow(player)
				if now == low then
					return
				end
				low = now
				for e in emitters do
					if e.Parent then
						apply(e)
					else
						emitters[e] = nil
					end
				end
			end)
		)
	end

	return function()
		for _, c in conns do
			c:Disconnect()
		end
		table.clear(conns)
		low = false
		for e in emitters do
			if e.Parent then
				apply(e)
			end
		end
		table.clear(emitters)
	end
end

return EffectsDimmer
