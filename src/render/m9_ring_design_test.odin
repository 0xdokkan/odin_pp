package render

import "core:testing"
import fight "../fight"

@(test)
test_ring_guidance_follows_real_enemy_attack_windows :: proc(t: ^testing.T) {
	state := fight.begin()
	enemy := &state.fighters[1]
	enemy.action=.Heavy
	enemy.active_move=state.moves[.Heavy]
	enemy.action_tick=enemy.active_move.startup-1
	_,accent := m9_ring_hint(&state)
	testing.expect_value(t,accent,GOTHIC_RED)
	enemy.action_tick=enemy.active_move.startup
	_,accent=m9_ring_hint(&state)
	testing.expect_value(t,accent,GOTHIC_MUTED)
	enemy.action_tick=enemy.active_move.startup+enemy.active_move.active
	_,accent=m9_ring_hint(&state)
	testing.expect_value(t,accent,GOTHIC_BLUE)
	// Dodge recovery does not advertise the attack punish window.
	enemy.action=.Dodge
	_,accent=m9_ring_hint(&state)
	testing.expect_value(t,accent,GOTHIC_MUTED)
}

@(test)
test_ring_guidance_uses_four_held_throw_poses_and_result_precedence :: proc(t: ^testing.T) {
	state := fight.begin()
	state.throw_active=true
	expected := [4]string{"PRESA A DUE MANI","SOLLEVA","LANCIA","IMPATTO"}
	for label,i in expected {
		state.throw_tick=i*fight.THROW_POSE_TICKS
		text,_ := m9_ring_hint(&state)
		testing.expect_value(t,string(text),label)
	}
	state.result=.Won
	text,_ := m9_ring_hint(&state)
	testing.expect_value(t,string(text),"CAMPIONE SCONFITTO")
}
