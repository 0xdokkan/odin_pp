package render

import game "../game"
import view "../view"

// World beats are already committed by gameplay. They own visual cues only,
// never an old room snapshot or an input lock. The bound covers the maximum
// sixty-second clock debt plus the tail of the preceding rendered beat.
MAX_WORLD_PRESENTATION_CUES :: MAX_PRESENTATION_CUES*64

World_Presentation_Cue :: struct {
	cue: Presentation_Cue,
	delay: f32,
	actor: Presentation_Actor,
	object: Presentation_Grid_Object,
}

World_Playback :: struct {
	cues: [MAX_WORLD_PRESENTATION_CUES]World_Presentation_Cue,
	count: int,
	active_indices: [MAX_WORLD_PRESENTATION_CUES]int,
	active_count: int,
	high_water: int,
	rejected_batches: int,
}

renderer_world_is_busy :: proc(renderer: ^Renderer) -> bool {
	return renderer != nil && renderer.world_playback != nil && renderer.world_playback.count > 0
}

renderer_blocks_player_input :: proc(renderer: ^Renderer) -> bool {
	return renderer != nil && event_timeline_is_busy(&renderer.timeline)
}

renderer_world_available_cues :: proc(renderer: ^Renderer) -> int {
	if renderer == nil { return 0 }
	return MAX_WORLD_PRESENTATION_CUES-(renderer.world_playback.count if renderer.world_playback != nil else 0)
}

renderer_world_can_accept :: proc(renderer: ^Renderer, events: ^game.Event_Log) -> bool {
	return renderer != nil && events != nil && events.count >= 0 && events.count <= len(events.events) &&
	       events.dropped_count == 0 && events.count <= renderer_world_available_cues(renderer)
}

clear_renderer_world_playback :: proc(renderer: ^Renderer) {
	if renderer != nil && renderer.world_playback != nil {
		renderer.world_playback.count = 0
		renderer.world_playback.active_count = 0
		renderer.world_playback.high_water = 0
		renderer.world_playback.rejected_batches = 0
	}
}

destroy_renderer_world_playback :: proc(renderer: ^Renderer) {
	if renderer != nil && renderer.world_playback != nil {
		free(renderer.world_playback)
		renderer.world_playback = nil
	}
}

begin_renderer_world_timeline :: proc(renderer: ^Renderer, before: Room_Presentation,
	events: ^game.Event_Log, after: ^Room_Presentation = nil) -> bool {
	if !renderer_world_can_accept(renderer, events) {
		if renderer != nil && renderer.world_playback != nil { renderer.world_playback.rejected_batches += 1 }
		return false
	}
	if events.count == 0 { return false }
	if renderer.world_playback == nil { renderer.world_playback = new(World_Playback) }
	world := renderer.world_playback
	origin := before
	for event in events.events[:events.count] {
		kind := presentation_cue_kind(event)
		entry := &world.cues[world.count]
		entry^ = {cue = {kind = kind, event = event, duration = presentation_cue_duration(kind, event)}}
		// Waypoints of one body retain their normal duration and order. Every
		// other body starts immediately; thirty enemies are not thirty turns.
		if kind == .Move {
			for previous in world.cues[:world.count] {
				if previous.cue.kind != .Move || previous.cue.event.target != event.target { continue }
				entry.delay = max(entry.delay, previous.delay+previous.cue.duration-previous.cue.elapsed)
			}
		}
		if actor, found := presentation_actor_in_view(&origin, event.target); found { entry.actor = actor^ }
		if object, found := presentation_grid_object_in_view(&origin, event.target); found { entry.object = object^ }
		entry.cue.started = entry.delay <= 0
		if entry.cue.started {
			world.active_indices[world.active_count] = world.count
			world.active_count += 1
		}
		world.count += 1
	}
	world.high_water = max(world.high_water, world.count)
	return true
}

update_renderer_world_playback :: proc(renderer: ^Renderer, dt: f32) -> bool {
	if !renderer_world_is_busy(renderer) || !(dt > 0 && dt < max(f32)) { return false }
	world := renderer.world_playback
	retained := 0
	world.active_count = 0
	for &entry in world.cues[:world.count] {
		step := dt
		if entry.delay > 0 {
			wait := min(entry.delay, step)
			entry.delay -= wait
			step -= wait
		}
		if entry.delay <= PRESENTATION_TIME_EPSILON {
			entry.delay = 0
			entry.cue.started = true
			entry.cue.elapsed = min(entry.cue.duration, entry.cue.elapsed+step)
		}
		if entry.cue.duration-entry.cue.elapsed <= PRESENTATION_TIME_EPSILON { continue }
		world.cues[retained] = entry
		if entry.cue.started {
			world.active_indices[world.active_count] = retained
			world.active_count += 1
		}
		retained += 1
	}
	world.count = retained
	return retained == 0
}

// Active cue iteration is shared by sprite poses, ground FX and overlays.
// Pending waypoints consume no drawing work and cannot hide a player effect.
renderer_active_cue_count :: proc(renderer: ^Renderer) -> int {
	if renderer == nil { return 0 }
	count := presentation_group_size(&renderer.timeline)
	if renderer.world_playback != nil {
		count += renderer.world_playback.active_count
	}
	return count
}

renderer_active_cue_at :: proc(renderer: ^Renderer, offset: int) -> (^Presentation_Cue, bool) {
	if renderer == nil || offset < 0 { return nil, false }
	foreground := presentation_group_size(&renderer.timeline)
	if offset < foreground { return presentation_cue_at(&renderer.timeline, offset) }
	remaining := offset-foreground
	if renderer.world_playback != nil && remaining < renderer.world_playback.active_count {
		return &renderer.world_playback.cues[renderer.world_playback.active_indices[remaining]].cue, true
	}
	return nil, false
}

// Preserve a foreground cue's reveal timing only for fields which gameplay
// has not changed again. A later enemy hit, shield consumption, movement or
// expiry always wins over the older foreground snapshot.
merge_foreground_actor :: proc(current: ^Presentation_Actor, shown, final: Presentation_Actor) {
	if current.position == final.position { current.position = shown.position }
	if current.health == final.health { current.health = shown.health }
	if current.statuses == final.statuses { current.statuses = shown.statuses }
	if current.visible == final.visible { current.visible = shown.visible; current.opacity = shown.opacity }
}

renderer_presentation_snapshot :: proc(renderer: ^Renderer, room: ^game.Room) -> Room_Presentation {
	result := capture_room_presentation(room)
	if renderer == nil { return result }
	if renderer_blocks_player_input(renderer) && renderer.timeline.view.valid {
		shown := &renderer.timeline.view
		final := &renderer.timeline.final_view
		if !final.valid { result = shown^ }
		else {
			if result.phase == final.phase { result.phase = shown.phase }
			if result.deck == final.deck { result.deck = shown.deck }
			if result.gold == final.gold { result.gold = shown.gold }
			if result.pulse_count == final.pulse_count { result.pulse_count = shown.pulse_count }
			if result.relics == final.relics { result.relics = shown.relics }
			if result.modifier == final.modifier { result.modifier = shown.modifier }
			merge_foreground_actor(&result.player, shown.player, final.player)
			for actor in shown.enemies[:shown.enemy_count] {
				live, live_found := presentation_actor_in_view(&result, actor.entity)
				last, last_found := presentation_actor_in_view(final, actor.entity)
				if live_found && last_found { merge_foreground_actor(live, actor, last^) }
				else if !live_found && !last_found && actor.visible && result.enemy_count < len(result.enemies) {
					result.enemies[result.enemy_count] = actor
					result.enemy_count += 1
				}
			}
			for object in shown.objects[:shown.object_count] {
				live, live_found := presentation_grid_object_in_view(&result, object.entity)
				last, last_found := presentation_grid_object_in_view(final, object.entity)
				if live_found && last_found {
					if live.position == last.position { live.position = object.position }
					if live.health == last.health { live.health = object.health }
					if live.detonation_pulse == last.detonation_pulse { live.detonation_pulse = object.detonation_pulse }
					if live.device_armed == last.device_armed { live.device_armed = object.device_armed }
					if live.visible == last.visible { live.visible = object.visible; live.opacity = object.opacity }
				} else if !live_found && !last_found && object.visible && result.object_count < len(result.objects) {
					result.objects[result.object_count] = object
					result.object_count += 1
				}
			}
			if result.trap_count == final.trap_count && result.traps == final.traps {
				result.traps, result.trap_count = shown.traps, shown.trap_count
			}
			if result.loot_count == final.loot_count && result.loot == final.loot {
				result.loot, result.loot_count = shown.loot, shown.loot_count
			}
		}
	}
	apply_world_presentation(renderer, &result)
	return result
}

// One bounded scan per visible body, rather than a scan per queued waypoint.
// This stays linear in queue size even after a long clock hitch.
world_presentation_position :: proc(world: ^World_Playback, entity: game.Entity_Ref, logical: view.Vec2) -> view.Vec2 {
	first: ^Presentation_Cue
	last := logical
	for &entry in world.cues[:world.count] {
		if entry.cue.kind != .Move || entry.cue.event.target != entity { continue }
		if first == nil { first = &entry.cue }
		last = presentation_position(entry.cue.event.to_position)
	}
	// A newer foreground command can replace this body's logical destination.
	// The older track keeps its effects but cannot pull that body backward.
	if first == nil || logical != last { return logical }
	from, to := presentation_position(first.event.from_position), presentation_position(first.event.to_position)
	p := presentation_cue_eased_progress(first)
	return {from.x+(to.x-from.x)*p, from.y+(to.y-from.y)*p}
}

apply_world_presentation :: proc(renderer: ^Renderer, result: ^Room_Presentation) {
	if !renderer_world_is_busy(renderer) { return }
	world := renderer.world_playback
	if result.player.visible && result.player.health > 0 {
		result.player.position = world_presentation_position(world, game.PLAYER_ENTITY, result.player.position)
	}
	for &actor in result.enemies[:result.enemy_count] {
		if actor.visible && actor.health > 0 { actor.position = world_presentation_position(world, actor.entity, actor.position) }
	}
	for &object in result.objects[:result.object_count] {
		if object.visible { object.position = world_presentation_position(world, object.entity, object.position) }
	}
	for &entry in world.cues[:world.count] {
		cue := &entry.cue
		entity := cue.event.target
		if cue.kind != .Defeat || !cue.started { continue }
		if entry.actor.visible && entity == game.PLAYER_ENTITY && result.player.health <= 0 {
			result.player.opacity = 1-presentation_cue_progress(cue)
		} else if entry.actor.visible && entity.kind == .Enemy {
			_, exists := presentation_actor_in_view(result, entity)
			if !exists && result.enemy_count < len(result.enemies) {
				actor := entry.actor
				actor.health, actor.opacity = 0, 1-presentation_cue_progress(cue)
				result.enemies[result.enemy_count] = actor
				result.enemy_count += 1
			}
		} else if entry.object.visible && entity.kind == .Object {
			_, exists := presentation_grid_object_in_view(result, entity)
			if !exists && result.object_count < len(result.objects) {
				object := entry.object
				object.health, object.opacity = 0, 1-presentation_cue_progress(cue)
				result.objects[result.object_count] = object
				result.object_count += 1
			}
		}
	}
}
