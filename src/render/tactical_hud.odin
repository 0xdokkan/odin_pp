package render

import "core:c"
import "core:fmt"
import rl "vendor:raylib"
import game "../game"

TACTICAL_HUD_HEIGHT :: f32(88)

tactical_refocus_bounds :: proc(renderer: ^Renderer) -> rl.Rectangle {
	return {renderer.canvas_width-151, 43, 137, 25}
}
tactical_map_controls_bounds :: proc(renderer: ^Renderer) -> rl.Rectangle {
	return {renderer.canvas_width-151, 12, 137, 25}
}
tactical_phase_bounds :: proc(renderer: ^Renderer) -> rl.Rectangle {
	return {renderer.canvas_width*0.5-155, 10, 310, 71}
}

// Small separate surfaces preserve the space between health, clock and controls.
// This same geometry is shared with pointer hitboxes and scene framing.
tactical_hud_panel :: proc(bounds: rl.Rectangle, accent: rl.Color = GOTHIC_STEEL) {
	rl.DrawRectangleRec({bounds.x+2, bounds.y+3, bounds.width, bounds.height}, {3, 7, 12, 120})
	rl.DrawRectangleRec(bounds, {14, 21, 31, 225})
	rl.DrawRectangleRec({bounds.x, bounds.y, 2, bounds.height}, accent)
	rl.DrawRectangleRec({bounds.x+2, bounds.y, bounds.width-2, 1}, {67, 85, 110, 150})
	rl.DrawRectangleRec({bounds.x+2, bounds.y+bounds.height-1, bounds.width-2, 1}, {4, 9, 15, 190})
}

draw_tactical_status :: proc(renderer: ^Renderer, room: ^game.Room) {
	v := renderer_status_view(renderer, room)
	tactical_hud_panel({14, 12, 270, 47}, GOTHIC_BLUE)
	gothic_text_fit(renderer, fmt.ctprintf("HP %d/%d", v.health, v.max_health), {24, 16, 113, 28}, 24, GOTHIC_PAPER)
	bar := rl.Rectangle{146, 23, 125, 10}
	rl.DrawRectangleRec(bar, GOTHIC_INK)
	rl.DrawRectangleRec({bar.x+1, bar.y+1, bar.width-2, bar.height-2}, GOTHIC_DARK_RED)
	health_width := (bar.width-2)*clamp(f32(v.health)/f32(max(i32(1), v.max_health)), f32(0), f32(1))
	rl.DrawRectangleRec({bar.x+1, bar.y+1, health_width, bar.height-2}, GOTHIC_RED)
	rl.DrawRectangleRec({bar.x+1, bar.y+1, health_width, 2}, {228, 95, 103, 255})
	for mark in 1..<10 { rl.DrawRectangleRec({bar.x+f32(mark)*(bar.width/10), bar.y+1, 1, bar.height-2}, {13, 17, 24, 140}) }
	gothic_text_fit(renderer, fmt.ctprintf("ORO %d", v.gold), {25, 40, 104, 17}, 12, GOTHIC_MUTED)
	phase := "STANZA LIBERATA" if v.phase == .Loot || v.phase == .Complete else fmt.ctprintf("NEMICI %d", v.enemy_count)
	gothic_text_fit(renderer, phase, {147, 40, 127, 17}, 12, GOTHIC_BLUE if v.phase == .Loot else GOTHIC_MUTED)
	status_width := f32(270)/f32(max(1, v.statuses.count))
	for status, index in v.statuses.items[:v.statuses.count] {
		label: string
		switch status.kind {
		case .Poison: label = "VELENO"
		case .Shield: label = "SCUDO"
		case .Thorns: label = "SPINE"
		case .Afterimage: label = "OMBRA"
		case .Stagger: label = "STORDITO"
		case .Survey: label = "VISTA"
		}
		if v.statuses.count > 3 {
			switch status.kind {
			case .Poison: label = "VEL"
			case .Shield: label = "SCU"
			case .Thorns: label = "SPI"
			case .Afterimage: label = "OMB"
			case .Stagger: label = "STO"
			case .Survey: label = "VIS"
			}
		}
		accent := GOTHIC_BLUE
		switch status.kind {
		case .Poison, .Thorns: accent = {148, 166, 116, 255}
		case .Stagger: accent = GOTHIC_RED
		case .Afterimage: accent = {164, 144, 183, 255}
		case .Shield, .Survey:
		}
		bounds := rl.Rectangle{14+f32(index)*status_width, 65, status_width-3, 17}
		rl.DrawRectangleRec(bounds, {14, 21, 31, 225})
		rl.DrawRectangleRec({bounds.x, bounds.y, 1, bounds.height}, accent)
		gothic_text_fit(renderer, fmt.ctprintf("%s %d / %ds", label, status.potency, status.remaining_pulses), {bounds.x+4, bounds.y, bounds.width-6, 17}, 12, accent)
	}
}

draw_tactical_hud :: proc(renderer: ^Renderer, room: ^game.Room, paused, hologram: bool) {
	s := &room.player.tactical
	combat := renderer.tactical.snapshot.phase == .Combat
	busy := renderer_blocks_player_input(renderer)
	recovering := game.tactical_is_recovering(room)
	cinematic := presentation_time_policy(&renderer.timeline) == .Cinematic
	bounds := tactical_phase_bounds(renderer)
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
	else if busy { label = "AZIONE" }
	// The pulse continues during casting; cinematic dice and QTE own a full pause.
	timed := combat
	accent := GOTHIC_RED if timed && s.remaining <= 5 else GOTHIC_BLUE
	if recovering { accent = {218, 169, 90, 255} }
	tactical_hud_panel(bounds, accent)
	gothic_text_fit(renderer, fmt.ctprintf("PULSE %d", min(s.cycle, max(int)-1)+1), {x+12, y+7, 91, 22}, 16, GOTHIC_MUTED)
	gothic_text_fit(renderer, label, {x+107, y+7, 106, 22}, 18, GOTHIC_PAPER)
	if timed {
		gothic_text_fit(renderer, fmt.ctprintf("%.1fs", s.remaining), {x+width-83, y+4, 72, 27}, 24, accent)
	}
	budget := max(f32(1), f32(s.budget))
	if recovering { budget = game.TACTICAL_RECOVERY_SECONDS }
	rl.DrawRectangleRec({x+12, y+35, width-24, 4}, GOTHIC_STEEL)
	if timed {
		rl.DrawRectangleRec({x+12, y+35, (width-24)*clamp(s.remaining/budget, f32(0), f32(1)), 4}, accent)
	} else if !combat {
		rl.DrawRectangleRec({x+12, y+35, width-24, 2}, GOTHIC_BLUE)
	}
	status := fmt.ctprintf("PASSO / ATTACCO -%.0fs / RECUPERO %.0fs", game.TACTICAL_MOVE_SECONDS, game.TACTICAL_RECOVERY_SECONDS)
	if busy { status = "AZIONE / I NEMICI CONTINUANO" }
	if game.tactical_is_casting(room) { status = fmt.ctprintf("LANCIO %.1fs / NEMICI SOSPESI", s.cast_remaining) }
	if cinematic { status = "CINEMATICA / TEMPO SOSPESO" }
	if recovering { status = "MUOVITI / CARTE E ATTACCHI IN RECUPERO" }
	if room.qte.kind != .None { status = "QTE / TEMPO DEL PULSE SOSPESO" }
	if !combat { status = "RACCOGLI IL BOTTINO / RAGGIUNGI L'USCITA" }
	if hologram && combat && room.qte.kind == .None {
		status = "MAPPA APERTA / RECUPERO IN CORSO" if recovering else "MAPPA APERTA / IL TEMPO SCORRE"
	}
	gothic_text_fit(renderer, status, {x+12, y+46, width-24, 18}, 12, accent if hologram else GOTHIC_MUTED)
	gothic_button(renderer, tactical_map_controls_bounds(renderer), "TAB", "CHIUDI" if hologram else "MAPPA", room.qte.kind == .None)
	if !hologram && combat {
		gothic_button(renderer, tactical_refocus_bounds(renderer), "F", fmt.ctprintf("REFOCUS -%.0fs", game.TACTICAL_REFOCUS_SECONDS), refocus_button_is_enabled(renderer))
		ready := game.tactical_dodge_ready(room) && !recovering
		recovery := max(0, s.dodge_recovery-(1 if room.tactical_pulse.pending else 0))
		text := fmt.ctprintf("SHIFT: SCHIVA -%.0fs", game.TACTICAL_DODGE_SECONDS) if ready else fmt.ctprintf("SCHIVA: %ds", recovery)
		if recovering { text = "SCHIVA: IN RECUPERO" }
		gothic_text_fit(renderer, text, {renderer.canvas_width-149, 73, 135, 15}, 10, GOTHIC_BLUE if ready else GOTHIC_MUTED)
	}
	if !hologram { draw_m8_active_bar(renderer, room) }
	if room.qte.kind != .None { draw_tactical_defense_hud(renderer, room) }
	if paused {
		rl.DrawRectangle(0, 0, c.int(renderer.canvas_width), c.int(renderer.canvas_height), {3, 7, 12, 185})
		px, py := renderer.canvas_width*0.5-120, renderer.canvas_height*0.5-43
		tactical_hud_panel({px, py, 240, 86}, GOTHIC_BLUE)
		gothic_text(renderer, "PAUSA", px+78, py+12, 32, GOTHIC_PAPER)
		gothic_text(renderer, "P PER RIPRENDERE", px+48, py+56, 16, GOTHIC_MUTED)
	}
}

draw_tactical_defense_hud :: proc(renderer: ^Renderer, room: ^game.Room) {
	q := &room.qte
	x, y := f32(14), TACTICAL_HUD_HEIGHT+13
	tactical_hud_panel({x, y, 237, 143}, GOTHIC_RED)
	gothic_text_fit(renderer, fmt.ctprintf("%s / %.2fs", "DIAGONALE" if q.kind == .Diagonal else "DIFENDITI", q.remaining), {x+12, y+8, 213, 24}, 18, GOTHIC_PAPER)
	rl.DrawRectangleRec({x+12, y+37, 213, 3}, GOTHIC_STEEL)
	rl.DrawRectangleRec({x+12, y+37, 213*clamp(q.remaining/room.player.tactical.config.qte_seconds, f32(0), f32(1)), 3}, GOTHIC_RED)
	if !q.selected {
		line := y+49
		if .Block in q.defenses { gothic_text(renderer, "J BLOCK / K PARRY", x+12, line, 18, GOTHIC_PAPER); line += 27 }
		if .Deflect in q.defenses { gothic_text(renderer, "L DEVIAZIONE", x+12, line, 18, GOTHIC_PAPER); line += 27 }
		if .Dodge in q.defenses { gothic_text(renderer, "I SCHIVA > WASD", x+12, line, 18, GOTHIC_PAPER) }
	} else if q.kind == .Defense && q.mode == .Dodge {
		gothic_text(renderer, "WASD: SCEGLI LA CELLA", x+12, y+66, 16, GOTHIC_PAPER)
	} else {
		keys := [?]string{"W", "D", "S", "A"}
		gothic_text(renderer, "PREMI", x+12, y+50, 14, GOTHIC_MUTED)
		gothic_button(renderer, {x+12, y+78, 213, 44}, fmt.ctprintf("%s", keys[int(q.keys[q.progress])]), fmt.ctprintf("%d / %d", q.progress+1, q.length))
	}
}
