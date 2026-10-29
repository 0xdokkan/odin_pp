package render

import "core:math"
import rl "vendor:raylib"
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
// The reel's own splash (pilgrim_reel's mark), lined up with the catch
// breaking the water.
LAB_REEL_SPLASH_SECONDS :: f64(0.1)
// The rope's whirr at each full turn climbs with the spin: from this pitch,
// this much a turn, up to the fourteenth.
LAB_WHIRR_PITCH :: f32(0.85)
LAB_WHIRR_PITCH_PER_TURN :: f32(0.05)
LAB_WHIRR_TURNS :: i32(14)
// PINBALL (pinball.odin): its card, the strike's thwack, a solid thing's
// ding, a foe's bong and the burst.
LAB_PINBALL_CARD :: audio.Lab_Sfx.Card_Pinball
LAB_PINBALL_LAUNCH :: audio.Lab_Sfx.World_Pinball_Launch
LAB_PINBALL_DING :: audio.Lab_Sfx.World_Pinball_Ding
LAB_PINBALL_BONG :: audio.Lab_Sfx.World_Pinball_Bong
LAB_PINBALL_BURST :: audio.Lab_Sfx.World_Pinball_Burst
// The bong climbs a little with the value the foe took, up to this many over
// the card's.
LAB_BONG_PITCH :: f32(0.9)
LAB_BONG_PITCH_PER_VALUE :: f32(0.04)
LAB_BONG_STEPS :: i32(8)
// FIRST PERSON SHOOTER (first_person.odin): its card, the dive in (as the
// card's cue paces it) and the rise out, a shot at the muzzle, a hit on a
// foe and a shot on stone.
LAB_FIRST_PERSON_CARD :: audio.Lab_Sfx.Card_First_Person
LAB_FIRST_PERSON_SHOT :: audio.Lab_Sfx.Pilgrim_Ak_Shot
LAB_FIRST_PERSON_HIT :: audio.Lab_Sfx.World_Ak_Hit
LAB_FIRST_PERSON_RICOCHET :: audio.Lab_Sfx.World_Ak_Ricochet
LAB_FIRST_PERSON_ENTER :: audio.Lab_Sfx.Pilgrim_Fps_Dive
LAB_FIRST_PERSON_EXIT :: audio.Lab_Sfx.Pilgrim_Fps_Rise
// FIRST PERSON BRAWLER (first_person_fists.odin): the ring's bell at the dive,
// a punch's air (higher for a jab, lower for a hook), its blow by punch, a
// critical's ding, a mark's tick at its punch's pitch (left hook, jab, cross,
// right hook: low to high).
LAB_FISTS_BELL :: audio.Lab_Sfx.World_Ring_Bell
LAB_FISTS_WHOOSH :: audio.Lab_Sfx.Pilgrim_Fists_Whoosh
LAB_FISTS_CRIT :: audio.Lab_Sfx.World_Fists_Crit
LAB_FISTS_MARK :: audio.Lab_Sfx.Ui_Fists_Mark
@(rodata)
LAB_FISTS_HIT := [game.First_Person_Punch]audio.Lab_Sfx{.None = .World_Fists_Hit_Jab, .Jab = .World_Fists_Hit_Jab,
	.Cross = .World_Fists_Hit_Cross, .Left_Hook = .World_Fists_Hit_Hook, .Right_Hook = .World_Fists_Hit_Hook}
@(rodata)
LAB_FISTS_WHOOSH_PITCH := [game.First_Person_Punch]f32{.None = 1, .Jab = 1.15, .Cross = 1, .Left_Hook = 0.85, .Right_Hook = 0.85}
@(rodata)
LAB_FISTS_MARK_PITCH := [4]f32{0.85, 1, 1.12, 1.26}

Lab_Sound :: struct {
	sfx: audio.Lab_Sfx,
	at: f64,
	volume, pan: f32,
	// The play's pitch (0: as recorded): the Lazzo's whirr climbs with its speed.
	pitch: f32,
}

// A cue heard: its kind, its event and its command (Presentation_Cue.batch).
// The same event in a later command (two bumps from the same cell rolling the
// same face on the same foe) is a sound of its own.
Lab_Heard :: struct {
	kind: Presentation_Cue_Kind,
	event: game.Game_Event,
	batch: u32,
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
	// LAZZO as last heard (lasso.odin): its full turns and its releases.
	lasso_whirrs, lasso_releases: int,
	// PINBALL as last heard (pinball.odin): its strikes.
	pinball_strikes: int,
	// FIRST PERSON SHOOTER as last heard (first_person.odin): its shots, hits
	// and shots on stone, and its rises (a dive is its card's cue).
	first_person_shots, first_person_hits, first_person_ricochets, first_person_exits: int,
	// FIRST PERSON BRAWLER as last heard: punches thrown, landed, marks lit.
	fists_thrown, fists_landed, fists_marks_lit: int,
	// What the lab has played so far (smoke and tests).
	played: [audio.Lab_Sfx]int,
}

// A fresh board hears afresh.
@(private)
lab_sounds_reset :: proc(renderer: ^Renderer) {
	if renderer == nil || renderer.tactical.lab_sounds == nil { return }
	played := renderer.tactical.lab_sounds.played
	// The rope's counts go on (lasso_view_reset keeps them), and the ball's
	// and the view's (pinball_view_reset, first_person_view_reset): nothing
	// to hear yet.
	lasso := &renderer.tactical.lasso
	fp := &renderer.tactical.first_person
	renderer.tactical.lab_sounds^ = {played = played, lasso_whirrs = lasso.whirrs, lasso_releases = lasso.releases,
		pinball_strikes = renderer.tactical.pinball.strikes,
		first_person_shots = fp.shots, first_person_hits = fp.hits, first_person_ricochets = fp.ricochets,
		first_person_exits = fp.exits, fists_thrown = fp.fists_thrown, fists_landed = fp.fists_landed, fists_marks_lit = fp.fists_marks_lit}
}

// The bong's pitch for a foe struck at `value`, the card's being `base`.
@(private)
lab_bong_pitch :: proc(value, base: i32) -> f32 {
	return LAB_BONG_PITCH+LAB_BONG_PITCH_PER_VALUE*f32(clamp(value-base, 0, LAB_BONG_STEPS))
}

@(private)
destroy_lab_sounds :: proc(renderer: ^Renderer) {
	if renderer == nil || renderer.tactical.lab_sounds == nil { return }
	free(renderer.tactical.lab_sounds)
	renderer.tactical.lab_sounds = nil
}

// The whirr's pitch after `turns` full turns of the rope.
@(private)
lab_whirr_pitch :: proc(turns: i32) -> f32 {
	return LAB_WHIRR_PITCH+LAB_WHIRR_PITCH_PER_TURN*f32(clamp(turns, 0, LAB_WHIRR_TURNS))
}

@(private)
lab_sound_queue :: proc(s: ^Lab_Sounds, sfx: audio.Lab_Sfx, at: f64, volume: f32 = 1, pan: f32 = 0, pitch: f32 = 0) {
	if at-s.last_played[sfx] < LAB_SOUND_REPEAT_SECONDS && at >= s.last_played[sfx] { return }
	s.last_played[sfx] = at
	if s.count == LAB_SOUND_QUEUE { return }
	s.queue[s.count] = {sfx = sfx, at = at, volume = volume, pan = pan, pitch = pitch}
	s.count += 1
}

// Left and right on the screen: the board's width, softened; behind the
// player's eyes, left and right of the eye.
@(private)
lab_sound_pan :: proc(renderer: ^Renderer, entity: game.Entity_Ref) -> f32 {
	actor, ok := presentation_actor_in_view(renderer.tactical.snapshot, entity)
	if !ok || renderer.canvas_width <= 0 { return 0 }
	if renderer.tactical.first_person.amount > 0 {
		if entity == game.PLAYER_ENTITY { return 0 }
		camera := renderer.tactical.camera
		toward := rl.Vector3{actor.position.x+0.5, camera.position.y, actor.position.y+0.5}-camera.position
		if rl.Vector3Length(toward) < 0.001 { return 0 }
		return clamp(rl.Vector3DotProduct(rl.Vector3Normalize(toward), flipbook_camera_right(renderer)), -1, 1)*0.55
	}
	at := tactical_project(renderer, actor.position)
	return clamp((at.x/f32(renderer.canvas_width))*2-1, -1, 1)*0.55
}

@(private)
lab_sound_heard :: proc(s: ^Lab_Sounds, kind: Presentation_Cue_Kind, event: game.Game_Event, now: f64, batch := u32(0)) -> bool {
	for heard in s.heard {
		if heard.at > 0 && now-heard.at < LAB_SOUND_HEARD_SECONDS && heard.kind == kind && heard.batch == batch && heard.event == event { return true }
	}
	s.heard[s.heard_next] = {kind = kind, event = event, batch = batch, at = now}
	s.heard_next = (s.heard_next+1)%LAB_SOUND_HEARD
	return false
}

// A character's sound for the clip its card just started. `cause` is the cue
// that started it (.Move for a step); `shot`, an attack that looses a shot.
@(private)
lab_actor_sfx :: proc(character: gfx.Flipbook_Character, action: gfx.Living_Action, cause: Presentation_Cue_Kind,
	travelled: int, shot := false) -> (sfx: audio.Lab_Sfx, ok: bool) {
	// A blocked step bumps (the cue's own sound); a stopped blow is a block.
	// A blow RIFLESSO turns back has its own (lab_cue_sounds), and so do the
	// Lazzo's throw, the Canna da Pesca's cast and catch and the Pinball's
	// strike (update_lab_sounds).
	if action == .Block && cause != .Damage_Absorbed { return }
	if cause == .Lasso_Caught || cause == .Fish_Cast || cause == .Fish_Bite || cause == .Fish_Caught || cause == .Pinball_Launched { return }
	switch character {
	case .Pilgrim:
		#partial switch action {
		case .Move_Side: return .Pilgrim_Move_Side, true
		case .Move_Up: return .Pilgrim_Move_Up, true
		case .Move_Down: return .Pilgrim_Move_Down, true
		case .Dodge: return .Pilgrim_Dodge, true
		// FERETRO's arrow is loosed, not swung.
		case .Attack: return (.Pilgrim_Shoot if shot else .Pilgrim_Attack), true
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
@(private)
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

lab_status_sfx :: proc(status: game.Status_Kind) -> (sfx: audio.Lab_Sfx, ok: bool) {
	switch status {
	case .Poison: return .Ui_Status_Poison, true
	case .Shield: return .Ui_Status_Shield, true
	case .Thorns: return .Ui_Status_Thorns, true
	case .Afterimage: return .Ui_Status_Afterimage, true
	case .Stagger: return .Ui_Status_Stagger, true
	case .Burn: return .Ui_Status_Burn, true
	case .Slow: return .Ui_Status_Slow, true
	case .Deflect: return .Ui_Status_Deflect, true
	case .Arrows: return .Ui_Status_Arrows, true
	case .Fate: return .Ui_Status_Fate, true
	case .Venom_Blade: return .Ui_Status_Venom_Blade, true
	case .Bleed: return .Ui_Status_Bleed, true
	case .Survey:
	}
	return
}

@(private = "file")
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
@(private)
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
	case .Attack_Deflected:
		// RIFLESSO rings as the blow reaches the player and turns back.
		lab_sound_queue(s, .Pilgrim_Deflect, now+landing, 1, pan)
	case .Fate_Rolled:
		// The Dado del Destino's die bounces at the struck foe as it shows,
		// when the bump lands (update_fate_tokens).
		lab_sound_queue(s, .Ui_Fate_Die, now+landing, 1, pan)
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
		// CANNONE and BUCO NERO set down.
		case .Field_Cannon: lab_sound_queue(s, .World_Cannon_Place, now)
		case .Devouring_Hole: lab_sound_queue(s, .World_Black_Hole_Open, now)
		}
	case .Spell_Impact:
		#partial switch event.card_definition {
		case .Tesla_Coil: impacts^ += 1
		case .Shock_Floor: lab_sound_queue(s, .World_Shock_Floor, now)
		// A pool splashes on its cell, a fire catches there.
		case .Poison_Pool: lab_sound_queue(s, .World_Pool_Splash, now)
		case .Wildfire: lab_sound_queue(s, .World_Fire, now)
		}
	case .Damage:
		if kind, object := lab_object_kind(renderer, event.target); object {
			lab_sound_queue(s, .World_Ice_Crack if kind == .Ice_Block else .World_Object_Hit, now+landing)
		}
	case .Defeat:
		if event.target == game.PLAYER_ENTITY { lab_sound_queue(s, .Ui_Defeat, now+0.6) }
	// LAZZO (lasso.odin): the throw from his hand, then the loop cinching as
	// it drops round the foe (and the rope jerking taut as the card is
	// lifted); each hit on a foe, or a smash into the wall, at the swung card.
	case .Lasso_Caught:
		lab_sound_queue(s, .Pilgrim_Lasso_Throw, now, 1, lab_sound_pan(renderer, game.PLAYER_ENTITY))
		lab_sound_queue(s, .World_Lasso_Wrap, now+f64(cue.duration*LASSO_THROW_FLOWN), 1, pan)
	case .Lasso_Struck:
		smash := event.target == game.SYSTEM_ENTITY
		lab_sound_queue(s, .World_Lasso_Smash if smash else .World_Lasso_Hit, now, 1, lab_sound_pan(renderer, event.source))
	// CANNA DA PESCA (fishing.odin), at the player: the card as the rod is
	// cast; the bobber's plop as the bite's cue starts (the water shows), the
	// bite's gulp and splash as the bobber dips; the reel, its splash where
	// the catch breaks the water, then the catch reaching his hand (food) or
	// a caught card reaching him.
	case .Fish_Cast:
		lab_sound_queue(s, .Card_Fishing_Rod, now, 1, lab_sound_pan(renderer, game.PLAYER_ENTITY))
	case .Fish_Bite:
		player := lab_sound_pan(renderer, game.PLAYER_ENTITY)
		lab_sound_queue(s, .World_Bobber_Plop, now, 1, player)
		lab_sound_queue(s, .World_Fish_Bite, now+f64(cue.duration*FISHING_BITE_AT), 1, player)
	case .Fish_Caught:
		player := lab_sound_pan(renderer, game.PLAYER_ENTITY)
		duration := f64(cue.duration)
		lab_sound_queue(s, .Pilgrim_Reel, now+max(0, duration*f64(FISHING_REEL*FISHING_REEL_BREAKS)-LAB_REEL_SPLASH_SECONDS), 1, player)
		if event.card_definition == .Fishing_Rod {
			lab_sound_queue(s, .Pilgrim_Catch, now+duration*f64(fishing_food_taken()), 1, player)
		} else {
			lab_sound_queue(s, .Ui_Fish_Card, now+duration*f64(FISHING_CARD_LANDS), 1, player)
		}
	// PINBALL (pinball.odin), at the ball: it rings off a solid thing, a foe
	// it strikes bongs (higher the more it took), and it bursts.
	case .Pinball_Bounced:
		lab_sound_queue(s, LAB_PINBALL_DING, now, 0.8, lab_sound_pan(renderer, event.source))
	case .Pinball_Bumped:
		lab_sound_queue(s, LAB_PINBALL_BONG, now, 1, lab_sound_pan(renderer, event.source), lab_bong_pitch(event.amount, renderer.tactical.pinball.base))
	case .Pinball_Burst:
		lab_sound_queue(s, LAB_PINBALL_BURST, now, 1, pan)
	// FIRST PERSON SHOOTER (first_person.odin): the camera dives into his
	// eyes as the card's own cue paces it.
	case .First_Person_Begun:
		lab_sound_queue(s, LAB_FIRST_PERSON_ENTER, now)
		// The fists' ring: its bell as the gloves come up.
		if renderer.tactical.first_person.weapon == .Fists { lab_sound_queue(s, LAB_FISTS_BELL, now+0.1) }
	// BOMB MARLEY (marley.odin): the ball coming down, the lights turning, a
	// column warned, the bomb's whistle and its blast at the far end, a
	// character saved, the seconds earned, the end; and a groove on the
	// world's every beat, one a and one b in turn.
	case .Marley_Begun:
		lab_sound_queue(s, .World_Marley_Ball, now)
	case .Marley_Lights:
		lab_sound_queue(s, .World_Marley_Lights, now)
	case .Marley_Warned:
		lab_sound_queue(s, .World_Marley_Warn, now)
	case .Marley_Bomb:
		lab_sound_queue(s, .World_Marley_Bomb, now)
		lab_sound_queue(s, .World_Marley_Blast, now+f64(cue.duration)*0.55)
	case .Marley_Saved:
		lab_sound_queue(s, .World_Marley_Safe, now+f64(cue.duration)*0.4, 1, pan)
	case .Marley_Bonus:
		lab_sound_queue(s, .World_Marley_Bonus, now)
	case .Marley_Ended:
		lab_sound_queue(s, .World_Marley_End, now)
	// CANNONE (cannon.odin): the shot, and its strike on a foe as the ball (or
	// the beam) arrives; the cannon falling apart.
	case .Cannon_Fired:
		lab_sound_queue(s, .World_Laser_Fire if event.duration == 1 else .World_Cannon_Fire, now)
		if event.target != game.SYSTEM_ENTITY { lab_sound_queue(s, .World_Cannon_Hit, now+f64(cue.duration)*0.7, 0.9, lab_sound_pan(renderer, event.target)) }
	case .Cannon_Broken:
		lab_sound_queue(s, .World_Cannon_Break, now)
	// BUCO NERO (black_hole.odin): the hum on every beat, a foe swallowed, the
	// hole closing.
	case .Black_Hole_Tick:
		lab_sound_queue(s, .World_Black_Hole_Hum, now, 0.8)
	case .Black_Hole_Swallowed:
		lab_sound_queue(s, .World_Black_Hole_Swallow, now, 1, pan)
	case .Black_Hole_Closed:
		lab_sound_queue(s, .World_Black_Hole_Close, now)
	// DINOSAURO (dinosaur.odin): the roar of the dinosaur the die gave, its
	// stomp, and the climb down; SANGUINAMENTO's extra bite.
	case .Ride_Begun:
		roars := [game.Dino_Kind]audio.Lab_Sfx{.Raptor = .World_Dino_Roar_Raptor, .Stego = .World_Dino_Roar_Stego, .Dilo = .World_Dino_Roar_Dilo, .Giga = .World_Dino_Roar_Giga}
		lab_sound_queue(s, roars[game.Dino_Kind(clamp(event.duration, 0, 3))], now)
	case .Ride_Ended:
		lab_sound_queue(s, .World_Dino_Dismount, now)
	case .Dino_Stomp:
		lab_sound_queue(s, .World_Dino_Stomp, now)
	case .Bleed_Bite:
		lab_sound_queue(s, .World_Bleed_Tick, now+landing, 0.8, pan)
	case .Pulse_Advanced:
		if party := &renderer.tactical.snapshot.marley; party.active {
			lab_sound_queue(s, .World_Marley_Groove_A if party.elapsed%2 == 0 else .World_Marley_Groove_B, now, 0.8)
		}
	// INONDAZIONE (flood.odin): the wave over the whole sweep, the steam of
	// each fire it puts out.
	case .Flood_Swept:
		lab_sound_queue(s, .World_Flood_Wave, now)
	// A foe the wave pushes splashes as the front reaches it.
	case .Move:
		// A step on the dinosaur: light for the raptor, heavy for the others; a
		// foe the hole draws in whirs.
		if event.target == game.PLAYER_ENTITY && renderer.tactical.snapshot.ride.active {
			lab_sound_queue(s, .World_Dino_Step_Small if renderer.tactical.snapshot.ride.kind == .Raptor else .World_Dino_Step_Heavy, now)
		}
		if event.card_definition == .Devouring_Hole { lab_sound_queue(s, .World_Black_Hole_Pull, now, 0.8, pan) }
		if event.card_definition == .Flood_Wave {
			delay := f64(0)
			if head, led := flood_group_head(&renderer.timeline); led {
				length := flood_length(head.event)
				delay = f64(flood_arrival(flood_progress_index(game.Move_Direction(head.event.duration), event.from_position, length), length)*cue.duration)
			}
			lab_sound_queue(s, .World_Flood_Splash, now+delay, 0.8, pan)
		}
	case .Fire_Extinguished:
		lab_sound_queue(s, .World_Flood_Steam, now+f64(cue.duration)*0.3)
	}
}

// Once per frame with the living cards, in the lab only.
@(private)
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
			if sfx, ok := lab_actor_sfx(actor.character, actor.action, actor.cause, travelled, actor.shot); ok {
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
	// LAZZO: the rope whirrs at each full turn, higher as it speeds up, and
	// goes slack when it lets a living foe go, its card dropping back to the
	// floor (lasso.odin); a foe that dies on it falls with its own death.
	lasso := &v.lasso
	if lasso.whirrs != s.lasso_whirrs {
		s.lasso_whirrs = lasso.whirrs
		lab_sound_queue(s, .World_Lasso_Whirr, now, 0.8, lab_sound_pan(renderer, lasso.enemy), lab_whirr_pitch(lasso.turns))
	}
	if lasso.releases != s.lasso_releases {
		s.lasso_releases = lasso.releases
		lab_sound_queue(s, .World_Lasso_Release, now, 1, lab_sound_pan(renderer, lasso.enemy))
	}
	// PINBALL: the strike's thwack, as the swing set at the ball lands
	// (pinball.odin): the player's card swings silently, its blow is the ball's.
	ball := &v.pinball
	if ball.strikes != s.pinball_strikes {
		s.pinball_strikes = ball.strikes
		lab_sound_queue(s, LAB_PINBALL_LAUNCH, max(now, ball.contact), 1, lab_sound_pan(renderer, ball.enemy))
	}
	// FIRST PERSON SHOOTER: the rise out swoops (the dive in is its card's
	// cue, lab_cue_sounds); every shot cracks at the muzzle, a hit thuds, a
	// shot on stone ricochets (first_person.odin). The struck foe's own voice
	// stays still: no clip.
	fp := &v.first_person
	if fp.exits != s.first_person_exits {
		s.first_person_exits = fp.exits
		lab_sound_queue(s, LAB_FIRST_PERSON_EXIT, now)
	}
	if fp.shots != s.first_person_shots {
		s.first_person_shots = fp.shots
		lab_sound_queue(s, LAB_FIRST_PERSON_SHOT, now, 0.8)
	}
	if fp.hits != s.first_person_hits {
		s.first_person_hits = fp.hits
		lab_sound_queue(s, LAB_FIRST_PERSON_HIT, now+0.04, 0.9)
	}
	if fp.ricochets != s.first_person_ricochets {
		s.first_person_ricochets = fp.ricochets
		lab_sound_queue(s, LAB_FIRST_PERSON_RICOCHET, now+0.04, 0.8)
	}
	// FIRST PERSON BRAWLER: a punch's air as it leaves, its blow (or the
	// critical's ding) as it lands on the struck foe's side, a mark's tick.
	if fp.fists_thrown != s.fists_thrown {
		s.fists_thrown = fp.fists_thrown
		lab_sound_queue(s, LAB_FISTS_WHOOSH, now, 0.7, 0, LAB_FISTS_WHOOSH_PITCH[fp.fists_thrown_punch])
	}
	if fp.fists_landed != s.fists_landed {
		s.fists_landed = fp.fists_landed
		pan := lab_sound_pan(renderer, game.enemy_entity(fp.fists_struck))
		lab_sound_queue(s, LAB_FISTS_CRIT if fp.fists_hit_crit else LAB_FISTS_HIT[fp.fists_landed_punch], now, 1, pan)
	}
	if fp.fists_marks_lit != s.fists_marks_lit {
		s.fists_marks_lit = fp.fists_marks_lit
		lab_sound_queue(s, LAB_FISTS_MARK, now, 0.5, 0, LAB_FISTS_MARK_PITCH[clamp(int(fp.fists_lit_zone), 0, 3)])
	}
	// The cues now showing, each once; the cards first, so what they put on
	// the board knows they already sounded. What was heard is kept on the
	// world's clock: a cue the shadow holds still is never heard again.
	impacts := 0
	world := tactical_world_time_at(renderer, now)
	for cards in ([2]bool{true, false}) {
		for offset in 0..<renderer_active_cue_count(renderer) {
			cue, found := renderer_active_cue_at(renderer, offset)
			if !found || !cue.started || (cue.kind == .Card_Played) != cards || lab_sound_heard(s, cue.kind, cue.event, world, cue.batch) { continue }
			lab_cue_sounds(renderer, s, cue, now, &impacts)
		}
	}
	// A discharge strikes along every link at once: one zap. (The ring's
	// chord is for the square closing into the Ring, lab_watch_room.)
	if impacts > 0 { lab_sound_queue(s, .World_Tesla_Zap, now) }
	lab_watch_room(s, room, now)
}

// The room's own moments: the clock, criticals, the window, the defence.
@(private)
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
	} else if room.phase == .Combat {
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
		pitch := sound.pitch if sound.pitch > 0 else 1
		audio.lab_play(bank, sound.sfx, volume*gain, pitch*(1+0.04*wobble), sound.pan)
	}
	s.count = kept
}
