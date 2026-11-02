package render

// Extend this policy for future wheels/reveals without teaching the controller
// each animation's kind. The foreground alone owns cinematic suspension.
Presentation_Time_Policy :: enum { Live, Cast, Cinematic }

// The dice; BENVENUTI A NAPOLI's grandpa coming with his table or his purse
// (the user's choice: the world stands still for him, docs/piano-napoli.md).
@(private)
presentation_cue_is_cinematic :: proc(cue: ^Presentation_Cue) -> bool {
	return cue != nil && (cue.kind == .Dice_Rolled || cue.kind == .Napoli_Begun && napoli_event_is_visit(cue.event))
}

presentation_time_policy :: proc(timeline: ^Presentation_Timeline) -> Presentation_Time_Policy {
	if cue, found := active_presentation_cue(timeline); found {
		if presentation_cue_is_cinematic(cue) { return .Cinematic }
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
		if !presentation_cue_is_cinematic(cue) { total += cue.duration }
		offset += span
	}
	if total <= 0 { return }
	timeline.card_cast = true
	for offset in 0..<timeline.count {
		cue, _ := presentation_cue_at(timeline, offset)
		if !presentation_cue_is_cinematic(cue) { cue.duration *= seconds/total }
	}
}
