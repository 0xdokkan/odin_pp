package render

import "core:fmt"
import "core:math"
import rl "vendor:raylib"
import game "../game"

TACTICAL_HUD_HEIGHT :: f32(84)

@(private)
tactical_refocus_bounds :: proc(renderer: ^Renderer) -> rl.Rectangle {
	return tactical_hud_layout(renderer).refocus
}
@(private)
tactical_map_controls_bounds :: proc(renderer: ^Renderer) -> rl.Rectangle {
	return tactical_hud_layout(renderer).map_button
}
@(private = "file")
tactical_phase_bounds :: proc(renderer: ^Renderer) -> rl.Rectangle {
	return tactical_hud_layout(renderer).pulse
}

// Kept for callers that tint a plate by state.
@(private)
tactical_hud_panel :: proc(bounds: rl.Rectangle, accent: rl.Color = GOTHIC_STEEL) {
	hud_frame(bounds, accent)
}

@(private)
tactical_status_label :: proc(kind: game.Status_Kind, short: bool) -> (label: string, accent: rl.Color) {
	accent = GOTHIC_BLUE
	switch kind {
	case .Poison: label, accent = "VELENO", HUD_VENOM
	case .Shield: label = "SCUDO"
	case .Thorns: label, accent = "SPINE", HUD_VENOM
	case .Afterimage: label, accent = "SCIA", HUD_SHADE
	case .Stagger: label, accent = "STORDITO", GOTHIC_RED
	case .Survey: label = "VISTA"
	case .Burn: label, accent = "BRUCIATURA", HUD_EMBER
	case .Slow: label, accent = "RALLENTAMENTO", HUD_FROST
	// The player's charges (game/player_charges.odin).
	case .Deflect: label, accent = "RIFLESSO", HUD_FROST
	case .Arrows: label, accent = "FRECCE", HUD_AMBER
	case .Fate: label, accent = "DESTINO", HUD_SHADE
	case .Venom_Blade: label, accent = "LAMA", HUD_VENOM
	}
	if short && len(label) > 3 { label = label[:3] }
	return
}

// A stack status shows its stacks; the others their potency and seconds.
// DESTINO also names the die its loaded bumps roll (`die`, its sides: DESTINO
// 3 d8), when it is given one.
tactical_status_chip_text :: proc(status: game.Status, short: bool, die := i32(0)) -> cstring {
	label, _ := tactical_status_label(status.kind, short)
	if status.kind == .Fate && die > 0 { return fmt.ctprintf("%s %d %s", label, status.potency, die_label(die)) }
	if game.status_kind_stacks(status.kind) { return fmt.ctprintf("%s %d", label, status.potency) }
	return fmt.ctprintf("%s %d / %ds", label, status.potency, status.remaining_pulses)
}

// The order of the HUD's status chips (the first three show, the rest are a
// count): what bites the player first (VELENO, BRUCIATURA), so that it never
// hides behind the count, then his charges (what his cards loaded him with:
// RIFLESSO, FRECCE, DESTINO, LAMA), then the rest, each group as it was gained.
@(private)
tactical_status_chip_order :: proc(statuses: ^game.Status_Set) -> (ordered: game.Status_Set) {
	group :: proc(kind: game.Status_Kind) -> int {
		if kind == .Poison || kind == .Burn { return 0 }
		return 1 if game.status_kind_is_player_charge(kind) else 2
	}
	for rank in 0..<3 {
		for status in statuses.items[:clamp(statuses.count, 0, len(statuses.items))] {
			if group(status.kind) != rank { continue }
			ordered.items[ordered.count] = status
			ordered.count += 1
		}
	}
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
	chips := tactical_status_chip_layout(renderer, room)
	for index in 0..<chips.shown {
		hud_chip(renderer, chips.bounds[index], chips.texts[index], chips.accents[index])
	}
	if chips.more > 0 {
		gothic_text_fit(renderer, fmt.ctprintf("+%d", chips.more), chips.counter, 12, GOTHIC_MUTED)
	}
}

// The status chips under VITA (draw_tactical_status): the first three of
// tactical_status_chip_order, their words short when the chips are narrow,
// and a count of the rest.
Tactical_Status_Chips :: struct {
	bounds: [3]rl.Rectangle,
	texts: [3]cstring,
	accents: [3]rl.Color,
	shown, more: int,
	counter: rl.Rectangle,
}

// The text room of a chip: its width less this (hud_chip).
HUD_CHIP_TEXT_MARGIN :: f32(9)

// The chips share their room evenly, as wide as one another up to 96, while
// every text holds so; when one would not (DESTINO 3 d20 beside two more and
// a count), each is as wide as its own text asks and the rest of the room is
// shared out, if that holds them all. While the Pinball's ball rolls its chip
// (PINBALL 14s x5: pinball.odin) comes right after the bites.
tactical_status_chip_layout :: proc(renderer: ^Renderer, room: ^game.Room) -> (chips: Tactical_Status_Chips) {
	v := renderer_status_view(renderer, room)
	b := tactical_hud_layout(renderer).vitals
	ordered := tactical_status_chip_order(&v.statuses)
	_, ball := pinball_chip(room, false)
	count := ordered.count+(1 if ball else 0)
	if count == 0 { return }
	// The ball's place among the chips: after VELENO and BRUCIATURA.
	bites := 0
	for status in ordered.items[:ordered.count] { if status.kind == .Poison || status.kind == .Burn { bites += 1 } }
	left := b.x+72
	row := b.y+b.height-22
	room_width := b.x+b.width-8-left
	chips.shown = min(count, 3)
	chips.more = count-chips.shown
	available := room_width-f32(chips.shown-1)*4-(26 if chips.more > 0 else 0)
	chip := min(f32(96), available/f32(chips.shown))
	short := chip < 80
	widths: [3]f32
	needed: f32
	even := true
	for index in 0..<chips.shown {
		if ball && index == bites {
			chips.accents[index] = PINBALL_STEEL_LIGHT
			chips.texts[index], _ = pinball_chip(room, short)
		} else {
			status := ordered.items[index-1 if ball && index > bites else index]
			_, chips.accents[index] = tactical_status_label(status.kind, short)
			chips.texts[index] = tactical_status_chip_text(status, short, v.fate_sides)
		}
		widths[index] = math.ceil(gothic_text_width(renderer, chips.texts[index], 12))+HUD_CHIP_TEXT_MARGIN
		needed += widths[index]
		if widths[index] > chip { even = false }
	}
	spare := (available-needed)/f32(chips.shown)
	x := left
	for index in 0..<chips.shown {
		width := chip if even || spare < 0 else f32(int(widths[index]+spare))
		chips.bounds[index] = {x, row-1, width, 18}
		x += width+4
	}
	chips.counter = {x, row, 24, 17}
	return
}

draw_tactical_hud :: proc(renderer: ^Renderer, room: ^game.Room, paused, hologram: bool) {
	// FIRST PERSON SHOOTER: the AK, the crosshair and the countdown under the
	// plates (first_person.odin).
	draw_first_person_overlay(renderer, room)
	s := &room.player.tactical
	fps := game.tactical_first_person_active(room)
	combat := renderer.tactical.snapshot.phase == .Combat
	busy := renderer_blocks_player_input(renderer)
	recovering := game.tactical_is_recovering(room)
	stunned := game.tactical_is_stunned(room)
	shadow := game.tactical_shadow_active(room)
	// LAZZO: the foe swung round the player once the throw is over (lasso.odin).
	lasso := game.tactical_lasso_active(room) && !game.tactical_is_casting(room)
	cinematic := presentation_time_policy(&renderer.timeline) == .Cinematic
	layout := tactical_hud_layout(renderer)
	bounds := layout.pulse
	x, y, width := bounds.x, bounds.y, bounds.width
	label: cstring = "AGISCI"
	switch s.phase {
	case .Decision, .Shadow:
	case .Recovery: label = "RECUPERO"
	case .Resolving: label = "AZIONE"
	case .Stunned: label = "STORDITO"
	}
	// MOVIMENTO OMBRA: the window waits, frozen, while the shadow walks. The
	// room cleared: exploring it, or fishing it (fishing.odin).
	if !combat { label = "PESCA" if fishing_in_progress(renderer) else "ESPLORA" }
	else if shadow { label = "OMBRA" }
	else if room.qte.kind != .None { label = "DIFESA" }
	else if recovering { label = "RECUPERO" }
	else if stunned { label = "STORDITO" }
	else if cinematic { label = "DADI" }
	else if game.tactical_is_casting(room) { label = "LANCIO" }
	else if lasso { label = "LAZZO" }
	else if busy || game.tactical_player_busy(room) { label = "AZIONE" }
	// The pulse continues during casting; cinematic dice and QTE own a full pause.
	timed := combat && !s.config.expedition
	accent := GOTHIC_RED if timed && s.remaining <= 5 else GOTHIC_BLUE
	if recovering { accent = HUD_AMBER }
	if stunned { accent = GOTHIC_RED }
	if shadow { accent = HUD_SHADE }
	if lasso && combat && room.qte.kind == .None && !recovering && !stunned { accent = HUD_AMBER }
	hud_frame(bounds, accent)
	gothic_text_fit(renderer, label, {x+12, y+5, 150, 24}, 18, GOTHIC_PAPER)
	sub := fmt.ctprintf("PULSE %d", min(s.cycle, max(int)-1)+1)
	if s.config.expedition { sub = fmt.ctprintf("BATTITO %d", s.encounter_beats+1) }
	// The window's own seconds wait, shown still, while the shadow's run.
	if shadow { sub = fmt.ctprintf("FERMO %.1fs", s.remaining) }
	// The turn the rope is in.
	if lasso { sub = fmt.ctprintf("GIRO %d", room.lasso.turns+1) }
	gothic_text_fit(renderer, sub, {x+12, y+26, 90, 14}, 10, GOTHIC_MUTED)
	if combat {
		timer := fmt.ctprintf("%.1fs", s.shadow_remaining if shadow else s.remaining)
		if s.config.expedition && !shadow { timer = "" }
		timer_width := gothic_text_width(renderer, timer, 24)
		// The tick: a lamp fills toward each whole second and flares gold in
		// the window where moves, bumps and cards turn critical. In the shadow,
		// the shadow's own beats (a two-key step on one goes diagonally); after
		// its last one the lamp rests.
		approach, on_beat := game.tactical_beat_glow(room)
		if shadow && !on_beat && game.tactical_shadow_elapsed(s) >= f32(game.TACTICAL_SHADOW_BEATS) { approach = 0 }
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
	if stunned { budget = max(f32(1), s.stun_duration) }
	meter := rl.Rectangle{x+104, y+29, width-116, 7}
	if shadow { hud_bar(meter, s.shadow_remaining/max(s.shadow_duration, 0.001), HUD_SHADE, int(s.shadow_duration+0.5)) }
	else if s.config.expedition && combat { hud_bar(meter, f32(s.encounter_beats%game.EXPEDITION_DRAW_BEATS)/f32(game.EXPEDITION_DRAW_BEATS), GOTHIC_BLUE, 4) }
	else if timed { hud_bar(meter, s.remaining/budget, accent, int(min(budget, 30))) }
	else { hud_bar(meter, 1, GOTHIC_BLUE if !combat else GOTHIC_STEEL) }
	// A timed action: a thin gold line drains as it plays out; a shadow's
	// step, a violet one.
	if game.tactical_shadow_step_busy(room) {
		left := clamp(s.shadow_step_remaining/game.TACTICAL_SHADOW_STEP_SECONDS, 0, 1)
		rl.DrawRectangleRec({meter.x, meter.y+meter.height+2, meter.width*left, 2}, SHADOW_RIM)
	} else if game.tactical_player_busy(room) && s.action_duration > 0 && s.action_remaining > 0 {
		left := clamp(s.action_remaining/s.action_duration, 0, 1)
		rl.DrawRectangleRec({meter.x, meter.y+meter.height+2, meter.width*left, 2}, TACTICAL_FEEDBACK_CRITICAL)
	}
	// One context line, only when it says something the plate does not.
	status: cstring
	if s.config.expedition && combat { status = fmt.ctprintf("PESCA FRA %d BATTITI / CRITICO SUL BATTITO", game.EXPEDITION_DRAW_BEATS-s.encounter_beats%game.EXPEDITION_DRAW_BEATS) }
	if busy { status = "I NEMICI CONTINUANO" }
	if game.tactical_player_busy(room) { status = fmt.ctprintf("AZIONE %.1fs / I NEMICI CONTINUANO", s.action_remaining) }
	if game.tactical_is_casting(room) { status = fmt.ctprintf("LANCIO %.1fs / NEMICI SOSPESI", s.cast_remaining) }
	if cinematic { status = "TEMPO SOSPESO" }
	if recovering { status = "MUOVITI / CARTE IN RECUPERO" }
	if stunned { status = "SOLO CARTE" }
	// Behind the player's eyes, how the AK and the steps are worked.
	if fps && !cinematic { status = FIRST_PERSON_HUD_STATUS }
	// The rope holds through a window's end and a stun: the pivot stays put.
	if lasso && !cinematic { status = lasso_hud_status(room) }
	if shadow { status = "MONDO FERMO / SOLO PASSI / DIAGONALE SUL BATTITO" }
	if room.qte.kind != .None { status = "PULSE SOSPESO" }
	if !combat { status = "BOSS / ESTRAI IL TUO ZAINO" if s.config.expedition else fishing_hud_status(renderer, room) }
	if hologram && combat && room.qte.kind == .None { status = "MAPPA APERTA / IL TEMPO SCORRE" }
	objective := "MEMORIA APERTA" if s.config.expedition && !combat else tactical_hud_objective(renderer, room)
	objective_width := gothic_text_width(renderer, objective, 10)
	gothic_text(renderer, objective, x+width-12-objective_width, y+bounds.height-17, 10, GOTHIC_BLUE if !combat else GOTHIC_MUTED)
	if status != nil {
		gothic_text_fit(renderer, status, {x+12, y+bounds.height-18, tactical_hud_status_room(renderer, objective), 14}, 10,
			accent if hologram || recovering else GOTHIC_MUTED)
	}
	// COMANDI: a 2x2 grid under the right column. MOSTRA EFFETTO's board is a
	// film: it has no commands to give.
	if !renderer.tactical.showcase {
		hud_frame(layout.commands, GOTHIC_STEEL)
		// No map behind the player's eyes.
		hud_button(renderer, layout.map_button, "TAB", "CHIUDI" if hologram else "MAPPA", room.qte.kind == .None && !fps)
		if !hologram && combat {
			hud_button(renderer, layout.refocus, "F", fmt.ctprintf("REFOCUS -%.0fs", game.TACTICAL_REFOCUS_SECONDS), refocus_button_is_enabled(renderer))
			draw_tactical_dodge_chip(renderer, room, layout.dodge)
		}
		if !hologram && m8_control_visible(room, .Character) {
			hud_button(renderer, layout.character, nil, "PERSONAGGIO", m8_control_enabled(renderer, room, .Character), GOTHIC_PAPER)
		}
	}
	if !hologram && !fps { draw_m8_active_bar(renderer, room) }
	if room.qte.kind != .None { draw_tactical_defense_hud(renderer, room) }
	if paused { draw_pause_menu(renderer, renderer.tactical.pause_hovered, renderer.tactical.pause_menu) }
}

// The plate's objective, at the right of its foot: the room's foes, or with
// the shrinking window this window's length (between two windows, the one
// coming's) and the cards counted toward the next won second, with any already
// won. In the shadow, while the Lazzo spins and behind the player's eyes no
// card can be played: the short one keeps the line's room for their rule.
tactical_hud_objective :: proc(renderer: ^Renderer, room: ^game.Room) -> cstring {
	s := &room.player.tactical
	v := renderer_status_view(renderer, room)
	if renderer.tactical.snapshot.phase != .Combat { return "STANZA LIBERATA" }
	lasso := game.tactical_lasso_active(room) && !game.tactical_is_casting(room)
	if !s.config.shrinking_window || game.tactical_shadow_active(room) || lasso ||
	   game.tactical_first_person_active(room) {
		return tactical_hud_foes_objective(v.enemy_count)
	}
	window := s.next_budget if (game.tactical_is_recovering(room) || game.tactical_is_stunned(room)) && s.next_budget > 0 else s.budget
	won := fmt.ctprintf(" +%ds", s.won_seconds) if s.won_seconds > 0 else ""
	return fmt.ctprintf("MAX %ds / CARTE %d/%d%s / NEMICI %d", window, s.cards_toward_second,
		game.TACTICAL_CARDS_PER_SECOND, won, v.enemy_count)
}

tactical_hud_foes_objective :: proc(foes: int) -> cstring {
	return fmt.ctprintf("NEMICI %d", foes)
}

// The room the plate's context line has beside its `objective`.
tactical_hud_status_room :: proc(renderer: ^Renderer, objective: cstring) -> f32 {
	return tactical_hud_layout(renderer).pulse.width-36-gothic_text_width(renderer, objective, 10)
}

// The dash is a key, not a button: a keycap, its cost and a recharge meter.
@(private = "file")
draw_tactical_dodge_chip :: proc(renderer: ^Renderer, room: ^game.Room, bounds: rl.Rectangle) {
	s := &room.player.tactical
	recovering := game.tactical_is_recovering(room)
	stunned := game.tactical_is_stunned(room)
	shadow := game.tactical_shadow_active(room)
	ready := game.tactical_dodge_ready(room) && !recovering && !stunned && !shadow
	recovery := max(0, s.dodge_recovery-(1 if room.tactical_pulse.pending else 0))
	detail := fmt.ctprintf("-%.0fs", game.TACTICAL_DODGE_SECONDS) if ready else fmt.ctprintf("PRONTA FRA %d", recovery)
	if recovering { detail = "IN RECUPERO" }
	if stunned { detail = "STORDITO" }
	if shadow { detail = "OMBRA" }
	rl.DrawRectangleRec(bounds, {12, 18, 27, 200})
	rl.DrawRectangleLinesEx(bounds, 1, {28, 38, 52, 255})
	cap_bounds := rl.Rectangle{bounds.x+4, bounds.y+4, 40, bounds.height-8}
	rl.DrawRectangleRec(cap_bounds, GOTHIC_BLUE if ready else GOTHIC_STEEL)
	gothic_text_fit(renderer, "SHIFT", {cap_bounds.x+3, cap_bounds.y+(cap_bounds.height-15)*0.5, cap_bounds.width-5, 16}, 10, GOTHIC_INK)
	left := cap_bounds.x+cap_bounds.width+7
	gothic_text_fit(renderer, "SCHIVA", {left, bounds.y+1, bounds.x+bounds.width-left-6, 14}, 12, GOTHIC_PAPER if ready else GOTHIC_MUTED)
	gothic_text_fit(renderer, detail, {left, bounds.y+13, bounds.x+bounds.width-left-6, 12}, 10, GOTHIC_BLUE if ready else GOTHIC_MUTED)
}

@(private = "file")
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
		if .Dodge in q.defenses { hud_button(renderer, {x+12, line, 213, 24}, "E", "SCHIVA, POI WASD", true, GOTHIC_RED) }
	} else if q.kind == .Defense && q.mode == .Dodge {
		gothic_text(renderer, "WASD: SCEGLI LA CELLA", x+12, y+66, 16, GOTHIC_PAPER)
	} else {
		keys := [?]string{"W", "D", "S", "A"}
		gothic_text(renderer, "PREMI", x+12, y+50, 14, GOTHIC_MUTED)
		gothic_button(renderer, {x+12, y+78, 213, 44}, fmt.ctprintf("%s", keys[int(q.keys[q.progress])]), fmt.ctprintf("%d / %d", q.progress+1, q.length))
	}
}
