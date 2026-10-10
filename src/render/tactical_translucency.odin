package render

import "core:math"
import "core:slice"
import rl "vendor:raylib"
import rlgl "vendor:raylib/rlgl"
import game "../game"
import grid "../grid"
import view "../view"

Tactical_Alpha_Entry :: struct {
	kind: enum {Sprite, Wall},
	key: Sprite_Key,
	entity: game.Entity_Ref,
	position: view.Vec2,
	opacity, depth: f32,
}

// Retain the scratch capacity between frames and release it with the renderer.
Tactical_Alpha_Buffer :: struct {entries: [dynamic]Tactical_Alpha_Entry}

destroy_tactical_translucents :: proc(renderer: ^Renderer) {
	buffer := renderer.tactical.translucents
	if buffer == nil { return }
	delete(buffer.entries)
	free(buffer)
	renderer.tactical.translucents = nil
}

collect_tactical_translucents :: proc(renderer: ^Renderer, room: ^game.Room = nil) -> []Tactical_Alpha_Entry {
	v := &renderer.tactical
	if v.translucents == nil {
		v.translucents = new(Tactical_Alpha_Buffer)
		v.translucents.entries = make([dynamic]Tactical_Alpha_Entry, 0, 128)
	}
	entries := &v.translucents.entries
	clear(entries)
	// The board pass (it has a room) advances the standees' clips; the map
	// reuses them as they are.
	if room != nil { update_flipbook_actors(renderer, room) }
	snapshot := v.snapshot
	for actor in snapshot.enemies[:snapshot.enemy_count] {
		cell := grid.Position{int(math.round(actor.position.x)), int(math.round(actor.position.y))}
		if actor.visible && tactical_render_visible(renderer, cell) {
			key := sprite_key_for_enemy(actor.archetype)
			append(entries, Tactical_Alpha_Entry{key = key, entity = actor.entity, position = actor.position,
				opacity = flipbook_opacity(renderer, actor.entity, key, actor.position, actor.opacity)})
		}
	}
	if snapshot.player.visible {
		append(entries, Tactical_Alpha_Entry{key = .Player, entity = game.PLAYER_ENTITY, position = snapshot.player.position,
			opacity = flipbook_opacity(renderer, game.PLAYER_ENTITY, .Player, snapshot.player.position, snapshot.player.opacity)})
	}
	// Standees removed from the board mid-death finish toppling first.
	if v.flipbook_state != nil && v.flipbook.loaded {
		for &actor in v.flipbook_state.actors {
			cell := grid.Position{int(math.round(actor.position.x)), int(math.round(actor.position.y))}
			if !actor.used || !actor.ghost || !tactical_render_visible(renderer, cell) { continue }
			key := flipbook_key(actor.character)
			append(entries, Tactical_Alpha_Entry{key = key, entity = actor.entity, position = actor.position,
				opacity = flipbook_opacity(renderer, actor.entity, key, actor.position, 1)})
		}
	}
	// The hologram intentionally supplies no room: its own miniature walls
	// remain in the table pass, and it only needs sorted actor billboards.
	if room != nil {
		for y in 0..<room.level_data.tiles.height { for x in 0..<room.level_data.tiles.width {
			if tactical_cell_on_screen(renderer, {x, y}) && tactical_render_visible(renderer, {x, y}) && diorama_interior_wall(room, {x, y}) {
				append(entries, Tactical_Alpha_Entry{kind = .Wall, position = {f32(x), f32(y)}})
			}
		} }
	}
	forward := rl.Vector3Normalize(v.camera.target-v.camera.position)
	for &entry in entries^ {
		// View depth, not radial distance: objects off to the side must not
		// change order with a nearer object on the same projected sight line.
		center := rl.Vector3{entry.position.x+0.5, DIORAMA_WALL_HEIGHT*0.5, entry.position.y+0.5}
		entry.depth = rl.Vector3DotProduct(center-v.camera.position, forward)
	}
	slice.sort_by(entries^[:], proc(a, b: Tactical_Alpha_Entry) -> bool { return a.depth > b.depth })
	return entries^[:]
}

draw_tactical_billboards :: proc(renderer: ^Renderer, room: ^game.Room = nil, lights: [4]rl.Vector4 = {}) {
	entries := collect_tactical_translucents(renderer, room)
	// All upper wall layers share actor alpha ordering. Keeping their depth
	// writes disabled prevents an invisible wall surface masking the sprite.
	rlgl.DrawRenderBatchActive()
	rlgl.DisableDepthMask()
	defer { rlgl.DrawRenderBatchActive(); rlgl.EnableDepthMask() }
	walls_active := false
	for entry in entries {
		if entry.kind == .Wall {
			if !walls_active { begin_tactical_lighting(renderer, accents = lights); walls_active = true }
			draw_diorama_wall(renderer, room, {int(entry.position.x), int(entry.position.y)})
		} else {
			if walls_active { rl.EndShaderMode(); walls_active = false }
			tactical_billboard(renderer, entry.key, entry.position, entry.opacity, entry.entity)
		}
	}
	if walls_active { rl.EndShaderMode() }
}
