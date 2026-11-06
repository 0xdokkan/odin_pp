package render

import "base:runtime"
import "core:math"
import "core:sync"
import "core:time"
import rl "vendor:raylib"
import gfx "../engine/gfx"

// The lab prints the actual game's procedural actors on its folded sheet.
// One process-owned immutable CPU cache serves geometry, tests and GPU uploads;
// each live lab context owns exactly one texture, uploaded once on creation.
PAGE_LAB_PRINT_FRAMES :: 12
PAGE_LAB_PRINT_COLUMNS :: 12
PAGE_LAB_PRINT_ACTORS :: 3
PAGE_LAB_PRINT_CLIPS :: 3
PAGE_LAB_PRINT_WIDTH :: CARTOON_CELL*PAGE_LAB_PRINT_COLUMNS
PAGE_LAB_PRINT_HEIGHT :: CARTOON_CELL*9
PAGE_LAB_PRINT_BYTES :: PAGE_LAB_PRINT_WIDTH*PAGE_LAB_PRINT_HEIGHT*4
PAGE_LAB_PRINT_HERO_SCALE :: f32(1.4)
PAGE_LAB_PRINT_ENEMY_SCALE :: f32(1.5)
// The paper fragment program uses the production raster's pixel coordinates.
#assert(CARTOON_CELL == 104 && CARTOON_PIXELS == 60 && CARTOON_FEET == 102)
@(private) PAGE_LAB_PRINT_HERO :: 0
@(private) PAGE_LAB_PRINT_ENEMY :: 1
@(private) PAGE_LAB_PRINT_MOUNTED :: 2

@(private)
Page_Lab_Print_Clip :: enum { Idle, Walk, Death }

@(private)
Page_Lab_Print_Cache :: struct {
	pixels: [PAGE_LAB_PRINT_WIDTH*PAGE_LAB_PRINT_HEIGHT]rl.Color,
	ink, masks: [PAGE_LAB_PRINT_ACTORS][CARTOON_CELL*CARTOON_CELL]u8,
	build_ms: f64,
}

@(private)
page_lab_print_once: sync.Once
@(private)
page_lab_print_cache: ^Page_Lab_Print_Cache

@(private)
Page_Lab_Print_Assets :: struct {
	atlas: rl.Texture2D,
	uploads: u64,
	init_ms: f64,
	origin_location, scale_location, frame_location, enabled_location, stock_location: i32,
}

@(private)
Page_Lab_Print_Sample :: struct {
	actor, frame: int,
	clip: Page_Lab_Print_Clip,
	origin: rl.Vector2,
	scale, lift: f32,
	valid: bool,
}

@(private)
page_lab_print_art :: proc(actor: int, clip: Page_Lab_Print_Clip, frame: int) -> Expedition_Paper {
	action := gfx.Living_Action.Idle
	switch clip {
	case .Idle:
	case .Walk: action = .Move_Side
	case .Death:
		// The physical sheet owns the fall. The production Death drawing also
		// squashes/shears the body, which would make it collapse twice here.
		// Keep the original upright anatomy and reuse its hurt-eye expression.
		if frame >= 3 { action = .Hurt }
	}
	progress := f32(frame)/f32(PAGE_LAB_PRINT_FRAMES)
	art: Expedition_Paper
	if actor == PAGE_LAB_PRINT_ENEMY {
		art = expedition_cyber_actor_art(.Brute, progress*2.4, action, progress)
	} else {
		art = expedition_robot_art(progress*2.4, action, progress, actor == PAGE_LAB_PRINT_MOUNTED)
	}
	// Blinks and dying eyes belong to the print. The page owns the body's pose.
	// Cyan eyes are authored polygons in the original art; antennae are higher.
	blink := clip == .Idle && frame == 10
	dying_blink := clip == .Death && frame > 0 && frame < 3
	foe_dead_eyes := clip == .Death && frame >= 3 && actor == PAGE_LAB_PRINT_ENEMY
	if blink || dying_blink || foe_dead_eyes {
		for &part in art.parts[:art.count] {
			cyan := part.color == (rl.Color{31,233,245,255}) || part.color == (rl.Color{29,235,245,255})
			if !cyan && !(foe_dead_eyes && part.color == EXPEDITION_PAPER_EDGE) { continue }
			low, high := max(f32), -max(f32)
			for p in part.points[:part.count] { low = min(low, p.y); high = max(high, p.y) }
			if low < .88 || high > 1.12 { continue }
			middle := (low+high)*.5
			opening := f32(.55) if dying_blink && frame == 1 else .14
			for &p in part.points[:part.count] { p.y = middle+(p.y-middle)*opening }
		}
	}
	return art
}

@(private)
page_lab_print_tile :: proc(actor: int, clip: Page_Lab_Print_Clip, frame: int) -> [2]int {
	index := (actor*PAGE_LAB_PRINT_CLIPS+int(clip))*PAGE_LAB_PRINT_FRAMES+frame
	return {index%PAGE_LAB_PRINT_COLUMNS*CARTOON_CELL, index/PAGE_LAB_PRINT_COLUMNS*CARTOON_CELL}
}

@(private)
page_lab_print_make_cache :: proc() {
	started := time.now()
	cache := new(Page_Lab_Print_Cache, runtime.heap_allocator())
	for actor in 0..<PAGE_LAB_PRINT_ACTORS {
		for clip in Page_Lab_Print_Clip { for frame in 0..<PAGE_LAB_PRINT_FRAMES {
			art := page_lab_print_art(actor, clip, frame)
			drawing := cartoon_raster(&art)
			tile := page_lab_print_tile(actor, clip, frame)
			for pixel, i in drawing {
				x, y := i%CARTOON_CELL, i/CARTOON_CELL
				cache.pixels[(tile.y+y)*PAGE_LAB_PRINT_WIDTH+tile.x+x] = pixel
				if pixel.a > 0 { cache.ink[actor][i] = 1 }
			}
		} }
		// Six source pixels of real cardboard beyond every animated ink contour.
		// At the last five rows, two separate sole windows preserve page hinges.
		for y in 0..<int(CARTOON_FEET) { for x in 0..<CARTOON_CELL {
			covered := false
			for dy in -6..=6 { for dx in -6..=6 {
				if dx*dx+dy*dy > 36 { continue }
				px, py := x+dx, y+dy
				if px < 0 || py < 0 || px >= CARTOON_CELL || py >= CARTOON_CELL { continue }
				covered = covered || cache.ink[actor][py*CARTOON_CELL+px] != 0
			} }
			if y >= int(CARTOON_FEET)-5 && actor != PAGE_LAB_PRINT_MOUNTED {
				local_x := abs((f32(x)+.5-CARTOON_CELL*.5)/CARTOON_PIXELS)
				inner := f32(.075) if actor == PAGE_LAB_PRINT_HERO else .10
				outer := f32(.36) if actor == PAGE_LAB_PRINT_HERO else .46
				covered = covered && local_x >= inner && local_x <= outer
			}
			if covered { cache.masks[actor][y*CARTOON_CELL+x] = 1 }
		} }
		// Like the production stock, only the sole boundary constrains moving ink.
		// Heads and arms use the union of all frames and never lose their drawing.
		for clip in Page_Lab_Print_Clip { for frame in 0..<PAGE_LAB_PRINT_FRAMES {
			tile := page_lab_print_tile(actor, clip, frame)
			for y in 0..<CARTOON_CELL { for x in 0..<CARTOON_CELL {
				if cache.masks[actor][y*CARTOON_CELL+x] == 0 {
					cache.pixels[(tile.y+y)*PAGE_LAB_PRINT_WIDTH+tile.x+x] = {}
				}
			} }
		} }
	}
	cache.build_ms = time.duration_seconds(time.since(started))*1000
	page_lab_print_cache = cache
}

@(private)
page_lab_print_cpu :: proc() -> ^Page_Lab_Print_Cache {
	sync.once_do(&page_lab_print_once, page_lab_print_make_cache)
	return page_lab_print_cache
}

@(private)
page_lab_print_sample :: proc(pose: Page_Lab_Pose, surface: Page_Lab_Surface, clock: f32) -> (sample: Page_Lab_Print_Sample) {
	if surface != .Hero && surface != .Enemy { return }
	sample.valid = true
	anchor := page_lab_origin(pose, surface)
	sample.origin = {anchor.x, anchor.z}
	sample.scale = PAGE_LAB_PRINT_HERO_SCALE
	if surface == .Enemy { sample.actor = PAGE_LAB_PRINT_ENEMY; sample.scale = PAGE_LAB_PRINT_ENEMY_SCALE }
	if surface == .Hero {
		switch pose.act {
		case .Walk, .Turn, .Climb: sample.clip = .Walk
		case .Death: sample.clip = .Death
		case .Mount: sample.actor = PAGE_LAB_PRINT_MOUNTED; sample.lift = .25
		case .Still, .Arrow, .Bomb, .Flight:
		}
	}
	seconds := max(clock, 0)
	if math.is_nan(seconds) || math.is_inf(seconds) { seconds = 0 }
	if sample.clip == .Death {
		sample.frame = clamp(int(clamp(pose.time/3, 0, 1)*f32(PAGE_LAB_PRINT_FRAMES-1)), 0, PAGE_LAB_PRINT_FRAMES-1)
	} else {
		period := f32(.8) if sample.clip == .Walk else 2.4
		sample.frame = clamp(int(math.mod(seconds, period)/period*PAGE_LAB_PRINT_FRAMES), 0, PAGE_LAB_PRINT_FRAMES-1)
	}
	return
}

@(private)
page_lab_print_source_pixel :: proc(sample: Page_Lab_Print_Sample, point: rl.Vector2) -> rl.Vector2 {
	local := rl.Vector2{(point.x-sample.origin.x)/sample.scale, (sample.origin.y-point.y-sample.lift)/sample.scale}
	return {CARTOON_CELL*.5+local.x*CARTOON_PIXELS, CARTOON_FEET-local.y*CARTOON_PIXELS}
}

@(private)
page_lab_print_contains :: proc(pose: Page_Lab_Pose, surface: Page_Lab_Surface, point: rl.Vector2) -> bool {
	sample := page_lab_print_sample(pose, surface, 0)
	if !sample.valid { return false }
	p := page_lab_print_source_pixel(sample, point)
	x, y := int(math.floor(p.x)), int(math.floor(p.y))
	if x < 0 || y < 0 || x >= CARTOON_CELL || y >= int(CARTOON_FEET) { return false }
	return page_lab_print_cpu().masks[sample.actor][y*CARTOON_CELL+x] != 0
}

@(private)
page_lab_print_upload :: proc(assets: ^Page_Lab_Print_Assets, shader: rl.Shader) -> bool {
	cache := page_lab_print_cpu()
	started := rl.GetTime()
	image := rl.Image{data = raw_data(cache.pixels[:]), width = PAGE_LAB_PRINT_WIDTH, height = PAGE_LAB_PRINT_HEIGHT,
		mipmaps = 1, format = .UNCOMPRESSED_R8G8B8A8}
	assets.atlas = rl.LoadTextureFromImage(image)
	if assets.atlas.id == 0 { return false }
	rl.SetTextureFilter(assets.atlas, .POINT)
	rl.SetTextureWrap(assets.atlas, .CLAMP)
	assets.uploads += 1
	assets.init_ms = (rl.GetTime()-started)*1000+cache.build_ms
	assets.origin_location = rl.GetShaderLocation(shader, "printOrigin")
	assets.scale_location = rl.GetShaderLocation(shader, "printScaleLift")
	assets.frame_location = rl.GetShaderLocation(shader, "printFrame")
	assets.enabled_location = rl.GetShaderLocation(shader, "printEnabled")
	assets.stock_location = rl.GetShaderLocation(shader, "paperStock")
	return true
}
