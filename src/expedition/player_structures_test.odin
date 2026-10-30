package expedition

import "core:slice"
import "core:testing"
import campaign "../campaign"
import game "../game"
import grid "../engine/grid"
import level "../level"

// A place where the player can stand and set `id` down: the first one a scan of the map finds, with the origin that works.
@(private = "file")
find_spot :: proc(w: ^World, data: ^level.Level, room: ^game.Room, id: level.Structure_Id, skip := 0) -> (stand, origin: grid.Position, found: bool) {
	seen := 0
	for y := 12; y < data.tiles.height-12; y += 3 {
		for x := 12; x < data.tiles.width-12; x += 3 {
			room.player.position = {x = x, y = y}
			tile, _ := level.tile_at(data, room.player.position)
			if tile.kind != .Floor { continue }
			for dy in -5..=5 {
				for dx in -5..=5 {
					at := grid.Position{x = x+dx, y = y+dy}
					candidate := structure_origin_for(id, 0, false, at)
					if result, _ := check_player_structure(w, data, room, id, candidate, 0, false); result == .Ok {
						if seen == skip { return {x = x, y = y}, candidate, true }
						seen += 1
						break
					}
				}
			}
		}
	}
	return
}

@(private = "file")
player_world :: proc(t: ^testing.T, w: ^World, data: ^level.Level, p: ^game.Player, biome := campaign.Biome.Egypt) -> game.Room {
	room := test_world(t, w, data, p, biome)
	game.end_expedition_encounter(&room)
	room.phase = .Loot
	return room
}

// A structure is set down with the health its kind has, written on the map and in the world's list; a building has none.
@(test)
test_the_player_sets_a_structure_down_with_its_health_and_it_is_recorded :: proc(t: ^testing.T) {
	w: World
	data: level.Level
	p: game.Player
	room := player_world(t, &w, &data, &p)
	defer level.destroy(&data)
	defer game.destroy_room(&room)
	for id in ([?]level.Structure_Id{.Cart, .Temple, .Pen}) {
		stand, origin, found := find_spot(&w, &data, &room, id, int(id))
		testing.expectf(t, found, "no place for a %v", id)
		if !found { continue }
		room.player.position = stand
		before := w.structure_count
		result, err := place_player_structure(&w, &data, &room, id, origin, 0, false)
		testing.expect_value(t, result, Player_Placement.Ok)
		testing.expect_value(t, err, level.Placement_Error.None)
		testing.expect_value(t, w.structure_count, before+1)
		_, at := level.structure_index_at(&data, origin)
		testing.expect(t, at || id == .Pen, "the footprint is on the map")
		last := data.structures[len(data.structures)-1]
		testing.expect_value(t, last.id, id)
		testing.expect_value(t, last.health, level.structure_max_health(id))
		testing.expect_value(t, w.structures[w.structure_count-1], last)
	}
	testing.expect_value(t, w.placed_by_player, 3)
}

// Only three in an expedition; none in a fight or in a cave; not far away, nor on the player or on someone; each with its reason.
@(test)
test_the_player_structures_have_limits_and_every_refusal_says_why :: proc(t: ^testing.T) {
	w: World
	data: level.Level
	p: game.Player
	room := player_world(t, &w, &data, &p)
	defer level.destroy(&data)
	defer game.destroy_room(&room)
	stand, origin, found := find_spot(&w, &data, &room, .Cart)
	testing.expect(t, found)
	room.player.position = stand
	// Far away.
	far, _ := check_player_structure(&w, &data, &room, .Cart, grid.offset(origin, PLAYER_STRUCTURE_REACH+6, 0), 0, false)
	testing.expect_value(t, far, Player_Placement.Too_Far)
	// On the player.
	on_player, _ := check_player_structure(&w, &data, &room, .Cart, structure_origin_for(.Cart, 0, false, stand), 0, false)
	testing.expect(t, on_player == .On_The_Player || on_player == .Not_Allowed, "not on the player")
	// On a foe.
	_ = game.begin_expedition_encounter(&room)
	_, spawned := game.spawn_enemy(&room, {position = grid.offset(origin, 1, 0), health = 3, attack = 1, archetype = .Chaser})
	testing.expect(t, spawned)
	in_fight, _ := check_player_structure(&w, &data, &room, .Cart, origin, 0, false)
	testing.expect_value(t, in_fight, Player_Placement.Not_Exploring)
	clear(&room.enemies)
	game.end_expedition_encounter(&room)
	room.phase = .Loot
	// On a drop.
	testing.expect(t, add_drop(&w, {x = origin.x, y = origin.y}, campaign.make_item(.Credits, 5)))
	occupied, _ := check_player_structure(&w, &data, &room, .Cart, origin, 0, false)
	testing.expect_value(t, occupied, Player_Placement.Occupied)
	w.drop_count -= 1
	// In a cave, under the rock.
	standing := room.player.position
	room.player.position = w.caves[0].place.arrival
	in_cave, _ := check_player_structure(&w, &data, &room, .Cart, origin, 0, false)
	testing.expect_value(t, in_cave, Player_Placement.In_Cave)
	room.player.position = standing
	// A text for every refusal; only the allowed one is silent.
	for result in Player_Placement {
		text := player_placement_text(result, .Not_Free)
		testing.expect(t, (result == .Ok) == (len(text) == 0))
	}
	// The limit.
	w.placed_by_player = MAX_PLAYER_STRUCTURES
	none_left, _ := check_player_structure(&w, &data, &room, .Cart, origin, 0, false)
	testing.expect_value(t, none_left, Player_Placement.No_More)
	w.placed_by_player = 0
	result, _ := place_player_structure(&w, &data, &room, .Cart, origin, 0, false)
	testing.expect_value(t, result, Player_Placement.Ok)
	// Not on top of what is already there.
	again, _ := check_player_structure(&w, &data, &room, .Cart, origin, 0, false)
	testing.expect_value(t, again, Player_Placement.Not_Allowed)
}

// The enemies break an object and the world's list follows: the checkpoint has what is on the map; and going into a cave leaves the
// structures standing (the cave is a layer of the same map).
@(test)
test_a_broken_structure_is_off_the_saved_list_and_a_cave_leaves_the_rest_standing :: proc(t: ^testing.T) {
	w: World
	data: level.Level
	p: game.Player
	room := player_world(t, &w, &data, &p)
	defer level.destroy(&data)
	defer game.destroy_room(&room)
	stand, origin, found := find_spot(&w, &data, &room, .Cart)
	testing.expect(t, found)
	room.player.position = stand
	result, _ := place_player_structure(&w, &data, &room, .Cart, origin, 0, false)
	testing.expect_value(t, result, Player_Placement.Ok)
	count := w.structure_count
	// In a cave the structures stay where they are, on the map and on the list.
	room.player.position = w.caves[0].place.arrival
	tick(&w, &room, 0.1)
	testing.expect_value(t, w.in_cave, 1)
	testing.expect_value(t, level.structure_count(&data), count)
	testing.expect_value(t, w.structure_count, count)
	room.player.position = stand
	// The enemies break it: the next checkpoint does not have it.
	cart := count-1
	cart_cell := data.structures[cart].origin
	testing.expect_value(t, game.strike_structures(&room, cart_cell, {cart_cell}, 99), 1)
	snapshot := new(Snapshot)
	defer free(snapshot)
	testing.expect(t, capture(&w, &room, snapshot))
	testing.expect_value(t, snapshot.world.structure_count, count-1)
	testing.expect_value(t, snapshot.world.placed_by_player, 1)
	// Restored, the map has the same structures as the list.
	w2: World
	data2: level.Level
	p2: game.Player
	room2: game.Room
	testing.expect(t, restore(snapshot, &w2, &data2, &p2, &room2))
	defer level.destroy(&data2)
	defer game.destroy_room(&room2)
	testing.expect_value(t, level.structure_count(&data2), count-1)
	testing.expect(t, slice.equal(data.tiles.cells[:], data2.tiles.cells[:]), "the tiles agree with the list")
}
