package render

import "core:fmt"
import "core:math"
import rl "vendor:raylib"
import rlgl "vendor:raylib/rlgl"
import game "../game"

// LANCIAFIAMME on the board (game/first_person_flame.odin, docs/piano-ia.md, Fase 14).
//
// THE WEAPON, in his hands: a 3D paper model made from code with the kit of the ace of clubs (napoli_models.odin), each part
// in three flat tones with the board's ink round it: two red tanks on his back, a hose to the gun, the gun in both hands, its
// brass nozzle pointing exactly where the rules turn him. His card turns to the side he aims at.
//
// THE FLAME: the rules' pieces are already left in the world, so it bends and stays behind him as water from a hose. Each
// piece draws three puffs from a fixed count, with no memory taken a frame and one blend for them all: white and yellow at
// the nozzle, then orange and red, dark smoke over the tip. It lights the floor orange; faint wavering puffs over it are the
// hot air. A foe burning keeps a small flame on his card (in the lab, where this card lives).

FLAME_CHIP_COLOR :: rl.Color{255, 140, 40, 255}
// Where the gun is in his frame (X his right, Y up, Z his front).
FLAME_GRIP_SIDE :: f32(0.2)
FLAME_GRIP_HEIGHT :: f32(0.62)
// Where the nozzle ends, ahead of him.
FLAME_NOZZLE_REACH :: f32(0.72)
FLAME_TEXTURE_SIZE :: 32
FLAME_PUFFS :: 3
// Seconds between the roar's clips (each a little longer, so they overlap).
FLAME_ROAR_SECONDS :: f64(0.5)

FLAME_TANK :: rl.Color{176, 50, 40, 255}
FLAME_TANK_DARK :: rl.Color{112, 32, 30, 255}
FLAME_STEEL :: rl.Color{92, 98, 112, 255}
FLAME_STEEL_DARK :: rl.Color{52, 56, 68, 255}
FLAME_BRASS :: rl.Color{206, 160, 72, 255}
FLAME_HOSE :: rl.Color{36, 36, 44, 255}
FLAME_WOOD :: rl.Color{122, 78, 44, 255}
FLAME_HAND :: rl.Color{232, 220, 190, 255}

// What the board keeps of it: its soft puff, and the rules' counters as last heard.
Flame_View :: struct {
	puff: rl.Texture2D,
	firing: bool,
	hits, fires, barrels: i32,
	roar_next: f64,
}

@(private)
destroy_flame_view :: proc(v: ^Flame_View) {
	if v.puff.id != 0 { rl.UnloadTexture(v.puff) }
	v^ = {}
}

@(private = "file")
flame_puff_texture :: proc() -> rl.Texture2D {
	if !rl.IsWindowReady() { return {} }
	pixels: [FLAME_TEXTURE_SIZE*FLAME_TEXTURE_SIZE]rl.Color
	half := f32(FLAME_TEXTURE_SIZE)/2
	for y in 0..<FLAME_TEXTURE_SIZE {
		for x in 0..<FLAME_TEXTURE_SIZE {
			dx, dy := (f32(x)+0.5-half)/half, (f32(y)+0.5-half)/half
			k := clamp(1-math.sqrt(dx*dx+dy*dy), 0, 1)
			pixels[y*FLAME_TEXTURE_SIZE+x] = {255, 255, 255, u8(255*math.pow(k, 1.4))}
		}
	}
	image := rl.Image{data = raw_data(pixels[:]), width = FLAME_TEXTURE_SIZE, height = FLAME_TEXTURE_SIZE, mipmaps = 1, format = .UNCOMPRESSED_R8G8B8A8}
	return rl.LoadTextureFromImage(image)
}

// The colour of the flame `k` of its way along (0 the nozzle, 1 the tip).
flame_color :: proc(k: f32) -> rl.Color {
	stops := [4]rl.Color{{255, 244, 214, 255}, {255, 206, 92, 255}, {255, 122, 34, 255}, {196, 40, 22, 255}}
	at := clamp(k, 0, 1)*f32(len(stops)-1)
	index := min(int(at), len(stops)-2)
	return rl.ColorLerp(stops[index], stops[index+1], at-f32(index))
}

// The chip under VITA: FIAMMA 14s.
flame_chip :: proc(room: ^game.Room, short: bool) -> (text: cstring, shown: bool) {
	if !game.first_person_flame_active(room) { return }
	left := int(math.ceil(room.first_person.remaining-0.0001))
	return fmt.ctprintf("%s %ds", "LNF" if short else "FIAMMA", left), true
}

// The point of the board under `mouse` (a canvas point), on the floor he stands on, in cells.
tactical_board_point :: proc(renderer: ^Renderer, room: ^game.Room, mouse: [2]f32) -> (point: [2]f32, ok: bool) {
	if renderer == nil || room == nil || room.player == nil || renderer.canvas_width <= 0 { return }
	ray := rl.GetScreenToWorldRayEx({mouse.x, mouse.y}, renderer.tactical.camera, i32(renderer.canvas_width), i32(renderer.canvas_height))
	if abs(ray.direction.y) < 0.0001 { return }
	ground := cell_overlay_ground(room.player.position)
	t := (ground-ray.position.y)/ray.direction.y
	if t < 0 { return }
	return {ray.position.x+ray.direction.x*t, ray.position.z+ray.direction.z*t}, true
}

// The way the rules turn him, on the board.
flame_way :: proc(yaw: f32) -> rl.Vector3 { return {math.cos(yaw), 0, math.sin(yaw)} }

// The gun, the tanks and his hands in the frame of a player at `feet` turned to `yaw`, `shake` of a firing tremble.
flame_model :: proc(model: ^Napoli_Model, feet: rl.Vector3, yaw, shake: f32) {
	frame := napoli_model_frame(feet, flame_way(yaw))
	side, y := FLAME_GRIP_SIDE, FLAME_GRIP_HEIGHT
	z := 0.012*math.sin(shake*90)*math.min(shake, 1)
	point :: proc(frame: rl.Matrix, x, y, z: f32) -> rl.Vector3 { return napoli_model_point(frame, {x, y, z}) }
	// The two tanks on his back, their bands and the valve between them.
	for x in ([2]f32{-0.1, 0.1}) {
		napoli_rod(model, point(frame, x, 0.52, -0.26), point(frame, x, 0.98, -0.26), 0.088, FLAME_TANK)
		napoli_disc(model, frame, {x, 0.62, -0.26}, 0.094, 0.03, FLAME_TANK_DARK)
		napoli_disc(model, frame, {x, 0.86, -0.26}, 0.094, 0.03, FLAME_TANK_DARK)
	}
	napoli_box(model, frame, {0, 0.75, -0.2}, {0.3, 0.05, 0.03}, FLAME_HOSE)
	napoli_rod(model, point(frame, -0.1, 1.08, -0.26), point(frame, 0.1, 1.08, -0.26), 0.022, FLAME_BRASS)
	napoli_ball(model, frame, {0, 1.1, -0.26}, {0.036, 0.036, 0.036}, FLAME_BRASS)
	// The hose, from the tank's foot round his side to the gun.
	napoli_rod(model, point(frame, 0.1, 0.48, -0.26), point(frame, 0.3, 0.42, -0.12), 0.024, FLAME_HOSE)
	napoli_rod(model, point(frame, 0.3, 0.42, -0.12), point(frame, 0.3, 0.46, 0.04), 0.024, FLAME_HOSE)
	napoli_rod(model, point(frame, 0.3, 0.46, 0.04), point(frame, side, y-0.04, 0.12+z), 0.024, FLAME_HOSE)
	// The gun: its stock, body and shroud, the igniter under it, the brass nozzle.
	napoli_rod(model, point(frame, side, y-0.02, -0.1+z), point(frame, side, y-0.13, -0.26+z), 0.038, FLAME_WOOD)
	napoli_rod(model, point(frame, side, y, -0.1+z), point(frame, side, y+0.01, 0.34+z), 0.05, FLAME_STEEL_DARK)
	napoli_rod(model, point(frame, side, y+0.01, 0.1+z), point(frame, side, y+0.015, 0.44+z), 0.066, FLAME_STEEL, false)
	for ring in 0..<3 {
		band := 0.16+f32(ring)*0.1+z
		napoli_rod(model, point(frame, side, y+0.012, band), point(frame, side, y+0.012, band+0.03), 0.072, FLAME_STEEL_DARK, false)
	}
	napoli_box(model, frame, {side, y-0.07, 0.42+z}, {0.05, 0.05, 0.1}, FLAME_HOSE)
	napoli_rod(model, point(frame, side, y+0.015, 0.44+z), point(frame, side, y+0.015, FLAME_NOZZLE_REACH-0.02+z), 0.032, FLAME_BRASS, false)
	napoli_ball(model, frame, {side, y+0.015, FLAME_NOZZLE_REACH+z}, {0.048, 0.048, 0.034}, FLAME_BRASS)
	// His two hands on it: the grip and the shroud, the sleeves back to his card.
	grip, fore := point(frame, side, y-0.1, 0.1+z), point(frame, side, y-0.05, 0.32+z)
	napoli_rod(model, point(frame, side, y-0.02, 0.12+z), grip, 0.03, FLAME_WOOD)
	napoli_rod(model, point(frame, side, y-0.02, 0.32+z), fore, 0.026, FLAME_WOOD)
	napoli_rod(model, point(frame, 0.26, 0.74, -0.04), grip, 0.036, FLAME_HAND)
	napoli_rod(model, point(frame, -0.12, 0.74, 0), fore, 0.034, FLAME_HAND)
	napoli_ball(model, rl.Matrix(1), grip, {0.05, 0.05, 0.05}, FLAME_HAND)
	napoli_ball(model, rl.Matrix(1), fore, {0.05, 0.05, 0.05}, FLAME_HAND)
}

// Where his nozzle is, for a player at `feet` turned to `yaw`.
flame_nozzle :: proc(feet: rl.Vector3, yaw: f32) -> rl.Vector3 {
	return napoli_model_point(napoli_model_frame(feet, flame_way(yaw)), {FLAME_GRIP_SIDE, FLAME_GRIP_HEIGHT+0.015, FLAME_NOZZLE_REACH})
}

// Where his feet are on the board as his card shows them.
@(private = "file")
flame_feet :: proc(renderer: ^Renderer) -> rl.Vector3 {
	position := renderer.tactical.snapshot.player.position
	at, _ := living_card_position(renderer, game.PLAYER_ENTITY, .Player, position)
	return {at.x+0.5, entity_point_ground(game.PLAYER_ENTITY, at), at.y+0.5}
}

// In the props' pass: the weapon in his hands.
@(private)
draw_flame_model :: proc(renderer: ^Renderer, room: ^game.Room) {
	if !game.first_person_flame_active(room) || renderer.tactical.snapshot == nil || !renderer.tactical.snapshot.player.visible { return }
	f := &room.first_person.flame
	shake := f32(tactical_world_time(renderer))*f32(1 if f.firing else 0)
	model: Napoli_Model
	flame_model(&model, flame_feet(renderer), f.yaw, shake)
	draw_napoli_model(&renderer.tactical.napoli.models, &model, 1)
}

// Once a frame: his card turns to the side he aims at.
@(private)
follow_flame :: proc(renderer: ^Renderer, room: ^game.Room) {
	if !game.first_person_flame_active(room) || !renderer.tactical.living { return }
	if pivot := living_find(renderer, game.PLAYER_ENTITY, .Pilgrim); pivot != nil {
		living_face(pivot, rl.Vector3DotProduct(flame_way(room.first_person.flame.yaw), flipbook_camera_right(renderer)), renderer.sprite_assets.elapsed)
	}
}

// Its sounds, from what the rules counted (update_lab_sounds): the click on, the roar while it fires, the breath off, the
// crackle on a foe, the dull catch of a barrel or a fire.
@(private)
lab_flame_sounds :: proc(renderer: ^Renderer, room: ^game.Room, s: ^Lab_Sounds, now: f64) {
	v := &renderer.tactical.flame
	active := game.first_person_flame_active(room)
	firing := active && room.first_person.flame.firing
	if firing && !v.firing { lab_sound_queue(s, .World_Flame_On, now); v.roar_next = now }
	if !firing && v.firing { lab_sound_queue(s, .World_Flame_Off, now) }
	v.firing = firing
	if firing && now >= v.roar_next {
		lab_sound_queue(s, .World_Flame_Roar, now, 0.85)
		v.roar_next = now+FLAME_ROAR_SECONDS
	}
	if !active { v.hits, v.fires, v.barrels = 0, 0, 0; return }
	f := &room.first_person.flame
	if f.hits > v.hits { lab_sound_queue(s, .World_Flame_Crackle, now) }
	if f.fires > v.fires || f.barrels > v.barrels { lab_sound_queue(s, .World_Flame_Catch, now) }
	v.hits, v.fires, v.barrels = f.hits, f.fires, f.barrels
}

// The small flame on a foe's card while he burns (in the lab, where this card lives).
@(private = "file")
draw_burning_foes :: proc(renderer: ^Renderer, room: ^game.Room, puff: rl.Texture2D, t: f32) {
	if !renderer.tactical.mechanics_lab { return }
	for &enemy in room.enemies {
		status, found := game.status_for_entity(room, game.enemy_entity(enemy.id), .Burn)
		if !found || status.potency <= 0 || !tactical_render_visible(renderer, enemy.position) { continue }
		ground := cell_overlay_ground(enemy.position)
		at := rl.Vector3{f32(enemy.position.x)+0.5, ground+0.28, f32(enemy.position.y)+0.5}
		for k in 0..<3 {
			phase := t*(7+f32(k))+f32(enemy.id)*1.7+f32(k)*2.1
			rise := f32(math.mod(f64(t)*(1.1+0.2*f64(k))+f64(k)*0.33, 1))
			spot := at+{0.16*math.sin(phase), 0.5*rise, 0.1*math.cos(phase)}
			marley_draw_print(renderer, puff, spot, 0.42*(1-0.6*rise), 0, flame_tint(0.2+0.7*rise, 0.9*(1-rise)))
		}
	}
}

@(private = "file")
flame_tint :: proc(k, alpha: f32) -> rl.Color {
	color := flame_color(k)
	color.a = u8(255*clamp(alpha, 0, 1))
	return color
}

// With the sky's things, over the cards: the flame, its smoke and light.
@(private)
draw_flame :: proc(renderer: ^Renderer, room: ^game.Room) {
	v := &renderer.tactical.flame
	active := game.first_person_flame_active(room)
	if !active && !renderer.tactical.mechanics_lab { return }
	if v.puff.id == 0 { v.puff = flame_puff_texture() }
	if v.puff.id == 0 { return }
	t := f32(tactical_world_time(renderer))
	// Over the cards, every puff seen through the others: no depth.
	rlgl.DrawRenderBatchActive()
	rlgl.DisableDepthTest()
	defer {
		rlgl.DrawRenderBatchActive()
		rlgl.EnableDepthTest()
	}
	rl.BeginBlendMode(.ADDITIVE)
	draw_burning_foes(renderer, room, v.puff, t)
	rl.EndBlendMode()
	if !active { return }
	f := &room.first_person.flame
	ground := cell_overlay_ground(room.player.position)
	height := ground+FLAME_GRIP_HEIGHT+0.015
	feet := flame_feet(renderer)
	nozzle := flame_nozzle(feet, f.yaw)
	reach := rl.Vector2Length({nozzle.x-feet.x, nozzle.z-feet.z})

	// The pieces out, from the tip back: where each stands, how far along.
	Spot :: struct { x, y, across_x, across_y, k, width: f32, ring: int }
	spots: [game.FLAME_PIECES]Spot
	count := 0
	for age := game.FLAME_PIECES-1; age >= 0; age -= 1 {
		piece := game.flame_piece_at(f, age)
		if !piece.alive { continue }
		distance := game.flame_piece_distance(age)
		if distance < reach*0.5 { continue }
		k := distance/game.FLAME_LENGTH
		point := game.flame_piece_point(piece^, distance+reach*0.35*(1-k))
		spots[count] = {point.x, point.y, -math.sin(piece.way), math.cos(piece.way), k, game.flame_width(distance), (int(f.head)-age+game.FLAME_PIECES)%game.FLAME_PIECES}
		count += 1
	}
	spot_at :: proc(spot: Spot, puff: int, height, t: f32) -> (at: rl.Vector3, wobble: f32, seed: int) {
		seed = int(gothic_hash(spot.ring, puff+3))
		wobble = f32(seed%200)/100-1
		beat := math.sin(t*23+f32(seed%628)/100)
		side := wobble*spot.width*0.42+0.05*beat*spot.k
		lift := 0.06*f32(puff)-0.06+spot.k*spot.k*0.34+0.04*beat
		return {spot.x+spot.across_x*side, height+lift, spot.y+spot.across_y*side}, wobble, seed
	}

	// Dark smoke over the tip, then the body of the flame, its colours laid on the floor's dark.
	rl.BeginBlendMode(.ALPHA)
	for spot, index in spots[:min(count, 7)] {
		rise := f32(7-index)*0.07
		marley_draw_print(renderer, v.puff, {spot.x, height+0.42+rise, spot.y}, 0.55+rise, t*30, {30, 24, 28, 120})
	}
	for spot in spots[:count] {
		at, wobble, seed := spot_at(spot, 0, height, t)
		marley_draw_print(renderer, v.puff, at, 0.34+0.72*spot.k, f32(seed%360)+t*60, flame_tint(spot.k*0.9+0.1+0.06*wobble, 0.8))
	}
	rl.EndBlendMode()

	// Its heart, added: white and yellow near the nozzle.
	rl.BeginBlendMode(.ADDITIVE)
	for spot in spots[:count] {
		for puff in 1..=2 {
			at, wobble, seed := spot_at(spot, puff, height, t)
			size := (0.2+0.4*spot.k)*(0.8+0.2*f32(puff))
			marley_draw_print(renderer, v.puff, at, size, f32(seed%360)+t*60, flame_tint(spot.k*0.75+0.06*wobble, 0.85-0.45*spot.k))
		}
	}
	// The pilot light, always; its flare while it fires.
	flicker := 0.8+0.2*math.sin(t*31)
	marley_draw_print(renderer, v.puff, nozzle, (0.55 if f.firing else 0.18)*flicker, 0, flame_tint(0.1, 0.95))
	if count > 0 {
		// Its light on the floor, a slow beat of it.
		last := spots[0]
		middle := [2]f32{(nozzle.x+last.x)/2, (nozzle.z+last.y)/2}
		marley_glow(middle.x, ground+0.03, middle.y, 2, {255, 120, 40, 255}, (0.34+0.08*math.sin(t*17))*min(f32(count)/12, 1))
		marley_glow(last.x, ground+0.035, last.y, 1.2, {255, 80, 30, 255}, 0.3*min(f32(count)/20, 1))
		// The hot air: faint puffs wavering over it.
		for k in 0..<4 {
			u := f32(k+1)/5
			at := rl.Vector3{nozzle.x+(last.x-nozzle.x)*u+0.12*math.sin(t*9+f32(k)), height+0.5+0.14*math.sin(t*7+f32(k)*2), nozzle.z+(last.y-nozzle.z)*u}
			marley_draw_print(renderer, v.puff, at, 0.7, t*40, {255, 214, 170, 26})
		}
	}
	rl.EndBlendMode()
}
