package render

import "core:math"
import audio "../engine/audio"
import gfx "../engine/gfx"
import game "../game"

// The mechanics lab's sounds (PROVA MECCANICHE only): made from code by
// tools/audio (no recordings). Each one is picked from what the board shows,
// so it lands with its drawing: a living card starting a clip plays that
// character's sound for that action (the recipes are timed on the clips'
// keys), a cue plays the card, device or status it shows, and the room's
// state plays the clock, the window and the defence prompt. The board pass
// fills a queue; the scene plays it through its audio.Lab_Bank.

LAB_SOUND_QUEUE :: 48
LAB_SOUND_HEARD :: 96
// A cue's event is sounded once, however many frames it shows.
LAB_SOUND_HEARD_SECONDS :: f64(4)
// The same effect again this soon is one sound (a refill draws five cards).
LAB_SOUND_REPEAT_SECONDS :: f64(0.05)
// Cards drawn together are dealt one after the other.
LAB_SOUND_DEAL_SECONDS :: f64(0.07)
// A card that puts its device on the board sounds for both.
LAB_SOUND_CARD_DEVICE_SECONDS :: f64(1)

Lab_Sound :: struct {
	sfx: audio.Lab_Sfx,
	at: f64,
	volume, pan: f32,
}

Lab_Heard :: struct {
	kind: Presentation_Cue_Kind,
	event: game.Game_Event,
	at: f64,
}

Lab_Sounds :: struct {
	queue: [LAB_SOUND_QUEUE]Lab_Sound,
	count: int,
	heard: [LAB_SOUND_HEARD]Lab_Heard,
	heard_next: int,
	last_played: [audio.Lab_Sfx]f64,
	// The room as it was last frame, to hear what changed.
	watching: bool,
	beat, beat_spent: u32,
	phase: game.Tactical_Phase,
	qte: game.QTE_Kind,
	qte_mode: game.Defense_Mode,
	qte_successes: u64,
	ring: bool,
	enemies: [game.MAX_ENEMIES_PER_ROOM]u32,
	enemy_count: int,
	deal: f64,
	// MOVIMENTO OMBRA as last heard (shadow_step.odin): the card's sinking
	// has sounded and its rise not yet, and the shadow's steps, diagonals on
	// a beat and beats so far.
	shadow: bool,
	shadow_steps, shadow_criticals, shadow_beats: u32,
	// What the lab has played so far (smoke and tests).
	played: [audio.Lab_Sfx]int,
}

// A fresh board hears afresh.
lab_sounds_reset :: proc(renderer: ^Renderer) {
	if renderer == nil || renderer.tactical.lab_sounds == nil { return }
	played := renderer.tactical.lab_sounds.played
	renderer.tactical.lab_sounds^ = {played = played}
}

destroy_lab_sounds :: proc(renderer: ^Renderer) {
	if renderer == nil || renderer.tactical.lab_sounds == nil { return }
	free(renderer.tactical.lab_sounds)
	renderer.tactical.lab_sounds = nil
}

lab_sound_queue :: proc(s: ^Lab_Sounds, sfx: audio.Lab_Sfx, at: f64, volume: f32 = 1, pan: f32 = 0) {
	if at-s.last_played[sfx] < LAB_SOUND_REPEAT_SECONDS && at >= s.last_played[sfx] { return }
	s.last_played[sfx] = at
	if s.count == LAB_SOUND_QUEUE { return }
	s.queue[s.count] = {sfx = sfx, at = at, volume = volume, pan = pan}
	s.count += 1
}

// Left and right on the screen: the board's width, softened.
lab_sound_pan :: proc(renderer: ^Renderer, entity: game.Entity_Ref) -> f32 {
	actor, ok := presentation_actor_in_view(renderer.tactical.snapshot, entity)
	if !ok || renderer.canvas_width <= 0 { return 0 }
	at := tactical_project(renderer, actor.position)
	return clamp((at.x/f32(renderer.canvas_width))*2-1, -1, 1)*0.55
}

lab_sound_heard :: proc(s: ^Lab_Sounds, kind: Presentation_Cue_Kind, event: game.Game_Event, now: f64) -> bool {
	for heard in s.heard {
		if heard.at > 0 && now-heard.at < LAB_SOUND_HEARD_SECONDS && heard.kind == kind && heard.event == event { return true }
	}
	s.heard[s.heard_next] = {kind = kind, event = event, at = now}
	s.heard_next = (s.heard_next+1)%LAB_SOUND_HEARD
	return false
}

// A character's sound for the clip its card just started. `cause` is the cue
// that started it (.Move for a step).
lab_actor_sfx :: proc(character: gfx.Flipbook_Character, action: gfx.Living_Action, cause: Presentation_Cue_Kind,
	travelled: int) -> (sfx: audio.Lab_Sfx, ok: bool) {
	// A blocked step bumps (the cue's own sound); a stopped blow is a block.
	if action == .Block && cause != .Damage_Absorbed { return }
	switch character {
	case .Pilgrim:
		#partial switch action {
		case .Move_Side: return .Pilgrim_Move_Side, true
		case .Move_Up: return .Pilgrim_Move_Up, true
		case .Move_Down: return .Pilgrim_Move_Down, true
		case .Dodge: return .Pilgrim_Dodge, true
		case .Attack: return .Pilgrim_Attack, true
		case .Cast: return .Pilgrim_Cast, true
		case .Hurt: return .Pilgrim_Hurt, true
		case .Hurt_Back: return .Pilgrim_Hurt_Back, true
		case .Block: return .Pilgrim_Block, true
		case .Interact: return .Pilgrim_Interact, true
		case .Death: return .Pilgrim_Death, true
		}
	case .Ghoul:
		#partial switch action {
		case .Move_Side, .Move_Up, .Move_Down: return .Ghoul_Move, true
		case .Attack: return .Ghoul_Attack, true
		case .Hurt, .Hurt_Back: return .Ghoul_Hurt, true
		case .Death: return .Ghoul_Death, true
		}
	case .Archer:
		#partial switch action {
		case .Move_Side, .Move_Up, .Move_Down: return .Archer_Move, true
		case .Attack: return .Archer_Shoot, true
		case .Hurt, .Hurt_Back: return .Archer_Hurt, true
		case .Death: return .Archer_Death, true
		}
	case .Brute:
		#partial switch action {
		case .Move_Side, .Move_Up, .Move_Down: return .Brute_Charge if travelled >= 2 else .Brute_Move, true
		case .Attack: return .Brute_Attack, true
		case .Hurt, .Hurt_Back: return .Brute_Hurt, true
		case .Death: return .Brute_Death, true
		}
	case .Bomber:
		#partial switch action {
		case .Move_Side, .Move_Up, .Move_Down: return .Bomber_Move, true
		case .Attack, .Cast: return .Bomber_Throw, true
		case .Hurt, .Hurt_Back: return .Bomber_Hurt, true
		case .Death: return .Bomber_Death, true
		}
	case .Bishop:
		#partial switch action {
		case .Move_Side, .Move_Up, .Move_Down: return .Bishop_Move, true
		case .Cast: return .Bishop_Protect, true
		case .Attack: return .Bishop_Attack, true
		case .Hurt, .Hurt_Back: return .Bishop_Hurt, true
		case .Death: return .Bishop_Death, true
		}
	case .Archmage:
		#partial switch action {
		case .Move_Side, .Move_Up, .Move_Down: return .Archmage_Move, true
		case .Cast: return .Archmage_Cast, true
		case .Attack: return .Archmage_Attack, true
		case .Hurt, .Hurt_Back: return .Archmage_Hurt, true
		case .Death: return .Archmage_Death, true
		}
	}
	return
}

// The loop a card falls into: an enemy's telegraph, the pilgrim's daze.
lab_base_sfx :: proc(character: gfx.Flipbook_Character, base: gfx.Living_Action) -> (sfx: audio.Lab_Sfx, ok: bool) {
	#partial switch base {
	case .Windup:
		#partial switch character {
		case .Ghoul: return .Ghoul_Windup, true
		case .Archer: return .Archer_Aim, true
		case .Brute: return .Brute_Windup, true
		case .Bomber: return .Bomber_Prepare, true
		}
	case .Stunned:
		if character == .Pilgrim { return .Pilgrim_Stunned, true }
	}
	return
}

lab_card_sfx :: proc(card: game.Card_Id) -> (sfx: audio.Lab_Sfx, ok: bool) {
	switch card {
	case .Strike: return .Card_Strike, true
	case .Arc_Bolt: return .Card_Arc_Bolt, true
	case .Piercing_Ray: return .Card_Piercing_Ray, true
	case .Cross_Slash: return .Card_Cross_Slash, true
	case .Firebomb: return .Card_Firebomb, true
	case .Guard: return .Card_Guard, true
	case .Toxic_Wave: return .Card_Toxic_Wave, true
	case .Thorn_Coat: return .Card_Thorn_Coat, true
	case .Afterimage: return .Card_Afterimage, true
	case .Counter_Rune: return .Card_Counter_Rune, true
	case .Battle_Focus: return .Card_Battle_Focus, true
	case .Calculated_Risk: return .Card_Calculated_Risk, true
	case .Spark_Forge: return .Card_Spark_Forge, true
	case .Spark: return .Card_Spark, true
	case .Shove: return .Card_Shove, true
	case .Dash: return .Card_Dash, true
	case .Grappling_Hook: return .Card_Grappling_Hook, true
	case .Heavy_Blow: return .Card_Heavy_Blow, true
	case .Venom_Needle: return .Card_Venom_Needle, true
	case .Caustic_Bloom: return .Card_Caustic_Bloom, true
	case .Purifying_Guard: return .Card_Purifying_Guard, true
	case .Volatile_Study: return .Card_Volatile_Study, true
	case .Fate_Strike: return .Card_Fate_Strike, true
	case .Chain_Lightning: return .Card_Chain_Lightning, true
	case .Sundering_Blow: return .Card_Sundering_Blow, true
	case .Prismatic_Barrage: return .Card_Prismatic_Barrage, true
	case .Twin_Venom: return .Card_Twin_Venom, true
	case .Shock_Floor: return .Card_Shock_Floor, true
	case .Tesla_Coil: return .Card_Tesla_Coil, true
	case .Titan_Grip: return .Card_Titan_Grip, true
	case .Storm_Crown: return .Card_Storm_Crown, true
	case .Sei_Denari: return .Card_Sei_Denari, true
	case .Sette_Denari: return .Card_Sette_Denari, true
	case .Shadow_Step: return .Card_Shadow_Step, true
	case .Count:
	}
	return
}

lab_status_sfx :: proc(status: game.Status_Kind) -> (sfx: audio.Lab_Sfx, ok: bool) {
	switch status {
	case .Poison: return .Ui_Status_Poison, true
	case .Shield: return .Ui_Status_Shield, true
	case .Thorns: return .Ui_Status_Thorns, true
	case .Afterimage: return .Ui_Status_Afterimage, true
	case .Stagger: return .Ui_Status_Stagger, true
	case .Burn: return .Ui_Status_Burn, true
	case .Slow: return .Ui_Status_Slow, true
	case .Survey:
	}
	return
}

lab_object_kind :: proc(renderer: ^Renderer, entity: game.Entity_Ref) -> (kind: game.Grid_Object_Kind, ok: bool) {
	snapshot := renderer.tactical.snapshot
	if snapshot == nil || entity.kind != .Object { return }
	for object in snapshot.objects[:snapshot.object_count] {
		if object.entity == entity { return object.kind, true }
	}
	return
}

// A cue's own sound: cards, devices, rewards, statuses. Characters' actions
// sound through their cards' clips (lab_actor_sfx).
lab_cue_sounds :: proc(renderer: ^Renderer, s: ^Lab_Sounds, cue: ^Presentation_Cue, now: f64, impacts: ^int) {
	event := cue.event
	pan := lab_sound_pan(renderer, event.target)
	// What a blow does sounds as it lands: a bolt still flying to its mark
	// has not missed it yet (attack_fx.odin).
	landing, _ := attack_fx_landing_in(renderer, event.target, now, event.source)
	#partial switch cue.kind {
	case .Card_Played:
		if sfx, ok := lab_card_sfx(event.card_definition); ok { lab_sound_queue(s, sfx, now) }
	case .Card_Drawn, .Card_Created:
		s.deal = max(s.deal+LAB_SOUND_DEAL_SECONDS, now)
		s.last_played[.Ui_Card_Draw] = 0
		lab_sound_queue(s, .Ui_Card_Draw, s.deal, 0.9 if cue.kind == .Card_Drawn else 0.6)
	case .Refocus, .Card_Refocused:
		lab_sound_queue(s, .Ui_Refocus, now)
	case .Gold_Gained:
		// The coins of the Scopa cards are the card's own sound.
		if now-s.last_played[.Card_Sei_Denari] > 0.6 && now-s.last_played[.Card_Sette_Denari] > 0.6 { lab_sound_queue(s, .Ui_Gold, now) }
	case .Energy_Gained:
		lab_sound_queue(s, .Ui_Energy, now)
	case .Loot_Dropped:
		lab_sound_queue(s, .Ui_Loot_Drop, now, 1, lab_sound_pan(renderer, event.source))
	case .Status_Applied:
		if sfx, ok := lab_status_sfx(event.status); ok { lab_sound_queue(s, sfx, now, 1, pan) }
	case .Status_Expired, .Status_Removed:
		lab_sound_queue(s, .Ui_Status_Expired, now, 1, pan)
	case .Damage_Absorbed:
		// The pilgrim's card blocks with its own sound.
		if event.target != game.PLAYER_ENTITY { lab_sound_queue(s, .Ui_Block_Absorb, now+landing, 1, pan) }
	case .Attack_Missed:
		lab_sound_queue(s, .Ui_Miss, now+landing, 1, pan)
	case .Move_Blocked:
		lab_sound_queue(s, .Ui_Move_Blocked, now, 1, pan)
	case .Heal:
		lab_sound_queue(s, .Pilgrim_Heal, now, 1 if event.target == game.PLAYER_ENTITY else 0.7, pan)
	case .Explosive_Armed:
		lab_sound_queue(s, .World_Bomb_Fuse, now+landing)
	case .Explosive_Disarmed:
		lab_sound_queue(s, .World_Bomb_Fizzle, now)
	case .Explosion:
		lab_sound_queue(s, .World_Barrel_Explosion if event.object_kind == .Barrel else .World_Explosion, now)
	case .Object_Spawned:
		#partial switch event.object_kind {
		case .Tesla_Coil:
			// The card already sets its coil down: the board's own sound is
			// for a coil that comes any other way.
			if now-s.last_played[.Card_Tesla_Coil] > LAB_SOUND_CARD_DEVICE_SECONDS { lab_sound_queue(s, .World_Tesla_Deploy, now) }
		case .Fire: lab_sound_queue(s, .World_Fire, now)
		}
	case .Spell_Impact:
		#partial switch event.card_definition {
		case .Tesla_Coil: impacts^ += 1
		case .Shock_Floor: lab_sound_queue(s, .World_Shock_Floor, now)
		}
	case .Damage:
		if kind, object := lab_object_kind(renderer, event.target); object {
			lab_sound_queue(s, .World_Ice_Crack if kind == .Ice_Block else .World_Object_Hit, now+landing)
		}
	case .Defeat:
		if event.target == game.PLAYER_ENTITY { lab_sound_queue(s, .Ui_Defeat, now+0.6) }
	}
}

// Once per frame with the living cards, in the lab only.
update_lab_sounds :: proc(renderer: ^Renderer, room: ^game.Room, now: f64) {
	v := &renderer.tactical
	if !v.mechanics_lab || v.living_state == nil || room == nil || room.player == nil { return }
	if v.lab_sounds == nil { v.lab_sounds = new(Lab_Sounds) }
	s := v.lab_sounds
	// Characters: a sound for each clip a card starts, and for the loops of
	// telegraph and daze.
	for &actor in v.living_state.actors {
		if !actor.used || actor.ghost { continue }
		pan := lab_sound_pan(renderer, actor.entity)
		if actor.action != .Idle && actor.started != actor.voiced {
			actor.voiced = actor.started
			travelled := int(abs(actor.move_to.x-actor.move_from.x)+abs(actor.move_to.y-actor.move_from.y)+0.5)
			if sfx, ok := lab_actor_sfx(actor.character, actor.action, actor.cause, travelled); ok {
				// A reaction waiting for its blow sounds when it starts.
				ahead := max(0, actor.started-living_clock_at(renderer, actor.entity, now))
				lab_sound_queue(s, sfx, now+ahead, 1, pan)
			}
		}
		if actor.base != actor.voiced_base {
			actor.voiced_base = actor.base
			if sfx, ok := lab_base_sfx(actor.character, actor.base); ok { lab_sound_queue(s, sfx, now, 1, pan) }
		}
	}
	// MOVIMENTO OMBRA: the card's own cues show it going down into its shadow
	// (after the card's sound) and climbing back out (after the landing);
	// each sounds as it starts to show. The shadow's steps start no clip on
	// the card, so the boots and the paper's scrape stay silent: the pool has
	// a step of its own, a diagonal on a beat also stings, and its beats tick
	// like the world's.
	shadow := &v.shadow
	player_pan := lab_sound_pan(renderer, game.PLAYER_ENTITY)
	if !s.shadow && shadow.active && shadow.sink > 0 {
		s.shadow = true
		lab_sound_queue(s, .Pilgrim_Shadow_Sink, now, 1, player_pan)
	} else if s.shadow && !shadow.active && shadow.rise > 0 {
		s.shadow = false
		lab_sound_queue(s, .Pilgrim_Shadow_Rise, now, 1, player_pan)
	}
	if shadow.steps != s.shadow_steps {
		s.shadow_steps = shadow.steps
		lab_sound_queue(s, .Pilgrim_Shadow_Step, now, 1, player_pan)
	}
	if shadow.criticals != s.shadow_criticals {
		s.shadow_criticals = shadow.criticals
		lab_sound_queue(s, .Ui_Critical, now)
	}
	if shadow.beats != s.shadow_beats {
		s.shadow_beats = shadow.beats
		lab_sound_queue(s, .Ui_Beat_Tick, now)
	}
	// The cues now showing, each once; the cards first, so what they put on
	// the board knows they already sounded. What was heard is kept on the
	// world's clock: a cue the shadow holds still is never heard again.
	impacts := 0
	world := tactical_world_time_at(renderer, now)
	for cards in ([2]bool{true, false}) {
		for offset in 0..<renderer_active_cue_count(renderer) {
			cue, found := renderer_active_cue_at(renderer, offset)
			if !found || !cue.started || (cue.kind == .Card_Played) != cards || lab_sound_heard(s, cue.kind, cue.event, world) { continue }
			lab_cue_sounds(renderer, s, cue, now, &impacts)
		}
	}
	// A discharge strikes along every link at once: one zap. (The ring's
	// chord is for the square closing into the Ring, lab_watch_room.)
	if impacts > 0 { lab_sound_queue(s, .World_Tesla_Zap, now) }
	lab_watch_room(s, room, now)
}

// The room's own moments: the clock, criticals, the window, the defence.
lab_watch_room :: proc(s: ^Lab_Sounds, room: ^game.Room, now: f64) {
	t := &room.player.tactical
	arrived := false
	enemies: [game.MAX_ENEMIES_PER_ROOM]u32
	enemy_count := min(len(room.enemies), len(enemies))
	for index in 0..<enemy_count {
		enemies[index] = room.enemies[index].id
		known := false
		for id in s.enemies[:s.enemy_count] { if id == enemies[index] { known = true; break } }
		if !known { arrived = true }
	}
	if !s.watching {
		s.watching = true
	} else if game.tactical_enabled(room) && room.phase == .Combat {
		if t.beat_index > s.beat && t.phase == .Decision { lab_sound_queue(s, .Ui_Beat_Tick, now) }
		if t.beat_spent != s.beat_spent && t.beat_spent != 0 { lab_sound_queue(s, .Ui_Critical, now) }
		if t.phase != s.phase {
			// A stun that Movimento Ombra interrupted resumes; it does not strike again.
			if t.phase == .Stunned && s.phase != .Shadow { lab_sound_queue(s, .Ui_Stun, now) }
			else if t.phase == .Recovery && s.phase == .Decision && t.remaining > 0 { lab_sound_queue(s, .Ui_Window_End, now) }
		}
		if room.qte.kind == .Defense && s.qte != .Defense { lab_sound_queue(s, .Ui_Defense_Prompt, now) }
		if room.qte.kind == .None && s.qte == .Defense && t.metrics.qte_successes > s.qte_successes &&
		   (s.qte_mode == .Parry || s.qte_mode == .Deflect) { lab_sound_queue(s, .Pilgrim_Parry, now) }
		if room.tesla_ring.pending && !s.ring { lab_sound_queue(s, .World_Tesla_Ring, now) }
		if arrived { lab_sound_queue(s, .World_Spawn, now) }
	}
	s.beat, s.beat_spent, s.phase = t.beat_index, t.beat_spent, t.phase
	s.qte, s.qte_successes, s.ring = room.qte.kind, t.metrics.qte_successes, room.tesla_ring.pending
	if room.qte.kind == .Defense { s.qte_mode = room.qte.mode }
	s.enemies, s.enemy_count = enemies, enemy_count
}

// The scene plays what is due (volume: the player's effects volume).
play_lab_sounds :: proc(renderer: ^Renderer, bank: ^audio.Lab_Bank, volume: f32) {
	if renderer == nil || renderer.tactical.lab_sounds == nil { return }
	s := renderer.tactical.lab_sounds
	now := renderer.sprite_assets.elapsed
	kept := 0
	for index in 0..<s.count {
		sound := s.queue[index]
		if sound.at > now { s.queue[kept] = sound; kept += 1; continue }
		s.played[sound.sfx] += 1
		if bank == nil { continue }
		// A little life in every play: ±4% pitch, ±1.5 dB.
		seed := u32(sound.at*7919) ~ u32(sound.sfx)*2654435761
		wobble := f32(seed%1000)/500-1
		wobble2 := f32((seed/1000)%1000)/500-1
		gain := sound.volume*math.pow(10, wobble2*1.5/20)
		audio.lab_play(bank, sound.sfx, volume*gain, 1+0.04*wobble, sound.pan)
	}
	s.count = kept
}
