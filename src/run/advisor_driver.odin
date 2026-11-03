package run

import "base:runtime"
import advisor "../advisor"
import game "../game"
import render "../render"

// THE IA'S PILOT (docs/piano-ia.md, Fase 2). Every frame the IA's card is running, the tactical controller calls it:
// when the situation changes (its discrete fingerprint: a step, a blow, a beat, an intent, the defence keys) it takes a
// new root, the snapshot of the real room (only read); then it spends a few nodes of the search, its frame's slice
// (the thread is Fase 4's), and gives the advice it has to the board's marks. Behind the eyes of a view, the IA off,
// out of a fight: no marks, and the search's memory goes back.

// The work a frame spends: a node is a quarter to half a millisecond in the IA's arena (-o:speed; a long horizon's
// counts two), so at most two milliseconds or so.
ADVISOR_FRAME_WORK :: 3
// A root also grows old: the world's seconds run on under it.
ADVISOR_ROOT_SECONDS :: f32(1)

Advisor_Pilot :: struct {
	search: advisor.Search,
	root: u64,
	since_root: f32,
}

// One pilot a thread (the tests play rooms side by side), in the process's own memory.
@(private = "file", thread_local)
advisor_pilot: ^Advisor_Pilot

@(private = "file")
advisor_pilot_release :: proc() {
	if advisor_pilot == nil { return }
	advisor.search_destroy(&advisor_pilot.search)
	free(advisor_pilot, runtime.heap_allocator())
	advisor_pilot = nil
}

drive_advisor :: proc(room: ^game.Room, renderer: ^render.Renderer, dt: f32) {
	shown := render.Advice_View{}
	defer renderer.tactical.advice = shown
	if room == nil || room.player == nil || room.phase != .Combat || !game.ia_active(room) { advisor_pilot_release(); return }
	if advisor_pilot == nil {
		advisor_pilot = new(Advisor_Pilot, runtime.heap_allocator())
		if advisor_pilot == nil { return }
		if !advisor.search_init(&advisor_pilot.search) { free(advisor_pilot, runtime.heap_allocator()); advisor_pilot = nil; return }
	}
	p := advisor_pilot
	fingerprint := advisor.discrete_fingerprint(room)
	p.since_root += dt
	kept: advisor.Advice
	if !p.search.rooted || fingerprint != p.root || p.since_root >= ADVISOR_ROOT_SECONDS {
		// Thinking ahead: the situation is one the last root already tried, and its best reply is ready.
		pondered, found := advisor.search_pondered(&p.search, fingerprint)
		// The same situation, only older: its advice stands until the new root's first round.
		if fingerprint == p.root { kept = p.search.advice }
		advisor.search_root(&p.search, room)
		p.root, p.since_root = fingerprint, 0
		if found { p.search.advice = pondered }
	}
	advisor.search_step(&p.search, ADVISOR_FRAME_WORK)
	advice := p.search.advice if p.search.advice.valid else kept
	if advice.valid { shown = advisor_view(advice) }
}

// The advice the pilot has now (none while the IA is off): the lab's act follows it.
advisor_current_advice :: proc() -> advisor.Advice {
	if advisor_pilot == nil { return {} }
	return advisor_pilot.search.advice
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
	case .Play_Card: return .Later, "le carte: Fase 3"
	case .Refocus: return .Later, "rimescolare la mano: Fase 3, con le carte"
	case .Shoot: return .Later, "la freccia del Feretro, una carica di carta: Fase 3"
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
	}
	return
}
