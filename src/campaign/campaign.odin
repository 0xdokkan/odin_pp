package campaign

import game "../game"

SLOT_COUNT :: 3
NORMAL_BIOMES :: 11
ARCADE_RECORDS :: 16
Biome :: enum u8 { Cyber, West, Jungle, City, Egypt, Vietnam, Snow, Inferno, Gothic, Sky, Space, Secret, Count }
BIOME_NAMES :: [Biome.Count]string{"Robotica cibernetica", "Far West", "Giungla preistorica", "City pop", "Antico Egitto", "Vietnam", "Montagne innevate", "Inferno", "Southern gothic", "Isola nel cielo", "Spazio", "La memoria del creatore"}
biome_name :: proc(biome: Biome) -> string { names := BIOME_NAMES; return names[biome] if biome < .Count else "Sconosciuto" }
biome_rank :: proc(biome: Biome) -> int {
	#partial switch biome {
	case .Cyber: return 0
	case .West, .Jungle, .City: return 1
	case .Egypt, .Vietnam, .Snow: return 2
	case .Inferno, .Gothic, .Sky: return 3
	case .Space: return 4
	case: return 5
	}
}
biome_size :: proc(biome: Biome) -> int { return 160 if biome_rank(biome) <= 1 else (192 if biome_rank(biome) == 2 else 224) }
Record :: struct { best_score: i64, best_stars: u8, plays, wins: u32 }
Run_Progress :: struct {
	active: bool,
	biome: Biome,
	seed: u64,
	level: i32,
	xp: i32,
	points: i32,
	pool: [game.Card_Id.Count]bool,
	boss_defeated: bool,
	// TEMPORARY test mode: the biome was open only through test_all_biomes.
	test: bool,
}
Campaign :: struct {
	initialized: bool,
	backpack: Backpack,
	depot: [dynamic]Inventory_Grid,
	discovered: [game.Card_Id.Count]bool,
	secrets: [Biome.Count]u64,
	unlocked: [Biome.Count]bool,
	visited: [Biome.Count]bool,
	won: [Biome.Count]bool,
	streak_biomes: [Biome.Count]bool,
	streak, best_streak, total_wins, deaths: u32,
	normal_ending, true_ending: bool,
	memory_fragments: u64,
	backpack_width: int,
	records: [ARCADE_RECORDS]Record,
	run: Run_Progress,
	play_seconds: f64,
	saved_unix_seconds: i64,
	revision: u64,
	// TEMPORARY test mode: every biome opens for play without touching unlocked.
	test_all_biomes: bool,
}

initialize :: proc(c: ^Campaign) {
	if c == nil { return }
	c^ = {initialized = true, backpack = make_backpack(), backpack_width = BACKPACK_WIDTH}
	c.unlocked[Biome.Cyber] = true
	append(&c.depot, make_grid(GRID_MAX_WIDTH, GRID_MAX_HEIGHT))
	for id in game.Card_Id.Strike..<game.Card_Id.Count {
		definition, _ := game.card_definition_by_id(id)
		c.discovered[id] = game.card_in_collection(id) && (definition.rarity == .Common ||
			id == .Dash || id == .Shove || id == .Guard || id == .Lasso || id == .Fishing_Rod)
	}
}
destroy :: proc(c: ^Campaign) { if c != nil { delete(c.depot); c^ = {} } }
// TEMPORARY test mode (branch biomi-sbloccati): to remove it, delete
// test_all_biomes, Run_Progress.test and every use of them, then read
// c.unlocked again where biome_open is called. A slot saved during a test
// expedition would no longer load, so finish those expeditions first.
biome_open :: proc(c: ^Campaign, biome: Biome) -> bool {
	return c != nil && biome < .Count && (c.unlocked[biome] || c.test_all_biomes)
}
// The switch waits for the hub: an expedition keeps the mode it left with.
set_test_all_biomes :: proc(c: ^Campaign, on: bool) -> bool {
	if c == nil || !c.initialized || c.run.active { return false }
	c.test_all_biomes = on; c.revision += 1
	return true
}
begin_run :: proc(c: ^Campaign, biome: Biome, seed: u64) -> bool {
	if c == nil || !c.initialized || c.run.active || !biome_open(c, biome) ||
	   c.backpack.pending_count > 0 { return false }
	test := !c.unlocked[biome]
	c.run = {active = true, biome = biome, seed = seed, level = 1, pool = c.discovered, test = test}
	if !test { c.visited[biome] = true }
	c.revision += 1
	return true
}
discover :: proc(c: ^Campaign, card: game.Card_Id) -> bool {
	if c == nil || card < .Strike || card >= .Count || c.discovered[card] || !game.card_in_collection(card) { return false }
	c.discovered[card] = true; c.revision += 1
	// Do not change the current run pool: archive discoveries become available
	// only on the next expedition, even if the present expedition is lost.
	return true
}
card_in_pool :: proc(c: ^Campaign, card: game.Card_Id) -> bool {
	if c == nil || card < .Strike || card >= .Count || !game.card_in_collection(card) { return false }
	return c.run.pool[card] if c.run.active else c.discovered[card]
}
discover_secret :: proc(c: ^Campaign, biome: Biome, index: int) -> bool {
	if c == nil || biome >= .Count || index < 0 || index >= 64 { return false }
	mask := u64(1) << u64(index)
	if c.secrets[biome] & mask != 0 { return false }
	c.secrets[biome] |= mask; c.revision += 1
	return true
}
secret_known :: proc(c: ^Campaign, biome: Biome, index: int) -> bool {
	return c != nil && biome < .Count && index >= 0 && index < 64 && c.secrets[biome] & (u64(1) << u64(index)) != 0
}
xp_for_level :: proc(level: i32) -> i32 { return 4+2*clamp(level, 1, 1000000) }
add_xp :: proc(c: ^Campaign, amount: i32) -> (levels: i32) {
	if c == nil || !c.run.active || amount <= 0 { return }
	c.run.xp = i32(min(i64(max(i32)), i64(c.run.xp)+i64(amount)))
	for c.run.xp >= xp_for_level(c.run.level) {
		c.run.xp -= xp_for_level(c.run.level); c.run.level += 1; c.run.points += 1; levels += 1
	}
	c.revision += 1
	return
}
upgrade_card :: proc(c: ^Campaign, deck: ^game.Deck_State, card_id: u32, in_combat: bool) -> bool {
	if c == nil || !c.run.active || c.run.points <= 0 || deck == nil || in_combat || deck.combat_active { return false }
	if game.upgrade_owned_card(deck, card_id) != .Upgraded { return false }
	c.run.points -= 1; c.revision += 1
	return true
}

depot_add :: proc(c: ^Campaign, item: Item) -> bool {
	if c == nil || !item_valid(item) { return false }
	for &page in c.depot { if grid_add(&page, item) { c.revision += 1; return true } }
	page := make_grid(GRID_MAX_WIDTH, GRID_MAX_HEIGHT)
	if !grid_add(&page, item) { return false }
	append(&c.depot, page); c.revision += 1
	return true
}
depot_take :: proc(c: ^Campaign, page, index: int) -> bool {
	if c == nil || c.run.active || page < 0 || page >= len(c.depot) || index < 0 || index >= c.depot[page].count { return false }
	item := c.depot[page].entries[index].item
	if !grid_add(&c.backpack.grid, item) { return false }
	grid_remove(&c.depot[page], index); c.revision += 1
	return true
}
depot_store :: proc(c: ^Campaign, index: int) -> bool {
	if c == nil || c.run.active || index < 0 || index >= c.backpack.grid.count { return false }
	if !depot_add(c, c.backpack.grid.entries[index].item) { return false }
	grid_remove(&c.backpack.grid, index); c.revision += 1
	return true
}
depot_credits :: proc(c: ^Campaign) -> (total: i64) {
	if c == nil { return }
	for &page in c.depot { for entry in page.entries[:page.count] { if entry.item.kind == .Credits { total += i64(entry.item.quantity) } } }
	return
}
depot_pay :: proc(c: ^Campaign, amount: i64) -> bool {
	if c == nil || amount < 0 || depot_credits(c) < amount { return false }
	left := amount
	for &page in c.depot {
		index := 0
		for index < page.count && left > 0 {
			entry := &page.entries[index]
			if entry.item.kind != .Credits { index += 1; continue }
			paid := i32(min(left, i64(entry.item.quantity)))
			left -= i64(paid); entry.item.quantity -= paid
			if entry.item.quantity == 0 { grid_remove(&page, index) } else { index += 1 }
		}
	}
	c.revision += 1
	return true
}
depot_credit :: proc(c: ^Campaign, amount: i64) -> bool {
	if c == nil || amount < 0 { return false }
	for left := amount; left > 0; {
		part := i32(min(left, 99)); if !depot_add(c, make_item(.Credits, part)) { return false }; left -= i64(part)
	}
	return true
}

@(private)
extract_item :: proc(c: ^Campaign, item: Item) {
	if item.kind == .None { return }
	if item.kind == .Memory { c.memory_fragments |= u64(1) << u64(item.variant) }
	if item.kind == .Backpack { c.backpack_width = max(c.backpack_width, min(GRID_MAX_WIDTH, BACKPACK_WIDTH+max(1, int(item.variant)))) }
	depot_add(c, item)
}

// A failed or zero-star arcade still extracts every item and counts as a win.
// Repeated wins in one biome cannot replace a missing biome in the streak.
finish_run :: proc(c: ^Campaign, victory: bool, stars: u8 = 0) -> bool {
	if c == nil || !c.run.active { return false }
	biome := c.run.biome
	if victory {
		for entry in c.backpack.grid.entries[:c.backpack.grid.count] { extract_item(c, entry.item) }
		for item in c.backpack.relics { extract_item(c, item) }
		extract_item(c, c.backpack.weapon)
		for item in c.backpack.pending[:c.backpack.pending_count] { extract_item(c, item) }
	}
	// A test expedition only moves the backpack: wins, streak, routes,
	// endings and deaths stay as the real progress left them.
	if c.run.test {
		if victory { reward_stars(c, stars) }
		c.backpack = make_backpack(c.backpack_width); c.run = {}; c.revision += 1
		return true
	}
	if victory {
		c.streak += 1; c.best_streak = max(c.best_streak, c.streak); c.total_wins += 1
		c.won[biome] = true; c.streak_biomes[biome] = true
		#partial switch biome {
		case .Cyber: c.unlocked[Biome.West] = true; c.unlocked[Biome.City] = true; c.unlocked[Biome.Jungle] = true
		case .West: c.unlocked[Biome.Egypt] = true
		case .Egypt: c.unlocked[Biome.Inferno] = true
		case .City: c.unlocked[Biome.Snow] = true
		case .Snow: c.unlocked[Biome.Sky] = true
		case .Jungle: c.unlocked[Biome.Vietnam] = true
		case .Vietnam: c.unlocked[Biome.Gothic] = true
		case .Secret: c.true_ending = true
		case:
		}
		all_before_space, all_won, complete_streak := true, true, true
		for i in 0..<NORMAL_BIOMES {
			if i < int(Biome.Space) { all_before_space = all_before_space && c.won[i] }
			all_won = all_won && c.won[i]; complete_streak = complete_streak && c.streak_biomes[i]
		}
		if all_before_space { c.unlocked[Biome.Space] = true }
		if all_won { c.normal_ending = true }
		if complete_streak { c.unlocked[Biome.Secret] = true }
		reward_stars(c, stars)
	} else {
		c.streak = 0; c.streak_biomes = {}; c.deaths += 1
	}
	c.backpack = make_backpack(c.backpack_width); c.run = {}; c.revision += 1
	return true
}
@(private)
reward_stars :: proc(c: ^Campaign, stars: u8) {
	// Bonus tiers are cumulative; archive discovery is deterministic and
	// cannot consume an expedition's combat or reward random stream.
	if stars >= 1 { depot_credit(c, 20) }
	if stars >= 2 { depot_add(c, make_item(.Healing, 2)) }
	if stars >= 3 {
		found := false
		for id in game.Card_Id.Strike..<game.Card_Id.Count {
			if discover(c, id) { found = true; break }
		}
		if !found { depot_add(c, make_item(.Relic, 1, i32(game.Relic_Id.Guard_Sigil))) }
	}
}
record_result :: proc(c: ^Campaign, index: int, score: i64, stars: u8, won: bool) -> bool {
	if c == nil || index < 0 || index >= ARCADE_RECORDS { return false }
	record := &c.records[index]
	better := score > record.best_score || stars > record.best_stars
	record.plays += 1; if won { record.wins += 1 }
	record.best_score = max(record.best_score, score); record.best_stars = max(record.best_stars, min(stars, 3))
	c.revision += 1
	return better
}
campaign_valid :: proc(c: ^Campaign) -> bool {
	if c == nil || !c.initialized || !backpack_valid(&c.backpack) || len(c.depot) == 0 || len(c.depot) > 10000 ||
	   c.backpack_width < BACKPACK_WIDTH || c.backpack_width > GRID_MAX_WIDTH || !c.unlocked[Biome.Cyber] ||
	   c.play_seconds < 0 || c.play_seconds > 1e12 || c.streak > c.best_streak || c.streak > c.total_wins { return false }
	if c.run.active && (!biome_open(c, c.run.biome) || c.run.test == c.unlocked[c.run.biome] || c.run.level < 1 || c.run.level > 1000000 ||
	   c.run.xp < 0 || c.run.xp >= xp_for_level(c.run.level) || c.run.points < 0) { return false }
	for &page in c.depot { if !grid_valid(&page) { return false } }
	for record in c.records { if record.best_stars > 3 || record.wins > record.plays { return false } }
	return true
}
