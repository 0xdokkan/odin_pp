package game

import "core:testing"
import grid "../engine/grid"
import level "../level"

card_demo_test_inside :: proc(cell: grid.Position) -> bool {
	return cell.x > 0 && cell.y > 0 && cell.x < CARD_DEMO_WIDTH-1 && cell.y < CARD_DEMO_HEIGHT-1 &&
	       cell != CARD_DEMO_PLAYER && cell != CARD_DEMO_EXIT
}

// MOSTRA EFFETTO's scenes are rooms the game builds: at every level every
// cell a scene names is on the floor, never the player's or the exit's,
// nothing stands on another; the card's room is built with the card in hand
// (the rod in the deck), its dice show the faces asked, its foes are held but
// the free ones, and a card let go on its target there finds it a target as
// the hand's drop does (card_drop_target).
@(test)
test_card_demo_scenes_build_their_rooms :: proc(t: ^testing.T) {
	for id in Card_Id {
		if id == .Count { continue }
		for upgrade in i32(0)..=card_max_upgrade_level(id) {
			scene := card_demo_scene(id, upgrade)
			taken: [dynamic]grid.Position
			defer delete(taken)
			place :: proc(t: ^testing.T, taken: ^[dynamic]grid.Position, id: Card_Id, upgrade: i32, cell: grid.Position, what: string) {
				testing.expectf(t, card_demo_test_inside(cell), "%v +%d: the %s at %v is off the floor", id, upgrade, what, cell)
				for other in taken { testing.expectf(t, other != cell, "%v +%d: the %s at %v stands on something else", id, upgrade, what, cell) }
				append(taken, cell)
			}
			for foe in scene.foes[:scene.foe_count] { place(t, &taken, id, upgrade, foe.at, "foe") }
			for object in scene.objects[:scene.object_count] { place(t, &taken, id, upgrade, object.position, "object") }
			for coil in scene.coils[:scene.coil_count] { place(t, &taken, id, upgrade, coil, "coil") }
			for pool in scene.pools[:scene.pool_count] { place(t, &taken, id, upgrade, pool, "pool") }
			if scene.gesture != .Double_Click && scene.gesture != .Drag_To_Player {
				testing.expectf(t, card_demo_test_inside(scene.target), "%v +%d: its target %v is off the floor", id, upgrade, scene.target)
			}
			card := Card_Instance{id = 1, definition_id = id, upgrade_level = upgrade,
				lifetime = .Combat if card_definition_temporary(id) else .Permanent}
			dice: Dice_State
			if scene.faces != {} {
				found: bool
				dice, found = card_demo_dice(card, scene.faces, FISHING_HEAL_SIDES)
				testing.expectf(t, found, "%v +%d: no dice show %v", id, upgrade, scene.faces)
			}
			data: level.Level
			player: Player
			room: Room
			if !testing.expectf(t, create_card_demo_room(scene, card, dice, &data, &player, GAME_TACTICAL_CONFIG, &room), "%v +%d: no room", id, upgrade) {
				level.destroy(&data)
				continue
			}
			testing.expectf(t, room.player == &player && player.position == CARD_DEMO_PLAYER && room.phase == (.Loot if scene.cleared else .Combat),
				"%v +%d: the room is not the scene's", id, upgrade)
			testing.expectf(t, len(room.enemies) == scene.foe_count, "%v +%d: %d foes of %d", id, upgrade, len(room.enemies), scene.foe_count)
			for enemy, index in room.enemies {
				held := !scene.foes[index].free
				// A held foe only recovers, for longer than any take.
				testing.expectf(t, !held || (enemy.recovery_pulses > 100 && (enemy.intent.kind == .None || enemy.intent.kind == .Recover)),
					"%v +%d: foe %d is not held (%v)", id, upgrade, index, enemy.intent.kind)
			}
			held: Card_Instance
			if card_is_room_tool(id) {
				rod, found := fishing_rod(&player.deck)
				testing.expectf(t, found && rod.upgrade_level == upgrade && fishing_room_open(&room), "%v +%d: no rod to fish with", id, upgrade)
			} else {
				for in_hand in player.deck.hand[:player.deck.hand_count] { if in_hand.definition_id == id { held = in_hand } }
				testing.expectf(t, held.id != 0 && held.upgrade_level == upgrade, "%v +%d: not in hand", id, upgrade)
			}
			if held.id != 0 && scene.gesture != .Double_Click {
				cell := scene.target
				if scene.gesture == .Drag_To_Player { cell = player.position }
				_, aimed := card_drop_target(&room, held, cell)
				testing.expectf(t, aimed, "%v +%d: let go on %v it finds no target", id, upgrade, cell)
			}
			destroy_room(&room)
			level.destroy(&data)
		}
	}
}

// A default scene follows its card's targeting: what a foe card aims at
// stands at the player's right on the board's screen, a self card is clicked
// twice, an area card's foes stand inside its area.
@(test)
test_card_demo_default_scenes_follow_the_targeting :: proc(t: ^testing.T) {
	strike, _ := card_definition_by_id(.Strike)
	scene := card_demo_default_scene(strike)
	testing.expect(t, scene.gesture == .Drag_To_Foe && scene.foe_count == 1 && scene.foes[0].at == card_demo_offset(0, -1))
	bolt, _ := card_definition_by_id(.Arc_Bolt)
	scene = card_demo_default_scene(bolt)
	testing.expect(t, scene.gesture == .Drag_To_Foe && scene.foes[0].at == card_demo_offset(1, -1))
	guard, _ := card_definition_by_id(.Guard)
	scene = card_demo_default_scene(guard)
	testing.expect(t, scene.gesture == .Double_Click && scene.foe_count == 0)
	bomb, _ := card_definition_by_id(.Firebomb)
	scene = card_demo_default_scene(bomb)
	testing.expect(t, scene.gesture == .Drag_To_Cell && scene.foe_count == 2 && scene.object_count == 1 && scene.objects[0].kind == .Barrel)
	for foe in scene.foes[:scene.foe_count] {
		testing.expect(t, max(abs(foe.at.x-scene.target.x), abs(foe.at.y-scene.target.y)) <= bomb.targeting.radius)
	}
	ray, _ := card_definition_by_id(.Piercing_Ray)
	scene = card_demo_default_scene(ray)
	testing.expect(t, scene.gesture == .Drag_Along_Line && scene.foe_count == 2 && scene.target == card_demo_offset(3, -3))
	// A card with no target at all is clicked twice too; one that draws has
	// cards to draw; one that washes a status away finds it on the player.
	wave, _ := card_definition_by_id(.Toxic_Wave)
	scene = card_demo_default_scene(wave)
	testing.expect(t, scene.gesture == .Double_Click && scene.foe_count == 2)
	focus, _ := card_definition_by_id(.Battle_Focus)
	testing.expect(t, card_demo_default_scene(focus).filler_count > 0)
	purifying, _ := card_definition_by_id(.Purifying_Guard)
	scene = card_demo_default_scene(purifying)
	testing.expect(t, scene.player_status == .Poison && scene.player_stacks > 0)
}
