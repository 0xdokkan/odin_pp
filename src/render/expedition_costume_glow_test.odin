package render

import "core:testing"
import rl "vendor:raylib"
import game "../game"

@(test)
test_expedition_costume_glow_uses_the_existing_intent_clock_and_fade :: proc(t: ^testing.T) {
	r := new(Renderer)
	defer free(r)
	player: game.Player
	room := game.Room{player = &player, phase = .Combat}
	defer delete(room.enemies)
	append(&room.enemies, game.Enemy{id = 7, health = 10, archetype = .Chaser, intent = {kind = .Attack}})
	entity := game.enemy_entity(7)
	for kind in ([4]game.Enemy_Intent_Kind{.Attack, .Charge, .Protect, .Bombard}) {
		room.enemies[0].intent.kind = kind
		color, _ := foe_glow_color(kind)
		for left in ([3]f32{3, 1.5, .25}) {
			player.tactical.clock_fraction = .375
			room.enemies[0].tactical_cooldown = left+player.tactical.clock_fraction
			update_foe_glows(r, &room)
			amount := foe_glow_amount(left, game.tactical_enemy_intent_seconds(&room.enemies[0]))
			print_tint, paper_tint := expedition_costume_glow_tints(r, entity)
			testing.expect_value(t, print_tint, foe_glow_mix(rl.WHITE, color, amount*.6))
			testing.expect_value(t, paper_tint, foe_glow_mix(rl.WHITE, color, amount*.5))
			// Cosmetic time alone must not advance an active attack's warning.
			r.sprite_assets.elapsed += 1
			update_foe_glows(r, &room)
			still_print, still_paper := expedition_costume_glow_tints(r, entity)
			testing.expect_value(t, still_print, print_tint)
			testing.expect_value(t, still_paper, paper_tint)
		}
	}
	room.enemies[0].intent.kind = .Recover
	r.sprite_assets.elapsed += f64(FOE_GLOW_FADE)*.5
	update_foe_glows(r, &room)
	_, amount := foe_glow(r, entity)
	testing.expect(t, amount > .49 && amount < .51, "The wardrobe shares the existing fade after the action")
	r.sprite_assets.elapsed += f64(FOE_GLOW_FADE)
	update_foe_glows(r, &room)
	print_tint, paper_tint := expedition_costume_glow_tints(r, entity)
	testing.expect_value(t, print_tint, rl.WHITE)
	testing.expect_value(t, paper_tint, rl.WHITE)
	print_tint, paper_tint = expedition_costume_glow_tints(r, game.enemy_entity(99))
	testing.expect_value(t, print_tint, rl.WHITE)
	testing.expect_value(t, paper_tint, rl.WHITE)
}

@(test)
test_expedition_costume_tint_keeps_ink_alpha_and_idle_palette :: proc(t: ^testing.T) {
	for color in ([4]rl.Color{EXPEDITION_PAPER_EDGE, EXPEDITION_PAPER_INK, {65, 140, 190, 230}, {244, 62, 55, 255}}) {
		testing.expect_value(t, expedition_paper_tint(color, rl.WHITE), color)
		for glow in ([2]rl.Color{FOE_GLOW_RED, FOE_GLOW_PURPLE}) {
			tint := foe_glow_mix(rl.WHITE, glow, .6)
			shown := expedition_paper_tint(color, tint)
			testing.expect_value(t, shown.a, color.a)
			if color == EXPEDITION_PAPER_INK { testing.expect_value(t, shown, color) }
			else { testing.expect(t, shown != color, "Printed wardrobe must retain the warning instead of covering it with idle pigment") }
		}
	}
}
