--!strict
-- Player-facing English for the menus area (keys start with "menus."). Localize.catalog checks it.
-- Inventory and hotbar, Settings, Leaderboards (panel and world boards), the slime key card, the pad slime
-- keys, the slime tag's Buy chip and move mode.
return {
	-- Inventory (bag panel and hotbar)
	["menus.inventory.title"] = "Inventory",
	["menus.inventory.bag"] = "Bag",
	["menus.inventory.hotbar"] = "Hotbar",
	["menus.inventory.hint"] = "Drag items here",
	["menus.inventory.empty_title"] = "Your bag is empty",
	["menus.inventory.empty_body"] = "Items you buy at the Item shop and rewards from goals show up here.",
	["menus.inventory.order_refused"] = "Couldn't save your hotbar",
	["menus.inventory.order_blanked"] = "That item can't go on the hotbar",
	["menus.inventory.footer_click"] = "Drag an item onto a hotbar slot to put it there. Drag it off the bar to take it off. Click an item to equip it.",
	["menus.inventory.footer_tap"] = "Drag an item onto a hotbar slot to put it there. Drag it off the bar to take it off. Tap an item to equip it.",
	["menus.inventory.bag_tip_key"] = { source = "Inventory ({key})", example = { key = "`" } },
	["menus.inventory.count.one"] = { source = "{count} item", example = { count = "1" } },
	["menus.inventory.count.other"] = { source = "{count} items", example = { count = "3" } },
	["menus.inventory.not_in_hand"] = "Not in hand",
	["menus.inventory.ready_in"] = { source = "Ready in {seconds}s", example = { seconds = "3" } },
	["menus.inventory.no_one_in_reach"] = "No one in reach",
	["menus.inventory.cant_find_you"] = "Can't find you",
	["menus.inventory.aim_somewhere"] = "Aim somewhere",
	["menus.inventory.aim_ground"] = "Aim at the ground",
	["menus.inventory.cant_use_here"] = "Can't use that here",
	["menus.inventory.tool_bat"] = "Bat",
	["menus.inventory.tool_speed_coil"] = "Speed Coil",

	-- Settings
	["menus.settings.title"] = "Settings",
	["menus.settings.on"] = "On",
	["menus.settings.off"] = "Off",
	["menus.settings.replay"] = "Replay tutorial",
	["menus.settings.replay_hint"] = "Walk through the first steps",
	["menus.settings.replay_button"] = "Replay",
	["menus.settings.replay_running"] = "Running",
	["menus.settings.version"] = "Game version",
	["menus.settings.studio"] = "Studio",
	["menus.settings.player_id"] = { source = "Player ID {id}", example = { id = "42" } },
	["menus.settings.reset"] = "Reset settings",
	["menus.settings.reset_hint"] = "Your slimes and cash stay",
	["menus.settings.reset_button"] = "Hold to reset",

	-- Leaderboards (the panel and the world boards)
	["menus.leaderboard.title"] = "Leaderboards",
	["menus.leaderboard.empty"] = "No entries yet",
	["menus.leaderboard.loading"] = "Loading the board",
	["menus.leaderboard.tab_dex"] = "SlimeDex",
	["menus.leaderboard.tab_weekly"] = "Weekly",
	["menus.leaderboard.tab_earners"] = "Earners",
	["menus.leaderboard.tab_steals"] = "Steals",
	["menus.leaderboard.tab_merges"] = "Merges",
	["menus.leaderboard.you_ranked"] = {
		source = "You: {rank}  {value}",
		example = { rank = "#3", value = "$1.5K" },
	},
	["menus.leaderboard.you_value"] = { source = "You: {value}", example = { value = "$90" } },
	["menus.leaderboard.you_none"] = "You: no score yet",
	["menus.leaderboard.board_you"] = "You",
	["menus.leaderboard.board_you_rank"] = { source = "You {rank}", example = { rank = "#48" } },

	-- Slime key card (pad slimes and the lock button)
	["menus.key_card.lock_timer"] = { source = "LOCKED {time}", example = { time = "1:42" } },
	["menus.key_card.lock_pad_hint"] = "or stand on the green ring",
	["menus.key_card.locked"] = "Locked",
	["menus.key_card.hold"] = "Hold",
	["menus.key_card.pad_up"] = "Up",
	["menus.key_card.pad_down"] = "Dn",
	["menus.key_card.pad_left"] = "Lt",
	["menus.key_card.pad_right"] = "Rt",

	-- Pad slime keys (client prompts)
	["menus.slime_keys.favorite"] = "Favorite",
	["menus.slime_keys.unfavorite"] = "Unfavorite",
	["menus.slime_keys.sell"] = "Sell",
	["menus.slime_keys.sell_price"] = { source = "Sell {price}", example = { price = "$450" } },
	["menus.slime_keys.move"] = "Move",

	-- Slime tag
	["menus.slime_tag.buy"] = { source = "Buy {price}", example = { price = "$1.2K" } },

	-- Move mode
	["menus.move.place"] = "Place",
	["menus.move.cancel"] = "Cancel",
	["menus.move.moving"] = "Moving...",
	["menus.move.moving_name"] = { source = "Moving {name}", example = { name = "Bubbles" } },
	["menus.move.slime"] = "slime",
	["menus.move.point"] = "Point at a pad",
	["menus.move.pad"] = { source = "Pad {pad}", example = { pad = "3" } },
	["menus.move.own_pad"] = { source = "Pad {pad}: its own pad", example = { pad = "1" } },
	["menus.move.pad_locked"] = { source = "Pad {pad} is locked", example = { pad = "7" } },
	["menus.move.swap"] = {
		source = "Pad {pad}: swap with {name}",
		example = { pad = "2", name = "Bubbles" },
	},
	["menus.move.swap_unknown"] = { source = "Pad {pad}: swap with that slime", example = { pad = "2" } },
	["menus.move.vat"] = { source = "Merge vat ({count}/{size})", example = { count = "2", size = "3" } },
	["menus.move.vat_gated"] = {
		source = "Merge vat ({count}/{size}): {reason}",
		example = { count = "1", size = "3", reason = "Epic merges open at Rebirth 2" },
	},
	["menus.move.vat_cant"] = "The vat can't take this slime",
	["menus.move.pick_slime"] = "Pick one of your slimes",
	["menus.move.vat_failed"] = "the vat didn't take it",
	["menus.move.move_failed"] = "the move didn't go through",
	["menus.move.cant_move"] = { source = "Can't move: {reason}", example = { reason = "that pad is locked" } },
}
