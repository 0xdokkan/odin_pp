package render

import "core:c"
import "core:fmt"
import "core:math"
import rl "vendor:raylib"
import rlgl "vendor:raylib/rlgl"
import gfx "../engine/gfx"
import game "../game"
import grid "../engine/grid"
import view "../engine/view"

// CANNA DA PESCA on the board (game/fishing.odin), cut from paper like the
// cards and the props. Once the room is cleared its slot stands at the right
// of the footer, where a hand's card would: the rod's card with PESCA n/m
// (the room's fishings left, of its own), picked up and dropped on a cell or
// chosen and then a cell clicked, as a card is. While it is held, the cells it
// may fish within its reach are marked blue, the water already there
// brighter, and the cell under the mouse green (or red where it may not).
// The water is the ground's decal in blue (ground_fx.odin's Water layer: paper
// and ink round it, two rings of ripples baked round each cell's middle),
// with rings of light spreading on it. A fishing is three cues, about three
// seconds (presentation_timeline.odin): the cast, the paper rod swung back and
// out over the water, its line flying with the bobber to the cell (the water
// shows from its plop); the bite, the bobber floating on its ring until it
// dips under with a splash and a paper "!"; the catch, the rod pulled up, the
// catch out of the water in a spray of drops and flying to the player on an
// arc, its line after it (a caught card hangs over him a moment, CARTA
// PESCATA and its name below the board; food says its name over him, its d4
// and its green token follow). The player's card rises into its cast as the
// rod is cast (living_cue_action: never the lantern's blow and back flip),
// then holds the rod still (it channels) while the rod reels the catch in; it
// turns to face the water. Nothing here gates gameplay or input: the cues
// alone hold the player's lane while they play.

FISHING_WATER_LIGHT :: rl.Color{140, 200, 240, 255}
FISHING_BITE_RED :: rl.Color{226, 58, 52, 255}
// A held prop's texels, times these: the rod reaches out a long arm's length,
// and what it catches shows plainly.
FISHING_ROD_SCALE :: f32(1.25)
FISHING_CATCH_SCALE :: f32(1.8)
FISHING_BOBBER_SCALE :: f32(1.5)
FISHING_LINE_POINTS :: 14
// The cast's moments, as shares of its cue: the rod is wound back, then swung
// out; the bobber leaves its tip and lands as the cue ends.
FISHING_CAST_BACK :: f32(0.3)
FISHING_CAST_RELEASE :: f32(0.52)
// The bite's: the bobber floats until it dips under (the splash, the "!").
FISHING_BITE_AT :: f32(0.64)
// The catch's: reeled up out of the water (it breaks the surface at this
// share of the reeling), then its flight to the player (a card lands over him
// early, then hangs there; food is taken at this share of its flight).
FISHING_REEL :: f32(0.36)
FISHING_REEL_BREAKS :: f32(0.3)
FISHING_CARD_LANDS :: f32(0.42)
FISHING_FOOD_TAKEN :: f32(0.94)
FISHING_SPLASH_SECONDS :: f32(0.42)

// The pieces drawn with the cards and walls (Tactical_Alpha_Entry.fishing).
Fishing_Piece :: enum i32 {Rod, Bobber, Catch}

// What makes a cue this one, whichever frame shows it.
Fishing_Cue_Key :: struct {
	batch: u32,
	kind: Presentation_Cue_Kind,
}

// The fishing as the board shows it this frame (fishing_pose).
Fishing_Pose :: struct {
	shown: bool,
	kind: Presentation_Cue_Kind,
	// The cue's progress and seconds, and its event.
	u, duration: f32,
	event: game.Game_Event,
	cell: grid.Position,
	// The rod: its grip in the hand and its tip; its line's end and slack.
	grip, tip: rl.Vector3,
	line_end: rl.Vector3,
	line_shown: bool,
	sag: f32,
	bobber: rl.Vector3,
	bobber_shown: bool,
	// What it caught, in the air, and how far it has turned.
	catch: rl.Vector3,
	catch_shown: bool,
	catch_turn: f32,
	// Seconds since the bite (negative before it): its splash and its "!".
	bite: f32,
	// Seconds since the catch broke the water (negative before): its spray.
	spray: f32,
}

Fishing_View :: struct {
	pose: Fishing_Pose,
	seen: [8]Fishing_Cue_Key,
	seen_next: int,
	// What the board has shown so far (the smoke and tests): casts, bites,
	// catches and the cards among them.
	casts, bites, catches, cards: int,
}

// A fresh board: what was shown goes, the counts stay.
@(private)
fishing_view_reset :: proc(f: ^Fishing_View) {
	f^ = {casts = f.casts, bites = f.bites, catches = f.catches, cards = f.cards}
}

@(private)
destroy_fishing_view :: proc(renderer: ^Renderer) {
	if renderer != nil { renderer.tactical.fishing = {} }
}

@(private)
fishing_cue_kind :: proc(kind: Presentation_Cue_Kind) -> bool {
	return kind == .Fish_Cast || kind == .Fish_Bite || kind == .Fish_Caught
}

// The fishing cue the board shows now: always the player's own, in the
// foreground (the game's fish_with_rod is his command).
@(private = "file")
fishing_active_cue :: proc(renderer: ^Renderer) -> (^Presentation_Cue, bool) {
	if renderer == nil { return nil, false }
	cue, found := active_presentation_cue(&renderer.timeline)
	if !found || !cue.started || !fishing_cue_kind(cue.kind) { return nil, false }
	return cue, true
}

// The rod is out over the water: the player's card holds it, channeling.
@(private)
fishing_cue_showing :: proc(renderer: ^Renderer) -> bool {
	_, found := fishing_active_cue(renderer)
	return found
}

// The fishing and what follows it (its d4) show: the HUD says PESCA.
@(private)
fishing_in_progress :: proc(renderer: ^Renderer) -> bool {
	if fishing_cue_showing(renderer) { return true }
	cue, found := active_presentation_cue(&renderer.timeline)
	return found && cue.kind == .Dice_Rolled && cue.event.card_definition == .Fishing_Rod
}

// What a catch says: the food's name, or that a card was caught.
@(private)
fishing_catch_label :: proc(event: game.Game_Event) -> cstring {
	if event.card_definition != .Fishing_Rod { return "CARTA PESCATA" }
	if event.duration < 0 || event.duration > i32(max(game.Fishing_Food)) { return "PESCATO" }
	return fmt.ctprintf("%s", game.fishing_food_name(game.Fishing_Food(event.duration)))
}

// The words under the board, where a played card's show: the rod's name as
// it is cast, and a caught card's.
@(private)
fishing_cue_banner :: proc(cue: ^Presentation_Cue) -> (label: cstring, accent: rl.Color, shown: bool) {
	#partial switch cue.kind {
	case .Fish_Cast:
		definition, found := game.card_definition_by_id(.Fishing_Rod)
		if !found { return }
		return fmt.ctprintf("%s", definition.name), FISHING_WATER_LIGHT, true
	case .Fish_Caught:
		if cue.event.card_definition == .Fishing_Rod { return }
		definition, found := game.card_definition_by_id(cue.event.card_definition)
		if !found { return }
		return fmt.ctprintf("CARTA PESCATA / %s", definition.name), TACTICAL_FEEDBACK_CRITICAL, true
	}
	return
}

// The HUD's line in a cleared room (draw_tactical_hud).
@(private)
fishing_hud_status :: proc(renderer: ^Renderer, room: ^game.Room) -> cstring {
	way: cstring = "F5 RICOMINCIA" if room.endless else "RAGGIUNGI L'USCITA"
	if fishing_in_progress(renderer) { return "PESCA IN CORSO" }
	if !game.fishing_room_open(room) { return "ARENA LIBERA / F5 RICOMINCIA" if room.endless else "RACCOGLI IL BOTTINO / RAGGIUNGI L'USCITA" }
	left := game.fishing_casts_left(room)
	if left <= 0 { return fmt.ctprintf("PESCHE FINITE / %s", way) }
	return fmt.ctprintf("CANNA DA PESCA %d/%d / %s", left, game.fishing_casts_allowed(room), way)
}

// --------------------------------------------------------------------------
// Following the cues.

// Once per frame (update_tactical_view, which may run twice a frame): each
// fishing cue counted as it starts showing; the player's card turned to the
// water as he casts.
@(private)
update_tactical_fishing :: proc(renderer: ^Renderer) {
	f := &renderer.tactical.fishing
	cue, found := fishing_active_cue(renderer)
	if !found { return }
	key := Fishing_Cue_Key{batch = cue.batch, kind = cue.kind}
	seen := false
	for previous in f.seen { if previous == key && key.batch != 0 { seen = true; break } }
	if !seen {
		f.seen[f.seen_next] = key
		f.seen_next = (f.seen_next+1)%len(f.seen)
		#partial switch cue.kind {
		case .Fish_Cast: f.casts += 1
		case .Fish_Bite: f.bites += 1
		case .Fish_Caught:
			f.catches += 1
			if cue.event.card_definition != .Fishing_Rod { f.cards += 1 }
		}
	}
	if cue.kind == .Fish_Cast && renderer.tactical.living {
		if pivot := living_find(renderer, game.PLAYER_ENTITY, .Pilgrim); pivot != nil {
			p := renderer.tactical.snapshot.player.position
			cell := cue.event.to_position
			d := rl.Vector3{f32(cell.x)-p.x, 0, f32(cell.y)-p.y}
			living_face(pivot, rl.Vector3DotProduct(d, flipbook_camera_right(renderer)), renderer.sprite_assets.elapsed)
		}
	}
}

// The far end of a prop laid by draw_attack_prop from `grip` toward `long`:
// the prop keeps its own length, in the plane facing the eye.
@(private = "file")
fishing_prop_end :: proc(renderer: ^Renderer, prop: gfx.Attack_Prop, grip, long: rl.Vector3, texel: f32) -> rl.Vector3 {
	camera := renderer.tactical.camera
	view_dir := rl.Vector3Normalize(camera.target-camera.position)
	along := long-view_dir*rl.Vector3DotProduct(long, view_dir)
	if rl.Vector3Length(along) < 0.0001 { along = rl.Vector3{0, 1, 0}-view_dir*view_dir.y }
	if rl.Vector3Length(along) < 0.0001 { along = {1, 0, 0} }
	return grip+rl.Vector3Normalize(along)*attack_prop_length(prop, texel)
}

@(private = "file")
fishing_smooth :: proc(u: f32) -> f32 {
	v := clamp(u, 0, 1)
	return v*v*(3-2*v)
}

// The rod's lean from upright toward the water's side of the screen
// (radians) at `u` of a cue.
@(private = "file")
fishing_rod_angle :: proc(kind: Presentation_Cue_Kind, u: f32, now: f64) -> f32 {
	#partial switch kind {
	case .Fish_Cast:
		switch {
		case u < FISHING_CAST_BACK: return 0.75+(-0.45-0.75)*fishing_smooth(u/FISHING_CAST_BACK)
		case u < FISHING_CAST_RELEASE:
			// The whip forward, fast at once.
			return -0.45+(1.2+0.45)*attack_ease_out((u-FISHING_CAST_BACK)/(FISHING_CAST_RELEASE-FISHING_CAST_BACK))
		}
		return 1.2+(0.85-1.2)*fishing_smooth((u-FISHING_CAST_RELEASE)/(1-FISHING_CAST_RELEASE))
	case .Fish_Bite:
		if u < FISHING_BITE_AT { return 0.85+0.03*f32(math.sin(now*2.6)) }
		// The bite tugs the tip down.
		return 0.85+0.18*fishing_smooth((u-FISHING_BITE_AT)/0.08)+0.04*f32(math.sin(now*24))
	case .Fish_Caught:
		if u < FISHING_REEL { return 1.0+(0.2-1.0)*attack_ease_out(u/FISHING_REEL) }
		return 0.2+(0.55-0.2)*fishing_smooth((u-FISHING_REEL)/(1-FISHING_REEL))
	}
	return 0.85
}

// The fishing on the 3D board this frame, from its cue.
@(private = "file")
fishing_pose :: proc(renderer: ^Renderer) -> (pose: Fishing_Pose) {
	cue, found := fishing_active_cue(renderer)
	if !found { return }
	feet, height, ok := attack_card(renderer, game.PLAYER_ENTITY)
	if !ok { return }
	pose.shown, pose.kind, pose.event = true, cue.kind, cue.event
	pose.u, pose.duration = presentation_cue_progress(cue), cue.duration
	pose.cell = cue.event.to_position if cue.kind == .Fish_Cast else cue.event.from_position
	pose.bite, pose.spray = -1, -1
	now := renderer.sprite_assets.elapsed
	up := rl.Vector3{0, 1, 0}
	right := flipbook_camera_right(renderer)
	toward := attack_toward_camera(renderer)
	water := attack_cell_center(pose.cell, GROUND_DECAL_HEIGHT+0.02)
	away := rl.Vector3{water.x-feet.x, 0, water.z-feet.z}
	if rl.Vector3Length(away) < 0.001 { away = right }
	away = rl.Vector3Normalize(away)
	side := f32(1) if rl.Vector3DotProduct(away, right) >= 0 else -1
	// The rod leans from upright toward the water's side of the screen, as a
	// cut-out held up to the eye.
	_, screen_up := attack_screen_axes(renderer)
	pose.grip = feet+up*(height*0.46)+right*(0.13*side)+toward*0.06
	angle := fishing_rod_angle(cue.kind, pose.u, now)
	pose.tip = fishing_prop_end(renderer, .Rod, pose.grip, screen_up*math.cos(angle)+right*(side*math.sin(angle)),
		attack_texel(.Pilgrim)*FISHING_ROD_SCALE)
	chest := feet+up*(height*0.62)+toward*0.1
	pose.line_shown, pose.bobber_shown = true, true
	#partial switch cue.kind {
	case .Fish_Cast:
		if pose.u < FISHING_CAST_RELEASE {
			pose.bobber = pose.tip-up*0.1
		} else {
			p := (pose.u-FISHING_CAST_RELEASE)/(1-FISHING_CAST_RELEASE)
			e := attack_ease_out(p)
			pose.bobber = pose.tip+(water-pose.tip)*e+up*(math.sin(p*math.PI)*0.5)
		}
		pose.sag = 0.02
	case .Fish_Bite:
		pose.bobber = water+up*(0.03+0.012*f32(math.sin(now*6.5)))
		pose.sag = 0.2
		if pose.u >= FISHING_BITE_AT {
			pose.bite = (pose.u-FISHING_BITE_AT)*cue.duration
			dip := fishing_smooth(pose.bite/0.07)
			pose.bobber.y -= 0.075*dip-0.012*f32(math.sin(now*30))*dip
			pose.sag = 0.04
		}
	case .Fish_Caught:
		pose.catch_shown = true
		food := cue.event.card_definition == .Fishing_Rod
		flight := f32(1) if food else FISHING_CARD_LANDS
		risen := water+up*0.42+toward*0.05
		switch {
		case pose.u < FISHING_REEL:
			q := pose.u/FISHING_REEL
			pose.catch = water+up*(0.02+0.4*attack_ease_out(q))+toward*0.05*q
			// It breaks the water a third of the way up.
			pose.spray = (pose.u-FISHING_REEL*FISHING_REEL_BREAKS)*cue.duration
		case pose.u < flight:
			p := (pose.u-FISHING_REEL)/(flight-FISHING_REEL)
			e := fishing_smooth(p)
			pose.catch = risen+(chest-risen)*e+up*(math.sin(p*math.PI)*0.55)
			pose.spray = (pose.u-FISHING_REEL*FISHING_REEL_BREAKS)*cue.duration
			// Food is taken as it reaches him.
			if food && p > FISHING_FOOD_TAKEN { pose.catch_shown = false }
		case:
			// A card hangs over him, its name below the board.
			pose.catch = feet+up*(height+0.24+0.03*f32(math.sin(now*3)))+toward*0.12
		}
		pose.catch_turn = pose.u*7
		pose.bobber = pose.catch+up*0.17
		pose.sag = 0.05
		if !pose.catch_shown || pose.u >= flight {
			// The line drops slack from the tip.
			pose.bobber = pose.tip-up*0.18
			pose.sag = 0
		}
	case:
		pose.shown = false
	}
	pose.line_end = pose.bobber
	return
}

// --------------------------------------------------------------------------
// The sorted pass.

// The rod with its line (just in front of the player's card), the bobber and
// what it caught, sorted with the cards and walls (one entry each).
@(private)
collect_fishing_entries :: proc(renderer: ^Renderer, entries: ^[dynamic]Tactical_Alpha_Entry) {
	f := &renderer.tactical.fishing
	f.pose = fishing_pose(renderer)
	pose := &f.pose
	if !pose.shown || !renderer.tactical.attack_props.loaded { return }
	toward := attack_toward_camera(renderer)
	at := pose.grip+toward*0.3
	append(entries, Tactical_Alpha_Entry{kind = .Fishing, fishing = .Rod, position = {at.x-0.5, at.z-0.5}})
	if pose.bobber_shown {
		at = pose.bobber+toward*0.12
		append(entries, Tactical_Alpha_Entry{kind = .Fishing, fishing = .Bobber, position = {at.x-0.5, at.z-0.5}})
	}
	if pose.catch_shown || pose.spray >= 0 {
		at = pose.catch+toward*0.25
		append(entries, Tactical_Alpha_Entry{kind = .Fishing, fishing = .Catch, position = {at.x-0.5, at.z-0.5}})
	}
}

@(private)
draw_fishing_entry :: proc(renderer: ^Renderer, entry: Tactical_Alpha_Entry) {
	pose := &renderer.tactical.fishing.pose
	if !pose.shown { return }
	rlgl.DrawRenderBatchActive()
	rlgl.DisableBackfaceCulling()
	defer { rlgl.DrawRenderBatchActive(); rlgl.EnableBackfaceCulling() }
	texel := attack_texel(.Pilgrim)
	right, up := attack_screen_axes(renderer)
	switch entry.fishing {
	case .Rod:
		draw_attack_prop(renderer, .Rod, pose.grip, pose.tip, texel*FISHING_ROD_SCALE, 1)
		if pose.line_shown { draw_fishing_line(renderer, pose.tip, pose.line_end, pose.sag) }
	case .Bobber:
		if pose.bobber_shown {
			draw_attack_prop(renderer, .Bobber, pose.bobber, pose.bobber+rl.Vector3{0, 1, 0}, texel*FISHING_BOBBER_SCALE, 1)
		}
		// The bite: a splash of drops and a paper "!" over the bobber.
		if pose.bite >= 0 {
			draw_fishing_splash(renderer, attack_cell_center(pose.cell, 0.05), pose.bite, 7, pose.cell.x*5+pose.cell.y*3)
			pop := f32(1.5) if pose.bite < 0.06 else 1
			bang := pose.bobber+rl.Vector3{0, 0.42, 0}
			draw_attack_prop(renderer, .Bang, bang, bang+up, texel*1.6*pop, clamp(pose.bite/0.04, 0, 1))
		}
		// The plop, as the bite's cue starts.
		if pose.kind == .Fish_Bite && pose.bite < 0 {
			draw_fishing_splash(renderer, attack_cell_center(pose.cell, 0.05), pose.u*pose.duration, 4, pose.cell.x*3+pose.cell.y*7)
		}
	case .Catch:
		if pose.spray >= 0 { draw_fishing_splash(renderer, attack_cell_center(pose.cell, 0.05), pose.spray, 8, pose.cell.x*11+pose.cell.y) }
		if !pose.catch_shown { return }
		prop := gfx.Attack_Prop.Card_Back
		if pose.event.card_definition == .Fishing_Rod { prop = fishing_food_prop(game.Fishing_Food(clamp(pose.event.duration, 0, i32(max(game.Fishing_Food))))) }
		turn := pose.catch_turn
		// A card held over him faces the eye, upright.
		if pose.event.card_definition != .Fishing_Rod && pose.u >= FISHING_CARD_LANDS { turn = 0 }
		draw_attack_prop(renderer, prop, pose.catch, pose.catch+up*math.cos(turn)+right*math.sin(turn), texel*FISHING_CATCH_SCALE, 1)
	}
}

@(private = "file")
fishing_food_prop :: proc(food: game.Fishing_Food) -> gfx.Attack_Prop {
	switch food {
	case .Fish: return .Fish
	case .Apple: return .Apple
	case .Bread: return .Bread
	case .Cheese: return .Cheese
	case .Meat: return .Meat
	}
	return .Fish
}

// Drops of water thrown up from `at`, `t` seconds after it was struck.
@(private = "file")
draw_fishing_splash :: proc(renderer: ^Renderer, at: rl.Vector3, t: f32, count, seed: int) {
	p := t/FISHING_SPLASH_SECONDS
	if p < 0 || p > 1 { return }
	right, up := attack_screen_axes(renderer)
	toward := attack_toward_camera(renderer)
	texel := attack_texel(.Pilgrim)
	for drop in 0..<count {
		angle := f32(drop)*math.TAU/f32(count)+f32(seed%7)*0.4
		out := right*math.cos(angle)+toward*math.sin(angle)*0.6
		speed := 0.36+f32((seed+drop*5)%4)*0.07
		point := at+out*(speed*p)+rl.Vector3{0, 0.8*p-0.75*p*p, 0}
		prop := gfx.Attack_Prop.Wet_A if drop%2 == 0 else gfx.Attack_Prop.Wet_B
		turn := p*6+f32(drop)
		draw_attack_prop(renderer, prop, point, point+up*math.cos(turn)+right*math.sin(turn), texel*1.4, clamp((1-p)*2.5, 0, 1))
	}
}

// The line, a thin strip of ink in its paper margin from the rod's tip to
// `end`, sagging by `sag` of its length.
@(private = "file")
draw_fishing_line :: proc(renderer: ^Renderer, tip, end: rl.Vector3, sag: f32) {
	camera := renderer.tactical.camera
	view_dir := rl.Vector3Normalize(camera.target-camera.position)
	length := rl.Vector3Distance(tip, end)
	if length < 0.01 { return }
	middle := (tip+end)*0.5-rl.Vector3{0, length*sag, 0}
	points: [FISHING_LINE_POINTS]rl.Vector3
	for index in 0..<FISHING_LINE_POINTS {
		t := f32(index)/f32(FISHING_LINE_POINTS-1)
		points[index] = tip*((1-t)*(1-t))+middle*(2*t*(1-t))+end*(t*t)
	}
	texel := attack_texel(.Pilgrim)
	// Plain colour: the batch would otherwise keep the props' atlas bound.
	rlgl.SetTexture(rlgl.GetTextureIdDefault())
	defer rlgl.SetTexture(0)
	for layer in 0..<2 {
		half := texel*(1.15 if layer == 0 else 0.42)
		colour := LIVING_TOKEN_PAPER if layer == 0 else LIVING_TOKEN_INK
		rlgl.Begin(rlgl.QUADS)
		rlgl.Color4ub(colour.r, colour.g, colour.b, 255)
		for index in 0..<FISHING_LINE_POINTS-1 {
			a, b := points[index], points[index+1]
			side := rl.Vector3CrossProduct(b-a, view_dir)
			if rl.Vector3Length(side) < 0.000001 { continue }
			side = rl.Vector3Normalize(side)*half
			// Each piece reaches half a width past its ends: no gap at a bend.
			along := rl.Vector3Normalize(b-a)*(half*0.5)
			corners := [4]rl.Vector3{a-along+side, a-along-side, b+along-side, b+along+side}
			for corner in corners { rlgl.Vertex3f(corner.x, corner.y, corner.z) }
		}
		rlgl.End()
	}
}

// Rings of light spreading on the water (after the ground's decal): two on
// each cell of it, slowly, and a quick one where the bobber plops, where the
// fish bites and where the catch breaks the water.
@(private)
draw_fishing_ripples :: proc(renderer: ^Renderer) {
	v := &renderer.tactical
	if v.snapshot == nil { return }
	ground := &v.snapshot.ground
	world := tactical_world_time(renderer)
	for water, index in ground.water[:clamp(ground.water_count, 0, len(ground.water))] {
		if !tactical_cell_on_screen(renderer, water) || !tactical_render_visible(renderer, water) { continue }
		centre := rl.Vector3{f32(water.x)+0.5, GROUND_DECAL_HEIGHT+0.004, f32(water.y)+0.5}
		for ring in 0..<2 {
			r := f32(math.mod(world*0.45+f64(ring)*0.5+f64(index)*0.31, 1))
			rl.DrawCircle3D(centre, 0.06+0.3*r, {1, 0, 0}, 90, color_with_opacity(GROUND_WATER_GLINT, (1-r)*0.5))
		}
	}
	cue, found := fishing_active_cue(renderer)
	if !found || cue.kind == .Fish_Cast { return }
	cell := cue.event.from_position
	if !tactical_render_visible(renderer, cell) { return }
	centre := rl.Vector3{f32(cell.x)+0.5, GROUND_DECAL_HEIGHT+0.006, f32(cell.y)+0.5}
	u := presentation_cue_progress(cue)
	moments := [2]f32{0, FISHING_BITE_AT} if cue.kind == .Fish_Bite else [2]f32{FISHING_REEL*FISHING_REEL_BREAKS, -1}
	for moment in moments {
		if moment < 0 || u < moment { continue }
		t := (u-moment)*cue.duration/0.6
		if t > 1 { continue }
		for ring in 0..<2 {
			r := clamp(t*1.2-f32(ring)*0.25, 0, 1)
			if r <= 0 { continue }
			rl.DrawCircle3D(centre, 0.05+0.42*r, {1, 0, 0}, 90, color_with_opacity(GROUND_WATER_GLINT, (1-r)*0.85))
		}
	}
}

// --------------------------------------------------------------------------
// --------------------------------------------------------------------------
// The slot and the aim.

// The rod's slot once the room is cleared: the size of a hand's card, at the
// right of the footer (the cleared room's controls keep its left: m8_bar_bounds).
fishing_slot_bounds :: proc(renderer: ^Renderer) -> rl.Rectangle {
	bar := m8_bar_bounds(renderer, true)
	width := min(f32(166), bar.width*0.22-6)
	return {bar.x+bar.width-width, renderer.canvas_height-160, width, 154}
}

// The slot (draw_tactical_hand, the room cleared): the rod's card with PESCA
// n/m over it (the fishings left of the room's), dimmed once they are spent
// or while the board shows an action; the hint above it, the inspector while
// it is under the mouse or held, its name by the mouse while it is dragged.
@(private)
draw_fishing_slot :: proc(renderer: ^Renderer, room: ^game.Room, hovered, selected, dragged: u32, mouse: view.Vec2) {
	if !game.fishing_room_open(room) { return }
	rod, held := game.fishing_rod(&room.player.deck)
	definition, found := game.card_definition_by_id(.Fishing_Rod)
	if !held || !found { return }
	bounds := fishing_slot_bounds(renderer)
	left, total := game.fishing_casts_left(room), game.fishing_casts_allowed(room)
	busy := renderer_blocks_player_input(renderer)
	rl.DrawRectangleGradientV(c.int(bounds.x-14), c.int(bounds.y-34), c.int(bounds.width+28), c.int(bounds.height+40), {8, 13, 21, 0}, {8, 13, 21, 230})
	draw_tactical_card(renderer, bounds, rod, definition, -1, true, rod.id == selected || rod.id == dragged, rod.id == hovered, left > 0 && !busy)
	ribbon := rl.Rectangle{math.round(bounds.x+bounds.width*0.5-42), bounds.y-11, 84, 20}
	rl.DrawRectangleRec(ribbon, rl.Color{16, 38, 62, 245} if left > 0 else rl.Color{38, 40, 44, 245})
	rl.DrawRectangleLinesEx(ribbon, 1, FISHING_WATER_LIGHT if left > 0 else GOTHIC_STEEL)
	label := fmt.ctprintf("PESCA %d/%d", left, total)
	gothic_text(renderer, label, ribbon.x+(ribbon.width-gothic_text_width(renderer, label, 14))*0.5, ribbon.y+2, 14,
		GOTHIC_PAPER if left > 0 else GOTHIC_MUTED)
	hint: cstring = "TRASCINA SU UNA CASELLA" if left > 0 else "PESCHE FINITE"
	if rod.id == selected { hint = "SCEGLI L'ACQUA / DESTRO: ANNULLA" }
	if rod.id == dragged { hint = "LASCIA SU UNA CASELLA" }
	// The board still shows an action: a fishing, or the room's last falls.
	if busy { hint = "PESCA IN CORSO" if fishing_in_progress(renderer) else "ATTENDI" }
	width := gothic_text_width(renderer, hint, 10)
	gothic_text(renderer, hint, math.round(bounds.x+bounds.width-width), bounds.y-27, 10, GOTHIC_BLUE if left > 0 else GOTHIC_MUTED)
	if rod.id == hovered || rod.id == selected || rod.id == dragged {
		_, effect := tactical_inspector_effect(renderer, room, hovered, selected, dragged)
		draw_tactical_card_inspector(renderer, rod, definition, rod.id == selected, effect, tactical_inspector_effect_ready(renderer, room))
	}
	if rod.id == dragged { gothic_text(renderer, fmt.ctprintf("%s", definition.name), mouse.x+14, mouse.y-18, 16, GOTHIC_PAPER) }
}

// While the rod is held (picked up or chosen): the cells it may fish within
// its reach blue, the water already there brighter, and the cell under the
// mouse green, or red where it may not fish.
@(private)
draw_fishing_target_range :: proc(renderer: ^Renderer, room: ^game.Room, card_id: u32) {
	if renderer == nil || room == nil || room.player == nil || room.level_data == nil || card_id == 0 || !game.fishing_room_open(room) { return }
	rod, held := game.fishing_rod(&room.player.deck)
	if !held || rod.id != card_id { return }
	centre := room.player.position
	for dy in -game.FISHING_RANGE..=game.FISHING_RANGE {
		for dx in -game.FISHING_RANGE..=game.FISHING_RANGE {
			cell := grid.Position{centre.x+dx, centre.y+dy}
			if game.fishing_target_error(room, cell) != .Fished { continue }
			if game.fishing_cell_is_water(room, cell) {
				draw_card_range_cell(renderer, cell, {70, 150, 220, 96}, {160, 214, 250, 255})
			} else {
				draw_card_range_cell(renderer, cell, {56, 132, 206, 84}, {130, 196, 246, 230})
			}
		}
	}
	if !renderer.has_hovered_cell { return }
	if game.fishing_target_error(room, renderer.hovered_cell) == .Fished {
		draw_card_range_cell(renderer, renderer.hovered_cell, {74, 196, 133, 96}, {123, 235, 169, 255})
	} else {
		draw_card_range_cell(renderer, renderer.hovered_cell, {190, 68, 70, 76}, {235, 91, 91, 255})
	}
}

// The share of a food catch's cue at which it reaches his hand (the lab's
// catch sounds then: lab_cue_sounds).
@(private)
fishing_food_taken :: proc() -> f32 {
	return FISHING_REEL+(1-FISHING_REEL)*FISHING_FOOD_TAKEN
}
