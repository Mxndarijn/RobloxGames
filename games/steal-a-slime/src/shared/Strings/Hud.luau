--!strict
-- Player-facing English for the hud area (keys start with "hud."). Localize.catalog checks it.
-- The HUD's money and status clusters, their tooltips, the left menu, steal cards, the boss card, the obby
-- card, the carry overlay, world pop-up words and the join loading screen.
return {
	-- Status slots (bottom right): name and effect in the tooltip.
	["hud.status.now"] = "Now",
	["hud.status.rain.name"] = "Slime Rain",
	["hud.status.rain.effect"] = "Slimes pour from the sky and rarer ones show up more often. Grab them!",
	["hud.status.event.effect"] = {
		source = "{luck} luck: rarer slimes show up more often.",
		example = { luck = "x2" },
	},
	["hud.status.luck.name"] = "Luck Potion",
	["hud.status.luck.effect"] = {
		source = "{luck} luck for everyone on this server: rarer slimes come from the fountain.",
		example = { luck = "x2.5" },
	},
	["hud.status.friend.name"] = "Friend boost",
	["hud.status.friend.effect"] = {
		source = "{percent} income while your friends play on this server.",
		example = { percent = "+20%" },
	},
	["hud.status.blessed.name"] = "Blessed",
	["hud.status.blessed.effect"] = {
		source = "{percent} income from the Slime Ritual.",
		example = { percent = "+30%" },
	},
	["hud.status.mvp.name"] = "Boss Champion",
	["hud.status.mvp.effect"] = {
		source = "{income} income and {speed} speed for bringing a boss home.",
		example = { income = "+25%", speed = "+10%" },
	},
	["hud.status.obby.name"] = "Obby",
	["hud.status.obby.effect"] = {
		source = "{income} income from the obby sections you cleared.",
		example = { income = "x1.3" },
	},
	["hud.status.obby.cooldown_effect"] = {
		source = "Run the obby again after this: every section adds income, up to {income}.",
		example = { income = "x2" },
	},
	["hud.status.boost.name"] = "Income boost",
	["hud.status.boost.effect"] = {
		source = "{income} income from a code or quest reward.",
		example = { income = "x2" },
	},
	["hud.status.pet.name"] = "Pet bonus",
	["hud.status.pet.income_effect"] = {
		source = "{percent} income from your favourite slime riding along with you.",
		example = { percent = "+3%" },
	},
	["hud.status.pet.luck_effect"] = {
		source = "{percent} luck from your favourite slime riding along with you: rarer slimes show up more often.",
		example = { percent = "+3%" },
	},
	["hud.status.secret.name"] = { source = "Featured Secret: {name}", example = { name = "Nebula" } },
	["hud.status.secret.effect"] = "Can spawn as a Secret this week.",
	["hud.status.lock_break.name"] = "Lock break",
	["hud.status.lock_break.effect"] = "You can walk through that base's locked door. It stays locked for everyone else.",

	-- Status tooltip: the time line.
	["hud.tooltip.ends_in"] = { source = "Ends in {time}", example = { time = "4h 6m" } },
	["hud.tooltip.while_friends"] = "Active while friends are here",
	["hud.tooltip.while_pet"] = "Active while your pet follows you",
	["hud.tooltip.active_now"] = "Active now",
	["hud.tooltip.starts_in"] = { source = "Starts in {time}", example = { time = "1:40" } },
	["hud.tooltip.next_boost"] = { source = "Next boost ready in {time}", example = { time = "1:40" } },
	["hud.tooltip.time_left"] = { source = "Time left: {time}", example = { time = "1:37" } },

	-- Server modifier, weekend, rain and friend lines.
	["hud.modifier.luck"] = { source = "{name} {luck} luck", example = { name = "Luck Surge", luck = "x2" } },
	["hud.modifier.luck_left"] = {
		source = "{name} {luck} luck - {time} left",
		example = { name = "Luck Surge", luck = "x2", time = "3:20" },
	},
	["hud.modifier.left"] = { source = "{name} - {time} left", example = { name = "Golden Hour", time = "3:20" } },
	["hud.weekend.name"] = { source = "{mult} Weekend", example = { mult = "x2" } },
	["hud.weekend.left"] = { source = "{mult} Weekend - {time} left", example = { mult = "x2", time = "1d 4h" } },
	["hud.rain.active"] = { source = "SLIME RAIN! Luck {luck}", example = { luck = "x2" } },
	["hud.rain.active_left"] = {
		source = "SLIME RAIN! Luck {luck} - {time} left",
		example = { luck = "x2", time = "1:05" },
	},
	["hud.rain.soon"] = { source = "Slime Rain in {time}", example = { time = "4:30" } },
	["hud.friends.income"] = { source = "Friends {percent} income", example = { percent = "+20%" } },

	-- Left menu tiles.
	["hud.nav.rebirth"] = "Rebirth",
	["hud.nav.goals"] = "Goals",
	["hud.nav.dex"] = "SlimeDex",
	["hud.nav.codes"] = "Codes",
	["hud.nav.skins"] = "Skins",
	["hud.nav.leaders"] = "Leaders",
	["hud.nav.settings"] = "Settings",

	-- Steal cards (top centre) and the boss card's alarm strip. {name} is a player's display name.
	["hud.steal.someone"] = "someone",
	["hud.steal.stealing"] = { source = "{name} is stealing your slime!", example = { name = "Ann" } },
	["hud.steal.stealing_two"] = {
		source = "{first} and {second} are stealing your slimes!",
		example = { first = "Ann", second = "Bo" },
	},
	["hud.steal.stealing_many"] = {
		source = "{first} and {others} others are stealing your slimes!",
		example = { first = "Ann", others = "2" },
	},
	["hud.steal.stolen"] = { source = "{name} has stolen one of your slimes", example = { name = "Ann" } },
	["hud.steal.bonked"] = "You got bonked!",
	["hud.steal.home"] = "Your slime is back home",
	["hud.steal.locked"] = "This base is locked",
	["hud.steal.stealing_hint"] = "Chase them and hit them with your bat",
	["hud.steal.stolen_hint"] = "Lock your base to keep the rest safe",
	["hud.steal.bonked_hint"] = "The slime bounced home",
	["hud.steal.home_hint"] = { source = "It escaped from {name}", example = { name = "Ann" } },
	["hud.steal.opens_in"] = { source = "Opens in {time}", example = { time = "1:42" } },
	["hud.steal.strip_chase"] = "Chase them",
	["hud.steal.strip_lock"] = "Lock your base",
	["hud.steal.strip_bounced"] = "It bounced home",
	["hud.steal.more"] = { source = "+{count} more", example = { count = "2" } },

	-- Steal alert arrow.
	["hud.alert.thief"] = "Thief",
	["hud.alert.visitor"] = "Visitor",

	-- Words that pop up over players and slimes.
	["hud.fx.bonk"] = "BONK!",
	["hud.fx.chomp"] = "CHOMP!",
	["hud.fx.pop"] = "POP!",
	["hud.fx.boing"] = "BOING!",
	["hud.fx.squeak"] = "SQUEAK!",
	["hud.fx.mega_squeak"] = "MEGA SQUEAK!",
	["hud.fx.squeak_small"] = "squeak",

	-- Member tags over heads and in chat.
	["hud.member.vip"] = "VIP",
	["hud.member.club"] = "CLUB",

	-- Rare drop banner.
	["hud.rare.secret"] = "SECRET",
	["hud.rare.rare"] = "RARE",
	["hud.rare.spilled"] = {
		source = "A {rarity} slime spilled from the fountain! Grab it!",
		example = { rarity = "LEGENDARY" },
	},

	-- Boss card. {name} is the boss's name, a player's name for carrier / priority / winner.
	["hud.boss.the_boss"] = "The boss",
	["hud.boss.ouch"] = { source = "Ouch! {seconds}s", example = { seconds = "3" } },
	["hud.boss.hits"] = { source = "Hits {mult}", example = { mult = "x3" } },
	["hud.boss.guards"] = { source = "Guards {left}/{total}", example = { left = "2", total = "4" } },
	["hud.boss.dodge"] = "Dodge!",
	["hud.boss.you_share"] = { source = "You {percent}", example = { percent = "42%" } },
	["hud.boss.hit_it"] = "Hit it!",
	["hud.boss.incoming"] = "BOSS INCOMING",
	["hud.boss.to_plaza"] = "To the plaza",
	["hud.boss.down"] = { source = "{name} is down!", example = { name = "King Goo" } },
	["hud.boss.grab_it"] = "Grab it!",
	["hud.boss.carry_home"] = "Carry it home",
	["hud.boss.has_it"] = { source = "{name} has it", example = { name = "Ann" } },
	["hud.boss.bonk"] = "Bonk!",
	["hud.boss.grabs_first"] = { source = "{name} grabs first", example = { name = "Ann" } },
	["hud.boss.winner_team"] = { source = "{name} + team", example = { name = "Ann" } },
	["hud.boss.the_team"] = "The team",
	["hud.boss.brought_home"] = "Brought home!",
	["hud.boss.badges.one"] = { source = "{count} badge", example = { count = "+1" } },
	["hud.boss.badges.other"] = { source = "{count} badges", example = { count = "+2" } },
	["hud.boss.shared_win"] = "Shared win",
	["hud.boss.got_away"] = { source = "{name} got away", example = { name = "King Goo" } },
	["hud.boss.next_in"] = { source = "Next {time}", example = { time = "9:30" } },
	["hud.boss.next_time"] = "Next time!",

	-- Obby sign and run card.
	["hud.obby.step_in"] = "Step in to start!",
	["hud.obby.boost_left"] = {
		source = "{income} income · {time} left",
		example = { income = "x1.5", time = "3:12" },
	},
	["hud.obby.boost_ready_in"] = { source = "Boost ready in {time}", example = { time = "1:40" } },
	["hud.obby.step_in_up_to"] = { source = "Step in: up to {income} income!", example = { income = "x2" } },
	["hud.obby.course_every"] = { source = "A new course every {minutes} min", example = { minutes = "15" } },
	["hud.obby.new_course_in"] = { source = "New course in {time}", example = { time = "12:34" } },
	["hud.obby.course_left"] = {
		source = "Course #{course} · {time} left",
		example = { course = "1,204", time = "12:34" },
	},
	["hud.obby.best"] = { source = "Best {time}", example = { time = "0:51.4" } },
	["hud.obby.you"] = "You",
	["hud.obby.you_rank"] = { source = "You {rank}", example = { rank = "#23" } },
	["hud.obby.start"] = "Start",
	["hud.obby.finish"] = "Finish",
	["hud.obby.section"] = { source = "Section {at}/{of}", example = { at = "3", of = "6" } },
	["hud.obby.income"] = { source = "{income} income", example = { income = "x1.3" } },
	["hud.obby.per_section"] = { source = "{percent} a section", example = { percent = "+17%" } },
	["hud.obby.total"] = { source = "Total {time}", example = { time = "2:14" } },
	["hud.obby.base_open"] = "Base open",
	["hud.obby.slower_locks"] = { source = "{percent} slower locks", example = { percent = "50%" } },

	-- Rebirth and SlimeDex progress lines.
	["hud.progress.tier_now"] = {
		source = "Now · rebirth {rebirth}: {income} income · {seconds}s lock",
		example = { rebirth = "3", income = "x2.5", seconds = "40" },
	},
	["hud.progress.tier"] = {
		source = "Rebirth {rebirth}: {income} income · {seconds}s lock",
		example = { rebirth = "4", income = "x3", seconds = "45" },
	},
	["hud.progress.max_reached"] = "Max rebirths reached",
	["hud.progress.ready_now"] = "READY! Rebirth now",
	["hud.progress.more_needed"] = {
		source = "{amount} more needed ({percent})",
		example = { amount = "$3.7K", percent = "42%" },
	},
	["hud.progress.max"] = "Max rebirths",
	["hud.progress.ready"] = "Ready!",
	["hud.progress.more"] = { source = "{amount} more", example = { amount = "$3.7K" } },
	["hud.progress.slime_a"] = { source = "a {name}", example = { name = "Flan" } },
	["hud.progress.slime_an"] = { source = "an {name}", example = { name = "Imp" } },
	["hud.progress.all_done"] = "All rebirths done",
	["hud.progress.need"] = { source = "Need {items}", example = { items = "$15.5M and a Flan" } },
	["hud.progress.need_more"] = { source = "Need {amount} more", example = { amount = "$178.8K" } },
	["hud.progress.wait_vat"] = { source = "Wait for the vat: {name} is brewing", example = { name = "Flan" } },
	["hud.progress.not_ready"] = "Not ready yet",
	["hud.progress.top_rank"] = "Top rank reached!",
	["hud.progress.next_rank"] = {
		source = "Next: {title} at {rebirths} rebirths",
		example = { title = "Slime Wrangler", rebirths = "3" },
	},
	["hud.progress.next_rank_perk"] = {
		source = "Next: {title} at {rebirths} rebirths - {perk}",
		example = { title = "Slime Wrangler", rebirths = "3", perk = "unlocks the OfflineCap upgrade" },
	},
	["hud.progress.rank"] = { source = "Rank: {title}", example = { title = "Goo Getter" } },
	["hud.progress.dex_all"] = "All SlimeDex rewards collected!",
	["hud.progress.dex_next"] = {
		source = "Next: {count} species {cash}, {percent} income",
		example = { count = "15", cash = "+$5K", percent = "+3%" },
	},
	["hud.progress.dex_bonus"] = { source = "SlimeDex bonus: {percent} income", example = { percent = "+5%" } },
	["hud.progress.dex_short"] = { source = "SlimeDex {percent}", example = { percent = "+5%" } },

	-- Lists: "x, y and z".
	["hud.list.comma"] = { source = "{list}, {item}", example = { list = "$15.5M", item = "a Flan" } },
	["hud.list.and"] = { source = "{list} and {item}", example = { list = "$15.5M, a Flan", item = "an Imp" } },

	-- Carry overlay.
	["hud.carry.drop"] = "Drop",
	["hud.carry.stolen"] = "Bring the slime to your plot!",
	["hud.carry.wild"] = "Wild slime - bring it to your plot",
	["hud.carry.full"] = "Your plot is full",
	["hud.carry.full_hint"] = "Sell or merge a slime",

	-- Join loading screen (src/first/LoadingGate keeps the same English as its fallback).
	["hud.loading.tip_lock"] = "Lock your base to stop thieves",
	["hud.loading.tip_steal"] = "Steal slimes from other bases",
	["hud.loading.tip_rarer"] = "Rarer slimes earn more cash",
	["hud.loading.tip_merge"] = "Merge two slimes in the vat",
	["hud.loading.tip_obby"] = "Run the obby for a cash boost",
	["hud.loading.ready"] = "Ready!",
	["hud.loading.skip"] = "Skip",
}
