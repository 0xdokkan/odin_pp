package game

import "core:encoding/json"
import "core:testing"
import "core:mem"
import level "../level"

// The view's weapon (docs/piano-prima-persona.md, Fase 1): the AK as ever, the
// others taken up with their own bytes, refused on a dinosaur's back, kept by a
// save under their own keys.

@(test)
test_first_person_weapon_rides_in_the_effect_and_the_state :: proc(t: ^testing.T) {
	data: level.Level
	player: Player
	spawns := [?]Enemy_Spawn{{position = {x = 2, y = 10}, health = 40, attack = 1}}
	room := first_person_test_room(t, &data, &player, spawns[:])
	defer level.destroy(&data)
	defer destroy_room(&room)
	lasso_test_hold(&room, room.enemies[0].id)
	// The AK's card and effect name no weapon: the first one.
	testing.expect_value(t, first_person_effect(20).charges, i32(0))
	definition, found := card_definition_by_id(.First_Person)
	testing.expect(t, found)
	testing.expect_value(t, definition.effects[0].charges, i32(0))
	for weapon in First_Person_Weapon {
		effect := first_person_effect(20, weapon)
		got, known := first_person_effect_weapon(effect.charges)
		testing.expect(t, known && got == weapon)
		testing.expect(t, effect_is_valid(&room, effect))
	}
	// No weapon past the last one, nor before the first.
	for charges in ([2]i32{-1, i32(max(First_Person_Weapon))+1}) {
		_, known := first_person_effect_weapon(charges)
		testing.expect(t, !known)
		testing.expect(t, !effect_is_valid(&room, {kind = .First_Person, target = PLAYER_ENTITY, amount = 20, charges = charges}))
	}
	// The effect takes it up; the event names its card.
	action := make_action(.Card, PLAYER_ENTITY, entity_target(PLAYER_ENTITY), .Self)
	testing.expect(t, add_effect(&action, first_person_effect(20, .Sword)))
	report := resolve_action(&room, &action)
	testing.expect(t, report.accepted && tactical_first_person_active(&room))
	testing.expect_value(t, room.first_person.weapon, First_Person_Weapon.Sword)
	testing.expect_value(t, room.first_person.duration, f32(20))
	begun := false
	for event in report.events.events[:report.events.count] {
		if event.kind == .First_Person_Begun { begun = event.card_definition == FIRST_PERSON_WEAPONS[.Sword].card }
	}
	testing.expect(t, begun)
}

@(test)
test_first_person_weapons_share_their_bytes :: proc(t: ^testing.T) {
	data: level.Level
	player: Player
	spawns := [?]Enemy_Spawn{{position = {x = 2, y = 10}, health = 40, attack = 1}}
	room := first_person_test_room(t, &data, &player, spawns[:])
	defer level.destroy(&data)
	defer destroy_room(&room)
	lasso_test_hold(&room, room.enemies[0].id)
	// Room stays under its budget (event_test): the weapons overlap.
	testing.expect(t, size_of(First_Person_Arms) == size_of(First_Person_AK))
	// The AK fires and ends: its trail and the room's counts stay.
	testing.expect(t, tactical_begin_first_person(&room, 2))
	testing.expect(t, first_person_test_fire(&room, 0.5, 1.0/60, FIRST_PERSON_TEST_NORTH) > 0)
	shots, hits := room.first_person.shots, room.first_person.hits
	tactical_first_person_tick(&room, 5)
	testing.expect(t, !tactical_first_person_active(&room))
	trail := room.first_person.trail
	testing.expect(t, trail[0].number == 1)
	// The AK again keeps its trail.
	testing.expect(t, tactical_begin_first_person(&room, 2))
	testing.expect(t, room.first_person.trail == trail)
	tactical_first_person_tick(&room, 5)
	// Another weapon starts clear, with the room's counts: the bow with its
	// own put in place as it is taken up (first_person_bow_begin: its arrows to
	// come and its zones), as the fists and the sword do theirs.
	testing.expect(t, tactical_begin_first_person(&room, 3, .Bow))
	testing.expect(t, room.first_person.weapon == .Bow && room.first_person.remaining == 3)
	testing.expect(t, room.first_person.shots == shots && room.first_person.hits == hits)
	fresh := room.first_person.bow
	testing.expect(t, fresh.loosed == 0 && !fresh.drawing && fresh.pending == 0)
	for arrow in fresh.arrows { testing.expect(t, arrow.state == .None) }
	// It has no trigger: the button touches nothing and nothing is ever due.
	first_person_set_trigger(&room, true)
	testing.expect(t, !room.first_person.trigger && !first_person_fire_due(&room))
	_, fired := first_person_fire(&room, FIRST_PERSON_TEST_NORTH)
	testing.expect(t, !fired && room.first_person.shots == shots)
	tactical_first_person_tick(&room, 1)
	testing.expect(t, room.first_person.bow.loosed == 0 && room.first_person.bow.pending > 0)
	// The end of the fight leaves its bytes alone.
	room.first_person.trail[0].number = 7
	room.phase = .Loot
	tactical_end_combat(&room)
	testing.expect(t, !room.first_person.active && room.first_person.trail[0].number == 7)
}

@(test)
test_first_person_only_the_ak_is_taken_up_riding :: proc(t: ^testing.T) {
	data: level.Level
	player: Player
	spawns := [?]Enemy_Spawn{{position = {x = 2, y = 10}, health = 40, attack = 1}}
	room := first_person_test_room(t, &data, &player, spawns[:])
	defer level.destroy(&data)
	defer destroy_room(&room)
	lasso_test_hold(&room, room.enemies[0].id)
	report: Action_Report
	testing.expect(t, begin_ride(&room, .Raptor, 10, &report))
	testing.expect(t, tactical_ride_active(&room))
	for weapon in First_Person_Weapon {
		testing.expect_value(t, tactical_can_begin_first_person(&room, weapon), weapon == .AK)
		testing.expect_value(t, effect_is_valid(&room, first_person_effect(20, weapon)), weapon == .AK)
	}
	testing.expect(t, !tactical_begin_first_person(&room, 20, .Bow))
	testing.expect(t, tactical_begin_first_person(&room, 20))
}

@(test)
test_first_person_save_keeps_each_weapon :: proc(t: ^testing.T) {
	// The AK: all of it, through JSON as a save writes it.
	ak: First_Person_State
	ak.active, ak.weapon, ak.remaining, ak.duration, ak.shots, ak.hits = true, .AK, 12.5, 20, 9, 4
	ak.cooldown, ak.trigger = -0.05, true
	ak.trail[0] = {number = 9, hit = .Foe, target = enemy_entity(3), cell = {x = 4, y = 2}, origin = {6.5, 1.05, 6.5},
		point = {4.5, 1, 2.9}, damage = 1}
	bytes, marshalled := json.marshal(first_person_save(ak), allocator = context.temp_allocator)
	testing.expect(t, marshalled == nil)
	read: First_Person_Save
	testing.expect(t, json.unmarshal(bytes, &read, allocator = context.temp_allocator) == nil)
	back, ok := first_person_load(read)
	testing.expect(t, ok && first_person_test_same(back, ak))
	// Another weapon: its own, and none of the AK's.
	fists := ak
	fists.weapon, fists.arms = .Fists, {}
	back, ok = first_person_load(first_person_save(fists))
	testing.expect(t, ok && first_person_test_same(back, fists))
	// A save from before the weapons has no `weapon`: the AK's.
	old := `{"active":true,"remaining":12.5,"duration":20,"cooldown":0.1,"trigger":false,"shots":9,"hits":4}`
	read = {}
	testing.expect(t, json.unmarshal(transmute([]u8)old, &read, allocator = context.temp_allocator) == nil)
	back, ok = first_person_load(read)
	testing.expect(t, ok && back.weapon == .AK && back.active && back.remaining == 12.5 && back.cooldown == f32(0.1) && back.shots == 9)
	// A weapon the game does not know is refused.
	read.weapon = First_Person_Weapon(9)
	_, ok = first_person_load(read)
	testing.expect(t, !ok)
}

// Byte for byte: a raw union has no ==.
@(private = "file")
first_person_test_same :: proc(a, b: $T) -> bool {
	a, b := a, b
	return mem.compare_ptrs(&a, &b, size_of(T)) == 0
}
