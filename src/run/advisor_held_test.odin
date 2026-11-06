package run

import "core:testing"
import advisor "../advisor"
import game "../game"
import level "../level"

@(test)
test_advisor_held_policy_drops_illegal_card_before_a_replacement_is_ready :: proc(t: ^testing.T) {
	rows := [?]string{"#########", "#.......#", "#.......#", "#.......#", "#..@#...#", "#......>#", "#########"}
	data, err, _ := level.from_ascii(rows[:])
	if !testing.expect_value(t, err, .None) { return }
	defer level.destroy(&data)
	player, created := game.create_player({max_health = 20, attack = 1})
	if !testing.expect(t, created) { return }
	testing.expect(t, game.initialize_empty_deck(&player.deck, {hand_size = 1, max_energy = 3, energy_regen_per_pulse = 1}, 99))
	_, added := game.add_owned_card(&player.deck, .Arc_Bolt)
	testing.expect(t, added)
	config := game.EXPEDITION_TACTICAL_CONFIG
	config.vision_size = 0
	testing.expect(t, game.configure_tactical(&player, config))
	foes := [?]game.Enemy_Spawn{
		{position = {x = 3, y = 1}, health = 2, attack = 1},
		{position = {x = 5, y = 4}, health = 2, attack = 1},
	}
	room, built := game.create_room(&data, &player, {enemies = foes[:]})
	if !testing.expect(t, built) { return }
	defer game.destroy_room(&room)
	for &enemy in room.enemies { enemy.recovery_pulses, enemy.intent, enemy.tactical_cooldown = 99, {}, 0 }
	game.plan_enemy_intents(&room)
	search := new(advisor.Search)
	defer free(search)
	if !testing.expect(t, advisor.search_init(search)) { return }
	defer advisor.search_destroy(search)
	chosen := advisor.search_whole(search, &room, 4000)
	if !testing.expect(t, chosen.valid && chosen.kind == .Card) { return }
	index, found := game.enemy_index_by_id(&room, chosen.move.target.entity.id)
	if !testing.expect(t, found) { return }
	// A genuine search result enters the same hold policy as a worker packet;
	// no thread timing or synthetic advice is needed to withhold its replacement.
	pilot: Advisor_Pilot
	advisor_update_held(&pilot, &room, chosen)
	testing.expect_value(t, pilot.shown, chosen)
	game.tactical_tick(&room, .125, true, false)
	advisor_update_held(&pilot, &room, {})
	testing.expect_value(t, pilot.shown, chosen)
	room.enemies[index].position = {x = 3, y = 2}
	advisor_update_held(&pilot, &room, {})
	testing.expect_value(t, pilot.shown, chosen)
	testing.expect_value(t, advisor_view(&room, pilot.shown).cell, room.enemies[index].position)
	room.enemies[index].position = {x = 6, y = 4}
	advisor_update_held(&pilot, &room, {})
	testing.expect(t, !pilot.shown.valid)
	// Once ready, the new real root can replace it normally.
	fresh := advisor.search_whole(search, &room, 4000)
	if !testing.expect(t, fresh.valid) { return }
	advisor_update_held(&pilot, &room, fresh)
	testing.expect_value(t, pilot.shown, fresh)
}
