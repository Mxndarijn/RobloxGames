--!nocheck
--[[
	livetest Checks: assertions over a booted Runtime's DataModel. Each check
	returns { name, ok, detail }. Used by tools/livetest/run.luau and by
	tests/LiveBoot.spec.luau.
]]

local roblox = require("@lune/roblox")
local Enum, Vector3 = roblox.Enum, roblox.Vector3

local Checks = {}

Checks.WILD_FOLDER = "WildSlimes" -- Constants.WILD_FOLDER

local function count(folder, class)
	if not folder then
		return 0
	end
	local n = 0
	for _, child in folder:GetChildren() do
		if not class or child:IsA(class) then
			n += 1
		end
	end
	return n
end

local function warningsMatching(rt, pattern)
	local out = {}
	for _, w in rt.warnings do
		if string.find(w.text, pattern) then
			table.insert(out, w.text)
		end
	end
	return out
end

-- Wild slimes under workspace.Wild (the models clients actually see).
function Checks.wildSlimes(rt, minimum)
	local wild = rt.workspace:FindFirstChild(Checks.WILD_FOLDER)
	local n = count(wild, "Model")
	local failures = warningsMatching(rt, "ModelFactory.build failed")
	local detail = `{n} slime model(s) in workspace.{Checks.WILD_FOLDER} after {string.format("%.0f", rt.T)} s`
	if #failures > 0 then
		detail ..= `; {#failures} ModelFactory.build failure(s), first: {failures[1]}`
	end
	return { name = "wild slimes spawned", ok = n >= minimum, detail = detail }
end

-- Every TextLabel / TextButton under workspace with an empty or default
-- ("Label") Text, and every sign-like part with no text on it at all.
function Checks.signText(rt)
	local empty = {}
	local labels = 0
	for _, d in rt.workspace:GetDescendants() do
		if d:IsA("TextLabel") or d:IsA("TextButton") then
			labels += 1
			local text = d.Text
			if text == "" or text == "Label" or text == "Button" then
				table.insert(empty, `{d:GetFullName()} = {string.format("%q", text)}`)
			end
		end
	end
	local blank = {}
	for _, d in rt.workspace:GetDescendants() do
		if d:IsA("BasePart") and string.find(d.Name, "Sign") then
			local hasText = false
			for _, g in d:GetDescendants() do
				if (g:IsA("TextLabel") or g:IsA("TextButton")) and g.Text ~= "" then
					hasText = true
				end
			end
			-- A SurfaceGui elsewhere may target this part through Adornee; good enough for a smoke check.
			if not hasText then
				table.insert(blank, d:GetFullName())
			end
		end
	end
	local detail = `{labels} text label(s) in workspace, {#empty} empty; {#blank} sign part(s) with no text`
	local lines = {}
	for i = 1, math.min(#empty, 5) do
		table.insert(lines, "  empty: " .. empty[i])
	end
	for i = 1, math.min(#blank, 10) do
		table.insert(lines, "  blank sign: " .. blank[i])
	end
	if #blank > 10 then
		table.insert(lines, `  ... and {#blank - 10} more`)
	end
	return {
		name = "signs have text",
		ok = #empty == 0 and #blank == 0,
		detail = detail .. (if #lines > 0 then "\n" .. table.concat(lines, "\n") else ""),
		empty = empty,
		blank = blank,
	}
end

-- Every workspace.Plots.<plot>.Sign carries non-empty text; `owner` (a display
-- name) must appear on at least one of them.
function Checks.plotSigns(rt, owner)
	local plots = rt.workspace:FindFirstChild("Plots")
	local blank, total, owned = {}, 0, false
	for _, plot in (if plots then plots:GetChildren() else {}) do
		local sign = plot:FindFirstChild("Sign")
		if sign then
			total += 1
			local texts = {}
			for _, d in sign:GetDescendants() do
				if (d:IsA("TextLabel") or d:IsA("TextButton")) and d.Text ~= "" then
					table.insert(texts, d.Text)
				end
			end
			if #texts == 0 then
				table.insert(blank, sign:GetFullName())
			end
			if owner and table.find(texts, `{owner}'s plot`) then
				owned = true
			end
		end
	end
	local detail = `{total} plot sign(s), {#blank} blank`
	if owner then
		detail ..= if owned then `; {owner}'s plot shown` else `; no sign shows {owner}'s plot`
	end
	return {
		name = "plot signs have text",
		ok = total > 0 and #blank == 0 and (owner == nil or owned),
		detail = detail,
		blank = blank,
	}
end

function Checks.props(rt)
	local missing = {}
	local names = { "ItemShopStand", "UpgradeShopStand", "LeaderboardBoard", "TutorialNpc" }
	for _, name in names do
		if not rt.workspace:FindFirstChild(name, true) then
			table.insert(missing, name)
		end
	end
	return {
		name = "world props placed",
		ok = #missing == 0,
		detail = if #missing == 0
			then table.concat(names, ", ") .. " present"
			else "missing: " .. table.concat(missing, ", "),
	}
end

-- Slimes that landed below / inside the ground or far from the volcano (visual glitch hints).
function Checks.slimePlacement(rt)
	local wild = rt.workspace:FindFirstChild(Checks.WILD_FOLDER)
	local bad = {}
	local n = 0
	for _, model in (wild and wild:GetChildren() or {}) do
		local body = model:IsA("Model") and (model.PrimaryPart or model:FindFirstChild("Body"))
		if body then
			n += 1
			local p = body.CFrame.Position
			if p.Y < -5 or p.Y > 200 or p.Magnitude ~= p.Magnitude then
				table.insert(bad, `{model.Name} at ({string.format("%.1f, %.1f, %.1f", p.X, p.Y, p.Z)})`)
			end
		end
	end
	return {
		name = "wild slimes on the ground",
		ok = #bad == 0,
		detail = `{n} checked, {#bad} out of range` .. (if #bad > 0 then ": " .. table.concat(bad, "; ") else ""),
	}
end

function Checks.noErrors(rt)
	local interesting = {}
	for _, w in rt.warnings do
		if string.find(w.text, "%[Server%]") or string.find(w.text, "Infinite yield") then
			table.insert(interesting, `t={string.format("%.1f", w.t)} {w.text}`)
		end
	end
	for _, e in rt.errors do
		table.insert(interesting, `t={string.format("%.1f", e.t)} ERROR {string.split(e.text, "\n")[1]}`)
	end
	local seen, lines = {}, {}
	for _, line in interesting do
		local key = string.gsub(line, "^t=[%d%.]+ ", "")
		if not seen[key] then
			seen[key] = true
			table.insert(lines, "  " .. line)
		end
	end
	return {
		name = "no server warnings / script errors",
		ok = #rt.errors == 0 and #interesting == 0,
		detail = `{#rt.errors} script error(s), {#interesting} warning(s)`
			.. (if #lines > 0 then "\n" .. table.concat(lines, "\n", 1, math.min(#lines, 12)) else ""),
	}
end

-- Z-fighting hint (static geometry, no renderer): pairs of opaque parts under
-- `root` with the same rotation whose faces lie in the same plane and overlap.
-- That is what flickers in-game. Rotated parts are compared in the first part's
-- space, so tilted rocks are covered too. Informational: returns pairs, never fails.
function Checks.zFighting(rt, root, limit, eps)
	local parts = {}
	for _, d in root:GetDescendants() do
		if d:IsA("BasePart") and d.Transparency < 0.95 then
			table.insert(parts, d)
		end
	end
	local pairsFound = {}
	local EPS = eps or 0.02
	for a = 1, #parts do
		local pa = parts[a]
		local ra = pa.CFrame.Rotation
		local ha = pa.Size / 2
		for b = a + 1, #parts do
			local pb = parts[b]
			local rel = pa.CFrame:ToObjectSpace(pb.CFrame)
			-- same orientation (axis-aligned relative rotation, any 90-degree turn is fine for boxes)
			local rx, ry, rz = rel.RightVector, rel.UpVector, rel.LookVector
			local aligned = true
			for _, v in { rx, ry, rz } do
				local m = math.max(math.abs(v.X), math.abs(v.Y), math.abs(v.Z))
				if m < 0.999 then
					aligned = false
				end
			end
			if
				aligned
				and pa.Shape == pb.Shape
				and pa:IsA("Part")
				and pb:IsA("Part")
				and pa.Shape == Enum.PartType.Block
			then
				local hb = (rel.Rotation * pb.Size)
				hb = Vector3.new(math.abs(hb.X), math.abs(hb.Y), math.abs(hb.Z)) / 2
				local c = rel.Position
				local overlap = {}
				for _, axis in { "X", "Y", "Z" } do
					overlap[axis] = math.min(ha[axis], c[axis] + hb[axis]) - math.max(-ha[axis], c[axis] - hb[axis])
				end
				for _, axis in { "X", "Y", "Z" } do
					local others = {}
					for _, o in { "X", "Y", "Z" } do
						if o ~= axis then
							table.insert(others, overlap[o])
						end
					end
					if others[1] > 0.05 and others[2] > 0.05 then
						for _, fa in { -ha[axis], ha[axis] } do
							for _, fb in { c[axis] - hb[axis], c[axis] + hb[axis] } do
								if math.abs(fa - fb) < EPS and (pa.Color ~= pb.Color or pa.Material ~= pb.Material) then
									-- Coplanar faces facing the same way overlap visibly (opposite faces touching is fine).
									local sameSide = (fa > 0) == (fb > c[axis])
									if sameSide then
										table.insert(
											pairsFound,
											`{pa:GetFullName()} / {pb:GetFullName()} ({axis} face)`
										)
									end
								end
							end
						end
					end
				end
			end
		end
		if limit and #pairsFound >= limit then
			break
		end
	end
	return pairsFound
end

function Checks.all(rt, opts)
	opts = opts or {}
	return {
		Checks.wildSlimes(rt, opts.minSlimes or 1),
		Checks.slimePlacement(rt),
		Checks.props(rt),
		Checks.signText(rt),
		Checks.noErrors(rt),
	}
end

return Checks
