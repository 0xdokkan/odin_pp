package combatdebug

import "core:testing"
import game "../game"
import level "../level"

@(test)
test_kiting_waits_instead_of_walking_into_an_ice_block :: proc(t: ^testing.T) {
	rows := [?]string{"######", "#.@.>#", "######"}
	level_data := debug_test_level(t, rows[:])
	defer level.destroy(&level_data)
	player := debug_test_player(t)
	enemies := [?]game.Enemy_Spawn{{position = {x = 3, y = 1}, health = 10, attack = 1}}
	objects := [?]game.Grid_Object_Spawn{{kind = .Ice_Block, position = {x = 1, y = 1}}}
	room, ok := game.create_room(&level_data, &player, {enemies = enemies[:], objects = objects[:]})
	testing.expect(t, ok)
	defer game.destroy_room(&room)
	decision := choose_max_distance_command(&room, nil)
	testing.expect(t, decision.valid)
	testing.expect_value(t, decision.kind, Command_Kind.Wait)
}

@(test)
test_kiting_accounts_for_entry_hazards_but_wait_does_not_retrigger_fire :: proc(t: ^testing.T) {
	rows := [?]string{"#######", "#.....#", "#..@..#", "#....>#", "#######"}
	level_data := debug_test_level(t, rows[:])
	defer level.destroy(&level_data)
	player := debug_test_player(t)
	enemies := [?]game.Enemy_Spawn{{position = {x = 4, y = 2}, health = 10, attack = 1}}
	objects := [?]game.Grid_Object_Spawn{{kind = .Fire, position = {x = 2, y = 2}}}
	traps := [?]game.Trap_Spawn{{position = {x = 3, y = 1}, damage = 5}}
	room, ok := game.create_room(&level_data, &player, {
		enemies = enemies[:], objects = objects[:], traps = traps[:],
	})
	testing.expect(t, ok)
	defer game.destroy_room(&room)
	decision := choose_max_distance_command(&room, nil)
	testing.expect(t, decision.valid)
	testing.expect_value(t, decision.kind, Command_Kind.Move)
	testing.expect_value(t, decision.direction, game.Move_Direction.South)
	player.position = {x = 2, y = 2}
	wait_score, valid := score_candidate(&room, player.position, .North, false, 4, nil)
	testing.expect(t, valid)
	testing.expect_value(t, wait_score.hazard_damage, i64(0))
}
