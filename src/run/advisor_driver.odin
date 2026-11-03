package run

import "base:runtime"
import "core:fmt"
import advisor "../advisor"
import game "../game"
import grid "../engine/grid"
import render "../render"

// THE IA'S PILOT (docs/piano-ia.md, Fasi 2 e 4). Every frame of a fight the tactical controller calls it. While the
// IA's card runs, the search runs on a thread of its own (advisor.Worker): when the situation changes the pilot
// photographs the real room (only read, a few microseconds) and hands it over; every frame it reads the newest advice
// the worker has, never waiting for it, and gives it to the board's marks. Behind the eyes of a view or with the IA's
// seconds over the marks go and the worker sleeps; out of the fight it is closed and its memory given back.
//
// When to take a new root:
// - at once, when what a player sees changes (the discrete fingerprint: a step, a blow, a beat, an intent, the hand,
//   the defence keys). If the change is a first move the worker already tried, its best reply is the advice in the same
//   frame (thinking ahead);
// - when only the world's seconds ran on: after ADVISOR_FRESH_SECONDS if the search of the root is over (the plan's
//   tenth of a second), and after ADVISOR_ROOT_SECONDS anyway. A search still going is not thrown away every tenth of a
//   second: its second round, the one thinking ahead needs, takes about a third of a second with the cards.
ADVISOR_FRESH_SECONDS :: f32(0.1)
ADVISOR_ROOT_SECONDS :: f32(1)
// Without the worker (a thread that could not start), the search runs here, this much work a frame: a node is a quarter
// to half a millisecond in the IA's arena (-o:speed), so two or three milliseconds.
ADVISOR_FRAME_WORK :: 3

Advisor_Pilot :: struct {
	worker: ^advisor.Worker,
	// The search of the frame's own slices, only when the worker could not start.
	sliced: ^advisor.Search,
	root, generation: u64,
	since_root: f32,
	// The game's state the current root was taken with (advisor_context.odin), as one number.
	context_key: u64,
	// The advice shown, and how long it has been.
	shown: advisor.Advice,
	shown_age: f32,
	// THE HELD ADVICE (the user's rule, 3 November 2026): once shown, an advice stays until the player's next action
	// (`acted`, set by the game's own command: advisor_note_action). Its only exception: a foe announces a blow on the
	// player's cell (`danger`, a new one since the advice was held); and an advice that can no longer be done (the foe
	// dead, the card gone, the cell taken, the player moved by a blow) gives way too.
	acted: bool,
	// The action's new root is taken (once: then the pilot waits for its advice).
	acted_rooted: bool,
	held_danger: u64,
	held_at: grid.Position,
	// The warning: its text and its seconds left.
	warning: cstring,
	warning_left: f32,
}

// THE WARNING (docs/piano-ia.md, «L'avviso»): the player's own first move, one the IA had tried, loses at least this much
// more life by the horizon than the advice (or may die where the advice does not).
ADVISOR_WARNING_LIFE :: f32(2)

// One pilot a thread (the tests play rooms side by side), in the process's own memory.
@(private = "file", thread_local)
advisor_pilot: ^Advisor_Pilot

// The pilot closed: its worker stopped and waited for (it stops between two nodes), its memory given back.
advisor_pilot_release :: proc() {
	p := advisor_pilot
	if p == nil { return }
	if p.worker != nil { advisor.worker_stop(p.worker) }
	if p.sliced != nil { advisor.search_destroy(p.sliced); free(p.sliced, runtime.heap_allocator()) }
	free(p, runtime.heap_allocator())
	advisor_pilot = nil
}

@(private = "file")
advisor_pilot_open :: proc() -> ^Advisor_Pilot {
	heap := runtime.heap_allocator()
	p := new(Advisor_Pilot, heap)
	if p == nil { return nil }
	p.worker = advisor.worker_start()
	if p.worker == nil {
		p.sliced = new(advisor.Search, heap)
		if p.sliced == nil || !advisor.search_init(p.sliced) { free(p.sliced, heap); free(p, heap); return nil }
	}
	return p
}

drive_advisor :: proc(room: ^game.Room, renderer: ^render.Renderer, dt: f32) {
	shown := render.Advice_View{}
	defer renderer.tactical.advice = shown
	if room == nil || room.player == nil || room.phase != .Combat { advisor_pilot_release(); return }
	if !game.ia_active(room) {
		if advisor_pilot != nil { advisor_pilot.shown, advisor_pilot.root, advisor_pilot.acted = {}, 0, false }
		return
	}
	if advisor_pilot == nil { advisor_pilot = advisor_pilot_open() }
	p := advisor_pilot
	if p == nil { return }
	fingerprint := advisor.discrete_fingerprint(room)
	// The game's state changed (the progress, a heal, the sleepers): a new root too.
	game_context := advisor_game_context
	if key := advisor_context_key(game_context); key != p.context_key { p.context_key, p.since_root = key, ADVISOR_ROOT_SECONDS }
	p.since_root += dt
	p.warning_left = max(0, p.warning_left-dt)
	before := p.shown
	// The newest advice for the room as it is now (none yet: invalid).
	fresh: advisor.Advice
	if p.worker != nil {
		w := p.worker
		advisor.worker_poll(w)
		current := w.latest.generation == p.generation && p.generation != 0
		over := current && w.latest.done
		if p.root == 0 || (p.acted && !p.acted_rooted) || fingerprint != p.root || (over && p.since_root >= ADVISOR_FRESH_SECONDS) || p.since_root >= ADVISOR_ROOT_SECONDS {
			// The player's own move, one the worker had tried: its best reply at once (thinking ahead).
			if p.acted && !p.acted_rooted && fingerprint != p.root && w.latest.root == p.root {
				fresh = advisor_ahead(p, w.latest.ponder[:w.latest.ponder_count], w.latest.advice, fingerprint)
			}
			p.acted_rooted = p.acted
			p.generation = advisor.worker_offer(w, room, game_context)
			p.root, p.since_root = fingerprint, 0
		} else if current && w.latest.advice.valid {
			fresh = w.latest.advice
		}
	} else {
		s := p.sliced
		if !s.rooted || (p.acted && !p.acted_rooted) || fingerprint != p.root || (s.done && p.since_root >= ADVISOR_FRESH_SECONDS) || p.since_root >= ADVISOR_ROOT_SECONDS {
			if p.acted && !p.acted_rooted && fingerprint != p.root && s.rooted { fresh = advisor_ahead(p, s.ponder[:s.ponder_count], s.advice, fingerprint) }
			p.acted_rooted = p.acted
			advisor.search_root(s, room, game_context)
			p.root, p.since_root = fingerprint, 0
		}
		advisor.search_step(s, ADVISOR_FRAME_WORK)
		if !fresh.valid && s.advice.valid && s.advice.root == fingerprint { fresh = s.advice }
	}
	// THE HELD ADVICE.
	danger := advisor.player_danger(room)
	switch {
	case p.acted || !p.shown.valid:
		// The player acted (or nothing is shown): the next advice is the one, nothing old in the meantime.
		if p.acted { p.shown = {} }
		if fresh.valid { advisor_hold(p, room, fresh, danger) }
	case danger != 0 && danger != p.held_danger && fresh.valid:
		// A blow announced on the player's cell since the advice was held: the IA may change its mind, once.
		advisor_hold(p, room, fresh, danger)
	case fresh.valid && !advisor.advice_possible(room, p.shown, p.held_at):
		advisor_hold(p, room, fresh, danger)
	}
	if p.shown.kind != before.kind || p.shown.cell != before.cell || p.shown.move != before.move { p.shown_age = 0 } else { p.shown_age += dt }
	if p.shown.valid { shown = advisor_view(room, p.shown) }
	shown.age = p.shown_age
	shown.warning, shown.warning_left = p.warning, p.warning_left
}

@(private = "file")
advisor_hold :: proc(p: ^Advisor_Pilot, room: ^game.Room, advice: advisor.Advice, danger: u64) {
	p.shown, p.acted, p.acted_rooted, p.held_danger, p.held_at = advice, false, false, danger, room.player.position
}

// The player's own action, done by the game (execute_gameplay_command): the held advice lets go.
advisor_note_action :: proc() {
	if advisor_pilot != nil { advisor_pilot.acted, advisor_pilot.acted_rooted = true, false }
}

// The situation is the one right after the player's own first move, one the IA had tried: its best reply is the advice
// at once; and if that move was much worse than the advice, the warning.
@(private = "file")
advisor_ahead :: proc(p: ^Advisor_Pilot, table: []advisor.Ponder, advised: advisor.Advice, fingerprint: u64) -> advisor.Advice {
	for entry in table {
		if entry.child != fingerprint { continue }
		if advised.valid {
			extra := entry.loss-advised.loss
			if entry.dies && !advised.dies {
				p.warning, p.warning_left = "! MORTE", render.ADVICE_WARNING_SECONDS
			} else if extra >= ADVISOR_WARNING_LIFE {
				p.warning, p.warning_left = fmt.ctprintf("! -%d", int(extra+0.5)), render.ADVICE_WARNING_SECONDS
			}
		}
		return entry.advice
	}
	return {}
}

// The advice the pilot shows now (none while the IA is off): the lab's act follows it.
advisor_current_advice :: proc() -> advisor.Advice {
	if advisor_pilot == nil { return {} }
	return advisor_pilot.shown
}

// TESTS ONLY: the pilot's worker held (it does no work while held), and how far its search of the current root went.
advisor_pilot_hold :: proc(held: bool) {
	if advisor_pilot != nil && advisor_pilot.worker != nil { advisor.worker_hold(advisor_pilot.worker, held) }
}

// The snapshot the pilot last handed to its worker (the packets of that root carry its number).
advisor_pilot_generation :: proc() -> u64 {
	if advisor_pilot == nil { return 0 }
	return advisor_pilot.generation
}

advisor_pilot_packet :: proc() -> advisor.Packet {
	if advisor_pilot == nil || advisor_pilot.worker == nil { return {} }
	return advisor_pilot.worker.latest
}

// The advice as the board shows it (the provisional marks and words).
advisor_view :: proc(room: ^game.Room, advice: advisor.Advice) -> render.Advice_View {
	switch advice.kind {
	case .None: return {}
	case .Step, .Diagonal, .Dodge:
		// SCHIVA when the step leaves a cell a blow is coming to, VAI otherwise.
		word: cstring = "SCHIVA" if advice.kind == .Dodge || advisor.cell_threat(room, room.player.position) > 0 else "VAI"
		return {mark = .Step, cell = advice.cell, word = word}
	case .Bump: return {mark = .Bump, cell = advice.cell, word = "COLPISCI"}
	case .Shoot: return {mark = .Bump, cell = advice.cell, word = "FRECCIA"}
	case .Wait: return {mark = .Wait, cell = advice.cell, word = "ASPETTA"}
	case .Refocus: return {mark = .Refocus, cell = advice.cell, word = "RIMESCOLA"}
	case .Card: return {mark = .Card, cell = advice.cell, word = "CARTA", card_id = advice.move.card_id}
	case .Activate: return {mark = .Refocus, cell = advice.cell, word = "TESLA"}
	case .Equip: return {mark = .Refocus, cell = advice.cell, word = "ARMA DI RISERVA"}
	case .Defend:
		view := render.Advice_View{mark = .Defend, cell = advice.cell, word = "DIFENDI", defense = advice.move.defense, has_defense = true}
		if advice.move.defense == .Dodge { view.key, view.has_key = advice.move.direction, true }
		return view
	case .Key: return {mark = .Defend, cell = advice.cell, word = "DIFENDI", key = advice.move.direction, has_key = true}
	}
	return {}
}

// THE COMMANDS THE IA KNOWS (the rule for ever: docs/piano-ia.md, «La regola per sempre»). Every command of the game
// is a move the IA advises, a move it will advise in a later phase, the world's own, or none of a fight's moves. The
// switch has no default: a new command does not build until it has its line here.
Advisor_Command_Use :: enum u8 { Advised, Later, World, Outside }

advisor_command_use :: proc(kind: Gameplay_Command_Kind) -> (use: Advisor_Command_Use, why: string) {
	switch kind {
	case .None: return .Outside, "nessun comando"
	case .Move: return .Advised, "il passo, e contro un nemico il colpo a mano"
	case .Dodge: return .Advised, "la schivata"
	case .Wait: return .Advised, "aspettare"
	case .Begin_Diagonal: return .Advised, "il passo in diagonale, coi suoi due tasti"
	case .QTE_Key: return .Advised, "i tasti della diagonale e della difesa"
	case .Defense: return .Advised, "la difesa a tasti"
	case .Play_Card: return .Advised, "le carte della mano, sui loro bersagli migliori (advisor/cards.odin)"
	case .Refocus: return .Advised, "rimescolare la mano"
	case .Shoot: return .Advised, "la freccia del Feretro, a ogni nemico"
	case .Activate: return .Advised, "scaricare le bobine di Tesla (o aprirne l'anello)"
	case .Equip: return .Advised, "prendere in mano l'arma di riserva"
	case .Shadow_Emerge: return .World, "Movimento Ombra finito: il Viandante esce dove sta l'ombra"
	case .Ability: return .Outside, "l'abilità del vecchio prototipo: il tabellone non la offre"
	case .Timeout, .Continue_Pulse, .QTE_Fail, .Lasso_Spin, .Pinball_Roll, .Enemy_Flight:
		return .World, "il mondo che va avanti da solo"
	case .Fish: return .Outside, "la canna da pesca, a stanza vuota: fuori dal combattimento"
	case .First_Person_Fire, .First_Person_Fists, .First_Person_Sword, .First_Person_Bow, .First_Person_Club, .Napoli_Nonno:
		return .Outside, "le viste: la IA si ferma (scelta dell'utente)"
	}
	return .Outside, ""
}

// A move of the IA as the game's own commands, in order (a diagonal and a defence are a command and their keys).
advisor_move_commands :: proc(room: ^game.Room, move: advisor.Move) -> (commands: [3]Gameplay_Command, count: int) {
	base := Gameplay_Command{origin_phase = .Combat}
	switch move.kind {
	case .Step: commands[0] = base; commands[0].kind, commands[0].direction = .Move, move.direction; count = 1
	case .Dodge: commands[0] = base; commands[0].kind, commands[0].direction = .Dodge, move.direction; count = 1
	case .Wait:
		// In the shadow waiting is no command: its seconds run by themselves.
		if room != nil && game.tactical_shadow_active(room) { return }
		commands[0] = base; commands[0].kind = .Wait; count = 1
	case .Refocus: commands[0] = base; commands[0].kind = .Refocus; count = 1
	case .Card:
		commands[0] = base
		commands[0].kind, commands[0].card_id, commands[0].target, commands[0].direction = .Play_Card, move.card_id, move.target, move.direction
		count = 1
	case .Diagonal:
		commands[0] = base; commands[0].kind, commands[0].offset = .Begin_Diagonal, move.offset
		commands[1] = base; commands[1].kind, commands[1].direction = .QTE_Key, (.West if move.offset.x < 0 else .East)
		commands[2] = base; commands[2].kind, commands[2].direction = .QTE_Key, (.North if move.offset.y < 0 else .South)
		count = 3
	case .Defend:
		commands[0] = base; commands[0].kind, commands[0].defense = .Defense, move.defense
		commands[1] = base; commands[1].kind = .QTE_Key
		// The key the rules will ask (game.select_defense), or the dodge's landing; a parry missed is no key.
		if move.defense == .Dodge { commands[1].direction = move.direction }
		else if room != nil { commands[1].direction = game.Move_Direction((room.pulse_count+u64(room.qte.enemy_id))%4) }
		count = 2 if move.succeed || move.defense == .Dodge else 1
	case .Key: commands[0] = base; commands[0].kind, commands[0].direction = .QTE_Key, move.direction; count = 1
	case .Shoot: commands[0] = base; commands[0].kind, commands[0].target = .Shoot, move.target; count = 1
	case .Activate: commands[0] = base; commands[0].kind = .Activate; count = 1
	case .Equip: commands[0] = base; commands[0].kind = .Equip; count = 1
	}
	return
}
