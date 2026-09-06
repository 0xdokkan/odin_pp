package render

import "core:testing"
import game "../game"
import grid "../grid"
import level "../level"
import view "../view"

Object_Interaction_Test_Scene :: struct {
	data: level.Level,
	player: game.Player,
	room: game.Room,
	renderer: Renderer,
	shove: game.Card_Instance,
}

init_object_interaction_test_scene :: proc(t: ^testing.T, scene: ^Object_Interaction_Test_Scene) {
	rows := [?]string{"#########", "#.......#", "#@......#", "#.......#", "#......>#", "#########"}
	err: level.Parse_Error
	scene.data, err, _ = level.from_ascii(rows[:])
	testing.expect_value(t, err, level.Parse_Error.None)
	ok: bool
	scene.player, ok = game.create_player({max_health = 20, attack = 2})
	testing.expect(t, ok)
	enemies := [?]game.Enemy_Spawn{{position = {7, 3}, health = 20, attack = 1, archetype = .Archer}}
	objects := [?]game.Grid_Object_Spawn{{kind = .Barrel, position = {2, 2}}}
	scene.room, ok = game.create_room(&scene.data, &scene.player, {enemies = enemies[:], objects = objects[:]})
	testing.expect(t, ok)
	scene.shove, ok = game.create_temporary_card(&scene.player.deck, .Shove)
	testing.expect(t, ok)
	scene.renderer = Renderer{
		projection = {tile_width = 64, tile_height = 32},
		camera = view.make_camera({420, 150}),
		canvas_width = 960,
		canvas_height = 540,
	}
}

destroy_object_interaction_test_scene :: proc(scene: ^Object_Interaction_Test_Scene) {
	game.destroy_room(&scene.room)
	level.destroy(&scene.data)
}

@(test)
test_barrel_body_click_targets_its_cell_across_camera_zoom_and_pan :: proc(t: ^testing.T) {
	scene: Object_Interaction_Test_Scene
	init_object_interaction_test_scene(t, &scene)
	defer destroy_object_interaction_test_scene(&scene)
	barrel := scene.room.objects[0]
	zooms := [?]f32{0.35, 1, 2.4}
	for zoom in zooms {
		scene.renderer.camera.zoom = zoom
		scene.renderer.camera.origin = {380+zoom*15, 90+zoom*10}
		center := cell_center(&scene.renderer, barrel.position)
		point := view.Vec2{center.x, center.y-max(f32(8), 12*zoom)*1.5}
		floor := view.canvas_to_cell(&scene.renderer.camera, &scene.renderer.projection, point)
		testing.expect(t, floor != barrel.position)
		index, found := grid_object_at_canvas_point(&scene.renderer, &scene.room, point)
		testing.expect(t, found)
		testing.expect_value(t, scene.room.objects[index].id, barrel.id)
		anchor := object_aware_card_target_cell(&scene.renderer, &scene.room, scene.shove, point, floor)
		testing.expect_value(t, anchor, barrel.position)
		target, valid := game.card_drop_target(&scene.room, scene.shove, anchor)
		testing.expect(t, valid)
		testing.expect_value(t, target, game.entity_target(game.object_entity(barrel.id)))
	}
}

@(test)
test_object_picking_keeps_aoe_dash_and_opponent_only_card_geometry :: proc(t: ^testing.T) {
	scene: Object_Interaction_Test_Scene
	init_object_interaction_test_scene(t, &scene)
	defer destroy_object_interaction_test_scene(&scene)
	center := cell_center(&scene.renderer, scene.room.objects[0].position)
	point := view.Vec2{center.x, center.y-18}
	floor := view.canvas_to_cell(&scene.renderer.camera, &scene.renderer.projection, point)
	definitions := [?]game.Card_Id{.Firebomb, .Cross_Slash, .Dash, .Spark, .Venom_Needle}
	for definition in definitions {
		card := game.Card_Instance{id = 100, definition_id = definition}
		anchor := object_aware_card_target_cell(&scene.renderer, &scene.room, card, point, floor)
		testing.expect_value(t, anchor, floor)
	}
	update_object_target_hover(&scene.renderer, &scene.room, point, scene.shove.id)
	testing.expect_value(t, scene.renderer.hovered_cell, scene.room.objects[0].position)
	update_object_target_hover(&scene.renderer, &scene.room, point, 0)
	testing.expect_value(t, scene.renderer.hovered_cell, floor)
}

@(test)
test_bomb_under_enemy_does_not_steal_actor_targeting :: proc(t: ^testing.T) {
	scene: Object_Interaction_Test_Scene
	init_object_interaction_test_scene(t, &scene)
	defer destroy_object_interaction_test_scene(&scene)
	scene.room.enemies[0].position = {2, 2}
	scene.room.objects[0].kind = .Bomb
	center := cell_center(&scene.renderer, scene.room.enemies[0].position)
	_, hit := grid_object_at_canvas_point(&scene.renderer, &scene.room, center)
	testing.expect(t, !hit)
	anchor := object_aware_card_target_cell(&scene.renderer, &scene.room, scene.shove, center, {2, 2})
	target, valid := game.card_drop_target(&scene.room, scene.shove, anchor)
	testing.expect(t, valid)
	testing.expect_value(t, target, game.entity_target(game.enemy_entity(scene.room.enemies[0].id)))
	opponent_only := game.Card_Instance{id = 101, definition_id = .Spark, lifetime = .Combat}
	opponent_anchor := object_aware_card_target_cell(&scene.renderer, &scene.room, opponent_only, center, {2, 2})
	opponent_target, opponent_valid := game.card_drop_target(&scene.room, opponent_only, opponent_anchor)
	testing.expect(t, opponent_valid)
	testing.expect_value(t, opponent_target, target)
	hint, found := object_shove_hint(&scene.room, scene.room.objects[0].id, scene.shove.id)
	testing.expect(t, found && !hint.targets_object && !hint.can_push)
}

@(test)
test_shove_help_reports_diagonal_range_and_blocked_landing_without_mutating :: proc(t: ^testing.T) {
	scene: Object_Interaction_Test_Scene
	init_object_interaction_test_scene(t, &scene)
	defer destroy_object_interaction_test_scene(&scene)
	barrel_id := scene.room.objects[0].id
	before := scene.player.deck
	hint, found := object_shove_hint(&scene.room, barrel_id, scene.shove.id)
	testing.expect(t, found && hint.shove_in_hand && hint.selected && hint.affordable && hint.can_push)
	testing.expect_value(t, hint.evaluation.movement.destination, grid.Position{3, 2})
	scene.player.position = {1, 1}
	hint, found = object_shove_hint(&scene.room, barrel_id, scene.shove.id)
	testing.expect(t, found && !hint.can_push)
	testing.expect_value(t, hint.distance, 2)
	testing.expect_value(t, hint.evaluation.error, game.Card_Compile_Error.Target_Out_Of_Range)
	scene.player.position = {1, 2}
	scene.room.enemies[0].position = {3, 2}
	hint, found = object_shove_hint(&scene.room, barrel_id, scene.shove.id)
	testing.expect(t, found && hint.targets_object && !hint.can_push)
	testing.expect_value(t, hint.evaluation.movement.error, game.Movement_Error.Actor_Blocker)
	// Damage remains legal when the push is blocked; the hint must not claim
	// that Shove is harmless or rejected in this situation.
	testing.expect_value(t, hint.evaluation.error, game.Card_Compile_Error.None)
	testing.expect_value(t, scene.player.deck, before)
	testing.expect_value(t, scene.room.objects[0].detonation_pulse, u64(0))
	scene.room.enemies[0].position = {7, 3}
	scene.room.objects[0].kind = .Ice_Block
	scene.room.objects[0].health = 1
	hint, found = object_shove_hint(&scene.room, barrel_id, scene.shove.id)
	testing.expect(t, found && hint.targets_object && hint.breaks_before_push && !hint.can_push)
}

@(test)
test_barrel_click_shove_ignites_even_when_the_landing_is_blocked :: proc(t: ^testing.T) {
	blocked_cases := [?]bool{false, true}
	for blocked in blocked_cases {
		scene: Object_Interaction_Test_Scene
		init_object_interaction_test_scene(t, &scene)
		defer destroy_object_interaction_test_scene(&scene)
		barrel_id := scene.room.objects[0].id
		if blocked {
			scene.room.enemies[0].position = {3, 2}
		}
		center := cell_center(&scene.renderer, scene.room.objects[0].position)
		point := view.Vec2{center.x, center.y-18}
		update_object_target_hover(&scene.renderer, &scene.room, point, scene.shove.id)
		target, valid := game.card_drop_target(&scene.room, scene.shove, scene.renderer.hovered_cell)
		testing.expect(t, valid)
		hint, found := object_shove_hint(&scene.room, barrel_id, scene.shove.id)
		testing.expect(t, found && hint.can_push == !blocked)
		play := game.play_card(&scene.room, scene.shove.id, target)
		testing.expect(t, game.card_play_was_committed(play.result))
		index, exists := game.object_index_by_id(&scene.room, barrel_id)
		testing.expect(t, exists)
		expected := grid.Position{2, 2} if blocked else grid.Position{3, 2}
		testing.expect_value(t, scene.room.objects[index].position, expected)
		testing.expect_value(t, scene.room.objects[index].detonation_pulse, u64(3))
		testing.expect_value(t, game.explosive_pulses_remaining(scene.room.objects[index].detonation_pulse, scene.room.pulse_count), 2)
	}
}

@(test)
test_picking_and_preview_allow_armed_barrel_push_without_resetting_fuse :: proc(t: ^testing.T) {
	scene: Object_Interaction_Test_Scene
	init_object_interaction_test_scene(t, &scene)
	defer destroy_object_interaction_test_scene(&scene)
	barrel_id := scene.room.objects[0].id
	events: game.Event_Log
	testing.expect(t, game.arm_explosive(&scene.room, barrel_id, game.PLAYER_ENTITY, &events))
	deadline := scene.room.objects[0].detonation_pulse
	hint, found := object_shove_hint(&scene.room, barrel_id, scene.shove.id)
	testing.expect(t, found && hint.can_push)
	testing.expect_value(t, hint.remaining_pulses, 2)
	center := cell_center(&scene.renderer, scene.room.objects[0].position)
	point := view.Vec2{center.x, center.y-18}
	update_object_target_hover(&scene.renderer, &scene.room, point, scene.shove.id)
	target, valid := game.card_drop_target(&scene.room, scene.shove, scene.renderer.hovered_cell)
	testing.expect(t, valid)
	play := game.play_card(&scene.room, scene.shove.id, target)
	testing.expect(t, game.card_play_was_committed(play.result))
	index, exists := game.object_index_by_id(&scene.room, barrel_id)
	testing.expect(t, exists)
	testing.expect_value(t, scene.room.objects[index].position, grid.Position{3, 2})
	testing.expect_value(t, scene.room.objects[index].detonation_pulse, deadline)
}

@(test)
test_ice_silhouette_and_bomb_circle_exclude_empty_bounding_box_corners :: proc(t: ^testing.T) {
	center := view.Vec2{200, 200}
	testing.expect(t, object_body_contains_point(.Ice_Block, center, {200, 170}, 1))
	testing.expect(t, !object_body_contains_point(.Ice_Block, center, {216, 170}, 1))
	testing.expect(t, object_body_contains_point(.Bomb, center, {200, 190}, 1))
	testing.expect(t, !object_body_contains_point(.Bomb, center, {211, 185}, 1))
	testing.expect(t, !object_body_contains_point(.Barrel, center, {213, 200}, 1))
}

@(test)
test_low_zoom_square_corners_and_boss_shoulders_target_actor_over_northern_barrel :: proc(t: ^testing.T) {
	scene: Object_Interaction_Test_Scene
	init_object_interaction_test_scene(t, &scene)
	defer destroy_object_interaction_test_scene(&scene)
	scene.renderer.camera.zoom = 0.35
	scene.room.enemies[0].position = {2, 2}
	scene.room.objects[0].position = {2, 1}
	center := cell_center(&scene.renderer, scene.room.enemies[0].position)
	barrel_center := cell_center(&scene.renderer, scene.room.objects[0].position)
	archetypes := [?]game.Enemy_Archetype{.Demolitionist, .Brute}
	bolt := game.Card_Instance{id = 101, definition_id = .Arc_Bolt}
	for archetype in archetypes {
		scene.room.enemies[0].archetype = archetype
		points := [2]view.Vec2{{center.x+10, center.y-10}, {center.x+14, center.y-8}}
		point_count := 2
		if archetype == .Brute {
			points[0] = {center.x+8, center.y-8}
			point_count = 1
		}
		for point in points[:point_count] {
			floor := view.canvas_to_cell(&scene.renderer.camera, &scene.renderer.projection, point)
			// Both the old circle test and a veto followed by floor targeting
			// fail here: this visible actor fragment projects onto the barrel.
			testing.expect_value(t, floor, scene.room.objects[0].position)
			testing.expect(t, !body_circle_contains_point(center, point, enemy_draw_radius(&scene.renderer, scene.room.enemies[0])))
			testing.expect(t, object_body_contains_point(.Barrel, barrel_center, point, scene.renderer.camera.zoom))
			_, hit_object := grid_object_at_canvas_point(&scene.renderer, &scene.room, point)
			testing.expect(t, !hit_object)
			cards := [?]game.Card_Instance{scene.shove, bolt}
			for card in cards {
				anchor := object_aware_card_target_cell(&scene.renderer, &scene.room, card, point, floor)
				testing.expect_value(t, anchor, scene.room.enemies[0].position)
				target, valid := game.card_drop_target(&scene.room, card, anchor)
				testing.expect(t, valid)
				testing.expect_value(t, target, game.entity_target(game.enemy_entity(scene.room.enemies[0].id)))
			}
			floor_cards := [?]game.Card_Id{.Firebomb, .Dash, .Cross_Slash}
			for definition in floor_cards {
				card := game.Card_Instance{id = 102, definition_id = definition}
				testing.expect_value(t, object_aware_card_target_cell(&scene.renderer, &scene.room, card, point, floor), floor)
			}
		}
	}
	// A circular Chaser has no square corner. The same exposed barrel remains
	// pickable there; expanding every enemy's hit box would incorrectly hide it.
	scene.room.enemies[0].archetype = .Chaser
	point := view.Vec2{center.x+6, center.y-6}
	floor := view.canvas_to_cell(&scene.renderer.camera, &scene.renderer.projection, point)
	index, object_found := grid_object_at_canvas_point(&scene.renderer, &scene.room, point)
	testing.expect(t, object_found)
	testing.expect_value(t, scene.room.objects[index].id, scene.room.objects[0].id)
	anchor := object_aware_card_target_cell(&scene.renderer, &scene.room, bolt, point, floor)
	target, valid := game.card_drop_target(&scene.room, bolt, anchor)
	testing.expect(t, valid)
	testing.expect_value(t, target, game.entity_target(game.object_entity(scene.room.objects[0].id)))
}
