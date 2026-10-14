package render

import gfx "../engine/gfx"
import game "../game"
import view "../view"

// World beats are already committed by gameplay. They own visual cues only,
// never an old room snapshot or an input lock. The bound covers the maximum
// sixty-second clock debt plus the tail of the preceding rendered beat.
MAX_WORLD_PRESENTATION_CUES :: MAX_PRESENTATION_CUES*64
// The bodies whose deaths are still to come that one snapshot keeps apart
// (hold_unlanded_blows): every enemy and object of a room at once.
HOLD_STANDING_BODIES :: game.MAX_ENEMIES_PER_ROOM+game.MAX_GRID_OBJECTS_PER_ROOM

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
	renderer.cue_batches += 1
	first := world.count
	// A charge strikes once it has arrived, on every board: its blow, and all
	// the batch shows after it, wait for the charger's own pending walk.
	floor: f32
	// The blows' timing follows the attack clips, which only a living board has.
	living := renderer.tactical.living
	for event in events.events[:events.count] {
		kind := presentation_cue_kind(event)
		entry := &world.cues[world.count]
		entry^ = {cue = {kind = kind, event = event, duration = presentation_cue_duration(kind, event), batch = renderer.cue_batches}}
		// Waypoints of one body retain their normal duration and order. Every
		// other body starts immediately; thirty enemies are not thirty turns.
		if kind == .Move {
			for previous in world.cues[:world.count] {
				if previous.cue.kind != .Move || previous.cue.event.target != event.target { continue }
				entry.delay = max(entry.delay, previous.delay+previous.cue.duration-previous.cue.elapsed)
			}
			// A body pushed by a blow gives ground as the blow lands: on the
			// hit drawing of its striker's attack clip.
			if living && event.source != event.target && event.source.kind == .Enemy {
				for previous in world.cues[first:world.count] {
					if !game.event_is_attack(previous.cue.event) || previous.cue.event.source != event.source { continue }
					contact: f32
					if actor, found := presentation_actor_in_view(&origin, event.source); found {
						if character, ok := flipbook_character(sprite_key_for_enemy(actor.archetype)); ok { contact = f32(attack_fx_impact_seconds(character)) }
					}
					entry.delay = max(entry.delay, previous.delay+contact)
				}
			}
		} else {
			if game.event_is_attack(event) {
				for previous in world.cues[:world.count] {
					if previous.cue.kind == .Move && previous.cue.event.target == event.source {
						floor = max(floor, world_walk_left(renderer, previous))
					}
				}
			}
			// What befalls a blow's attacker later in its batch (the thorns'
			// answer, the bite of its own poison, its death and its loot) waits
			// until it is done striking: it is seen to strike first.
			if living {
				subject := event.source if event.kind == .Loot_Dropped else event.target
				for previous in world.cues[first:world.count] {
					blow := previous.cue.event
					if !game.event_is_attack(blow) || blow.source != subject { continue }
					entry.delay = max(entry.delay, previous.delay+world_blow_done(&origin, blow))
				}
			}
		}
		entry.delay = max(entry.delay, floor)
		if actor, found := presentation_actor_in_view(&origin, event.target); found { entry.actor = actor^ }
		if object, found := presentation_grid_object_in_view(&origin, event.target); found { entry.object = object^ }
		// A body that dies here stands where its walks leave it (apply_world_presentation).
		if kind == .Defeat { entry.actor.position = world_walks_end(world, event.target, entry.actor.position) }
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

// Seconds from a blow's cue until its attacker, as the batch's first view
// shows it, is done striking (attack_fx_done_seconds).
world_blow_done :: proc(origin: ^Room_Presentation, blow: game.Game_Event) -> f32 {
	ranged := game.event_is_ranged_attack(blow)
	// The player's shot is an arrow (attack_look), whatever is in his hand.
	if blow.source == game.PLAYER_ENTITY {
		look := Attack_Look.Bolt if ranged else attack_player_look(origin.weapon)
		return f32(attack_fx_done_seconds(.Pilgrim, look, blow))
	}
	actor, found := presentation_actor_in_view(origin, blow.source)
	if !found { return 0 }
	character, known := flipbook_character(sprite_key_for_enemy(actor.archetype))
	if !known { return 0 }
	return f32(attack_fx_done_seconds(character, attack_enemy_look(actor.archetype, ranged), blow))
}

// Where the walks queued for a body leave it (`from` when none is).
world_walks_end :: proc(world: ^World_Playback, entity: game.Entity_Ref, from: view.Vec2) -> view.Vec2 {
	last := from
	for &entry in world.cues[:world.count] {
		if entry.cue.kind == .Move && entry.cue.event.target == entity { last = presentation_position(entry.cue.event.to_position) }
	}
	return last
}

// Seconds until a pending walk of a body has shown: its cue and, on a living
// board, its card's slide, which can outlast the cue (gfx.Living_Clip's
// travel_start+travel_ms: the brute stomps for longer than his step).
world_walk_left :: proc(renderer: ^Renderer, walk: World_Presentation_Cue) -> f32 {
	shown := walk.cue.duration
	event := walk.cue.event
	if renderer.tactical.living && event.source == event.target && walk.actor.entity == event.target && !game.event_is_teleport(event) {
		character, known := gfx.Flipbook_Character.Pilgrim, event.target == game.PLAYER_ENTITY
		if !known { character, known = flipbook_character(sprite_key_for_enemy(walk.actor.archetype)) }
		if known {
			for action in ([3]gfx.Living_Action{.Move_Side, .Move_Up, .Move_Down}) {
				clip := &gfx.LIVING_SHEETS[character].clips[gfx.living_resolve(character, action)]
				if clip.travel != .None { shown = max(shown, (f32(clip.travel_start)+f32(clip.travel_ms))/1000) }
			}
		}
	}
	return walk.delay+shown-walk.cue.elapsed
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
			if result.weapon == final.weapon { result.weapon = shown.weapon }
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
			if result.ground == final.ground { result.ground = shown.ground }
		}
	}
	apply_world_presentation(renderer, &result)
	hold_unlanded_blows(renderer, &result)
	return result
}

// What a blow does shows as it lands, as its token and the struck card's
// reaction do: until then (a world cue still waiting, a bolt still flying, a
// swing not yet down) the heart over the struck fighter's head and the HUD keep
// the health it had, a body the blow fells as well (it falls as the blow
// lands), and the player keeps on show the charges the blow spends: those his
// own blow spent (a bump's Lama and Destino, an arrow), and the RIFLESSO that
// turns an enemy's back as it reaches him.
hold_unlanded_blows :: proc(renderer: ^Renderer, result: ^Room_Presentation) {
	// A body whose death is still to come in the world's cues already stands
	// as its command found it (apply_world_presentation): nothing to give back.
	standing: [HOLD_STANDING_BODIES]game.Entity_Ref
	standing_count := 0
	if renderer.world_playback != nil {
		for &entry in renderer.world_playback.cues[:renderer.world_playback.count] {
			if entry.cue.kind != .Defeat || entry.cue.started || entry.cue.event.target == game.PLAYER_ENTITY || standing_count == len(standing) { continue }
			standing[standing_count] = entry.cue.event.target
			standing_count += 1
		}
	}
	hold :: proc(result: ^Room_Presentation, standing: []game.Entity_Ref, target: game.Entity_Ref, amount: i32) {
		actor, found := presentation_actor_in_view(result, target)
		if !found || amount <= 0 { return }
		for body in standing { if body == target { return } }
		actor.health = min(actor.max_health, max(actor.health, 0)+amount)
	}
	// A blow the board shows with its props waits for it: on the frame its
	// cue starts, before the prop is on the board (observe_attack_cues), then
	// for as long as the prop carries it.
	props := renderer.tactical.enabled && renderer.tactical.scene_3d && renderer.tactical.living
	waiting :: proc(renderer: ^Renderer, cue: ^Presentation_Cue, props: bool) -> bool {
		return game.event_is_attack(cue.event) && (!cue.started || (props && !attack_fx_shown(renderer, cue)))
	}
	// RIFLESSO's charges still to be spent, and where the first stood.
	deflects: i32
	slot := -1
	if renderer.world_playback != nil {
		for &entry in renderer.world_playback.cues[:renderer.world_playback.count] {
			if !waiting(renderer, &entry.cue, props) { continue }
			#partial switch entry.cue.kind {
			case .Damage:
				hold(result, standing[:standing_count], entry.cue.event.target, entry.cue.event.amount)
			case .Attack_Deflected:
				deflects += 1
				if index, found := game.status_index(&entry.actor.statuses, .Deflect); found && slot < 0 { slot = index }
			}
		}
	}
	// The player's own blows: the view takes them as their cues start.
	for offset in 0..<presentation_group_size(&renderer.timeline) {
		cue, found := presentation_cue_at(&renderer.timeline, offset)
		if found && cue.started && cue.kind == .Damage && waiting(renderer, cue, props) { hold(result, standing[:standing_count], cue.event.target, cue.event.amount) }
	}
	if attack_fx_foreground_pending(renderer) {
		statuses := &result.player.statuses
		for &status in statuses.items[:statuses.count] {
			if game.status_kind_is_player_charge(status.kind) { status.potency = max(status.potency, renderer.timeline.charges_before[status.kind]) }
		}
	}
	if props {
		now := renderer.sprite_assets.elapsed
		for &fx in renderer.tactical.attack_fx.items {
			if !fx.used { continue }
			if fx.damage > 0 && fx.landing-living_clock_at(renderer, fx.attacker, now) > 0 { hold(result, standing[:standing_count], fx.victim, fx.damage) }
			if fx.deflect && !fx.answered {
				deflects += 1
				if slot < 0 { slot = int(fx.slot) }
			}
		}
	}
	hold_player_charge(&result.player.statuses, .Deflect, deflects, slot)
}

// `count` more of the player's charge `kind` than `statuses` carry; when its
// last one is already gone, back at `slot` among them (its chip's place in
// the HUD's order: as it was gained), or last.
hold_player_charge :: proc(statuses: ^game.Status_Set, kind: game.Status_Kind, count: i32, slot: int) {
	if count <= 0 || statuses.count < 0 || statuses.count > len(statuses.items) { return }
	if index, found := game.status_index(statuses, kind); found {
		statuses.items[index].potency += count
		return
	}
	if statuses.count == len(statuses.items) { return }
	at := clamp(slot, 0, statuses.count) if slot >= 0 else statuses.count
	for index := statuses.count; index > at; index -= 1 { statuses.items[index] = statuses.items[index-1] }
	statuses.items[at] = {kind = kind, potency = count}
	statuses.count += 1
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
		// Loot of a death still to come is not on the floor yet.
		if cue.kind == .Loot_Dropped && !cue.started { hide_collected_presentation_loot(result, cue.event) }
		if cue.kind != .Defeat { continue }
		// A death still to come (its body strikes first) keeps the body on
		// the board as it stood; a death showing fades it out.
		if entry.actor.visible && entity == game.PLAYER_ENTITY && result.player.health <= 0 {
			if cue.started { result.player.opacity = 1-presentation_cue_progress(cue) }
		} else if entry.actor.visible && entity.kind == .Enemy {
			_, exists := presentation_actor_in_view(result, entity)
			if !exists && result.enemy_count < len(result.enemies) {
				actor := entry.actor
				actor.position = world_presentation_position(world, entity, actor.position)
				if cue.started { actor.health, actor.opacity = 0, 1-presentation_cue_progress(cue) }
				result.enemies[result.enemy_count] = actor
				result.enemy_count += 1
			}
		} else if entry.object.visible && entity.kind == .Object {
			_, exists := presentation_grid_object_in_view(result, entity)
			if !exists && result.object_count < len(result.objects) {
				object := entry.object
				if cue.started { object.health, object.opacity = 0, 1-presentation_cue_progress(cue) }
				result.objects[result.object_count] = object
				result.object_count += 1
			}
		}
	}
}
