--!strict
--[[
	ObbyVineSync (VisualsClient module, contract/obby.md §5 "Vine ropes for everyone")

	Every client shows the same vine ropes. A rope nobody holds swings on server time already (ObbyFx). This adds the
	ropes other players hang on:
	  * send: the rope the local player holds (ObbyMoves `held`) goes to the server as Request ObbyVine, only the
	    latest one, paced by ObbyVineSend. The server checks it (on a run, a rope on that course, rate limit) and sets
	    the Player's ObbyVine attribute, which replicates to every client
	  * draw: for every other player with that attribute, the rope (ObbyMoves `rope`) turns to the angle their
	    replicated root hangs at (Vine.angleAt, written as Vine.OTHER_ANGLE / OTHER_FADE for ObbyFx), their arms go
	    up on the knob (ObbyVinePose: joint edits are local, so each client poses the others itself) and a Beam
	    runs from the knob to their hands. A root further than the rope's length plus Vine.HOLD_SLACK from its pivot
	    is not drawn on it. When they let go the rope swings on and fades back to its server-time swing over
	    ObbyMoves.RETURN, as the local player's own does
	Runs only while ObbyLook.isInside (other players are only seen there). Call `tick(dt)` once a frame, after
	ObbyMoves and before ObbyFx.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Visuals = ReplicatedStorage:WaitForChild("Visuals")
local Constants = require(Shared:WaitForChild("Constants"))
local ObbyLook = require(Visuals:WaitForChild("ObbyLook"))
local ObbyMoves = require(script.Parent:WaitForChild("ObbyMoves"))
local ObbyVinePose = require(script.Parent:WaitForChild("ObbyVinePose"))
local ObbyVineSend = require(Visuals:WaitForChild("ObbyVineSend"))
local Remotes = require(Shared:WaitForChild("Remotes"))
local Vine = require(Shared:WaitForChild("ObbySections"):WaitForChild("Vine"))

local ObbyVineSync = {}

export type Controller = { tick: (dt: number) -> (), stop: () -> () }

type Rope = ObbyMoves.Rope

-- Another player hanging on a rope, as this client draws them.
type Holder = {
	id: string,
	rope: Rope?,
	character: Model?,
	arms: ObbyVinePose.Saved,
	beam: Beam?,
	hands: Attachment?,
	th: number,
	w: number,
	at: number, -- os.clock of the grab (the rope eases to them over ObbyMoves.GRAB_EASE)
	seen: boolean, -- drawn on the rope at least once (a let go swings on from there)
}

-- A rope another player let go of, swinging on while it eases back to its server-time swing.
type Return = { knob: BasePart, ropePart: BasePart?, arm: number, th: number, w: number, at: number }

local function show(knob: BasePart, ropePart: BasePart?, th: number?, fade: number?)
	knob:SetAttribute(Vine.OTHER_ANGLE, th)
	knob:SetAttribute(Vine.OTHER_FADE, fade)
	if ropePart then
		ropePart:SetAttribute(Vine.OTHER_ANGLE, th)
		ropePart:SetAttribute(Vine.OTHER_FADE, fade)
	end
end

local function smooth(k: number): number
	local c = math.clamp(k, 0, 1)
	return c * c * (3 - 2 * c)
end

function ObbyVineSync.start(moves: ObbyMoves.Controller): Controller
	local player = Players.LocalPlayer
	local send = ObbyVineSend.new()
	local holders: { [Player]: Holder } = {}
	local returns: { Return } = {}
	local request: RemoteFunction? = nil

	local function fire(id: string)
		task.spawn(function()
			if request == nil then
				request = Remotes.get(Constants.REQUEST) :: RemoteFunction
			end
			pcall(function()
				(request :: RemoteFunction):InvokeServer("ObbyVine", id)
			end)
			ObbyVineSend.done(send)
		end)
	end

	-- Takes the rope, arms and beam off a holder; with `swing`, the rope swings on from where they left it.
	local function release(h: Holder, swing: boolean)
		ObbyVinePose.lower(h.arms)
		if h.beam then
			h.beam:Destroy()
			h.beam = nil
		end
		if h.hands then
			h.hands:Destroy()
			h.hands = nil
		end
		local r = h.rope
		if r and r.item.part.Parent then
			show(r.item.part, r.ropePart, nil, nil)
			if swing and h.seen then
				table.insert(
					returns,
					{ knob = r.item.part, ropePart = r.ropePart, arm = r.arm, th = h.th, w = h.w, at = os.clock() }
				)
			end
		end
		h.rope = nil
		h.seen = false
	end

	local function releaseAll()
		for _, h in holders do
			release(h, false)
		end
		table.clear(holders)
		for _, r in returns do
			if r.knob.Parent then
				show(r.knob, r.ropePart, nil, nil)
			end
		end
		table.clear(returns)
	end

	local function stepReturns(clock: number, dt: number)
		for i = #returns, 1, -1 do
			local r = returns[i]
			local fade = 1 - (clock - r.at) / ObbyMoves.RETURN
			if fade <= 0 or not r.knob.Parent then
				if r.knob.Parent then
					show(r.knob, r.ropePart, nil, nil)
				end
				table.remove(returns, i)
			else
				r.th, r.w = Vine.step(r.arm, r.th, r.w, 0, dt)
				show(r.knob, r.ropePart, r.th, smooth(fade))
			end
		end
	end

	-- One other player on rope `id` this frame.
	local function draw(other: Player, id: string, clock: number, dt: number)
		local h: Holder? = holders[other]
		if h and h.id ~= id then
			release(h, true)
			h = nil
		end
		if not h then
			h = {
				id = id,
				rope = nil,
				character = nil,
				arms = {},
				beam = nil,
				hands = nil,
				th = 0,
				w = 0,
				at = clock,
				seen = false,
			}
			holders[other] = h
		end
		local holder = h :: Holder
		if holder.rope == nil or not holder.rope.item.part.Parent then
			holder.rope = moves.rope(id)
			if holder.rope then
				-- a rope still swinging back from someone's let go is theirs now
				local knob = holder.rope.item.part
				for i = #returns, 1, -1 do
					if returns[i].knob == knob then
						table.remove(returns, i)
					end
				end
			end
		end
		local r = holder.rope
		local character = other.Character
		local root = character and character:FindFirstChild("HumanoidRootPart")
		local th: number? = nil
		if r and root and root:IsA("BasePart") then
			local rel = root.Position - r.pivot
			th = Vine.angleAt(r.arm, rel:Dot(r.dir), rel:Dot(r.up))
		end
		if holder.character ~= character then
			ObbyVinePose.lower(holder.arms)
			holder.character = character
		end
		if r == nil or th == nil or character == nil then
			-- not on the rope where this client sees them (yet): draw nothing of it
			ObbyVinePose.lower(holder.arms)
			if holder.beam then
				holder.beam:Destroy()
				holder.beam = nil
			end
			if holder.hands then
				holder.hands:Destroy()
				holder.hands = nil
			end
			if r and r.item.part.Parent then
				show(r.item.part, r.ropePart, nil, nil)
			end
			holder.seen = false
			return
		end
		local angle = th :: number
		if holder.seen and dt > 1e-4 then
			-- the rope's speed, for the swing on after a let go: smoothed over a few frames
			holder.w += ((angle - holder.th) / dt - holder.w) * math.min(1, dt * 10)
		end
		holder.th = angle
		holder.seen = true
		local knob = r.item.part
		show(knob, r.ropePart, angle, smooth((clock - holder.at) / ObbyMoves.GRAB_EASE))
		if #holder.arms == 0 then
			holder.arms = ObbyVinePose.raise(character :: Model)
		end
		if not holder.beam or not holder.hands then
			holder.beam, holder.hands = ObbyVinePose.rope(knob)
		end
		local hands = holder.hands :: Attachment
		hands.WorldPosition = ObbyVinePose.grip(character :: Model) or knob.Position
	end

	local function tick(dt: number)
		local clock = os.clock()
		local inside = ObbyLook.isInside()
		local want = if inside then moves.held() else ""
		local shown = player:GetAttribute(Constants.OBBY_VINE_ATTRIBUTE)
		local id = ObbyVineSend.next(send, want, if type(shown) == "string" then shown else "", clock)
		if id ~= nil then
			fire(id)
		end
		if not inside then
			if next(holders) ~= nil or #returns > 0 then
				releaseAll()
			end
			return
		end
		stepReturns(clock, dt)
		for _, other in Players:GetPlayers() do
			if other == player then
				continue
			end
			local on = other:GetAttribute(Constants.OBBY_VINE_ATTRIBUTE)
			if type(on) == "string" and on ~= "" then
				draw(other, on, clock, dt)
			elseif holders[other] then
				release(holders[other], true)
				holders[other] = nil
			end
		end
		for other, h in holders do
			if other.Parent == nil then
				release(h, false)
				holders[other] = nil
			end
		end
	end

	return { tick = tick, stop = releaseAll }
end

return ObbyVineSync
