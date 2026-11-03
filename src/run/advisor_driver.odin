package run

import "base:runtime"
import advisor "../advisor"
import game "../game"
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
	// The advice shown, and whether it is the current root's own.
	shown: advisor.Advice,
}

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
		if advisor_pilot != nil { advisor_pilot.shown, advisor_pilot.root = {}, 0 }
		return
	}
	if advisor_pilot == nil { advisor_pilot = advisor_pilot_open() }
	p := advisor_pilot
	if p == nil { return }
	fingerprint := advisor.discrete_fingerprint(room)
	p.since_root += dt
	if p.worker != nil {
		w := p.worker
		advisor.worker_poll(w)
		current := w.latest.generation == p.generation && p.generation != 0
		over := current && w.latest.done
		if p.root == 0 || fingerprint != p.root || (over && p.since_root >= ADVISOR_FRESH_SECONDS) || p.since_root >= ADVISOR_ROOT_SECONDS {
			if fingerprint != p.root {
				// Thinking ahead, from the newest the worker found for the root before.
				p.shown = {}
				if pondered, found := advisor.ponder_lookup(w.latest.ponder[:w.latest.ponder_count], fingerprint); found && w.latest.root == p.root {
					p.shown = pondered
				}
			}
			p.generation = advisor.worker_offer(w, room)
			p.root, p.since_root = fingerprint, 0
		} else if current && w.latest.advice.valid {
			p.shown = w.latest.advice
		}
	} else {
		s := p.sliced
		if !s.rooted || fingerprint != p.root || (s.done && p.since_root >= ADVISOR_FRESH_SECONDS) || p.since_root >= ADVISOR_ROOT_SECONDS {
			pondered, found := advisor.search_pondered(s, fingerprint)
			if fingerprint != p.root { p.shown = pondered if found else {} }
			advisor.search_root(s, room)
			p.root, p.since_root = fingerprint, 0
		}
		advisor.search_step(s, ADVISOR_FRAME_WORK)
		if s.advice.valid { p.shown = s.advice }
	}
	if p.shown.valid { shown = advisor_view(p.shown) }
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

advisor_pilot_packet :: proc() -> advisor.Packet {
	if advisor_pilot == nil || advisor_pilot.worker == nil { return {} }
	return advisor_pilot.worker.latest
}

// The advice as the board shows it (the provisional marks and words).
advisor_view :: proc(advice: advisor.Advice) -> render.Advice_View {
	switch advice.kind {
	case .None: return {}
	case .Step, .Diagonal: return {mark = .Step, cell = advice.cell, word = "VAI"}
	case .Dodge: return {mark = .Step, cell = advice.cell, word = "SCHIVA"}
	case .Bump: return {mark = .Bump, cell = advice.cell, word = "COLPISCI"}
	case .Wait: return {mark = .Wait, cell = advice.cell, word = "ASPETTA"}
	case .Defend, .Key: return {mark = .Defend, cell = advice.cell, word = "DIFENDI"}
	case .Card: return {mark = .Card, cell = advice.cell, word = "CARTA", card_id = advice.move.card_id}
	case .Refocus: return {mark = .Wait, cell = advice.cell, word = "RIMESCOLA"}
	case .Shoot: return {mark = .Bump, cell = advice.cell, word = "FRECCIA"}
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
	case .Activate: return .Later, "le bobine di Tesla: Fase 7, coi casi speciali"
	case .Equip: return .Later, "l'arma di riserva: Fase 7, coi casi speciali"
	case .Shadow_Emerge: return .Later, "Movimento Ombra: Fase 7, coi casi speciali"
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
	case .Wait: commands[0] = base; commands[0].kind = .Wait; count = 1
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
	}
	return
}
