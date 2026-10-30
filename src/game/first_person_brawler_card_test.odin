package game

import "core:testing"
import level "../level"

// FIRST PERSON BRAWLER, the card (docs/piano-prima-persona.md, Fase 2 passo 5):
// the AK's numbers, the fists as its weapon, lab only; played, it takes the
// fists up behind his eyes and names itself.
@(test)
test_first_person_brawler_is_the_fists_card :: proc(t: ^testing.T) {
	definition, found := card_definition_by_id(.First_Person_Brawler)
	testing.expect(t, found && validate_card_definition(&definition))
	ak, _ := card_definition_by_id(.First_Person)
	testing.expect(t, definition.rarity == ak.rarity && definition.cost == ak.cost && definition.time_cost == 0 && definition.targeting.rule == .Self)
	testing.expect(t, card_is_lab_only(.First_Person_Brawler) && !card_is_lab_only(.First_Person))
	effect := definition.effects[0]
	weapon, known := first_person_effect_weapon(effect.charges)
	testing.expect(t, effect.kind == .First_Person && known && weapon == .Fists)
	// Twenty seconds, +2 an upgrade, thirty at +5.
	for upgrade in i32(0)..=FIRST_PERSON_MAX_UPGRADE_LEVEL {
		made, ok := instantiate_card_effect(effect, PLAYER_ENTITY, {id = 1, definition_id = .First_Person_Brawler, upgrade_level = upgrade})
		testing.expect(t, ok && made.amount == FIRST_PERSON_SECONDS+FIRST_PERSON_SECONDS_PER_UPGRADE*upgrade && made.charges == i32(First_Person_Weapon.Fists))
	}
	testing.expect_value(t, FIRST_PERSON_WEAPONS[.Fists].card, Card_Id.First_Person_Brawler)
	testing.expect(t, card_is_first_person(.First_Person) && card_is_first_person(.First_Person_Brawler) && !card_is_first_person(.Strike))

	// Played on himself: the fists behind his eyes, the body at his cell's
	// centre, the cue naming this card.
	data: level.Level
	player: Player
	spawns := [?]Enemy_Spawn{{position = {x = 2, y = 10}, health = 40, attack = 1}}
	room := first_person_test_room(t, &data, &player, spawns[:])
	defer level.destroy(&data)
	defer destroy_room(&room)
	lasso_test_hold(&room, room.enemies[0].id)
	card := rework_hand_card(t, &room, .First_Person_Brawler)
	room.player.deck.energy = room.player.deck.rules.max_energy
	play := play_card(&room, card.id, entity_target(PLAYER_ENTITY))
	testing.expect_value(t, play.result, Card_Play_Result.Played)
	testing.expect(t, first_person_fists_active(&room) && room.first_person.duration == f32(FIRST_PERSON_SECONDS))
	testing.expect_value(t, room.first_person.fists.body, [2]f32{6.5, 6.5})
	named := false
	for event in room.recent_events.events[:room.recent_events.count] {
		if event.kind == .First_Person_Begun { named = event.card_definition == .First_Person_Brawler }
	}
	testing.expect(t, named, "the cue does not name First Person Brawler")
}
