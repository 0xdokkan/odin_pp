package run

import advisor "../advisor"
import campaign "../campaign"
import world "../expedition"
import game "../game"

// THE IA'S GAME STATE (docs/piano-ia.md, Fase 6): the run, the expedition and the lab tell the advisor how near the end
// is, which real heals are near and which foes sleep on the map (advisor.Game_Context). The scenes set it every frame
// before the tactical controller (advisor_set_context); the pilot hands it to the worker with every snapshot.
//
// THE TABLES OF PLACES AND OF THE BACKPACK (the rule for ever: docs/piano-ia.md, «La regola per sempre»): every place of
// the expedition, every node of the run, every biome and every item of the backpack has its line, in switches with no
// default: a new one does not build until the IA knows it.

// How far a real heal outside the fight still counts (the plan's proposal): a FONTE within 20 cells.
ADVISOR_HEAL_REACH :: 20
// How far a sleeping foe still matters: those farther away cannot be woken within the search's horizon.
ADVISOR_SLEEPER_REACH :: 24

Advisor_Place :: struct {
	// The life it gives back once, outside the fight (0: none).
	heal: i32,
	// Foes wait there (a NIDO's waves, a trial, the boss).
	foes: bool,
	why: string,
}

advisor_site :: proc(kind: world.Site_Kind) -> Advisor_Place {
	switch kind {
	case .Spring: return {heal = 16, why = "la FONTE cura 16 una volta"}
	case .Nest: return {foes = true, why = "il NIDO manda ondate di nemici"}
	case .Trial: return {foes = true, why = "la PROVA è uno scontro"}
	case .Boss: return {foes = true, why = "il boss: la fine della spedizione"}
	case .Cache: return {why = "un forziere: niente vita"}
	case .Archive: return {why = "un archivio: niente vita"}
	case .Workshop: return {why = "un'officina: niente vita"}
	case .Memory: return {why = "una memoria: niente vita"}
	case .Tunnel: return {why = "un tunnel: niente vita"}
	case .Cave: return {why = "una grotta: i suoi gruppi contano come gli altri"}
	}
	return {}
}

Advisor_Node :: struct {
	// The share of the player's life it gives back (the Rest: 30%).
	heal_percent: i32,
	why: string,
}

advisor_node :: proc(kind: game.Node_Kind) -> Advisor_Node {
	switch kind {
	case .Rest: return {heal_percent = 30, why = "il Riposo cura il 30% della vita"}
	case .Combat: return {why = "uno scontro"}
	case .Elite: return {why = "uno scontro più duro"}
	case .Boss: return {why = "il boss: la fine della run"}
	case .Shop: return {why = "il negozio: niente vita gratis"}
	case .Event: return {why = "un evento: niente vita certa"}
	case .Treasure: return {why = "un tesoro: niente vita"}
	case .Count:
	}
	return {}
}

// What the IA knows of a biome: its foes are the biome's, the same table of foes (advisor.enemy_knowledge); its rank
// (campaign.biome_rank) tells how hard. Nothing else changes the advice yet.
advisor_biome :: proc(biome: campaign.Biome) -> string {
	switch biome {
	case .Cyber: return "Robotica cibernetica: il primo bioma"
	case .West, .Jungle, .City: return "un bioma del secondo giro"
	case .Egypt, .Vietnam, .Snow: return "un bioma del terzo giro"
	case .Inferno, .Gothic, .Sky: return "un bioma del quarto giro"
	case .Space: return "lo Spazio: il più duro"
	case .Secret: return "la memoria del creatore"
	case .Count:
	}
	return ""
}

// The life an item of the backpack gives back (0: none). The Cibo pescato does not count (the user's exception: the
// fishing rod's food); the Kit di riparazione cures 12.
advisor_item_heal :: proc(item: campaign.Item) -> i32 {
	switch item.kind {
	case .Healing: return 0 if item.variant > 0 else 12
	case .None, .Energy, .Temporary_Card, .Decoy, .Upgrade, .Weapon, .Relic, .Credits, .Memory, .Backpack, .Structure_Kit: return 0
	}
	return 0
}

// The game's state the scenes set before the controller, one a thread (the tests play side by side).
@(thread_local)
advisor_game_context: advisor.Game_Context

advisor_set_context :: proc(game_context: advisor.Game_Context) { advisor_game_context = game_context }

// THE RUN: the depth of the node on the way to the boss; the Rest on a node the player can go to next.
advisor_context_run :: proc(run: ^game.Run_State) -> (game_context: advisor.Game_Context) {
	if run == nil { return }
	game_context.known = true
	nodes := run.route_map.nodes[:]
	deepest := 0
	for node in nodes { deepest = max(deepest, node.depth) }
	index := int(run.current_node)
	if index >= 0 && index < len(nodes) {
		current := nodes[index]
		if deepest > 0 { game_context.progress = f32(current.depth)/f32(deepest) }
		for next in current.outgoing[:current.outgoing_count] {
			if int(next) < 0 || int(next) >= len(nodes) { continue }
			percent := advisor_node(nodes[int(next)].kind).heal_percent
			game_context.heal_outside = max(game_context.heal_outside, run.player.stats.max_health*percent/100)
		}
	}
	return
}

// THE EXPEDITION: the groups beaten and the places done of all, the boss; the FONTE not yet used within reach and the
// backpack's Kit; the foes asleep on the map near the player.
advisor_context_expedition :: proc(w: ^world.World, bag: ^campaign.Backpack, room: ^game.Room) -> (game_context: advisor.Game_Context) {
	if w == nil || room == nil || room.player == nil { return }
	game_context.known = true
	p := room.player.position
	beaten, done := 0, 0
	for &g in w.groups[:w.group_count] {
		alive := false
		for m in g.members[:g.count] {
			if !m.alive { continue }
			alive = true
			game_context.remaining_foes += 0 if m.deployed else 1
			if m.deployed || world.distance(p, m.enemy.position) > ADVISOR_SLEEPER_REACH || game_context.sleeper_count == advisor.MAX_SLEEPERS { continue }
			// The expedition wakes a foe within 3 cells on grass, 6 elsewhere (world.sync).
			wake := 3 if world.ground(w, m.enemy.position) == .Grass else 6
			game_context.sleepers[game_context.sleeper_count] = {position = m.enemy.position, archetype = m.enemy.archetype, health = m.enemy.health, wake = wake}
			game_context.sleeper_count += 1
		}
		if !alive { beaten += 1 }
	}
	game_context.remaining_foes += len(room.enemies)
	for site in w.sites[:w.site_count] {
		if site.state == .Resolved { done += 1 }
		place := advisor_site(site.kind)
		if place.heal > 0 && site.state != .Resolved && world.distance(p, site.position) <= ADVISOR_HEAL_REACH {
			game_context.heal_outside = max(game_context.heal_outside, place.heal)
		}
	}
	if bag != nil {
		for entry in bag.grid.entries[:bag.grid.count] { game_context.heal_outside = max(game_context.heal_outside, advisor_item_heal(entry.item)) }
	}
	groups := f32(beaten)/f32(max(w.group_count, 1))
	sites := f32(done)/f32(max(w.site_count, 1))
	game_context.progress = 1 if w.boss_defeated else 0.5*groups+0.5*sites
	return
}

// THE LAB: F11 sets how near the end it is (0, 50 and 100%), the rest as the room has it.
advisor_context_lab :: proc(progress: f32) -> advisor.Game_Context {
	return {known = true, progress = progress}
}

// The context's few numbers that change an advice, as one (the pilot takes a new root when it changes).
@(private)
advisor_context_key :: proc(game_context: advisor.Game_Context) -> u64 {
	return u64(game_context.progress*100) | u64(u32(game_context.heal_outside)) << 8 | u64(game_context.sleeper_count) << 40 | u64(game_context.known) << 60
}
