package fps

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

// Billboards: alpha-tested (so they can be drawn in any order against the
// walls) and fogged like the lit voxel mesh. Lighting comes in through the
// vertex colour, computed on the CPU from the same point light.
SPRITE_VERTEX :: `#version 330
in vec3 vertexPosition;
in vec2 vertexTexCoord;
in vec4 vertexColor;
uniform mat4 mvp;
out vec2 fragTexCoord;
out vec4 fragColor;
out vec3 fragPos;
void main() {
    fragTexCoord = vertexTexCoord;
    fragColor = vertexColor;
    fragPos = vertexPosition;
    gl_Position = mvp * vec4(vertexPosition, 1.0);
}
`

SPRITE_FRAGMENT :: `#version 330
in vec2 fragTexCoord;
in vec4 fragColor;
in vec3 fragPos;
uniform sampler2D texture0;
uniform vec3 viewPos;
uniform vec4 fogColor;
uniform vec2 fogRange;
out vec4 finalColor;
void main() {
    vec4 base = texture(texture0, fragTexCoord) * fragColor;
    if (base.a < 0.1) discard;
    float d = length(viewPos - fragPos);
    float fog = clamp((d - fogRange.x) / max(fogRange.y - fogRange.x, 0.001), 0.0, 1.0);
    finalColor = vec4(mix(base.rgb, fogColor.rgb, fog * fogColor.a), base.a);
}
`

FOG_COLOR :: rl.Color{7, 12, 21, 255}
FOG_NEAR :: f32(4)
FOG_FAR :: f32(22)
LANTERN_COLOR :: Vec3{0.83, 1.06, 1.38}
MUZZLE_COLOR :: Vec3{1.3, 1.85, 2.3}
SPRITE_AMBIENT :: Vec3{0.64, 0.68, 0.76}
MUZZLE_TIME :: f32(0.09)

MAX_TRAILS :: 16
MAX_DECOR :: 200
MAX_MARKS :: 10
MAX_SPRITE_DRAWS :: 320

Trail :: struct {
	from, to: Vec3,
	life:     f32,
	color:    rl.Color,
}

Decor_Kind :: enum u8 {
	Candle,
	Skull,
	Bones,
	Brazier,
}

Decor :: struct {
	kind:     Decor_Kind,
	position: Vec3,
	phase:    f32,
}

// Score text floating up from where it was earned.
Mark :: struct {
	position: Vec3,
	text:     string, // literals only
	color:    rl.Color,
	life:     f32,
}

Banner_Kind :: enum u8 {
	None,
	Start,
	Rune,
	Portal_Open,
	Sealed,
	Wave,
}

View :: struct {
	gpu:           bool,
	lighting:      gfx.Lighting,
	sprite_shader: rl.Shader,
	sprite_ok:     bool,
	loc_view:      i32,
	loc_fog_color: i32,
	loc_fog_range: i32,
	model:         rl.Model,
	has_model:     bool,
	sprites:       [Sprite_Id]gfx.Sprite,
	figures:       gfx.Paper_Figures,
	// Animated paper standees for the enemies, one player per slot.
	book:          gfx.Flipbook_Assets,
	books:         [MAX_ENEMIES]gfx.Flipbook_Player,
	book_states:   [MAX_ENEMIES]Enemy_State,
	book_hurt:     [MAX_ENEMIES]bool,
	book_kinds:    [MAX_ENEMIES]Enemy_Kind,
	glow:          rl.Texture2D,
	stone:         rl.Texture2D,
	cam:           camera.Fps_Camera,
	particles:     fx.Particles(1024),
	flash:         fx.Flash,
	hit_stop:      fx.Hit_Stop,
	fx_rng:        rng.Rng,
	trails:        [MAX_TRAILS]Trail,
	trail_next:    int,
	marks:         [MAX_MARKS]Mark,
	mark_next:     int,
	decor:         [MAX_DECOR]Decor,
	decor_count:   int,
	muzzle:        f32,
	kick:          f32,
	hitmarker:     f32,
	killmarker:    f32,
	hurt_time:     f32,
	hurt_angle:    f32,
	dry_time:      f32,
	banner:        Banner_Kind,
	banner_value:  int,
	banner_time:   f32,
	show_map:      bool,
	time:          f32,
	end_time:      f32,
	shake_scale:   f32,
	ghost_hp:      f32,
	pickup_pulse:  f32,
}

// GPU resources that do not depend on the crypt layout.
view_init :: proc(v: ^View) {
	v.lighting = gfx.lighting_create()
	v.lighting.fog_color = FOG_COLOR
	v.lighting.fog_near = FOG_NEAR
	v.lighting.fog_far = FOG_FAR
	v.lighting.sun_dir = {-0.35, -1, -0.45}
	v.lighting.sun_color = {0.19, 0.24, 0.34}
	v.lighting.ambient = {0.29, 0.33, 0.42}
	v.lighting.specular = 0.22
	v.sprite_shader = rl.LoadShaderFromMemory(SPRITE_VERTEX, SPRITE_FRAGMENT)
	v.sprite_ok = rl.IsShaderValid(v.sprite_shader)
	if v.sprite_ok {
		v.loc_view = rl.GetShaderLocation(v.sprite_shader, "viewPos")
		v.loc_fog_color = rl.GetShaderLocation(v.sprite_shader, "fogColor")
		v.loc_fog_range = rl.GetShaderLocation(v.sprite_shader, "fogRange")
	}
	v.figures = gfx.paper_figures_create()
	gfx.create_flipbook_assets(&v.book)
	for id in Sprite_Id {
		v.sprites[id], _ = gfx.sprite_load(SPRITE_ASSETS[id])
	}
	img := rl.GenImageGradientRadial(64, 64, 0, rl.WHITE, rl.BLANK)
	v.glow = rl.LoadTextureFromImage(img)
	rl.UnloadImage(img)
	rl.SetTextureFilter(v.glow, .BILINEAR)
	v.stone = make_stone_texture()
	// The minimap preference survives retries.
	v.show_map = true
	v.gpu = true
}

view_destroy :: proc(v: ^View) {
	release_model(v)
	gfx.paper_figures_destroy(&v.figures)
	gfx.destroy_flipbook_assets(&v.book)
	for id in Sprite_Id {
		gfx.sprite_destroy(&v.sprites[id])
	}
	if v.stone.id != 0 {
		rl.UnloadTexture(v.stone)
	}
	if v.glow.id != 0 {
		rl.UnloadTexture(v.glow)
	}
	if v.sprite_ok {
		rl.UnloadShader(v.sprite_shader)
	}
	gfx.lighting_destroy(&v.lighting)
	v.gpu = false
}

// rl.UnloadModel also unloads every non-default material shader and texture,
// which would free the shared lighting shader and stone texture (and later
// double free them). Hand the defaults back to the materials first.
@(private)
release_model :: proc(v: ^View) {
	if !v.has_model {
		return
	}
	for i in 0..<v.model.materialCount {
		v.model.materials[i].shader = rl.Shader{id = rlgl.GetShaderIdDefault(), locs = rlgl.GetShaderLocsDefault()}
		v.model.materials[i].maps[0].texture = rl.Texture2D{id = rlgl.GetTextureIdDefault(), width = 1, height = 1, mipmaps = 1,
			format = .UNCOMPRESSED_R8G8B8A8}
	}
	rl.UnloadModel(v.model)
	v.model = {}
	v.has_model = false
}

// Grey ashlar shared by every voxel face and tinted by the material colour.
// The voxel mesher orients face UVs differently per axis, so the pattern is
// symmetric under transposition: square blocks with an even bevel.
@(private)
make_stone_texture :: proc() -> rl.Texture2D {
	// Flat paper colour; the house's boards and mouldings are actual geometry.
	img := rl.GenImageColor(2, 2, rl.WHITE)
	tex := rl.LoadTextureFromImage(img)
	rl.UnloadImage(img)
	return tex
}

@(private)
voxel_palette :: proc() -> gfx.Voxel_Palette {
	p: gfx.Voxel_Palette
	set :: proc(p: ^gfx.Voxel_Palette, m: Material, c: rl.Color) {
		p[u8(m)] = c
	}
	set(&p, .Floor, {98, 77, 68, 255})
	set(&p, .Floor_Cracked, {74, 60, 58, 255})
	set(&p, .Floor_Room_A, {119, 91, 76, 255})
	set(&p, .Floor_Room_B, {103, 81, 72, 255})
	set(&p, .Ceiling, {35, 45, 62, 255})
	set(&p, .Slate, {78, 102, 100, 255})
	set(&p, .Slate_Trim, {64, 48, 48, 255})
	set(&p, .Moss, {91, 111, 123, 255})
	set(&p, .Moss_Trim, {45, 63, 76, 255})
	set(&p, .Brick, {117, 84, 91, 255})
	set(&p, .Brick_Trim, {70, 49, 56, 255})
	set(&p, .Obsidian, {65, 78, 104, 255})
	set(&p, .Obsidian_Trim, {36, 48, 69, 255})
	set(&p, .Glyph, {105, 158, 192, 255})
	set(&p, .Pillar, {144, 156, 168, 255})
	set(&p, .Arch, {170, 143, 116, 255})
	return p
}

// Layout-dependent resources and per-round feedback state.
view_reset :: proc(v: ^View, w: ^World) {
	release_model(v)
	if v.gpu {
		palette := voxel_palette()
		v.model, v.has_model = gfx.build_voxel_model(&w.voxels, &palette)
		if v.has_model {
			gfx.lighting_apply_to_model(&v.lighting, &v.model)
			if v.stone.id != 0 {
				for i in 0..<v.model.materialCount {
					v.model.materials[i].maps[0].texture = v.stone
				}
			}
		}
	}
	fx.clear(&v.particles)
	v.trails = {}
	v.marks = {}
	v.flash = {}
	v.hit_stop = {}
	v.muzzle, v.kick, v.hitmarker, v.killmarker = 0, 0, 0, 0
	v.hurt_time, v.dry_time, v.end_time = 0, 0, 0
	v.banner, v.banner_value, v.banner_time = .Start, w.rune_count, 0
	v.ghost_hp = w.player.hp
	v.fx_rng = rng.create(rng.derive(w.config.seed, 50))
	v.cam = camera.fps_create(player_eye(w.player), w.player.yaw)
	v.cam.pitch = w.player.pitch
	build_decor(v, w)
}

@(private)
add_decor :: proc(v: ^View, kind: Decor_Kind, position: Vec3, r: ^rng.Rng) {
	if v.decor_count >= MAX_DECOR {
		return
	}
	v.decor[v.decor_count] = Decor{kind = kind, position = position, phase = rng.float01(r) * math.TAU}
	v.decor_count += 1
}

// Candles along hall walls, braziers by the portal, bones in corridors.
// Purely cosmetic, so it uses its own random stream.
@(private)
build_decor :: proc(v: ^View, w: ^World) {
	v.decor_count = 0
	r := rng.create(rng.derive(w.config.seed, 51))
	m := &w.maze
	exit := room_center_voxel(m.rooms[m.exit_room])
	add_decor(v, .Brazier, Vec3{f32(exit.x) - 1.5, FLOOR_Y, f32(exit.y) + 0.5}, &r)
	add_decor(v, .Brazier, Vec3{f32(exit.x) + 3.5, FLOOR_Y, f32(exit.y) + 0.5}, &r)
	for z in 0..<w.side {
		for x in 0..<w.side {
			if !walkable_xz(w, x, z) {
				continue
			}
			// Direction toward an adjacent wall, if any.
			wall: Vec2
			for d in ([4][2]int{{1, 0}, {-1, 0}, {0, 1}, {0, -1}}) {
				if !walkable_xz(w, x+d.x, z+d.y) {
					wall = Vec2{f32(d.x), f32(d.y)}
					break
				}
			}
			if wall == {} {
				continue
			}
			room := tile_room(m, tile_of_voxel(x), tile_of_voxel(z))
			base := Vec3{f32(x) + 0.5 + wall.x*0.3, FLOOR_Y, f32(z) + 0.5 + wall.y*0.3}
			if room >= 0 {
				if rng.chance(&r, 0.16) {
					add_decor(v, .Candle, base, &r)
					if rng.chance(&r, 0.5) {
						add_decor(v, .Candle, base+Vec3{wall.y * 0.22, 0, wall.x * 0.22}, &r)
					}
				}
			} else {
				roll := rng.float01(&r)
				if roll < 0.035 {
					add_decor(v, .Skull, base, &r)
				} else if roll < 0.07 {
					add_decor(v, .Bones, base, &r)
				} else if roll < 0.085 {
					add_decor(v, .Candle, base, &r)
				}
			}
		}
	}
}

@(private)
add_trail :: proc(v: ^View, from, to: Vec3, color: rl.Color) {
	v.trails[v.trail_next] = Trail{from = from, to = to, life = 1, color = color}
	v.trail_next = (v.trail_next + 1) % MAX_TRAILS
}

@(private)
add_mark :: proc(v: ^View, position: Vec3, text: string, color: rl.Color) {
	v.marks[v.mark_next] = Mark{position = position, text = text, color = color, life = 1}
	v.mark_next = (v.mark_next + 1) % MAX_MARKS
}

@(private)
trauma :: proc(v: ^View, amount: f32) {
	camera.add_trauma(&v.cam.shake, amount*v.shake_scale)
}

// Where the staff crystal sits in the world, for bolt trails and the light.
muzzle_position :: proc(v: ^View) -> Vec3 {
	fwd := camera.fps_forward(v.cam)
	right := Vec3{-math.cos(v.cam.yaw), 0, math.sin(v.cam.yaw)}
	return v.cam.position + fwd*0.55 + right*0.24 + Vec3{0, -0.16, 0}
}

// Particle colours of each enemy's insides.
@(private)
enemy_gore :: proc(kind: Enemy_Kind) -> (a, b: rl.Color) {
	switch kind {
	case .Ghoul:
		return {130, 170, 70, 255}, {40, 60, 20, 0}
	case .Wraith:
		return {170, 240, 255, 255}, {60, 120, 160, 0}
	case .Cultist:
		return {220, 40, 50, 255}, {80, 10, 20, 0}
	}
	return rl.WHITE, rl.BLANK
}

@(private)
spatial_volume :: proc(v: ^View, p: Vec3) -> f32 {
	d := physics.length3(p - v.cam.position)
	return clamp(1-d/24, 0.12, 1)
}

// Turns the step's events into sound, particles, shake and HUD feedback.
view_consume_events :: proc(g: ^Game, frame: ^host.Frame) {
	w := &g.world
	v := &g.view
	a := frame.audio
	r := &v.fx_rng
	for i in 0..<w.event_count {
		e := w.events[i]
		switch e.kind {
		case .Shot:
			v.muzzle = MUZZLE_TIME
			v.kick = 1
			from := muzzle_position(v)
			// The beam starts a little ahead of the crystal so it stays thin on screen.
			ahead := physics.normalize3(e.position - from)
			add_trail(v, from+ahead*min(0.5, physics.length3(e.position-from)*0.5), e.position, {154, 212, 250, 230})
			audio.play(a, .Laser, 0.45, rng.float_range(r, 0.62, 0.72))
			trauma(v, 0.07)
			emitter := fx.Emitter{speed_min = 0.5, speed_max = 2, direction = e.normal, spread = 0.6,
				life_min = 0.08, life_max = 0.18, size_start = 0.05, size_end = 0,
				color_start = {189, 231, 255, 255}, color_end = {56, 119, 187, 0}, three_d = true}
			fx.emit(&v.particles, emitter, from, 4, r)
		case .Dry_Fire:
			v.dry_time = 0.4
			audio.play(a, .Blip, 0.4, 0.45)
		case .Wall_Hit:
			sparks := fx.Emitter{speed_min = 1.5, speed_max = 4.5, direction = e.normal, spread = 1.1,
				life_min = 0.15, life_max = 0.4, size_start = 0.06, size_end = 0,
				color_start = {255, 236, 170, 255}, color_end = {255, 110, 30, 0}, gravity = 9, drag = 1.5,
				three_d = true}
			fx.emit(&v.particles, sparks, e.position+e.normal*0.03, 12, r)
			dust := fx.Emitter{speed_min = 0.2, speed_max = 0.8, direction = e.normal, spread = 1.3,
				life_min = 0.4, life_max = 0.8, size_start = 0.09, size_end = 0.02,
				color_start = {120, 110, 100, 160}, color_end = {60, 55, 50, 0}, gravity = -0.3, drag = 2,
				three_d = true}
			fx.emit(&v.particles, dust, e.position+e.normal*0.05, 5, r)
			audio.play(a, .Hit, 0.18, rng.float_range(r, 1.3, 1.6))
		case .Enemy_Hit:
			v.hitmarker = 0.16
			ca, cb := enemy_gore(e.enemy)
			gore := fx.Emitter{speed_min = 1, speed_max = 3.5, direction = -e.normal, spread = 1.0,
				life_min = 0.25, life_max = 0.55, size_start = 0.08, size_end = 0.01,
				color_start = ca, color_end = cb, gravity = 9, drag = 1, three_d = true}
			fx.emit(&v.particles, gore, e.position, 14, r)
			audio.play(a, .Hit, 0.5, rng.float_range(r, 0.85, 1.05))
			trauma(v, 0.05)
		case .Enemy_Killed:
			v.killmarker = 0.3
			v.hitmarker = 0.2
			fx.hit_stop(&v.hit_stop, 0.05)
			ca, cb := enemy_gore(e.enemy)
			burst := fx.Emitter{speed_min = 2, speed_max = 6, direction = {0, 1, 0}, spread = math.PI,
				life_min = 0.4, life_max = 0.9, size_start = 0.12, size_end = 0.01,
				color_start = ca, color_end = cb, gravity = 8, drag = 1.2, three_d = true}
			fx.emit(&v.particles, burst, e.position, 36, r)
			embers := fx.Emitter{speed_min = 0.5, speed_max = 2, direction = {0, 1, 0}, spread = 0.9,
				life_min = 0.6, life_max = 1.3, size_start = 0.05, size_end = 0,
				color_start = {255, 200, 110, 255}, color_end = {200, 60, 30, 0}, gravity = -1.5, drag = 1,
				three_d = true}
			fx.emit(&v.particles, embers, e.position, 14, r)
			audio.play(a, .Explosion, 0.55, rng.float_range(r, 1.1, 1.3))
			trauma(v, 0.18)
			text := "+100"
			switch e.enemy {
			case .Ghoul:
				text = "+100"
			case .Wraith:
				text = "+150"
			case .Cultist:
				text = "+200"
			}
			add_mark(v, e.position+Vec3{0, 0.4, 0}, text, {232, 196, 112, 255})
		case .Projectile_Shot_Down:
			v.hitmarker = 0.16
			burst := fx.Emitter{speed_min = 1.5, speed_max = 4, direction = {0, 1, 0}, spread = math.PI,
				life_min = 0.2, life_max = 0.5, size_start = 0.08, size_end = 0,
				color_start = {248, 138, 149, 255}, color_end = {151, 32, 49, 0}, gravity = 2, three_d = true}
			fx.emit(&v.particles, burst, e.position, 18, r)
			audio.play(a, .Hit, 0.45, 1.6)
			add_mark(v, e.position, "Parata +25", {172, 220, 250, 255})
		case .Enemy_Alert:
			vol := spatial_volume(v, e.position)
			add_mark(v, e.position+Vec3{0, 0.45, 0}, "!", {255, 90, 70, 255})
			switch e.enemy {
			case .Ghoul:
				audio.play(a, .Hurt, 0.4*vol, 0.42)
			case .Wraith:
				audio.play(a, .Power_Up, 0.25*vol, 0.6)
			case .Cultist:
				audio.play(a, .Lose, 0.22*vol, 1.4)
			}
		case .Enemy_Windup:
			audio.play(a, .Dash, 0.35*spatial_volume(v, e.position), 0.55)
		case .Enemy_Strike:
			audio.play(a, .Push, 0.6*spatial_volume(v, e.position), 0.8)
		case .Enemy_Cast:
			audio.play(a, .Laser, 0.4*spatial_volume(v, e.position), 0.4)
			flare := fx.Emitter{speed_min = 0.5, speed_max = 1.8, direction = {0, 1, 0}, spread = math.PI,
				life_min = 0.2, life_max = 0.4, size_start = 0.07, size_end = 0,
				color_start = {248, 138, 149, 255}, color_end = {151, 32, 49, 0}, three_d = true}
			fx.emit(&v.particles, flare, e.position, 10, r)
		case .Projectile_Burst:
			burst := fx.Emitter{speed_min = 1, speed_max = 3.5, direction = e.normal, spread = 1.4,
				life_min = 0.2, life_max = 0.45, size_start = 0.08, size_end = 0,
				color_start = {248, 138, 149, 255}, color_end = {127, 28, 42, 0}, gravity = 3, three_d = true}
			fx.emit(&v.particles, burst, e.position, 16, r)
			audio.play(a, .Hit, 0.35*spatial_volume(v, e.position), 0.6)
		case .Player_Hurt:
			fx.flash_start(&v.flash, {200, 20, 30, 120}, 0.35)
			trauma(v, 0.42)
			fx.hit_stop(&v.hit_stop, 0.03)
			to := e.position - v.cam.position
			v.hurt_angle = math.angle_diff(w.player.yaw, math.atan2(to.x, to.z))
			v.hurt_time = 1
			audio.play(a, .Hurt, 0.7, rng.float_range(r, 0.9, 1.05))
		case .Pickup_Health:
			fx.flash_start(&v.flash, {220, 60, 70, 70}, 0.3)
			audio.play(a, .Coin, 0.5, 0.8)
			add_mark(v, e.position+Vec3{0, 0.8, 0}, "+30 Vita", {255, 120, 120, 255})
			v.pickup_pulse = 1
		case .Pickup_Mana:
			fx.flash_start(&v.flash, {80, 120, 255, 70}, 0.3)
			audio.play(a, .Coin, 0.5, 1.15)
			add_mark(v, e.position+Vec3{0, 0.8, 0}, "+45 Mana", {150, 180, 255, 255})
			v.pickup_pulse = 1
		case .Rune_Taken:
			fx.flash_start(&v.flash, {255, 200, 100, 70}, 0.45)
			audio.play(a, .Power_Up, 0.7, 1)
			audio.play(a, .Coin, 0.5, 0.7)
			trauma(v, 0.2)
			glyphs := fx.Emitter{speed_min = 1, speed_max = 3, direction = {0, 1, 0}, spread = math.PI,
				life_min = 0.5, life_max = 1.2, size_start = 0.09, size_end = 0,
				color_start = {255, 240, 180, 255}, color_end = {255, 150, 40, 0}, gravity = -1, drag = 1.5,
				three_d = true}
			fx.emit(&v.particles, glyphs, e.position+Vec3{0, 1, 0}, 40, r)
			add_mark(v, e.position+Vec3{0, 1.4, 0}, "+500", {255, 220, 140, 255})
			v.banner, v.banner_value, v.banner_time = .Rune, int(e.value), 0
		case .Portal_Open:
			trauma(v, 0.55)
			audio.play(a, .Explosion, 0.6, 0.5)
			audio.play(a, .Confirm, 0.6, 0.6)
			v.banner, v.banner_time = .Portal_Open, 0
		case .Portal_Sealed:
			audio.play(a, .Back, 0.5, 0.6)
			v.banner, v.banner_value, v.banner_time = .Sealed, w.rune_count - w.runes_taken, 0
		case .Wave:
			// Shown after the portal banner, which it would otherwise hide.
		case .Jump:
			audio.play(a, .Jump, 0.18, 0.7)
		case .Land:
			audio.play(a, .Land, 0.45, 0.9)
			trauma(v, min(e.value*0.02, 0.15))
		case .Footstep:
			audio.play(a, .Step, 0.55, rng.float_range(r, 0.8, 1.05))
		case .Escaped:
			fx.flash_start(&v.flash, {188, 221, 255, 180}, 0.9)
			audio.play(a, .Power_Up, 0.7, 0.5)
		case .Died:
			fx.flash_start(&v.flash, {150, 0, 10, 200}, 1.2)
			trauma(v, 0.6)
		}
	}
}

// Per-frame feedback: camera, particles, timers, ambient emitters.
view_update :: proc(g: ^Game, frame: ^host.Frame, live: bool) {
	w := &g.world
	v := &g.view
	dt := frame.dt
	v.time += dt
	p := w.player
	eye := player_eye(p)
	alpha := g.clock.alpha if w.status == .Playing else 1
	v.cam.position = p.prev_eye + (eye-p.prev_eye)*alpha
	v.cam.yaw = p.yaw
	v.cam.pitch = p.pitch
	if !live {
		return
	}
	camera.fps_update(&v.cam, p.speed if p.grounded else 0, dt)
	fx.update(&v.particles, dt, true)
	fx.flash_update(&v.flash, dt)
	v.muzzle = max(v.muzzle-dt, 0)
	v.kick *= math.exp(-14 * dt)
	v.hitmarker = max(v.hitmarker-dt, 0)
	v.killmarker = max(v.killmarker-dt, 0)
	v.hurt_time = max(v.hurt_time-dt*1.2, 0)
	v.dry_time = max(v.dry_time-dt, 0)
	v.pickup_pulse = max(v.pickup_pulse-dt*2, 0)
	v.banner_time += dt
	if v.ghost_hp > p.hp {
		v.ghost_hp = max(v.ghost_hp-dt*30, p.hp)
	} else {
		v.ghost_hp = p.hp
	}
	if w.status != .Playing {
		v.end_time += dt
	}
	for &t in v.trails {
		t.life = max(t.life-dt*7, 0)
	}
	for &m in v.marks {
		m.life = max(m.life-dt*0.9, 0)
		m.position.y += dt * 0.6
	}
	r := &v.fx_rng
	// Trails behind cultist bolts.
	for pr in w.projectiles {
		if !pr.alive {
			continue
		}
		trail := fx.Emitter{speed_min = 0, speed_max = 0.4, direction = {0, 1, 0}, spread = math.PI,
			life_min = 0.2, life_max = 0.4, size_start = 0.09, size_end = 0,
			color_start = {237, 76, 103, 220}, color_end = {103, 21, 36, 0}, three_d = true}
		fx.emit(&v.particles, trail, pr.position, 1, r)
	}
	// Runes shed sparks so they read from a distance, and the open portal swirls.
	if rng.chance(r, dt*20) {
		for i in 0..<w.pickup_count {
			pk := w.pickups[i]
			if pk.kind != .Rune || pk.taken || physics.length3(pk.position-eye) > 14 {
				continue
			}
			spark := fx.Emitter{speed_min = 0.2, speed_max = 0.7, direction = {0, 1, 0}, spread = 0.8,
				life_min = 0.6, life_max = 1.2, size_start = 0.05, size_end = 0,
				color_start = {255, 220, 140, 255}, color_end = {255, 120, 30, 0}, gravity = -0.6,
				radius = 0.3, three_d = true}
			fx.emit(&v.particles, spark, pk.position+Vec3{0, 0.9, 0}, 1, r)
		}
	}
	if w.portal.open && rng.chance(r, dt*40) {
		a := rng.float01(r) * math.TAU
		rr := rng.float_range(r, 0.3, 0.9)
		pos := w.portal.center + Vec3{math.cos(a) * rr, math.sin(a) * rr * 1.3, 0}
		mote := fx.Emitter{speed_min = 0.3, speed_max = 1, direction = {0, 1, 0}, spread = 0.6,
			life_min = 0.5, life_max = 1, size_start = 0.06, size_end = 0,
			color_start = {179, 221, 255, 255}, color_end = {60, 125, 192, 0}, gravity = -1, three_d = true}
		fx.emit(&v.particles, mote, pos, 1, r)
	}
}

// Camera for this frame: interpolated eye, recoil kick and the death fall.
view_camera :: proc(g: ^Game) -> rl.Camera3D {
	v := &g.view
	cam := v.cam
	cam.pitch += v.kick * 0.03
	c := camera.fps_to_raylib(cam)
	if g.world.status == .Lost {
		t := min(v.end_time/0.9, 1)
		k := 1 - (1-t)*(1-t)
		drop := Vec3{0, -1.2 * k, 0}
		c.position += drop
		c.target += drop + Vec3{0, -0.3 * k, 0}
		right := Vec3{-math.cos(cam.yaw), 0, math.sin(cam.yaw)}
		c.up = physics.normalize3(Vec3{0, 1, 0} + right*0.7*k)
	}
	return c
}

// The shader supports one point light: the muzzle flash wins, then an
// incoming bolt, then a nearby rune or the open portal, else the lantern.
@(private)
choose_light :: proc(g: ^Game, eye: Vec3) {
	w := &g.world
	v := &g.view
	l := &v.lighting
	flicker := 1 + 0.06*math.sin(v.time*13.1) + 0.04*math.sin(v.time*29.7)
	fwd := camera.fps_forward(v.cam)
	l.point_pos = eye + Vec3{fwd.x * 0.3, 0.25, fwd.z * 0.3}
	l.point_color = LANTERN_COLOR * flicker
	l.point_radius = 10.5
	if v.muzzle > 0 {
		k := v.muzzle / MUZZLE_TIME
		l.point_pos = muzzle_position(v) + fwd*0.4
		l.point_color = LANTERN_COLOR + (MUZZLE_COLOR-LANTERN_COLOR)*k
		l.point_radius = 9.5 + 4*k
		return
	}
	best := f32(6)
	found := false
	for pr in w.projectiles {
		if !pr.alive {
			continue
		}
		d := physics.length3(pr.position - eye)
		if d < best {
			best, found = d, true
			l.point_pos = pr.position
		}
	}
	if found {
		l.point_color = Vec3{1.7, 0.33, 0.4}
		l.point_radius = 7
		return
	}
	best = 6.5
	for i in 0..<w.pickup_count {
		pk := w.pickups[i]
		if pk.kind != .Rune || pk.taken {
			continue
		}
		center := pk.position + Vec3{0, 1.1, 0}
		d := physics.length3(center - eye)
		if d < best {
			best, found = d, true
			l.point_pos = center
		}
	}
	if found {
		pulse := 1 + 0.15*math.sin(v.time*4)
		l.point_color = Vec3{1.8, 1.25, 0.55} * pulse
		l.point_radius = 8.5
		return
	}
	if w.portal.open && physics.length3(w.portal.center-eye) < 9 {
		l.point_pos = w.portal.center
		l.point_color = Vec3{0.6, 1.25, 1.9} * flicker
		l.point_radius = 10
	}
}

@(private)
light_at :: proc(v: ^View, p: Vec3, base := rl.WHITE) -> rl.Color {
	l := v.lighting
	d := physics.length3(l.point_pos - p)
	att := clamp(1-d/max(l.point_radius, 0.01), 0, 1)
	k := SPRITE_AMBIENT + l.point_color*(att*att)
	return rl.Color{u8(clamp(f32(base.r)*k.x, 0, 255)), u8(clamp(f32(base.g)*k.y, 0, 255)),
		u8(clamp(f32(base.b)*k.z, 0, 255)), base.a}
}

@(private)
Sprite_Draw :: struct {
	sprite: Sprite_Id,
	frame:  int,
	center: Vec3,
	size:   Vec2,
	tint:   rl.Color,
	flip:   bool,
	figure: bool,
	figure_index: int,
	pose: f32,
	// A flipbook standee: player slot, feet and resting height.
	book: bool,
	book_index: int,
	feet: Vec3,
	height: f32,
	dist:   f32,
}

@(private)
Draw_List :: struct {
	items: [MAX_SPRITE_DRAWS]Sprite_Draw,
	count: int,
}

@(private)
push_sprite :: proc(list: ^Draw_List, eye: Vec3, d: Sprite_Draw) {
	if list.count >= MAX_SPRITE_DRAWS {
		return
	}
	item := d
	delta := d.center - eye
	item.dist = delta.x*delta.x + delta.y*delta.y + delta.z*delta.z
	list.items[list.count] = item
	list.count += 1
}

// Sprite standing on `feet`, `height` tall, keeping the sprite's aspect.
@(private)
standing :: proc(v: ^View, id: Sprite_Id, feet: Vec3, height: f32) -> (center: Vec3, size: Vec2) {
	s := v.sprites[id]
	width := height
	if s.height > 0 {
		width = height * f32(s.width) / f32(s.height)
	}
	return feet + Vec3{0, height * 0.5, 0}, Vec2{width, height}
}

@(private)
enemy_sprite :: proc(kind: Enemy_Kind) -> (Sprite_Id, f32) {
	switch kind {
	case .Ghoul:
		return .Ghoul, 1.8
	case .Wraith:
		return .Wraith, 1.65
	case .Cultist:
		return .Cultist, 1.9
	}
	return .Ghoul, 1.8
}

@(private)
collect_sprites :: proc(g: ^Game, list: ^Draw_List, cam: rl.Camera3D) {
	w := &g.world
	v := &g.view
	eye := Vec3(cam.position)
	alpha := g.clock.alpha if w.status == .Playing else 1
	right := Vec3{-math.cos(v.cam.yaw), 0, math.sin(v.cam.yaw)}
	for i in 0..<w.enemy_count {
		e := w.enemies[i]
		id, height := enemy_sprite(e.kind)
		feet := e.prev_feet + (enemy_feet(e)-e.prev_feet)*alpha
		frame := FRAME_WALK_A
		tint := rl.WHITE
		params := enemy_params(e.kind)
		lift := params.hover
		switch e.state {
		case .Dead:
			frame = FRAME_DEAD
			lift = 0
			if e.kind == .Wraith {
				// Wraiths leave only a fading wisp.
				tint.a = u8(255 * clamp(1-e.state_time/1.5, 0, 1))
				if tint.a < 10 {
					continue
				}
			}
		case .Windup, .Strike:
			frame = FRAME_ATTACK
			if e.kind == .Ghoul {
				// Telegraph: the ghoul flushes red while it rears up.
				k := clamp(e.state_time/params.windup, 0, 1)
				tint = rl.Color{255, u8(255 - 120*k), u8(255 - 140*k), 255}
			}
		case .Idle, .Chase, .Recover:
			if e.kind == .Wraith {
				frame = FRAME_WALK_A + int(v.time*3+e.phase)%2
			} else {
				frame = FRAME_WALK_A + int(e.anim/0.5)%2
			}
		}
		if e.kind == .Wraith && e.state != .Dead {
			lift += 0.12 * math.sin(v.time*2.3+e.phase)
		}
		if e.hurt_time > 0 && e.state != .Dead {
			frame = FRAME_FLASH
		}
		center, size := standing(v, id, feet+Vec3{0, lift, 0}, height)
		lit := light_at(v, center, tint)
		if frame == FRAME_FLASH {
			lit = rl.WHITE
		}
		flip := e.facing.x*right.x + e.facing.y*right.z < 0
		if v.book.loaded && i < len(v.books) {
			fps_update_book(v, i, e)
			if e.kind == .Wraith { lit = rl.Color{min(lit.r,155),min(lit.g,213),lit.b,lit.a} }
			standee_feet := feet+Vec3{0, lift, 0}
			push_sprite(list, eye, Sprite_Draw{center=standee_feet+Vec3{0, height*0.5, 0}, tint=lit, flip=!flip,
				book=true, book_index=i, feet=standee_feet, height=height*0.9})
		} else if v.figures.texture.id != 0 {
			figure_index := 1 if e.kind == .Ghoul else (6 if e.kind == .Wraith else 5)
			size = gfx.paper_figure_size(&v.figures, figure_index, height)
			pose := f32(frame%2)*2-1
			if e.state == .Dead {
				size.y *= 0.19
				size.x *= 1.15
				center = feet+Vec3{0,size.y*0.5,0}
				lit = {90,98,117,tint.a}
			} else if e.state == .Windup || e.state == .Strike {
				size.x *= 1.09
				size.y *= 0.94
				center.y -= height*0.03
			} else {
				center.y += pose*0.018
			}
			if e.kind == .Wraith { lit = rl.Color{min(lit.r,155),min(lit.g,213),lit.b,lit.a} }
			if e.hurt_time > 0 { lit = {180,224,255,255} }
			push_sprite(list, eye, Sprite_Draw{sprite=id,frame=frame,center=center,size=size,tint=lit,flip=flip,
				figure=true,figure_index=figure_index,pose=pose})
		} else {
			push_sprite(list, eye, Sprite_Draw{sprite=id,frame=frame,center=center,size=size,tint=lit,flip=flip})
		}
	}
	for i in 0..<w.pickup_count {
		pk := w.pickups[i]
		if pk.taken {
			continue
		}
		bob := math.sin(v.time*2.2+pk.phase) * 0.08
		switch pk.kind {
		case .Rune:
			// Fake spin: the tablet narrows and shows its plain back half the time.
			spin := math.cos(v.time*2 + pk.phase)
			center := pk.position + Vec3{0, 1.05 + bob, 0}
			size := Vec2{0.72 * max(abs(spin), 0.08), 0.96}
			frame := 0 if spin >= 0 else 1
			push_sprite(list, eye, Sprite_Draw{sprite = .Rune, frame = frame, center = center, size = size,
				tint = rl.Color{255, 250, 240, 255}})
		case .Health:
			center, size := standing(v, .Health, pk.position+Vec3{0, 0.15 + bob, 0}, 0.55)
			push_sprite(list, eye, Sprite_Draw{sprite = .Health, center = center, size = size, tint = light_at(v, center, {255, 230, 230, 255})})
		case .Mana:
			center, size := standing(v, .Mana, pk.position+Vec3{0, 0.15 + bob, 0}, 0.55)
			push_sprite(list, eye, Sprite_Draw{sprite = .Mana, center = center, size = size, tint = light_at(v, center, {230, 235, 255, 255})})
		}
	}
	for i in 0..<v.decor_count {
		d := v.decor[i]
		delta := d.position - eye
		if delta.x*delta.x+delta.z*delta.z > FOG_FAR*FOG_FAR {
			continue
		}
		switch d.kind {
		case .Candle:
			center, size := standing(v, .Candle, d.position, 0.32)
			push_sprite(list, eye, Sprite_Draw{sprite = .Candle, center = center, size = size, tint = light_at(v, center, {255, 240, 220, 255})})
			flame := int(v.time*8+d.phase) % 2
			fc, fs := standing(v, .Flame, d.position+Vec3{0, 0.27, 0}, 0.16)
			push_sprite(list, eye, Sprite_Draw{sprite = .Flame, frame = flame, center = fc, size = fs, tint = rl.WHITE})
		case .Skull:
			center, size := standing(v, .Skull, d.position, 0.26)
			push_sprite(list, eye, Sprite_Draw{sprite = .Skull, center = center, size = size, tint = light_at(v, center)})
		case .Bones:
			center, size := standing(v, .Bones, d.position, 0.18)
			push_sprite(list, eye, Sprite_Draw{sprite = .Bones, center = center, size = size, tint = light_at(v, center)})
		case .Brazier:
			center, size := standing(v, .Brazier, d.position, 1.0)
			push_sprite(list, eye, Sprite_Draw{sprite = .Brazier, center = center, size = size, tint = light_at(v, center)})
			flame := int(v.time*7+d.phase) % 2
			fc, fs := standing(v, .Flame, d.position+Vec3{0, 0.92, 0}, 0.7)
			push_sprite(list, eye, Sprite_Draw{sprite = .Flame, frame = flame, center = fc, size = fs, tint = rl.WHITE})
		}
	}
}

@(private)
draw_sprite_list :: proc(v: ^View, list: ^Draw_List, cam: rl.Camera3D) {
	// Far to near, so translucent wraiths blend over what is behind them.
	items := list.items[:list.count]
	for i in 1..<len(items) {
		item := items[i]
		j := i - 1
		for j >= 0 && items[j].dist < item.dist {
			items[j+1] = items[j]
			j -= 1
		}
		items[j+1] = item
	}
	// Sorted cutouts still test against world depth, but must not write it.
	// A detached paper border can otherwise occlude its own illustration when
	// the camera pitches and the two billboard layers cease to be coplanar.
	rlgl.DrawRenderBatchActive()
	rlgl.DisableDepthMask()
	defer { rlgl.DrawRenderBatchActive(); rlgl.EnableDepthMask() }
	if v.sprite_ok {
		view_pos := Vec3(cam.position)
		rl.SetShaderValue(v.sprite_shader, v.loc_view, &view_pos, .VEC3)
		fog := [4]f32{f32(FOG_COLOR.r) / 255, f32(FOG_COLOR.g) / 255, f32(FOG_COLOR.b) / 255, 1}
		rl.SetShaderValue(v.sprite_shader, v.loc_fog_color, &fog, .VEC4)
		fog_range := [2]f32{FOG_NEAR, FOG_FAR}
		rl.SetShaderValue(v.sprite_shader, v.loc_fog_range, &fog_range, .VEC2)
		rl.BeginShaderMode(v.sprite_shader)
	}
	for item in items {
		if item.book {
			// Paper first in its own shader (fog arrives through the tint),
			// then the print back under the fogged sprite shader.
			book := &v.books[item.book_index]
			print, row, frame := gfx.flipbook_billboard_quad(cam, book, item.feet, item.height, item.flip, f64(v.time))
			paper := gfx.flipbook_turn_page(&book.page, &v.book, book.character, row, frame, f64(v.time))
			gfx.draw_flipbook_paper(&v.book, book.character, print, paper, item.flip, f32(item.tint.a)/255,
				{item.tint.r, item.tint.g, item.tint.b, 255})
			if v.sprite_ok { rl.BeginShaderMode(v.sprite_shader) }
			gfx.draw_flipbook_print(&v.book, book.character, print, row, frame, item.flip, item.tint)
			continue
		}
		if item.figure {
			source := gfx.paper_figure_source(&v.figures,item.figure_index,item.flip)
			// Two independent layers: the border holds its pose, the drawing steps.
			border_tint:=rl.Color{218,225,237,item.tint.a}
			border_center:=item.center+Vec3{0,-item.pose*0.012,0}
			rl.DrawBillboardPro(cam,v.figures.border,source,border_center,{0,1,0},item.size,item.size*0.5,0,border_tint)
			rl.DrawBillboardPro(cam,v.figures.texture,source,item.center,{0,1,0},item.size,item.size*0.5,0,item.tint)
			continue
		}
		s := v.sprites[item.sprite]
		if s.texture.id == 0 {
			continue
		}
		src := gfx.sprite_source(s, item.frame, item.flip)
		rl.DrawBillboardPro(cam, s.texture, src, item.center, {0, 1, 0}, item.size, item.size*0.5, 0, item.tint)
	}
	if v.sprite_ok {
		rl.EndShaderMode()
	}
}

@(private)
fog_fade :: proc(eye, p: Vec3) -> f32 {
	d := physics.length3(p - eye)
	return 1 - clamp((d-FOG_NEAR)/(FOG_FAR-FOG_NEAR), 0, 1)
}

@(private)
glow :: proc(v: ^View, cam: rl.Camera3D, p: Vec3, size: f32, color: rl.Color) {
	c := color
	c.a = u8(f32(c.a) * fog_fade(Vec3(cam.position), p))
	if c.a == 0 {
		return
	}
	src := rl.Rectangle{0, 0, f32(v.glow.width), f32(v.glow.height)}
	rl.DrawBillboardPro(cam, v.glow, src, p, {0, 1, 0}, {size, size}, {size * 0.5, size * 0.5}, 0, c)
}

// Additive light sources over the scene, without writing depth.
@(private)
draw_glows :: proc(g: ^Game, cam: rl.Camera3D) {
	w := &g.world
	v := &g.view
	rlgl.DrawRenderBatchActive()
	rlgl.DisableDepthMask()
	rl.BeginBlendMode(.ADDITIVE)
	for t in v.trails {
		if t.life <= 0 {
			continue
		}
		c := t.color
		c.a = u8(255 * t.life)
		rl.DrawCylinderEx(t.from, t.to, 0.006+0.01*t.life, 0.015+0.03*t.life, 5, c)
		glow(v, cam, t.to, 0.6*t.life+0.2, {139, 207, 252, u8(190 * t.life)})
	}
	for pr in w.projectiles {
		if !pr.alive {
			continue
		}
		glow(v, cam, pr.position, 1.1, {230, 55, 80, 230})
		glow(v, cam, pr.position, 0.45, {255, 215, 216, 255})
	}
	for i in 0..<w.pickup_count {
		pk := w.pickups[i]
		if pk.taken {
			continue
		}
		pulse := 0.85 + 0.15*math.sin(v.time*3+pk.phase)
		switch pk.kind {
		case .Rune:
			// Soft halo, a pool on the floor and a faint shaft of light up to
			// the vault, so runes can be spotted down a corridor.
			glow(v, cam, pk.position+Vec3{0, 1.05, 0}, 2.6*pulse, {255, 150, 60, 70})
			glow(v, cam, pk.position+Vec3{0, 0.05, 0}, 1.4, {255, 150, 60, 90})
			for k in 0..<7 {
				glow(v, cam, pk.position+Vec3{0, 0.3 + f32(k)*0.5, 0}, 0.55, {255, 190, 110, 34})
			}
		case .Health:
			glow(v, cam, pk.position+Vec3{0, 0.4, 0}, 0.8*pulse, {255, 60, 60, 110})
		case .Mana:
			glow(v, cam, pk.position+Vec3{0, 0.4, 0}, 0.8*pulse, {80, 120, 255, 120})
		}
	}
	for i in 0..<w.enemy_count {
		e := w.enemies[i]
		if e.state == .Windup && e.kind == .Cultist {
			k := clamp(e.state_time/enemy_params(e.kind).windup, 0, 1)
			glow(v, cam, enemy_feet(e)+Vec3{0, 1.95, 0}, 0.4+0.7*k, {231, 58, 83, 230})
		}
		if e.state == .Windup && e.kind == .Wraith {
			glow(v, cam, enemy_eye(e), 0.9, {146, 206, 246, 160})
		}
	}
	for i in 0..<v.decor_count {
		d := v.decor[i]
		flicker := 0.85 + 0.15*math.sin(v.time*11+d.phase)
		#partial switch d.kind {
		case .Candle:
			glow(v, cam, d.position+Vec3{0, 0.36, 0}, 0.55*flicker, {255, 160, 70, 130})
		case .Brazier:
			glow(v, cam, d.position+Vec3{0, 1.25, 0}, 2.2*flicker, {255, 130, 50, 150})
		}
	}
	draw_portal(g, cam)
	rl.EndBlendMode()
	rlgl.DrawRenderBatchActive()
	rlgl.EnableDepthMask()
}

// The portal: a ring of motes spinning in the plane of the arch. Sealed, it
// is a faint dull membrane; open, a bright blue vortex.
@(private)
draw_portal :: proc(g: ^Game, cam: rl.Camera3D) {
	w := &g.world
	v := &g.view
	c := w.portal.center
	if !w.portal.open {
		// The seal: one point per rune on a slowly turning ring, lit as the
		// runes are found, so the arch itself shows what is missing.
		glow(v, cam, c, 1.8, {49, 89, 138, 70})
		count := max(w.rune_count, 1)
		for i in 0..<count {
			a := v.time*0.35 + f32(i)*math.TAU/f32(count) + math.PI/2
			p := c + Vec3{math.cos(a) * 0.7, math.sin(a) * 1.1, 0}
			if i < w.runes_taken {
				pulse := 0.85 + 0.15*math.sin(v.time*5+f32(i))
				glow(v, cam, p, 0.6*pulse, {255, 180, 80, 230})
				glow(v, cam, p, 0.25, {255, 240, 200, 255})
			} else {
				glow(v, cam, p, 0.38, {74, 111, 155, 120})
			}
		}
		return
	}
	k := clamp(w.portal.open_time*1.5, 0, 1)
	glow(v, cam, c, 2.6*k, {77, 150, 219, 130})
	glow(v, cam, c, 0.9*k, {201, 232, 255, 150})
	for ring in 0..<3 {
		radius := (0.35 + f32(ring)*0.28) * k
		count := 10 + ring*4
		speed := f32(2.4) - f32(ring)*0.6
		for i in 0..<count {
			a := v.time*speed + f32(i)*math.TAU/f32(count) + f32(ring)
			p := c + Vec3{math.cos(a) * radius, math.sin(a) * radius * 1.4, 0}
			glow(v, cam, p, 0.26, {134, 205, 255, 170})
		}
	}
}

// Flush inlays follow solid faces: decoration never suggests a new platform
// or a collision volume. Only nearby faces are submitted to the renderer.
@(private)
draw_haunted_house :: proc(g: ^Game, eye: Vec3) {
	w := &g.world
	for z in max(0,int(eye.z)-13)..<min(w.side,int(eye.z)+14) {
		for x in max(0,int(eye.x)-13)..<min(w.side,int(eye.x)+14) {
			if !walkable_xz(w,x,z) { continue }
			// Flush floorboards: unchanged walking and projectile volumes.
			for n in 0..<4 {
				rl.DrawCube({f32(x)+f32(n)*.25,FLOOR_Y+.006,f32(z)+.5},.012,.008,1,{47,36,41,255})
			}
			for direction in ([4][2]int{{1,0},{-1,0},{0,1},{0,-1}}) {
				if walkable_xz(w,x+direction.x,z+direction.y) { continue }
				p:=Vec3{f32(x)+.5+f32(direction.x)*.487,FLOOR_Y,f32(z)+.5+f32(direction.y)*.487}
				tangent:=Vec3{-f32(direction.y),0,f32(direction.x)}
				face :: proc(p,tangent:Vec3,along,high:f32,c:rl.Color) {
					rl.DrawCube(p,.027 if tangent.x==0 else along,high,along if tangent.x==0 else .027,c)
				}
				face(p+{0,.67,0},tangent,1,1.22,{64,48,50,255})
				for n in 0..<4 {face(p+tangent*(f32(n)*.25-.375)+{0,.65,0},tangent,.022,1.10,{108,83,77,255})}
				for y in ([3]f32{.13,1.30,2.68}) {face(p+{0,y,0},tangent,1,.065,{150,123,106,255})}
				if (x*3+z*5)%5!=0 {continue}
				// Uneven ancestral portraits, mounted flat against existing walls.
				q:=p-Vec3{f32(direction.x)*.022,0,f32(direction.y)*.022}+{0,2.01,0}
				face(q,tangent,.68,.94,{183,143,96,255})
				q-=Vec3{f32(direction.x)*.018,0,f32(direction.y)*.018}
				face(q,tangent,.56,.82,{26,34,45,255})
				q-=Vec3{f32(direction.x)*.018,0,f32(direction.y)*.018}
				face(q+{0,-.13,0},tangent,.34,.34,{67,67,78,255})
				face(q+{0,.14,0},tangent,.22,.28,{137,147,145,255})
				for sign in ([2]f32{-1,1}) {face(q+tangent*(sign*.055)+{0,.18,0},tangent,.027,.035,{153,235,214,255})}
			}
		}
	}
}

@(private)
draw_enemy_ground_feedback :: proc(g: ^Game, eye: Vec3) {
	w:=&g.world
	for enemy in w.enemies[:w.enemy_count] {
		if enemy.state==.Dead { continue }
		feet:=enemy_feet(enemy)
		if physics.length3(feet-eye)>FOG_FAR { continue }
		gfx.draw_blob_shadow(feet,0.38,0.60*fog_fade(eye,feet))
		if enemy.state!=.Windup { continue }
		params:=enemy_params(enemy.kind)
		progress:=clamp(enemy.state_time/params.windup,0,1)
		p:=feet+Vec3{0,0.037,0}
		color:=rl.Color{222,55,79,u8(210*fog_fade(eye,p))}
		// The closing ring is a timing tell, not a promise about hit volume.
		radius:=0.58-progress*0.16
		rl.DrawCircle3D(p,radius,{1,0,0},90,color)
		rl.DrawCircle3D(p,0.40,{1,0,0},90,{111,32,48,color.a})
		facing:=Vec3{enemy.facing.x,0,enemy.facing.y}
		rl.DrawLine3D(p+facing*0.45,p+facing*(0.75+progress*0.22),color)
	}
}

view_draw :: proc(g: ^Game, frame: ^host.Frame) {
	v := &g.view
	cam := view_camera(g)
	eye := Vec3(cam.position)
	choose_light(g, eye)
	rl.BeginMode3D(cam)
	gfx.lighting_update(&v.lighting, eye)
	if v.has_model {
		rl.DrawModel(v.model, {}, 1, rl.WHITE)
	}
	draw_haunted_house(g,eye)
	draw_enemy_ground_feedback(g,eye)
	list := new(Draw_List, context.temp_allocator)
	collect_sprites(g, list, cam)
	draw_sprite_list(v, list, cam)
	fx.draw3d(&v.particles)
	draw_glows(g, cam)
	rl.EndMode3D()
	draw_hud(g, frame, cam)
}

// Drives an enemy standee from its brain state: the chase strides, the
// wind-up telegraphs, the strike lands on its impact drawing, a hit flinches
// and death crumples the print before the card fades.
@(private)
fps_update_book :: proc(v: ^View, index: int, e: Enemy) {
	now := f64(v.time)
	book := &v.books[index]
	character := gfx.Flipbook_Character.Ghoul
	if e.kind == .Wraith { character = .Archmage }
	if e.kind == .Cultist { character = .Bishop }
	if book.character != character || v.book_kinds[index] != e.kind || (e.state != .Dead && book.action == .Death) {
		book^ = gfx.flipbook_player(character, f64(e.phase))
		v.book_kinds[index] = e.kind
		v.book_states[index] = .Idle
	}
	switch e.state {
	case .Idle: gfx.flipbook_loop(book, .Idle, now)
	case .Chase: gfx.flipbook_loop(book, .Walk, now)
	case .Windup: gfx.flipbook_loop(book, .Windup, now)
	case .Recover: gfx.flipbook_loop(book, .Stunned, now)
	case .Strike:
		if v.book_states[index] != .Strike { gfx.flipbook_play(book, .Attack, now, true) }
	case .Dead:
		if v.book_states[index] != .Dead { gfx.flipbook_play(book, .Death, now) }
	}
	hurt := e.hurt_time > 0 && e.state != .Dead
	if hurt && !v.book_hurt[index] { gfx.flipbook_play(book, .Hurt, now) }
	v.book_hurt[index] = hurt
	v.book_states[index] = e.state
}
