package render

import gfx "../engine/gfx"

// The board's actions at the player's pace (game.tactical_player_pace, which
// Room_Presentation.pace carries). In the game as it is played every picture
// of an action plays in 1/pace of its first time: a cue, a drawing's one-shot
// clip (a step, a blow, a wound, a death, a turn, a topple), a blow's swing
// and flight. Loops (idle, channel, stunned) keep their own. Behind the
// player's eyes and under the bare rules the pace is one: the first times.

// The part of its first time an action's picture plays in (1: all of it).
action_scale :: proc(shown: ^Room_Presentation) -> f64 {
	if shown == nil || !(shown.pace > 1) { return 1 }
	return 1/f64(shown.pace)
}

// The scale of the board as it shows now.
renderer_action_scale :: proc(renderer: ^Renderer) -> f64 {
	if renderer == nil { return 1 }
	return action_scale(renderer.tactical.snapshot)
}

// A scale as stored on an actor or a blow: none yet is the first times.
@(private)
action_scale_of :: proc(scale: f64) -> f64 {
	return scale if scale > 0 else 1
}

// A living clip played at `scale`: its seconds, its hit, its slide, its drawing.
living_played_seconds :: proc(clip: ^gfx.Living_Clip, scale: f64) -> f64 {
	return gfx.living_clip_seconds(clip)*(1 if clip.loop else action_scale_of(scale))
}

living_played_hit :: proc(clip: ^gfx.Living_Clip, scale: f64) -> f64 {
	return gfx.living_hit_seconds(clip)*(1 if clip.loop else action_scale_of(scale))
}

// When the card starts its slide, from the clip's start, and for how long.
living_played_travel :: proc(clip: ^gfx.Living_Clip, scale: f64) -> (start, length: f64) {
	s := 1 if clip.loop else action_scale_of(scale)
	return f64(clip.travel_start)/1000*s, f64(clip.travel_ms)/1000*s
}

living_played_frame :: proc(clip: ^gfx.Living_Clip, elapsed, scale: f64, first: i32 = 0) -> (frame: i32, finished: bool) {
	return gfx.living_frame(clip, elapsed if clip.loop else elapsed/action_scale_of(scale), first)
}

flipbook_played_seconds :: proc(clip: ^gfx.Flipbook_Clip, scale: f64, first: i32 = 0) -> f64 {
	return gfx.flipbook_clip_seconds(clip, first)*(1 if clip.loop else action_scale_of(scale))
}

flipbook_played_frame :: proc(clip: ^gfx.Flipbook_Clip, elapsed, scale: f64, first: i32 = 0) -> (frame: i32, finished: bool) {
	return gfx.flipbook_frame(clip, elapsed if clip.loop else elapsed/action_scale_of(scale), first)
}
