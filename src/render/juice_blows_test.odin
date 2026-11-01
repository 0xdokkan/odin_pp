package render

import "core:testing"
import game "../game"

@(private = "file")
Juice_Test_Board :: struct {
	player: game.Player,
	enemies: [1]game.Enemy,
	room: game.Room,
	snapshot: Room_Presentation,
	renderer: ^Renderer,
}

@(private = "file")
juice_test_board :: proc(b: ^Juice_Test_Board) {
	b.player = game.Player{position = {x = 2, y = 2}, health = 10, stats = {max_health = 10}}
	b.enemies = {{id = 1, archetype = .Chaser, position = {x = 3, y = 2}, health = 9, max_health = 9}}
	b.room = make_presentation_timeline_test_room(&b.player, b.enemies[:], nil)
	b.snapshot = capture_room_presentation(&b.room)
	b.renderer = attack_test_renderer(&b.snapshot)
	b.renderer.sprite_assets.elapsed = 10
}

@(private = "file")
juice_test_free :: proc(b: ^Juice_Test_Board) {
	attack_test_free(b.renderer)
	game.destroy_room(&b.room)
}

// One started cue at the timeline's head (and whatever follows it).
@(private = "file")
juice_test_cues :: proc(renderer: ^Renderer, cues: ..Presentation_Cue) {
	renderer.timeline.head, renderer.timeline.count = 0, len(cues)
	for cue, index in cues { renderer.timeline.cues[index] = cue }
	renderer.timeline.cues[0].started = true
}

// The player's bump: the plan's blow (pause, shake, kick, flash, sparks), once.
@(test)
test_the_players_bump_gives_its_juice_once :: proc(t: ^testing.T) {
	b: Juice_Test_Board
	juice_test_board(&b)
	defer juice_test_free(&b)
	foe := game.enemy_entity(1)
	blow := attack_test_blow(.Damaged, game.PLAYER_ENTITY, foe, b.player.position, b.enemies[0].position)
	juice_test_cues(b.renderer, {kind = .Damage, event = blow, duration = 0.2, batch = 1})
	observe_juice_blows(b.renderer)
	testing.expect(t, abs(b.renderer.juice.trauma-JUICE_BLOW.trauma) < 1e-6)
	testing.expect_value(t, b.renderer.juice.hold, JUICE_BLOW.hold)
	kick := juice_kick_offset(b.renderer, foe)
	testing.expect(t, abs(kick.x-JUICE_BLOW.kick) < 1e-5 && abs(kick.y) < 1e-5, "thrown back away from the player")
	testing.expect(t, juice_struck_flash(b.renderer, foe) > 0.99)
	testing.expect_value(t, b.renderer.tactical.juice_blows.blows, 1)
	// The same cue the next frame juices nothing more.
	observe_juice_blows(b.renderer)
	testing.expect_value(t, b.renderer.tactical.juice_blows.blows, 1)
	// The kick comes home and the flash fades.
	b.renderer.sprite_assets.elapsed += JUICE_KICK_SECONDS
	testing.expect_value(t, juice_kick_offset(b.renderer, foe), [2]f32{})
	testing.expect_value(t, juice_struck_flash(b.renderer, foe), f32(0))
}

// A critical: its stronger juice; a kill: the strongest, its card stays out.
@(test)
test_a_critical_and_a_kill_juice_harder :: proc(t: ^testing.T) {
	b: Juice_Test_Board
	juice_test_board(&b)
	defer juice_test_free(&b)
	foe := game.enemy_entity(1)
	blow := attack_test_blow(.Damaged, game.PLAYER_ENTITY, foe, b.player.position, b.enemies[0].position)
	blow.area_mask |= game.EVENT_CRITICAL_BIT
	juice_test_cues(b.renderer, {kind = .Damage, event = blow, duration = 0.2, batch = 1})
	observe_juice_blows(b.renderer)
	testing.expect(t, abs(b.renderer.juice.trauma-JUICE_CRITICAL.trauma) < 1e-6)
	testing.expect_value(t, b.renderer.juice.hold, JUICE_CRITICAL.hold)
	testing.expect_value(t, b.renderer.tactical.juice_blows.criticals, 1)
	// Another blow, its batch fells the foe.
	b.renderer.juice = {}
	b.renderer.tactical.juice_blows = {}
	blow.area_mask &~= game.EVENT_CRITICAL_BIT
	juice_test_cues(b.renderer, {kind = .Damage, event = blow, duration = 0.2, batch = 2},
		{kind = .Defeat, event = {kind = .Entity_Defeated, target = foe}, duration = 0.2, batch = 2})
	observe_juice_blows(b.renderer)
	testing.expect(t, abs(b.renderer.juice.trauma-JUICE_KILL.trauma) < 1e-6)
	testing.expect_value(t, b.renderer.juice.hold, JUICE_KILL.hold)
	testing.expect_value(t, b.renderer.tactical.juice_blows.kills, 1)
	b.renderer.sprite_assets.elapsed += 1
	testing.expect(t, juice_kick_offset(b.renderer, foe).x > JUICE_KILL.kick*0.99, "a kill's card stays thrown back")
}

// His cards only shake (the user's choice): no hit-stop, no kick.
@(test)
test_a_cards_damage_only_shakes :: proc(t: ^testing.T) {
	b: Juice_Test_Board
	juice_test_board(&b)
	defer juice_test_free(&b)
	foe := game.enemy_entity(1)
	juice_test_cues(b.renderer, {kind = .Damage, event = {kind = .Damaged, source = game.PLAYER_ENTITY, target = foe, amount = 3,
		card_definition = .Strike}, duration = 0.2, batch = 1})
	observe_juice_blows(b.renderer)
	testing.expect(t, abs(b.renderer.juice.trauma-JUICE_BLOW.trauma) < 1e-6)
	testing.expect_value(t, b.renderer.juice.hold, f32(0))
	testing.expect_value(t, juice_kick_offset(b.renderer, foe), [2]f32{})
	// Damage that runs with time (a status's) gives none.
	b.renderer.juice = {}
	juice_test_cues(b.renderer, {kind = .Damage, event = {kind = .Damaged, source = game.PLAYER_ENTITY, target = foe, amount = 1,
		has_status_cause = true}, duration = 0.2, batch = 2})
	observe_juice_blows(b.renderer)
	testing.expect_value(t, b.renderer.juice.trauma, f32(0))
}

// A foe's blow on the player: a shake and the red edge; one his guard takes:
// a lighter shake; an explosion: weaker the farther it is.
@(test)
test_a_foes_blow_a_guard_and_a_blast_shake_the_board :: proc(t: ^testing.T) {
	b: Juice_Test_Board
	juice_test_board(&b)
	defer juice_test_free(&b)
	foe := game.enemy_entity(1)
	hit := attack_test_blow(.Damaged, foe, game.PLAYER_ENTITY, b.enemies[0].position, b.player.position, amount = 4)
	juice_test_cues(b.renderer, {kind = .Damage, event = hit, duration = 0.2, batch = 1})
	observe_juice_blows(b.renderer)
	testing.expect(t, abs(b.renderer.juice.trauma-JUICE_HURT_TRAUMA) < 1e-6)
	testing.expect_value(t, b.renderer.juice.hold, f32(0))
	testing.expect(t, b.renderer.tactical.juice_blows.hurt > 0 && b.renderer.tactical.juice_blows.hurt_at == b.renderer.sprite_assets.elapsed)
	b.renderer.juice = {}
	guard := attack_test_blow(.Damage_Absorbed, foe, game.PLAYER_ENTITY, b.enemies[0].position, b.player.position)
	juice_test_cues(b.renderer, {kind = .Damage_Absorbed, event = guard, duration = 0.2, batch = 2})
	observe_juice_blows(b.renderer)
	testing.expect(t, abs(b.renderer.juice.trauma-JUICE_GUARD_TRAUMA) < 1e-6)
	b.renderer.juice = {}
	juice_test_cues(b.renderer, {kind = .Explosion, event = {kind = .Explosion, to_position = {x = 2, y = 2}}, duration = 0.2, batch = 3})
	observe_juice_blows(b.renderer)
	near := b.renderer.juice.trauma
	b.renderer.juice = {}
	juice_test_cues(b.renderer, {kind = .Explosion, event = {kind = .Explosion, to_position = {x = 10, y = 2}}, duration = 0.2, batch = 4})
	observe_juice_blows(b.renderer)
	testing.expect(t, abs(near-JUICE_BLAST_TRAUMA) < 1e-6 && b.renderer.juice.trauma < near*0.5)
}
