--!strict
--[[
	SlimeEmotes (contract/slime-life.md): the small emote bubbles over slimes
	(a heart, surprise, a question, a star, a note, dots, Zzz, dizzy stars, anger
	and a sweat drop). Supplementary-plane emoji only: they render everywhere (tests/ui/Glyphs.spec). A fixed pool of at most MAX
	BillboardGuis, made once; each frame the runner hands over what every
	animated slime wants to show, nearest first, and the pool shows the first
	MAX of them. Client-only, nothing replicates.

	  SlimeEmotes.new(parent) -> Pool
	  SlimeEmotes.show(pool, wants, now)   wants: { Want }, nearest first
	  SlimeEmotes.destroy(pool)
]]

local SlimeEmotes = {}

SlimeEmotes.MAX = 6 -- bubbles on screen at once
SlimeEmotes.SIZE = 34 -- px
SlimeEmotes.POP_SECONDS = 0.18
SlimeEmotes.MAX_DISTANCE = 70 -- studs: the bubble hides further away (BillboardGui.MaxDistance)
SlimeEmotes.SIDE = 1.1 -- studs to the right of the slime's top (the info card sits right above it)
-- Emote name (SlimeBeats.Emote) -> what the bubble shows.
SlimeEmotes.GLYPHS = table.freeze({
	love = "💗",
	alert = "😮",
	ask = "🤔",
	star = "🌟",
	note = "🎵",
	dots = "💬",
	sleep = "💤",
	dizzy = "💫",
	angry = "💢",
	sweat = "💦",
} :: { [string]: string })
local STYLE = table.freeze({
	fill = Color3.fromRGB(255, 255, 255),
	stroke = Color3.fromRGB(42, 33, 64),
	strokeThickness = 2,
})

export type Want = { adornee: BasePart, emote: string, height: number, key: any }

type Slot = { gui: BillboardGui, scale: UIScale, label: TextLabel, key: any, emote: string?, shownAt: number }
export type Pool = { slots: { Slot } }

function SlimeEmotes.new(parent: Instance): Pool
	-- Straight into `parent` (PlayerGui): a BillboardGui with ResetOnSpawn off survives a respawn, a Folder may not.
	local slots: { Slot } = {}
	for i = 1, SlimeEmotes.MAX do
		local gui = Instance.new("BillboardGui")
		gui.Name = `SlimeEmote{i}`
		gui.Size = UDim2.fromOffset(SlimeEmotes.SIZE, SlimeEmotes.SIZE)
		gui.LightInfluence = 0
		gui.AlwaysOnTop = false
		gui.MaxDistance = SlimeEmotes.MAX_DISTANCE
		gui.ResetOnSpawn = false
		gui.Enabled = false
		local bubble = Instance.new("Frame")
		bubble.Name = "Bubble"
		bubble.Size = UDim2.fromScale(1, 1)
		bubble.BackgroundColor3 = STYLE.fill
		bubble.Parent = gui
		local corner = Instance.new("UICorner")
		corner.CornerRadius = UDim.new(0.5, 0)
		corner.Parent = bubble
		local stroke = Instance.new("UIStroke")
		stroke.Color = STYLE.stroke
		stroke.Thickness = STYLE.strokeThickness
		stroke.Parent = bubble
		local scale = Instance.new("UIScale")
		scale.Parent = bubble
		local label = Instance.new("TextLabel")
		label.Name = "Glyph"
		label.Size = UDim2.fromScale(0.8, 0.8)
		label.Position = UDim2.fromScale(0.1, 0.1)
		label.BackgroundTransparency = 1
		label.TextScaled = true
		label.Text = ""
		label.Parent = bubble
		gui.Parent = parent
		table.insert(slots, { gui = gui, scale = scale, label = label, key = nil, emote = nil, shownAt = 0 })
	end
	return { slots = slots }
end

-- Pop-in size: overshoots a little, then settles at 1.
local function pop(age: number): number
	local k = math.clamp(age / SlimeEmotes.POP_SECONDS, 0, 1)
	return if k < 1 then 0.6 + 0.55 * math.sin(k * math.pi * 0.75) else 1
end

function SlimeEmotes.show(pool: Pool, wants: { Want }, now: number)
	-- Keep a slot on the slime it already shows (no flicker when the order changes), then fill free ones.
	local taken: { [any]: Slot } = {}
	local keep: { [Slot]: Want } = {}
	local count = math.min(#wants, SlimeEmotes.MAX)
	for i = 1, count do
		local want = wants[i]
		for _, slot in pool.slots do
			if slot.key == want.key and not keep[slot] then
				keep[slot] = want
				taken[want.key] = slot
				break
			end
		end
	end
	for i = 1, count do
		local want = wants[i]
		if not taken[want.key] then
			for _, slot in pool.slots do
				if not keep[slot] then
					keep[slot] = want
					taken[want.key] = slot
					slot.key = want.key
					slot.emote = nil
					break
				end
			end
		end
	end
	for _, slot in pool.slots do
		local want = keep[slot]
		if not want then
			slot.gui.Enabled = false
			(slot.gui :: any).Adornee = nil
			slot.key = nil
			slot.emote = nil
		else
			if slot.emote ~= want.emote then
				slot.emote = want.emote
				slot.shownAt = now
				slot.label.Text = SlimeEmotes.GLYPHS[want.emote] or ""
			end
			slot.gui.Adornee = want.adornee
			slot.gui.StudsOffset = Vector3.new(SlimeEmotes.SIDE, want.height + 0.15 * math.sin(now * 3), 0)
			slot.scale.Scale = pop(now - slot.shownAt)
			slot.gui.Enabled = true
		end
	end
end

function SlimeEmotes.destroy(pool: Pool)
	for _, slot in pool.slots do
		slot.gui:Destroy()
	end
	table.clear(pool.slots)
end

return SlimeEmotes
