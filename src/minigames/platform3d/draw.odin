package platform3d

import "core:fmt"
import "core:math"
import rl "vendor:raylib"
import rlgl "vendor:raylib/rlgl"
import audio "../../engine/audio"
import camera "../../engine/camera"
import fx "../../engine/fx"
import gfx "../../engine/gfx"
import host "../../engine/host"
import physics "../../engine/physics"
import rng "../../engine/rng"
import ui "../../engine/ui"
import tween "../../engine/tween"

SPARK_COUNT :: 1024
DUST_COUNT :: 384

PITCH_MIN :: f32(0.12)
PITCH_MAX :: f32(1.05)
ZOOM_MIN :: f32(7)
ZOOM_MAX :: f32(15)

// The tower's diorama palette: obsidian, blue slate, ivory cutouts and gold rewards.
SKY_TOP :: rl.Color{5, 9, 16, 255}
SKY_HORIZON :: rl.Color{28, 44, 65, 255}
ABYSS_MID :: rl.Color{16, 28, 43, 255}
ABYSS_DEEP :: rl.Color{7, 12, 21, 255}
FOG :: rl.Color{24, 39, 58, 235}
IVORY :: rl.Color{236, 226, 204, 255}
IVORY_DIM :: rl.Color{160, 152, 136, 255}
GOLD :: rl.Color{232, 196, 112, 255}
CRIMSON :: rl.Color{196, 44, 58, 255}
SOUL :: rl.Color{140, 220, 255, 255}

Message_Kind :: enum u8 {
	None,
	Portal_Open,
	Sealed,
	Fell,
	Spiked,
	Time_Low,
}

View :: struct {
	lit:             gfx.Lighting,
	figures:         gfx.Paper_Figures,
	// The board's animated paper standees: the hero and the ghoul sentinels.
	book:            gfx.Flipbook_Assets,
	hero:            gfx.Flipbook_Player,
	ghouls:          [MAX_SENTINELS]gfx.Flipbook_Player,
	was_grounded:    bool,
	glow:            gfx.Lighting, // unlit but fogged, for emissive things
	terrain:         rl.Model,
	glow_model:      rl.Model,
	has_terrain:     bool,
	has_glow:        bool,
	generation:      u64,
	halo:            gfx.Sprite,
	gem_icon:        gfx.Sprite,
	life_icon:       gfx.Sprite,
	cam:             camera.Orbit_Camera,
	zoom:            f32,
	distance:        f32,
	ground_y:        f32,
	follow:          Vec3,
	swing_yaw:       f32,
	swing:           f32,
	sparks:          fx.Particles(SPARK_COUNT),
	dust:            fx.Particles(DUST_COUNT),
	popups:          fx.Popups(12),
	flash:           fx.Flash,
	rng:             rng.Rng,
	time:            f32,
	play_time:       f32,
	squash:          f32,
	squash_velocity: f32,
	yaw:             f32,
	step_phase:      f32,
	ember_timer:     f32,
	light_pos:       Vec3,
	light_color:     Vec3,
	light_level:     f32,
	message:         Message_Kind,
	message_value:   int,
	message_time:    f32,
	shake_scale:     f32,
}

voxel_palette :: proc() -> gfx.Voxel_Palette {
	p: gfx.Voxel_Palette
	p[u8(Material.Stone)] = {64, 87, 113, 255}
	p[u8(Material.Stone_Dark)] = {31, 47, 68, 255}
	p[u8(Material.Stone_Top)] = {107, 139, 167, 255}
	p[u8(Material.Moss)] = {60, 85, 106, 255}
	p[u8(Material.Plank)] = {105, 98, 87, 255}
	p[u8(Material.Crystal)] = {104, 150, 214, 255}
	p[u8(Material.Ember)] = {132, 193, 230, 255}
	p[u8(Material.Rune)] = {90, 156, 215, 255}
	return p
}

@(private = "file")
GEM_ROWS := [?]string{
	"....a....",
	"...aab...",
	"..aabbc..",
	".aabbbcc.",
	"aabbbbccd",
	".bbbbccd.",
	"..bbccd..",
	"...ccd...",
	"....d....",
}

@(private = "file")
LIFE_ROWS := [?]string{
	"...a...",
	"..aba..",
	".abcba.",
	".abcba.",
	"abcccba",
	"abcccba",
	".abcba.",
	"..ddd..",
}

view_init :: proc(v: ^View) {
	v.figures = gfx.paper_figures_create()
	gfx.create_flipbook_assets(&v.book)
	v.hero = gfx.flipbook_player(.Pilgrim)
	for &ghoul, index in v.ghouls { ghoul = gfx.flipbook_player(.Ghoul, f64(index)*0.37) }
	v.lit = gfx.lighting_create()
	v.lit.specular = 0.18
	v.lit.sun_dir = {-0.5, -1, -0.32}
	v.lit.sun_color = {0.76, 0.86, 1.0}
	v.lit.ambient = {0.29, 0.35, 0.44}
	v.lit.fog_color = FOG
	v.lit.fog_near = 18
	v.lit.fog_far = 78
	v.glow = gfx.lighting_create()
	v.glow.sun_color = {}
	v.glow.ambient = {1, 1, 1}
	v.glow.fog_color = FOG
	v.glow.fog_near = 22
	v.glow.fog_far = 95
	v.rng = rng.create(0x5EED)

	// Soft round halo for additive glows, built procedurally as rows.
	SIZE :: 32
	cells: [SIZE][SIZE]u8
	rows: [SIZE]string
	for y in 0..<SIZE {
		for x in 0..<SIZE {
			dx := (f32(x) + 0.5 - SIZE*0.5) / (SIZE * 0.5)
			dy := (f32(y) + 0.5 - SIZE*0.5) / (SIZE * 0.5)
			k := max(1-math.sqrt(dx*dx+dy*dy), 0)
			cells[y][x] = '0' + u8(min(k*k*9.99, 9))
		}
		rows[y] = string(cells[y][:])
	}
	halo_palette: gfx.Pixel_Palette
	for i in 1..=9 {
		a := f32(i) / 9
		gfx.palette_set(&halo_palette, u8('0'+i), rl.Color{255, 255, 255, u8(255 * a)})
	}
	frames := [1]gfx.Frame_Rows{rows[:]}
	v.halo, _ = gfx.sprite_create(frames[:], &halo_palette)

	gem: gfx.Pixel_Palette
	gfx.palette_set(&gem, 'a', {226, 248, 255, 255})
	gfx.palette_set(&gem, 'b', {140, 214, 255, 255})
	gfx.palette_set(&gem, 'c', {80, 140, 230, 255})
	gfx.palette_set(&gem, 'd', {44, 72, 150, 255})
	gem_frames := [1]gfx.Frame_Rows{GEM_ROWS[:]}
	v.gem_icon, _ = gfx.sprite_create(gem_frames[:], &gem)

	life: gfx.Pixel_Palette
	gfx.palette_set(&life, 'a', {178, 38, 52, 255})
	gfx.palette_set(&life, 'b', {236, 112, 60, 255})
	gfx.palette_set(&life, 'c', {255, 214, 130, 255})
	gfx.palette_set(&life, 'd', {92, 84, 72, 255})
	life_frames := [1]gfx.Frame_Rows{LIFE_ROWS[:]}
	v.life_icon, _ = gfx.sprite_create(life_frames[:], &life)
}

view_destroy :: proc(v: ^View) {
	unload_models(v)
	gfx.paper_figures_destroy(&v.figures)
	gfx.destroy_flipbook_assets(&v.book)
	gfx.lighting_destroy(&v.lit)
	gfx.lighting_destroy(&v.glow)
	gfx.sprite_destroy(&v.halo)
	gfx.sprite_destroy(&v.gem_icon)
	gfx.sprite_destroy(&v.life_icon)
}

@(private)
unload_models :: proc(v: ^View) {
	if v.has_terrain {
		gfx.unload_lit_model(&v.terrain)
		v.has_terrain = false
	}
	if v.has_glow {
		gfx.unload_lit_model(&v.glow_model)
		v.has_glow = false
	}
}

// Two meshes from one map: lit stone, and the emissive materials apart so
// they can skip the sun and glow through the dark.
@(private)
build_models :: proc(v: ^View, w: ^World) {
	unload_models(v)
	v.generation = w.generation
	if len(w.terrain.cells) == 0 {
		return
	}
	split := w.terrain
	split.cells = make([]u8, len(w.terrain.cells))
	defer delete(split.cells)
	palette := voxel_palette()
	for c, i in w.terrain.cells {
		split.cells[i] = 0 if material_glows(Material(c)) else c
	}
	v.terrain, v.has_terrain = gfx.build_voxel_model(&split, &palette)
	if v.has_terrain {
		gfx.lighting_apply_to_model(&v.lit, &v.terrain)
	}
	for c, i in w.terrain.cells {
		split.cells[i] = c if material_glows(Material(c)) else 0
	}
	v.glow_model, v.has_glow = gfx.build_voxel_model(&split, &palette)
	if v.has_glow {
		gfx.lighting_apply_to_model(&v.glow, &v.glow_model)
	}
}

view_reset :: proc(v: ^View, w: ^World) {
	if v.generation != w.generation || !v.has_terrain {
		build_models(v, w)
	}
	feet := physics.body3_feet(w.player.body)
	v.cam = camera.orbit_create(feet)
	v.cam.yaw = w.player.yaw
	v.cam.pitch = 0.36
	v.cam.height = 1.3
	v.cam.smoothing = 8
	v.cam.fov = 55
	v.zoom = 9.5
	v.distance = v.zoom
	v.cam.distance = v.zoom
	v.ground_y = feet.y
	v.follow = feet
	v.yaw = w.player.yaw
	v.swing = 0
	v.squash = 0
	v.squash_velocity = 0
	v.play_time = 0
	v.message = .None
	v.message_time = 0
	v.light_level = 0
	v.light_pos = feet
	v.flash = {}
	fx.clear(&v.sparks)
	fx.clear(&v.dust)
	v.popups.count = 0
}

view_camera_input :: proc(v: ^View, look, mouse: Vec2, zoom: f32, dt: f32) {
	v.cam.yaw += look.x * 2.4 * dt
	v.cam.pitch = clamp(v.cam.pitch+look.y*1.3*dt, PITCH_MIN, PITCH_MAX)
	v.cam.yaw -= mouse.x * 0.005
	v.cam.pitch = clamp(v.cam.pitch+mouse.y*0.005, PITCH_MIN, PITCH_MAX)
	v.zoom = clamp(v.zoom+zoom*0.8, ZOOM_MIN, ZOOM_MAX)
	if look.x != 0 || mouse.x != 0 {
		v.swing = 0 // the player took the camera back
	}
}

@(private)
wrap_angle :: proc "contextless" (a: f32) -> f32 {
	r := math.mod(a+math.PI, math.TAU)
	if r < 0 {
		r += math.TAU
	}
	return r - math.PI
}

@(private)
v3 :: proc "contextless" (v: Vec3) -> rl.Vector3 {
	return rl.Vector3{v.x, v.y, v.z}
}

@(private)
spark :: proc(v: ^View, position, velocity: Vec3, life, size: f32, from, to: rl.Color, gravity: f32 = 0, drag: f32 = 1) {
	fx.spawn(&v.sparks, fx.Particle{position = position, velocity = velocity, life = life, max_life = life,
		size_start = size, size_end = 0, color_start = from, color_end = to, gravity = gravity, drag = drag})
}

@(private)
burst :: proc(v: ^View, origin: Vec3, count: int, speed_lo, speed_hi: f32, life: f32, size: f32, from, to: rl.Color,
	gravity: f32 = 4, up_bias: f32 = 0) {
	for _ in 0..<count {
		d: Vec3
		for {
			d = Vec3{rng.float_signed(&v.rng), rng.float_signed(&v.rng), rng.float_signed(&v.rng)}
			l := physics.length3(d)
			if l > 0.05 && l <= 1 {
				d /= l
				break
			}
		}
		d.y += up_bias
		speed := rng.float_range(&v.rng, speed_lo, speed_hi)
		spark(v, origin, d*speed, life*rng.float_range(&v.rng, 0.6, 1.2), size, from, to, gravity, 1.5)
	}
}

@(private)
dust_ring :: proc(v: ^View, origin: Vec3, count: int, speed: f32) {
	for i in 0..<count {
		a := f32(i)/f32(count)*math.TAU + rng.float_signed(&v.rng)*0.3
		dir := Vec3{math.cos(a), rng.float_range(&v.rng, 0.15, 0.5), math.sin(a)}
		life := rng.float_range(&v.rng, 0.3, 0.55)
		fx.spawn(&v.dust, fx.Particle{position = origin + Vec3{0, 0.05, 0}, velocity = dir * speed * rng.float_range(&v.rng, 0.6, 1.2),
			life = life, max_life = life, size_start = rng.float_range(&v.rng, 0.12, 0.22), size_end = 0,
			color_start = {196, 186, 172, 255}, color_end = {150, 140, 130, 255}, gravity = 2, drag = 5})
	}
}

@(private)
say :: proc(v: ^View, kind: Message_Kind, value := 0, duration: f32 = 2.4) {
	v.message = kind
	v.message_value = value
	v.message_time = duration
}

// Reacts to one simulation step's events: sound, particles, shake, freeze.
view_events :: proc(v: ^View, w: ^World, frame: ^host.Frame, hit: ^fx.Hit_Stop) {
	a := frame.audio
	for i in 0..<w.event_count {
		e := w.events[i]
		switch e.kind {
		case .Jump:
			audio.play(a, .Jump, 0.7)
			dust_ring(v, e.position, 8, 2.2)
			v.squash_velocity += 5.5
		case .Air_Jump:
			audio.play(a, .Jump, 0.6, 1.35)
			for k in 0..<14 {
				ang := f32(k) / 14 * math.TAU
				spark(v, e.position+{0, 0.1, 0}, Vec3{math.cos(ang) * 3.2, -0.6, math.sin(ang) * 3.2}, 0.35, 0.12,
					{190, 240, 255, 255}, {60, 120, 255, 0})
			}
			v.squash_velocity += 4.5
		case .Dash:
			audio.play(a, .Dash, 0.8)
			camera.add_trauma(&v.cam.shake, 0.12)
		case .Land:
			strength := clamp(e.value/18, 0.2, 1)
			audio.play(a, .Land, 0.35+0.5*strength, 1.1-0.25*strength)
			dust_ring(v, e.position, 6+int(10*strength), 1.5+2*strength)
			v.squash_velocity -= 2 + e.value*0.35
			if e.value > 17 {
				camera.add_trauma(&v.cam.shake, 0.22)
			}
		case .Shard:
			audio.play(a, .Coin, 0.9, 1+0.04*e.value)
			burst(v, e.position, 36, 2, 6.5, 0.7, 0.14, {230, 250, 255, 255}, {70, 140, 255, 0}, 3)
			burst(v, e.position, 14, 0.5, 1.6, 1.2, 0.1, {160, 230, 255, 255}, {120, 90, 255, 0}, -1.5, 0.8)
			fx.flash_start(&v.flash, {140, 220, 255, 60}, 0.25)
			fx.hit_stop(hit, 0.045)
			cam := camera.orbit_to_raylib(v.cam)
			screen := rl.GetWorldToScreenEx(v3(e.position), cam, i32(frame.canvas.width), i32(frame.canvas.height))
			fx.popup(&v.popups, {screen.x, screen.y - 20}, "+150", GOLD, 1.0)
		case .Portal_Open:
			audio.play(a, .Power_Up, 0.9)
			say(v, .Portal_Open, 0, 3)
			fx.flash_start(&v.flash, {255, 190, 120, 70}, 0.5)
			camera.add_trauma(&v.cam.shake, 0.3)
			burst(v, e.position, 60, 2, 7, 1.2, 0.16, {255, 220, 150, 255}, {230, 40, 50, 0}, 1)
		case .Portal_Sealed:
			audio.play(a, .Back, 0.8)
			say(v, .Sealed, int(e.value))
		case .Knockback:
			audio.play(a, .Hit, 0.9)
			burst(v, e.position, 22, 2, 6, 0.4, 0.1, {255, 240, 220, 255}, {255, 80, 60, 0}, 6)
			camera.add_trauma(&v.cam.shake, 0.45)
			fx.hit_stop(hit, 0.07)
			fx.flash_start(&v.flash, {255, 255, 255, 40}, 0.12)
		case .Death:
			audio.play(a, .Hurt, 1)
			camera.add_trauma(&v.cam.shake, 0.55)
			fx.flash_start(&v.flash, {200, 30, 40, 110}, 0.6)
			fx.hit_stop(hit, 0.09)
			if Death_Kind(int(e.value)) == .Spikes {
				audio.play(a, .Explosion, 0.5, 1.4)
				burst(v, e.position, 40, 2, 7, 0.6, 0.14, {255, 120, 90, 255}, {120, 10, 30, 0}, 9)
				say(v, .Spiked, w.lives)
			} else {
				say(v, .Fell, w.lives)
			}
		case .Respawn:
			audio.play(a, .Power_Up, 0.5, 1.5)
			for k in 0..<26 {
				ang := f32(k) / 26 * math.TAU
				r := rng.float_range(&v.rng, 0.3, 0.6)
				spark(v, e.position+{math.cos(ang) * r, 0.1, math.sin(ang) * r}, {0, rng.float_range(&v.rng, 1.5, 4), 0},
					0.8, 0.12, {170, 235, 255, 255}, {80, 120, 255, 0})
			}
			v.swing_yaw = e.value
			v.swing = 0.8
			v.message_time = min(v.message_time, 0.4)
		case .Crumble_Shake:
			audio.play(a, .Step, 0.8, 0.6)
			for _ in 0..<8 {
				fx.spawn(&v.dust, fx.Particle{position = e.position + {rng.float_signed(&v.rng), -0.5, rng.float_signed(&v.rng)},
					velocity = {0, -0.6, 0}, life = 0.6, max_life = 0.6, size_start = 0.1, size_end = 0,
					color_start = {170, 146, 120, 255}, color_end = {120, 100, 80, 255}, gravity = 6})
			}
		case .Crumble_Fall:
			audio.play(a, .Push, 0.8, 0.7)
			for _ in 0..<14 {
				fx.spawn(&v.dust, fx.Particle{position = e.position + {rng.float_signed(&v.rng), rng.float_signed(&v.rng) * 0.4, rng.float_signed(&v.rng)},
					velocity = {rng.float_signed(&v.rng) * 1.5, rng.float_range(&v.rng, -1, 1.5), rng.float_signed(&v.rng) * 1.5},
					life = 1.2, max_life = 1.2, size_start = rng.float_range(&v.rng, 0.15, 0.3), size_end = 0.05,
					color_start = {150, 124, 98, 255}, color_end = {110, 90, 72, 255}, gravity = 18, drag = 0.5})
			}
		case .Time_Low:
			audio.play(a, .Blip, 1, 0.7)
			say(v, .Time_Low)
		case .Win:
			burst(v, e.position, 80, 2, 8, 1.4, 0.16, {255, 230, 170, 255}, {200, 40, 60, 0}, 1, 0.5)
			fx.flash_start(&v.flash, {255, 230, 200, 120}, 0.7)
		case .Lose:
		}
	}
}

// Real-time presentation: camera, player animation, ambience.
view_update :: proc(v: ^View, w: ^World, frame: ^host.Frame, dt: f32) {
	v.time += dt
	v.shake_scale = frame.profile.settings.screen_shake if frame.profile != nil else 1
	v.message_time = max(v.message_time-dt, 0)
	if w.status == .Playing && w.phase != .Finished {
		v.play_time += dt
	}
	p := w.player
	feet := physics.body3_feet(p.body)
	if w.phase != .Dying {
		// Height follows the ground stood on, so jumps do not bob the view.
		if p.grounded || feet.y < v.ground_y {
			v.ground_y = feet.y
		} else if feet.y > v.ground_y+2.5 {
			v.ground_y = feet.y - 2.5
		}
		v.follow = Vec3{feet.x, v.ground_y, feet.z}
	}
	if v.swing > 0 {
		v.swing -= dt
		v.cam.yaw += wrap_angle(v.swing_yaw-v.cam.yaw) * (1 - math.exp(-5*dt))
	}
	camera.orbit_update(&v.cam, v.follow, dt)
	// Pull the camera in front of rock that would hide the player.
	v.cam.distance = v.zoom
	look := v.cam.focus + Vec3{0, v.cam.height, 0}
	eye := camera.orbit_eye(v.cam)
	limit := v.zoom
	if hit := physics.raycast_voxels(&w.terrain, look, eye-look, v.zoom); hit.hit {
		limit = max(2.2, hit.distance-0.4)
	}
	if limit < v.distance {
		v.distance = limit
	} else {
		v.distance = tween.damp(v.distance, limit, 3, dt)
	}
	v.cam.distance = v.distance
	v.cam.shake.max_offset = 0.24 * v.shake_scale

	// Squash and stretch on a damped spring, plus a stretch with vertical speed.
	v.squash_velocity += (-170*v.squash - 15*v.squash_velocity) * dt
	v.squash = clamp(v.squash+v.squash_velocity*dt, -0.42, 0.45)
	v.yaw += wrap_angle(p.yaw-v.yaw) * (1 - math.exp(-16*dt))

	speed := physics.length2(Vec2{p.body.velocity.x, p.body.velocity.z})
	if w.phase == .Alive && p.grounded && speed > 1.5 && w.status == .Playing {
		v.step_phase += speed * dt
		if v.step_phase > 1.8 {
			v.step_phase = 0
			audio.play(frame.audio, .Step, 0.35, rng.float_range(&v.rng, 0.85, 1.15))
			dust_ring(v, feet, 3, 0.8)
		}
	}
	if p.dash_remaining > 0 && w.phase == .Alive {
		center := physics.body3_center(p.body)
		for _ in 0..<2 {
			spark(v, center+{rng.float_signed(&v.rng) * 0.25, rng.float_signed(&v.rng) * 0.5, rng.float_signed(&v.rng) * 0.25},
				{0, 0.3, 0}, 0.28, 0.32, {230, 60, 70, 150}, {120, 20, 60, 0})
		}
	}
	update_ambience(v, w, dt)
	update_light(v, w, dt)
	fx.update(&v.sparks, dt, true)
	fx.update(&v.dust, dt, true)
	fx.popups_update(&v.popups, dt)
	fx.flash_update(&v.flash, dt)
}

@(private)
update_ambience :: proc(v: ^View, w: ^World, dt: f32) {
	// Embers drifting up out of the abyss around the camera.
	v.ember_timer += dt
	for v.ember_timer > 0.05 {
		v.ember_timer -= 0.05
		c := v.cam.focus
		pos := c + Vec3{rng.float_signed(&v.rng) * 22, -rng.float_range(&v.rng, 4, 14), rng.float_signed(&v.rng) * 22}
		life := rng.float_range(&v.rng, 4, 7)
		fx.spawn(&v.sparks, fx.Particle{position = pos, velocity = {rng.float_signed(&v.rng) * 0.3, rng.float_range(&v.rng, 1, 2.2), rng.float_signed(&v.rng) * 0.3},
			life = life, max_life = life, size_start = rng.float_range(&v.rng, 0.05, 0.1), size_end = 0,
			color_start = {255, 150, 70, 220}, color_end = {200, 40, 40, 0}, gravity = -0.1, drag = 0.1})
	}
	for i in 0..<w.brazier_count {
		b := w.braziers[i]
		if physics.length3(b-v.cam.focus) > 45 || !rng.chance(&v.rng, dt*22) {
			continue
		}
		spark(v, b+{rng.float_signed(&v.rng) * 0.16, 1.0, rng.float_signed(&v.rng) * 0.16},
			{rng.float_signed(&v.rng) * 0.3, rng.float_range(&v.rng, 1, 2.2), rng.float_signed(&v.rng) * 0.3},
			rng.float_range(&v.rng, 0.4, 0.7), 0.16, {255, 214, 120, 255}, {220, 50, 30, 0}, -1, 1)
	}
	for i in 0..<w.shard_count {
		s := w.shards[i]
		if s.taken || physics.length3(s.position-v.cam.focus) > 32 || !rng.chance(&v.rng, dt*7) {
			continue
		}
		spark(v, s.position+{rng.float_signed(&v.rng) * 0.4, -0.3, rng.float_signed(&v.rng) * 0.4}, {0, 0.7, 0}, 1.2, 0.07,
			{180, 240, 255, 255}, {80, 120, 255, 0}, -0.2, 0.5)
	}
	if w.portal_open && rng.chance(&v.rng, dt*40) {
		// Motes spiralling into the open portal.
		ang := rng.float01(&v.rng) * math.TAU
		r := f32(1.6)
		offset := Vec3{0, math.sin(ang) * r * 1.4, 0}
		tangent: Vec3
		if w.portal_axis == 0 {
			offset.z = math.cos(ang) * r
			tangent = Vec3{0, math.cos(ang), -math.sin(ang)}
		} else {
			offset.x = math.cos(ang) * r
			tangent = Vec3{-math.sin(ang), math.cos(ang), 0}
		}
		spark(v, w.portal_center+offset, -offset*0.9+tangent*1.5, 1.0, 0.1, {255, 210, 140, 255}, {220, 40, 60, 0}, 0, 0.3)
	}
}

// The one point light follows the nearest shard, or the open portal.
@(private)
update_light :: proc(v: ^View, w: ^World, dt: f32) {
	center := physics.body3_center(w.player.body)
	best := f32(16)
	target := v.light_pos
	color := Vec3{0.45, 0.8, 1.3}
	found := false
	for i in 0..<w.shard_count {
		s := w.shards[i]
		if s.taken {
			continue
		}
		if d := physics.length3(s.position-center); d < best {
			best = d
			target = s.position
			found = true
		}
	}
	radius := f32(9)
	if w.portal_open && physics.length3(w.portal_center-center) < max(best, 24) {
		target = w.portal_center
		color = Vec3{1.5, 0.55, 0.35}
		radius = 13
		found = true
	}
	k := 1 - math.exp(-5*dt)
	v.light_pos += (target - v.light_pos) * k
	v.light_color += (color - v.light_color) * k
	v.light_level += ((f32(1) if found else 0) - v.light_level) * k
	pulse := 0.85 + 0.15*math.sin(v.time*3)
	v.lit.point_pos = v.light_pos
	v.lit.point_color = v.light_color * v.light_level * pulse
	v.lit.point_radius = radius
}

view_draw :: proc(v: ^View, w: ^World, frame: ^host.Frame) {
	width := frame.canvas.width
	height := frame.canvas.height
	cam := camera.orbit_to_raylib(v.cam)
	draw_sky(v, width, height)

	rl.BeginMode3D(cam)
	eye := Vec3{cam.position.x, cam.position.y, cam.position.z}
	gfx.lighting_update(&v.lit, eye)
	gfx.lighting_update(&v.glow, eye)
	if v.has_terrain {
		rl.DrawModel(v.terrain, {}, 1, rl.WHITE)
	}
	gfx.lighting_begin(&v.lit)
	draw_far_spires(w)
	draw_diorama_caps(v, w)
	draw_movers(v, w)
	draw_spike_plates(w)
	draw_bridge_posts(w)
	draw_braziers(w, false)
	fx.draw3d(&v.dust)
	gfx.lighting_end(&v.lit)

	if v.has_glow {
		rl.DrawModel(v.glow_model, {}, 1, rl.WHITE)
	}
	gfx.lighting_begin(&v.glow)
	draw_mover_glow(v, w)
	draw_spikes(v, w)
	draw_shards(v, w)
	draw_bridge_ropes(w)
	draw_braziers(w, true)
	gfx.lighting_end(&v.glow)
	draw_portal_surface(v, w)
	draw_shadows(v, w)
	draw_paper_actors(v, w, cam)

	// Additive pass without depth writes, so glows never clip each other.
	rlgl.DrawRenderBatchActive()
	rlgl.DisableDepthMask()
	rl.BeginBlendMode(.ADDITIVE)
	draw_halos(v, w, cam)
	fx.draw3d(&v.sparks)
	rl.EndBlendMode()
	rlgl.DrawRenderBatchActive()
	rlgl.EnableDepthMask()
	rl.EndMode3D()

	gfx.draw_vignette(width, height, 0.55)
	fx.flash_draw(v.flash, width, height)
	draw_hud(v, w, frame, cam)
}

// Paper and illustration share a plane. They test the solid world's depth,
// but cannot write it: the independent border pose must not hide its own art.
// Without depth writes the actors must be composited from farthest to nearest.
@(private)
draw_paper_actors :: proc(v: ^View, w: ^World, cam: rl.Camera3D) {
	Actor :: struct { index: int, distance: f32 }
	actors: [MAX_SENTINELS+1]Actor
	eye := Vec3(cam.position)
	actors[0] = {index = -1, distance = physics.length3(physics.body3_center(w.player.body)-eye)}
	for i in 0..<w.sentinel_count {
		actors[i+1] = {index = i, distance = physics.length3(w.sentinels[i].position-eye)}
	}
	count := w.sentinel_count+1
	for i in 1..<count {
		actor := actors[i]
		j := i-1
		for j>=0 && actors[j].distance<actor.distance {
			actors[j+1] = actors[j]
			j -= 1
		}
		actors[j+1] = actor
	}
	rlgl.DrawRenderBatchActive()
	rlgl.DisableDepthMask()
	gfx.lighting_begin_unlit(&v.lit)
	defer {
		gfx.lighting_end(&v.lit)
		rlgl.DrawRenderBatchActive()
		rlgl.EnableDepthMask()
	}
	for actor in actors[:count] {
		if actor.index<0 { draw_player(v, w) }
		else { draw_sentinel(v, w, w.sentinels[actor.index], actor.index) }
	}
}

// Where the horizon sits on screen for the current pitch.
@(private)
horizon_y :: proc(v: ^View, height: f32) -> f32 {
	half := math.tan(v.cam.fov * 0.5 * math.RAD_PER_DEG)
	return height*0.5 - math.tan(v.cam.pitch)/half*height*0.5
}

// Screen x of a world bearing (yaw), or false when it is out of view.
@(private)
bearing_x :: proc(v: ^View, bearing, width, height: f32) -> (f32, bool) {
	half_h := math.atan(math.tan(v.cam.fov*0.5*math.RAD_PER_DEG) * width / height)
	a := wrap_angle(bearing - v.cam.yaw)
	if abs(a) > half_h+0.35 {
		return 0, false
	}
	return width*0.5 - math.tan(a)/math.tan(half_h)*width*0.5, true
}

@(private)
draw_sky :: proc(v: ^View, width, height: f32) {
	h := clamp(horizon_y(v, height), -60, height)
	if h > 0 {
		gfx.draw_vertical_gradient({0, 0, width, h}, SKY_TOP, SKY_HORIZON)
	}
	mid := h + (height-h)*0.45
	gfx.draw_vertical_gradient({0, h, width, mid - h + 1}, SKY_HORIZON, ABYSS_MID)
	gfx.draw_vertical_gradient({0, mid, width, height - mid}, ABYSS_MID, ABYSS_DEEP)
	if h > 12 {
		gfx.draw_stars(width, h-10, 70, v.time, -v.cam.yaw*12800)
	}
	// A pale moon low over the spires.
	if x, ok := bearing_x(v, 0.7, width, height); ok {
		y := max(h-46, 34)
		gfx.draw_glow({x, y}, 64, {200, 180, 230, 90})
		rl.DrawCircleV({x, y}, 26, {232, 226, 240, 255})
		rl.DrawCircleV({x - 7, y - 5}, 6, {206, 200, 220, 255})
		rl.DrawCircleV({x + 9, y + 7}, 4, {206, 200, 220, 255})
	}
	// Two layers of distant spire silhouettes around the horizon.
	for layer in 0..<2 {
		color := rl.Color{29, 47, 68, 255} if layer == 0 else rl.Color{14, 27, 43, 255}
		count := 30
		for i in 0..<count {
			seed := f32(i*7 + layer*131)
			bearing := f32(i)/f32(count)*math.TAU + math.sin(seed*1.7)*0.08 + f32(layer)*0.11
			x, ok := bearing_x(v, bearing, width, height)
			if !ok {
				continue
			}
			tall := (40 + 70*abs(math.sin(seed*2.3))) * (1.25 if layer == 1 else 0.8)
			half := 6 + 6*abs(math.sin(seed*3.1))
			base := h + 28 + f32(layer)*14
			top := h - tall
			rl.DrawRectangleRec({x - half, top + half*2, half * 2, base - top - half*2}, color)
			rl.DrawTriangle({x, top - half}, {x - half, top + half*2 + 1}, {x + half, top + half*2 + 1}, color)
			// A floating chunk beside some of them.
			if math.sin(seed*5.3) > 0.4 {
				fy := top + tall*0.3 + math.sin(v.time*0.5+seed)*3
				rl.DrawRectangleRec({x + half + 6, fy, half * 1.2, half * 0.8}, color)
			}
		}
	}
}

@(private)
draw_far_spires :: proc(w: ^World) {
	for i in 0..<w.far_count {
		s := w.far[i]
		h := s.height
		base := s.position
		rl.DrawCubeV(v3(base+{0, h * 0.3, 0}), {s.width, h * 0.6, s.width}, {43, 64, 88, 255})
		rl.DrawCubeV(v3(base+{0, h * 0.72, 0}), {s.width * 0.7, h * 0.26, s.width * 0.7}, {56, 80, 107, 255})
		rl.DrawCubeV(v3(base+{0, h * 0.92, 0}), {s.width * 0.4, h * 0.16, s.width * 0.4}, {84, 111, 139, 255})
		rl.DrawCubeV(v3(base+{s.width * 0.9, h * 0.62, 0}), {s.width * 0.6, s.width * 0.5, s.width * 0.6}, {32, 51, 73, 255})
	}
}

// Static collision voxels remain the source of truth. Only exposed tops get
// a thin layered cap; draw distance bounds the added geometry on large levels.
@(private)
draw_diorama_caps :: proc(v: ^View, w: ^World) {
	for p in w.pads[:w.pad_count] {
		if p.kind == .Shuttle || p.kind == .Crumble { continue }
		center := Vec3{f32(p.lo.x+p.hi.x)*0.5, f32(p.top), f32(p.lo.y+p.hi.y)*0.5}
		if physics.length3(center-v.follow)>38 { continue }
		sx, sz := f32(p.hi.x-p.lo.x), f32(p.hi.y-p.lo.y)
		// Thin silver-blue lip: side faces catch light, recessed grout stays dark.
		rl.DrawCubeV(v3(center-{0, 0.07, 0}), {sx+0.05, 0.085, sz+0.05}, {72, 103, 137, 255})
		for z in p.lo.y..<p.hi.y { for x in p.lo.x..<p.hi.x {
			// Decorative pillar bases or solid towers must not be capped above.
			if physics.voxel_get(&w.terrain,x,p.top,z) != 0 { continue }
			if material_glows(Material(physics.voxel_get(&w.terrain,x,p.top-1,z))) { continue }
			pos := Vec3{f32(x)+0.5, f32(p.top)+0.008, f32(z)+0.5}
			shade := u8((x*17+z*13)%9)
			rl.DrawCubeV(v3(pos), {0.955, 0.025, 0.955}, {u8(97+shade), u8(125+shade), u8(153+shade), 255})
			rl.DrawCubeV(v3(pos+{0, 0.017, -0.452}), {0.88, 0.012, 0.025}, {162, 186, 206, 255})
		} }
		// Carved recess and stone pilaster on the front of every island.
		if sz>=2 && p.depth>=2 {
			rl.DrawCubeV(v3(center+{0, -0.68, sz*0.5+0.008}), {0.46, 0.86, 0.035}, {9, 19, 32, 255})
			rl.DrawCubeV(v3(center+{-0.31, -0.72, sz*0.5+0.035}), {0.1, 1.04, 0.1}, {69, 93, 119, 255})
			rl.DrawCubeV(v3(center+{0.31, -0.72, sz*0.5+0.035}), {0.1, 1.04, 0.1}, {69, 93, 119, 255})
			rl.DrawCubeV(v3(center+{0, -0.25, sz*0.5+0.04}), {0.72, 0.11, 0.12}, {111, 142, 171, 255})
		}
	}
}

@(private)
draw_movers :: proc(v: ^View, w: ^World) {
	for i in 0..<w.mover_count {
		m := w.movers[i]
		if m.kind == .Crumble && m.state == .Gone {
			continue
		}
		c := m.position + m.size*0.5
		switch m.kind {
		case .Shuttle:
			rl.DrawCubeV(v3(c), v3(m.size), {62, 88, 117, 255})
			rl.DrawCubeV(v3(c+{0, 0.455, 0}), v3(Vec3{m.size.x + 0.04, 0.1, m.size.z + 0.04}), {151, 182, 208, 255})
		case .Crumble:
			offset: Vec3
			if m.state == .Shaking {
				offset = Vec3{math.sin(v.time*71) * 0.05, 0, math.cos(v.time*83) * 0.05}
			}
			rlgl.PushMatrix()
			rlgl.Translatef(c.x+offset.x, c.y, c.z+offset.z)
			if m.state == .Falling {
				rlgl.Rotatef(m.fall_speed*2.5, 1, 0, 0.6)
			}
			rl.DrawCubeV({}, v3(m.size), {156, 128, 100, 255})
			rl.DrawCubeV({0, 0.5, 0}, {m.size.x * 0.9, 0.02, 0.07}, {84, 66, 52, 255})
			rl.DrawCubeV({0.2, 0.5, 0}, {0.07, 0.02, m.size.z * 0.8}, {84, 66, 52, 255})
			rlgl.PopMatrix()
		}
	}
}

@(private)
draw_mover_glow :: proc(v: ^View, w: ^World) {
	for i in 0..<w.mover_count {
		m := w.movers[i]
		if m.kind != .Shuttle {
			continue
		}
		c := m.position + m.size*0.5
		pulse := u8(200 + 55*math.sin(v.time*3+f32(i)))
		rune := rl.Color{110, 200, 255, pulse}
		y := c.y - 0.5
		rl.DrawCubeV(v3(Vec3{c.x, y, m.position.z}), {m.size.x, 0.08, 0.08}, rune)
		rl.DrawCubeV(v3(Vec3{c.x, y, m.position.z + m.size.z}), {m.size.x, 0.08, 0.08}, rune)
		rl.DrawCubeV(v3(Vec3{m.position.x, y, c.z}), {0.08, 0.08, m.size.z}, rune)
		rl.DrawCubeV(v3(Vec3{m.position.x + m.size.x, y, c.z}), {0.08, 0.08, m.size.z}, rune)
		rlgl.PushMatrix()
		rlgl.Translatef(c.x, y-0.55+math.sin(v.time*2+f32(i))*0.08, c.z)
		rlgl.Rotatef(v.time*70, 0, 1, 0)
		rl.DrawCylinder({0, 0, 0}, 0, 0.22, 0.32, 4, {170, 230, 255, 255})
		rl.DrawCylinder({0, -0.32, 0}, 0.22, 0, 0.32, 4, {80, 140, 230, 255})
		rlgl.PopMatrix()
	}
}

@(private)
draw_spike_plates :: proc(w: ^World) {
	for i in 0..<w.spike_count {
		s := w.spikes[i]
		c := (s.lo + s.hi) * 0.5
		size := s.hi - s.lo
		rl.DrawCubeV({c.x, s.top + 0.03, c.y}, {size.x - 0.06, 0.06, size.y - 0.06}, {58, 54, 66, 255})
	}
}

@(private)
draw_spikes :: proc(v: ^View, w: ^World) {
	for i in 0..<w.spike_count {
		s := w.spikes[i]
		ext := spike_extension(s, w.time)
		warn := spike_warning(s, w.time)
		rattle := warn * 0.05 * (0.5 + 0.5*math.sin(v.time*55))
		h := 0.07 + 0.66*ext + rattle
		tip := ui.mix_color({120, 110, 130, 255}, {255, 80, 60, 255}, max(ext, warn))
		for z := s.lo.y + 0.25; z < s.hi.y; z += 0.5 {
			for x := s.lo.x + 0.25; x < s.hi.x; x += 0.5 {
				base := rl.Vector3{x, s.top + 0.06, z}
				rl.DrawCylinder(base, 0, 0.13, h, 4, {96, 92, 108, 255})
				rl.DrawCylinder(base+{0, h * 0.55, 0}, 0, 0.13*0.45, h*0.45, 4, tip)
			}
		}
		if warn > 0 || ext > 0 {
			c := (s.lo + s.hi) * 0.5
			size := s.hi - s.lo
			glow := ui.with_alpha({255, 110, 60, 255}, max(warn, ext)*0.8)
			rl.DrawCubeV({c.x, s.top + 0.065, s.lo.y + 0.03}, {size.x, 0.02, 0.06}, glow)
			rl.DrawCubeV({c.x, s.top + 0.065, s.hi.y - 0.03}, {size.x, 0.02, 0.06}, glow)
			rl.DrawCubeV({s.lo.x + 0.03, s.top + 0.065, c.y}, {0.06, 0.02, size.y}, glow)
			rl.DrawCubeV({s.hi.x - 0.03, s.top + 0.065, c.y}, {0.06, 0.02, size.y}, glow)
		}
	}
}

@(private)
sentinel_yaw :: proc(s: Sentinel, time: f32) -> f32 {
	ahead := sentinel_position(s, time+0.08) - s.position
	if physics.length3(ahead) < 0.001 {
		d := s.b - s.a
		return math.atan2(d.x, d.z)
	}
	return math.atan2(ahead.x, ahead.z)
}

@(private)
draw_sentinel :: proc(v: ^View, w: ^World, s: Sentinel, index: int = 0) {
	pose := math.floor(v.time*5)/5
	feet := s.position + Vec3{0, -0.66+math.sin(pose*3+s.phase*5)*0.075, 0}
	flip := math.sin(sentinel_yaw(s,w.time)-v.cam.yaw)<0
	if v.book.loaded && index >= 0 && index < len(v.ghouls) {
		// A patrolling ghoul standee, striding on its own clock.
		ghoul := &v.ghouls[index]
		gfx.flipbook_loop(ghoul, .Walk, f64(v.time))
		gfx.draw_flipbook_billboard(&v.book, camera.orbit_to_raylib(v.cam), ghoul, s.position+Vec3{0, -0.62, 0}, 1.3,
			!flip, rl.WHITE, f64(v.time))
	} else {
		gfx.paper_figure_billboard(&v.figures, camera.orbit_to_raylib(v.cam), 1, feet, 1.5, flip, time = v.time+s.phase)
	}
	rl.DrawCircle3D(v3(s.position-{0, 0.72, 0}), 0.55, {1, 0, 0}, 90, {220, 60, 60, 200})
}

@(private)
draw_shards :: proc(v: ^View, w: ^World) {
	for i in 0..<w.shard_count {
		s := w.shards[i]
		if s.taken {
			continue
		}
		pos := shard_draw_position(v, s, i)
		rlgl.PushMatrix()
		rlgl.Translatef(pos.x, pos.y, pos.z)
		rlgl.Rotatef(v.time*90+f32(i)*40, 0, 1, 0)
		rl.DrawCylinder({0, 0, 0}, 0, 0.3, 0.44, 4, {210, 246, 255, 255})
		rl.DrawCylinder({0, -0.44, 0}, 0.3, 0, 0.44, 4, {88, 150, 236, 255})
		rlgl.PopMatrix()
		for k in 0..<2 {
			a := v.time*2.4 + f32(k)*math.PI + f32(i)
			rl.DrawCubeV(v3(pos+{math.cos(a) * 0.55, math.sin(a*1.3) * 0.2, math.sin(a) * 0.55}), {0.06, 0.06, 0.06}, {220, 250, 255, 255})
		}
	}
}

@(private)
shard_draw_position :: proc(v: ^View, s: Shard, i: int) -> Vec3 {
	return s.position + {0, math.sin(v.time*2+f32(i)) * 0.12, 0}
}

// Hooded wanderer: ivory mask, crimson hood and cape, slate cloak.
@(private)
draw_player :: proc(v: ^View, w: ^World) {
	if !player_visible(v, w) { return }
	feet := physics.body3_feet(w.player.body)
	cam := camera.orbit_to_raylib(v.cam)
	// Same acolyte as the run; four held poses suggest a paper miniature.
	speed := physics.length2(Vec2{w.player.body.velocity.x, w.player.body.velocity.z})
	pose := math.floor(w.stride*3)/3
	feet.y += abs(math.sin(pose))*0.04*min(speed/w.params.max_speed, 1)
	height := 1.58 * clamp(1+v.squash*0.25, 0.9, 1.12)
	flip := math.sin(v.yaw-v.cam.yaw)<0
	if v.book.loaded {
		// The same Viandante standee as the run: it strides while running,
		// leaps on take-off and falls when the climb ends.
		now := f64(v.time)
		hero := &v.hero
		gfx.flipbook_loop(hero, .Walk if w.player.grounded && speed > 0.4 else .Idle, now)
		if !w.player.grounded && v.was_grounded { gfx.flipbook_play(hero, .Dodge, now) }
		if w.phase == .Dying { gfx.flipbook_play(hero, .Death, now) }
		else if hero.action == .Death { hero^ = gfx.flipbook_player(.Pilgrim) }
		v.was_grounded = w.player.grounded
		gfx.draw_flipbook_billboard(&v.book, cam, hero, feet, height*0.92, !flip, rl.WHITE, now)
		return
	}
	gfx.paper_figure_billboard(&v.figures, cam, 0, feet, height, flip, time = v.time)
}

@(private)
player_visible :: proc(v: ^View, w: ^World) -> bool {
	if w.phase == .Dying && w.death_kind == .Spikes {
		return false
	}
	if w.status == .Won {
		return false
	}
	// Blink while the respawn grace lasts.
	return w.invulnerable <= 0 || int(w.invulnerable*14)%2 == 0
}

@(private)
chest_position :: proc(v: ^View, w: ^World) -> Vec3 {
	feet := physics.body3_feet(w.player.body)
	s := 1 + v.squash
	return feet + Vec3{math.sin(v.yaw) * 0.19, 0.72 * s, math.cos(v.yaw) * 0.19}
}

@(private)
draw_bridge_ropes :: proc(w: ^World) {
	for i in 0..<w.bridge_count {
		b := w.bridges[i]
		lat := 1 - b.axis
		for side in 0..<2 {
			l := f32(b.lo[lat]) - 0.12 if side == 0 else f32(b.hi[lat]) + 0.12
			a0 := f32(b.lo[b.axis]) - 0.2
			a1 := f32(b.hi[b.axis]) + 0.2
			prev: Vec3
			for k in 0..=12 {
				t := f32(k) / 12
				p: [2]f32
				p[b.axis] = a0 + (a1-a0)*t
				p[lat] = l
				pt := Vec3{p[0], f32(b.y) + 1.9 - 0.45*math.sin(t*math.PI), p[1]}
				if k > 0 {
					rl.DrawLine3D(v3(prev), v3(pt), {150, 116, 80, 255})
				}
				prev = pt
			}
		}
	}
}

@(private)
draw_bridge_posts :: proc(w: ^World) {
	for i in 0..<w.bridge_count {
		b := w.bridges[i]
		lat := 1 - b.axis
		for end in 0..<2 {
			for side in 0..<2 {
				p: [2]f32
				p[b.axis] = f32(b.lo[b.axis]) - 0.2 if end == 0 else f32(b.hi[b.axis]) + 0.2
				p[lat] = f32(b.lo[lat]) - 0.12 if side == 0 else f32(b.hi[lat]) + 0.12
				rl.DrawCubeV({p[0], f32(b.y) + 1.55, p[1]}, {0.14, 1.1, 0.14}, {96, 72, 54, 255})
			}
		}
	}
}

// Filled ellipse in the arch; dark and still while sealed, a churning glow
// once enough shards are found.
@(private)
draw_portal_surface :: proc(v: ^View, w: ^World) {
	c := w.portal_center
	open := w.portal_open
	rings := 5
	for ring in 0..<rings {
		k := 1 - f32(ring)/f32(rings)
		r := 1.3 * k
		color: rl.Color
		if open {
			color = ui.mix_color({120, 20, 40, 230}, {255, 200, 120, 255}, 1-k)
		} else {
			color = ui.mix_color({24, 14, 34, 235}, {70, 40, 110, 235}, (1-k)*(0.6+0.4*math.sin(v.time*1.5)))
		}
		spin := v.time * (1.6 if open else 0.3) * (1 + f32(ring)*0.3)
		ellipse(c, w.portal_axis, r, r*1.55, spin, 0.01*f32(ring), color)
	}
}

@(private)
ellipse :: proc(c: Vec3, axis: int, rx, ry, spin, offset: f32, color: rl.Color) {
	SEGMENTS :: 28
	normal := Vec3{1, 0, 0} if axis == 0 else Vec3{0, 0, 1}
	side := Vec3{0, 0, 1} if axis == 0 else Vec3{1, 0, 0}
	rlgl.Begin(rlgl.TRIANGLES)
	rlgl.Color4ub(color.r, color.g, color.b, color.a)
	for i in 0..<SEGMENTS {
		a0 := f32(i)/SEGMENTS*math.TAU + spin
		a1 := f32(i+1)/SEGMENTS*math.TAU + spin
		wobble0 := 1 + 0.04*math.sin(a0*5)
		wobble1 := 1 + 0.04*math.sin(a1*5)
		p0 := c + side*(math.cos(a0)*rx*wobble0) + Vec3{0, math.sin(a0) * ry * wobble0, 0}
		p1 := c + side*(math.cos(a1)*rx*wobble1) + Vec3{0, math.sin(a1) * ry * wobble1, 0}
		for face in 0..<2 {
			n := normal * (offset if face == 0 else -offset)
			q0 := p0 + n
			q1 := p1 + n
			m := c + n
			if face == 0 {
				rlgl.Vertex3f(m.x, m.y, m.z)
				rlgl.Vertex3f(q0.x, q0.y, q0.z)
				rlgl.Vertex3f(q1.x, q1.y, q1.z)
			} else {
				rlgl.Vertex3f(m.x, m.y, m.z)
				rlgl.Vertex3f(q1.x, q1.y, q1.z)
				rlgl.Vertex3f(q0.x, q0.y, q0.z)
			}
		}
	}
	rlgl.End()
}

// Ground height under a point (voxels and solid movers), and whether found.
@(private)
ground_under :: proc(w: ^World, p: Vec3, depth: f32) -> (f32, bool) {
	best := f32(-1e9)
	found := false
	if hit := physics.raycast_voxels(&w.terrain, p+{0, 0.05, 0}, {0, -1, 0}, depth); hit.hit {
		best = hit.point.y
		found = true
	}
	for i in 0..<w.mover_count {
		m := w.movers[i]
		if !mover_solid(m) {
			continue
		}
		top := m.position.y + m.size.y
		if top <= p.y+0.06 && top > best && p.x > m.position.x && p.x < m.position.x+m.size.x &&
		   p.z > m.position.z && p.z < m.position.z+m.size.z {
			best = top
			found = true
		}
	}
	return best, found
}

@(private)
draw_shadows :: proc(v: ^View, w: ^World) {
	if player_visible(v, w) && w.phase == .Alive {
		feet := physics.body3_feet(w.player.body)
		if y, ok := ground_under(w, feet, 30); ok {
			h := feet.y - y
			gfx.draw_blob_shadow({feet.x, y, feet.z}, 0.38*(1-min(h/10, 0.55)), 0.55*(1-min(h/12, 0.6)))
		}
	}
	for i in 0..<w.sentinel_count {
		s := w.sentinels[i]
		gfx.draw_blob_shadow({s.position.x, f32(w.pads[s.pad].top), s.position.z}, 0.42, 0.35)
	}
	for i in 0..<w.shard_count {
		s := w.shards[i]
		if !s.taken {
			gfx.draw_blob_shadow({s.position.x, f32(w.pads[s.pad].top), s.position.z}, 0.22, 0.25)
		}
	}
}

@(private)
draw_halos :: proc(v: ^View, w: ^World, cam: rl.Camera3D) {
	tex := v.halo.texture
	if tex.id == 0 {
		return
	}
	for i in 0..<w.shard_count {
		s := w.shards[i]
		if s.taken {
			continue
		}
		pos := shard_draw_position(v, s, i)
		pulse := 0.85 + 0.15*math.sin(v.time*3+f32(i))
		rl.DrawBillboard(cam, tex, v3(pos), 2.2*pulse, {70, 150, 255, 150})
		rl.DrawBillboard(cam, tex, v3(pos), 0.9, {200, 240, 255, 200})
	}
	for i in 0..<w.brazier_count {
		b := w.braziers[i]
		flicker := 0.9 + 0.1*math.sin(v.time*13+f32(i)*2)
		rl.DrawBillboard(cam, tex, v3(b+{0, 1.15, 0}), 1.7*flicker, {255, 120, 40, 150})
	}
	// Nudged toward the eye so the halo never sinks into the portal disc.
	eye := Vec3{cam.position.x, cam.position.y, cam.position.z}
	c := w.portal_center + physics.normalize3(eye-w.portal_center)*0.5
	if w.portal_open {
		rl.DrawBillboard(cam, tex, v3(c), 5.5+0.4*math.sin(v.time*2), {255, 80, 60, 170})
		rl.DrawBillboard(cam, tex, v3(c), 2.6, {255, 210, 140, 200})
		// A beacon column, visible across the whole course.
		base := w.portal_center - {0, 2.3, 0}
		rl.DrawCylinder(v3(base), 0.5, 0.9, 40, 12, {255, 90, 60, 24})
		rl.DrawCylinder(v3(base), 0.2, 0.35, 40, 8, {255, 200, 140, 30})
	} else {
		rl.DrawBillboard(cam, tex, v3(c), 3.6, {110, 60, 170, 60})
	}
	for i in 0..<w.sentinel_count {
		s := w.sentinels[i]
		rl.DrawBillboard(cam, tex, v3(s.position+{0, 0.4, 0}), 1.5, {255, 110, 50, 90})
	}
	if player_visible(v, w) {
		rl.DrawBillboard(cam, tex, v3(chest_position(v, w)), 0.8, {120, 210, 255, 110})
	}
	for i in 0..<w.mover_count {
		m := w.movers[i]
		if m.kind == .Shuttle {
			rl.DrawBillboard(cam, tex, v3(m.position+{m.size.x * 0.5, -0.7, m.size.z * 0.5}), 1.6, {90, 170, 255, 90})
		}
	}
}

// Camera-space direction to a point, for edge markers.
@(private)
view_direction :: proc(cam: rl.Camera3D, p: Vec3) -> (screen: Vec2, depth: f32) {
	eye := Vec3{cam.position.x, cam.position.y, cam.position.z}
	f := physics.normalize3(Vec3{cam.target.x, cam.target.y, cam.target.z} - eye)
	r := physics.normalize3(Vec3{f.y*0 - f.z*1, f.z*0 - f.x*0, f.x*1 - f.y*0})
	u := Vec3{r.y*f.z - r.z*f.y, r.z*f.x - r.x*f.z, r.x*f.y - r.y*f.x}
	d := p - eye
	x := d.x*r.x + d.y*r.y + d.z*r.z
	y := d.x*u.x + d.y*u.y + d.z*u.z
	return physics.normalize2(Vec2{x, -y}), d.x*f.x + d.y*f.y + d.z*f.z
}

// Diamond over a target on screen, or an arrow on the screen edge.
@(private)
draw_marker :: proc(cam: rl.Camera3D, p: Vec3, width, height: f32, color: rl.Color, time: f32, edge: bool) {
	dir, depth := view_direction(cam, p)
	screen := rl.GetWorldToScreenEx(v3(p), cam, i32(width), i32(height))
	margin := f32(28)
	top := f32(ui.HUD_MARGIN + ui.HUD_TOP_HEIGHT + 22)
	inside := depth > 0 && screen.x > margin && screen.x < width-margin && screen.y > top && screen.y < height-margin
	if inside {
		r := 6 + math.sin(time*5)
		rl.DrawPoly(screen, 4, r+2, 0, {0, 0, 0, color.a / 2})
		rl.DrawPoly(screen, 4, r, 0, color)
		return
	}
	if !edge {
		return
	}
	center := Vec2{width * 0.5, height * 0.5}
	half := Vec2{width*0.5 - margin, height*0.5 - margin}
	if dir.y < 0 {
		half.y = center.y - top
	}
	k := min(half.x/max(abs(dir.x), 0.001), half.y/max(abs(dir.y), 0.001))
	tip := center + dir*k
	back := tip - dir*16
	side := Vec2{-dir.y, dir.x} * 9
	rl.DrawTriangle({tip.x, tip.y}, {back.x + side.x, back.y + side.y}, {back.x - side.x, back.y - side.y}, color)
	rl.DrawTriangle({tip.x, tip.y}, {back.x - side.x, back.y - side.y}, {back.x + side.x, back.y + side.y}, color)
}

@(private)
draw_hud :: proc(v: ^View, w: ^World, frame: ^host.Frame, cam: rl.Camera3D) {
	theme := frame.theme
	width := frame.canvas.width
	height := frame.canvas.height
	center := physics.body3_center(w.player.body)

	// Markers: every shard nearby, the nearest one off screen, the open portal.
	nearest := -1
	nearest_d := max(f32)
	for i in 0..<w.shard_count {
		s := w.shards[i]
		if s.taken {
			continue
		}
		d := physics.length3(s.position - center)
		if d < nearest_d {
			nearest_d = d
			nearest = i
		}
		if d < 48 {
			draw_marker(cam, s.position+{0, 0.9, 0}, width, height, ui.with_alpha(SOUL, 1-d/60), v.time, false)
		}
	}
	if w.portal_open {
		draw_marker(cam, w.portal_center+{0, 3.6, 0}, width, height, GOLD, v.time, true)
	} else if nearest >= 0 {
		draw_marker(cam, w.shards[nearest].position+{0, 0.9, 0}, width, height, ui.with_alpha(SOUL, 0.85), v.time, true)
	}

	// Shared HUD: vitals, objective, score. Every value owns a bounded lane.
	palette := theme.palette
	zones := ui.hud_columns(frame.canvas)
	for zone in zones {
		ui.hud_panel(theme, zone)
	}
	left, middle, right := ui.shrink(zones[0], 10), ui.shrink(zones[1], 10), ui.shrink(zones[2], 10)
	for i in 0..<w.settings.lives {
		tint := rl.WHITE if i < w.lives else palette.border
		gfx.draw_sprite(v.life_icon, 0, {left.x + 10 + f32(i)*24, left.y + 10}, 2.4, tint = tint)
	}
	ui.draw_text_fit(theme, "SCATTO", {left.x, left.y + 27, 56, 18}, .Small, palette.text_dim)
	ui.hud_meter(theme, {left.x + 66, left.y + 34, left.width - 66, 5},
		1-w.player.dash_cooldown/PLAYER_PARAMS.dash_cooldown)

	enough := w.shards_taken >= w.shards_required
	count_color := palette.warning if enough else palette.text
	gfx.draw_sprite(v.gem_icon, 0, {middle.x + 10, middle.y + 12}, 2.6)
	ui.draw_text_fit(theme, fmt.tprintf("FRAMMENTI  %d/%d", w.shards_taken, w.shards_required),
		{middle.x + 30, middle.y, middle.width - 30, 23}, .Body, count_color)
	label := "Raggiungi il santuario" if w.portal_open else "Raccogli i frammenti d'anima"
	extra := w.shard_count - w.shards_required
	if extra > 0 && enough {
		label = fmt.tprintf("PORTALE APERTO   Bonus %d/%d", max(w.shards_taken-w.shards_required, 0), extra)
	}
	ui.draw_text_fit(theme, label, {middle.x, middle.y + 27, middle.width, 18}, .Small, palette.text_dim, .Center)

	score, _ := world_score(w)
	ui.draw_text_fit(theme, "PUNTI", {right.x, right.y, 64, 20}, .Small, palette.text_dim)
	ui.draw_text_fit(theme, fmt.tprintf("%d", score),
		{right.x + 68, right.y - 2, right.width - 68, 26}, .Large, palette.text, .Right)
	clock := host.format_time(w.time)
	clock_color := palette.text_dim
	if w.time_limit > 0 {
		left_time := max(w.time_limit-w.time, 0)
		clock = fmt.tprintf("TEMPO  %s", host.format_time(left_time))
		if left_time < 10 {
			clock_color = ui.mix_color(palette.danger, palette.text, 0.5+0.5*math.sin(v.time*10))
		}
	}
	ui.draw_text_fit(theme, clock, {right.x, right.y + 26, right.width, 20}, .Body, clock_color, .Right)

	// Centre messages.
	if v.message_time > 0 && v.message != .None {
		alpha := min(v.message_time*2, 1)
		title, sub: string
		color := IVORY
		switch v.message {
		case .None:
		case .Portal_Open:
			title = "Il portale si risveglia!"
			sub = "Raggiungi il santuario"
			color = GOLD
		case .Sealed:
			title = "Il portale è sigillato"
			sub = fmt.tprintf("Servono ancora %d frammenti", v.message_value)
			if v.message_value == 1 {
				sub = "Serve ancora un frammento"
			}
			color = SOUL
		case .Fell:
			title = "Inghiottito dall'abisso"
		case .Spiked:
			title = "Trafitto!"
		case .Time_Low:
			title = "Il tempo stringe!"
			color = CRIMSON
		}
		if v.message == .Fell || v.message == .Spiked {
			color = CRIMSON
			sub = "Ultima vita!" if v.message_value == 1 else fmt.tprintf("Vite rimaste: %d", v.message_value)
			if v.message_value <= 0 {
				sub = "Nessuna vita rimasta"
			}
		}
		toast := rl.Rectangle{width*0.5 - 230, ui.HUD_MARGIN + ui.HUD_TOP_HEIGHT + 8, 460, 24}
		ui.draw_text_fit(theme, title, toast, .Body, ui.with_alpha(color, alpha), .Center)
		if sub != "" {
			toast.y += 23
			ui.draw_text_fit(theme, sub, toast, .Small, ui.with_alpha(palette.text_dim, alpha), .Center)
		}
	}

	for i in 0..<v.popups.count {
		p := v.popups.items[i]
		a := clamp(p.life/p.max_life*1.5, 0, 1)
		ui.draw_text_centered(theme, p.text, p.position, .Large, ui.with_alpha(p.color, a))
	}

	if w.status == .Playing && v.play_time < 9 {
		a := clamp((9-v.play_time)/2, 0, 1)
		ui.draw_text_fit(theme, "SPAZIO doppio salto    SHIFT scatto    Q/E visuale",
			{width*0.5 - 250, height - 34, 500, 20}, .Small, ui.with_alpha(palette.text_dim, a), .Center)
	}
}

// Iron fire bowls on a stone pedestal; the flames are particles.
@(private)
draw_braziers :: proc(w: ^World, glow: bool) {
	for i in 0..<w.brazier_count {
		b := w.braziers[i]
		if glow {
			rl.DrawCubeV(v3(b+{0, 0.93, 0}), {0.42, 0.06, 0.42}, {255, 150, 60, 255})
			continue
		}
		rl.DrawCubeV(v3(b+{0, 0.06, 0}), {0.5, 0.12, 0.5}, {70, 66, 82, 255})
		rl.DrawCubeV(v3(b+{0, 0.45, 0}), {0.26, 0.7, 0.26}, {86, 82, 98, 255})
		rl.DrawCubeV(v3(b+{0, 0.86, 0}), {0.56, 0.14, 0.56}, {48, 44, 52, 255})
	}
}
