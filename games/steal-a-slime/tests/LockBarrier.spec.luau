--!nocheck
-- Bug #8 (gate post squeeze): the front LockBarrier panel used to be a 0.3 sheet at z = -h, pierced by the GatePost
-- (2.5 deep) and the 1.6-thick front fence pieces; a non-owner jumping against the protruding post corner got
-- depenetrated through it (pc-watcher shot 189, gate_post_squeeze). The front panel is now a slab that encloses
-- all of them and ends at the PlotLockGuard limit. Built from WorldLayout.build() like the real world.
local Config = require("../src/shared/Config")
local Constants = require("../src/shared/Constants")
local LayoutMath = require("../src/visuals/shared/LayoutMath")
local PlotDecor = require("../src/visuals/shared/PlotDecor")
local PlotLockGuard = require("../src/server/PlotLockGuard")
local TestRunner = require("./TestRunner")
local WorldLayout = require("../src/visuals/shared/WorldLayout")

local describe, it, expect = TestRunner.describe, TestRunner.it, TestRunner.expect

-- Default Humanoid JumpHeight (JumpPower 50 at gravity 196.2 is 6.4): the highest a character's feet get.
local MAX_JUMP_HEIGHT = 7.2
local JUMP_MARGIN = 2 -- a character's feet at the top of the jump must still be under the panel top by this much
local EPS = 1e-6

local function find(nodes, name)
	for _, node in nodes or {} do
		if node.name == name then
			return node
		end
	end
	return nil
end

local function toLocal(part)
	local centre, yaw = WorldLayout.plotCentre(1)
	local p = LayoutMath.apply(
		LayoutMath.orientation({ 0, -yaw, 0 }),
		{ part.pos[1] - centre[1], part.pos[2] - centre[2], part.pos[3] - centre[3] }
	)
	-- Every part here is yawed with the plot (front pieces by an extra 180), so the local size is the node size.
	return { x = p[1], y = p[2], z = p[3], sx = part.size[1], sy = part.size[2], sz = part.size[3], node = part }
end

-- Plot 1 children of `group` in plot-local coordinates (Base-centred, entrance at -Z), by name.
local function localParts(plotNode, group)
	local out = {}
	for _, part in find(plotNode.children, group).children do
		if part.pos then
			out[part.name] = toLocal(part)
		else
			out[part.name] = { node = part }
		end
	end
	return out
end

describe("LockBarrier front slab (bug #8)", function()
	local s = WorldLayout.PLOT_SIZE
	local h = s / 2
	local plots = find(WorldLayout.build(), Constants.PLOTS_FOLDER)
	local plotNode = plots.children[1]
	local barrier = localParts(plotNode, "LockBarrier")
	local fence = localParts(plotNode, "Fence")
	local front = barrier.Front

	local function zRange(p)
		return p.z - p.sz / 2, p.z + p.sz / 2
	end

	it("covers the full width including the gate opening and the post edges", function()
		expect(front.sx >= s - EPS).toBe(true)
		expect(math.abs(front.x) < EPS).toBe(true)
		local gate = WorldLayout.GATE_SLOT / 2
		expect(front.x - front.sx / 2 <= -gate).toBe(true)
		expect(front.x + front.sx / 2 >= gate).toBe(true)
		local post = fence.GatePost
		expect(front.x + front.sx / 2 >= post.x + post.sx / 2).toBe(true)
		-- reaches the side panels' outer faces
		expect(front.x + front.sx / 2 >= h + WorldLayout.BARRIER_SIDE_THICKNESS / 2 - EPS).toBe(true)
	end)

	it("encloses the GatePost and every front fence piece in depth", function()
		local lo, hi = zRange(front)
		local pieces = { fence.GatePost }
		for _, seg in WorldLayout.fenceSegments() do
			if seg.side == "Front" then
				local piece = fence[seg.name]
				-- a panel whose mesh is not uploaded is a Model of two segment halves
				if piece.node.children then
					for _, half in piece.node.children do
						table.insert(pieces, toLocal(half))
					end
				else
					table.insert(pieces, piece)
				end
			end
		end
		expect(#pieces > 2).toBe(true)
		for _, piece in pieces do
			local plo, phi = zRange(piece)
			expect(lo < plo).toBe(true)
			expect(hi > phi).toBe(true)
		end
		-- the post is the deepest piece: the outer face is beyond it by the pad
		local plo, phi = zRange(fence.GatePost)
		expect(lo <= plo - WorldLayout.BARRIER_FRONT_OUTER_PAD + EPS).toBe(true)
		expect(hi >= phi).toBe(true)
	end)

	it("ends at the PlotLockGuard limit and keeps the barrier a ghost for the owner group", function()
		expect(WorldLayout.BARRIER_FRONT_INNER_INSET).toBe(PlotLockGuard.MARGIN)
		local _, hi = zRange(front)
		expect(math.abs(hi - -(h - PlotLockGuard.MARGIN)) < EPS).toBe(true)
		expect(front.node.transparency).toBe(1)
		expect(front.node.canQuery).toBe(false)
	end)

	it("is tall enough that a jump cannot clear it", function()
		local top = front.y + front.sy / 2
		expect(top >= 1 + MAX_JUMP_HEIGHT + JUMP_MARGIN).toBe(true)
		expect(front.sy).toBe(PlotDecor.BARRIER_HEIGHT)
		expect(front.y - front.sy / 2).toBe(1)
	end)

	it("leaves the side and back panels as they were and meets them at the corners", function()
		for _, name in { "Back", "Left", "Right" } do
			local p = barrier[name]
			local thin = if name == "Back" then p.sz else p.sx
			local long = if name == "Back" then p.sx else p.sz
			expect(math.abs(thin - 0.3) < EPS).toBe(true)
			expect(long).toBe(s)
			expect(p.sy).toBe(PlotDecor.BARRIER_HEIGHT)
		end
		expect(math.abs(barrier.Back.z - h) < EPS).toBe(true)
		expect(math.abs(barrier.Left.x + h) < EPS).toBe(true)
		expect(math.abs(barrier.Right.x - h) < EPS).toBe(true)
		-- the slab spans the side panels' full x extent and overlaps their front ends in z
		for _, name in { "Left", "Right" } do
			local p = barrier[name]
			local lo, hi = zRange(front)
			expect(p.z - p.sz / 2 >= lo).toBe(true)
			expect(p.z - p.sz / 2 <= hi).toBe(true)
			expect(math.abs(front.x + (if name == "Left" then -1 else 1) * front.sx / 2) >= math.abs(p.x) + 0.15 - EPS).toBe(
				true
			)
		end
		expect(Config.PLOT_COUNT > 0).toBe(true)
	end)
end)
