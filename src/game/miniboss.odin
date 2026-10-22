package game

import grid "../engine/grid"

DEMOLITIONIST_ENRAGED_CHARGE_RANGE :: 6
DEMOLITIONIST_CHARGE_RECOVERY      :: 2
DEMOLITIONIST_MAX_APPROACH_PULSES  :: 2

@(private = "file")
demolitionist_phase_name :: proc(phase: i32) -> string {
	return "Overdrive" if phase >= 2 else "Demolition"
}

@(private)
update_demolitionist_phase :: proc(enemy: ^Enemy) {
	if enemy == nil || enemy.archetype != .Demolitionist {
		return
	}
	if enemy.boss_phase == 0 {
		enemy.boss_phase = 1
	}
	if enemy.boss_phase == 1 && enemy.health <= enemy.max_health/2 {
		enemy.boss_phase = 2
		enemy.boss_cycle = 0
		enemy.boss_approach_pulses = 0
	}
}

@(private)
plan_demolitionist_intent :: proc(
	room: ^Room, enemy: ^Enemy, origin: grid.Position,
	predicted_positions: ^[MAX_ENEMIES_PER_ROOM]grid.Position,
	enemy_count, ordered_index: int, reserved_bombs: []grid.Position,
) -> Enemy_Intent {
	if room.player.tactical.config.expedition {
		return plan_expedition_boss(room, enemy, origin, predicted_positions, enemy_count, ordered_index, reserved_bombs)
	}
	bomb_stages: u32 = 2 if enemy.boss_phase >= 2 else 1
	if enemy.boss_cycle < bomb_stages {
		return plan_tactical_bomber(room, enemy, origin, predicted_positions,
			enemy_count, ordered_index, reserved_bombs)
	}
	attacker := enemy^
	charge_range := BRUTE_MAX_CHARGE_RANGE
	if enemy.boss_phase >= 2 {
		attacker.attack += 1 if attacker.attack < max(i32) else 0
		charge_range = DEMOLITIONIST_ENRAGED_CHARGE_RANGE
	}
	return plan_brute_intent(room, &attacker, origin, predicted_positions,
		enemy_count, ordered_index, charge_range)
}

// Progress even interrupted attacks: the player earns the same recovery window
// when a committed charge is pushed aside or blocked.
@(private)
begin_demolitionist_offense :: proc(enemy: ^Enemy, kind: Enemy_Intent_Kind) {
	if enemy.archetype != .Demolitionist {
		return
	}
	stages: u32 = 3 if enemy.boss_phase >= 2 else 2
	enemy.boss_cycle = (enemy.boss_cycle+1)%stages
	enemy.boss_approach_pulses = 0
	if kind == .Charge || kind == .Attack {
		enemy.recovery_pulses = DEMOLITIONIST_CHARGE_RECOVERY
	} else if enemy.boss_phase >= 2 {
		enemy.recovery_pulses = 0
	} else {
		enemy.recovery_pulses = 1
	}
}

@(private)
begin_demolitionist_approach :: proc(enemy: ^Enemy) {
	if enemy.archetype != .Demolitionist {
		return
	}
	bomb_stages: u32 = 2 if enemy.boss_phase >= 2 else 1
	if enemy.boss_cycle < bomb_stages {
		return
	}
	enemy.boss_approach_pulses += 1
	if enemy.boss_approach_pulses >= DEMOLITIONIST_MAX_APPROACH_PULSES {
		// Telegraphing a charge must not turn into endless pursuit when the
		// player changes alignment or an object closes the only route.
		enemy.recovery_pulses = DEMOLITIONIST_CHARGE_RECOVERY
		enemy.boss_approach_pulses = 0
		enemy.boss_cycle = 0
	}
}
