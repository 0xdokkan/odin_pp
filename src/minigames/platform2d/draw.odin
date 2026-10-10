package platform2d

// Presentation: camera, particles, sound and HUD driven by world events, plus
// all raylib drawing. Nothing here feeds back into the simulation.

import "core:fmt"
import "core:math"
import rl "vendor:raylib"
import audio "../../engine/audio"
import camera "../../engine/camera"
import fx "../../engine/fx"
import gfx "../../engine/gfx"
import host "../../engine/host"
import physics "../../engine/physics"
import rng "../../engine/rng"
import ui "../../engine/ui"

ZOOM :: f32(2)

COLOR_IVORY :: rl.Color{236, 226, 204, 255}
COLOR_DIM :: rl.Color{160, 152, 136, 255}
COLOR_GOLD :: rl.Color{255, 200, 96, 255}
COLOR_EMBER :: rl.Color{255, 136, 52, 255}
COLOR_CRIMSON :: rl.Color{200, 44, 56, 255}
COLOR_ASH :: rl.Color{170, 160, 150, 255}

Ring :: struct {
	position: Vec2,
	time:     f32,
	duration: f32,
	radius:   f32,
	color:    rl.Color,
}

Ghost :: struct {
	feet:  Vec2,
	frame: int,
	flip:  bool,
	life:  f32,
}

View :: struct {
	sprites:      Sprites,
	cam:          camera.Camera2,
	// Dust and debris blend normally; sparks, fire and embers add light.
	dust:         fx.Particles(384),
	glow:         fx.Particles(640),
	popups:       fx.Popups(16),
	flash:        fx.Flash,
	hit_stop:     fx.Hit_Stop,
	random:       rng.Rng,
	time:         f32,
	squash:       Vec2,
	run_time:     f32,
	look:         Vec2,
	rings:        [16]Ring,
	ghosts:       [10]Ghost,
	ghost_timer:  f32,
	banner:       string,
	banner_sub:   string,
	banner_time:  f32,
	started:      bool,
	ember_pulse:  f32,
	heart_pulse:  f32,
	score_shown:  f32,
	streak:       int,
	streak_timer: f32,
	last_second:  int,
	shake_scale:  f32,
	area:         int,
	area_time:    f32,
}

view_reset :: proc(v: ^View, w: ^World) {
	sprites := v.sprites
	v^ = {}
	v.sprites = sprites
	v.random = rng.create(rng.derive(w.config.seed, 99))
	v.cam = camera.camera2_create(player_center(w.player), ZOOM)
	v.cam.deadzone = {16, 20}
	v.cam.smoothing = 7
	// The last rows are bedrock under the pits; keep the view on the action.
	v.cam.bounds_max = level_size(w) - {0, 22}
	v.cam.shake = camera.shake_default(9)
	v.cam.position.y -= 30
	camera.camera2_clamp(&v.cam, {960, 540})
	v.squash = {1, 1}
	v.shake_scale = 1
	v.last_second = -1
}

@(private)
shake :: proc(v: ^View, amount: f32) {
	camera.add_trauma(&v.cam.shake, amount*v.shake_scale)
}

@(private)
ring :: proc(v: ^View, at: Vec2, radius: f32, color: rl.Color, duration: f32 = 0.35) {
	oldest := 0
	for r, i in v.rings {
		if r.time >= r.duration {
			oldest = i
			break
		}
		if r.time/r.duration > v.rings[oldest].time/v.rings[oldest].duration {
			oldest = i
		}
	}
	v.rings[oldest] = Ring{position = at, radius = radius, color = color, duration = duration}
}

@(private)
banner :: proc(v: ^View, text: string, sub := "", duration: f32 = 2) {
	v.banner = text
	v.banner_sub = sub
	v.banner_time = duration
}

@(private)
emit2 :: proc(p: ^fx.Particles($N), e: fx.Emitter, at: Vec2, count: int, r: ^rng.Rng) {
	fx.emit(p, e, {at.x, at.y, 0}, count, r)
}

@(private)
points_text :: proc(points: i64) -> string {
	switch points {
	case 10:
		return "+10"
	case 25:
		return "+25"
	case 50:
		return "+50"
	case 75:
		return "+75"
	case 100:
		return "+100"
	case 125:
		return "+125"
	case 150:
		return "+150"
	case 175:
		return "+175"
	case 200:
		return "+200"
	}
	return "+"
}

// ---------------------------------------------------------------------------
// Emitters (world pixels; the camera doubles them)

DUST_PUFF :: fx.Emitter{
	speed_min = 10, speed_max = 45, direction = {0, -1, 0}, spread = 1.3,
	life_min = 0.25, life_max = 0.5, size_start = 3, size_end = 0,
	color_start = {176, 166, 154, 190}, color_end = {120, 110, 104, 0}, gravity = -15, drag = 5,
}

SPARK_BURST :: fx.Emitter{
	speed_min = 40, speed_max = 130, direction = {0, -1, 0}, spread = math.PI,
	life_min = 0.2, life_max = 0.5, size_start = 2, size_end = 0,
	color_start = {255, 236, 170, 255}, color_end = {255, 110, 40, 0}, gravity = 160, drag = 2.5,
}

FLAME :: fx.Emitter{
	speed_min = 12, speed_max = 30, direction = {0, -1, 0}, spread = 0.35,
	life_min = 0.35, life_max = 0.7, size_start = 3.5, size_end = 0.5,
	color_start = {255, 210, 110, 230}, color_end = {200, 40, 30, 0}, gravity = -40, drag = 1.5, radius = 2.5,
}

ASH_RISE :: fx.Emitter{
	speed_min = 6, speed_max = 18, direction = {0, -1, 0}, spread = 0.6,
	life_min = 3, life_max = 5.5, size_start = 1.6, size_end = 0.4,
	color_start = {255, 150, 70, 210}, color_end = {200, 60, 40, 0}, gravity = -4, drag = 0.2,
}

DEBRIS :: fx.Emitter{
	speed_min = 30, speed_max = 90, direction = {0, -1, 0}, spread = 1.4,
	life_min = 0.5, life_max = 0.9, size_start = 3, size_end = 1.5,
	color_start = {150, 118, 88, 255}, color_end = {90, 70, 56, 0}, gravity = 520, drag = 0.5, spin = 8,
}

GORE :: fx.Emitter{
	speed_min = 50, speed_max = 170, direction = {0, -1, 0}, spread = math.PI,
	life_min = 0.35, life_max = 0.8, size_start = 3, size_end = 0,
	color_start = {120, 112, 126, 255}, color_end = {50, 46, 58, 0}, gravity = 380, drag = 1.2, spin = 6,
}

// ---------------------------------------------------------------------------
// Events -> feedback

view_consume_events :: proc(v: ^View, w: ^World, frame: ^host.Frame) {
	r := &v.random
	for e in w.events[:w.event_count] {
		switch e.kind {
		case .Jump:
			emit2(&v.dust, DUST_PUFF, e.position, 6, r)
			v.squash = {0.72, 1.32}
			audio.play(frame.audio, .Jump, 0.8)
		case .Air_Jump:
			sparks := SPARK_BURST
			sparks.direction = {0, 1, 0}
			sparks.spread = 0.9
			emit2(&v.glow, sparks, e.position, 10, r)
			ring(v, e.position, 14, {255, 190, 110, 200}, 0.3)
			v.squash = {0.8, 1.25}
			audio.play(frame.audio, .Jump, 0.75, 1.3)
		case .Wall_Jump:
			puff := DUST_PUFF
			puff.direction = {e.value, 0, 0}
			emit2(&v.dust, puff, e.position - {e.value * 5, 0}, 7, r)
			v.squash = {0.75, 1.28}
			audio.play(frame.audio, .Jump, 0.8, 0.9)
		case .Dash:
			sparks := SPARK_BURST
			sparks.direction = {-e.value, 0, 0}
			sparks.spread = 0.5
			emit2(&v.glow, sparks, e.position, 12, r)
			v.squash = {1.45, 0.72}
			shake(v, 0.12)
			audio.play(frame.audio, .Dash)
		case .Land:
			k := clamp((e.value-120)/300, 0, 1)
			if e.value > 120 {
				puff := DUST_PUFF
				puff.direction = {1, 0, 0}
				emit2(&v.dust, puff, e.position, 2+int(k*5), r)
				puff.direction = {-1, 0, 0}
				emit2(&v.dust, puff, e.position, 2+int(k*5), r)
				v.squash = {1 + 0.45*k, 1 - 0.38*k}
				audio.play(frame.audio, .Land, 0.4+0.6*k)
			}
			if e.value > 380 {
				shake(v, 0.18)
			}
		case .Ember:
			emit2(&v.glow, SPARK_BURST, e.position, 10, r)
			ring(v, e.position, 12, {255, 210, 120, 220}, 0.3)
			fx.popup(&v.popups, e.position - {0, 6}, "+10", COLOR_GOLD, 0.6)
			v.ember_pulse = 1
			v.streak = v.streak + 1 if v.streak_timer > 0 else 0
			v.streak_timer = 0.6
			audio.play(frame.audio, .Coin, 0.7, 1 + 0.06*f32(min(v.streak, 10)))
		case .Stomp:
			emit2(&v.dust, GORE, e.position, 16, r)
			emit2(&v.glow, SPARK_BURST, e.position, 12, r)
			ring(v, e.position, 22, {255, 236, 200, 230}, 0.3)
			fx.popup(&v.popups, e.position - {0, 10}, points_text(i64(e.value)), COLOR_IVORY, 0.8)
			fx.hit_stop(&v.hit_stop, 0.06)
			shake(v, 0.22)
			v.squash = {0.75, 1.3}
			audio.play(frame.audio, .Hit, 0.9)
			audio.play(frame.audio, .Jump, 0.5, 1.2 + 0.12*f32(min(e.count, 6)))
		case .Hurt:
			gore := GORE
			gore.color_start = {214, 50, 60, 255}
			gore.color_end = {120, 20, 30, 0}
			emit2(&v.dust, gore, e.position, 12, r)
			fx.flash_start(&v.flash, {190, 30, 44, 130}, 0.3)
			fx.hit_stop(&v.hit_stop, 0.09)
			shake(v, 0.5)
			v.heart_pulse = 1
			audio.play(frame.audio, .Hurt)
		case .Death:
			gore := GORE
			gore.color_start = {214, 50, 60, 255}
			gore.color_end = {120, 20, 30, 0}
			gore.speed_max = 240
			emit2(&v.dust, gore, e.position, 26, r)
			emit2(&v.glow, SPARK_BURST, e.position, 24, r)
			ring(v, e.position, 34, {255, 120, 90, 230}, 0.45)
			fx.flash_start(&v.flash, {200, 40, 40, 110}, 0.35)
			fx.hit_stop(&v.hit_stop, 0.12)
			shake(v, 0.65)
			audio.play(frame.audio, .Explosion, 0.6)
		case .Respawn:
			flame := FLAME
			flame.speed_max = 70
			emit2(&v.glow, flame, e.position - {0, 6}, 24, r)
			ring(v, e.position - {0, 8}, 26, {255, 200, 120, 220}, 0.5)
			banner(v, "Rinasci dalle ceneri", "", 1.4)
			audio.play(frame.audio, .Power_Up, 0.5)
		case .Checkpoint:
			flame := FLAME
			flame.speed_max = 90
			flame.spread = 0.8
			emit2(&v.glow, flame, e.position - {0, 10}, 30, r)
			ring(v, e.position - {0, 10}, 30, {255, 190, 100, 230}, 0.5)
			fx.flash_start(&v.flash, {255, 180, 90, 50}, 0.4)
			banner(v, "Fuoco acceso", "Ripartirai da qui", 1.8)
			audio.play(frame.audio, .Power_Up, 0.8)
		case .Charge:
			play_at(v, frame, .Laser, e.position, 0.22, 0.45)
		case .Shoot:
			sparks := SPARK_BURST
			sparks.direction = {e.value, 0, 0}
			sparks.spread = 0.6
			emit2(&v.glow, sparks, e.position, 8, r)
			play_at(v, frame, .Shoot, e.position, 0.6)
		case .Fireball_Pop:
			emit2(&v.glow, SPARK_BURST, e.position, 8, r)
			play_at(v, frame, .Hit, e.position, 0.25, 1.4)
		case .Enemy_Burn:
			emit2(&v.glow, FLAME, e.position, 14, r)
			play_at(v, frame, .Explosion, e.position, 0.25, 1.3)
		case .Crumble_Shake:
			puff := DUST_PUFF
			puff.color_start = {150, 118, 88, 200}
			emit2(&v.dust, puff, e.position + {0, 8}, 3, r)
			play_at(v, frame, .Step, e.position, 0.6, 0.6)
		case .Crumble_Break:
			emit2(&v.dust, DEBRIS, e.position, 10, r)
			play_at(v, frame, .Explosion, e.position, 0.22, 1.7)
		case .Exit:
			ring(v, e.position, 60, {255, 210, 140, 240}, 0.8)
			emit2(&v.glow, SPARK_BURST, e.position, 40, r)
			fx.flash_start(&v.flash, {255, 220, 160, 120}, 0.7)
			shake(v, 0.3)
			banner(v, "Fuga riuscita!", "", 2)
			audio.play(frame.audio, .Power_Up, 0.9, 1.4)
		case .Time_Up:
			banner(v, "Tempo scaduto", "", 2)
			audio.play(frame.audio, .Hurt)
		case .Game_Over:
		}
	}
}

// Per-frame presentation: camera, ambience, timers. Runs while paused too,
// but only ambient effects move then.
view_update :: proc(v: ^View, w: ^World, frame: ^host.Frame, playing: bool) {
	dt := frame.dt
	v.time += dt
	v.shake_scale = frame.profile.settings.screen_shake if frame.profile != nil else 1
	p := w.player
	r := &v.random
	view := Vec2{frame.canvas.width, frame.canvas.height}

	if playing && !v.started {
		v.started = true
		banner(v, "Raggiungi il portale", fmt.tprintf("%d braci nella torre", w.ember_count), 2.2)
	}

	// Camera: look ahead where the player faces, and down while falling fast.
	target := player_center(p)
	desired := Vec2{p.ctrl.facing * 34, 0}
	if !p.ctrl.grounded && p.ctrl.body.velocity.y > 140 {
		desired.y = 30
	}
	if w.phase == .Exiting {
		target = physics.rect_center(w.exit_rect)
		desired = {}
	}
	if w.phase != .Dying {
		v.look += (desired - v.look) * (1 - math.exp(-2.5*dt))
	}
	v.cam.lookahead = v.look
	camera.camera2_update(&v.cam, target, view, dt)

	fx.update(&v.dust, dt)
	fx.update(&v.glow, dt)
	fx.popups_update(&v.popups, dt)
	fx.flash_update(&v.flash, dt)
	for &ring in v.rings {
		ring.time = min(ring.time+dt, ring.duration)
	}
	for &g in v.ghosts {
		g.life = max(g.life-dt, 0)
	}
	v.banner_time = max(v.banner_time-dt, 0)
	v.ember_pulse = max(v.ember_pulse-dt*3, 0)
	v.heart_pulse = max(v.heart_pulse-dt*2, 0)
	v.streak_timer = max(v.streak_timer-dt, 0)
	if area := world_area(w); area != v.area {
		v.area = area
		v.area_time = 2.5
	}
	v.area_time = max(v.area_time-dt, 0)
	score, _ := world_score(w)
	v.score_shown += (f32(score) - v.score_shown) * (1 - math.exp(-8*dt))
	if abs(f32(score)-v.score_shown) < 1 {
		v.score_shown = f32(score)
	}

	// Ambient embers drift up through the whole view.
	half := view / (2 * ZOOM)
	if rng.chance(r, dt*16) {
		at := v.cam.position + {rng.float_range(r, -half.x, half.x), half.y + 6}
		emit2(&v.glow, ASH_RISE, at, 1, r)
	}
	for c in w.checkpoints[:w.checkpoint_count] {
		if c.lit && rng.chance(r, dt*30) && on_screen(v, c.feet, 40) {
			emit2(&v.glow, FLAME, c.feet - {0, 9}, 1, r)
		}
	}
	if w.has_exit && rng.chance(r, dt*20) && on_screen(v, physics.rect_center(w.exit_rect), 80) {
		c := physics.rect_center(w.exit_rect)
		a := rng.float_range(r, 0, math.TAU)
		start := c + Vec2{math.cos(a) * 26, math.sin(a) * 34}
		spark := SPARK_BURST
		spark.direction = {c.x - start.x, c.y - start.y, 0}
		spark.spread = 0.1
		spark.speed_min = 30
		spark.speed_max = 50
		spark.gravity = 0
		spark.life_min = 0.5
		spark.life_max = 0.7
		emit2(&v.glow, spark, start, 1, r)
	}
	// Lava spits a few bubbles where the player can see them.
	if rng.chance(r, dt*6) {
		x := int((v.cam.position.x + rng.float_range(r, -half.x, half.x)) / TILE)
		for y in 0..<LEVEL_ROWS {
			if tile_kind(w, x, y) == .Lava {
				spit := FLAME
				spit.speed_min = 30
				spit.speed_max = 60
				spit.gravity = 160
				emit2(&v.glow, spit, {(f32(x) + rng.float01(r)) * TILE, f32(y)*TILE + 6}, 3, r)
				break
			}
		}
	}
	if !playing {
		return
	}
	for b in w.projectiles {
		if b.active && rng.chance(r, 0.7) {
			trail := FLAME
			trail.direction = {-b.velocity.x, 0, 0}
			trail.radius = 1.5
			emit2(&v.glow, trail, b.position, 1, r)
		}
	}

	// Player-driven effects.
	vx := p.ctrl.body.velocity.x
	vy := p.ctrl.body.velocity.y
	if p.ctrl.grounded && abs(vx) > 20 {
		stride := int(v.run_time)
		v.run_time += dt * abs(vx) / 150 * 11
		// A soft footfall on each planted foot of the run cycle.
		if int(v.run_time) != stride && int(v.run_time)%2 == 0 {
			audio.play(frame.audio, .Step, 0.3, rng.float_range(r, 0.85, 1.1))
		}
		if abs(vx) > 120 && rng.chance(r, dt*8) {
			puff := DUST_PUFF
			puff.direction = {-math.sign(vx), -0.5, 0}
			emit2(&v.dust, puff, player_feet(p), 1, r)
		}
	}
	if w.phase == .Alive && !p.ctrl.grounded && p.ctrl.wall_side != 0 && vy > 30 && rng.chance(r, dt*20) {
		emit2(&v.dust, DUST_PUFF, player_center(p) + {p.ctrl.wall_side * 5, 4}, 1, r)
	}
	v.ghost_timer -= dt
	if p.ctrl.dash_remaining > 0 && v.ghost_timer <= 0 && w.phase == .Alive {
		v.ghost_timer = 0.025
		for &g in v.ghosts {
			if g.life <= 0 {
				g = Ghost{feet = player_feet(p), frame = int(player_frame(v, w)), flip = p.ctrl.facing < 0, life = 0.25}
				break
			}
		}
	}
	v.squash += (Vec2{1, 1} - v.squash) * (1 - math.exp(-14*dt))

	// Countdown ticks in the last ten seconds of a timed run.
	if w.time_limit > 0 && w.phase == .Alive {
		left := int(math.ceil(w.time_limit - w.time))
		if left <= 10 && left != v.last_second && left > 0 {
			v.last_second = left
			audio.play(frame.audio, .Step, 0.8, 1.6)
		}
	}
}

@(private)
on_screen :: proc(v: ^View, p: Vec2, margin: f32) -> bool {
	d := p - v.cam.position
	return abs(d.x) < 240+margin && abs(d.y) < 135+margin
}

player_frame :: proc(v: ^View, w: ^World) -> Player_Frame {
	p := w.player
	if !p.ctrl.grounded {
		if p.ctrl.dash_remaining > 0 || p.ctrl.body.velocity.y < -30 {
			return .Jump
		}
		return .Fall
	}
	if abs(p.ctrl.body.velocity.x) > 20 {
		cycle := [4]Player_Frame{.Run_A, .Run_B, .Run_C, .Run_B}
		return cycle[int(v.run_time) % 4]
	}
	return .Blink if math.mod(v.time, 3.2) < 0.12 else .Idle
}

// ---------------------------------------------------------------------------
// Drawing

draw_game :: proc(v: ^View, w: ^World, frame: ^host.Frame) {
	canvas := frame.canvas
	size := Vec2{canvas.width, canvas.height}
	draw_backdrop(v, w, canvas)
	cam := camera.camera2_to_raylib(v.cam, size)
	rl.BeginMode2D(cam)
	half := size / (2 * ZOOM)
	x0 := max(int(math.floor((v.cam.position.x - half.x) / TILE)) - 1, 0)
	x1 := min(int(math.floor((v.cam.position.x + half.x) / TILE)) + 1, w.cols-1)
	y0 := max(int(math.floor((v.cam.position.y - half.y) / TILE)) - 1, 0)
	y1 := min(int(math.floor((v.cam.position.y + half.y) / TILE)) + 1, LEVEL_ROWS-1)

	draw_player_light(v, w)
	draw_tiles(v, w, x0, x1, y0, y1)
	draw_checkpoints(v, w)
	draw_portal(v, w)
	draw_embers(v, w)
	draw_enemies(v, w)
	draw_player(v, w)
	fx.draw2d(&v.dust)
	rl.BeginBlendMode(.ADDITIVE)
	draw_projectiles(v, w)
	fx.draw2d(&v.glow)
	for r in v.rings {
		if r.time < r.duration {
			gfx.draw_shockwave(r.position, r.time/r.duration, r.radius, r.color)
		}
	}
	rl.EndBlendMode()
	rl.EndMode2D()

	draw_popups(v, frame)
	gfx.draw_vignette(canvas.width, canvas.height, 0.5)
	fx.flash_draw(v.flash, canvas.width, canvas.height)
	draw_hud(v, w, frame)
}

// Small deterministic hash for decoration choices.
@(private)
hash01 :: proc "contextless" (a, b: int) -> f32 {
	h := u32(a)*374761393 + u32(b)*668265263
	h = (h ~ (h >> 13)) * 1274126177
	h ~= h >> 16
	return f32(h & 0xFFFF) / 65535
}

@(private)
draw_backdrop :: proc(v: ^View, w: ^World, canvas: rl.Rectangle) {
	s := &v.sprites
	gfx.draw_vertical_gradient(canvas, {7, 11, 18, 255}, {31, 48, 67, 255})
	scroll := v.cam.position.x * ZOOM
	// Zero when the camera sits on the ground, positive as it climbs.
	lift := (v.cam.bounds_max.y - 135 - v.cam.position.y) * ZOOM
	gfx.draw_stars(canvas.width, 300, 80, v.time, scroll*0.4)

	moon := Vec2{canvas.width*0.76 - scroll*0.01, 118 + lift*0.04}
	rl.BeginBlendMode(.ADDITIVE)
	soft_glow(s, moon, 190, {68, 130, 187, 110})
	soft_glow(s, moon, 80, {120, 171, 218, 90})
	rl.EndBlendMode()
	rl.DrawCircleV(moon, 46, {236, 214, 190, 255})
	rl.DrawCircleV(moon + {-14, -10}, 8, {216, 192, 170, 255})
	rl.DrawCircleV(moon + {12, 14}, 6, {218, 194, 172, 255})
	rl.DrawCircleV(moon + {16, -16}, 4, {220, 198, 176, 255})
	draw_ash_tower(v, canvas, world_progress(w), lift)
	// Smoke across the moon.
	for i in 0..<3 {
		y := moon.y + 18 + f32(i)*14
		x := math.mod(v.time*(6+f32(i)*3)+f32(i)*140, canvas.width+300) - 150
		rl.DrawEllipse(i32(x), i32(y), 120, 7, {17, 28, 43, 120})
	}

	draw_spires(canvas, scroll*0.1, 330+lift*0.12, 130, {28, 44, 62, 255}, 1)
	gfx.draw_hills(canvas.width, canvas.height, 430+lift*0.2, 120, scroll*0.2, {19, 31, 46, 255}, 1.7)
	draw_spires(canvas, scroll*0.32, 420+lift*0.3, 210, {14, 24, 37, 255}, 2)
	gfx.draw_hills(canvas.width, canvas.height, 500+lift*0.4, 70, scroll*0.4, {9, 16, 26, 255}, 4.2)
	rl.DrawRectangleGradientV(0, i32(canvas.height-220), i32(canvas.width), 220, {0, 0, 0, 0}, {44, 85, 116, 65})
}

// Ruined towers with a few lit windows, repeating with the scroll.
@(private)
draw_spires :: proc(canvas: rl.Rectangle, scroll, base, spacing: f32, color: rl.Color, seed: int) {
	first := int(math.floor(scroll/spacing)) - 1
	count := int(canvas.width/spacing) + 3
	for i in first..<first+count {
		h := hash01(i, seed)
		x := f32(i)*spacing - scroll + hash01(i, seed+7)*spacing*0.4
		width := 22 + h*26
		height := 70 + hash01(i, seed+3)*140
		top := base - height
		rl.DrawRectangleRec({x, top, width, canvas.height - top}, color)
		apex := Vec2{x + width*0.5, top - 26 - h*34}
		rl.DrawTriangle({x - 4, top}, {x + width + 4, top}, apex, color)
		rl.DrawTriangle({x - 4, top}, apex, {x + width + 4, top}, color)
		rl.DrawRectangleRec({x-5, top+height*0.35, 5, canvas.height-top}, color)
		rl.DrawRectangleRec({x+width, top+height*0.35, 5, canvas.height-top}, color)
		rl.DrawRectangleRec({x-3, top+4, width+6, 2}, {68, 92, 116, 75})
		if hash01(i, seed+11) > 0.45 {
			rl.DrawRectangleRec({x + width*0.5 - 2, top + 18, 4, 7}, {112, 179, 221, 150})
		}
		if hash01(i, seed+13) > 0.7 {
			rl.DrawRectangleRec({x + width*0.5 - 2, top + 44, 4, 7}, {78, 136, 177, 130})
		}
	}
}

@(private)
draw_player_light :: proc(v: ^View, w: ^World) {
	if w.phase == .Dying {
		return
	}
	rl.BeginBlendMode(.ADDITIVE)
	flicker := 1 + 0.06*math.sin(v.time*11) + 0.04*math.sin(v.time*23)
	soft_glow(&v.sprites, player_center(w.player), 64*flicker, {39, 78, 119, 190})
	rl.EndBlendMode()
}

@(private)
solid_at :: proc(w: ^World, x, y: int) -> bool {
	k := tile_kind(w, x, y)
	return k == .Stone || k == .Crumble
}

@(private)
draw_tiles :: proc(v: ^View, w: ^World, x0, x1, y0, y1: int) {
	tex := v.sprites.tiles.texture
	for y in y0..=y1 {
		for x in x0..=x1 {
			pos := Vec2{f32(x) * TILE, f32(y) * TILE}
			switch tile_kind(w, x, y) {
			case .Empty:
			case .Stone:
				frame := Tile_Frame.Stone
				tint := rl.WHITE
				if !solid_at(w, x, y-1) {
					frame = .Stone_Top
				} else {
					if hash01(x, y) > 0.78 {
						frame = .Stone_Cracked
					}
					// Deeper rock recedes into shadow.
					depth := 1
					if solid_at(w, x, y-2) {
						depth = 2
					}
					if depth == 2 && solid_at(w, x, y-3) {
						depth = 3
					}
					shade := u8(235 - 30*depth)
					tint = {shade, shade, u8(min(int(shade)+12, 255)), 255}
				}
				rl.DrawTextureRec(tex, tile_source(v.sprites.tiles, frame), pos, tint)
				edge := rl.Color{14, 12, 20, 255}
				if !solid_at(w, x-1, y) && x > 0 {
					rl.DrawRectangleRec({pos.x, pos.y, 1, TILE}, edge)
				}
				if !solid_at(w, x+1, y) && x < w.cols-1 {
					rl.DrawRectangleRec({pos.x + TILE - 1, pos.y, 1, TILE}, edge)
				}
				if !solid_at(w, x, y+1) && y < LEVEL_ROWS-1 {
					rl.DrawRectangleRec({pos.x, pos.y + TILE - 1, TILE, 1}, edge)
					rl.DrawRectangleGradientV(i32(pos.x), i32(pos.y+TILE), i32(TILE), 6, {0, 0, 0, 90}, {0, 0, 0, 0})
				}
				// Polished blue bevel and inset seam; solid geometry stays unchanged.
				if frame == .Stone_Top {
					rl.DrawRectangleRec({pos.x+1, pos.y+1, TILE-2, 1}, {162, 188, 208, 210})
					rl.DrawRectangleRec({pos.x+1, pos.y+3, TILE-2, 1}, {37, 57, 77, 190})
				}
				// Candles on a few ledges of the ruins.
				if frame == .Stone_Top && hash01(x, y+101) > 0.93 && tile_kind(w, x, y-1) == .Empty {
					draw_candle(v, pos + {f32(4 + int(hash01(x, y+7)*8)), 0})
				}
			case .Ledge:
				rl.DrawTextureRec(tex, tile_source(v.sprites.tiles, .Ledge), pos, rl.WHITE)
			case .Spike:
				up := spike_points_up(w, x, y)
				src := tile_source(v.sprites.tiles, .Spikes, !up)
				rl.DrawTexturePro(tex, src, {pos.x, pos.y, TILE, TILE}, {}, 0, rl.WHITE)
			case .Crumble:
				c := crumble_at(w, x, y)
				state := c.state if c != nil else Crumble_State.Intact
				switch state {
				case .Intact:
					rl.DrawTextureRec(tex, tile_source(v.sprites.tiles, .Crumble), pos, rl.WHITE)
				case .Shaking:
					wobble := Vec2{math.round(math.sin(v.time*70+f32(x)) * 1.2), 0}
					rl.DrawTextureRec(tex, tile_source(v.sprites.tiles, .Crumble), pos + wobble, {255, 200, 180, 255})
				case .Gone:
					rl.DrawRectangleLinesEx({pos.x + 1, pos.y + 1, TILE - 2, TILE - 2}, 1, {150, 118, 88, 40})
				}
			case .Lava:
				draw_lava(v, w, x, y, pos)
			}
		}
	}
}

@(private)
draw_candle :: proc(v: ^View, base: Vec2) {
	rl.DrawRectangleRec({base.x, base.y - 5, 2, 5}, {222, 210, 186, 255})
	flick := 0.5 + 0.5*math.sin(v.time*13 + base.x)
	rl.DrawRectangleRec({base.x, base.y - 7, 2, 2}, {255, u8(180 + 60*flick), 90, 255})
	rl.BeginBlendMode(.ADDITIVE)
	soft_glow(&v.sprites, base + {1, -7}, 12 + 2*flick, {150, 80, 30, 255})
	rl.EndBlendMode()
}

@(private)
draw_lava :: proc(v: ^View, w: ^World, x, y: int, pos: Vec2) {
	surface := tile_kind(w, x, y-1) != .Lava
	body := rl.Color{186, 50, 28, 255}
	if !surface {
		rl.DrawRectangleRec({pos.x, pos.y, TILE, TILE}, {150, 36, 22, 255})
		return
	}
	for i in 0..<8 {
		px := pos.x + f32(i)*2
		h := 5 + math.sin(v.time*2.6 + px*0.32)*1.4 + math.sin(v.time*1.3 + px*0.11)*0.8
		top := pos.y + math.round(h)
		rl.DrawRectangleRec({px, top, 2, pos.y + TILE - top}, body)
		rl.DrawRectangleRec({px, top, 2, 2}, {255, 178, 76, 255})
	}
	rl.DrawRectangleRec({pos.x, pos.y + 11, TILE, 5}, {150, 36, 22, 255})
	rl.BeginBlendMode(.ADDITIVE)
	glow := 0.75 + 0.25*math.sin(v.time*2 + f32(x)*0.7)
	rl.DrawRectangleGradientV(i32(pos.x), i32(pos.y-18), i32(TILE), 24, {0, 0, 0, 0}, {255, 110, 40, u8(60*glow)})
	rl.EndBlendMode()
}

@(private)
draw_checkpoints :: proc(v: ^View, w: ^World) {
	for c in w.checkpoints[:w.checkpoint_count] {
		if !on_screen(v, c.feet, 30) {
			continue
		}
		gfx.draw_sprite_feet(v.sprites.brazier, 0, c.feet, 1, false, rl.WHITE if c.lit else {150, 150, 160, 255})
		if c.lit {
			rl.BeginBlendMode(.ADDITIVE)
			flick := 1 + 0.12*math.sin(v.time*9 + c.feet.x)
			soft_glow(&v.sprites, c.feet - {0, 12}, 56*flick, {200, 100, 40, 255})
			rl.EndBlendMode()
		} else {
			// A faint wisp hints that it can be lit.
			a := u8(60 + 40*math.sin(v.time*3))
			rl.DrawCircleV(c.feet - {0, 11}, 2, {200, 180, 160, a})
		}
	}
}

@(private)
draw_portal :: proc(v: ^View, w: ^World) {
	if !w.has_exit {
		return
	}
	r := w.exit_rect
	c := physics.rect_center(r)
	if !on_screen(v, c, 60) {
		return
	}
	stone := rl.Color{51, 69, 89, 255}
	dark := rl.Color{18, 29, 42, 255}
	arch_center := Vec2{c.x, r.y + 16}
	rl.DrawRectangleRec({r.x - 7, r.y + 16, 7, r.height - 16}, stone)
	rl.DrawRectangleRec({r.x + r.width, r.y + 16, 7, r.height - 16}, stone)
	rl.DrawRing(arch_center, 16, 23, 180, 360, 20, stone)
	rl.DrawRing(arch_center, 22, 23, 180, 360, 20, dark)
	rl.DrawRectangleRec({r.x - 9, r.y + r.height - 4, r.width + 18, 4}, dark)
	// Keystone.
	rl.DrawRectangleRec({c.x - 3, r.y - 8, 6, 8}, {196, 56, 62, 255})

	inner := Rect{r.x, r.y + 16, r.width, r.height - 16}
	rl.DrawRectangleRec({inner.x, inner.y, inner.width, inner.height}, {24, 6, 16, 255})
	rl.DrawCircleSector(arch_center, 16, 180, 360, 20, {24, 6, 16, 255})
	rl.BeginBlendMode(.ADDITIVE)
	pulse := 0.8 + 0.2*math.sin(v.time*3)
	soft_glow(&v.sprites, c, 64*pulse, {190, 50, 60, 255})
	for k in 0..<28 {
		a := v.time*(1.6 + f32(k%3)*0.4) + f32(k)*(math.TAU/28)
		rad := 6 + f32(k%4)*3 + 1.5*math.sin(v.time*2 + f32(k))
		p := c + Vec2{math.cos(a) * rad * 0.9, math.sin(a) * rad * 1.5}
		col := rl.Color{255, 200, 110, 200} if k%2 == 0 else rl.Color{230, 60, 70, 200}
		rl.DrawCircleV(p, 1.3, col)
	}
	rl.DrawCircleV(c, 4*pulse, {255, 230, 190, 200})
	rl.EndBlendMode()
}

@(private)
draw_embers :: proc(v: ^View, w: ^World) {
	for e, i in w.embers[:w.ember_count] {
		if e.collected || !on_screen(v, e.position, 16) {
			continue
		}
		bob := math.sin(v.time*3 + f32(i)*0.7) * 1.5
		p := e.position + {0, math.round(bob)}
		rl.BeginBlendMode(.ADDITIVE)
		glow := 0.7 + 0.3*math.sin(v.time*5 + f32(i))
		soft_glow(&v.sprites, p, 16, {u8(160*glow), u8(80*glow), 20, 255})
		rl.EndBlendMode()
		gfx.draw_sprite(v.sprites.ember, int(v.time*5 + f32(i)*0.37) % 2, p)
	}
}

@(private)
draw_enemies :: proc(v: ^View, w: ^World) {
	for e in w.enemies[:w.enemy_count] {
		if !e.alive {
			continue
		}
		c := physics.body2_center(e.body)
		if !on_screen(v, c, 24) {
			continue
		}
		feet := Vec2{c.x, e.body.position.y + e.body.size.y}
		switch e.kind {
		case .Ghoul:
			frame := int(e.phase*6) % 2
			bob := Vec2{1, 1 + 0.06*math.sin(e.phase*12)}
			gfx.draw_sprite_cutout_feet(v.sprites.ghoul, v.sprites.ghoul_paper, frame, feet, 1, e.dir < 0, rl.WHITE, bob)
			rl.BeginBlendMode(.ADDITIVE)
			soft_glow(&v.sprites, feet - {0, 8.5 - f32(frame)}, 5, {120, 44, 14, 255})
			rl.EndBlendMode()
		case .Bat:
			frame := int(e.phase*(14 if e.aggro else 9)) % 2
			gfx.draw_sprite_cutout(v.sprites.bat, v.sprites.bat_paper, frame, c, 1, e.dir < 0)
			if e.aggro {
				rl.BeginBlendMode(.ADDITIVE)
				soft_glow(&v.sprites, c + {0, 1}, 8, {110, 22, 20, 255})
				rl.EndBlendMode()
			}
		case .Totem:
			wobble := Vec2{}
			heat := f32(0.25)
			if e.charge > 0 {
				heat = 1 - e.charge/0.55
				wobble.x = math.round(math.sin(v.time*60)) * 0.5
			}
			gfx.draw_sprite_cutout_feet(v.sprites.totem, v.sprites.totem_paper, 0, feet + wobble, 1)
			top_left := feet + wobble - {8, 16}
			rl.BeginBlendMode(.ADDITIVE)
			for eye in ([2]Vec2{{5, 6}, {11, 6}}) {
				p := top_left + eye
				rl.DrawCircleV(p, 2 + heat*2, {255, 90, 40, u8(120 + 120*heat)})
				soft_glow(&v.sprites, p, 6 + heat*10, {u8(80 + 170*heat), u8(20 + 40*heat), 10, 255})
			}
			rl.EndBlendMode()
		}
	}
}

@(private)
draw_projectiles :: proc(v: ^View, w: ^World) {
	for b in w.projectiles {
		if !b.active {
			continue
		}
		soft_glow(&v.sprites, b.position, 22, {220, 90, 30, 255})
		rl.DrawCircleV(b.position, 4.5, {255, 150, 60, 160})
		rl.DrawCircleV(b.position, 2.5, {255, 240, 200, 255})
	}
}

@(private)
draw_player :: proc(v: ^View, w: ^World) {
	for g in v.ghosts {
		if g.life > 0 {
			a := u8(140 * g.life / 0.25)
			gfx.draw_sprite_feet(v.sprites.player, g.frame, g.feet, 1, g.flip, {255, 90, 70, a})
		}
	}
	if w.phase == .Dying {
		return
	}
	p := w.player
	if p.invulnerable > 0 && w.phase == .Alive && int(v.time*18)%2 == 0 {
		return
	}
	squash := v.squash
	if w.phase == .Exiting {
		k := clamp(w.phase_timer/EXIT_TIME, 0, 1)
		squash *= k
	}
	frame := player_frame(v, w)
	flip := p.ctrl.facing < 0
	// Sliding down a wall: face away from it, cloak flaring.
	if !p.ctrl.grounded && p.ctrl.wall_side != 0 && p.ctrl.body.velocity.y > 0 {
		flip = p.ctrl.wall_side > 0
	}
	gfx.draw_sprite_cutout_feet(v.sprites.player, v.sprites.player_paper, int(frame), player_feet(p), 1, flip, rl.WHITE, squash)
}

@(private)
draw_popups :: proc(v: ^View, frame: ^host.Frame) {
	origin := Vec2{math.round(v.cam.position.x), math.round(v.cam.position.y)}
	center := Vec2{frame.canvas.width, frame.canvas.height} * 0.5
	for i in 0..<v.popups.count {
		p := v.popups.items[i]
		a := clamp(p.life/p.max_life*1.6, 0, 1)
		screen := (p.position - origin) * ZOOM + center
		// Own shadow: the stock one keeps full opacity while the text fades.
		ui.draw_text_centered(frame.theme, p.text, screen + {2, 2}, .Body, {0, 0, 0, u8(160 * a)}, false)
		ui.draw_text_centered(frame.theme, p.text, screen, .Body, ui.with_alpha(p.color, a), false)
	}
}

// ---------------------------------------------------------------------------
// HUD

@(private)
draw_hud :: proc(v: ^View, w: ^World, frame: ^host.Frame) {
	theme := frame.theme
	p := theme.palette
	canvas := frame.canvas
	zones := ui.hud_columns(canvas)
	for zone in zones {
		ui.hud_panel(theme, zone)
	}
	left, middle, right := ui.shrink(zones[0], 10), ui.shrink(zones[1], 10), ui.shrink(zones[2], 10)

	// Vitals and collectibles stay together; star previews have their own lane.
	for i in 0..<w.max_lives {
		scale := f32(2.4)
		if i == w.lives && v.heart_pulse > 0 {
			scale += v.heart_pulse
		}
		gfx.draw_sprite(v.sprites.heart, 0 if i < w.lives else 1,
			{left.x + 10 + f32(i)*25, left.y + 10}, scale)
	}
	gfx.draw_sprite(v.sprites.ember, 0, {left.x + 8, left.y + 36}, 2.2 + v.ember_pulse*0.8)
	ratio := ember_ratio(w)
	ui.draw_text_fit(theme, fmt.tprintf("%d/%d BRACI", w.embers_collected, w.ember_count),
		{left.x + 24, left.y + 26, left.width - 88, 20}, .Small, p.warning)
	lit := [3]bool{true, ratio >= 0.6, ratio >= 0.9 && w.hits == 0}
	for i in 0..<3 {
		ui.draw_star({left.x + left.width - 46 + f32(i)*18, left.y + 36}, 6,
			p.warning if lit[i] else p.border)
	}

	area := "TORRE DI CENERE"
	if v.area < w.chunk_count {
		area = w.chunks[v.area].title
	}
	ui.draw_text_fit(theme, area, {middle.x, middle.y, middle.width, 20}, .Body, p.text, .Center)
	clock := host.format_time(w.time)
	clock_color := p.text_dim
	if w.time_limit > 0 {
		left_time := max(w.time_limit-w.time, 0)
		clock = fmt.tprintf("TEMPO  %s", host.format_time(left_time))
		if left_time < 10 {
			clock_color = ui.mix_color(p.danger, p.text, 0.5+0.5*math.sin(v.time*10))
		}
	}
	ui.draw_text_fit(theme, clock, {middle.x, middle.y + 26, middle.width, 20}, .Body, clock_color, .Center)

	ui.draw_text_fit(theme, "PUNTI", {right.x, right.y, 64, 20}, .Small, p.text_dim)
	ui.draw_text_fit(theme, fmt.tprintf("%d", i64(v.score_shown)),
		{right.x + 68, right.y - 2, right.width - 68, 26}, .Large, p.text, .Right)
	label := "RAGGIUNGI IL PORTALE"
	if w.combo > 1 {
		label = fmt.tprintf("COMBO x%d", w.combo)
	}
	ui.draw_text_fit(theme, label, {right.x, right.y + 27, right.width, 18}, .Small,
		p.warning if w.combo > 1 else p.text_dim, .Right)

	// A slim route ribbon leaves the landing area unobstructed.
	bar := rl.Rectangle{canvas.width*0.5 - 160, canvas.height - 18, 320, 5}
	ui.hud_panel(theme, {bar.x - 8, bar.y - 8, bar.width + 16, 21})
	progress := world_progress(w)
	ui.hud_meter(theme, bar, progress)
	goal := max(physics.rect_center(w.exit_rect).x, 1)
	for c in w.checkpoints[:w.checkpoint_count] {
		x := bar.x + bar.width*clamp(c.feet.x/goal, 0, 1)
		rl.DrawRectangleRec({x - 1, bar.y - 2, 2, bar.height + 4}, p.warning if c.lit else p.border)
	}
	rl.DrawPoly({bar.x + bar.width, bar.y + 2}, 4, 5, 0, p.warning)
	rl.DrawCircleV({bar.x + bar.width*progress, bar.y + 2}, 3, p.text)

	if v.banner_time > 0 && v.banner != "" {
		a := clamp(v.banner_time*2, 0, 1)
		toast := rl.Rectangle{canvas.width*0.5 - 240, ui.HUD_MARGIN + ui.HUD_TOP_HEIGHT + 8, 480, 24}
		ui.draw_text_fit(theme, v.banner, toast, .Body, ui.with_alpha(p.text, a), .Center)
		if v.banner_sub != "" {
			toast.y += 23
			ui.draw_text_fit(theme, v.banner_sub, toast, .Small, ui.with_alpha(p.warning, a), .Center)
		}
	}
}

// The burning tower of the title stands against the moon and drifts closer
// as the run progresses.
@(private)
draw_ash_tower :: proc(v: ^View, canvas: rl.Rectangle, progress, lift: f32) {
	x := canvas.width*0.8 - progress*canvas.width*0.3
	top := 96 + lift*0.06
	color := rl.Color{19, 31, 46, 255}
	rl.DrawRectangleRec({x - 30, top, 60, canvas.height - top}, color)
	rl.DrawRectangleRec({x - 40, top - 8, 80, 12}, color)
	for i in 0..<5 {
		rl.DrawRectangleRec({x - 40 + f32(i)*17.5, top - 18, 10, 10}, color)
	}
	// Buttresses widen the base.
	rl.DrawTriangle({x - 30, top + 140}, {x - 52, canvas.height}, {x - 30, canvas.height}, color)
	rl.DrawTriangle({x + 30, top + 140}, {x + 30, canvas.height}, {x + 52, canvas.height}, color)
	for k in 0..<7 {
		if hash01(k, 77) < 0.35 {
			continue
		}
		side := f32(-14) if k%2 == 0 else f32(8)
		flick := 0.75 + 0.25*math.sin(v.time*(3 + f32(k)) + f32(k))
		rl.DrawRectangleRec({x + side, top + 30 + f32(k)*34, 6, 12}, {u8(220*flick), u8(104*flick), 52, 255})
	}
	rl.BeginBlendMode(.ADDITIVE)
	flare := 1 + 0.08*math.sin(v.time*5) + 0.05*math.sin(v.time*13)
	soft_glow(&v.sprites, {x, top - 20}, 120*flare, {150, 56, 26, 255})
	soft_glow(&v.sprites, {x, top - 14}, 40*flare, {255, 150, 60, 255})
	rl.EndBlendMode()
}
