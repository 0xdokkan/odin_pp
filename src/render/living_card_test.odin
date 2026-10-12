package render

import "core:testing"
import gfx "../engine/gfx"
import game "../game"
import view "../view"

// Every action of every character lands on a drawn clip, and a move's card
// slide ends before its drawings do.
@(test)
test_living_clips_resolve_and_slides_end_inside_their_clip :: proc(t: ^testing.T) {
	for character in gfx.Flipbook_Character {
		sheet := &gfx.LIVING_SHEETS[character]
		for action in gfx.Living_Action {
			clip := &sheet.clips[gfx.living_resolve(character, action)]
			testing.expectf(t, clip.count > 0, "%v %v: no drawings", character, action)
			testing.expectf(t, clip.count <= gfx.LIVING_MAX_FRAMES && clip.hit < clip.count, "%v %v: bad table", character, action)
			for index in 0..<clip.count {
				testing.expectf(t, clip.durations[index] > 0, "%v %v: drawing %d has no time", character, action, index)
			}
			if clip.travel != .None {
				ms := gfx.living_clip_seconds(clip)*1000
				testing.expectf(t, f64(clip.travel_start)+f64(clip.travel_ms) <= ms+1, "%v %v: the card is still sliding when the clip ends", character, action)
			}
		}
		// The board's moves all push the card along.
		for move in ([3]gfx.Living_Action{.Move_Side, .Move_Up, .Move_Down}) {
			testing.expectf(t, sheet.clips[move].travel != .None, "%v %v: no travel", character, move)
		}
	}
}

@(test)
test_living_travel_curves_leave_and_land_on_the_cells :: proc(t: ^testing.T) {
	for kind in gfx.Living_Travel {
		if kind == .None { continue }
		testing.expectf(t, abs(living_travel_progress(kind, 0)) < 1e-4, "%v: moves before the push", kind)
		testing.expectf(t, abs(living_travel_progress(kind, 1)-1) < 1e-4, "%v: misses the cell", kind)
		testing.expectf(t, abs(living_travel_lift(kind, 0)) < 1e-4 && abs(living_travel_lift(kind, 1)) < 1e-4, "%v: does not land", kind)
	}
	// A shove knocks the card a little past the cell before it settles; a
	// stomp moves it half a cell per step.
	peak := f32(0)
	for step in 0..=100 { peak = max(peak, living_travel_progress(.Shove, f32(step)/100)) }
	testing.expect(t, peak > 1.01)
	testing.expect(t, abs(living_travel_progress(.Stomp, 0.5)-0.5) < 1e-4)
	testing.expect(t, living_travel_lift(.Hop, 0.25) > 0.05 && living_travel_lift(.Float, 0.5) > 0.05)
}

@(test)
test_living_frame_holds_the_last_drawing_and_loops :: proc(t: ^testing.T) {
	once := gfx.Living_Clip{count = 3}
	once.durations[0], once.durations[1], once.durations[2] = 100, 100, 100
	frame, finished := gfx.living_frame(&once, 0.05)
	testing.expect(t, frame == 0 && !finished)
	frame, finished = gfx.living_frame(&once, 0.15)
	testing.expect(t, frame == 1 && !finished)
	frame, finished = gfx.living_frame(&once, 0.35)
	testing.expect(t, frame == 2 && finished)
	// Started from its impact drawing, a one-shot skips the drawings before.
	frame, _ = gfx.living_frame(&once, 0.05, 1)
	testing.expect(t, frame == 1)
	loop := gfx.Living_Clip{count = 2, loop = true}
	loop.durations[0], loop.durations[1] = 100, 200
	frame, finished = gfx.living_frame(&loop, 0.25)
	testing.expect(t, frame == 1 && !finished)
	frame, _ = gfx.living_frame(&loop, 0.35)
	testing.expect(t, frame == 0)
}

// The card stays on its cell until the push, slides as one block, then stands
// on the new cell.
@(test)
test_living_card_waits_for_the_push_then_slides :: proc(t: ^testing.T) {
	renderer := new(Renderer)
	defer free(renderer)
	renderer.tactical.living = true
	renderer.tactical.living_state = new(Living_State)
	defer free(renderer.tactical.living_state)
	slot := living_slot(renderer.tactical.living_state, game.PLAYER_ENTITY, .Pilgrim, 0)
	slot.slide_from, slot.slide_to = {2, 3}, {3, 3}
	slot.slide_start, slot.slide_ms, slot.slide_kind, slot.sliding = 1, 200, .Shove, true
	cell := view.Vec2{3, 3}
	renderer.sprite_assets.elapsed = 0.9
	at, lift := living_card_position(renderer, game.PLAYER_ENTITY, .Player, cell)
	testing.expect(t, at.x == 2 && at.y == 3 && lift == 0)
	renderer.sprite_assets.elapsed = 1.1
	at, _ = living_card_position(renderer, game.PLAYER_ENTITY, .Player, cell)
	testing.expect(t, at.x > 2.2 && at.x < 3.2 && at.y == 3)
	renderer.sprite_assets.elapsed = 1.3
	at, _ = living_card_position(renderer, game.PLAYER_ENTITY, .Player, cell)
	testing.expect(t, at.x == 3 && at.y == 3)
	// Classic cards never slide.
	renderer.tactical.living = false
	renderer.sprite_assets.elapsed = 1.1
	at, _ = living_card_position(renderer, game.PLAYER_ENTITY, .Player, cell)
	testing.expect(t, at.x == 3 && at.y == 3)
}

@(test)
test_living_player_card_comes_back_after_death_on_restart :: proc(t: ^testing.T) {
	renderer := new(Renderer)
	defer free(renderer)
	renderer.tactical.living = true
	renderer.tactical.living_state = new(Living_State)
	defer free(renderer.tactical.living_state)
	state := renderer.tactical.living_state
	slot := living_slot(state, game.PLAYER_ENTITY, .Pilgrim, 0)
	slot.action, slot.started = .Death, 0
	now := f64(100)
	actor := Presentation_Actor{entity = game.PLAYER_ENTITY, health = 0, max_health = 22, visible = true}
	living_observe(renderer, state, nil, actor, .Pilgrim, now)
	found := living_find(renderer, game.PLAYER_ENTITY, .Pilgrim)
	testing.expect(t, found != nil && found.action == .Death)
	actor.health = 22
	living_observe(renderer, state, nil, actor, .Pilgrim, now+1)
	found = living_find(renderer, game.PLAYER_ENTITY, .Pilgrim)
	testing.expect(t, found != nil && found.action == .Idle)
	found.action = .Death
	clear_event_animations(renderer)
	testing.expect(t, living_find(renderer, game.PLAYER_ENTITY, .Pilgrim) == nil)
}
