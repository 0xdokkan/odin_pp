package render

// Extend this policy for future wheels/reveals without teaching the controller
// each animation's kind. The foreground alone owns cinematic suspension.
Presentation_Time_Policy :: enum { Live, Cast, Cinematic }

presentation_cue_is_cinematic :: proc(kind: Presentation_Cue_Kind) -> bool {
	return kind == .Dice_Rolled
}

presentation_time_policy :: proc(timeline: ^Presentation_Timeline) -> Presentation_Time_Policy {
	if cue, found := active_presentation_cue(timeline); found {
		if presentation_cue_is_cinematic(cue.kind) { return .Cinematic }
		if timeline.card_cast { return .Cast }
	}
	return .Live
}

fit_card_cast_timeline :: proc(renderer: ^Renderer, seconds: f32) {
	if renderer == nil || seconds <= 0 { return }
	timeline := &renderer.timeline
	total: f32
	for offset := 0; offset < timeline.count; {
		span := presentation_group_size(timeline, offset)
		cue, _ := presentation_cue_at(timeline, offset)
		if !presentation_cue_is_cinematic(cue.kind) { total += cue.duration }
		offset += span
	}
	if total <= 0 { return }
	timeline.card_cast = true
	for offset in 0..<timeline.count {
		cue, _ := presentation_cue_at(timeline, offset)
		if !presentation_cue_is_cinematic(cue.kind) { cue.duration *= seconds/total }
	}
}
