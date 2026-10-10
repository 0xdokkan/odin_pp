// Particles and transient feedback (popups, flashes). Simulation is pure and
// allocation-free; drawing procedures use raylib.
package fx

import "core:math"
import rl "vendor:raylib"
import rng "../rng"

Vec2 :: [2]f32
Vec3 :: [3]f32

Particle :: struct {
	position:   Vec3,
	velocity:   Vec3,
	life:       f32,
	max_life:   f32,
	size_start: f32,
	size_end:   f32,
	color_start: rl.Color,
	color_end:  rl.Color,
	gravity:    f32,
	drag:       f32,
	spin:       f32,
	angle:      f32,
}

// Fixed-capacity system; when full, the oldest particle slot is reused.
Particles :: struct($N: int) {
	items:  [N]Particle,
	count:  int,
	cursor: int,
}

Emitter :: struct {
	speed_min, speed_max: f32,
	// Emission direction and cone half-angle (radians). In 2D only x/y are used.
	direction:  Vec3,
	spread:     f32,
	life_min, life_max: f32,
	size_start, size_end: f32,
	color_start, color_end: rl.Color,
	gravity:    f32,
	drag:       f32,
	spin:       f32,
	// Positions are jittered within this radius.
	radius:     f32,
	three_d:    bool,
}

BURST :: Emitter{
	speed_min = 40, speed_max = 140, direction = {0, -1, 0}, spread = math.PI,
	life_min = 0.25, life_max = 0.6, size_start = 4, size_end = 0,
	color_start = {255, 230, 160, 255}, color_end = {200, 60, 40, 0}, gravity = 200, drag = 2,
}

DUST :: Emitter{
	speed_min = 10, speed_max = 50, direction = {0, -1, 0}, spread = 1.2,
	life_min = 0.2, life_max = 0.45, size_start = 3, size_end = 0,
	color_start = {200, 190, 170, 200}, color_end = {200, 190, 170, 0}, gravity = -20, drag = 4,
}

SPARKS :: Emitter{
	speed_min = 120, speed_max = 260, direction = {0, -1, 0}, spread = math.PI,
	life_min = 0.1, life_max = 0.3, size_start = 2, size_end = 0,
	color_start = {255, 255, 220, 255}, color_end = {255, 140, 40, 0}, gravity = 300, drag = 1,
}

emit :: proc(p: ^Particles($N), e: Emitter, origin: Vec3, count: int, r: ^rng.Rng) {
	base := normalize(e.direction)
	for _ in 0..<count {
		dir: Vec3
		if e.three_d {
			// Random direction inside a cone around base.
			for {
				v := Vec3{rng.float_signed(r), rng.float_signed(r), rng.float_signed(r)}
				l := v.x*v.x + v.y*v.y + v.z*v.z
				if l > 0.0001 && l <= 1 {
					v /= math.sqrt(l)
					if dot(v, base) >= math.cos(e.spread) || e.spread >= math.PI {
						dir = v
						break
					}
				}
			}
		} else {
			angle := math.atan2(base.y, base.x) + rng.float_signed(r)*e.spread
			dir = Vec3{math.cos(angle), math.sin(angle), 0}
		}
		jitter: Vec3
		if e.radius > 0 && e.three_d {
			for {
				v := Vec3{rng.float_signed(r), rng.float_signed(r), rng.float_signed(r)}
				if v.x*v.x+v.y*v.y+v.z*v.z <= 1 {
					jitter = v * e.radius
					break
				}
			}
		} else if e.radius > 0 {
			d := rng.unit_disc(r) * e.radius
			jitter = Vec3{d.x, d.y, 0}
		}
		life := rng.float_range(r, e.life_min, max(e.life_max, e.life_min))
		spawn(p, Particle{
			position    = origin + jitter,
			velocity    = dir * rng.float_range(r, e.speed_min, max(e.speed_max, e.speed_min)),
			life        = life,
			max_life    = life,
			size_start  = e.size_start,
			size_end    = e.size_end,
			color_start = e.color_start,
			color_end   = e.color_end,
			gravity     = e.gravity,
			drag        = e.drag,
			spin        = e.spin * rng.float_signed(r),
		})
	}
}

spawn :: proc(p: ^Particles($N), particle: Particle) {
	if p.count < N {
		p.items[p.count] = particle
		p.count += 1
		return
	}
	p.items[p.cursor] = particle
	p.cursor = (p.cursor + 1) % N
}

// Gravity pulls toward +y in 2D (screen down) and -y in 3D; set per emitter.
update :: proc(p: ^Particles($N), dt: f32, three_d := false) {
	i := 0
	for i < p.count {
		q := &p.items[i]
		q.life -= dt
		if q.life <= 0 {
			p.count -= 1
			p.items[i] = p.items[p.count]
			continue
		}
		g := Vec3{0, -q.gravity, 0} if three_d else Vec3{0, q.gravity, 0}
		q.velocity += g * dt
		q.velocity *= max(1-q.drag*dt, 0)
		q.position += q.velocity * dt
		q.angle += q.spin * dt
		i += 1
	}
	if p.cursor >= p.count {
		p.cursor = 0
	}
}

clear :: proc(p: ^Particles($N)) {
	p.count = 0
	p.cursor = 0
}

particle_progress :: proc "contextless" (q: Particle) -> f32 {
	if q.max_life <= 0 {
		return 1
	}
	return 1 - q.life/q.max_life
}

particle_color :: proc "contextless" (q: Particle) -> rl.Color {
	t := particle_progress(q)
	return rl.Color{
		u8(f32(q.color_start.r) + (f32(q.color_end.r)-f32(q.color_start.r))*t),
		u8(f32(q.color_start.g) + (f32(q.color_end.g)-f32(q.color_start.g))*t),
		u8(f32(q.color_start.b) + (f32(q.color_end.b)-f32(q.color_start.b))*t),
		u8(f32(q.color_start.a) + (f32(q.color_end.a)-f32(q.color_start.a))*t),
	}
}

particle_size :: proc "contextless" (q: Particle) -> f32 {
	t := particle_progress(q)
	return q.size_start + (q.size_end-q.size_start)*t
}

draw2d :: proc(p: ^Particles($N)) {
	for i in 0..<p.count {
		q := p.items[i]
		s := particle_size(q)
		if s <= 0.1 {
			continue
		}
		rl.DrawRectanglePro({q.position.x, q.position.y, s, s}, {s * 0.5, s * 0.5}, q.angle*180/math.PI, particle_color(q))
	}
}

// 3D particles as small camera-independent cubes (no texture needed).
draw3d :: proc(p: ^Particles($N)) {
	for i in 0..<p.count {
		q := p.items[i]
		s := particle_size(q)
		if s <= 0.001 {
			continue
		}
		rl.DrawCube(q.position, s, s, s, particle_color(q))
	}
}

@(private)
normalize :: proc "contextless" (v: Vec3) -> Vec3 {
	l := math.sqrt(v.x*v.x + v.y*v.y + v.z*v.z)
	if l < 1e-5 {
		return {0, -1, 0}
	}
	return v / l
}

@(private)
dot :: proc "contextless" (a, b: Vec3) -> f32 {
	return a.x*b.x + a.y*b.y + a.z*b.z
}

// Rising, fading text such as "+10" or "CRITICO".
Popup :: struct {
	position: Vec2,
	text:     string,
	color:    rl.Color,
	life:     f32,
	max_life: f32,
}

Popups :: struct($N: int) {
	items: [N]Popup,
	count: int,
}

// `text` must outlive the popup: use literals or a persistent allocator.
popup :: proc(p: ^Popups($N), position: Vec2, text: string, color: rl.Color, life: f32 = 0.8) {
	if p.count >= N {
		for i in 1..<N {
			p.items[i-1] = p.items[i]
		}
		p.count = N - 1
	}
	p.items[p.count] = Popup{position = position, text = text, color = color, life = life, max_life = life}
	p.count += 1
}

popups_update :: proc(p: ^Popups($N), dt: f32) {
	i := 0
	for i < p.count {
		q := &p.items[i]
		q.life -= dt
		q.position.y -= 30 * dt
		if q.life <= 0 {
			for j in i+1..<p.count {
				p.items[j-1] = p.items[j]
			}
			p.count -= 1
			continue
		}
		i += 1
	}
}

// Full-screen colour flash that fades out (damage, pickups).
Flash :: struct {
	color:    rl.Color,
	time:     f32,
	duration: f32,
}

flash_start :: proc(f: ^Flash, color: rl.Color, duration: f32 = 0.2) {
	f^ = Flash{color = color, time = duration, duration = duration}
}

flash_update :: proc(f: ^Flash, dt: f32) {
	f.time = max(f.time-dt, 0)
}

flash_draw :: proc(f: Flash, width, height: f32) {
	if f.time <= 0 || f.duration <= 0 {
		return
	}
	a := f.time / f.duration
	c := f.color
	c.a = u8(f32(c.a) * a)
	rl.DrawRectangleRec({0, 0, width, height}, c)
}

// Brief freeze on impact; callers skip simulation while `active`.
Hit_Stop :: struct {
	remaining: f32,
}

hit_stop :: proc(h: ^Hit_Stop, seconds: f32) {
	h.remaining = max(h.remaining, seconds)
}

// Returns the dt the simulation should use this frame (0 while frozen).
hit_stop_filter :: proc(h: ^Hit_Stop, dt: f32) -> f32 {
	if h.remaining <= 0 {
		return dt
	}
	h.remaining -= dt
	if h.remaining < 0 {
		leftover := -h.remaining
		h.remaining = 0
		return leftover
	}
	return 0
}
