package game

Player_Ability :: enum {
	Guard,
	Toxic_Wave,
	Thorn_Coat,
	Afterimage,
}

use_player_ability :: proc(room: ^Room, ability: Player_Ability) -> Action_Result {
	if room == nil || room.player == nil || room.phase != .Combat {
		return .Invalid_Phase
	}
	if ability == .Toxic_Wave && len(room.enemies) > MAX_ACTION_EFFECTS {
		return .Invalid_Phase
	}
	clear_event_log(&room.recent_events)

	action: Action
	switch ability {
	case .Guard:
		action = make_action(.Ability, PLAYER_ENTITY, entity_target(PLAYER_ENTITY), .Self)
		added := add_effect(&action, apply_status_effect(PLAYER_ENTITY, .Shield, 3, 3))
		assert(added)
	case .Toxic_Wave:
		action = make_action(.Ability, PLAYER_ENTITY, {}, .None)
		for enemy in room.enemies {
			added := add_effect(&action, apply_status_effect(enemy_entity(enemy.id), .Poison, 1, 3))
			assert(added)
		}
	case .Thorn_Coat:
		action = make_action(.Ability, PLAYER_ENTITY, entity_target(PLAYER_ENTITY), .Self)
		added := add_effect(&action, apply_status_effect(PLAYER_ENTITY, .Thorns, 1, 3))
		assert(added)
	case .Afterimage:
		action = make_action(.Ability, PLAYER_ENTITY, entity_target(PLAYER_ENTITY), .Self)
		added := add_effect(&action, apply_status_effect(PLAYER_ENTITY, .Afterimage, 1, 4))
		assert(added)
	}

	report := resolve_action(room, &action)
	if !report.accepted {
		return .Invalid_Phase
	}
	append_event_log(&room.recent_events, &report.events)
	_, outcome := finish_player_combat_command(room)
	switch outcome {
	case .Player_Defeated:
		return .Player_Defeated
	case .Combat_Ended:
		return .Combat_Ended
	case .Combat_Continues:
	}
	return .Used_Ability
}
