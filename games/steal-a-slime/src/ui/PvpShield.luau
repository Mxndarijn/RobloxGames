--!strict
--[[
	PvpShield (client, FEATURES.PvP, CONTRACT.md §26.7)

	The new-player shield badge everyone sees: a small BillboardGui with the shield icon (ItemIcons "Shield") over the
	head of every player whose replicated `PvpShieldUntil` attribute (Constants.PVP_SHIELD_ATTRIBUTE, server time) is
	still in the future. The badges live in the local PlayerGui (Adornee = the head), so nothing replicates. The
	shielded player's own countdown is the HUD's `Shield` status slot (HudClusters.shield).

	PvpShield.start(opts) -> { tick(now), count(), stop() }: watches every player's attribute and character; `tick`
	(the client's one frame loop) drops badges whose shield ran out, at most once a second.
]]

local Players = game:GetService("Players")

local ItemIconView = require(script.Parent.ItemIconView)

local PvpShield = {}

PvpShield.BADGE = table.freeze({
	name = "PvpShieldBadge",
	icon = "Shield", -- ItemIcons id
	size = 34, -- px
	offsetY = 2.4, -- studs above the head
	maxDistance = 120, -- studs
	tickSeconds = 1,
})

-- Pure: is a shield that ends at `untilTime` (the attribute value) still on at `now`?
function PvpShield.active(untilTime: any, now: number): boolean
	return type(untilTime) == "number" and untilTime == untilTime and untilTime > now
end

export type Options = {
	attribute: string, -- Constants.PVP_SHIELD_ATTRIBUTE
	registry: any, -- ItemIcons registry
	serverNow: () -> number,
	parent: Instance, -- where the badges live (the local PlayerGui)
}

function PvpShield.start(opts: Options)
	local B = PvpShield.BADGE
	local badges: { [Player]: { gui: BillboardGui, icon: any } } = {}
	local conns: { RBXScriptConnection } = {}
	local lastTick = -math.huge

	local function drop(player: Player)
		local badge = badges[player]
		badges[player] = nil
		if badge then
			badge.gui:Destroy()
		end
	end

	local function refresh(player: Player)
		local head = player.Character and player.Character:FindFirstChild("Head")
		if not head or not PvpShield.active(player:GetAttribute(opts.attribute), opts.serverNow()) then
			drop(player)
			return
		end
		local badge = badges[player]
		if badge and badge.gui.Adornee == head and badge.gui.Parent then
			return
		end
		drop(player)
		local gui = Instance.new("BillboardGui")
		gui.Name = B.name
		gui.Size = UDim2.fromOffset(B.size, B.size)
		gui.StudsOffset = Vector3.new(0, B.offsetY, 0)
		gui.MaxDistance = B.maxDistance
		gui.LightInfluence = 0
		gui.ResetOnSpawn = false
		gui.Adornee = head
		local icon = ItemIconView.new({ Name = "Icon", Size = B.size, Id = B.icon }, opts.registry)
		icon.instance.Parent = gui
		icon.setActive(true)
		gui.Parent = opts.parent
		badges[player] = { gui = gui, icon = icon }
	end

	local function watch(player: Player)
		table.insert(
			conns,
			player:GetAttributeChangedSignal(opts.attribute):Connect(function()
				refresh(player)
			end)
		)
		table.insert(
			conns,
			player.CharacterAdded:Connect(function(character: Model)
				character:WaitForChild("Head", 5)
				refresh(player)
			end)
		)
		refresh(player)
	end

	for _, player in Players:GetPlayers() do
		watch(player)
	end
	table.insert(conns, Players.PlayerAdded:Connect(watch))
	table.insert(conns, Players.PlayerRemoving:Connect(drop))

	local self = {}

	-- From the client's frame loop: badges whose shield ran out go (about once a second).
	function self.tick(now: number)
		if now - lastTick < B.tickSeconds then
			return
		end
		lastTick = now
		for _, player in Players:GetPlayers() do
			refresh(player)
		end
	end

	function self.count(): number
		local n = 0
		for _ in badges do
			n += 1
		end
		return n
	end

	function self.stop()
		for _, conn in conns do
			conn:Disconnect()
		end
		for player in badges do
			drop(player)
		end
	end

	return self
end

return PvpShield
