--!strict
-- Player-facing English for the world area (keys start with "world."). Localize.catalog checks it.
-- world.reason.*: refusal reasons as the systems write them (server/RequestText matches them); world.prompt.*:
-- ProximityPrompt texts; the rest: signs, boards and tags in the world. world.recipe.<id>: the Dex hint of each
-- merge recipe, from MergeRecipes (the one place its English is written); world.daily_short.<kind>.<id>: the
-- daily streak's tile words, and world.fx.shout.<rarity>: the hatch title per rarity, from Config.
local Shared = if script then (game:GetService("ReplicatedStorage") :: any).Shared else nil
local MergeRecipes = if Shared then require(Shared.MergeRecipes) else require("../MergeRecipes")
local Config = if Shared then require(Shared.Config) else require("../Config")
local DailyRewards = if Shared then require(Shared.DailyRewards) else require("../DailyRewards")

local defs: { [string]: any } = {
	-- Refusal reasons (server/RequestText)
	["world.reason.a_new_course_is_on_its_way"] = "A new course is on its way. Back in a moment!",
	["world.reason.a_slime_the_rebirth_needs_is_brewing"] = "A slime the rebirth needs is brewing in the vat",
	["world.reason.all_pads_unlocked"] = "all pads unlocked",
	["world.reason.already_brewing"] = "already brewing",
	["world.reason.already_carrying_a_slime"] = "already carrying a slime",
	["world.reason.already_claimed"] = "already claimed",
	["world.reason.already_claimed_today"] = "already claimed today",
	["world.reason.already_in_the_vat"] = "Already in the vat",
	["world.reason.already_maxed"] = "already maxed",
	["world.reason.already_owned"] = "already owned",
	["world.reason.bad_aim"] = "bad aim",
	["world.reason.bad_argument"] = "bad argument",
	["world.reason.base_is_locked"] = "base is locked",
	["world.reason.cancel_the_brew_first"] = "Cancel the brew first",
	["world.reason.cannot_merge"] = "cannot merge",
	["world.reason.cant_be_saved"] = "can't be saved",
	["world.reason.cant_find_you"] = "can't find you",
	["world.reason.cant_fire_right_now"] = "can't fire right now",
	["world.reason.cant_push_right_now"] = "can't push right now",
	["world.reason.cant_slap_yourself"] = "can't slap yourself",
	["world.reason.cant_target_yourself"] = "can't target yourself",
	["world.reason.coming_soon"] = "Coming soon",
	["world.reason.egg_is_being_stolen"] = "egg is being stolen",
	["world.reason.egg_is_not_ready"] = "egg is not ready",
	["world.reason.eggs_cant_be_merged"] = "eggs can't be merged",
	["world.reason.eggs_cant_be_sold"] = "eggs can't be sold",
	["world.reason.eggs_cant_go_in_the_vat"] = "Eggs can't go in the vat",
	["world.reason.failed"] = "failed",
	["world.reason.go_inside_their_base_to_steal"] = "Go inside their base to steal",
	["world.reason.its_out_of_reach"] = "it's out of reach",
	["world.reason.its_still_shrinking"] = "it's still shrinking",
	["world.reason.jackpot_slimes_cant_be_merged"] = "jackpot slimes can't be merged",
	["world.reason.max_rebirths_reached"] = "max rebirths reached",
	["world.reason.missing_slime"] = "missing slime",
	["world.reason.moving_slimes_is_off"] = "moving slimes is off",
	["world.reason.need_three_different_slimes"] = "need three different slimes",
	["world.reason.need_three_slimes"] = "need three slimes",
	["world.reason.no_aim"] = "no aim",
	["world.reason.no_bat"] = "no bat",
	["world.reason.no_boss"] = "no boss",
	["world.reason.no_brew_credits"] = "no brew credits",
	["world.reason.no_brew_to_finish"] = "no brew to finish",
	["world.reason.no_credit_of_that"] = "no credit of that",
	["world.reason.no_drop"] = "no drop",
	["world.reason.no_egg_to_hatch"] = "no egg to hatch",
	["world.reason.no_hatch_credits"] = "no hatch credits",
	["world.reason.no_lock_break_credits"] = "no lock break credits",
	["world.reason.no_slime_can_grow_right_now"] = "no slime can grow right now",
	["world.reason.no_snack_credits"] = "no snack credits",
	["world.reason.no_such_player"] = "no such player",
	["world.reason.no_such_quest"] = "no such quest",
	["world.reason.no_such_shop"] = "no such shop",
	["world.reason.no_target"] = "no target",
	["world.reason.no_target_needed"] = "no target needed",
	["world.reason.no_traps_left"] = "no traps left",
	["world.reason.no_weather_here"] = "no weather here",
	["world.reason.nobody_owns_that_base"] = "nobody owns that base",
	["world.reason.not_a_trap"] = "not a trap",
	["world.reason.not_a_vine"] = "not a vine",
	["world.reason.not_available_in_your_region"] = "not available in your region",
	["world.reason.not_available_right_now"] = "not available right now",
	["world.reason.not_brewing"] = "not brewing",
	["world.reason.not_carrying"] = "not carrying",
	["world.reason.not_enough_cash"] = "not enough cash",
	["world.reason.not_equipped"] = "not equipped",
	["world.reason.not_finished_yet"] = "not finished yet",
	["world.reason.not_in_the_obby"] = "not in the obby",
	["world.reason.not_in_the_vat"] = "not in the vat",
	["world.reason.not_loaded"] = "not loaded",
	["world.reason.not_on_a_run"] = "not on a run",
	["world.reason.not_owned"] = "not owned",
	["world.reason.not_ready"] = "not ready",
	["world.reason.not_your_egg"] = "not your egg",
	["world.reason.not_your_slime"] = "not your slime",
	["world.reason.nothing_in_reach"] = "nothing in reach",
	["world.reason.only_a_recipe_merges_these"] = "only a recipe merges these",
	["world.reason.open_the_shop_first"] = "open the shop first",
	["world.reason.pad_is_locked"] = "pad is locked",
	["world.reason.pad_taken"] = "pad taken",
	["world.reason.pet_seat_is_locked"] = "pet seat is locked",
	["world.reason.pick_a_locked_base"] = "pick a locked base",
	["world.reason.plot_base_is_locked"] = "plot base is locked",
	["world.reason.plot_bases_are_off"] = "plot bases are off",
	["world.reason.plot_full"] = "plot full",
	["world.reason.plot_skin_is_locked"] = "plot skin is locked",
	["world.reason.plot_skins_are_off"] = "plot skins are off",
	["world.reason.put_your_slime_down_first"] = "Put your slime down first",
	["world.reason.pvp_is_not_open_yet"] = "PvP is not open yet",
	["world.reason.server_error"] = "server error",
	["world.reason.server_is_full"] = "server is full",
	["world.reason.session_lost"] = "session lost",
	["world.reason.slap_on_cooldown"] = "slap on cooldown",
	["world.reason.slime_is_busy"] = "slime is busy",
	["world.reason.slime_is_gone"] = "slime is gone",
	["world.reason.slime_not_found_yet"] = "slime not found yet",
	["world.reason.slimes_must_be_the_same_rarity"] = "slimes must be the same rarity",
	["world.reason.sold_out_until_the_restock"] = "sold out until the restock",
	["world.reason.someone_is_already_carrying_it"] = "someone is already carrying it",
	["world.reason.stealing_is_paused_for_a_moment"] = "stealing is paused for a moment",
	["world.reason.still_brewing"] = "still brewing",
	["world.reason.still_loading"] = "still loading",
	["world.reason.stunned"] = "stunned",
	["world.reason.target_is_immune"] = "target is immune",
	["world.reason.target_isnt_carrying_a_slime"] = "target isn't carrying a slime",
	["world.reason.target_isnt_carrying_the_boss"] = "target isn't carrying the boss",
	["world.reason.that_base_isnt_locked"] = "that base isn't locked",
	["world.reason.that_base_just_lost_a_slime_its"] = "that base just lost a slime: its short lock can't be opened",
	["world.reason.that_code_doesnt_exist"] = "That code doesn't exist",
	["world.reason.that_code_doesnt_work"] = "That code doesn't work",
	["world.reason.that_code_has_expired"] = "That code has expired",
	["world.reason.that_is_a_vip_perk"] = "that is a VIP perk",
	["world.reason.that_is_not_a_base"] = "that is not a base",
	["world.reason.that_is_not_an_incubating_egg_on"] = "that is not an incubating egg on your pads",
	["world.reason.that_isnt_sold_here"] = "that isn't sold here",
	["world.reason.that_slime_cant_grow_any_more"] = "that slime can't grow any more",
	["world.reason.that_slime_is_brewing_in_the_vat"] = "That slime is brewing in the vat",
	["world.reason.thats_your_own_base"] = "that's your own base",
	["world.reason.thats_your_own_slime"] = "that's your own slime",
	["world.reason.the_boss_isnt_down_yet"] = "the boss isn't down yet",
	["world.reason.the_boss_isnt_fighting"] = "the boss isn't fighting",
	["world.reason.the_egg_smashed"] = "the egg smashed",
	["world.reason.the_gift_couldnt_be_delivered_try_again"] = "the gift couldn't be delivered, try again",
	["world.reason.the_luck_potion_is_already_at_its"] = "the luck potion is already at its longest",
	["world.reason.the_obby_isnt_open_yet"] = "The Obby isn't open yet",
	["world.reason.the_shop_is_closed"] = "the shop is closed",
	["world.reason.the_top_helper_grabs_first"] = "the top helper grabs first",
	["world.reason.the_tutorial_is_already_done"] = "the tutorial is already done",
	["world.reason.the_tutorial_is_already_running"] = "the tutorial is already running",
	["world.reason.the_vat_is_brewing"] = "The vat is brewing",
	["world.reason.the_vat_is_full"] = "The vat is full",
	["world.reason.the_weather_cant_change_that_way_right"] = "the weather can't change that way right now",
	["world.reason.their_slimes_cant_be_saved_on_this"] = "their slimes can't be saved on this server",
	["world.reason.too_far_away"] = "too far away",
	["world.reason.too_far_from_the_shop"] = "too far from the shop",
	["world.reason.too_fast"] = "too fast",
	["world.reason.too_many_lock_break_credits"] = "too many lock break credits",
	["world.reason.too_many_unsent_gifts"] = "too many unsent gifts",
	["world.reason.unknown_credit"] = "unknown credit",
	["world.reason.unknown_item"] = "unknown item",
	["world.reason.unknown_perk"] = "unknown perk",
	["world.reason.unknown_pet_seat"] = "unknown pet seat",
	["world.reason.unknown_plot_base"] = "unknown plot base",
	["world.reason.unknown_plot_skin"] = "unknown plot skin",
	["world.reason.unknown_product"] = "unknown product",
	["world.reason.unknown_slime"] = "unknown slime",
	["world.reason.unknown_style"] = "unknown style",
	["world.reason.unknown_upgrade"] = "unknown upgrade",
	["world.reason.walk_closer_to_your_lock_pad"] = "walk closer to your lock pad",
	["world.reason.you_already_own_the_speed_coil"] = "you already own the Speed Coil",
	["world.reason.you_already_used_that_code"] = "You already used that code",
	["world.reason.you_can_already_walk_in_they_let"] = "you can already walk in: they let their friends in",
	["world.reason.you_cant_do_that_right_now"] = "you can't do that right now",
	["world.reason.you_cant_hold_more_of_these"] = "you can't hold more of these",
	["world.reason.you_cant_shop_right_now"] = "you can't shop right now",
	["world.reason.you_dont_have_any"] = "you don't have any",
	["world.reason.you_dont_own_that"] = "you don't own that",
	["world.reason.you_dont_own_that_bat_skin"] = "you don't own that Bat skin",
	["world.reason.you_dont_own_that_trail"] = "you don't own that trail",
	["world.reason.you_gave_todays_potion_already_back_tomorrow"] = "you gave today's potion already: back tomorrow",
	["world.reason.you_have_no_unsent_gift_of_that"] = "you have no unsent gift of that",
	["world.reason.you_just_dropped_a_slime"] = "you just dropped a slime",
	["world.reason.your_base_is_already_locked"] = "your base is already locked",
	["world.reason.your_lock_break_is_still_running"] = "your lock break is still running",
	["world.reason.your_progress_cant_be_saved_on_this"] = "your progress can't be saved on this server",
	["world.reason.needs_rebirths"] = { source = "needs {count} rebirths", example = { count = "5" } },
	["world.reason.hold_max"] = { source = "you can only hold {count}", example = { count = "5" } },
	["world.reason.need_slime"] = { source = "need a {name}", example = { name = "Bubbles" } },
	["world.reason.need_cash"] = { source = "need {price}", example = { price = "$80" } },
	["world.reason.upgrade_locked"] = { source = "locked: reach {count} rebirths", example = { count = "3" } },
	["world.reason.vat_takes"] = { source = "The vat takes {rarity} slimes", example = { rarity = "Common" } },
	["world.reason.pad_rebirth"] = { source = "Rebirth {count} to unlock this pad", example = { count = "2" } },
	["world.reason.grab_rebirth"] = { source = "Rebirth {count} to grab this", example = { count = "12" } },
	["world.reason.open_shop"] = { source = "open the {shop} first", example = { shop = "Item Shop" } },

	-- Prompts on plots, slimes, props (ProximityPrompt ActionText / ObjectText)
	["world.prompt.lock_base"] = "Lock base",
	["world.prompt.free_plot"] = "Free plot",
	["world.prompt.buy_pad"] = "Buy pad",
	["world.prompt.merge_vat"] = "Merge vat",
	["world.prompt.manage_vat"] = "Manage vat",
	["world.prompt.block_friends"] = "Block friends",
	["world.prompt.allow_friends"] = "Allow friends",
	["world.prompt.friends_can_enter"] = "Friends can enter",
	["world.prompt.friends_blocked"] = "Friends: blocked",
	["world.prompt.status_open"] = "OPEN",
	["world.prompt.status_locked"] = { source = "LOCKED {time}", example = { time = "1:42" } },
	["world.prompt.base_status"] = {
		source = "{name}'s base: {status}",
		example = { name = "Merijn", status = "OPEN" },
	},
	["world.prompt.pad_rebirth"] = { source = "Rebirth {count} to unlock", example = { count = "3" } },
	["world.prompt.build_floor_price"] = {
		source = "Build floor {floor} {price}",
		example = { floor = "2", price = "$1.2K" },
	},
	["world.prompt.buy_pad_price"] = { source = "Buy pad {price}", example = { price = "$1.2K" } },
	["world.prompt.all_pads_unlocked"] = "All pads unlocked",
	["world.prompt.pad_of"] = { source = "Pad {pad} of {max}", example = { pad = "9", max = "24" } },
	["world.prompt.steal"] = "Steal",
	["world.prompt.grab"] = "Grab",
	["world.prompt.buy_price"] = { source = "Buy {price}", example = { price = "$1.5K" } },
	["world.prompt.boss_slime"] = { source = "BOSS {name}", example = { name = "Legendary King Goo" } },
	["world.prompt.hatch"] = "Hatch!",
	["world.prompt.drop_down"] = "Drop down",
	["world.prompt.goo_tube"] = "Goo tube",
	["world.prompt.item_shop"] = "Item Shop",
	["world.prompt.browse_items"] = "Browse items",
	["world.prompt.upgrade_shop"] = "Upgrade Shop",
	["world.prompt.browse_upgrades"] = "Browse upgrades",
	["world.prompt.exclusive_shop"] = "Exclusive Shop",
	["world.prompt.browse_exclusives"] = "Browse exclusives",
	["world.prompt.professor_goo"] = "Professor Goo",
	["world.prompt.view_leaderboards"] = "View leaderboards",
	["world.prompt.guide"] = "Guide",
	["world.prompt.talk"] = "Talk",
	-- Mystery Eggs
	["world.egg.lucky_meter"] = { source = "Lucky {count}/{max}", example = { count = "3", max = "12" } },
	["world.egg.hatch_object"] = {
		source = "{egg} · {meter}",
		example = { egg = "Golden Mystery Egg", meter = "Lucky 3/12" },
	},
	-- Signs on props (Props)
	["world.sign.item_shop"] = "Item shop",
	["world.sign.upgrade_shop"] = "Upgrade shop",
	["world.sign.exclusive"] = "EXCLUSIVE",
	["world.sign.hall_of_fame"] = "HALL OF FAME",
	["world.sign.obby"] = "OBBY",
	["world.sign.guide"] = "Guide",
	["world.sign.professor_goo"] = "Professor Goo",
	-- Boards
	["world.board.top_earners"] = "Top Earners",
	["world.board.no_entries"] = "No entries yet",
	-- The Upcoming Events board (EventBoard)
	["world.events.title"] = "UPCOMING EVENTS",
	["world.events.now"] = "NOW",
	["world.events.left"] = { source = "{time} left", example = { time = "2:05" } },
	["world.events.boss_fight"] = "Boss Fight",
	["world.events.boss_here"] = { source = "{name} is here!", example = { name = "King Goo" } },
	["world.events.boss"] = "Boss",
	["world.events.boss_arrives"] = "arrives at the fountain",
	["world.events.slime_rain"] = "Slime Rain",
	["world.events.rain_now"] = "rarer slimes fall now!",
	["world.events.rain_soon"] = "slimes pour from the sky",
	["world.events.legendary"] = "Legendary",
	["world.events.mythic"] = "Mythic",
	["world.events.guaranteed"] = "guaranteed from the fountain",
	["world.events.event_running"] = "event running",
	-- More refusal reasons (shared builders: VatState, MergeGate, EggKind)
	["world.reason.vat_add_any"] = { source = "Add {count} slimes of one rarity", example = { count = "3" } },
	["world.reason.vat_add_more"] = { source = "Add {count} more {rarity}", example = { count = "1", rarity = "Rare" } },
	["world.reason.rebirth_to_unlock"] = { source = "Rebirth {count} to unlock", example = { count = "3" } },
	["world.reason.locked"] = "Locked",
	["world.reason.egg_rank_one"] = {
		source = "Reach {rank} ({count} rebirth) to pick up {kind} Mystery Eggs",
		example = { rank = "Goo Getter", count = "1", kind = "Shiny" },
	},
	["world.reason.egg_rank_other"] = {
		source = "Reach {rank} ({count} rebirths) to pick up {kind} Mystery Eggs",
		example = { rank = "Slime Boss", count = "5", kind = "Cosmic" },
	},
	-- Why a slime can't be grabbed (GrabBlock, the GrabPrompt card)
	["world.grab.carrying"] = "Already carrying a slime",
	["world.grab.plot_full"] = "Plot is full, buy more pads",
	["world.grab.money"] = "Not enough money",
	["world.grab.wait"] = { source = "Grab in {seconds}s", example = { seconds = "1.5" } },
	["world.grab.need_more"] = { source = "Need {price} more", example = { price = "$1.2K" } },
	-- SlimeDex hints (SpeciesDex, State.dex)
	["world.dex.boss_hint"] = "Defeat the boss event",
	["world.dex.featured_week"] = { source = "Featured Secret: week of {date}", example = { date = "19 Oct" } },
	-- The merge vat's tag (VatView, MergeGate) and pad slimes in the vat
	["world.vat.ready"] = "Ready",
	["world.vat.brewing"] = { source = "Brewing {time}", example = { time = "0:12" } },
	["world.vat.move_in"] = "Move slimes in",
	["world.vat.load"] = { source = "{count}/{max} {rarity}", example = { count = "2", max = "3", rarity = "Rare" } },
	["world.vat.rebirth_to_merge"] = { source = "Rebirth {count} to merge", example = { count = "3" } },
	["world.vat.cant_merge"] = "Can't merge",
	["world.vat.up_to"] = { source = "Up to {rarity}", example = { rarity = "Rare" } },
	["world.vat.in_vat"] = "In vat",
	["world.vat.in_vat_brewing"] = "IN VAT",
	-- Slime labels (SlimeLabel: pad signs and floating tags)
	["world.label.brewed"] = { source = "Brewed {name}", example = { name = "Bubbles" } },
	["world.label.hatches_on_pad"] = { source = "Hatches in {time} on a pad", example = { time = "5:00" } },
	["world.label.ready_to_hatch"] = "Ready to hatch!",
	["world.label.hatches_in"] = { source = "Hatches in {time}", example = { time = "4:05" } },
	-- The ritual circle (Ritual)
	["world.ritual.title"] = "Slime Ritual",
	["world.ritual.resting"] = "Ritual resting",
	["world.ritual.hold_still"] = "Hold still!",
	["world.ritual.players"] = { source = "{count}/{max} players", example = { count = "1", max = "2" } },
	["world.ritual.charging"] = {
		source = "{count}/{max} - {seconds}s",
		example = { count = "2", max = "2", seconds = "3" },
	},
	["world.ritual.minutes"] = { source = "{count} min", example = { count = "5" } },
	["world.ritual.seconds"] = { source = "{count}s", example = { count = "90" } },
	["world.ritual.sign"] = {
		source = "Slime Ritual: {players} players stand here {hold}s = +{percent}% income for {duration}",
		example = { players = "2", hold = "5", percent = "10", duration = "5 min" },
	},
	-- The cash pads (CashPadView)
	["world.cash_pad.collect"] = "COLLECT",
	-- The plot sign (PlotSigns)
	["world.sign.plot_number"] = { source = "Plot {number}", example = { number = "3" } },
	["world.sign.empty_plot"] = "Empty plot",
	["world.sign.owner_plot"] = { source = "{name}'s plot", example = { name = "Merijn" } },
	["world.sign.plot_stats"] = {
		source = "{income}, {rebirths}, {steals}",
		example = { income = "+$1.25K/s", rebirths = "2 rebirths", steals = "1 steal" },
	},
	["world.sign.rebirths.one"] = { source = "{count} rebirth", example = { count = "1" } },
	["world.sign.rebirths.other"] = { source = "{count} rebirths", example = { count = "2" } },
	["world.sign.steals.one"] = { source = "{count} steal", example = { count = "1" } },
	["world.sign.steals.other"] = { source = "{count} steals", example = { count = "12" } },
	-- The obby board and sign (ObbyBoard, ObbyBoardView, ObbyRules)
	["world.obby.course"] = { source = "Course #{number}", example = { number = "1,204" } },
	["world.obby.board_course"] = {
		source = "{course} · new course in {time}",
		example = { course = "Course #1,204", time = "4:05" },
	},
	["world.obby.board_offline"] = "Board offline",
	["world.obby.last_course"] = {
		source = "Last course: {name} {time}",
		example = { name = "Merijn", time = "0:36.8" },
	},
	["world.obby.fastest_runs"] = "FASTEST RUNS",
	["world.obby.lock_rule"] = { source = "Base locks run {percent}% slower in a run", example = { percent = "50" } },
	["world.obby.no_times"] = "No times yet",
	-- The daily streak's rewards (DailyRewards, State.daily)
	["world.daily.egg"] = "Mystery Egg",
	["world.daily.egg_short"] = "Egg",
	["world.daily.boost"] = { source = "{mult}x income {minutes}m", example = { mult = "2", minutes = "15" } },
	["world.daily.consumables"] = { source = "{count} {name}s", example = { count = "2", name = "Luck Potion" } },
	["world.daily.trail"] = { source = "{name} trail", example = { name = "Sparkle" } },
	["world.daily.seat"] = { source = "{name} seat", example = { name = "Golden Cloud" } },
	-- Client markers and effects (visuals/client)
	["world.marker.next_pad"] = { source = "Next pad {price}", example = { price = "$1.2K" } },
	["world.marker.your_plot"] = "Your plot",
	["world.obby.vine_hint"] = "Jump to let go",
	["world.obby.back_to_base"] = "BACK TO BASE",
	["world.fx.lucky"] = "🍀 LUCKY!",
	["world.fx.rarity_step"] = {
		source = '<font color="{fromColor}">{from}</font> → <font color="{toColor}">{to}</font>',
		example = { fromColor = "#FFC428", from = "Legendary", toColor = "#EC5AFF", to = "Mythic" },
	},
	["world.fx.lucky_hatch"] = { source = "LUCKY! {rarity}", example = { rarity = "MYTHIC!" } },
	-- The claw show's banner (ClawShow) and the names of cosmetics in it (Purchases.itemMessage)
	["world.claw.got"] = { source = "{buyer} got {item}!", example = { buyer = "Merijn", item = "the Sparkle trail" } },
	["world.claw.gifted"] = {
		source = "{buyer} gifted {item}!",
		example = { buyer = "Merijn", item = "the Sparkle trail" },
	},
	["world.claw.prize"] = { source = "{buyer} got a prize!", example = { buyer = "Merijn" } },
	["world.item.trail"] = { source = "the {name} trail", example = { name = "Sparkle" } },
	["world.item.the"] = { source = "the {name}", example = { name = "Golden Bat" } },
	["world.item.bat"] = { source = "the {name} Bat", example = { name = "Candy" } },
	["world.item.base_skin"] = { source = "the {name} base skin", example = { name = "Candy" } },
	["world.item.base"] = { source = "the {name} base", example = { name = "Goo Factory" } },
	["world.item.lockStyle"] = { source = "the {name} lock", example = { name = "Heart" } },
	-- Refusals of gifts and server boosts (Purchases)
	["world.reason.that_cant_be_gifted"] = "that can't be gifted",
	["world.reason.you_cant_gift_yourself"] = "you can't gift yourself",
	["world.reason.that_player_isnt_in_this_server"] = "that player isn't in this server",
	["world.reason.they_already_have_it"] = "they already have it",
	["world.reason.a_slime_rain_is_already_falling"] = "a Slime Rain is already falling",
	["world.reason.not_during_a_boss"] = "not during a boss",
	["world.reason.next_paid_rain"] = {
		source = "the next paid rain is possible in {minutes} min",
		example = { minutes = "12" },
	},
	["world.reason.the_boss_is_already_here"] = "the boss is already here",
	["world.reason.the_boss_is_on_its_way_already"] = "the boss is on its way already",
	["world.reason.not_during_a_slime_rain"] = "not during a Slime Rain",
	["world.reason.boss_summon_again"] = {
		source = "the boss can be summoned again in {minutes} min",
		example = { minutes = "12" },
	},
	["world.vat.merges_open"] = {
		source = "{rarity} merges open at Rebirth {count}",
		example = { rarity = "Epic", count = "3" },
	},
	["world.vat.merges_locked"] = { source = "{rarity} merges are locked", example = { rarity = "Secret" } },
	-- END
}

-- A rebirth rank's perks (Perks.tierMessage): one sentence per mix of perks, the same words as Perks.tierText.
do
	local UNLOCK = "unlocks the {upgrade} upgrade"
	local INCOME = "+{percent}% income"
	local MERGES = "opens {rarities} merges"
	local example = { upgrade = "Strong Arms", percent = 25, rarities = "Rare" }
	local parts = { unlock = UNLOCK, income = INCOME, merges = MERGES }
	for _, combo in
		{ "unlock", "income", "merges", "unlock_income", "unlock_merges", "income_merges", "unlock_income_merges" }
	do
		local words, ex = {}, {}
		for _, part in string.split(combo, "_") do
			table.insert(words, parts[part])
			local name = if part == "unlock" then "upgrade" elseif part == "income" then "percent" else "rarities"
			ex[name] = example[name]
		end
		defs[`world.rank.{combo}`] = { source = table.concat(words, ", "), example = ex }
	end
end

-- The follow pet's perk ("+3% income"), one per Config.PET_PASSIVES kind (Perks.petPassive).
for kind, def: any in Config.PET_PASSIVES.KINDS :: any do
	defs[`world.pet_perk.{kind}`] = { source = `+\{percent\}% {def.word}`, example = { percent = 3 } }
end

for _, recipe in MergeRecipes.RECIPES do
	defs[`world.recipe.{recipe.id}`] = recipe.hint
end

-- The hatch title's shout per rarity ("LEGENDARY!", EggHatchTimeline.titleMessage).
for _, rarity in Config.RARITIES do
	defs[`world.fx.shout.{rarity.name}`] = `{string.upper(rarity.name)}!`
end

-- The daily streak's narrow tiles: the first word of a reward's name ("Luck", "Golden"), DailyRewards.firstWord.
for kind, list in { consumable = Config.CONSUMABLES, trail = Config.EXCLUSIVE_SHOP.trails, seat = Config.PET_SEATS } do
	for _, row in list :: any do
		defs[`world.daily_short.{kind}.{row.id}`] = DailyRewards.firstWord(row.name)
	end
end

return defs
