package run

import "core:fmt"
import "core:math"
import "core:os"
import "core:slice"
import "core:time"
import rl "vendor:raylib"
import artifacts "../devtools/artifacts"
import host "../engine/host"
import input "../engine/input"
import ui "../engine/ui"
import render "../render"

@(private)
PAGE_LAB_BENCHMARK :: #config(PAGE_LAB_BENCHMARK, false)
@(private)
PAGE_LAB_WARMUP :: 60
@(private)
PAGE_LAB_SAMPLES :: 600
@(private)
Page_Lab_Camera :: enum { Expedition, Detail, First_Person }
@(private)
Page_Lab_Frame :: struct { frame_ms, update_ms, draw_ms: f64 }
@(private)
Page_Lab_Scene :: struct {
	fixture: ^Page_Lab_Fixture,
	model: ^render.Page_Lab_Model,
	resources: ^render.Page_Lab_Draw_Context,
	pose: render.Page_Lab_Pose,
	print_clock: f32,
	model_ready, plain_paper: bool,
	camera_mode: Page_Lab_Camera,
	camera: rl.Camera3D,
	orbit: render.Tactical_Orbit,
	focus, selection_point: rl.Vector3,
	look: rl.Vector2,
	paused, no_shadows, no_roof, debug, selected, initialized, smoke: bool,
	selection: render.Page_Lab_Surface,
	hover: render.Page_Lab_Hit,
	stats: render.Page_Lab_Draw_Stats,
	stage, held: int,
	update_ms, draw_ms: f64,
	peak_vertices, peak_triangles, peak_shadow_pairs, peak_shadow_triangles: int,
	peak_submitted_bytes: u64,
	shadow_fallback: bool,
	frames: [PAGE_LAB_WARMUP+PAGE_LAB_SAMPLES]Page_Lab_Frame,
}

@(private)
Page_Lab_Shot :: struct {
	name: cstring,
	act: render.Page_Lab_Act,
	seconds: f32,
	camera: Page_Lab_Camera,
	focus: rl.Vector3,
	distance: f32,
	no_shadows, no_roof: bool,
	print_clock: f32,
	plain_paper, rear_view: bool,
}
@(private)
PAGE_LAB_SHOTS := [?]Page_Lab_Shot{
	{name = "panorama", camera = .Expedition},
	{name = "piede", camera = .Detail},
	{name = "passo", act = .Walk, seconds = .7, camera = .Expedition},
	{name = "passo_dettaglio", act = .Walk, seconds = .7, camera = .Detail},
	{name = "curva", act = .Turn, seconds = 1.3, camera = .Detail},
	{name = "salita", act = .Climb, seconds = 2.5, camera = .Expedition},
	{name = "salita_dettaglio", act = .Climb, seconds = 2.5, camera = .Detail},
	{name = "montata", act = .Mount, seconds = 2, camera = .Detail},
	{name = "morte_piega", act = .Death, seconds = 1.4, camera = .Detail},
	{name = "morte_pagina", act = .Death, seconds = 3.2, camera = .Detail},
	{name = "freccia", act = .Arrow, seconds = 1.4, camera = .Detail, focus = {2.5, .7, 2.5}, distance = 5},
	{name = "bomba", act = .Bomb, seconds = 1.4, camera = .Detail, focus = {6.5, .7, 2.5}, distance = 5},
	{name = "volo", act = .Flight, seconds = 1.4, camera = .Detail, focus = {11.5, .9, 2.5}, distance = 5},
	{name = "arco", camera = .Detail, focus = {3, 1, 9.75}, distance = 6},
	{name = "ponte", camera = .Detail, focus = {8, .7, 9}, distance = 6},
	{name = "tetto", camera = .Detail, focus = {13, .8, 9}, distance = 6},
	{name = "tetto_aperto", camera = .Detail, focus = {13, .8, 9}, distance = 6, no_roof = true},
	{name = "ombra", act = .Walk, seconds = .7, camera = .Detail},
	{name = "senza_ombra", act = .Walk, seconds = .7, camera = .Detail, no_shadows = true},
	{name = "occhi", camera = .First_Person},
	{name = "stampa_idle_a", camera = .Detail, print_clock = 0},
	{name = "stampa_idle_b", camera = .Detail, print_clock = 2.05},
	{name = "cartoncino_senza_stampa", camera = .Detail, plain_paper = true},
	{name = "retro_cartoncino", camera = .Detail, rear_view = true},
	{name = "laboratorio", camera = .Expedition},
}
@(private)
PAGE_LAB_SEQUENCE_ACTS := [?]render.Page_Lab_Act{.Walk, .Turn, .Death}
@(private)
PAGE_LAB_BENCH_ACTS := [?]render.Page_Lab_Act{.Still, .Walk, .Climb, .Flight}

// A visual workshop, isolated from campaign saves and combat rules. The room
// supplies the real expedition/first-person camera; the candidate paper mesh
// supplies drawing, shadows and selection. Resources open on the first frame.
page_lab_scene :: proc(smoke: bool = false) -> host.Scene {
	s := new(Page_Lab_Scene)
	s.smoke = smoke
	s.look = {-math.PI/2, 0}
	s.orbit = {yaw = render.EXPEDITION_CAMERA_YAW, pitch = render.EXPEDITION_CAMERA_PITCH, distance = 5.6, initialized = true}
	return {name = "page-laboratory", data = s, opaque = true, modal = true, clear_color = {22, 33, 43, 255},
		update = page_lab_scene_update, draw = page_lab_scene_draw, after_present = page_lab_scene_present,
		destroy = page_lab_scene_destroy}
}

@(private)
page_lab_scene_destroy :: proc(data: rawptr) {
	s := cast(^Page_Lab_Scene)data
	render.page_lab_draw_destroy(s.resources)
	if s.resources != nil { free(s.resources) }
	if s.model != nil { free(s.model) }
	page_lab_fixture_destroy(s.fixture)
	free(s)
}

@(private)
page_lab_scene_initialize :: proc(s: ^Page_Lab_Scene, frame: ^host.Frame) -> bool {
	s.fixture = page_lab_fixture_create(int(frame.canvas.width), int(frame.canvas.height))
	if s.fixture == nil { return false }
	s.model = new(render.Page_Lab_Model)
	s.resources = new(render.Page_Lab_Draw_Context)
	if !render.page_lab_draw_init(s.resources) { return false }
	s.initialized = true
	when PAGE_LAB_BENCHMARK {
		if s.smoke {
			rl.SetTargetFPS(0); rl.ClearWindowState({.VSYNC_HINT})
			fmt.println("PAGE LAB BENCHMARK: fixed_dt=1/60 warmup=60 samples=600 no_readbacks; CPU scopes are nested, not GPU timers")
		}
	}
	return true
}

@(private)
page_lab_scene_act :: proc(s: ^Page_Lab_Scene, direction: int) {
	s.pose = {act = render.Page_Lab_Act((int(s.pose.act)+direction+9)%9)}
	s.print_clock = 0
	s.focus = {}; s.selected = false
}

@(private)
page_lab_scene_surface_name :: proc(surface: render.Page_Lab_Surface) -> string {
	switch surface {
	case .Page: return "La pagina"
	case .Hero: return "Il Viandante"
	case .Enemy: return "Il custode"
	case .Object: return "Il tesoro"
	case .Arch: return "L'arco"
	case .Bridge: return "Il ponte"
	case .Roof: return "Il tetto"
	case .Arrow: return "La freccia"
	case .Bomb: return "La bomba"
	case .Flight: return "L'ala"
	}
	unreachable()
}

@(private)
page_lab_scene_ui :: proc(s: ^Page_Lab_Scene, frame: ^host.Frame) {
	ctx := frame.ui; p := ctx.theme.palette
	width, height := frame.canvas.width, frame.canvas.height
	ui.label(ctx, {24, 12, width-180, 20}, "ODIN PP  /  LABORATORIO", .Small, {160, 201, 200, 255})
	ui.label(ctx, {24, 32, width-180, 40}, "La pagina prende vita", .Title, {245, 230, 202, 255})
	if ui.button(ctx, {width-136, 22, 112, 32}, "Torna") { host.pop(frame) }
	panel := ui.panel(ctx, {18, height-126, width-36, 94})
	if ui.button(ctx, {panel.x, panel.y, 36, 30}, "<") { page_lab_scene_act(s, -1) }
	ui.label(ctx, {panel.x+48, panel.y, 250, 30}, fmt.tprintf("%02d  /  %s", int(s.pose.act)+1, render.page_lab_act_name(s.pose.act)), .Body, p.text)
	if ui.button(ctx, {panel.x+290, panel.y, 36, 30}, ">") { page_lab_scene_act(s, 1) }
	if ui.button(ctx, {width-174, panel.y, 130, 30}, "Riprendi" if s.paused else "Ferma il tempo") { s.paused = !s.paused }
	if width > 800 && ui.slider(ctx, {panel.x+350, panel.y, width-574, 30}, "Tempo", &s.pose.time, 0, 3.99, .01) {
		s.paused = true; s.print_clock = s.pose.time
	}
	row := panel.y+40
	camera_name := "Vista: spedizione" if s.camera_mode == .Expedition else ("Vista: dettaglio" if s.camera_mode == .Detail else "Vista: nei suoi occhi")
	if ui.button(ctx, {panel.x, row, 190, 30}, camera_name) { s.camera_mode = Page_Lab_Camera((int(s.camera_mode)+1)%3); s.focus = {} }
	if ui.button(ctx, {panel.x+200, row, 145, 30}, "Ombre: no" if s.no_shadows else "Ombre: si") { s.no_shadows = !s.no_shadows }
	if ui.button(ctx, {panel.x+355, row, 145, 30}, "Tetto: aperto" if s.no_roof else "Tetto: chiuso") { s.no_roof = !s.no_roof }
	if ui.button(ctx, {panel.x+510, row, 145, 30}, "Stampa: no" if s.plain_paper else "Stampa: animata") { s.plain_paper = !s.plain_paper }
	if s.selected && ui.button(ctx, {width-154, row, 110, 30}, "Osserva") {
		s.focus = s.selection_point; s.camera_mode = .Detail
	}
	ui.label(ctx, {24, height-28, width-48, 20}, "1-9 scene   Spazio pausa   C vista   P stampa   O ombre   T tetto   Clic seleziona   Rotella zoom", .Small, {168, 190, 195, 255})
}

// Space belongs to the workshop timeline. Enter/pad confirmation still
// activates the focused control, but Space must not also close or change it.
@(private)
page_lab_scene_pause_key :: proc(s: ^Page_Lab_Scene, ctx: ^ui.Context, pressed: bool) {
	if !pressed { return }
	s.paused = !s.paused
	ctx.nav.pressed -= {.Confirm}
}

@(private)
page_lab_scene_advance :: proc(s: ^Page_Lab_Scene, dt: f32) {
	if s.paused { return }
	s.pose.time = math.mod(s.pose.time+dt, f32(4))
	s.print_clock = math.mod(s.print_clock+dt, f32(24))
}

// A stationary support must not be rebuilt just to advance its printed eyes.
@(private)
page_lab_scene_geometry_pose :: proc(pose: render.Page_Lab_Pose) -> render.Page_Lab_Pose {
	result := pose
	if result.act == .Still { result.time = 0 }
	return result
}

@(private)
page_lab_scene_update :: proc(data: rawptr, frame: ^host.Frame) {
	s := cast(^Page_Lab_Scene)data
	started := time.tick_now()
	if !s.initialized && !page_lab_scene_initialize(s, frame) {
		fmt.eprintln("page laboratory: initialization failed")
		if s.smoke { page_lab_scene_destroy(data); os.exit(2) }
		host.quit(frame)
		return
	}
	dt := f32(1)/60 if s.smoke else min(frame.dt, .1)
	if s.smoke {
		when PAGE_LAB_BENCHMARK {
			s.pose.act = PAGE_LAB_BENCH_ACTS[s.stage]
			s.pose.time = f32(s.held%240)/60
			s.print_clock = f32(s.held)/60
			s.camera_mode = .Expedition
		} else { if s.stage >= len(PAGE_LAB_SHOTS) {
			s.pose = {act = PAGE_LAB_SEQUENCE_ACTS[s.stage-len(PAGE_LAB_SHOTS)], time = f32(s.held)/60}
			s.print_clock = f32(s.held)/60; s.plain_paper = false
			s.camera_mode = .Expedition
			s.no_shadows, s.no_roof = false, false
		} else {
			shot := PAGE_LAB_SHOTS[s.stage]
			s.pose = {act = shot.act, time = shot.seconds}; s.camera_mode = shot.camera
			s.focus = shot.focus; s.no_shadows, s.no_roof = shot.no_shadows, shot.no_roof
			s.print_clock, s.plain_paper = shot.print_clock, shot.plain_paper
			s.orbit.yaw = render.EXPEDITION_CAMERA_YAW+(math.PI if shot.rear_view else 0)
			s.orbit.distance = shot.distance if shot.distance > 0 else 5.6
		}}
	} else if frame.focused {
		if input.key_pressed(frame.devices, .ESCAPE) { host.pop(frame); return }
		page_lab_scene_pause_key(s, frame.ui, input.key_pressed(frame.devices, .SPACE))
		if input.key_pressed(frame.devices, .C) { s.camera_mode = Page_Lab_Camera((int(s.camera_mode)+1)%3); s.focus = {} }
		if input.key_pressed(frame.devices, .O) { s.no_shadows = !s.no_shadows }
		if input.key_pressed(frame.devices, .T) { s.no_roof = !s.no_roof }
		if input.key_pressed(frame.devices, .P) { s.plain_paper = !s.plain_paper }
		if input.key_pressed(frame.devices, .F4) { s.debug = !s.debug }
		for key, index in ([9]rl.KeyboardKey{.ONE, .TWO, .THREE, .FOUR, .FIVE, .SIX, .SEVEN, .EIGHT, .NINE}) {
			if input.key_pressed(frame.devices, key) { s.pose = {act = render.Page_Lab_Act(index)}; s.print_clock = 0; s.focus = {} }
		}
		page_lab_scene_advance(s, dt)
		if input.mouse_down(frame.devices, .MIDDLE) {
			delta := input.mouse_delta(frame.devices)
			if s.camera_mode == .First_Person { s.look.x += delta.x*.006; s.look.y = clamp(s.look.y-delta.y*.006, f32(-.55), f32(.55)) }
			else {
				s.camera_mode = .Detail
				s.orbit.yaw = math.mod(s.orbit.yaw-delta.x*.009, f32(math.PI*2))
				s.orbit.pitch = clamp(s.orbit.pitch+delta.y*.007, f32(.12), f32(1.45))
			}
		}
		if s.camera_mode == .Detail { s.orbit.distance = clamp(s.orbit.distance-input.mouse_wheel(frame.devices)*.5, f32(2.5), f32(28)) }
	}
	if !s.smoke { page_lab_scene_ui(s, frame) }
	else { when !PAGE_LAB_BENCHMARK {
		if s.stage == len(PAGE_LAB_SHOTS)-1 {
			previous := ui.set_interactive(frame.ui, false)
			page_lab_scene_ui(s, frame)
			ui.set_interactive(frame.ui, previous)
		}
	}}
	s.fixture.renderer.canvas_width, s.fixture.renderer.canvas_height = frame.canvas.width, frame.canvas.height
	s.camera = page_lab_fixture_camera(s.fixture, s.pose, dt, s.camera_mode == .First_Person, s.look.x, s.look.y)
	if s.camera_mode == .Detail {
		target := s.focus
		if target == (rl.Vector3{}) { target = render.page_lab_hero_anchor(s.pose)+{0, .9, -.25} }
		s.camera = render.page_lab_inspection_camera(target, s.orbit.yaw, s.orbit.pitch, s.orbit.distance)
	}
	geometry_pose := page_lab_scene_geometry_pose(s.pose)
	if !s.model_ready || s.model.pose != geometry_pose {
		render.page_lab_build(s.model, geometry_pose)
		s.model_ready = true
	}
	if s.smoke && s.held == 0 {
		if !render.page_lab_validate(s.model) { fmt.eprintln("page laboratory: invalid sheet", s.pose.act); os.exit(2) }
	}
	s.hover = {}
	if !s.smoke && frame.focused && frame.mouse_inside && frame.mouse.y > 76 && frame.mouse.y < frame.canvas.height-132 {
		ray := rl.GetScreenToWorldRayEx({frame.mouse.x, frame.mouse.y}, s.camera, i32(frame.canvas.width), i32(frame.canvas.height))
		s.hover = render.page_lab_pick(s.model, ray, !s.no_roof, s.camera_mode == .First_Person)
		if input.mouse_pressed(frame.devices, .LEFT) {
			s.selected = s.hover.hit
			if s.selected { s.selection = s.hover.surface; s.selection_point = s.hover.point }
		}
	}
	s.update_ms = time.duration_milliseconds(time.tick_since(started))
}

@(private)
page_lab_scene_draw :: proc(data: rawptr, frame: ^host.Frame) {
	s := cast(^Page_Lab_Scene)data
	if !s.initialized { return }
	started := time.tick_now()
	s.stats = render.page_lab_draw(s.model, s.camera, {
		resources = s.resources, shadows = !s.no_shadows, roof = !s.no_roof,
		hide_hero = s.camera_mode == .First_Person, has_selected = s.selected, selected = s.selection,
		print_clock = s.print_clock, plain_paper = s.plain_paper,
	})
	when PAGE_LAB_BENCHMARK {
		s.peak_vertices = max(s.peak_vertices, s.stats.model_vertices)
		s.peak_triangles = max(s.peak_triangles, s.stats.model_triangles)
		s.peak_shadow_pairs = max(s.peak_shadow_pairs, s.stats.shadow_pairs_tested)
		s.peak_shadow_triangles = max(s.peak_shadow_triangles, s.stats.shadow_triangles)
		s.peak_submitted_bytes = max(s.peak_submitted_bytes, s.stats.submitted_attribute_bytes)
		s.shadow_fallback = s.shadow_fallback || s.stats.shadow_grid_fallback
	}
	if s.debug {
		text := fmt.ctprintf("%s  |  %d vertici  %d triangoli  |  CPU %.2f ms", render.page_lab_act_name(s.pose.act), s.model.vertex_count, s.model.triangle_count, s.stats.draw_cpu_ms)
		rl.DrawText(text, 24, 82, 16, {190, 214, 210, 255})
	}
	s.draw_ms = time.duration_milliseconds(time.tick_since(started))
}

@(private)
page_lab_scene_capture :: proc(name: cstring) {
	artifacts.screenshot(name)
}

@(private)
page_lab_scene_percentiles :: proc(values: []f64) {
	slice.sort(values)
}

@(private)
page_lab_scene_present :: proc(data: rawptr, frame: ^host.Frame) {
	s := cast(^Page_Lab_Scene)data
	if !s.smoke || !s.initialized { return }
	when PAGE_LAB_BENCHMARK {
		s.frames[s.held] = {f64(rl.GetFrameTime())*1000, s.update_ms, s.draw_ms}
		s.held += 1
		if s.held < len(s.frames) { return }
		ordered: [PAGE_LAB_SAMPLES]f64
		total: f64
		for sample, i in s.frames[PAGE_LAB_WARMUP:] { ordered[i] = sample.frame_ms; total += sample.frame_ms }
		page_lab_scene_percentiles(ordered[:])
		stats := s.stats
		fmt.printf("PAGE LAB BENCHMARK act=%v canvas=%dx%d samples=%d mean_ms=%.6f p95_ms=%.6f p99_ms=%.6f max_ms=%.6f vertices=%d triangles=%d model_capacity_bytes=%d context_capacity_bytes=%d shaders=%d meshes=%d textures=%d print_uploads=%d print_bytes=%d\n",
			s.pose.act, int(frame.canvas.width), int(frame.canvas.height), PAGE_LAB_SAMPLES, total/PAGE_LAB_SAMPLES,
			ordered[(PAGE_LAB_SAMPLES*95+99)/100-1], ordered[(PAGE_LAB_SAMPLES*99+99)/100-1], ordered[PAGE_LAB_SAMPLES-1],
			stats.model_vertices, stats.model_triangles, stats.model_capacity_bytes, stats.context_capacity_bytes, stats.gpu_owned_shaders, stats.gpu_owned_meshes,
			stats.gpu_owned_textures, stats.print_uploads, stats.print_payload_bytes)
		fmt.printf("PAGE LAB COUNTERS act=%v peak_vertices=%d peak_triangles=%d peak_shadow_pairs=%d peak_shadow_triangles=%d peak_submitted_bytes=%d shadow_grid_references=%d shadow_grid_fallback=%v last_shadow_cpu_ms=%.6f\n",
			s.pose.act, s.peak_vertices, s.peak_triangles, s.peak_shadow_pairs, s.peak_shadow_triangles, s.peak_submitted_bytes,
			stats.shadow_grid_references, s.shadow_fallback, stats.shadow_cpu_ms)
		for sample, i in s.frames {
			fmt.printf("PAGE LAB FRAME CSV,%d,%d,%d,%.9f,%.9f,%.9f\n", s.stage, i+1, int(i>=PAGE_LAB_WARMUP), sample.frame_ms, sample.update_ms, sample.draw_ms)
		}
		s.stage += 1; s.held = 0
		s.peak_vertices, s.peak_triangles, s.peak_shadow_pairs, s.peak_shadow_triangles = 0, 0, 0, 0
		s.peak_submitted_bytes = 0; s.shadow_fallback = false
		if s.stage == len(PAGE_LAB_BENCH_ACTS) { host.quit(frame) }
	} else { if s.stage >= len(PAGE_LAB_SHOTS) {
		s.held += 1
		if s.held%20 == 0 {
			valid := render.page_lab_validate(s.model)
			if !valid { fmt.eprintln("page laboratory: invalid animated sheet"); os.exit(2) }
			fmt.printf("PAGE LAB SEQUENCE act=%v frame=%d time=%.3f valid=%v\n", s.pose.act, s.held, s.pose.time, valid)
			page_lab_scene_capture(fmt.ctprintf("odin_pp_page_cardboard_seq_%v_%02d.png", s.pose.act, s.held/20))
		}
		if s.held == 240 {
			s.stage += 1; s.held = 0
			if s.stage == len(PAGE_LAB_SHOTS)+len(PAGE_LAB_SEQUENCE_ACTS) { host.quit(frame) }
		}
	} else {
		s.held += 1
		if s.held < 48 { return }
		valid := render.page_lab_validate(s.model)
		fmt.printf("PAGE LAB SHOT stage=%d name=%s act=%v time=%.3f vertices=%d triangles=%d hinges=%d valid=%v camera=%v shaders=%d textures=%d print_clock=%.3f hero_frame=%d enemy_frame=%d print_uploads=%d print_bytes=%d\n",
			s.stage, PAGE_LAB_SHOTS[s.stage].name, s.pose.act, s.pose.time, s.model.vertex_count, s.model.triangle_count, s.model.hinge_count, valid, s.camera_mode, s.stats.gpu_owned_shaders,
			s.stats.gpu_owned_textures, s.print_clock, s.stats.hero_print_frame, s.stats.enemy_print_frame, s.stats.print_uploads, s.stats.print_payload_bytes)
		if !valid { os.exit(2) }
		page_lab_scene_capture(fmt.ctprintf("odin_pp_page_cardboard_%02d_%s.png", s.stage, PAGE_LAB_SHOTS[s.stage].name))
		s.stage += 1; s.held = 0
	}}
}
