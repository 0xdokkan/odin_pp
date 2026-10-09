package render

// Rendered playback preserves enough frames to see the die leave the floor.
// A hitch may otherwise consume the entire throw, even when its baked physics
// contains large rebounds. Explicit seek/replay retains update_event_timeline.
DICE_MAX_FRAME_PROGRESS :: f32(1.0/18.0)

update_renderer_frame_timeline :: proc(renderer: ^Renderer, dt: f32) -> bool {
	if renderer == nil || !(dt > 0 && dt < max(f32)) { return false }
	was_busy := renderer_timeline_is_busy(renderer)
	renderer.frame_clock_valid = true
	renderer.frame_simulation_dt = 0
	renderer.frame_had_cinematic = false
	cast_frame := renderer.timeline.card_cast && event_timeline_is_busy(&renderer.timeline)
	timeline := &renderer.timeline
	if !event_timeline_is_busy(timeline) {
		renderer.frame_simulation_dt = dt
		update_renderer_world_playback(renderer, dt*renderer_playback_speed(renderer))
		return was_busy && !renderer_timeline_is_busy(renderer)
	}
	// Casting has a gameplay duration: F4 cannot accelerate its paid seconds.
	speed := f32(1) if cast_frame else renderer_playback_speed(renderer)
	remaining := dt*speed
	for remaining > 0 && event_timeline_is_busy(timeline) {
		cue, _ := active_presentation_cue(timeline)
		cinematic := presentation_cue_is_cinematic(cue.kind)
		renderer.frame_had_cinematic = renderer.frame_had_cinematic || cinematic
		available := max(f32(0), cue.duration-cue.elapsed)
		if available <= 0 {
			update_event_timeline(timeline, min(remaining, PRESENTATION_TIME_EPSILON))
			remaining -= min(remaining, PRESENTATION_TIME_EPSILON)
			continue
		}
		step := min(remaining, available)
		limited := false
		contact_elapsed: f32
		reached_contact := false
		if cue.kind == .Dice_Rolled {
			limit := cue.duration*DICE_MAX_FRAME_PROGRESS
			limited = step > limit
			step = min(step, limit)
			// A visible ascent alone does not show an impact: expose its actual
			// floor pose for one frame before continuing into the next flight.
			for landmark in ([3]f32{DICE_PHYSICS_IMPACT_PROGRESS, DICE_SECOND_IMPACT_PROGRESS, DICE_THIRD_IMPACT_PROGRESS}) {
				at := cue.duration*landmark
				if cue.elapsed < at && cue.elapsed+step >= at {
					step, contact_elapsed, reached_contact = at-cue.elapsed, at, true
					break
				}
			}
		}
		update_event_timeline(timeline, step)
		if !cinematic { renderer.frame_simulation_dt += step/speed }
		remaining -= step
		if reached_contact {
			// Store the same absolute boundary used by the next comparison;
			// elapsed+step rounding must never repeatedly stop just below it.
			cue.elapsed = contact_elapsed
			break
		}
		if limited { break }
	}
	if !event_timeline_is_busy(timeline) { renderer.frame_simulation_dt += remaining/speed }
	if !cast_frame { update_renderer_world_playback(renderer, renderer.frame_simulation_dt*renderer_playback_speed(renderer)) }
	return was_busy && !renderer_timeline_is_busy(renderer)
}
