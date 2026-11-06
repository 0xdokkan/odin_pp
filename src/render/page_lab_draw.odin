package render

import "core:math"
import rl "vendor:raylib"
import rlgl "vendor:raylib/rlgl"

// Isolated F1 presentation. The caller owns this context and destroys its one
// shader before closing the window. The fixed scratch arrays never grow; rlgl
// owns the shared streaming batch. The immutable actor atlas is uploaded once.
Page_Lab_Draw_Context :: struct {
	shader: rl.Shader,
	print: Page_Lab_Print_Assets,
	ready, failed: bool,
	shadow_bounds: [PAGE_LAB_MAX_TRIANGLES]Page_Lab_Shadow_Bounds,
	shadow_prepared: [PAGE_LAB_MAX_TRIANGLES]Page_Lab_Shadow_Receiver,
	shadow_receivers, shadow_candidates: [PAGE_LAB_MAX_TRIANGLES]u32,
	shadow_seen: [PAGE_LAB_MAX_TRIANGLES]u32,
	shadow_bin_offsets: [PAGE_LAB_SHADOW_BINS+1]int,
	shadow_bin_refs: [PAGE_LAB_SHADOW_REFS]u32,
	shadow_receiver_count: int,
	shadow_generation: u32,
	shadow_index_ready: bool,
	shadow_domain: Page_Lab_Shadow_Bounds,
	shadow_bin_scale: rl.Vector2,
	vertex_normals: [PAGE_LAB_MAX_VERTICES]rl.Vector3,
}

Page_Lab_Draw_Options :: struct {
	resources: ^Page_Lab_Draw_Context,
	shadows, roof, wireframe, hide_hero: bool,
	has_selected: bool,
	selected: Page_Lab_Surface,
	print_clock: f32,
	plain_paper: bool,
}

Page_Lab_Draw_Stats :: struct {
	model_vertices, model_triangles: int,
	surface_triangles, shadow_triangles, edge_triangles, wire_segments: int,
	shadow_pairs_tested, shadow_pairs_clipped: int,
	shadow_grid_references: int,
	shadow_grid_fallback: bool,
	submitted_vertices, submitted_attribute_bytes: u64,
	model_payload_bytes, model_capacity_bytes, context_capacity_bytes: u64,
	gpu_owned_meshes, gpu_owned_shaders: int,
	gpu_owned_textures: int,
	print_uploads: u64,
	print_payload_bytes, print_cpu_cache_bytes: u64,
	hero_print_frame, enemy_print_frame: int,
	print_init_ms: f64,
	draw_cpu_ms, shadow_cpu_ms: f64,
}

Page_Lab_Hit :: struct {
	hit: bool,
	distance: f32,
	point: rl.Vector3,
	surface: Page_Lab_Surface,
	triangle: int,
}

@(private)
Page_Lab_Shadow_Bounds :: struct { lo, hi: rl.Vector2 }

@(private)
PAGE_LAB_SHADOW_COLUMNS :: 64
@(private)
PAGE_LAB_SHADOW_ROWS :: 48
@(private)
PAGE_LAB_SHADOW_BINS :: PAGE_LAB_SHADOW_COLUMNS*PAGE_LAB_SHADOW_ROWS
@(private)
PAGE_LAB_SHADOW_REFS :: PAGE_LAB_MAX_TRIANGLES*16

@(private)
PAGE_LAB_LIGHT :: rl.Vector3{-.46, 1, .38}

@(private)
PAGE_LAB_PAPER_VERTEX :: `#version 330
in vec3 vertexPosition;
in vec2 vertexTexCoord;
in vec4 vertexColor;
uniform mat4 mvp;
out vec2 sheet;
out vec4 pigment;
void main() {
    sheet=vertexTexCoord;
    pigment=vertexColor;
    gl_Position=mvp*vec4(vertexPosition,1.);
}`

@(private)
PAGE_LAB_PAPER_FRAGMENT :: `#version 330
in vec2 sheet;
in vec4 pigment;
uniform sampler2D texture0;
uniform vec2 printOrigin;
uniform vec2 printScaleLift;
uniform vec4 printFrame;
uniform float printEnabled;
uniform float paperStock;
out vec4 finalColor;
void main() {
    // Material coordinates belong to the uncut page: every fold keeps its ink.
    float rule=sheet.y*2.;
    float distanceToRule=abs(fract(rule+.5)-.5);
    float ruleWidth=max(fwidth(rule),.001);
    float line=1.-smoothstep(.006,.006+ruleWidth,distanceToRule);
    float margin=1.-smoothstep(.012,.012+max(fwidth(sheet.x),.001),abs(sheet.x-1.));
    vec2 fibre=floor(sheet*vec2(155.,640.));
    float grain=fract(sin(dot(fibre,vec2(12.9898,78.233)))*43758.5453);
    float bright=smoothstep(.30,.75,max(pigment.r,max(pigment.g,pigment.b)));
    vec3 stock=gl_FrontFacing?vec3(.984,.949,.847):vec3(.83,.765,.625);
    vec3 paper=pigment.rgb*mix(vec3(1.),stock,paperStock)*(.965+.035*grain);
    paper=mix(paper,paper*vec3(.65,.76,.83),line*.23*bright);
    paper=mix(paper,paper*vec3(.96,.58,.49),margin*.33*bright);
    if(printEnabled>.5&&gl_FrontFacing) {
        vec2 local=vec2(sheet.x-printOrigin.x,printOrigin.y-sheet.y-printScaleLift.y)/printScaleLift.x;
        vec2 pixel=vec2(52.+local.x*60.,102.-local.y*60.);
        if(all(greaterThanEqual(pixel,vec2(0.)))&&all(lessThan(pixel,vec2(104.)))) {
            vec2 uv=(printFrame.xy+clamp(pixel,vec2(.5),vec2(103.5)))/printFrame.zw;
            vec4 ink=texture(texture0,uv);
            paper=mix(paper,ink.rgb*pigment.rgb*(.985+.015*grain),ink.a);
        }
    }
    finalColor=vec4(paper,pigment.a);
}`

page_lab_draw_init :: proc(state: ^Page_Lab_Draw_Context) -> bool {
	if state == nil || state.failed { return false }
	if state.ready { return true }
	state.shader = rl.LoadShaderFromMemory(PAGE_LAB_PAPER_VERTEX, PAGE_LAB_PAPER_FRAGMENT)
	if !rl.IsShaderValid(state.shader) {
		if state.shader.id != 0 { rl.UnloadShader(state.shader) }
		state.shader = {}; state.failed = true
		return false
	}
	if !page_lab_print_upload(&state.print, state.shader) {
		rl.UnloadShader(state.shader); state.shader = {}; state.failed = true
		return false
	}
	state.ready = true
	return true
}

page_lab_draw_destroy :: proc(state: ^Page_Lab_Draw_Context) {
	if state == nil { return }
	if state.ready { rl.UnloadShader(state.shader) }
	if state.print.atlas.id != 0 { rl.UnloadTexture(state.print.atlas) }
	state.print = {}
	state.shader = {}; state.ready = false; state.failed = false
}

// The production expedition camera is supplied by update_tactical_view. This
// helper is only for the lab's explicit inspection view, with the same orbit math.
page_lab_inspection_camera :: proc(target: rl.Vector3, yaw, pitch, distance: f32, perspective := true) -> rl.Camera3D {
	return tactical_orbit_camera({yaw = yaw, pitch = clamp(pitch, .08, 1.5), distance = max(distance, .2), initialized = true}, target, perspective)
}

@(private)
page_lab_surface_visible :: proc(surface: Page_Lab_Surface, roof, hide_hero: bool) -> bool {
	return (roof || surface != .Roof) && (!hide_hero || surface != .Hero)
}

@(private)
page_lab_triangle_points :: proc(model: ^Page_Lab_Model, triangle: Page_Lab_Triangle) -> (p: [3]rl.Vector3, valid: bool) {
	for index, i in triangle.indices {
		if int(index) >= model.vertex_count || int(index) >= len(model.vertices) { return }
		p[i] = model.vertices[index].position
	}
	return p, true
}

// Double-sided Moller-Trumbore. The caller supplies a normalized direction,
// so distance is a world-space length, not an arbitrary ray parameter.
@(private)
page_lab_ray_triangle :: proc(ray: rl.Ray, p: [3]rl.Vector3) -> (distance: f32, hit: bool) {
	e1, e2 := p[1]-p[0], p[2]-p[0]
	h := rl.Vector3CrossProduct(ray.direction, e2)
	det := rl.Vector3DotProduct(e1, h)
	if abs(det) < 0.0000001 { return }
	s := ray.position-p[0]
	u := rl.Vector3DotProduct(s, h)/det
	if u < -.00001 || u > 1.00001 { return }
	q := rl.Vector3CrossProduct(s, e1)
	v := rl.Vector3DotProduct(ray.direction, q)/det
	if v < -.00001 || u+v > 1.00001 { return }
	distance = rl.Vector3DotProduct(e2, q)/det
	return distance, distance >= 0
}

page_lab_pick :: proc(model: ^Page_Lab_Model, ray: rl.Ray, roof := true, hide_hero := false) -> (result: Page_Lab_Hit) {
	if model == nil { return }
	length := rl.Vector3Length(ray.direction)
	if length < .000001 { return }
	normalized := rl.Ray{position = ray.position, direction = ray.direction/length}
	result.distance = max(f32); result.triangle = -1
	for triangle, i in model.triangles[:model.triangle_count] {
		if !page_lab_surface_visible(triangle.surface, roof, hide_hero) { continue }
		points, valid := page_lab_triangle_points(model, triangle)
		if !valid { continue }
		if distance, hit := page_lab_ray_triangle(normalized, points); hit && (distance < result.distance ||
			(abs(distance-result.distance) < .00001 && result.surface == .Page && triangle.surface != .Page)) {
			result = {hit = true, distance = distance, point = normalized.position+normalized.direction*distance,
				surface = triangle.surface, triangle = i}
		}
	}
	if !result.hit { result.distance = 0 }
	return
}

@(private)
page_lab_emit_triangle :: proc(p: [3]rl.Vector3, uv: [3]rl.Vector2, color: rl.Color) {
	_ = rlgl.CheckRenderBatchLimit(3)
	rlgl.Begin(rlgl.TRIANGLES)
	rlgl.Color4ub(color.r, color.g, color.b, color.a)
	for v, i in p {
		rlgl.TexCoord2f(uv[i].x, uv[i].y)
		rlgl.Vertex3f(v.x, v.y, v.z)
	}
	rlgl.End()
}

@(private)
page_lab_polygon_triangle :: proc(points: []rl.Vector3, triangle: int) -> [3]rl.Vector3 {
	return {points[0], points[triangle+1], points[triangle+2]}
}

// Shadows and cut edges have one color and zero UVs throughout the polygon.
// Reserve the entire fan before Begin: the batch cannot flush halfway through
// it. The fan retains the old individual triangles' exact vertex order.
@(private)
page_lab_emit_flat_polygon :: proc(points: []rl.Vector3, color: rl.Color) -> int {
	triangles := max(len(points)-2, 0)
	if triangles == 0 { return 0 }
	_ = rlgl.CheckRenderBatchLimit(i32(triangles*3))
	rlgl.Begin(rlgl.TRIANGLES)
	rlgl.Color4ub(color.r, color.g, color.b, color.a)
	rlgl.TexCoord2f(0, 0)
	for i in 0..<triangles {
		for p in page_lab_polygon_triangle(points, i) { rlgl.Vertex3f(p.x, p.y, p.z) }
	}
	rlgl.End()
	return triangles
}

@(private)
page_lab_tint :: proc(color: rl.Color, shade: f32) -> rl.Color {
	return {u8(clamp(f32(color.r)*shade, 0, 255)), u8(clamp(f32(color.g)*shade, 0, 255)),
		u8(clamp(f32(color.b)*shade, 0, 255)), color.a}
}

@(private)
page_lab_draw_faces :: proc(model: ^Page_Lab_Model, camera: rl.Camera3D, options: Page_Lab_Draw_Options, page: bool, stats: ^Page_Lab_Draw_Stats) {
	state := options.resources
	ready := state != nil && state.ready
	if ready { rl.BeginShaderMode(state.shader) }
	// One uniform/texture change per surface, never per triangle. Animated ink
	// changes the atlas rectangle, while the same triangles retain their depth.
	for surface in Page_Lab_Surface {
		if (surface == .Page) != page || !page_lab_surface_visible(surface, options.roof, options.hide_hero) { continue }
		sample := page_lab_print_sample(model.pose, surface, options.print_clock)
		stock := sample.valid || options.plain_paper
		if ready {
			rlgl.DrawRenderBatchActive()
			enabled := f32(1) if sample.valid && !options.plain_paper else 0
			stock_value := f32(1) if stock else 0
			rl.SetShaderValue(state.shader, state.print.enabled_location, &enabled, .FLOAT)
			rl.SetShaderValue(state.shader, state.print.stock_location, &stock_value, .FLOAT)
			if sample.valid {
				tile := page_lab_print_tile(sample.actor, sample.clip, sample.frame)
				scale := rl.Vector2{sample.scale, sample.lift}
				frame := rl.Vector4{f32(tile.x), f32(tile.y), PAGE_LAB_PRINT_WIDTH, PAGE_LAB_PRINT_HEIGHT}
				rl.SetShaderValue(state.shader, state.print.origin_location, &sample.origin, .VEC2)
				rl.SetShaderValue(state.shader, state.print.scale_location, &scale, .VEC2)
				rl.SetShaderValue(state.shader, state.print.frame_location, &frame, .VEC4)
				rlgl.SetTexture(state.print.atlas.id)
			} else { rlgl.SetTexture(rlgl.GetTextureIdDefault()) }
		}
		for triangle in model.triangles[:model.triangle_count] {
			if triangle.surface != surface { continue }
			p, valid := page_lab_triangle_points(model, triangle)
			if !valid { continue }
			n := rl.Vector3Normalize(rl.Vector3CrossProduct(p[1]-p[0], p[2]-p[0]))
			front := rl.Vector3DotProduct(n, camera.position-(p[0]+p[1]+p[2])/3) >= 0
			light_normal := n if front else -n
			shade := .72+.28*max(rl.Vector3DotProduct(light_normal, rl.Vector3Normalize(PAGE_LAB_LIGHT)), 0)
			pigment := rl.WHITE if stock else triangle.front if front else triangle.back
			color := page_lab_tint(pigment, shade)
			uv: [3]rl.Vector2
			for index, i in triangle.indices { uv[i] = model.vertices[index].sheet }
			page_lab_emit_triangle(p, uv, color)
			stats.surface_triangles += 1
		}
	}
	rlgl.DrawRenderBatchActive(); rlgl.SetTexture(rlgl.GetTextureIdDefault())
	if ready { rl.EndShaderMode() }
}

// Clip a convex polygon against dot(point-origin,normal)>=offset. Fixed storage
// is enough: a triangle clipped by four planes has at most seven vertices.
@(private)
page_lab_clip_polygon :: proc(input: []rl.Vector3, origin, normal: rl.Vector3, offset: f32 = 0) -> (out: [12]rl.Vector3, count: int) {
	if len(input) == 0 { return }
	previous := input[len(input)-1]
	previous_distance := rl.Vector3DotProduct(previous-origin, normal)-offset
	for current in input {
		current_distance := rl.Vector3DotProduct(current-origin, normal)-offset
		if (current_distance >= 0) != (previous_distance >= 0) {
			t := previous_distance/(previous_distance-current_distance)
			out[count] = previous+(current-previous)*t; count += 1
		}
		if current_distance >= 0 { out[count] = current; count += 1 }
		previous, previous_distance = current, current_distance
	}
	return
}

@(private)
page_lab_project_shadow :: proc(caster, receiver: [3]rl.Vector3) -> (polygon: [12]rl.Vector3, count: int) {
	n := rl.Vector3Normalize(rl.Vector3CrossProduct(receiver[1]-receiver[0], receiver[2]-receiver[0]))
	if n.y < 0 { n = -n }
	denominator := rl.Vector3DotProduct(n, PAGE_LAB_LIGHT)
	if n.y < .05 || denominator < .05 { return }
	initial := caster
	polygon, count = page_lab_clip_polygon(initial[:], receiver[0], n, .0005)
	if count < 3 { count = 0; return }
	for &p in polygon[:count] { p -= PAGE_LAB_LIGHT*(rl.Vector3DotProduct(p-receiver[0], n)/denominator) }
	for i in 0..<3 {
		a, b, other := receiver[i], receiver[(i+1)%3], receiver[(i+2)%3]
		inside := rl.Vector3CrossProduct(n, b-a)
		if rl.Vector3DotProduct(other-a, inside) < 0 { inside = -inside }
		polygon, count = page_lab_clip_polygon(polygon[:count], a, inside)
		if count < 3 { count = 0; return }
	}
	// Only the shadow is biased, not the authoritative page or picking surface.
	for &p in polygon[:count] { p += n*.003 }
	return
}

@(private)
page_lab_shadow_bounds :: proc(points: [3]rl.Vector3, low, high: f32) -> (bounds: Page_Lab_Shadow_Bounds) {
	bounds.lo = {max(f32), max(f32)}; bounds.hi = {-max(f32), -max(f32)}
	for p in points {
		for y in ([2]f32{low, high}) {
			q := p-PAGE_LAB_LIGHT*((p.y-y)/PAGE_LAB_LIGHT.y)
			bounds.lo.x = min(bounds.lo.x, q.x); bounds.lo.y = min(bounds.lo.y, q.z)
			bounds.hi.x = max(bounds.hi.x, q.x); bounds.hi.y = max(bounds.hi.y, q.z)
		}
	}
	return
}

@(private)
page_lab_bounds_overlap :: proc(a, b: Page_Lab_Shadow_Bounds) -> bool {
	return a.hi.x >= b.lo.x && a.hi.y >= b.lo.y && a.lo.x <= b.hi.x && a.lo.y <= b.hi.y
}

@(private)
page_lab_shadow_bins :: proc(state: ^Page_Lab_Draw_Context, bounds: Page_Lab_Shadow_Bounds) -> (lo, hi: [2]int, found: bool) {
	if !page_lab_bounds_overlap(bounds, state.shadow_domain) { return }
	a := (bounds.lo-state.shadow_domain.lo)*state.shadow_bin_scale
	b := (bounds.hi-state.shadow_domain.lo)*state.shadow_bin_scale
	lo = {clamp(int(math.floor(a.x)), 0, PAGE_LAB_SHADOW_COLUMNS-1),
		clamp(int(math.floor(a.y)), 0, PAGE_LAB_SHADOW_ROWS-1)}
	hi = {clamp(int(math.floor(b.x)), 0, PAGE_LAB_SHADOW_COLUMNS-1),
		clamp(int(math.floor(b.y)), 0, PAGE_LAB_SHADOW_ROWS-1)}
	return lo, hi, true
}

// CSR bins index the real receiver triangles in the light plane, including
// negative projected coordinates and the changing cuts. The domain is derived
// from all receivers, not clamped to the world's [0,16]x[0,12] footprint.
// Long page bands may occupy multiple bins; per-query stamps remove duplicates.
// An unusual model exceeding the fixed index budget falls back to the exact
// receiver list, retaining every shadow instead of silently dropping geometry.
@(private)
page_lab_shadow_index :: proc(state: ^Page_Lab_Draw_Context, model: ^Page_Lab_Model) -> (low, high: f32, found: bool) {
	low, high = max(f32), -max(f32)
	state.shadow_receiver_count = 0; state.shadow_index_ready = false
	state.shadow_domain = {lo = {max(f32), max(f32)}, hi = {-max(f32), -max(f32)}}
	for &offset in state.shadow_bin_offsets { offset = 0 }
	contained := true
	for triangle, i in model.triangles[:model.triangle_count] {
		if triangle.surface != .Page { continue }
		p, valid := page_lab_triangle_points(model, triangle)
		if !valid { continue }
		bounds := page_lab_shadow_light_bounds(p)
		for v in p {
			low = min(low, v.y); high = max(high, v.y)
			contained = contained && v.x >= 0 && v.z >= 0 && v.x <= PAGE_LAB_SIZE.x && v.z <= PAGE_LAB_SIZE.y
		}
		state.shadow_bounds[i] = bounds
		state.shadow_prepared[i] = page_lab_shadow_receiver(p)
		state.shadow_receivers[state.shadow_receiver_count] = u32(i); state.shadow_receiver_count += 1
		state.shadow_domain.lo.x = min(state.shadow_domain.lo.x, bounds.lo.x)
		state.shadow_domain.lo.y = min(state.shadow_domain.lo.y, bounds.lo.y)
		state.shadow_domain.hi.x = max(state.shadow_domain.hi.x, bounds.hi.x)
		state.shadow_domain.hi.y = max(state.shadow_domain.hi.y, bounds.hi.y)
	}
	if state.shadow_receiver_count == 0 { return }
	found = true
	span := state.shadow_domain.hi-state.shadow_domain.lo
	if !contained || span.x <= 0 || span.y <= 0 { return }
	state.shadow_bin_scale = {PAGE_LAB_SHADOW_COLUMNS/span.x, PAGE_LAB_SHADOW_ROWS/span.y}
	for id in state.shadow_receivers[:state.shadow_receiver_count] {
		lo, hi, inside := page_lab_shadow_bins(state, state.shadow_bounds[id])
		if !inside { return }
		for y in lo.y..=hi.y { for x in lo.x..=hi.x { state.shadow_bin_offsets[y*PAGE_LAB_SHADOW_COLUMNS+x+1] += 1 } }
	}
	for i in 0..<PAGE_LAB_SHADOW_BINS { state.shadow_bin_offsets[i+1] += state.shadow_bin_offsets[i] }
	if state.shadow_bin_offsets[PAGE_LAB_SHADOW_BINS] > len(state.shadow_bin_refs) { return }
	cursors: [PAGE_LAB_SHADOW_BINS]int
	copy(cursors[:], state.shadow_bin_offsets[:PAGE_LAB_SHADOW_BINS])
	for id in state.shadow_receivers[:state.shadow_receiver_count] {
		lo, hi, _ := page_lab_shadow_bins(state, state.shadow_bounds[id])
		for y in lo.y..=hi.y { for x in lo.x..=hi.x {
			bin := y*PAGE_LAB_SHADOW_COLUMNS+x
			state.shadow_bin_refs[cursors[bin]] = id; cursors[bin] += 1
		} }
	}
	state.shadow_index_ready = true
	return
}

@(private)
page_lab_shadow_query :: proc(state: ^Page_Lab_Draw_Context, bounds: Page_Lab_Shadow_Bounds) -> (candidates: []u32, tested: int) {
	count := 0
	if !state.shadow_index_ready {
		for id in state.shadow_receivers[:state.shadow_receiver_count] {
			tested += 1
			if page_lab_bounds_overlap(bounds, state.shadow_bounds[id]) { state.shadow_candidates[count] = id; count += 1 }
		}
		return state.shadow_candidates[:count], tested
	}
	lo, hi, found := page_lab_shadow_bins(state, bounds)
	if !found { return state.shadow_candidates[:0], 0 }
	if state.shadow_generation == max(u32) {
		for &seen in state.shadow_seen { seen = 0 }
		state.shadow_generation = 0
	}
	state.shadow_generation += 1
	for y in lo.y..=hi.y { for x in lo.x..=hi.x {
		bin := y*PAGE_LAB_SHADOW_COLUMNS+x
		for id in state.shadow_bin_refs[state.shadow_bin_offsets[bin]:state.shadow_bin_offsets[bin+1]] {
			if state.shadow_seen[id] == state.shadow_generation { continue }
			state.shadow_seen[id] = state.shadow_generation; tested += 1
			if page_lab_bounds_overlap(bounds, state.shadow_bounds[id]) { state.shadow_candidates[count] = id; count += 1 }
		}
	} }
	return state.shadow_candidates[:count], tested
}

@(private)
page_lab_draw_shadows :: proc(model: ^Page_Lab_Model, options: Page_Lab_Draw_Options, stats: ^Page_Lab_Draw_Stats) {
	state := options.resources
	if !options.shadows || state == nil { return }
	start := rl.GetTime()
	_, _, found := page_lab_shadow_index(state, model)
	if !found { return }
	stats.shadow_grid_fallback = !state.shadow_index_ready
	if state.shadow_index_ready { stats.shadow_grid_references = state.shadow_bin_offsets[PAGE_LAB_SHADOW_BINS] }
	// A stylized ink shadow, not the production sun/AO. MIN makes overlap
	// idempotent and preserves darker page print. No render target or shadow map.
	rlgl.DrawRenderBatchActive()
	rlgl.DisableDepthMask()
	rlgl.SetBlendFactorsSeparate(rlgl.ONE, rlgl.ONE, rlgl.ONE, rlgl.ONE, rlgl.MIN, rlgl.MAX)
	rl.BeginBlendMode(.CUSTOM_SEPARATE)
	for caster in model.triangles[:model.triangle_count] {
		if caster.surface == .Page || !page_lab_surface_visible(caster.surface, options.roof, options.hide_hero) { continue }
		p, valid := page_lab_triangle_points(model, caster)
		if !valid { continue }
		bounds := page_lab_shadow_light_bounds(p)
		candidates, tested := page_lab_shadow_query(state, bounds)
		stats.shadow_pairs_tested += tested
		for id in candidates {
			stats.shadow_pairs_clipped += 1
			polygon, count := page_lab_project_shadow_prepared(p, &state.shadow_prepared[id])
			stats.shadow_triangles += page_lab_emit_flat_polygon(polygon[:count], {153, 145, 130, 255})
		}
	}
	rl.EndBlendMode()
	rlgl.DrawRenderBatchActive(); rlgl.EnableDepthMask()
	stats.shadow_cpu_ms = (rl.GetTime()-start)*1000
}

@(private)
page_lab_draw_edge :: proc(a, b, normal: rl.Vector3, width: f32, color: rl.Color, stats: ^Page_Lab_Draw_Stats) {
	if rl.Vector3LengthSqr(b-a) < .00000001 { return }
	offset := normal*width*.5
	quad := [4]rl.Vector3{a-offset, b-offset, b+offset, a+offset}
	stats.edge_triangles += page_lab_emit_flat_polygon(quad[:], color)
}

@(private)
page_lab_draw_edges :: proc(model: ^Page_Lab_Model, camera: rl.Camera3D, options: Page_Lab_Draw_Options, stats: ^Page_Lab_Draw_Stats) {
	state := options.resources
	if state == nil { return }
	for &normal in state.vertex_normals[:model.vertex_count] { normal = {} }
	for triangle in model.triangles[:model.triangle_count] {
		if !page_lab_surface_visible(triangle.surface, options.roof, options.hide_hero) { continue }
		p, valid := page_lab_triangle_points(model, triangle)
		if !valid { continue }
		n := rl.Vector3Normalize(rl.Vector3CrossProduct(p[1]-p[0], p[2]-p[0]))
		for index in triangle.indices { state.vertex_normals[index] += n }
	}
	for edge in model.cut_edges[:model.cut_edge_count] {
		if !page_lab_surface_visible(edge.surface, options.roof, options.hide_hero) { continue }
		a, b := model.vertices[edge.indices[0]].position, model.vertices[edge.indices[1]].position
		n := rl.Vector3Normalize(state.vertex_normals[edge.indices[0]]+state.vertex_normals[edge.indices[1]])
		// A thin cut cross-section around the sheet's centre surface. Picking
		// intentionally uses the same centre triangles, not an enlarged hitbox.
		page_lab_draw_edge(a, b, n, .018, {215, 196, 157, 255}, stats)
		// A lighter fibre layer belongs to the same cut section, not a second stand.
		page_lab_draw_edge(a+n*.004, b+n*.004, n, .005, {247, 232, 196, 255}, stats)
		view_normal := rl.Vector3Normalize(rl.Vector3CrossProduct(b-a, camera.position-(a+b)*.5))
		color := rl.Color{70, 61, 51, 255}
		if options.has_selected && options.selected == edge.surface { color = {239, 112, 43, 255} }
		toward := rl.Vector3Normalize(camera.position-(a+b)*.5)*.005
		page_lab_draw_edge(a+toward, b+toward, view_normal, .009, color, stats)
	}
	for hinge in model.hinges[:model.hinge_count] {
		if !page_lab_surface_visible(hinge.surface, options.roof, options.hide_hero) { continue }
		a, b := model.vertices[hinge.indices[0]].position, model.vertices[hinge.indices[1]].position
		n := rl.Vector3Normalize(rl.Vector3CrossProduct(b-a, camera.position-(a+b)*.5))
		toward := rl.Vector3Normalize(camera.position-(a+b)*.5)*.004
		page_lab_draw_edge(a+toward, b+toward, n, .008, {133, 111, 82, 255}, stats)
	}
	if options.wireframe {
		for triangle in model.triangles[:model.triangle_count] {
			if !page_lab_surface_visible(triangle.surface, options.roof, options.hide_hero) { continue }
			p, valid := page_lab_triangle_points(model, triangle)
			if !valid { continue }
			for i in 0..<3 { rl.DrawLine3D(p[i], p[(i+1)%3], {39, 101, 124, 255}); stats.wire_segments += 1 }
		}
	}
}

page_lab_draw :: proc(model: ^Page_Lab_Model, camera: rl.Camera3D, options: Page_Lab_Draw_Options) -> (stats: Page_Lab_Draw_Stats) {
	if model == nil { return }
	start := rl.GetTime()
	stats.model_vertices, stats.model_triangles = model.vertex_count, model.triangle_count
	stats.model_payload_bytes = u64(model.vertex_count*size_of(Page_Lab_Vertex)+model.triangle_count*size_of(Page_Lab_Triangle)+
		model.cut_edge_count*size_of(Page_Lab_Edge)+model.hinge_count*size_of(Page_Lab_Hinge))
	stats.model_capacity_bytes = size_of(Page_Lab_Model)
	if options.resources != nil {
		stats.context_capacity_bytes = size_of(Page_Lab_Draw_Context)
		stats.gpu_owned_shaders = 1 if options.resources.ready else 0
		stats.gpu_owned_textures = 1 if options.resources.print.atlas.id != 0 else 0
		stats.print_uploads = options.resources.print.uploads
		stats.print_payload_bytes = PAGE_LAB_PRINT_BYTES if stats.gpu_owned_textures > 0 else 0
		stats.print_cpu_cache_bytes = size_of(Page_Lab_Print_Cache)
		stats.print_init_ms = options.resources.print.init_ms
	}
	stats.hero_print_frame = page_lab_print_sample(model.pose, .Hero, options.print_clock).frame
	stats.enemy_print_frame = page_lab_print_sample(model.pose, .Enemy, options.print_clock).frame
	rl.BeginMode3D(camera)
	rlgl.DisableBackfaceCulling()
	page_lab_draw_faces(model, camera, options, true, &stats)
	page_lab_draw_shadows(model, options, &stats)
	page_lab_draw_faces(model, camera, options, false, &stats)
	page_lab_draw_edges(model, camera, options, &stats)
	rlgl.DrawRenderBatchActive(); rlgl.EnableBackfaceCulling()
	rl.EndMode3D()
	stats.submitted_vertices = u64((stats.surface_triangles+stats.shadow_triangles+stats.edge_triangles)*3+stats.wire_segments*2)
	// Attributes explicitly supplied to rlgl: position(12)+UV(8)+color(4).
	// This is submission payload, not an assertion about driver/GPU allocation.
	stats.submitted_attribute_bytes = stats.submitted_vertices*24
	stats.draw_cpu_ms = (rl.GetTime()-start)*1000
	return
}
