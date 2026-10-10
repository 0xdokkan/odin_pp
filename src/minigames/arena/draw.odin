// Rendering, feedback and audio for the arena. Reads the World and its event
// records but never changes the simulation; its randomness has its own stream.
package arena

import "core:fmt"
import "core:math"
import rl "vendor:raylib"
import audio "../../engine/audio"
import camera "../../engine/camera"
import fx "../../engine/fx"
import gfx "../../engine/gfx"
import host "../../engine/host"
import physics "../../engine/physics"
import pool "../../engine/pool"
import rng "../../engine/rng"
import tween "../../engine/tween"
import ui "../../engine/ui"

MAX_POPUPS :: 40
MAX_AFTERIMAGES :: 12
MAX_RINGS :: 24
MAX_CRACKS :: 40
FACE_H :: f32(12)

INK :: rl.Color{10, 10, 16, 255}
IVORY :: rl.Color{236, 226, 204, 255}
IVORY_DIM :: rl.Color{160, 152, 136, 255}
CRIMSON :: rl.Color{178, 38, 52, 255}
GOLD :: rl.Color{232, 196, 112, 255}
EMBER :: rl.Color{240, 128, 48, 255}
VIOLET :: rl.Color{186, 120, 255, 255}
CLEAR :: rl.Color{0, 0, 0, 0}

// Iron braziers on the border walls, in cells.
BRAZIERS :: [8][2]int{{6, 0}, {12, 0}, {23, 0}, {29, 0}, {0, 5}, {0, 15}, {35, 5}, {35, 15}}

MUZZLE_SPARKS :: fx.Emitter{
	speed_min = 60, speed_max = 220, direction = {1, 0, 0}, spread = 0.45,
	life_min = 0.05, life_max = 0.14, size_start = 3, size_end = 0,
	color_start = {255, 236, 170, 255}, color_end = {240, 110, 40, 0}, drag = 6,
}

HIT_SPARKS :: fx.Emitter{
	speed_min = 90, speed_max = 260, direction = {1, 0, 0}, spread = 0.75,
	life_min = 0.08, life_max = 0.24, size_start = 3, size_end = 0,
	color_start = {255, 244, 210, 255}, color_end = {240, 90, 40, 0}, drag = 5,
}

DEATH_EMBERS :: fx.Emitter{
	speed_min = 50, speed_max = 260, direction = {0, -1, 0}, spread = math.PI,
	life_min = 0.3, life_max = 0.8, size_start = 5, size_end = 0,
	color_start = {255, 214, 130, 255}, color_end = {200, 40, 30, 0}, gravity = -50, drag = 3.5, spin = 6,
}

ASH :: fx.Emitter{
	speed_min = 40, speed_max = 170, direction = {0, -1, 0}, spread = math.PI,
	life_min = 0.4, life_max = 0.9, size_start = 4, size_end = 1,
	color_start = {44, 36, 44, 235}, color_end = {30, 26, 32, 0}, drag = 5, spin = 9,
}

DUST :: fx.Emitter{
	speed_min = 20, speed_max = 80, direction = {0, -1, 0}, spread = math.PI,
	life_min = 0.25, life_max = 0.55, size_start = 6, size_end = 0,
	color_start = {130, 120, 116, 130}, color_end = {90, 84, 84, 0}, drag = 4,
}

AMBIENT_EMBER :: fx.Emitter{
	speed_min = 8, speed_max = 28, direction = {0, -1, 0}, spread = 0.6,
	life_min = 1.2, life_max = 2.6, size_start = 2, size_end = 0,
	color_start = {255, 170, 90, 220}, color_end = {200, 60, 30, 0}, gravity = -14, drag = 0.4, radius = 8,
}

SPARKLE :: fx.Emitter{
	speed_min = 30, speed_max = 130, direction = {0, -1, 0}, spread = math.PI,
	life_min = 0.3, life_max = 0.7, size_start = 3, size_end = 0,
	color_start = {255, 236, 160, 255}, color_end = {232, 160, 60, 0}, gravity = -60, drag = 2,
}

Popup_Format :: enum u8 {
	Value,
	Plus,
	Minus,
	Times,
	Label,
}

Popup :: struct {
	pos:      Vec2,
	value:    i64,
	label:    string, // static text only
	format:   Popup_Format,
	color:    rl.Color,
	size:     ui.Text_Size,
	life:     f32,
	max_life: f32,
	rise:     f32,
}

Ring :: struct {
	pos:      Vec2,
	time:     f32,
	duration: f32,
	radius:   f32,
	color:    rl.Color,
}

Afterimage :: struct {
	pos:   Vec2,
	life:  f32,
	flip:  bool,
	frame: int,
}

Banner_Kind :: enum u8 {
	None,
	Wave,
	Clear,
	Enraged,
	Victory,
	Defeat,
}

Banner :: struct {
	kind:     Banner_Kind,
	value:    i64,
	flag:     bool,
	subtitle: string, // static text only
	time:     f32,
	duration: f32,
}

Render :: struct {
	sprites:       [Sprite_Id]gfx.Sprite,
	white:         [Sprite_Id]gfx.Sprite,
	level:         rl.RenderTexture2D,
	cracks:        [MAX_CRACKS]Vec2,
	crack_count:   int,
	sparks:        fx.Particles(900),
	debris:        fx.Particles(320),
	embers:        fx.Particles(220),
	ember_timer:   f32,
	popups:        [MAX_POPUPS]Popup,
	popup_count:   int,
	rings:         [MAX_RINGS]Ring,
	afterimages:   [MAX_AFTERIMAGES]Afterimage,
	ghost_timer:   f32,
	flash:         fx.Flash,
	hit_stop:      fx.Hit_Stop,
	cam:           camera.Camera2,
	fx_rng:        rng.Rng,
	time:          f32,
	banner:        Banner,
	muzzle:        f32,
	kick:          f32,
	crosshair:     Vec2,
	pad_aim:       bool,
	last_mouse:    Vec2,
	cursor_hidden: bool,
	heart_shake:   f32,
	hurt_glow:     f32,
	combo_flash:   f32,
	score_shown:   f64,
	boss_ghost:    f32,
	dash_ready:    f32,
	was_dash_ready: bool,
}

render_init :: proc(v: ^Render) {
	sprites_create(&v.sprites, &v.white)
	v.level = rl.LoadRenderTexture(i32(WORLD_W), i32(WORLD_H))
	rl.SetTextureFilter(v.level.texture, .POINT)
}

render_destroy :: proc(v: ^Render) {
	sprites_destroy(&v.sprites, &v.white)
	if v.level.id != 0 {
		rl.UnloadRenderTexture(v.level)
	}
	v.level = {}
	set_cursor_hidden(v, false)
}

// Fresh presentation state for a new round; GPU resources are kept.
render_reset :: proc(v: ^Render, w: ^World) {
	fx.clear(&v.sparks)
	fx.clear(&v.debris)
	v.popup_count = 0
	v.rings = {}
	v.afterimages = {}
	v.flash = {}
	v.hit_stop = {}
	v.banner = {}
	v.muzzle = 0
	v.kick = 0
	v.heart_shake = 0
	v.hurt_glow = 0
	v.combo_flash = 0
	v.score_shown = 0
	v.boss_ghost = 1
	v.was_dash_ready = true
	v.fx_rng = rng.create(rng.derive(w.config.seed, 50))
	v.cam = camera.camera2_create(w.player.pos, 1)
	v.cam.deadzone = {0, 0}
	v.cam.smoothing = 6
	v.cam.bounds_min = {-20, -28}
	v.cam.bounds_max = {WORLD_W + 20, WORLD_H + 20}
	v.cam.shake = camera.shake_default(9)
	// Resets run from update code, outside the canvas texture mode.
	bake_level(v, w)
}

set_cursor_hidden :: proc(v: ^Render, hidden: bool) {
	if hidden == v.cursor_hidden {
		return
	}
	if hidden {
		rl.HideCursor()
	} else {
		rl.ShowCursor()
	}
	v.cursor_hidden = hidden
}

@(private)
v2 :: proc "contextless" (p: Vec2) -> [3]f32 {
	return {p.x, p.y, 0}
}

@(private)
lerp2 :: proc "contextless" (a, b: Vec2, t: f32) -> Vec2 {
	return a + (b-a)*t
}

@(private)
alpha_of :: proc(c: rl.Color, a: f32) -> rl.Color {
	return ui.with_alpha(c, clamp(a, 0, 1))
}

@(private)
shake_scale :: proc(frame: ^host.Frame) -> f32 {
	if frame.profile == nil {
		return 1
	}
	return clamp(frame.profile.settings.screen_shake, 0, 1)
}

@(private)
enemy_color :: proc "contextless" (kind: Enemy_Kind) -> rl.Color {
	switch kind {
	case .Chaser:
		return {255, 150, 60, 255}
	case .Caster:
		return VIOLET
	case .Charger:
		return {255, 90, 70, 255}
	case .Splitter, .Shard:
		return {255, 120, 40, 255}
	case .Boss:
		return GOLD
	}
	return IVORY
}

@(private)
sprite_for :: proc "contextless" (kind: Enemy_Kind) -> Sprite_Id {
	switch kind {
	case .Chaser:
		return .Chaser
	case .Caster:
		return .Caster
	case .Charger:
		return .Charger
	case .Splitter:
		return .Splitter
	case .Shard:
		return .Shard
	case .Boss:
		return .Boss
	}
	return .Chaser
}

power_color :: proc "contextless" (power: Power) -> rl.Color {
	switch power {
	case .Spread:
		return GOLD
	case .Rapid:
		return {255, 110, 70, 255}
	case .Pierce:
		return {150, 210, 255, 255}
	}
	return IVORY
}

power_name :: proc "contextless" (power: Power) -> string {
	switch power {
	case .Spread:
		return "Ventaglio"
	case .Rapid:
		return "Raffica"
	case .Pierce:
		return "Perforante"
	}
	return ""
}

@(private)
pickup_power :: proc "contextless" (kind: Pickup_Kind) -> Power {
	#partial switch kind {
	case .Rapid:
		return .Rapid
	case .Pierce:
		return .Pierce
	}
	return .Spread
}

@(private)
burst :: proc(v: ^Render, e: fx.Emitter, pos: Vec2, dir: Vec2, count: int, additive := true) {
	em := e
	if dir != {} {
		em.direction = {dir.x, dir.y, 0}
	}
	if additive {
		fx.emit(&v.sparks, em, v2(pos), count, &v.fx_rng)
	} else {
		fx.emit(&v.debris, em, v2(pos), count, &v.fx_rng)
	}
}

@(private)
tinted :: proc(e: fx.Emitter, start, end: rl.Color) -> fx.Emitter {
	em := e
	em.color_start = start
	em.color_end = end
	return em
}

@(private)
add_ring :: proc(v: ^Render, pos: Vec2, radius, duration: f32, color: rl.Color) {
	oldest := 0
	for i in 0..<MAX_RINGS {
		if v.rings[i].time >= v.rings[i].duration {
			oldest = i
			break
		}
		if v.rings[i].time > v.rings[oldest].time {
			oldest = i
		}
	}
	v.rings[oldest] = Ring{pos = pos, radius = radius, duration = duration, color = color}
}

@(private)
add_popup :: proc(v: ^Render, pos: Vec2, value: i64, format: Popup_Format, color: rl.Color,
	size := ui.Text_Size.Body, label := "", life: f32 = 0.8, rise: f32 = 34) {
	if v.popup_count >= MAX_POPUPS {
		for i in 1..<MAX_POPUPS {
			v.popups[i-1] = v.popups[i]
		}
		v.popup_count = MAX_POPUPS - 1
	}
	jitter := Vec2{rng.float_signed(&v.fx_rng) * 6, rng.float_signed(&v.fx_rng) * 4}
	v.popups[v.popup_count] = Popup{
		pos = pos + jitter, value = value, label = label, format = format, color = color,
		size = size, life = life, max_life = life, rise = rise,
	}
	v.popup_count += 1
}

@(private)
trauma :: proc(v: ^Render, frame: ^host.Frame, amount: f32) {
	camera.add_trauma(&v.cam.shake, amount*shake_scale(frame))
}

@(private)
show_banner :: proc(v: ^Render, kind: Banner_Kind, value: i64, flag: bool, subtitle: string, duration: f32) {
	v.banner = Banner{kind = kind, value = value, flag = flag, subtitle = subtitle, duration = duration}
}

// Turns this frame's simulation events into particles, sound and shake.
render_events :: proc(v: ^Render, w: ^World, frame: ^host.Frame) {
	bank := frame.audio
	hit_sound, kill_sound := false, false
	for i in 0..<w.event_count {
		e := w.events[i]
		switch e.kind {
		case .Shot:
			v.muzzle = 0.07
			v.kick = 1
			burst(v, MUZZLE_SPARKS, e.pos, e.dir, 3)
			audio.play(bank, .Shoot, 0.2, rng.float_range(&v.fx_rng, 0.9, 1.12) * (0.85 if e.flag else 1))
		case .Bullet_Wall:
			burst(v, HIT_SPARKS, e.pos, e.dir, 4)
			burst(v, DUST, e.pos, e.dir, 2, false)
		case .Enemy_Hit:
			color := enemy_color(e.enemy)
			burst(v, tinted(HIT_SPARKS, {255, 250, 230, 255}, alpha_of(color, 0)), e.pos, e.dir, 5)
			add_popup(v, e.pos+{0, -14}, e.value, .Value, GOLD if e.flag else IVORY, .Small if !e.flag else .Body, life = 0.45, rise = 22)
			if !hit_sound {
				audio.play(bank, .Hit, 0.22, rng.float_range(&v.fx_rng, 0.9, 1.25))
				hit_sound = true
			}
		case .Enemy_Killed:
			kill_feedback(v, w, frame, e, &kill_sound)
		case .Enemy_Spawned:
			color := enemy_color(e.enemy)
			burst(v, tinted(DEATH_EMBERS, {255, 240, 220, 255}, alpha_of(color, 0)), e.pos, {}, 10 if e.enemy != .Boss else 50)
			add_ring(v, e.pos, 30 if e.enemy != .Boss else 110, 0.35, color)
			if e.enemy == .Boss {
				trauma(v, frame, 0.7)
				fx.flash_start(&v.flash, {255, 200, 120, 120}, 0.35)
				audio.play(bank, .Explosion, 0.6, 0.55)
			} else {
				audio.play(bank, .Land, 0.25, 0.7)
			}
		case .Spawn_Warning:
			if e.enemy == .Boss {
				audio.play(bank, .Power_Up, 0.5, 0.45)
			}
		case .Windup:
			audio.play(bank, .Blip, 0.18 if e.enemy != .Boss else 0.35, 0.45 if e.enemy == .Charger else 0.6)
		case .Enemy_Fire:
			audio.play(bank, .Laser, 0.16 if e.enemy != .Boss else 0.26, 0.5 if e.enemy != .Boss else 0.38)
		case .Charge:
			burst(v, DUST, e.pos, -e.dir, 8, false)
			audio.play(bank, .Dash, 0.4, 0.55)
		case .Wall_Slam:
			big := e.enemy == .Boss
			trauma(v, frame, 0.75 if big else 0.4)
			burst(v, DUST, e.pos, -e.dir, 16 if big else 10, false)
			burst(v, ASH, e.pos, -e.dir, 12, false)
			burst(v, HIT_SPARKS, e.pos, -e.dir, 10)
			add_ring(v, e.pos, 70 if big else 40, 0.4, {255, 200, 160, 200})
			audio.play(bank, .Explosion, 0.45, 0.7)
			add_popup(v, e.pos+{0, -24}, 0, .Label, GOLD, .Body, "Stordito!", 0.9, 28)
		case .Split:
			burst(v, tinted(DEATH_EMBERS, {255, 200, 90, 255}, {200, 60, 20, 0}), e.pos, e.dir, 14)
			audio.play(bank, .Hit, 0.3, 0.7)
		case .Player_Hurt:
			fx.flash_start(&v.flash, {200, 20, 30, 110}, 0.28)
			fx.hit_stop(&v.hit_stop, 0.07)
			trauma(v, frame, 0.55)
			burst(v, tinted(HIT_SPARKS, {255, 200, 200, 255}, {180, 20, 30, 0}), e.pos, e.dir, 14)
			add_popup(v, e.pos+{0, -20}, e.value, .Minus, {255, 90, 90, 255}, .Large, life = 0.9)
			v.heart_shake = 0.45
			v.hurt_glow = 1
			audio.play(bank, .Hurt, 0.6)
		case .Player_Dash:
			burst(v, DUST, e.pos, -e.dir, 6, false)
			add_ring(v, e.pos, 22, 0.2, {255, 230, 190, 160})
			audio.play(bank, .Dash, 0.35, rng.float_range(&v.fx_rng, 0.95, 1.1))
		case .Player_Died:
			trauma(v, frame, 0.9)
			fx.hit_stop(&v.hit_stop, 0.22)
			fx.flash_start(&v.flash, {255, 40, 40, 150}, 0.6)
			burst(v, tinted(DEATH_EMBERS, {255, 240, 220, 255}, {200, 20, 30, 0}), e.pos, {}, 40)
			burst(v, ASH, e.pos, {}, 16, false)
			add_ring(v, e.pos, 90, 0.6, CRIMSON)
			show_banner(v, .Defeat, 0, false, "", DEFEAT_TIME+2)
			audio.play(bank, .Explosion, 0.6, 0.6)
		case .Pickup_Dropped:
			burst(v, SPARKLE, e.pos, {}, 6)
			audio.play(bank, .Blip, 0.18, 1.6)
		case .Pickup_Taken:
			burst(v, SPARKLE, e.pos, {}, 18)
			if e.pickup == .Heart {
				add_ring(v, e.pos, 36, 0.35, {255, 90, 100, 220})
				if e.value > 0 {
					add_popup(v, e.pos+{0, -18}, e.value, .Plus, GOLD, .Body)
				} else {
					add_popup(v, e.pos+{0, -18}, 0, .Label, {255, 120, 120, 255}, .Body, "+1 Vita", 1)
				}
				audio.play(bank, .Coin, 0.45)
			} else {
				power := pickup_power(e.pickup)
				add_ring(v, e.pos, 44, 0.4, power_color(power))
				add_popup(v, e.pos+{0, -18}, 0, .Label, power_color(power), .Large, power_name(power), 1.1, 40)
				fx.flash_start(&v.flash, alpha_of(power_color(power), 0.25), 0.2)
				audio.play(bank, .Power_Up, 0.45)
			}
		case .Orb_Pop:
			burst(v, tinted(HIT_SPARKS, {240, 210, 255, 255}, {150, 60, 220, 0}), e.pos, {}, 3)
		case .Combo_Tier:
			if e.value > 1 {
				v.combo_flash = 1
				add_popup(v, w.player.pos+{0, -34}, e.value, .Times, GOLD, .Large, life = 0.9, rise = 26)
				audio.play(bank, .Coin, 0.3, 0.8+f32(e.value)*0.1)
			} else if e.value == 0 {
				add_popup(v, w.player.pos+{0, -34}, 0, .Label, IVORY_DIM, .Body, "Combo spezzata", 0.9, 20)
			}
		case .Wave_Start:
			subtitle := ""
			for kind in Enemy_Kind {
				if kind in w.new_kinds && kind != .Boss {
					subtitle = enemy_name(kind)
					break
				}
			}
			show_banner(v, .Wave, e.value, e.flag, subtitle, 2.4)
			audio.play(bank, .Confirm, 0.5, 0.8)
			if e.flag {
				trauma(v, frame, 0.3)
			}
		case .Wave_Clear:
			if w.phase != .Victory {
				show_banner(v, .Clear, e.value, e.flag, "", 2.2)
			}
			fx.flash_start(&v.flash, {255, 240, 210, 50}, 0.3)
			burst(v, SPARKLE, w.player.pos, {}, 24)
			add_popup(v, w.player.pos+{0, -30}, e.value, .Plus, GOLD, .Large, life = 1.2, rise = 40)
			audio.play(bank, .Coin, 0.5, 1.2)
		case .Boss_Enraged:
			show_banner(v, .Enraged, 0, false, "", 1.8)
			trauma(v, frame, 0.5)
			burst(v, DEATH_EMBERS, e.pos, {}, 30)
			add_ring(v, e.pos, 120, 0.5, EMBER)
			audio.play(bank, .Explosion, 0.5, 0.45)
		case .Victory:
			show_banner(v, .Victory, e.value, false, "", VICTORY_TIME+2)
			fx.flash_start(&v.flash, {255, 230, 170, 120}, 0.5)
			burst(v, SPARKLE, w.player.pos, {}, 50)
		}
	}
}

@(private)
kill_feedback :: proc(v: ^Render, w: ^World, frame: ^host.Frame, e: Event, kill_sound: ^bool) {
	color := enemy_color(e.enemy)
	bank := frame.audio
	switch e.enemy {
	case .Chaser, .Shard:
		burst(v, tinted(DEATH_EMBERS, {255, 230, 160, 255}, {200, 40, 30, 0}), e.pos, e.dir, 12)
		burst(v, ASH, e.pos, e.dir, 4, false)
		add_ring(v, e.pos, 22, 0.25, color)
		fx.hit_stop(&v.hit_stop, 0.02)
		trauma(v, frame, 0.08)
	case .Caster:
		burst(v, tinted(DEATH_EMBERS, {240, 210, 255, 255}, {90, 30, 160, 0}), e.pos, e.dir, 20)
		burst(v, ASH, e.pos, e.dir, 8, false)
		add_ring(v, e.pos, 32, 0.3, VIOLET)
		fx.hit_stop(&v.hit_stop, 0.04)
		trauma(v, frame, 0.18)
	case .Splitter:
		burst(v, tinted(DEATH_EMBERS, {255, 220, 120, 255}, {200, 50, 20, 0}), e.pos, e.dir, 20)
		add_ring(v, e.pos, 34, 0.3, color)
		fx.hit_stop(&v.hit_stop, 0.03)
		trauma(v, frame, 0.15)
	case .Charger:
		burst(v, DEATH_EMBERS, e.pos, e.dir, 26)
		burst(v, ASH, e.pos, e.dir, 18, false)
		add_ring(v, e.pos, 48, 0.4, {255, 120, 90, 255})
		fx.hit_stop(&v.hit_stop, 0.06)
		trauma(v, frame, 0.32)
	case .Boss:
		burst(v, DEATH_EMBERS, e.pos, {}, 120)
		burst(v, SPARKLE, e.pos, {}, 60)
		burst(v, ASH, e.pos, {}, 40, false)
		add_ring(v, e.pos, 160, 0.7, GOLD)
		add_ring(v, e.pos, 100, 0.5, CRIMSON)
		fx.hit_stop(&v.hit_stop, 0.35)
		fx.flash_start(&v.flash, {255, 240, 200, 180}, 0.6)
		trauma(v, frame, 1)
	}
	if e.flag {
		size := ui.Text_Size.Body if combo_multiplier(w.combo) > 1 || e.value >= 50 else .Small
		add_popup(v, e.pos+{0, -22}, e.value, .Plus, GOLD, size, life = 0.9)
	}
	if !kill_sound^ {
		kill_sound^ = true
		big := e.enemy == .Charger || e.enemy == .Boss
		pitch := f32(0.6) if big else rng.float_range(&v.fx_rng, 1.2, 1.6)
		audio.play(bank, .Explosion, 0.5 if big else 0.28, pitch)
	}
}

// Advances presentation-only state. `dt` is the hit-stopped game delta.
render_update :: proc(v: ^Render, w: ^World, frame: ^host.Frame, dt: f32, alpha: f32) {
	v.time += frame.dt
	fx.update(&v.sparks, dt)
	fx.update(&v.debris, dt)
	ambient_update(v, frame.dt)
	for i := 0; i < v.popup_count; {
		q := &v.popups[i]
		q.life -= dt
		if q.life <= 0 {
			for j in i+1..<v.popup_count {
				v.popups[j-1] = v.popups[j]
			}
			v.popup_count -= 1
			continue
		}
		i += 1
	}
	for &r in v.rings {
		r.time += dt
	}
	for &a in v.afterimages {
		a.life = max(a.life-dt*3.5, 0)
	}
	p := &w.player
	if !p.alive && rng.chance(&v.fx_rng, frame.dt*18) {
		fx.emit(&v.embers, AMBIENT_EMBER, v2(p.pos), 1, &v.fx_rng)
	}
	if p.dash_time > 0 {
		v.ghost_timer -= dt
		if v.ghost_timer <= 0 {
			v.ghost_timer = 0.018
			slot := 0
			for i in 0..<MAX_AFTERIMAGES {
				if v.afterimages[i].life < v.afterimages[slot].life {
					slot = i
				}
			}
			v.afterimages[slot] = Afterimage{pos = p.pos, life = 1, flip = p.aim.x < 0, frame = 0}
		}
	}
	fx.flash_update(&v.flash, frame.dt)
	v.muzzle = max(v.muzzle-dt, 0)
	v.kick = max(v.kick-dt*8, 0)
	v.heart_shake = max(v.heart_shake-frame.dt, 0)
	v.hurt_glow = max(v.hurt_glow-frame.dt*1.5, 0)
	v.combo_flash = max(v.combo_flash-frame.dt*2.5, 0)
	v.banner.time += frame.dt
	ready := p.dash_cooldown <= 0
	if ready && !v.was_dash_ready {
		v.dash_ready = 1
	}
	v.was_dash_ready = ready
	v.dash_ready = max(v.dash_ready-frame.dt*3, 0)
	// The score counts up instead of jumping, so big bonuses read as rewards.
	target := f64(w.score)
	v.score_shown += (target - v.score_shown) * f64(1 - math.exp(-10*frame.dt))
	if target-v.score_shown < 1 {
		v.score_shown = target
	}
	if boss := pool.get(&w.enemies, w.boss); boss != nil {
		frac := boss.hp / boss.max_hp
		if frac < v.boss_ghost {
			v.boss_ghost = max(v.boss_ghost-frame.dt*0.35, frac)
		} else {
			v.boss_ghost = frac
		}
	} else {
		v.boss_ghost = 1
	}

	view := Vec2{frame.canvas.width, frame.canvas.height}
	pos := lerp2(p.prev, p.pos, alpha)
	// The camera leans toward the crosshair so threats ahead stay in view.
	look: Vec2
	if v.pad_aim {
		look = p.aim * 70
	} else {
		mouse_world := camera.screen_to_world2(v.cam, view, frame.mouse)
		look = physics.clamp_length2((mouse_world-pos)*0.22, 90)
	}
	v.cam.lookahead = look
	camera.camera2_update(&v.cam, pos, view, frame.dt)
	if v.pad_aim {
		rl_cam := camera.camera2_to_raylib(v.cam, view)
		v.crosshair = rl.GetWorldToScreen2D(pos+p.aim*110, rl_cam)
	} else {
		v.crosshair = frame.mouse
	}
}

// Embers drift up from the cracks and braziers even while paused.
ambient_update :: proc(v: ^Render, dt: f32) {
	fx.update(&v.embers, dt)
	v.ember_timer -= dt
	braziers := BRAZIERS
	for v.ember_timer <= 0 {
		v.ember_timer += 0.045
		pick := rng.int_range(&v.fx_rng, 0, len(braziers)+v.crack_count-1)
		pos: Vec2
		if pick < len(braziers) {
			pos = brazier_flame(braziers[pick])
		} else {
			pos = v.cracks[pick-len(braziers)]
		}
		fx.emit(&v.embers, AMBIENT_EMBER, v2(pos), 1, &v.fx_rng)
	}
}

@(private)
brazier_flame :: proc "contextless" (cell: [2]int) -> Vec2 {
	c := cell_center(cell.x, cell.y)
	if cell.y == 0 {
		return c + {0, 8}
	}
	return c + {0, -2}
}

// ---------------------------------------------------------------------------
// Level baking

@(private)
hash01 :: proc "contextless" (x, y, salt: int) -> f32 {
	h := rng.mix(u64(x*73856093) ~ u64(y*19349663) ~ u64(salt*83492791))
	return f32(h >> 40) / f32(1 << 24)
}

bake_level :: proc(v: ^Render, w: ^World) {
	if v.level.id == 0 {
		return
	}
	salt := int(w.config.seed % 100000)
	rl.BeginTextureMode(v.level)
	rl.ClearBackground(INK)
	v.crack_count = 0
	for y in 0..<MAP_H {
		for x in 0..<MAP_W {
			if open_cell(w, x, y) {
				bake_floor(v, x, y, salt)
			}
		}
	}
	bake_circle(player_start())
	for i in 0..<w.portal_count {
		p := w.portals[i]
		rl.DrawRing(p, 15, 17, 0, 360, 28, {74, 40, 70, 255})
		rl.DrawRing(p, 8, 9, 0, 360, 20, {60, 34, 58, 255})
		for k in 0..<6 {
			a := f32(k) * math.PI / 3
			d := Vec2{math.cos(a), math.sin(a)}
			rl.DrawLineEx(p+d*10, p+d*14, 2, {70, 38, 66, 255})
		}
	}
	for y in 0..<MAP_H {
		for x in 0..<MAP_W {
			if !open_cell(w, x, y) {
				bake_wall(w, x, y, salt)
			}
		}
	}
	braziers := BRAZIERS
	for b in braziers {
		f := brazier_flame(b)
		rl.DrawRectangleRec({f.x - 8, f.y + 2, 16, 5}, {26, 24, 30, 255})
		rl.DrawRectangleRec({f.x - 6, f.y + 7, 12, 2}, {40, 36, 42, 255})
		rl.DrawRectangleRec({f.x - 7, f.y + 1, 14, 1}, {86, 70, 60, 255})
	}
	rl.EndTextureMode()
}

@(private)
bake_floor :: proc(v: ^Render, x, y, salt: int) {
	r := rl.Rectangle{f32(x) * TILE, f32(y) * TILE, TILE, TILE}
	shade := hash01(x, y, salt)
	base := ui.mix_color({48, 44, 52, 255}, {40, 37, 45, 255}, shade)
	rl.DrawRectangleRec(r, base)
	light := ui.mix_color(base, {80, 74, 82, 255}, 0.35)
	mortar := rl.Color{24, 22, 28, 255}
	rl.DrawRectangleRec({r.x, r.y, TILE, 1}, light)
	rl.DrawRectangleRec({r.x, r.y, 1, TILE}, light)
	rl.DrawRectangleRec({r.x, r.y + TILE - 1, TILE, 1}, mortar)
	rl.DrawRectangleRec({r.x + TILE - 1, r.y, 1, TILE}, mortar)
	roll := hash01(x, y, salt+1)
	switch {
	case roll < 0.28:
		rl.DrawRectangleRec({r.x, r.y + 15, TILE, 1}, mortar)
		rl.DrawRectangleRec({r.x, r.y + 16, TILE, 1}, light)
	case roll < 0.4:
		a := Vec2{r.x + 4 + hash01(x, y, salt+2)*12, r.y + 3}
		b := Vec2{r.x + 10 + hash01(x, y, salt+3)*12, r.y + 16}
		c := Vec2{r.x + 6 + hash01(x, y, salt+4)*18, r.y + 29}
		rl.DrawLineEx(a, b, 1, mortar)
		rl.DrawLineEx(b, c, 1, mortar)
	case roll < 0.445:
		// Ember cracks: dim here, the glow pulses on top every frame.
		a := Vec2{r.x + 3, r.y + 6 + hash01(x, y, salt+5)*20}
		b := Vec2{r.x + 16, r.y + 10 + hash01(x, y, salt+6)*12}
		c := Vec2{r.x + 29, r.y + 4 + hash01(x, y, salt+7)*24}
		rl.DrawLineEx(a, b, 2, {70, 26, 18, 255})
		rl.DrawLineEx(b, c, 2, {70, 26, 18, 255})
		rl.DrawLineEx(a, b, 1, {170, 70, 30, 255})
		rl.DrawLineEx(b, c, 1, {170, 70, 30, 255})
		if v.crack_count < MAX_CRACKS {
			v.cracks[v.crack_count] = b
			v.crack_count += 1
		}
	}
	for k in 0..<3 {
		px := r.x + 2 + hash01(x, y, salt+10+k)*28
		py := r.y + 2 + hash01(x, y, salt+20+k)*28
		rl.DrawRectangleRec({math.floor(px), math.floor(py), 1, 1}, mortar if k%2 == 0 else light)
	}
}

@(private)
bake_circle :: proc(c: Vec2) {
	dark := rl.Color{70, 26, 32, 255}
	dim := rl.Color{56, 24, 30, 255}
	rl.DrawRing(c, 108, 112, 0, 360, 72, dark)
	rl.DrawRing(c, 92, 94, 0, 360, 64, dim)
	rl.DrawRing(c, 30, 32, 0, 360, 32, dim)
	points: [5]Vec2
	for i in 0..<5 {
		a := -math.PI/2 + f32(i)*2*math.PI/5
		points[i] = c + Vec2{math.cos(a), math.sin(a)} * 92
	}
	for i in 0..<5 {
		rl.DrawLineEx(points[i], points[(i+2)%5], 2, dim)
	}
	for i in 0..<16 {
		a := f32(i) * 2 * math.PI / 16
		d := Vec2{math.cos(a), math.sin(a)}
		p := c + d*101
		rl.DrawRectanglePro({p.x, p.y, 6, 3}, {3, 1.5}, a*180/math.PI + 90, dark)
	}
}

@(private)
bake_wall :: proc(w: ^World, x, y, salt: int) {
	r := rl.Rectangle{f32(x) * TILE, f32(y) * TILE, TILE, TILE}
	tone := hash01(x, y, salt+30)
	top := ui.mix_color({76, 80, 100, 255}, {66, 70, 90, 255}, tone)
	seam := rl.Color{42, 44, 58, 255}
	rl.DrawRectangleRec(r, top)
	// Staggered bricks.
	for row in 0..<4 {
		ry := r.y + f32(row)*8
		rl.DrawRectangleRec({r.x, ry, TILE, 1}, seam)
		offset := f32(0) if (row+y)%2 == 0 else 8
		for k in 0..<3 {
			sx := r.x + offset + f32(k)*16
			if sx > r.x && sx < r.x+TILE {
				rl.DrawRectangleRec({sx, ry, 1, 8}, seam)
			}
		}
	}
	if open_cell(w, x, y-1) {
		rl.DrawRectangleRec({r.x, r.y, TILE, 2}, {112, 116, 140, 255})
	}
	if open_cell(w, x-1, y) {
		rl.DrawRectangleRec({r.x, r.y, 1, TILE}, {96, 100, 122, 255})
	}
	if open_cell(w, x+1, y) {
		rl.DrawRectangleRec({r.x + TILE - 1, r.y, 1, TILE}, {36, 38, 50, 255})
	}
	if open_cell(w, x, y+1) {
		// Front face spills onto the floor below, which gives the walls height.
		face := rl.Rectangle{r.x, r.y + TILE, TILE, FACE_H}
		rl.DrawRectangleRec(face, {46, 46, 62, 255})
		rl.DrawRectangleRec({face.x, face.y, TILE, 1}, {30, 30, 42, 255})
		rl.DrawRectangleRec({face.x, face.y + 6, TILE, 1}, {36, 36, 50, 255})
		for k in 0..<2 {
			sx := face.x + 8 + f32(k)*16 + (f32(4) if x%2 == 0 else 0)
			rl.DrawRectangleRec({sx, face.y, 1, 6}, {34, 34, 46, 255})
		}
		rl.DrawRectangleGradientV(i32(face.x), i32(face.y+FACE_H), i32(TILE), 8, {0, 0, 0, 110}, {0, 0, 0, 0})
	}
}

// ---------------------------------------------------------------------------
// World drawing

render_draw :: proc(v: ^Render, w: ^World, frame: ^host.Frame, alpha: f32, playing: bool) {
	view := Vec2{frame.canvas.width, frame.canvas.height}
	cam := camera.camera2_to_raylib(v.cam, view)
	rl.BeginMode2D(cam)
	if v.level.id != 0 {
		src := rl.Rectangle{0, 0, WORLD_W, -WORLD_H}
		rl.DrawTextureRec(v.level.texture, src, {0, 0}, rl.WHITE)
	}
	draw_floor_fx(v, w)
	draw_pickups(v, w)
	draw_telegraphs(v, w, alpha)
	draw_shadows(w, alpha)
	fx.draw2d(&v.debris)
	draw_afterimages(v)
	draw_actors(v, w, alpha)

	rl.BeginBlendMode(.ADDITIVE)
	draw_lights(v, w, alpha)
	draw_bullets(w, alpha)
	fx.draw2d(&v.sparks)
	fx.draw2d(&v.embers)
	for r in v.rings {
		if r.time < r.duration {
			gfx.draw_shockwave(r.pos, tween.ease(.Out_Cubic, r.time/r.duration), r.radius, r.color)
		}
	}
	rl.EndBlendMode()
	draw_orbs(v, w, alpha)
	rl.EndMode2D()

	gfx.draw_vignette(view.x, view.y, 0.6)
	draw_danger(v, w, view)
	fx.flash_draw(v.flash, view.x, view.y)
	draw_offscreen(v, w, cam, view)
	draw_popups(v, frame.theme, cam)
	draw_hud(v, w, frame)
	draw_banner(v, w, frame)
	if playing && w.phase != .Defeat {
		draw_crosshair(v)
	}
}

@(private)
draw_floor_fx :: proc(v: ^Render, w: ^World) {
	// Spawn runes: a closing ring and a filling core warn where enemies arrive.
	it := pool.iterator(&w.spawns)
	for s in pool.next(&it) {
		prog := 1 - s.timer/max(s.total, 0.01)
		color := enemy_color(s.kind)
		big := s.kind == .Boss
		radius := f32(48) if big else 18
		rr := radius * (1.3 - 0.4*prog)
		rl.DrawRing(s.pos, rr-2, rr, 0, 360, 36, alpha_of(color, 0.35+0.6*prog))
		rl.DrawCircleV(s.pos, radius*0.8*prog, alpha_of(color, 0.22*prog))
		spin := v.time * (3 if big else 5)
		for k in 0..<6 {
			a := spin + f32(k)*math.PI/3
			d := Vec2{math.cos(a), math.sin(a)}
			rl.DrawLineEx(s.pos+d*(rr+2), s.pos+d*(rr+6), 2, alpha_of(color, 0.5+0.5*prog))
		}
	}
}

@(private)
draw_pickups :: proc(v: ^Render, w: ^World) {
	it := pool.iterator(&w.pickups)
	for pk in pool.next(&it) {
		if pk.life < 3 && int(pk.life*8)%2 == 0 {
			continue
		}
		bob := math.sin(pk.age*4) * 3
		pop := tween.ease(.Out_Back, clamp(pk.age/0.3, 0, 1))
		rl.DrawEllipse(i32(pk.pos.x), i32(pk.pos.y+8), 7*pop, 3*pop, {0, 0, 0, 100})
		center := pk.pos + {0, bob - 4}
		if pk.kind == .Heart {
			gfx.draw_sprite(v.sprites[.Heart], 0, center, 2*pop)
		} else {
			color := power_color(pickup_power(pk.kind))
			gfx.draw_sprite(v.sprites[.Gem], 0, center, 2*pop, tint = color, rotation = math.sin(pk.age*2)*12)
		}
	}
}

@(private)
draw_telegraphs :: proc(v: ^Render, w: ^World, alpha: f32) {
	it := pool.iterator(&w.enemies)
	for e in pool.next(&it) {
		if e.state != .Windup {
			continue
		}
		pos := lerp2(e.prev, e.pos, alpha)
		charge := e.kind == .Charger || (e.kind == .Boss && e.move == .Charge)
		if charge {
			hit := physics.raycast_tiles(&w.tiles, pos, e.facing, 520)
			length := hit.distance if hit.hit else 520
			locked := e.timer <= 0.3
			pulse := 0.5 + 0.5*math.sin(v.time*30)
			a := f32(0.75) if locked else 0.25 + 0.3*pulse
			width := e.radius * 1.8
			angle := math.atan2(e.facing.y, e.facing.x) * 180 / math.PI
			col := rl.Color{255, 70, 60, 255}
			rl.DrawRectanglePro({pos.x, pos.y, length, width}, {0, width*0.5}, angle, alpha_of(col, a*0.28))
			side := Vec2{-e.facing.y, e.facing.x} * width * 0.5
			rl.DrawLineEx(pos+side, pos+side+e.facing*length, 1, alpha_of(col, a))
			rl.DrawLineEx(pos-side, pos-side+e.facing*length, 1, alpha_of(col, a))
			// Chevrons crawl along the lane toward its end.
			for k := f32(24); k < length-8; k += 34 {
				off := math.mod(k+v.time*120, length)
				c := pos + e.facing*off
				l := c - e.facing*7 + side*0.4
				rr := c - e.facing*7 - side*0.4
				rl.DrawLineEx(l, c, 2, alpha_of(col, a))
				rl.DrawLineEx(rr, c, 2, alpha_of(col, a))
			}
		} else if e.kind == .Boss && e.move == .Burst {
			prog := 1 - e.timer/0.9
			r := e.radius + 10 + 60*prog
			rl.DrawRing(pos, r-3, r, 0, 360, 48, alpha_of({255, 120, 60, 255}, 0.3+0.5*prog))
		} else if e.kind == .Boss && e.move == .Fan {
			dir := physics.normalize2(w.player.pos - pos)
			base := math.atan2(dir.y, dir.x)
			for i in 0..<5 {
				a := base + (f32(i)-2)*0.16
				d := Vec2{math.cos(a), math.sin(a)}
				rl.DrawLineEx(pos+d*e.radius, pos+d*(e.radius+120), 1, alpha_of({255, 160, 90, 255}, 0.35))
			}
		} else if e.kind == .Caster {
			dir := physics.normalize2(w.player.pos - pos)
			prog := 1 - e.timer/0.6
			for k := f32(18); k < 140; k += 14 {
				rl.DrawCircleV(pos+dir*k, 1.5, alpha_of(VIOLET, 0.5*prog))
			}
		}
	}
}

@(private)
draw_shadows :: proc(w: ^World, alpha: f32) {
	it := pool.iterator(&w.enemies)
	for e in pool.next(&it) {
		pos := lerp2(e.prev, e.pos, alpha)
		rl.DrawEllipse(i32(pos.x), i32(pos.y+e.radius*0.85), e.radius*1.05, e.radius*0.42, {0, 0, 0, 110})
	}
	p := &w.player
	if p.alive {
		pos := lerp2(p.prev, p.pos, alpha)
		rl.DrawEllipse(i32(pos.x), i32(pos.y+PLAYER_RADIUS*0.9), 11, 4.5, {0, 0, 0, 120})
	}
}

@(private)
draw_afterimages :: proc(v: ^Render) {
	for a in v.afterimages {
		if a.life <= 0 {
			continue
		}
		gfx.draw_sprite_feet(v.white[.Player], a.frame, a.pos+{0, PLAYER_RADIUS + 1}, 2, a.flip,
			alpha_of({255, 150, 70, 255}, a.life*0.45))
	}
}

@(private)
Draw_Item :: struct {
	y:     f32,
	enemy: int, // pool slot, or -1 for the player
}

@(private)
draw_actors :: proc(v: ^Render, w: ^World, alpha: f32) {
	items: [MAX_ENEMIES + 1]Draw_Item
	count := 0
	p := &w.enemies
	for i in 0..<p.high_water {
		if p.alive[i] {
			e := &p.items[i]
			items[count] = Draw_Item{y = lerp2(e.prev, e.pos, alpha).y, enemy = i}
			count += 1
		}
	}
	items[count] = Draw_Item{y = lerp2(w.player.prev, w.player.pos, alpha).y, enemy = -1}
	count += 1
	// Insertion sort: lists are short and nearly sorted frame to frame.
	for i in 1..<count {
		item := items[i]
		j := i - 1
		for j >= 0 && items[j].y > item.y {
			items[j+1] = items[j]
			j -= 1
		}
		items[j+1] = item
	}
	for i in 0..<count {
		if items[i].enemy < 0 {
			if w.player.alive {
				draw_player(v, w, alpha)
			}
		} else {
			draw_enemy(v, w, &p.items[items[i].enemy], alpha)
		}
	}
	// The fallen hero stays readable above the swarm.
	if !w.player.alive {
		draw_player(v, w, alpha)
	}
}

@(private)
draw_player :: proc(v: ^Render, w: ^World, alpha: f32) {
	p := &w.player
	pos := lerp2(p.prev, p.pos, alpha)
	feet := pos + {0, PLAYER_RADIUS + 1}
	sprite := v.sprites[.Player]
	flip := p.aim.x < 0
	if !p.alive {
		// Topples over and smoulders.
		t := clamp(w.phase_time/0.45, 0, 1)
		angle := (f32(-90) if flip else 90) * tween.ease(.Out_Bounce, t)
		tint := ui.mix_color(rl.WHITE, {210, 150, 140, 255}, t)
		gfx.draw_sprite(sprite, 0, pos+{0, PLAYER_RADIUS - 5}, 2, flip, tint, angle)
		return
	}
	speed := physics.length2(p.vel)
	moving := speed > 30
	frame := int(p.walk_time*9) % 2 if moving else 0
	squash := Vec2{1, 1}
	if p.dash_time > 0 {
		squash = {1.28, 0.8}
	} else if moving {
		squash.y = 1 + 0.06*math.sin(p.walk_time*18)
		squash.x = 2 - squash.y
	}
	tint := rl.WHITE
	if p.hurt_time < HURT_INVULN && int(v.time*16)%2 == 0 {
		tint = {255, 255, 255, 90}
	}
	behind := p.aim.y < -0.35
	if behind {
		draw_staff(v, p, pos)
	}
	gfx.draw_sprite_feet(sprite, frame, feet, 2, flip, tint, squash)
	if p.hurt_time < 0.1 {
		gfx.draw_sprite_feet(v.white[.Player], frame, feet, 2, flip, {255, 120, 120, 230}, squash)
	} else if p.dash_time > 0 {
		gfx.draw_sprite_feet(v.white[.Player], frame, feet, 2, flip, {255, 230, 190, 120}, squash)
	}
	if !behind {
		draw_staff(v, p, pos)
	}
}

@(private)
draw_staff :: proc(v: ^Render, p: ^Player, pos: Vec2) {
	hand := pos + Vec2{p.aim.x*3, 2}
	tip := hand + p.aim*17
	rl.DrawLineEx(hand, tip, 3, {52, 38, 34, 255})
	rl.DrawLineEx(hand+{0, -1}, tip+{0, -1}, 1, {150, 110, 74, 255})
	glow := GOLD
	for power in Power {
		if p.power[power] > 0 {
			glow = power_color(power)
		}
	}
	rl.DrawCircleV(tip, 2.5, glow)
	if v.muzzle > 0 {
		k := v.muzzle / 0.07
		rl.DrawCircleV(tip+p.aim*4, 7*k, {255, 244, 200, u8(230*k)})
		rl.DrawPoly(tip+p.aim*4, 4, 10*k, v.time*900, {255, 200, 120, u8(160*k)})
	}
}

@(private)
draw_enemy :: proc(v: ^Render, w: ^World, e: ^Enemy, alpha: f32) {
	pos := lerp2(e.prev, e.pos, alpha)
	id := sprite_for(e.kind)
	scale := f32(3) if e.kind == .Boss else 2
	flip := w.player.pos.x < pos.x
	if e.kind == .Charger && (e.state == .Windup || e.state == .Attack) {
		flip = e.facing.x < 0
	}
	frames := sprite_frame_count(id)
	frame := int(e.age*6+f32(e.id)*0.37) % frames
	squash := Vec2{1, 1}
	offset: Vec2
	switch e.kind {
	case .Chaser, .Shard:
		offset.y = -abs(math.sin(e.age*14+f32(e.id))) * 2
	case .Splitter:
		hop := max(math.sin(e.age*5.5), 0)
		squash = {1.14 - 0.24*hop, 0.86 + 0.3*hop}
		offset.y = -hop * 5
	case .Caster:
		offset.y = math.sin(e.age*3+f32(e.id)) * 2 - 2
	case .Charger:
		if e.state == .Windup {
			offset.x = math.sin(v.time*90) * 1.5
		} else if e.state == .Attack {
			squash = {1.15, 0.9}
		}
	case .Boss:
		offset.y = math.sin(e.age*2) * 2
	}
	if e.age < 0.3 {
		k := tween.ease(.Out_Back, e.age/0.3)
		squash *= Vec2{1.4 - 0.4*k, max(k, 0.05)}
	}
	if e.flash > 0 {
		k := e.flash / HIT_FLASH
		squash *= Vec2{1 + 0.12*k, 1 - 0.1*k}
	}
	feet := pos + {0, e.radius} + offset
	gfx.draw_sprite_feet(v.sprites[id], frame, feet, scale, flip, rl.WHITE, squash)
	overlay := rl.Color{}
	if e.flash > 0 {
		// Fades out, so sustained fire still shows the sprite underneath.
		k := e.flash / HIT_FLASH
		overlay = {255, 255, 255, u8((f32(130) if e.kind == .Boss else 210) * k)}
	} else if e.state == .Windup {
		pulse := 0.5 + 0.5*math.sin(v.time*28)
		overlay = alpha_of(enemy_color(e.kind), 0.25+0.45*pulse)
	} else if e.kind == .Boss && e.enraged {
		overlay = alpha_of({255, 80, 40, 255}, 0.15+0.15*math.sin(v.time*10))
	}
	if overlay.a > 0 {
		gfx.draw_sprite_feet(v.white[id], frame, feet, scale, flip, overlay, squash)
	}
	if e.state == .Stunned {
		for k in 0..<3 {
			a := v.time*5 + f32(k)*2.1
			star := pos + Vec2{math.cos(a)*e.radius*0.8, -e.radius*2.1 + math.sin(a)*3}
			rl.DrawPoly(star, 4, 3, v.time*200, GOLD)
		}
	}
	// Health bars only for the sturdy ones, once they are hurt.
	if e.kind != .Boss && e.kind != .Chaser && e.kind != .Shard && e.hp < e.max_hp {
		bw := e.radius * 2
		top := feet.y - f32(v.sprites[id].height)*scale*squash.y - 6
		rl.DrawRectangleRec({pos.x - bw*0.5 - 1, top - 1, bw + 2, 4}, {10, 8, 12, 200})
		rl.DrawRectangleRec({pos.x - bw*0.5, top, bw*(e.hp/e.max_hp), 2}, enemy_color(e.kind))
	}
}

@(private)
draw_lights :: proc(v: ^Render, w: ^World, alpha: f32) {
	t := v.time
	braziers := BRAZIERS
	for b, i in braziers {
		f := brazier_flame(b)
		flick := 0.8 + 0.2*math.sin(t*13+f32(i)*1.7) * math.sin(t*7.3+f32(i))
		rl.DrawCircleGradient(f, 80*flick, {255, 140, 60, 46}, CLEAR)
		rl.DrawCircleGradient(f, 14*flick, {255, 200, 120, 160}, CLEAR)
		h := 7 + 3*flick
		rl.DrawTriangle(f+{-4, 2}, f+{4, 2}, f+{math.sin(t*9+f32(i))*1.5, -h}, {255, 150, 60, 200})
		rl.DrawTriangle(f+{-2, 2}, f+{2, 2}, f+{0, -h*0.6}, {255, 230, 160, 220})
	}
	for i in 0..<v.crack_count {
		c := v.cracks[i]
		pulse := 0.5 + 0.5*math.sin(t*1.8+f32(i)*2.3)
		rl.DrawCircleGradient(c, 22, {255, 110, 40, u8(26 + 40*pulse)}, CLEAR)
	}
	center := player_start()
	pulse := 0.5 + 0.5*math.sin(t*1.3)
	rl.DrawRing(center, 106, 114, 0, 360, 72, {200, 40, 50, u8(8 + 14*pulse)})
	for i in 0..<w.portal_count {
		rl.DrawRing(w.portals[i], 13, 19, 0, 360, 28, {150, 70, 200, u8(16 + 14*math.sin(t*2+f32(i)))})
	}
	sit := pool.iterator(&w.spawns)
	for s in pool.next(&sit) {
		prog := 1 - s.timer/max(s.total, 0.01)
		radius := f32(130) if s.kind == .Boss else 46
		rl.DrawCircleGradient(s.pos, radius*(0.4+prog), alpha_of(enemy_color(s.kind), 0.35*prog), CLEAR)
	}
	p := &w.player
	ppos := lerp2(p.prev, p.pos, alpha)
	if p.alive {
		rl.DrawCircleGradient(ppos, 170, {255, 170, 100, 34}, CLEAR)
	} else {
		flicker := 0.8 + 0.2*math.sin(t*9)
		rl.DrawCircleGradient(ppos, 60*flicker, {255, 60, 40, 90}, CLEAR)
	}
	if v.muzzle > 0 {
		rl.DrawCircleGradient(ppos+p.aim*20, 60, {255, 200, 120, u8(90 * v.muzzle / 0.07)}, CLEAR)
	}
	pit := pool.iterator(&w.pickups)
	for pk in pool.next(&pit) {
		color := rl.Color{255, 80, 90, 255} if pk.kind == .Heart else power_color(pickup_power(pk.kind))
		rl.DrawCircleGradient(pk.pos, 26+3*math.sin(pk.age*5), alpha_of(color, 0.35), CLEAR)
	}
	eit := pool.iterator(&w.enemies)
	for e in pool.next(&eit) {
		pos := lerp2(e.prev, e.pos, alpha)
		if e.state == .Windup {
			color := enemy_color(e.kind)
			rl.DrawCircleGradient(pos, e.radius*3, alpha_of(color, 0.35), CLEAR)
			if e.kind == .Caster {
				hand := pos + physics.normalize2(w.player.pos-pos)*12 + {0, -6}
				prog := 1 - e.timer/0.6
				rl.DrawCircleV(hand, 2+4*prog, alpha_of(VIOLET, 0.9))
			}
		}
		if e.kind == .Boss {
			rl.DrawCircleGradient(pos, 90, {255, 120, 50, 40}, CLEAR)
		} else {
			// A faint underglow lifts the creatures off the dark floor.
			rl.DrawCircleGradient(pos+{0, 4}, e.radius*2.6, alpha_of(enemy_color(e.kind), 0.14), CLEAR)
		}
	}
}

@(private)
draw_bullets :: proc(w: ^World, alpha: f32) {
	it := pool.iterator(&w.bullets)
	for b in pool.next(&it) {
		pos := lerp2(b.prev, b.pos, alpha)
		dir := physics.normalize2(b.vel)
		pierce := b.radius > 5
		col := rl.Color{150, 210, 255, 255} if pierce else rl.Color{255, 196, 100, 255}
		tail := pos - dir*(20 if pierce else 13)
		rl.DrawLineEx(tail, pos, 5 if pierce else 3, alpha_of(col, 0.45))
		rl.DrawLineEx(pos-dir*6, pos, 2, alpha_of({255, 250, 230, 255}, 0.9))
		rl.DrawCircleGradient(pos, b.radius*3.2, alpha_of(col, 0.3), CLEAR)
	}
}

@(private)
draw_orbs :: proc(v: ^Render, w: ^World, alpha: f32) {
	rl.BeginBlendMode(.ADDITIVE)
	it := pool.iterator(&w.orbs)
	for o in pool.next(&it) {
		pos := lerp2(o.prev, o.pos, alpha)
		col := rl.Color{255, 110, 50, 255} if o.big else VIOLET
		rl.DrawCircleGradient(pos, o.radius*3, alpha_of(col, 0.4), CLEAR)
	}
	rl.EndBlendMode()
	it = pool.iterator(&w.orbs)
	for o, h in pool.next(&it) {
		pos := lerp2(o.prev, o.pos, alpha)
		pulse := 1 + 0.15*math.sin(v.time*22+f32(h.index))
		outer := rl.Color{200, 50, 40, 255} if o.big else rl.Color{120, 50, 200, 255}
		inner := rl.Color{255, 200, 120, 255} if o.big else rl.Color{230, 190, 255, 255}
		rl.DrawCircleV(pos, o.radius*pulse+1, {20, 8, 20, 200})
		rl.DrawCircleV(pos, o.radius*pulse, outer)
		rl.DrawCircleV(pos, o.radius*0.55*pulse, inner)
	}
}

// ---------------------------------------------------------------------------
// Screen-space overlays and HUD

@(private)
text :: proc(theme: ^ui.Theme, s: string, pos: Vec2, size: ui.Text_Size, color: rl.Color, a: f32 = 1) {
	ui.draw_text(theme, s, pos + {2, 2}, size, alpha_of({0, 0, 0, 170}, a), false)
	ui.draw_text(theme, s, pos, size, alpha_of(color, a*f32(color.a)/255), false)
}

@(private)
text_centered :: proc(theme: ^ui.Theme, s: string, center: Vec2, size: ui.Text_Size, color: rl.Color, a: f32 = 1) {
	m := ui.measure(theme, s, size)
	text(theme, s, center - m*0.5, size, color, a)
}

@(private)
text_right :: proc(theme: ^ui.Theme, s: string, right_top: Vec2, size: ui.Text_Size, color: rl.Color, a: f32 = 1) {
	m := ui.measure(theme, s, size)
	text(theme, s, {right_top.x - m.x, right_top.y}, size, color, a)
}

// Pure-red vignette while low on hearts, plus a pulse after every hit.
@(private)
draw_danger :: proc(v: ^Render, w: ^World, view: Vec2) {
	p := &w.player
	low := p.alive && p.hp*3 <= p.max_hp
	strength := v.hurt_glow * 0.55
	if low {
		beat := math.pow(max(math.sin(v.time*5.5), 0), 6)
		strength = max(strength, 0.2 + 0.22*beat)
	}
	if strength <= 0 {
		return
	}
	a := u8(255 * clamp(strength, 0, 1))
	band := i32(min(view.x, view.y) * 0.22)
	red := rl.Color{170, 10, 24, a}
	rl.DrawRectangleGradientV(0, 0, i32(view.x), band, red, CLEAR)
	rl.DrawRectangleGradientV(0, i32(view.y)-band, i32(view.x), band, CLEAR, red)
	rl.DrawRectangleGradientH(0, 0, band, i32(view.y), red, CLEAR)
	rl.DrawRectangleGradientH(i32(view.x)-band, 0, band, i32(view.y), CLEAR, red)
}

@(private)
triangle :: proc(a, b, c: Vec2, color: rl.Color) {
	// raylib culls clockwise triangles; order the corners for it.
	cross := (b.x-a.x)*(c.y-a.y) - (b.y-a.y)*(c.x-a.x)
	if cross > 0 {
		rl.DrawTriangle(a, c, b, color)
	} else {
		rl.DrawTriangle(a, b, c, color)
	}
}

@(private)
draw_offscreen :: proc(v: ^Render, w: ^World, cam: rl.Camera2D, view: Vec2) {
	center := view * 0.5
	half := center - {22, 22}
	shown := 0
	it := pool.iterator(&w.enemies)
	for e in pool.next(&it) {
		s := rl.GetWorldToScreen2D(e.pos, cam)
		if s.x > -4 && s.y > -4 && s.x < view.x+4 && s.y < view.y+4 {
			continue
		}
		d := physics.normalize2(s - center)
		if d == {} {
			continue
		}
		t := min(half.x/max(abs(d.x), 0.001), half.y/max(abs(d.y), 0.001))
		p := center + d*t
		perp := Vec2{-d.y, d.x}
		color := alpha_of(enemy_color(e.kind), 0.6+0.3*math.sin(v.time*8))
		size := f32(10) if e.kind == .Boss else 7
		triangle(p+d*size, p-d*size*0.5+perp*size*0.7, p-d*size*0.5-perp*size*0.7, color)
		shown += 1
		if shown >= 16 {
			break
		}
	}
}

@(private)
draw_popups :: proc(v: ^Render, theme: ^ui.Theme, cam: rl.Camera2D) {
	for i in 0..<v.popup_count {
		q := v.popups[i]
		t := 1 - q.life/q.max_life
		a := min(q.life/0.25, 1)
		s := rl.GetWorldToScreen2D(q.pos, cam)
		s.y -= q.rise * tween.ease(.Out_Cubic, t)
		label: string
		switch q.format {
		case .Value:
			label = fmt.tprintf("%d", q.value)
		case .Plus:
			label = fmt.tprintf("+%d", q.value)
		case .Minus:
			label = fmt.tprintf("-%d", q.value)
		case .Times:
			label = fmt.tprintf("x%d", q.value)
		case .Label:
			label = q.label
		}
		text_centered(theme, label, s, q.size, q.color, a)
	}
}

@(private)
bar :: proc(r: rl.Rectangle, frac: f32, fill: rl.Color, back := rl.Color{24, 22, 30, 220}) {
	rl.DrawRectangleRec({r.x - 1, r.y - 1, r.width + 2, r.height + 2}, {6, 6, 10, 200})
	rl.DrawRectangleRec(r, back)
	rl.DrawRectangleRec({r.x, r.y, r.width * clamp(frac, 0, 1), r.height}, fill)
}

@(private)
draw_hud :: proc(v: ^Render, w: ^World, frame: ^host.Frame) {
	theme := frame.theme
	view := Vec2{frame.canvas.width, frame.canvas.height}
	p := &w.player
	rl.DrawRectangleGradientV(0, 0, i32(view.x), 70, {6, 6, 10, 190}, CLEAR)

	// Hearts.
	shake := f32(0)
	if v.heart_shake > 0 {
		shake = math.sin(v.time*70) * 3 * v.heart_shake / 0.45
	}
	low := p.hp*3 <= p.max_hp
	for i in 0..<p.max_hp {
		pos := Vec2{26 + f32(i)*21 + shake, 20}
		if i < p.hp {
			beat := f32(1)
			if low {
				beat = 1 + 0.15*math.pow(max(math.sin(v.time*5.5), 0), 6)
			}
			gfx.draw_sprite(v.sprites[.Heart], 0, pos, 2*beat)
		} else {
			gfx.draw_sprite(v.white[.Heart], 0, pos, 2, tint = {46, 40, 52, 255})
		}
	}
	// Dash meter.
	ready := p.dash_cooldown <= 0
	dash := rl.Rectangle{16, 38, 92, 5}
	fill := GOLD if ready else rl.Color{120, 108, 88, 255}
	if v.dash_ready > 0 {
		fill = ui.mix_color(GOLD, rl.WHITE, v.dash_ready)
	}
	bar(dash, 1-p.dash_cooldown/DASH_COOLDOWN, fill)
	text(theme, "Scatto", {dash.x + dash.width + 8, dash.y - 7}, .Small, GOLD if ready else IVORY_DIM)
	// Active powers.
	y := f32(56)
	for power in Power {
		remaining := p.power[power]
		if remaining <= 0 {
			continue
		}
		color := power_color(power)
		blink := remaining < 2 && int(v.time*8)%2 == 0
		gfx.draw_sprite(v.sprites[.Gem], 0, {24, y + 9}, 1.6, tint = color)
		text(theme, power_name(power), {38, y}, .Small, color, 0.5 if blink else 1)
		bar({38, y + 17, 70, 3}, remaining/POWER_DURATION, color)
		y += 26
	}

	// Wave status.
	cx := view.x * 0.5
	switch w.phase {
	case .Calm:
		label := "Preparati" if w.wave == 0 else "Tregua"
		text_centered(theme, label, {cx, 16}, .Body, IVORY_DIM)
		calm := FIRST_CALM if w.wave == 0 else CALM_TIME
		bar({cx - 100, 32, 200, 4}, w.phase_time/calm, GOLD)
	case .Fight, .Victory, .Defeat:
		label := fmt.tprintf("Ondata %d / %d", w.wave, w.tuning.waves)
		text_centered(theme, label, {cx, 16}, .Body, IVORY)
		remaining := f32(1)
		if w.wave_total > 0 {
			remaining = 1 - f32(w.wave_killed)/f32(w.wave_total)
		}
		bar({cx - 100, 32, 200, 4}, remaining, CRIMSON)
	}

	// Score and combo, top right.
	right := view.x - 16
	score_color := ui.mix_color(IVORY, GOLD, clamp(f32(f64(w.score)-v.score_shown)/200, 0, 1))
	text_right(theme, fmt.tprintf("%d", i64(v.score_shown)), {right, 4}, .Large, score_color)
	goal := w.tuning.combo_goal
	if w.combo > 0 {
		mult := combo_multiplier(w.combo)
		flash := ui.mix_color(GOLD, rl.WHITE, v.combo_flash)
		text_right(theme, fmt.tprintf("x%d", mult), {right, 30}, .Large, flash)
		mw := ui.measure(theme, fmt.tprintf("x%d", mult), .Large).x
		text_right(theme, fmt.tprintf("Combo %d", w.combo), {right - mw - 10, 38}, .Small, IVORY)
		bar({right - 110, 60, 110, 3}, w.combo_timer/COMBO_WINDOW, GOLD)
	}
	best_color := GOLD if w.best_combo >= goal else IVORY_DIM
	text_right(theme, fmt.tprintf("Combo migliore %d / %d", w.best_combo, goal), {right, 66}, .Small, best_color)

	// Boss health.
	if boss := pool.get(&w.enemies, w.boss); boss != nil {
		r := rl.Rectangle{cx - 210, view.y - 30, 420, 9}
		text_centered(theme, enemy_name(.Boss), {cx, r.y - 12}, .Small, GOLD)
		rl.DrawRectangleRec({r.x - 2, r.y - 2, r.width + 4, r.height + 4}, {6, 6, 10, 220})
		rl.DrawRectangleRec(r, {30, 18, 22, 255})
		rl.DrawRectangleRec({r.x, r.y, r.width * v.boss_ghost, r.height}, {236, 226, 204, 200})
		fill_color := CRIMSON
		if boss.enraged {
			fill_color = ui.mix_color(CRIMSON, EMBER, 0.5+0.5*math.sin(v.time*8))
		}
		rl.DrawRectangleRec({r.x, r.y, r.width * clamp(boss.hp/boss.max_hp, 0, 1), r.height}, fill_color)
		rl.DrawRectangleRec({r.x, r.y, r.width, 2}, {255, 255, 255, 40})
	}
}

@(private)
draw_banner :: proc(v: ^Render, w: ^World, frame: ^host.Frame) {
	b := &v.banner
	if b.kind == .None || b.time > b.duration {
		return
	}
	theme := frame.theme
	view := Vec2{frame.canvas.width, frame.canvas.height}
	fade_in := clamp(b.time/0.3, 0, 1)
	fade_out := clamp((b.duration-b.time)/0.45, 0, 1)
	a := min(fade_in, fade_out)
	slide := (1 - tween.ease(.Out_Back, fade_in)) * 26
	y := view.y*0.3 + slide
	title, subtitle: string
	color := IVORY
	sub_color := IVORY_DIM
	switch b.kind {
	case .None:
	case .Wave:
		if b.flag {
			title = "Ultima ondata"
			subtitle = "Il Signore delle Braci si risveglia"
			color = GOLD
			sub_color = {255, 140, 90, 255}
		} else {
			title = fmt.tprintf("Ondata %d", b.value)
			if b.subtitle != "" {
				subtitle = fmt.tprintf("Nuovi nemici: %s", b.subtitle)
				sub_color = GOLD
			} else {
				subtitle = fmt.tprintf("di %d", w.tuning.waves)
			}
		}
	case .Clear:
		title = "Ondata perfetta!" if b.flag else "Ondata superata"
		subtitle = fmt.tprintf("Bonus +%d", b.value)
		color = GOLD if b.flag else IVORY
	case .Enraged:
		title = "Il Signore si infuria!"
		color = {255, 130, 70, 255}
	case .Victory:
		title = "Arena conquistata!"
		subtitle = fmt.tprintf("Vita residua +%d", b.value)
		color = GOLD
	case .Defeat:
		title = "Sei caduto tra le braci"
		color = {255, 90, 90, 255}
	}
	band := rl.Rectangle{0, y - 34, view.x, 84 if subtitle != "" else 62}
	shade := rl.Color{6, 4, 8, u8(150 * a)}
	rl.DrawRectangleGradientH(0, i32(band.y), i32(view.x*0.5), i32(band.height), CLEAR, shade)
	rl.DrawRectangleGradientH(i32(view.x*0.5), i32(band.y), i32(view.x*0.5), i32(band.height), shade, CLEAR)
	line := alpha_of(CRIMSON, a*0.8)
	rl.DrawRectangleGradientH(i32(view.x*0.2), i32(band.y), i32(view.x*0.3), 1, CLEAR, line)
	rl.DrawRectangleGradientH(i32(view.x*0.5), i32(band.y), i32(view.x*0.3), 1, line, CLEAR)
	text_centered(theme, title, {view.x * 0.5, y}, .Title, color, a)
	if subtitle != "" {
		text_centered(theme, subtitle, {view.x * 0.5, y + 34}, .Body, sub_color, a)
	}
}

@(private)
draw_crosshair :: proc(v: ^Render) {
	c := v.crosshair
	r := 9 + 5*v.kick
	for pass in 0..<2 {
		col := rl.Color{0, 0, 0, 150} if pass == 0 else GOLD
		o := Vec2{1, 1} if pass == 0 else Vec2{}
		rl.DrawRing(c+o, r-1.5, r, 0, 360, 28, col)
		for k in 0..<4 {
			a := f32(k)*math.PI/2 + math.PI/4 + v.time*0.8
			d := Vec2{math.cos(a), math.sin(a)}
			rl.DrawLineEx(c+o+d*(r+2), c+o+d*(r+7), 2, col)
		}
	}
	rl.DrawCircleV(c, 1.5, IVORY)
}
