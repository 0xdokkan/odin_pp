package render

import "core:testing"
import game "../game"
import level "../level"

@(test)
test_board_device_card_casts_replay_launch_impact_and_spawn_without_failures :: proc(t: ^testing.T) {
	for id in ([2]game.Card_Id{.Tesla_Coil,.Shock_Floor}) {
		data := create_encounter_presentation_test_level(t)
		defer level.destroy(&data)
		player := spell_presentation_player(t,id)
		testing.expect(t,game.configure_tactical(&player,game.DEFAULT_TACTICAL_CONFIG))
		enemies := [?]game.Enemy_Spawn{{position={6,3},health=20,attack=1}}
		room,created := game.create_room(&data,&player,{enemies=enemies[:]})
		testing.expect(t,created)
		defer game.destroy_room(&room)
		before := capture_room_presentation(&room)
		played := game.play_card(&room,player.deck.hand[0].id,game.cell_target({3,1}))
		testing.expect(t,game.card_play_was_committed(played.result))
		after := capture_room_presentation(&room)
		timeline := new(Presentation_Timeline)
		defer free(timeline)
		testing.expect(t,begin_event_timeline(timeline,before,room.recent_events,&after))
		launched,impacted,spawned,rolled := 0,0,0,0
		for cue in timeline.cues[:timeline.count] {
			if cue.kind == .Spell_Launched {launched+=1}
			if cue.kind == .Spell_Impact {impacted+=1}
			if cue.kind == .Object_Spawned {spawned+=1}
			if cue.kind == .Dice_Rolled {rolled+=1}
		}
		testing.expect_value(t,launched,1)
		testing.expect_value(t,impacted,1)
		testing.expect_value(t,spawned,1)
		testing.expect_value(t,rolled,1 if id == .Shock_Floor else 0)
		testing.expect(t,update_event_timeline(timeline,1000))
		testing.expect_value(t,timeline.update_failures,0)
		testing.expect_value(t,timeline.dropped_count,0)
		testing.expect_value(t,timeline.view.object_count,1)
		testing.expect_value(t,timeline.view.objects[0].kind,room.objects[0].kind)
		testing.expect_value(t,timeline.view.objects[0].position,presentation_position(room.objects[0].position))
		testing.expect(t,timeline.view.objects[0].visible)
	}
}

@(test)
test_tesla_activation_replays_walls_or_consumes_four_field_models_after_damage :: proc(t: ^testing.T) {
	for count in ([2]int{2,4}) {
		data := create_encounter_presentation_test_level(t)
		defer level.destroy(&data)
		player := spell_presentation_player(t,.Tesla_Coil)
		testing.expect(t,game.configure_tactical(&player,game.DEFAULT_TACTICAL_CONFIG))
		enemies := [?]game.Enemy_Spawn{{position={4,1},health=20,attack=1}}
		room,created := game.create_room(&data,&player,{enemies=enemies[:]})
		testing.expect(t,created)
		defer game.destroy_room(&room)
		positions := [4][2]int{{2,1},{6,1},{6,4},{2,4}}
		for point in positions[:count] {
			testing.expect(t,game.deploy_board_device(&room,.Tesla_Coil,{point[0],point[1]},8,0,room.recent_events))
		}
		before := capture_room_presentation(&room)
		testing.expect(t,game.activate_board_devices(&room))
		testing.expect(t,room.enemies[0].health<20)
		after := capture_room_presentation(&room)
		timeline := new(Presentation_Timeline)
		defer free(timeline)
		testing.expect(t,begin_event_timeline(timeline,before,room.recent_events,&after))
		defeated := 0
		for cue in timeline.cues[:timeline.count] {
			if cue.kind == .Defeat && cue.event.target.kind == .Object {defeated+=1}
		}
		testing.expect_value(t,defeated,4 if count == 4 else 0)
		testing.expect(t,update_event_timeline(timeline,1000))
		testing.expect_value(t,timeline.update_failures,0)
		testing.expect_value(t,timeline.dropped_count,0)
		testing.expect_value(t,timeline.view.enemies[0].health,room.enemies[0].health)
		visible := 0
		for object in timeline.view.objects[:timeline.view.object_count] {if object.visible {visible+=1}}
		testing.expect_value(t,visible,0 if count == 4 else 2)
		testing.expect_value(t,game.board_tesla_count(&room),visible)
	}
}
