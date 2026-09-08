package render

// Rendered playback preserves enough frames to see the die leave the floor.
// A hitch may otherwise consume the entire throw, even when its baked physics
// contains large rebounds. Explicit seek/replay retains update_event_timeline.
DICE_MAX_FRAME_PROGRESS :: f32(1.0/18.0)

update_renderer_frame_timeline :: proc(renderer: ^Renderer, dt: f32) -> bool {
	if renderer == nil || !(dt > 0 && dt < max(f32)) { return false }
	timeline := &renderer.timeline
	if !event_timeline_is_busy(timeline) { return false }
	remaining := dt*renderer_playback_speed(renderer)
	for remaining > 0 && event_timeline_is_busy(timeline) {
		cue, _ := active_presentation_cue(timeline)
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
		remaining -= step
		if reached_contact {
			// Store the same absolute boundary used by the next comparison;
			// elapsed+step rounding must never repeatedly stop just below it.
			cue.elapsed = contact_elapsed
			break
		}
		if limited { break }
	}
	return !event_timeline_is_busy(timeline)
}
