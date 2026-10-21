package render

import "core:c"
import "core:math"
import rl "vendor:raylib"
import rlgl "vendor:raylib/rlgl"
import game "../game"
import grid "../engine/grid"
import level "../level"

// "Neon void": an old virtual world. A black glossy floor with thin crimson
// seams that pulse very slowly, black faceted blocks edged by neon lines,
// low-poly black rocks for covers and a ring of far polygonal hills against a
// faint red horizon. Only the environment changes: actors, the HUD, the hand,
// the overlays and every effect keep their own colours. The gothic look stays
// available (Environment_Theme.Gothic, `--theme=gothic`): every neon path below
// is a branch on the theme, the old code stays as it was.
//
// Nothing here reads a clock but the world's (tactical_world_time: it holds
// still while the world is held), nothing consumes RNG, and nothing depends on
// what a hidden cell holds: hills come from the room's seed and size alone.

Environment_Theme :: enum u8 {Neon, Gothic}

// What a renderer made from now on starts with: the command line sets it once
// before the first renderer exists (create_tactical_assets copies it). Neon is
// the zero value, so a Tactical_View nobody configured is neon.
@(private)
startup_environment_theme := Environment_Theme.Neon

set_startup_environment_theme :: proc(theme: Environment_Theme) {
	startup_environment_theme = theme
}

// The look renderers made now would start with.
startup_environment_theme_choice :: proc() -> Environment_Theme {
	return startup_environment_theme
}

environment_theme_name :: proc(theme: Environment_Theme) -> string {
	switch theme {
	case .Neon: return "neon"
	case .Gothic: return "gothic"
	}
	return "neon"
}

// `--theme=<name>`'s name; false for anything else.
parse_environment_theme :: proc(name: string) -> (theme: Environment_Theme, ok: bool) {
	for candidate in Environment_Theme {
		if environment_theme_name(candidate) == name { return candidate, true }
	}
	return
}

@(private)
neon_active :: proc(renderer: ^Renderer) -> bool {
	return renderer.tactical.theme == .Neon
}

// ---------------------------------------------------------------------------
// Palette. The room family shifts the hue a little so rooms stay apart.

@(private)
neon_family_glow :: proc(family: level.Room_Family) -> [3]f32 {
	switch family {
	case .Scattered: return {0.96, 0.06, 0.16}   // red
	case .Pillars: return {0.90, 0.04, 0.27}     // crimson
	case .Ring: return {0.95, 0.04, 0.32}        // magenta red
	case .Twin_Courts: return {1.00, 0.20, 0.04} // orange red
	case .Asymmetric: return {0.78, 0.03, 0.09}  // deep blood
	}
	return {1.00, 0.09, 0.15}
}

@(private)
neon_glow :: proc(renderer: ^Renderer) -> [3]f32 {
	if renderer.tactical.snapshot == nil { return neon_family_glow(.Scattered) }
	return neon_family_glow(renderer.tactical.snapshot.family)
}

// The neon's colour at `strength` (1 is the full tube), with `alpha`.
@(private)
neon_color :: proc(glow: [3]f32, strength: f32, alpha: f32 = 1) -> rl.Color {
	return {u8(clamp(glow.x*strength, f32(0), f32(1))*255), u8(clamp(glow.y*strength, f32(0), f32(1))*255),
		u8(clamp(glow.z*strength, f32(0), f32(1))*255), u8(clamp(alpha, f32(0), f32(1))*255)}
}

// The very slow breath of every neon line, travelling across the board.
@(private)
neon_pulse :: proc(time: f32, x, y: f32) -> f32 {
	return 0.80+0.20*math.sin(time*0.75+x*0.43+y*0.29)
}

@(private)
neon_hash :: proc(a, b, c: u32) -> u32 {
	n := a*0x45d9f3b+b*0x119de1f3+c*0x2c1b3c6d+0x27d4eb2d
	n = (n~(n>>16))*0x45d9f3b
	n = (n~(n>>15))*0x119de1f3
	return n~(n>>16)
}

// 0 up to (not including) 1.
@(private)
neon_unit :: proc(n: u32) -> f32 {
	return f32(n&0xffffff)/f32(0x1000000)
}

// ---------------------------------------------------------------------------
// The material. One program serves the whole board: `hologram` selects the
// mode, and 3 is the neon one. A surface says what it is by the u of its
// texture coordinate (8 per kind): 0 black gloss, 1 seam, 2 emitted light,
// 3 faceted rock and block.

Neon_Tag :: enum u8 {Surface, Seam, Emissive, Facet}

NEON_GLSL_DECLS :: `
uniform float neonTime;
uniform vec3 neonColor;
float nHash(vec2 p) { return fract(sin(dot(p, vec2(127.1,311.7)))*43758.5453); }
float nSeg(vec2 p, vec2 a, vec2 b) {
    vec2 pa = p-a, ba = b-a;
    return length(pa-ba*clamp(dot(pa,ba)/dot(ba,ba),0.0,1.0));
}
// Sparse engraved traces and nodes, in a tile's own coordinates (-0.5..0.5).
float nCircuit(vec2 q, vec2 cell) {
    float h = nHash(cell*1.37+vec2(3.1,7.9));
    if (h > 0.20) return 0.0;
    float h2 = nHash(cell+vec2(9.7,1.3));
    if (h2 > 0.5) q.x = -q.x;
    if (fract(h2*7.0) > 0.5) q.y = -q.y;
    if (fract(h2*13.0) > 0.5) q = q.yx;
    float d = 1e3;
    d = min(d, nSeg(q, vec2(-0.30,-0.18), vec2(0.02,-0.18)));
    d = min(d, nSeg(q, vec2(0.02,-0.18), vec2(0.17,-0.03)));
    d = min(d, nSeg(q, vec2(0.17,-0.03), vec2(0.17,0.22)));
    d = min(d, abs(length(q-vec2(0.17,0.27))-0.045));
    if (fract(h*37.0) > 0.45) {
        d = min(d, nSeg(q, vec2(0.02,-0.18), vec2(0.02,-0.33)));
        d = min(d, abs(length(q-vec2(0.02,-0.37))-0.028));
    }
    return 1.0-smoothstep(0.004, 0.009, d);
}
`

NEON_GLSL_BRANCH :: `
    if (hologram == 3) {
        float tag = floor(surfaceUV.x*0.125+0.02);
        vec3 nn = normalize(normal);
        vec3 vv = normalize(eye-worldPosition);
        vec2 cellId = floor(worldPosition.xz);
        float pulse = 0.80+0.20*sin(neonTime*0.75+dot(cellId, vec2(0.43,0.29)));
        float farFade = smoothstep(6.0, 15.0, length(worldPosition.xz-lantern.xz));
        if (tag > 1.5 && tag < 2.5) {
            finalColor = vec4(color.rgb*(0.86+0.14*pulse)*(1.0-farFade*0.30), color.a);
            return;
        }
        float clearLit = roomClear*roomClear*(3.0-2.0*roomClear);
        vec3 ldir = normalize(vec3(-0.35, 1.0, -0.65));
        float key = max(dot(nn, ldir), 0.0);
        vec3 hv = normalize(ldir+vv);
        vec3 col;
        if (tag < 0.5) {
            // Glossy black. The coat reflects the glow of the horizon, the key
            // light is a thin hot line and the seam lights its own tile.
            col = color.rgb*(0.9+0.5*key);
            vec3 r = reflect(-vv, nn);
            float fres = pow(1.0-max(dot(nn,vv),0.0), 3.0);
            col += neonColor*0.03*fres*(0.35+0.65*smoothstep(-0.6, 0.8, r.x+0.5*r.z));
            col += vec3(1.0,0.45,0.50)*pow(max(dot(nn,hv),0.0), 70.0)*0.28;
            vec3 tl = lantern-worldPosition;
            float pool = max(dot(nn,normalize(tl)),0.0)/(1.0+dot(tl,tl)*0.045);
            col += mix(neonColor, vec3(1.0), 0.18)*0.045*pool;
            vec2 f = fract(worldPosition.xz);
            float e = min(min(f.x,1.0-f.x), min(f.y,1.0-f.y));
            float seam = 1.0-smoothstep(0.013, 0.024, e);
            col += neonColor*(seam*(0.40+0.50*pulse)*0.78+exp(-e*34.0)*0.065*pulse*(1.0+0.4*clearLit));
            if (nn.y > 0.9) col += neonColor*0.28*nCircuit(f-0.5, cellId)*(0.6+0.4*pulse);
            col += neonColor*0.008*clearLit;
        } else if (tag < 1.5) {
            col = neonColor*(0.60+0.40*pulse);
        } else {
            // Faceted black: the facets differ by a hair, the neon shows in the
            // rim and in the floor's glow climbing the lower faces.
            col = color.rgb*(0.55+1.9*key);
            col += neonColor*0.22*pow(1.0-max(dot(nn,vv),0.0), 3.0);
            col += neonColor*0.14*exp(-max(worldPosition.y,0.0)*3.2)*(1.0-abs(nn.y));
            col += vec3(1.0,0.45,0.50)*pow(max(dot(nn,hv),0.0), 40.0)*0.16;
            col += neonColor*0.025*clearLit;
        }
        for (int i=0; i<4; ++i) {
            if (accentLights[i].w <= 0.0) continue;
            vec3 delta = accentLights[i].xyz-worldPosition;
            float reach = accentLights[i].w/(1.0+dot(delta,delta)*1.2);
            col += neonColor*max(dot(nn,normalize(delta)),0.0)*reach*0.12;
        }
        col *= 1.0-farFade*0.55;
        finalColor = vec4(col, color.a);
        return;
    }
`

Neon_Locations :: struct {shader: c.uint, time_location, color_location: c.int}

// The program is shared (a Mostra effetto board borrows it), so its uniform
// locations are found once per program rather than kept in every view.
@(private = "file")
neon_locations: Neon_Locations

@(private)
neon_bind_uniforms :: proc(shader: rl.Shader, time: f32, glow: [3]f32) {
	if neon_locations.shader != shader.id {
		neon_locations = {shader = shader.id, time_location = rl.GetShaderLocation(shader, "neonTime"),
			color_location = rl.GetShaderLocation(shader, "neonColor")}
	}
	t, g := time, glow
	rl.SetShaderValue(shader, neon_locations.time_location, &t, .FLOAT)
	rl.SetShaderValue(shader, neon_locations.color_location, &g, .VEC3)
}

// Inside a neon resin pass: draw what follows (the exit, the props, the loot)
// with the board's own lighting, or back with the neon one. The pending batch
// is drawn first, so each side gets its own mode.
@(private)
neon_use_board_material :: proc(renderer: ^Renderer, board: bool) {
	if !neon_active(renderer) { return }
	v := &renderer.tactical
	rlgl.DrawRenderBatchActive()
	mode := c.int(Resin_Light_Mode.Board if board else Resin_Light_Mode.Neon)
	rl.SetShaderValue(v.light_shader, v.light_hologram_location, &mode, .INT)
}

// A beveled block like draw_resin_cube_v, tagged for the neon material.
@(private)
draw_neon_cube :: proc(renderer: ^Renderer, position, size: rl.Vector3, color: rl.Color, tag: Neon_Tag) {
	mesh := &renderer.tactical.block_mesh
	bevel := min(f32(0.055), min(size.x, min(size.y, size.z))*0.22)
	bevel_scale := bevel/DICE_BEVEL
	corner := size*0.5-rl.Vector3{bevel_scale*0.5, bevel_scale*0.5, bevel_scale*0.5}
	u0 := f32(tag)*8
	rlgl.SetTexture(rlgl.GetTextureIdDefault())
	rlgl.Begin(rlgl.TRIANGLES)
	rlgl.Color4ub(color.r, color.g, color.b, color.a)
	for triangle in mesh.triangles[:mesh.count] {
		n := rl.Vector3Normalize(triangle.normal)
		rlgl.Normal3f(n.x, n.y, n.z)
		for point in triangle.points {
			p := position+point*bevel_scale+rl.Vector3{
				corner.x if point.x > 0 else -corner.x,
				corner.y if point.y > 0 else -corner.y,
				corner.z if point.z > 0 else -corner.z}
			rlgl.TexCoord2f(u0+point.x+0.5, point.z+0.5)
			rlgl.Vertex3f(p.x, p.y, p.z)
		}
	}
	rlgl.End()
	rlgl.SetTexture(0)
}

// One flat triangle, wound so it faces away from `inside`.
@(private)
neon_triangle :: proc(a, b, c: rl.Vector3, inside: rl.Vector3, color: rl.Color, tag: Neon_Tag) {
	normal := rl.Vector3Normalize(rl.Vector3CrossProduct(b-a, c-a))
	b, c := b, c
	if rl.Vector3DotProduct(normal, (a+b+c)/3-inside) < 0 { b, c = c, b; normal = -normal }
	rlgl.Normal3f(normal.x, normal.y, normal.z)
	rlgl.Color4ub(color.r, color.g, color.b, color.a)
	u0 := f32(tag)*8+0.5
	rlgl.TexCoord2f(u0, 0.5); rlgl.Vertex3f(a.x, a.y, a.z)
	rlgl.TexCoord2f(u0, 0.5); rlgl.Vertex3f(b.x, b.y, b.z)
	rlgl.TexCoord2f(u0, 0.5); rlgl.Vertex3f(c.x, c.y, c.z)
}

// The direction from a point toward the eye (the view axis when orthographic).
@(private)
neon_toward_eye :: proc(renderer: ^Renderer, point: rl.Vector3) -> rl.Vector3 {
	camera := renderer.tactical.camera
	if camera.projection == .ORTHOGRAPHIC { return rl.Vector3Normalize(camera.position-camera.target) }
	return rl.Vector3Normalize(camera.position-point)
}

// A neon line as a thin ribbon turned to the eye: the same width at any GL
// line limit, depth tested, a hair in front of the face it edges. Emitted
// inside an open Begin(TRIANGLES) with the neon material.
@(private)
neon_ribbon :: proc(renderer: ^Renderer, a, b: rl.Vector3, width: f32, color: rl.Color) {
	mid := (a+b)*0.5
	eye := neon_toward_eye(renderer, mid)
	side := rl.Vector3CrossProduct(b-a, eye)
	length := rl.Vector3Length(side)
	if length < 1e-5 { return }
	side = side*(width*0.5/length)
	lift := eye*(width*0.5)
	p0, p1, p2, p3 := a-side+lift, a+side+lift, b+side+lift, b-side+lift
	normal := eye
	rlgl.Normal3f(normal.x, normal.y, normal.z)
	rlgl.Color4ub(color.r, color.g, color.b, color.a)
	u0 := f32(Neon_Tag.Emissive)*8+0.5
	// Counter-clockwise from the eye: (p0, p1, p2) turns with side × edge.
	if rl.Vector3DotProduct(rl.Vector3CrossProduct(p1-p0, p2-p0), eye) < 0 { p1, p3 = p3, p1 }
	for point in ([6]rl.Vector3{p0, p1, p2, p0, p2, p3}) {
		rlgl.TexCoord2f(u0, 0.5)
		rlgl.Vertex3f(point.x, point.y, point.z)
	}
}

// ---------------------------------------------------------------------------
// Floor, walls, covers, lamps.

@(private)
draw_neon_tile :: proc(renderer: ^Renderer, room: ^game.Room, tile: level.Tile, cell: grid.Position, preview: ^Card_Range_Preview) {
	p := rl.Vector3{f32(cell.x)+0.5, 0, f32(cell.y)+0.5}
	if tile.kind == .Wall {
		// No wall round the board: the floor just ends over the void, a red line
		// along its edge. Only the walls inside the room stand.
		if neon_is_border(room, cell) { draw_neon_board_rim(renderer, room, cell); return }
		if !diorama_interior_wall(room, cell) || first_person_solid_walls(renderer) { draw_neon_wall(renderer, room, cell) }
		return
	}
	n := gothic_hash(cell.x, cell.y)
	shade := u8(n%4)
	floor := card_range_floor_color(preview, cell, rl.Color{5+shade, 4+shade, 7+shade, 255})
	// A flat slab: tiles touch, and the shader lights the chamfers that meet
	// between them as the seams.
	rlgl.CheckRenderBatchLimit(c.int(120))
	draw_neon_cube(renderer, p+rl.Vector3{0, -0.05, 0}, {0.99, 0.135, 0.99}, floor, .Surface)
	if tile.kind == .Exit {
		// The exit keeps its own colours: lit by the board's material.
		neon_use_board_material(renderer, true)
		draw_resin_cube(renderer, p+rl.Vector3{0, 0.055, 0}, 0.8, 0.09, 0.8, DIORAMA_INK)
		rl.DrawCubeWires(p+rl.Vector3{0, 0.105, 0}, 0.70, 0.01, 0.70, DIORAMA_EDGE)
		draw_voxel_exit(renderer, cell)
		neon_use_board_material(renderer, false)
	}
}

// Whether `cell` is on the board's outer ring (where the gothic walls stand).
@(private)
neon_is_border :: proc(room: ^game.Room, cell: grid.Position) -> bool {
	return level.is_border_position(cell, room.level_data.tiles.width, room.level_data.tiles.height)
}

// The edge of the floor where the room's wall used to be: a red neon line along
// each side of the ring cell that touches the playable floor, a little under the
// tiles' top so that it reads as the rim of a slab hanging in the void.
@(private)
draw_neon_board_rim :: proc(renderer: ^Renderer, room: ^game.Room, cell: grid.Position) {
	glow := neon_glow(renderer)
	pulse := neon_pulse(f32(tactical_world_time(renderer)), f32(cell.x), f32(cell.y))
	line := neon_color(glow, 0.9*pulse)
	cx, cz := f32(cell.x)+0.5, f32(cell.y)+0.5
	toward := [4]grid.Position{{0, -1}, {1, 0}, {0, 1}, {-1, 0}}
	rlgl.CheckRenderBatchLimit(c.int(48))
	rlgl.SetTexture(rlgl.GetTextureIdDefault())
	rlgl.Begin(rlgl.TRIANGLES)
	for side in 0..<4 {
		neighbour, found := level.tile_at(room.level_data, {cell.x+toward[side].x, cell.y+toward[side].y})
		if !found || neighbour.kind == .Wall || neighbour.kind == .Void { continue }
		dx, dz := f32(toward[side].x)*0.5, f32(toward[side].y)*0.5
		// The shared edge runs across the side's direction.
		ax, az := f32(toward[side].y)*0.5, f32(toward[side].x)*0.5
		a := rl.Vector3{cx+dx-ax, 0.03, cz+dz-az}
		b := rl.Vector3{cx+dx+ax, 0.03, cz+dz+az}
		neon_ribbon(renderer, a, b, 0.04, line)
	}
	rlgl.End()
	rlgl.SetTexture(0)
}

@(private = "file")
neon_neighbour_is_wall :: proc(room: ^game.Room, cell: grid.Position) -> bool {
	tile, found := level.tile_at(room.level_data, cell)
	return !found || tile.kind == .Wall || tile.kind == .Void
}

// A black faceted block: a base ring, a shoulder ring and a smaller crown
// whose corners are nudged by the cell's own hash (so no two blocks are the
// same and none ever changes), edged in neon. It stays inside its tile.
@(private)
draw_neon_wall :: proc(renderer: ^Renderer, room: ^game.Room, cell: grid.Position) {
	h := diorama_wall_height(renderer, room, cell)
	transparent := diorama_interior_wall(room, cell) && !first_person_solid_walls(renderer)
	body_alpha := u8(64) if transparent else u8(255)
	line_alpha := f32(0.55) if transparent else f32(1)
	glow := neon_glow(renderer)
	time := f32(tactical_world_time(renderer))
	pulse := neon_pulse(time, f32(cell.x), f32(cell.y))
	line := neon_color(glow, 0.82*pulse, line_alpha)
	cx, cz := f32(cell.x)+0.5, f32(cell.y)+0.5
	corners := [4][2]f32{{-1, -1}, {1, -1}, {1, 1}, {-1, 1}}
	rings: [3][4]rl.Vector3
	widths := [3]f32{0.465, 0.465, 0.36}
	heights := [3]f32{-0.03, h*0.78, h}
	for ring in 0..<3 {
		for corner, index in corners {
			n := neon_hash(u32(cell.x), u32(cell.y), u32(ring*4+index))
			// Only the shoulder and the crown wander; the base stays square.
			wander := f32(0) if ring == 0 else (f32(0.012) if ring == 1 else f32(0.05))
			dx, dz := (neon_unit(n)-0.5)*2*wander, (neon_unit(n>>8)-0.5)*2*wander
			dy := (neon_unit(n>>16)-0.5)*2*(h*0.05) if ring == 2 else 0
			rings[ring][index] = {cx+corner[0]*widths[ring]+dx, heights[ring]+dy, cz+corner[1]*widths[ring]+dz}
		}
	}
	inside := rl.Vector3{cx, h*0.4, cz}
	// Side `side` runs from corner `side` to the next: toward -z, +x, +z, -x.
	toward := [4]grid.Position{{0, -1}, {1, 0}, {0, 1}, {-1, 0}}
	rlgl.CheckRenderBatchLimit(c.int(96+24*6))
	rlgl.SetTexture(rlgl.GetTextureIdDefault())
	rlgl.Begin(rlgl.TRIANGLES)
	for side in 0..<4 {
		next := (side+1)%4
		shade := u8(6+(neon_hash(u32(cell.x), u32(cell.y), u32(side))>>20)%5)
		// The side a neighbouring block shares is never seen.
		if !neon_neighbour_is_wall(room, {cell.x+toward[side].x, cell.y+toward[side].y}) {
			face := rl.Color{shade+2, shade, shade+3, body_alpha}
			neon_triangle(rings[0][side], rings[0][next], rings[1][next], inside, face, .Facet)
			neon_triangle(rings[0][side], rings[1][next], rings[1][side], inside, face, .Facet)
		}
		chamfer := rl.Color{shade+5, shade+1, shade+5, body_alpha}
		neon_triangle(rings[1][side], rings[1][next], rings[2][next], inside, chamfer, .Facet)
		neon_triangle(rings[1][side], rings[2][next], rings[2][side], inside, chamfer, .Facet)
	}
	top := rl.Color{14, 9, 14, body_alpha}
	neon_triangle(rings[2][0], rings[2][1], rings[2][2], inside+rl.Vector3{0, 4, 0}, top, .Facet)
	neon_triangle(rings[2][0], rings[2][2], rings[2][3], inside+rl.Vector3{0, 4, 0}, top, .Facet)
	for side in 0..<4 {
		next := (side+1)%4
		neon_ribbon(renderer, rings[0][side], rings[1][side], 0.022, line)
		neon_ribbon(renderer, rings[1][side], rings[2][side], 0.022, line)
		neon_ribbon(renderer, rings[1][side], rings[1][next], 0.020, line)
		neon_ribbon(renderer, rings[2][side], rings[2][next], 0.024, line)
		neon_ribbon(renderer, rings[0][side], rings[0][next], 0.018, line)
	}
	// One diagonal crack across the crown: the facets read as cut.
	if neon_hash(u32(cell.x), u32(cell.y), 77)%3 == 0 {
		neon_ribbon(renderer, rings[2][0], rings[2][2], 0.014, neon_color(glow, 0.7*pulse, line_alpha))
	}
	// The sconce is a red tube on the wall's face.
	if lamp, found := diorama_lamp(renderer, room, cell); found {
		neon_ribbon_tube(renderer, lamp, glow, pulse, line_alpha)
	}
	rlgl.End()
	rlgl.SetTexture(0)
}

// A vertical neon tube with a white-hot core (inside an open Begin(TRIANGLES)).
@(private)
neon_ribbon_tube :: proc(renderer: ^Renderer, lamp: rl.Vector3, glow: [3]f32, pulse: f32, alpha: f32) {
	neon_ribbon(renderer, lamp+rl.Vector3{0, -0.15, 0}, lamp+rl.Vector3{0, 0.15, 0}, 0.075, neon_color(glow, 1.0*pulse, alpha))
	neon_ribbon(renderer, lamp+rl.Vector3{0, -0.13, 0}, lamp+rl.Vector3{0, 0.13, 0}, 0.025,
		neon_color({1, 0.82, 0.8}, 1.0, alpha))
}

// The red halo of a lamp, in the accents pass (no depth writes, default shader).
@(private)
draw_neon_lamp_glow :: proc(renderer: ^Renderer, lamp: rl.Vector3, cell: grid.Position, opacity: f32 = 1) {
	time := f32(tactical_world_time(renderer))
	flicker := 0.90+0.10*math.sin(time*1.9+f32(cell.x+cell.y))
	glow := neon_glow(renderer)
	rl.DrawCube(lamp, 0.05, 0.30*flicker, 0.05, neon_color(glow, 1.0, opacity))
	rl.DrawCube(lamp, 0.02, 0.26*flicker, 0.02, neon_color({1, 0.85, 0.82}, 1.0, opacity))
	for layer in 0..<2 {
		size := f32(0.13)+f32(layer)*0.11
		rl.DrawCube(lamp, size, 0.26+f32(layer)*0.12, size, neon_color(glow, 1.0, f32(20-layer*8)/255*opacity*1.6))
	}
}

// A cover as a low-poly black rock: ring by ring, nudged by its cell.
@(private)
draw_neon_rock :: proc(renderer: ^Renderer, cell: grid.Position) {
	glow := neon_glow(renderer)
	time := f32(tactical_world_time(renderer))
	pulse := neon_pulse(time, f32(cell.x), f32(cell.y))
	line := neon_color(glow, 0.95*pulse)
	cx, cz := f32(cell.x)+0.5, f32(cell.y)+0.5
	seed := neon_hash(u32(cell.x), u32(cell.y), 5)
	turn := neon_unit(seed)*math.PI
	// Base (6), shoulder (6), crown (4).
	sides := [3]int{6, 6, 4}
	radii := [3]f32{0.36, 0.31, 0.17}
	heights := [3]f32{-0.02, 0.22, 0.42}
	rings: [3][6]rl.Vector3
	for ring in 0..<3 {
		for index in 0..<sides[ring] {
			n := neon_hash(u32(cell.x), u32(cell.y), u32(ring*8+index+11))
			angle := turn+f32(index)*(2*math.PI/f32(sides[ring]))+(neon_unit(n)-0.5)*0.45
			radius := radii[ring]*(0.84+0.32*neon_unit(n>>10))
			y := heights[ring]+(neon_unit(n>>18)-0.5)*0.09 if ring > 0 else heights[ring]
			rings[ring][index] = {cx+math.cos(angle)*radius, y, cz+math.sin(angle)*radius}
		}
	}
	inside := rl.Vector3{cx, 0.2, cz}
	rlgl.CheckRenderBatchLimit(c.int(180))
	rlgl.SetTexture(rlgl.GetTextureIdDefault())
	rlgl.Begin(rlgl.TRIANGLES)
	for ring in 0..<2 {
		count, upper := sides[ring], sides[ring+1]
		// Walk both rings around together: each lower vertex meets the
		// upper vertex at the same turn.
		for index in 0..<count {
			next := (index+1)%count
			ui := index*upper/count
			un := (next*upper/count)%upper if next != 0 else 0
			shade := u8(5+(neon_hash(u32(cell.x), u32(cell.y), u32(ring*8+index))>>20)%7)
			color := rl.Color{shade+2, shade, shade+3, 255}
			neon_triangle(rings[ring][index], rings[ring][next], rings[ring+1][un], inside, color, .Facet)
			neon_triangle(rings[ring][index], rings[ring+1][un], rings[ring+1][ui], inside, color, .Facet)
		}
	}
	crown := rl.Color{12, 8, 12, 255}
	neon_triangle(rings[2][0], rings[2][1], rings[2][2], inside+rl.Vector3{0, 3, 0}, crown, .Facet)
	neon_triangle(rings[2][0], rings[2][2], rings[2][3], inside+rl.Vector3{0, 3, 0}, crown, .Facet)
	for ring in 0..<3 {
		count := sides[ring]
		for index in 0..<count {
			neon_ribbon(renderer, rings[ring][index], rings[ring][(index+1)%count], 0.02, line)
			if ring < 2 {
				upper := sides[ring+1]
				neon_ribbon(renderer, rings[ring][index], rings[ring+1][index*upper/count], 0.018, line)
			}
		}
	}
	rlgl.End()
	rlgl.SetTexture(0)
}

// Hidden cells: identical black blocks with a dim red outline. Only the
// coordinates and the world clock enter, never what the cell holds.
@(private)
draw_neon_fog_block :: proc(renderer: ^Renderer, x, y: int, time: f32) {
	p := rl.Vector3{f32(x)+0.5, 0, f32(y)+0.5}
	rl.DrawCube(p+rl.Vector3{0, -0.05, 0}, 0.96, 0.30, 0.96, {2, 1, 3, 255})
	edge := neon_color(neon_glow(renderer), 0.22*neon_pulse(time, f32(x), f32(y)))
	top := p+rl.Vector3{0, 0.1015, 0}
	a, b, c2, d := top+rl.Vector3{-0.48, 0, -0.48}, top+rl.Vector3{0.48, 0, -0.48}, top+rl.Vector3{0.48, 0, 0.48}, top+rl.Vector3{-0.48, 0, 0.48}
	rl.DrawLine3D(a, b, edge)
	rl.DrawLine3D(b, c2, edge)
	rl.DrawLine3D(c2, d, edge)
	rl.DrawLine3D(d, a, edge)
}

// Sparse dim-red motes drift up from the floor (draw_diorama_accents).
@(private)
neon_mote_color :: proc(renderer: ^Renderer, alpha: u8) -> rl.Color {
	glow := neon_glow(renderer)
	return {u8(glow.x*190), u8(glow.y*120), u8(glow.z*130), alpha}
}

// ---------------------------------------------------------------------------
// The far hills. A ring of black faceted polyhedra beyond the walls, outlined
// in thin neon; from the room's seed and size only, never a clock or a global
// RNG. At most NEON_HILL_MAX meshes a frame, each culled against the view.

NEON_HILL_MAX :: 26
NEON_HILL_MIN_GAP :: f32(3.0)

Neon_Hill :: struct {
	center: rl.Vector2, // world x, z
	radius, height, turn: f32,
	sides: int,
	seed: u32,
}

@(private)
neon_hill_seed :: proc(width, height: int, family: level.Room_Family, exit: grid.Position, kind: game.Encounter_Kind) -> u32 {
	// A room carries no seed of its own: its size, family, kind and exit
	// (fixed for as long as the room lasts) tell one room from the next.
	return gothic_hash(width, height)~(u32(family)+1)*0x9e3779b1~gothic_hash(exit.x, exit.y)*3~(u32(kind)+7)*0x85ebca6b
}

@(private)
neon_hill_count :: proc(width, height: int) -> int {
	return clamp(12+(width+height)/3, 14, NEON_HILL_MAX)
}

// Hill `index` of a room `width` by `height` cells (rect [0,width] x [0,height]):
// always at least NEON_HILL_MIN_GAP beyond the farthest edge of the room.
@(private)
neon_hill :: proc(seed: u32, index, count, width, height: int) -> (hill: Neon_Hill) {
	n := neon_hash(seed, u32(index), 1)
	hill.seed = n
	hill.radius = 3.4+neon_unit(n>>4)*4.2
	hill.height = hill.radius*(0.34+0.42*neon_unit(n>>12))
	hill.turn = neon_unit(n>>20)*2*math.PI
	hill.sides = 6+int((n>>3)%3)
	w, h := f32(width), f32(height)
	angle := (f32(index)+0.5+(neon_unit(neon_hash(seed, u32(index), 2))-0.5)*0.7)*(2*math.PI/f32(count))
	dir := rl.Vector2{math.cos(angle), math.sin(angle)}
	half := rl.Vector2{w*0.5, h*0.5}
	edge := min(half.x/max(abs(dir.x), 1e-4), half.y/max(abs(dir.y), 1e-4))
	reach := edge+hill.radius*1.25+NEON_HILL_MIN_GAP+neon_unit(neon_hash(seed, u32(index), 3))*10
	at := half+dir*reach
	// Push out until the hill's whole footprint clears the room's rectangle.
	need := hill.radius*1.25+NEON_HILL_MIN_GAP
	nearest := rl.Vector2{clamp(at.x, 0, w), clamp(at.y, 0, h)}
	away := at-nearest
	if rl.Vector2Length(away) < need { at = nearest+rl.Vector2Normalize(away)*need }
	hill.center = at
	return
}

// How far the hill may rise before it stands between the eye and the room
// (0.12 to 1 of its height): a hill never covers a gameplay cell, whatever the
// orbit. Smooth in the camera, so the few hills near the eye ease, not pop.
@(private)
neon_hill_rise :: proc(eye: rl.Vector3, hill: Neon_Hill, room_width, room_height: f32) -> f32 {
	dx, dz := hill.center.x-eye.x, hill.center.y-eye.z
	d := math.sqrt(dx*dx+dz*dz)
	if d < 1e-3 || eye.y <= 0.05 { return 1 }
	ux, uz := dx/d, dz/d
	// The ray from the eye through the hill's axis against the room, widened
	// by half a cell.
	lo, hi := f32(-1e9), f32(1e9)
	for axis in 0..<2 {
		origin, direction := eye.x if axis == 0 else eye.z, ux if axis == 0 else uz
		low, high := f32(-0.5), (room_width if axis == 0 else room_height)+0.5
		if abs(direction) < 1e-6 {
			if origin < low || origin > high { return 1 }
			continue
		}
		t0, t1 := (low-origin)/direction, (high-origin)/direction
		if t0 > t1 { t0, t1 = t1, t0 }
		lo, hi = max(lo, t0), min(hi, t1)
	}
	if lo > hi || hi <= d { return 1 } // misses the room, or the room is before the hill
	// The room starts at `lo` (> d: behind the hill). Its apex ray must reach
	// the ground before the room does.
	reach := lo-0.6
	if reach <= d { return 0.12 }
	allowed := eye.y*(1-d/reach)
	return clamp(allowed/hill.height, f32(0.12), f32(1))
}

@(private)
neon_sphere_on_screen :: proc(f: ^Tactical_Draw_Frustum, center: rl.Vector3, radius: f32) -> bool {
	if !f.valid { return true }
	delta := center-f.eye
	z := rl.Vector3DotProduct(delta, f.forward)
	if z+radius <= 0 { return false }
	x, y := abs(rl.Vector3DotProduct(delta, f.right)), abs(rl.Vector3DotProduct(delta, f.up))
	if !f.perspective { return x <= f.horizontal+radius && y <= f.vertical+radius }
	return x <= z*f.horizontal+radius*f.horizontal_margin && y <= z*f.vertical+radius*f.vertical_margin
}

@(private)
draw_neon_hills :: proc(renderer: ^Renderer, room: ^game.Room) {
	if !neon_active(renderer) || room == nil { return }
	v := &renderer.tactical
	width, height := room.level_data.tiles.width, room.level_data.tiles.height
	seed := neon_hill_seed(width, height, room.family, room.exit_position, room.encounter_kind)
	count := neon_hill_count(width, height)
	glow := neon_glow(renderer)
	time := f32(tactical_world_time(renderer))
	for index in 0..<count {
		hill := neon_hill(seed, index, count, width, height)
		rise := neon_hill_rise(v.camera.position, hill, f32(width), f32(height))
		peak := hill.height*rise
		extent := hill.radius*1.2
		if !neon_sphere_on_screen(&v.draw_frustum, {hill.center.x, peak*0.5, hill.center.y}, extent+peak) { continue }
		distance := rl.Vector3Length(rl.Vector3{hill.center.x, 0, hill.center.y}-v.camera.position)
		if distance < 2 { continue }
		draw_neon_hill(renderer, hill, peak, glow, neon_pulse(time, hill.center.x*0.2, hill.center.y*0.2), distance)
	}
}

// Rings: the base, a shoulder, and the summit (off-centre, so the silhouette
// leans). A default-shader pass: its faces carry their own flat shade.
@(private)
draw_neon_hill :: proc(renderer: ^Renderer, hill: Neon_Hill, peak: f32, glow: [3]f32, pulse: f32, distance: f32) {
	sides := hill.sides
	base, shoulder: [8]rl.Vector3
	for index in 0..<sides {
		n := neon_hash(hill.seed, u32(index), 9)
		angle := hill.turn+f32(index)*(2*math.PI/f32(sides))+(neon_unit(n)-0.5)*0.5
		radius := hill.radius*(0.86+0.30*neon_unit(n>>9))
		base[index] = {hill.center.x+math.cos(angle)*radius, -0.5, hill.center.y+math.sin(angle)*radius}
		n2 := neon_hash(hill.seed, u32(index), 10)
		shoulder_radius := radius*(0.50+0.18*neon_unit(n2))
		lift := peak*(0.50+0.22*neon_unit(n2>>9))
		shoulder[index] = {hill.center.x+math.cos(angle)*shoulder_radius, lift, hill.center.y+math.sin(angle)*shoulder_radius}
	}
	lean := neon_hash(hill.seed, 0, 11)
	summit := rl.Vector3{hill.center.x+(neon_unit(lean)-0.5)*hill.radius*0.35, peak, hill.center.y+(neon_unit(lean>>12)-0.5)*hill.radius*0.35}
	inside := rl.Vector3{hill.center.x, peak*0.3, hill.center.y}
	sun := rl.Vector3Normalize({-0.35, 1.0, -0.65})
	// Flat shade of a face: near black, a trace of the horizon's red.
	shade :: proc(a, b, c, inside, sun: rl.Vector3, glow: [3]f32) -> rl.Color {
		normal := rl.Vector3Normalize(rl.Vector3CrossProduct(b-a, c-a))
		if rl.Vector3DotProduct(normal, (a+b+c)/3-inside) < 0 { normal = -normal }
		light := 0.25+0.75*max(rl.Vector3DotProduct(normal, sun), 0)
		return {u8(7+light*20*(0.6+glow.x*0.4)), u8(4+light*8), u8(8+light*13), 255}
	}
	rlgl.CheckRenderBatchLimit(c.int(sides*12+sides*6*3))
	rlgl.SetTexture(rlgl.GetTextureIdDefault())
	rlgl.Begin(rlgl.TRIANGLES)
	triangle :: proc(a, b, c, inside: rl.Vector3, color: rl.Color) {
		b, c := b, c
		normal := rl.Vector3CrossProduct(b-a, c-a)
		if rl.Vector3DotProduct(normal, (a+b+c)/3-inside) < 0 { b, c = c, b }
		rlgl.Color4ub(color.r, color.g, color.b, color.a)
		rlgl.Vertex3f(a.x, a.y, a.z)
		rlgl.Vertex3f(b.x, b.y, b.z)
		rlgl.Vertex3f(c.x, c.y, c.z)
	}
	for index in 0..<sides {
		next := (index+1)%sides
		triangle(shoulder[index], shoulder[next], summit, inside, shade(shoulder[index], shoulder[next], summit, inside, sun, glow))
		triangle(base[index], base[next], shoulder[next], inside, shade(base[index], base[next], shoulder[next], inside, sun, glow))
		triangle(base[index], shoulder[next], shoulder[index], inside, shade(base[index], shoulder[next], shoulder[index], inside, sun, glow))
	}
	rlgl.End()
	// The outline: thin ribbons whose width grows with the distance, so far
	// hills keep a line about as wide on the screen as near blocks do. Ribbons
	// are the neon tag of the shared program, so here plain quads (the default
	// shader reads the vertex colours).
	line := neon_color(glow, 0.55*pulse, 0.9)
	width := clamp(distance*0.0017, f32(0.02), f32(0.12))
	rlgl.Begin(rlgl.TRIANGLES)
	for index in 0..<sides {
		next := (index+1)%sides
		hill_ribbon(renderer, shoulder[index], summit, width, line)
		hill_ribbon(renderer, shoulder[index], shoulder[next], width, line)
		hill_ribbon(renderer, base[index], shoulder[index], width*0.8, line)
	}
	rlgl.End()
	rlgl.SetTexture(0)
}

// A ribbon turned to the eye, for the default shader (no normals, no tags).
@(private = "file")
hill_ribbon :: proc(renderer: ^Renderer, a, b: rl.Vector3, width: f32, color: rl.Color) {
	mid := (a+b)*0.5
	eye := neon_toward_eye(renderer, mid)
	side := rl.Vector3CrossProduct(b-a, eye)
	length := rl.Vector3Length(side)
	if length < 1e-5 { return }
	side = side*(width*0.5/length)
	lift := eye*(width*0.8)
	p0, p1, p2, p3 := a-side+lift, a+side+lift, b+side+lift, b-side+lift
	if rl.Vector3DotProduct(rl.Vector3CrossProduct(p1-p0, p2-p0), eye) < 0 { p1, p3 = p3, p1 }
	rlgl.Color4ub(color.r, color.g, color.b, color.a)
	for point in ([6]rl.Vector3{p0, p1, p2, p0, p2, p3}) { rlgl.Vertex3f(point.x, point.y, point.z) }
}

// ---------------------------------------------------------------------------
// The backdrop: a black void with a faint red glow along the horizon.

@(private)
draw_neon_backdrop :: proc(renderer: ^Renderer) {
	rl.ClearBackground({2, 1, 3, 255})
	w, h := renderer.canvas_width, renderer.canvas_height
	glow := neon_glow(renderer)
	time := f32(tactical_world_time(renderer))
	breath := 0.9+0.1*math.sin(time*0.4)
	// Two bands meeting at the horizon, a third of the way down.
	horizon := h*0.27
	band := neon_color(glow, 0.30*breath, 0.85)
	rl.DrawRectangleGradientV(0, 0, c.int(w), c.int(horizon), {2, 1, 3, 0}, band)
	rl.DrawRectangleGradientV(0, c.int(horizon), c.int(w), c.int(h*0.26), band, {2, 1, 3, 0})
	rl.DrawCircleGradient({w*0.5, horizon}, w*0.40, neon_color(glow, 0.22*breath, 0.40), {2, 1, 3, 0})
}
