package render

import "core:math"
import "core:slice"
import rl "vendor:raylib"
import rlgl "vendor:raylib/rlgl"
import game "../game"
import grid "../engine/grid"
import level "../level"
import view "../engine/view"

Tactical_Alpha_Entry :: struct {
	kind: enum {Sprite, Wall, Roof, Attack, Ground, Lasso, Fishing, Pinball, First_Person, Dino, Cover},
	// An Attack entry: its blow's slot in Attack_Fx_State.
	attack: i32,
	// A Ground entry: its flame's cell, or past the cells its splash (ground_fx.odin).
	ground: i32,
	// A Lasso entry: a piece of its rope, a half of its loop or a hit's star (lasso.odin).
	lasso: i32,
	// A Fishing entry: the rod and its line, the bobber, or the catch (fishing.odin).
	fishing: Fishing_Piece,
	// A Pinball entry: the ball (0), or a contact's star (pinball.odin).
	pinball: i32,
	// A First_Person entry: a tracer in flight, or past them its spark (first_person.odin).
	first_person: i32,
	key: Sprite_Key,
	entity: game.Entity_Ref,
	position: view.Vec2,
	opacity, depth: f32,
}

// Retain the scratch capacity between frames and release it with the renderer.
Tactical_Alpha_Buffer :: struct {entries: [dynamic]Tactical_Alpha_Entry}

@(private)
destroy_tactical_translucents :: proc(renderer: ^Renderer) {
	buffer := renderer.tactical.translucents
	if buffer == nil { return }
	delete(buffer.entries)
	free(buffer)
	renderer.tactical.translucents = nil
}

@(private)
collect_tactical_translucents :: proc(renderer: ^Renderer, room: ^game.Room = nil) -> []Tactical_Alpha_Entry {
	v := &renderer.tactical
	if v.translucents == nil {
		v.translucents = new(Tactical_Alpha_Buffer)
		v.translucents.entries = make([dynamic]Tactical_Alpha_Entry, 0, 128)
	}
	entries := &v.translucents.entries
	clear(entries)
	// The board pass (it has a room) advances the standees' clips; the map
	// reuses them as they are. The blows first: a struck card's reaction
	// waits for its own. The ground was followed once this frame already, as
	// the board began (draw_tactical_world).
	if room != nil { observe_attack_cues(renderer) }
	if room != nil { update_flipbook_actors(renderer, room) }
	if room != nil && v.living { update_living_actors(renderer, room) }
	living := v.living && v.living_assets.loaded && v.living_state != nil
	snapshot := v.snapshot
	for actor in snapshot.enemies[:snapshot.enemy_count] {
		cell := grid.Position{x = int(math.round(actor.position.x)), y = int(math.round(actor.position.y))}
		// The Pinball's ball has taken its foe's card's place (pinball.odin).
		if actor.visible && tactical_render_visible(renderer, cell) && !tactical_pinball_holds(renderer, actor.entity) {
			key := sprite_key_for_enemy(actor.archetype)
			opacity := living_opacity(renderer, actor.entity, key, actor.opacity) if living else
				flipbook_opacity(renderer, actor.entity, key, actor.position, actor.opacity)
			opacity *= pinball_card_opacity(renderer, actor.entity)
			append(entries, Tactical_Alpha_Entry{key = key, entity = actor.entity, position = actor.position, opacity = opacity})
		}
	}
	// Behind his eyes the player's card fades as the camera reaches it.
	if snapshot.player.visible && !first_person_hides_player(renderer) {
		opacity := living_opacity(renderer, game.PLAYER_ENTITY, .Player, snapshot.player.opacity) if living else
			flipbook_opacity(renderer, game.PLAYER_ENTITY, .Player, snapshot.player.position, snapshot.player.opacity)
		append(entries, Tactical_Alpha_Entry{key = .Player, entity = game.PLAYER_ENTITY, position = snapshot.player.position,
			opacity = opacity*first_person_player_shown(renderer)})
	}
	// Living cards removed from the board mid-death finish toppling first.
	if living {
		for &actor in v.living_state.actors {
			cell := grid.Position{x = int(math.round(actor.position.x)), y = int(math.round(actor.position.y))}
			if !actor.used || !actor.ghost || !tactical_render_visible(renderer, cell) || tactical_pinball_holds(renderer, actor.entity) { continue }
			key := flipbook_key(actor.character)
			append(entries, Tactical_Alpha_Entry{key = key, entity = actor.entity, position = actor.position,
				opacity = living_opacity(renderer, actor.entity, key, 1)})
		}
	}
	// Standees removed from the board mid-death finish toppling first.
	if v.flipbook_state != nil && v.flipbook.loaded {
		for &actor in v.flipbook_state.actors {
			cell := grid.Position{x = int(math.round(actor.position.x)), y = int(math.round(actor.position.y))}
			if !actor.used || !actor.ghost || !tactical_render_visible(renderer, cell) || tactical_pinball_holds(renderer, actor.entity) { continue }
			key := flipbook_key(actor.character)
			append(entries, Tactical_Alpha_Entry{key = key, entity = actor.entity, position = actor.position,
				opacity = flipbook_opacity(renderer, actor.entity, key, actor.position, 1)})
		}
	}
	if room != nil { collect_attack_fx_entries(renderer, entries) }
	if room != nil { collect_ground_entries(renderer, room, entries) }
	if room != nil { collect_lasso_entries(renderer, entries) }
	if room != nil { collect_fishing_entries(renderer, entries) }
	// The Pinball's ball shows on the map's hologram too.
	collect_pinball_entries(renderer, entries)
	if room != nil { collect_first_person_entries(renderer, entries) }
	if room != nil { collect_dino_entries(renderer, entries) }
	// The hologram intentionally supplies no room: its own miniature walls
	// remain in the table pass, and it only needs sorted actor billboards.
	// Behind the player's eyes they are opaque, with the floor.
	if room != nil && (room.player == nil || !room.player.tactical.config.expedition) && !first_person_solid_walls(renderer) {
		for y in 0..<room.level_data.tiles.height { for x in 0..<room.level_data.tiles.width {
			if tactical_cell_on_screen(renderer, {x = x, y = y}) && tactical_render_visible(renderer, {x = x, y = y}) && diorama_interior_wall(room, {x = x, y = y}) {
				append(entries, Tactical_Alpha_Entry{kind = .Wall, position = {f32(x), f32(y)}})
			}
		} }
	}
	// What covers the robot under a cave's rock or a bridge's deck (height_view.odin): a cell a layer, its layer in
	// the entry's `attack`.
	if room != nil && board_cover.under {
		c := board_cover.robot
		for y in c.y-BOARD_COVER_RADIUS..=c.y+BOARD_COVER_RADIUS { for x in c.x-BOARD_COVER_RADIUS..=c.x+BOARD_COVER_RADIUS {
			for layer in grid.LOWEST_LAYER..=grid.HIGHEST_LAYER {
				cell := grid.Position{x = x, y = y, layer = i8(layer)}
				if !cell_covers_robot(cell) || !level.kind_has_floor(board_tile(cell)) { continue }
				append(entries, Tactical_Alpha_Entry{kind = .Cover, attack = i32(layer), position = {f32(x), f32(y)}})
			}
		} }
	}
	// The envelope of each building that is not whole: its walls and colonnade, and its roof.
	if room != nil && (room.player == nil || !room.player.tactical.config.expedition) { collect_structure_entries(renderer, room, entries) }
	forward := rl.Vector3Normalize(v.camera.target-v.camera.position)
	for &entry in entries^ {
		// View depth, not radial distance: objects off to the side must not
		// change order with a nearer object on the same projected sight line.
		center := rl.Vector3{entry.position.x+0.5, DIORAMA_WALL_HEIGHT*0.5, entry.position.y+0.5}
		entry.depth = rl.Vector3DotProduct(center-v.camera.position, forward)
		// The dinosaur is drawn just before the card riding it.
		if entry.kind == .Dino { entry.depth += 0.01 }
	}
	slice.sort_by(entries^[:], proc(a, b: Tactical_Alpha_Entry) -> bool { return a.depth > b.depth })
	return entries^[:]
}

@(private)
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
			draw_diorama_wall(renderer, room, {x = int(entry.position.x), y = int(entry.position.y)})
		} else if entry.kind == .Roof {
			if !walls_active { begin_tactical_lighting(renderer, accents = lights); walls_active = true }
			draw_structure_roof(renderer, room, int(entry.attack))
		} else if entry.kind == .Attack {
			if walls_active { rl.EndShaderMode(); walls_active = false }
			draw_attack_fx_entry(renderer, entry)
		} else if entry.kind == .Ground {
			if walls_active { rl.EndShaderMode(); walls_active = false }
			draw_ground_entry(renderer, entry)
		} else if entry.kind == .Lasso {
			if walls_active { rl.EndShaderMode(); walls_active = false }
			draw_lasso_entry(renderer, entry)
		} else if entry.kind == .Fishing {
			if walls_active { rl.EndShaderMode(); walls_active = false }
			draw_fishing_entry(renderer, entry)
		} else if entry.kind == .Pinball {
			if walls_active { rl.EndShaderMode(); walls_active = false }
			draw_pinball_entry(renderer, entry)
		} else if entry.kind == .First_Person {
			if walls_active { rl.EndShaderMode(); walls_active = false }
			draw_first_person_entry(renderer, entry)
		} else if entry.kind == .Dino {
			if walls_active { rl.EndShaderMode(); walls_active = false }
			draw_dino_entry(renderer, entry)
		} else if entry.kind == .Cover {
			if walls_active { rl.EndShaderMode(); walls_active = false }
			draw_layer_cover({x = int(entry.position.x), y = int(entry.position.y), layer = i8(entry.attack)})
		} else {
			if walls_active { rl.EndShaderMode(); walls_active = false }
			tactical_billboard(renderer, entry.key, entry.position, entry.opacity, entry.entity)
		}
	}
	if walls_active { rl.EndShaderMode() }
	// The board pass only: the hologram has no room.
	draw_living_rings(renderer, room)
}
