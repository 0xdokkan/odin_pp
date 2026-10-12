package render

import "core:c"
import "core:fmt"
import rl "vendor:raylib"
import game "../game"

TACTICAL_HUD_HEIGHT :: f32(84)

tactical_refocus_bounds :: proc(renderer: ^Renderer) -> rl.Rectangle {
	return tactical_hud_layout(renderer).refocus
}
tactical_map_controls_bounds :: proc(renderer: ^Renderer) -> rl.Rectangle {
	return tactical_hud_layout(renderer).map_button
}
tactical_phase_bounds :: proc(renderer: ^Renderer) -> rl.Rectangle {
	return tactical_hud_layout(renderer).pulse
}

// Kept for callers that tint a plate by state.
tactical_hud_panel :: proc(bounds: rl.Rectangle, accent: rl.Color = GOTHIC_STEEL) {
	hud_frame(bounds, accent)
}

tactical_status_label :: proc(kind: game.Status_Kind, short: bool) -> (label: string, accent: rl.Color) {
	accent = GOTHIC_BLUE
	switch kind {
	case .Poison: label, accent = "VELENO", HUD_VENOM
	case .Shield: label = "SCUDO"
	case .Thorns: label, accent = "SPINE", HUD_VENOM
	case .Afterimage: label, accent = "OMBRA", HUD_SHADE
	case .Stagger: label, accent = "STORDITO", GOTHIC_RED
	case .Survey: label = "VISTA"
	}
	if short && len(label) > 3 { label = label[:3] }
	return
}

// VITA: health first and large, then gold and the active statuses.
draw_tactical_status :: proc(renderer: ^Renderer, room: ^game.Room) {
	v := renderer_status_view(renderer, room)
	layout := tactical_hud_layout(renderer)
	b := layout.vitals
	low := v.health*3 <= v.max_health
	hud_frame(b, GOTHIC_RED if low else GOTHIC_BLUE)
	gothic_text(renderer, "VITA", b.x+12, b.y+7, 10, GOTHIC_MUTED)
	gothic_text_fit(renderer, fmt.ctprintf("%d/%d", v.health, v.max_health), {b.x+12, b.y+17, 92, 28}, 24, GOTHIC_RED if low else GOTHIC_PAPER)
	hud_bar({b.x+108, b.y+21, b.width-120, 12}, f32(v.health)/f32(max(i32(1), v.max_health)), GOTHIC_RED, int(min(v.max_health, 20)))
	row := b.y+b.height-22
	gothic_inlay(b.x+16, row+8, 4, HUD_AMBER)
	gothic_text_fit(renderer, fmt.ctprintf("%d", v.gold), {b.x+24, row, 42, 17}, 12, HUD_AMBER)
	count := v.statuses.count
	if count == 0 { return }
	left := b.x+72
	room_width := b.x+b.width-8-left
	shown := min(count, 3)
	chip := min(f32(96), (room_width-f32(shown-1)*4-(26 if count > shown else 0))/f32(shown))
	for status, index in v.statuses.items[:shown] {
		label, accent := tactical_status_label(status.kind, chip < 80)
		hud_chip(renderer, {left+f32(index)*(chip+4), row-1, chip, 18}, fmt.ctprintf("%s %d / %ds", label, status.potency, status.remaining_pulses), accent)
	}
	if count > shown {
		gothic_text_fit(renderer, fmt.ctprintf("+%d", count-shown), {left+f32(shown)*(chip+4), row, 24, 17}, 12, GOTHIC_MUTED)
	}
}

draw_tactical_hud :: proc(renderer: ^Renderer, room: ^game.Room, paused, hologram: bool) {
	s := &room.player.tactical
	combat := renderer.tactical.snapshot.phase == .Combat
	busy := renderer_blocks_player_input(renderer)
	recovering := game.tactical_is_recovering(room)
	cinematic := presentation_time_policy(&renderer.timeline) == .Cinematic
	layout := tactical_hud_layout(renderer)
	bounds := layout.pulse
	x, y, width := bounds.x, bounds.y, bounds.width
	label: cstring = "AGISCI"
	switch s.phase {
	case .Decision:
	case .Recovery: label = "RECUPERO"
	case .Resolving: label = "AZIONE"
	}
	if !combat { label = "ESPLORA" }
	else if room.qte.kind != .None { label = "DIFESA" }
	else if recovering { label = "RECUPERO" }
	else if cinematic { label = "DADI" }
	else if game.tactical_is_casting(room) { label = "LANCIO" }
	else if busy || game.tactical_player_busy(room) { label = "AZIONE" }
	// The pulse continues during casting; cinematic dice and QTE own a full pause.
	timed := combat
	accent := GOTHIC_RED if timed && s.remaining <= 5 else GOTHIC_BLUE
	if recovering { accent = HUD_AMBER }
	hud_frame(bounds, accent)
	gothic_text_fit(renderer, label, {x+12, y+5, 150, 24}, 18, GOTHIC_PAPER)
	gothic_text_fit(renderer, fmt.ctprintf("PULSE %d", min(s.cycle, max(int)-1)+1), {x+12, y+26, 90, 14}, 10, GOTHIC_MUTED)
	if timed {
		timer := fmt.ctprintf("%.1fs", s.remaining)
		timer_width := gothic_text_width(renderer, timer, 24)
		// The tick: a lamp fills toward each whole second and flares gold in
		// the window where moves, bumps and cards turn critical.
		approach, on_beat := game.tactical_beat_glow(room)
		lamp := rl.Vector2{x+width-24-timer_width, y+15}
		gothic_text(renderer, timer, x+width-12-timer_width, y+3, 24, TACTICAL_FEEDBACK_CRITICAL if on_beat else accent)
		rl.DrawCircleV(lamp, 6, HUD_TROUGH)
		rl.DrawCircleSector(lamp, 5, -90, -90+360*approach, 16, color_with_opacity(TACTICAL_FEEDBACK_CRITICAL, 0.55))
		if on_beat {
			rl.DrawCircleV(lamp, 5, TACTICAL_FEEDBACK_CRITICAL)
			rl.DrawRing(lamp, 7, 9, 0, 360, 20, color_with_opacity(TACTICAL_FEEDBACK_CRITICAL, 0.7))
		}
		rl.DrawCircleLinesV(lamp, 6, HUD_EDGE)
	}
	budget := max(f32(1), f32(s.budget))
	if recovering { budget = game.TACTICAL_RECOVERY_SECONDS }
	meter := rl.Rectangle{x+104, y+29, width-116, 7}
	if timed { hud_bar(meter, s.remaining/budget, accent, int(min(budget, 30))) }
	else { hud_bar(meter, 1, GOTHIC_BLUE if !combat else GOTHIC_STEEL) }
	// A timed action (mechanics lab): a thin gold line drains as it plays out.
	if game.tactical_player_busy(room) && s.action_duration > 0 {
		left := clamp(s.action_remaining/s.action_duration, 0, 1)
		rl.DrawRectangleRec({meter.x, meter.y+meter.height+2, meter.width*left, 2}, TACTICAL_FEEDBACK_CRITICAL)
	}
	// One context line, only when it says something the plate does not.
	status: cstring
	if busy { status = "I NEMICI CONTINUANO" }
	if game.tactical_player_busy(room) { status = fmt.ctprintf("AZIONE %.1fs / I NEMICI CONTINUANO", s.action_remaining) }
	if game.tactical_is_casting(room) { status = fmt.ctprintf("LANCIO %.1fs / NEMICI SOSPESI", s.cast_remaining) }
	if cinematic { status = "TEMPO SOSPESO" }
	if recovering { status = "MUOVITI / CARTE IN RECUPERO" }
	if room.qte.kind != .None { status = "PULSE SOSPESO" }
	if !combat { status = "RACCOGLI IL BOTTINO / RAGGIUNGI L'USCITA" }
	if hologram && combat && room.qte.kind == .None { status = "MAPPA APERTA / IL TEMPO SCORRE" }
	v := renderer_status_view(renderer, room)
	objective: cstring = fmt.ctprintf("NEMICI %d", v.enemy_count) if combat else "STANZA LIBERATA"
	objective_width := gothic_text_width(renderer, objective, 10)
	gothic_text(renderer, objective, x+width-12-objective_width, y+bounds.height-17, 10, GOTHIC_BLUE if !combat else GOTHIC_MUTED)
	if status != nil {
		gothic_text_fit(renderer, status, {x+12, y+bounds.height-18, width-36-objective_width, 14}, 10, accent if hologram || recovering else GOTHIC_MUTED)
	}
	// COMANDI: a 2x2 grid under the right column.
	hud_frame(layout.commands, GOTHIC_STEEL)
	hud_button(renderer, layout.map_button, "TAB", "CHIUDI" if hologram else "MAPPA", room.qte.kind == .None)
	if !hologram && combat {
		hud_button(renderer, layout.refocus, "F", fmt.ctprintf("REFOCUS -%.0fs", game.TACTICAL_REFOCUS_SECONDS), refocus_button_is_enabled(renderer))
		draw_tactical_dodge_chip(renderer, room, layout.dodge)
	}
	if !hologram && m8_control_visible(room, .Character) {
		hud_button(renderer, layout.character, nil, "PERSONAGGIO", m8_control_enabled(renderer, room, .Character), GOTHIC_PAPER)
	}
	if !hologram { draw_m8_active_bar(renderer, room) }
	if room.qte.kind != .None { draw_tactical_defense_hud(renderer, room) }
	if paused {
		rl.DrawRectangle(0, 0, c.int(renderer.canvas_width), c.int(renderer.canvas_height), {3, 7, 12, 185})
		px, py := renderer.canvas_width*0.5-120, renderer.canvas_height*0.5-43
		hud_frame({px, py, 240, 86}, GOTHIC_BLUE)
		gothic_text(renderer, "PAUSA", px+78, py+12, 32, GOTHIC_PAPER)
		gothic_text(renderer, "P PER RIPRENDERE", px+48, py+56, 16, GOTHIC_MUTED)
	}
}

// The dash is a key, not a button: a keycap, its cost and a recharge meter.
draw_tactical_dodge_chip :: proc(renderer: ^Renderer, room: ^game.Room, bounds: rl.Rectangle) {
	s := &room.player.tactical
	recovering := game.tactical_is_recovering(room)
	ready := game.tactical_dodge_ready(room) && !recovering
	recovery := max(0, s.dodge_recovery-(1 if room.tactical_pulse.pending else 0))
	detail := fmt.ctprintf("-%.0fs", game.TACTICAL_DODGE_SECONDS) if ready else fmt.ctprintf("PRONTA FRA %d", recovery)
	if recovering { detail = "IN RECUPERO" }
	rl.DrawRectangleRec(bounds, {12, 18, 27, 200})
	rl.DrawRectangleLinesEx(bounds, 1, {28, 38, 52, 255})
	cap_bounds := rl.Rectangle{bounds.x+4, bounds.y+4, 40, bounds.height-8}
	rl.DrawRectangleRec(cap_bounds, GOTHIC_BLUE if ready else GOTHIC_STEEL)
	gothic_text_fit(renderer, "SHIFT", {cap_bounds.x+3, cap_bounds.y+(cap_bounds.height-15)*0.5, cap_bounds.width-5, 16}, 10, GOTHIC_INK)
	left := cap_bounds.x+cap_bounds.width+7
	gothic_text_fit(renderer, "SCHIVA", {left, bounds.y+1, bounds.x+bounds.width-left-6, 14}, 12, GOTHIC_PAPER if ready else GOTHIC_MUTED)
	gothic_text_fit(renderer, detail, {left, bounds.y+13, bounds.x+bounds.width-left-6, 12}, 10, GOTHIC_BLUE if ready else GOTHIC_MUTED)
}

draw_tactical_defense_hud :: proc(renderer: ^Renderer, room: ^game.Room) {
	q := &room.qte
	x, y := f32(14), TACTICAL_HUD_HEIGHT+13
	hud_frame({x, y, 237, 143}, GOTHIC_RED)
	gothic_text_fit(renderer, fmt.ctprintf("%s / %.2fs", "DIAGONALE" if q.kind == .Diagonal else "DIFENDITI", q.remaining), {x+12, y+8, 213, 24}, 18, GOTHIC_PAPER)
	hud_bar({x+12, y+36, 213, 6}, q.remaining/room.player.tactical.config.qte_seconds, GOTHIC_RED)
	if !q.selected {
		line := y+50
		if .Block in q.defenses { hud_button(renderer, {x+12, line, 213, 24}, "J", "BLOCK   K: PARRY", true, GOTHIC_RED); line += 29 }
		if .Deflect in q.defenses { hud_button(renderer, {x+12, line, 213, 24}, "L", "DEVIAZIONE", true, GOTHIC_RED); line += 29 }
		if .Dodge in q.defenses { hud_button(renderer, {x+12, line, 213, 24}, "I", "SCHIVA, POI WASD", true, GOTHIC_RED) }
	} else if q.kind == .Defense && q.mode == .Dodge {
		gothic_text(renderer, "WASD: SCEGLI LA CELLA", x+12, y+66, 16, GOTHIC_PAPER)
	} else {
		keys := [?]string{"W", "D", "S", "A"}
		gothic_text(renderer, "PREMI", x+12, y+50, 14, GOTHIC_MUTED)
		gothic_button(renderer, {x+12, y+78, 213, 44}, fmt.ctprintf("%s", keys[int(q.keys[q.progress])]), fmt.ctprintf("%d / %d", q.progress+1, q.length))
	}
}
