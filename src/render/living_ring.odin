package render

import "core:math"
import rl "vendor:raylib"
import rlgl "vendor:raylib/rlgl"
import gfx "../engine/gfx"
import game "../game"
import grid "../engine/grid"
import view "../engine/view"

// The action ring of a living board: a thin line with the shape of a living
// card's cut that closes in on the card and touches it the moment its owner
// acts. The player's ring beats the whole seconds of the critical tick in the
// gold of a critical action: wide just after a tick, on the card at the next;
// it runs with the clock, never with the animations. In the mechanics lab the
// enemies have rings too: one opens wide when its enemy arrives or commits to
// its next action and closes over that action's countdown, and its colour says
// what is coming.

// How wide the ring opens, against the card.
LIVING_RING_SPAN :: f32(1.6)
// Its line, in screen pixels.
LIVING_RING_WIDTH :: f32(1.6)
// The enemies' rings are off for now: the lab tries other ways to show an
// enemy's intent (intent_display.odin). The player's ring stays.
LIVING_ENEMY_RINGS :: false
// The share of a countdown over which a fresh ring fades in.
LIVING_RING_FADE :: f32(0.08)

Living_Ring_Kind :: enum u8 {
	None,
	Strike,  // a blow at arm's length: attack, shove, cleave, charge
	Ranged,  // from afar or over an area: aim, shot, bomb, lit barrel
	Move,
	Protect, // a shield for an ally
	Beat,    // the player's tick
}

// The board is a cold dark blue: warm hues stand out most against it, so the
// threats are red and orange. Green and violet sit next to blue and are kept
// light; red and green also differ in lightness, for colour-blind players.
// Gold is the player's alone (a critical action's colour).
@(private)
living_ring_color :: proc(kind: Living_Ring_Kind) -> rl.Color {
	switch kind {
	case .Strike: return {255, 66, 66, 255}
	case .Ranged: return {255, 150, 44, 255}
	case .Move: return {102, 232, 140, 255}
	case .Protect: return {196, 142, 255, 255}
	case .Beat: return TACTICAL_FEEDBACK_CRITICAL
	case .None:
	}
	return {}
}

// What an enemy's intent announces. Waiting and recovering announce nothing.
@(private)
living_ring_kind :: proc(enemy: ^game.Enemy) -> Living_Ring_Kind {
	intent := &enemy.intent
	switch intent.kind {
	case .Attack:
		if intent.windup || intent.target_object != 0 { return .Ranged }
		// A cleave reaches the cells beside the one in front: still at arm's length.
		for cell in intent.threatened_cells[:intent.threatened_cell_count] {
			if max(abs(cell.x-enemy.position.x), abs(cell.y-enemy.position.y)) > 1 { return .Ranged }
		}
		return .Strike
	case .Charge: return .Strike
	case .Bombard: return .Ranged
	case .Move: return .Move
	case .Protect: return .Protect
	case .None, .Wait, .Recover:
	}
	return .None
}

// 1 when the enemy has just committed to its action, 0 when it acts.
@(private)
living_ring_open :: proc(room: ^game.Room, enemy: ^game.Enemy) -> f32 {
	total := game.tactical_enemy_intent_seconds(enemy)
	if total <= 0 { return 0 }
	return clamp(game.tactical_enemy_seconds(room, enemy)/total, 0, 1)
}

// The share of the current second still to run, through the whole combat.
@(private)
living_beat_open :: proc(room: ^game.Room) -> (open: f32, on: bool) {
	if room.phase != .Combat { return }
	return clamp(1-room.player.tactical.clock_fraction, 0, 1), true
}

@(private)
draw_living_rings :: proc(renderer: ^Renderer, room: ^game.Room) {
	v := &renderer.tactical
	if room == nil || !v.living || !v.living_assets.loaded || v.living_assets.ring_shader.id == 0 ||
	   v.snapshot == nil || v.outline_mode == .Hologram { return }
	snapshot := v.snapshot
	// Over everything: a ring never hides behind the card in front.
	rlgl.DrawRenderBatchActive()
	rlgl.DisableDepthTest()
	defer { rlgl.DrawRenderBatchActive(); rlgl.EnableDepthTest() }
	// The enemies' rings are still a trial of the mechanics lab.
	for actor in snapshot.enemies[:snapshot.enemy_count if v.mechanics_lab && LIVING_ENEMY_RINGS else 0] {
		cell := grid.Position{x = int(math.round(actor.position.x)), y = int(math.round(actor.position.y))}
		if !actor.visible || actor.health <= 0 || !tactical_render_visible(renderer, cell) { continue }
		index, found := game.enemy_index_by_id(room, actor.entity.id)
		if !found { continue }
		enemy := &room.enemies[index]
		kind := living_ring_kind(enemy)
		if kind == .None || game.enemy_is_staggered(room, enemy) { continue }
		key := sprite_key_for_enemy(actor.archetype)
		character, ok := flipbook_character(key)
		if !ok { continue }
		draw_living_ring(renderer, character, key, actor.position, actor.entity, living_ring_open(room, enemy), living_ring_color(kind))
	}
	// In the shadow the card is under the floor: the pool's own beat ring
	// takes this one's place (draw_tactical_shadow_pool). Behind his eyes he
	// has no card to ring (the HUD's lamp keeps the beat: first_person.odin).
	if snapshot.player.visible && snapshot.player.health > 0 && !tactical_shadow_showing(renderer) && first_person_amount(renderer) <= 0 {
		if open, on := living_beat_open(room); on {
			draw_living_ring(renderer, .Pilgrim, .Player, snapshot.player.position, game.PLAYER_ENTITY, open, living_ring_color(.Beat))
		}
	}
}

@(private = "file")
draw_living_ring :: proc(renderer: ^Renderer, character: gfx.Flipbook_Character, key: Sprite_Key, position: view.Vec2,
	entity: game.Entity_Ref, open: f32, color: rl.Color) {
	assets := &renderer.tactical.living_assets
	if living_fall(living_find(renderer, entity, character), living_clock(renderer, entity)) > 0 { return }
	alpha := clamp((1-open)/LIVING_RING_FADE, 0, 1)
	if alpha <= 0 { return }
	quad := living_billboard_geometry(renderer, character, key, position, true, entity)
	points := quad.card_points
	center := (points[0]+points[1]+points[2]+points[3])*0.25
	scale := 1+(LIVING_RING_SPAN-1)*open
	uv := [4]rl.Vector2{{0, 0}, {0, 1}, {1, 1}, {1, 0}}
	width := LIVING_RING_WIDTH
	rl.SetShaderValue(assets.ring_shader, assets.ring_width_location, &width, .FLOAT)
	rl.BeginShaderMode(assets.ring_shader)
	rlgl.SetTexture(assets.papers[character].id)
	rlgl.Begin(rlgl.QUADS)
	rlgl.Color4ub(color.r, color.g, color.b, u8(f32(color.a)*alpha))
	for point, index in points {
		p := center+(point-center)*scale
		rlgl.TexCoord2f(uv[index].x, uv[index].y)
		rlgl.Vertex3f(p.x, p.y, p.z)
	}
	rlgl.End()
	rlgl.SetTexture(0)
	rl.EndShaderMode()
}
