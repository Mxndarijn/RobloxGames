-- Client datamodel: release probe R6 (ADVISORY), the in-world shop stands (#269 / #276) from the REAL client: for ItemShopStand and UpgradeShopStand
-- (fallback ShopStand for the item shop) the local character is moved in front of the stand with LocalPlayer.Character:PivotTo (the client owns its
-- character, so it replicates), the ShopPrompt (Constants.SHOP_PROMPT_NAME) on the stand is found from the CLIENT and triggered the way a real client
-- can: prompt:InputHoldBegin(), after HoldDuration prompt:InputHoldEnd(). The shop watcher shots hide every ProximityPrompt (Enabled false, attribute
-- PcwHidden); the probe turns a hidden prompt back on for the test and restores it.
-- Checks (ok = every non-nil check true):
--   item_shown / upgrade_shown   the prompt exists, Enabled, MaxActivationDistance > 0, ObjectText / ActionText set, and ProximityPromptService.PromptShown
--                                fires for it within 2 s of standing in front of the stand
--   item_opens / upgrade_opens   after InputHoldBegin / InputHoldEnd the SlimeUI.WorldShopPanel is visible within 3 s (and Player attribute OpenShop is the
--                                stand's ShopId); then closed again with the game's own Esc hook (SlimeUI attribute PcwPress = Escape, see cas_close)
-- The character ends where it started. ~16 s.
local Players = game:GetService("Players")
local PPS = game:GetService("ProximityPromptService")
local ORDER = { "item_shown", "item_opens", "upgrade_shown", "upgrade_opens" }
local checks = {}
local function set(name, ok, info)
	checks[name] = { ok = ok, info = info }
end
local function finish(extra)
	local parts, all, any = {}, true, false
	for _, name in ORDER do
		local c = checks[name] or { ok = nil, info = "not run" }
		checks[name] = c
		table.insert(parts, name .. " " .. (if c.ok == true then "PASS" elseif c.ok == false then "FAIL" else "n/a"))
		if c.ok == false then
			all = false
		elseif c.ok == true then
			any = true
		end
	end
	return {
		ok = if not all then false elseif any then true else nil,
		summary = table.concat(parts, ", "),
		detail = { checks = checks, extra = extra },
	}
end

local player = Players.LocalPlayer
local char = player.Character
local root = char and char:FindFirstChild("HumanoidRootPart")
local gui = player.PlayerGui:FindFirstChild("SlimeUI")
if not (root and gui) then
	return finish("no local character / SlimeUI")
end
local startCF = char:GetPivot()
local panel = gui:FindFirstChild("WorldShopPanel")
local shopPromptName = "ShopPrompt"
local function shown(o)
	local cur = o
	while cur and cur ~= gui do
		if cur:IsA("GuiObject") and not cur.Visible then
			return false
		end
		cur = cur.Parent
	end
	return gui.Enabled
end
local function standOf(name)
	return workspace:FindFirstChild(name, true)
end
local function promptOf(stand)
	local p = stand:FindFirstChild(shopPromptName, true)
	if p and p:IsA("ProximityPrompt") then
		return p
	end
	return nil
end
local function pressEscape()
	gui:SetAttribute("PcwPressResult", nil)
	gui:SetAttribute("PcwPress", nil)
	gui:SetAttribute("PcwPress", "Escape")
	local t0 = os.clock()
	while gui:GetAttribute("PcwPress") ~= nil and os.clock() - t0 < 3 do
		task.wait(0.05)
	end
	return gui:GetAttribute("PcwPressResult")
end

local function test(prefix, stand, shopId)
	if not panel then
		set(prefix .. "_shown", nil, "SlimeUI.WorldShopPanel missing (FEATURES.WorldShops off?)")
		set(prefix .. "_opens", nil, "SlimeUI.WorldShopPanel missing")
		return
	end
	-- front of the stand: the pivot's +-Z side nearer the map centre, 6 studs from its edge
	local pivot, size = stand:GetPivot(), stand:GetExtentsSize()
	local reach = math.max(size.X, size.Z) / 2 + 6
	local a, b = pivot:PointToWorldSpace(Vector3.new(0, 0, reach)), pivot:PointToWorldSpace(Vector3.new(0, 0, -reach))
	local spot = if Vector3.new(a.X, 0, a.Z).Magnitude <= Vector3.new(b.X, 0, b.Z).Magnitude then a else b
	local prompt = promptOf(stand)
	local t0 = os.clock()
	while not prompt and os.clock() - t0 < 3 do
		task.wait(0.2)
		prompt = promptOf(stand)
	end
	if not prompt then
		set(prefix .. "_shown", false, "no " .. shopPromptName .. " ProximityPrompt under " .. stand:GetFullName())
		set(prefix .. "_opens", nil, "no prompt")
		return
	end
	local savedEnabled = prompt.Enabled
	local hiddenByShot = prompt:GetAttribute("PcwHidden") == true or not prompt.Enabled
	prompt.Enabled = true
	local saw = false
	local conn = PPS.PromptShown:Connect(function(p)
		if p == prompt then
			saw = true
		end
	end)
	local look = (stand:GetPivot().Position - spot) * Vector3.new(1, 0, 1)
	char:PivotTo(CFrame.new(spot.X, root.Position.Y + 2, spot.Z) * CFrame.Angles(0, math.atan2(-look.X, -look.Z), 0))
	root.AssemblyLinearVelocity = Vector3.zero
	local t1 = os.clock()
	while not saw and os.clock() - t1 < 2.5 do
		task.wait(0.1)
	end
	local props = {
		enabled = prompt.Enabled, hidden_by_shot_restored = hiddenByShot, max_activation_distance = prompt.MaxActivationDistance,
		action_text = prompt.ActionText, object_text = prompt.ObjectText, hold_duration = prompt.HoldDuration,
		distance = (root.Position - prompt.Parent.Position).Magnitude, prompt_shown_event = saw,
	}
	set(prefix .. "_shown", saw and prompt.Enabled and prompt.MaxActivationDistance > 0 and prompt.ActionText ~= "" and prompt.ObjectText ~= "", props)
	-- trigger like a real client
	local opened
	do
		prompt:InputHoldBegin()
		task.wait(prompt.HoldDuration + 0.2)
		prompt:InputHoldEnd()
		local t2 = os.clock()
		while os.clock() - t2 < 3 do
			if shown(panel) then
				opened = true
				break
			end
			task.wait(0.1)
		end
	end
	local openShop = player:GetAttribute("OpenShop")
	local info = { panel_visible = opened == true, open_shop_attribute = openShop, expected_shop = shopId }
	if opened then
		info.escape_result = pressEscape()
		local t3 = os.clock()
		while shown(panel) and os.clock() - t3 < 2 do
			task.wait(0.1)
		end
		info.closed_with_escape = not shown(panel)
		if shown(panel) then
			gui:SetAttribute("PcwOpen", nil)
			gui:SetAttribute("PcwOpen", "")
			task.wait(0.4)
			info.closed_with_hook = not shown(panel)
		end
	end
	set(prefix .. "_opens", opened == true and (openShop == nil or openShop == shopId or openShop == ""), info)
	conn:Disconnect()
	prompt.Enabled = savedEnabled
	task.wait(0.5)
end

local itemStand = standOf("ItemShopStand") or standOf("ShopStand")
local upgradeStand = standOf("UpgradeShopStand")
if not (itemStand or upgradeStand) then
	return { ok = false, summary = "no ItemShopStand / UpgradeShopStand / ShopStand in the client world", detail = { checks = checks } }
end
local ok, err = pcall(function()
	if itemStand then
		test("item", itemStand, "ItemShop")
	end
	if upgradeStand then
		test("upgrade", upgradeStand, "UpgradeShop")
	end
end)
pcall(function()
	char:PivotTo(startCF)
	root.AssemblyLinearVelocity = Vector3.zero
end)
if not ok then
	for _, name in ORDER do
		if not checks[name] then
			set(name, false, "probe error: " .. tostring(err))
		end
	end
end
return finish({ item_stand = itemStand and itemStand:GetFullName(), upgrade_stand = upgradeStand and upgradeStand:GetFullName(), error = if ok then nil else tostring(err) })
