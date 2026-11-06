package render

import "core:math"
import rl "vendor:raylib"

// Fase 1: a visual study, with no game state, collision or combat rules.
// Every triangle belongs to the same original sheet. Cuts duplicate vertices;
// hinges retain the page's vertex IDs. There is no extra plane below a cutout.
Page_Lab_Act :: enum u8 { Still, Walk, Turn, Climb, Mount, Death, Arrow, Bomb, Flight }
Page_Lab_Surface :: enum u8 { Page, Hero, Enemy, Object, Arch, Bridge, Roof, Arrow, Bomb, Flight }
Page_Lab_Pose :: struct { act: Page_Lab_Act, time: f32 }
Page_Lab_Vertex :: struct { position: rl.Vector3, sheet: rl.Vector2 }
Page_Lab_Triangle :: struct { indices: [3]u32, surface: Page_Lab_Surface, front, back: rl.Color }
Page_Lab_Edge :: struct { indices: [2]u32, surface: Page_Lab_Surface }
Page_Lab_Hinge :: struct { indices: [2]u32, surface: Page_Lab_Surface }

PAGE_LAB_SIZE :: rl.Vector2{16, 12}
PAGE_LAB_CENTER :: rl.Vector3{8, 0, 6}
PAGE_LAB_HERO_ORIGIN :: rl.Vector3{6, 0, 5}
// Keep the complete enemy cut clear of the hero's final climb position (X=8.5).
PAGE_LAB_ENEMY_ORIGIN :: rl.Vector3{11, 0, 5}
PAGE_LAB_OBJECT_ORIGIN :: rl.Vector3{13.5, 0, 5}
PAGE_LAB_ARCH_ORIGIN :: rl.Vector3{3, 0, 9.75}
PAGE_LAB_BRIDGE_ORIGIN :: rl.Vector3{8, 0, 9}
PAGE_LAB_ROOF_ORIGIN :: rl.Vector3{13, 0, 9}
PAGE_LAB_ARROW_ORIGIN :: rl.Vector3{2.5, 0, 2.5}
PAGE_LAB_BOMB_ORIGIN :: rl.Vector3{6.5, 0, 2.5}
PAGE_LAB_FLIGHT_ORIGIN :: rl.Vector3{11.5, 0, 2.5}
PAGE_LAB_MAX_VERTICES :: 32768
PAGE_LAB_MAX_TRIANGLES :: 32768
PAGE_LAB_MAX_EDGES :: 16384
PAGE_LAB_MAX_HINGES :: 1024
@(private) PAGE_LAB_AXIS_X :: 320
@(private) PAGE_LAB_AXIS_Y :: 224
@(private) PAGE_LAB_NODES :: PAGE_LAB_AXIS_X*PAGE_LAB_AXIS_Y
@(private) PAGE_LAB_EDGE_SLOTS :: 131072
@(private) PAGE_LAB_STEP :: f32(1)/16

@(private)
Page_Lab_Edge_Record :: struct {
	key: u64,
	indices: [2]u32,
	surface, other: Page_Lab_Surface,
	count: u8,
}

// Allocate once with new(Page_Lab_Model), free after the lab scene closes.
// Scratch belongs to the model too: build and validation allocate nothing.
Page_Lab_Model :: struct {
	vertices: [PAGE_LAB_MAX_VERTICES]Page_Lab_Vertex,
	triangles: [PAGE_LAB_MAX_TRIANGLES]Page_Lab_Triangle,
	cut_edges: [PAGE_LAB_MAX_EDGES]Page_Lab_Edge,
	hinges: [PAGE_LAB_MAX_HINGES]Page_Lab_Hinge,
	vertex_count, triangle_count, cut_edge_count, hinge_count: int,
	overflow: bool,
	pose: Page_Lab_Pose,
	xs: [PAGE_LAB_AXIS_X]f32,
	ys: [PAGE_LAB_AXIS_Y]f32,
	x_count, y_count: int,
	cells: [PAGE_LAB_NODES]Page_Lab_Surface,
	page_ids, flap_ids: [PAGE_LAB_NODES]u32,
	flap_surfaces: [PAGE_LAB_NODES]Page_Lab_Surface,
	edges: [PAGE_LAB_EDGE_SLOTS]Page_Lab_Edge_Record,
	parents: [PAGE_LAB_MAX_VERTICES]u32,
	incidence: [PAGE_LAB_MAX_VERTICES]u16,
}

page_lab_act_name :: proc(act: Page_Lab_Act) -> string {
	switch act {
	case .Still: return "Fermo"
	case .Walk: return "Passo"
	case .Turn: return "Curva"
	case .Climb: return "Salita"
	case .Mount: return "Montatura"
	case .Death: return "Morte e chiusura"
	case .Arrow: return "Freccia-piega"
	case .Bomb: return "Bomba-piega"
	case .Flight: return "Volo-piega"
	}
	return ""
}

@(private)
page_lab_ease :: proc(x: f32) -> f32 { v:=clamp(x, 0, 1); return v*v*(3-2*v) }

page_lab_ground_height :: proc(pose: Page_Lab_Pose, point: rl.Vector2) -> f32 {
	// Same surface as level heights[x] = clamp(x-4, 0, 5), sampled at cell centres.
	return clamp(point.x-4.5, 0, 5)*.12 if pose.act==.Climb else 0
}

page_lab_hero_anchor :: proc(pose: Page_Lab_Pose) -> rl.Vector3 {
	p:=PAGE_LAB_HERO_ORIGIN
	t:=clamp(pose.time, 0, 4)
	switch pose.act {
	case .Walk: p.x+=.8*math.sin(t*math.PI*.5)
	case .Turn: p.x+=.65*math.sin(t*math.PI*.5); p.z+=.35*(1-math.cos(t*math.PI*.5))
	case .Climb: p.x=4.5+t
	case .Still, .Mount, .Death, .Arrow, .Bomb, .Flight:
	}
	p.y=page_lab_ground_height(pose, {p.x, p.z})
	return p
}

@(private)
page_lab_origin :: proc(pose: Page_Lab_Pose, surface: Page_Lab_Surface) -> rl.Vector3 {
	switch surface {
	case .Hero: return page_lab_hero_anchor(pose)
	case .Enemy: return PAGE_LAB_ENEMY_ORIGIN
	case .Object: return PAGE_LAB_OBJECT_ORIGIN
	case .Arch: return PAGE_LAB_ARCH_ORIGIN
	case .Bridge: return PAGE_LAB_BRIDGE_ORIGIN
	case .Roof: return PAGE_LAB_ROOF_ORIGIN
	case .Arrow: return PAGE_LAB_ARROW_ORIGIN
	case .Bomb: return PAGE_LAB_BOMB_ORIGIN
	case .Flight: return PAGE_LAB_FLIGHT_ORIGIN
	case .Page: return {}
	}
	return {}
}

@(private)
page_lab_shape :: proc(pose: Page_Lab_Pose, surface: Page_Lab_Surface, point: rl.Vector2) -> bool {
	return page_lab_shape_at(pose, surface, point, page_lab_origin(pose, surface))
}

// The prepared path supplies the same origin and mask sample once per axis.
// Keeping the shape predicates here also retains the direct reference path.
@(private)
page_lab_shape_at :: proc(pose: Page_Lab_Pose, surface: Page_Lab_Surface, point: rl.Vector2, o: rl.Vector3,
	mask_known := false, mask_value := false) -> bool {
	x:=point.x-o.x; v:=o.z-point.y; a:=abs(x)
	switch surface {
	case .Page: return false
	case .Hero:
		if v < 0 { return false }
		if pose.act==.Mount {
			// The mount and its rider are one cut, with four uncut feet.
			if v<.25 { return abs(a-.5)<.105 || abs(a-.1875)<.10 }
			if v < .70 && a < .63 { return true }
			if x>.40 && x<.78 && v<1.03 { return true }
		}
		return mask_value if mask_known else page_lab_print_contains(pose, surface, point)
	case .Enemy:
		return v >= 0 && (mask_value if mask_known else page_lab_print_contains(pose, surface, point))
	case .Object:
		return v>=0 && v<.9375 && a<(.5 if v<.6875 else .5-(v-.6875)*.7)
	case .Arch:
		if v<0 || a>1.25 { return false }
		outer:=.875+math.sqrt(max(f32(0), 1.25*1.25-x*x))
		inner:=.875+math.sqrt(max(f32(0), .875*.875-x*x))
		return v<outer && (a>=.875 || v>=inner)
	case .Bridge: return a<.75 && abs(v)<1.5
	case .Roof: return a<1.25 && abs(v)<1.25
	case .Arrow:
		if v<0 || v>2.125 { return false }
		return a<.125 if v<1.375 else a<(2.125-v)*.75
	case .Bomb:
		if v<0 || v>1.625 { return false }
		if v<.25 { return a<.375 }
		if v<1.375 { return x*x+(v-.75)*(v-.75)<.625*.625 }
		return a<.125
	case .Flight:
		if v<0 || v>2.125 { return false }
		if v<.625 { return a<.34375 }
		if v<1.375 { return a<.34375+(v-.625)*1.3 }
		if v<1.625 { return a<1.25-(v-1.375)*2.8 }
		return a<.28125
	}
	return false
}

@(private)
page_lab_surface_at :: proc(pose: Page_Lab_Pose, point: rl.Vector2) -> Page_Lab_Surface {
	for surface in Page_Lab_Surface.Hero..=Page_Lab_Surface.Flight {
		if page_lab_shape(pose, surface, point) { return surface }
	}
	return .Page
}

@(private)
page_lab_root :: proc(pose: Page_Lab_Pose, surface: Page_Lab_Surface, p: rl.Vector2) -> bool {
	o:=page_lab_origin(pose, surface)
	if surface==.Bridge { return abs(abs(p.y-o.z)-1.5)<.0001 }
	if surface==.Roof { return abs(abs(p.x-o.x)-1.25)<.0001 }
	return surface!=.Page && abs(p.y-o.z)<.0001
}

// An integral of a rotating tangent: the first part of the actual foot curves
// out of the page, rather than a separate ribbon being added below a sprite.
@(private)
page_lab_fold :: proc(v, angle: f32) -> (height, advance: f32) {
	if abs(angle)<.0001 { return 0, v }
	crease:=f32(.1875); distance:=min(v, crease); theta:=angle*distance/crease
	height=crease*(1-math.cos(theta))/angle
	advance=crease*math.sin(theta)/angle
	if v>crease { height+=(v-crease)*math.sin(angle); advance+=(v-crease)*math.cos(angle) }
	return
}

@(private)
page_lab_position :: proc(pose: Page_Lab_Pose, surface: Page_Lab_Surface, p: rl.Vector2) -> rl.Vector3 {
	ground:=page_lab_ground_height(pose, p)
	if surface==.Page || page_lab_root(pose, surface, p) { return {p.x, ground, p.y} }
	o:=page_lab_origin(pose, surface); x:=p.x-o.x; v:=o.z-p.y
	if surface==.Bridge {
		return {p.x, ground+1.05*math.sin((p.y-(o.z-1.5))/3*math.PI), p.y}
	}
	if surface==.Roof { return {p.x, ground+1.6*(1-abs(x)/1.25), p.y} }
	t:=clamp(pose.time, 0, 4); angle:=f32(math.PI*.5)
	if surface==.Hero {
		switch pose.act {
		case .Death: angle*=1-page_lab_ease(t/3)
		case .Walk, .Turn, .Climb:
			// Alternating curved soles share their uncut edge with the page throughout.
			angle+=.10*math.sin(t*math.PI*3+(math.PI if x<0 else 0))*math.exp(-v*3)
		case .Mount: angle-=.20*math.sin(t*math.PI*.5)*page_lab_ease(v/.8)
		case .Still, .Arrow, .Bomb, .Flight:
		}
	}
	if surface==.Arrow && pose.act==.Arrow { angle=.32+1.15*math.sin(t/4*math.PI) }
	if surface==.Bomb && pose.act==.Bomb { angle=.35+1.1*math.sin(t/4*math.PI) }
	if surface==.Flight && pose.act==.Flight { angle=1.05+.35*math.sin(t*math.PI) }
	h, d:=page_lab_fold(v, angle)
	// Bending follows the same sampled height as the real lab's ground.
	result:=rl.Vector3{p.x, page_lab_ground_height(pose, {p.x, o.z})+h, o.z-d}
	if surface==.Hero && pose.act==.Turn {
		yaw:=.55*math.sin(t*math.PI*.5)*page_lab_ease(v/.75)
		result.x=o.x+x*math.cos(yaw)-d*math.sin(yaw)
		result.z=o.z-x*math.sin(yaw)-d*math.cos(yaw)
	}
	if surface==.Flight {
		wing:=max(f32(0), abs(x)-.3)
		result.y+=wing*(.22+.18*math.sin(t*math.PI*2) if pose.act==.Flight else .22)
		result.z+=wing*.30
	}
	return result
}

@(private)
page_lab_colors :: proc(pose: Page_Lab_Pose, surface: Page_Lab_Surface, p: rl.Vector2) -> (front, back: rl.Color) {
	front={236, 221, 183, 255}; back={202, 181, 137, 255}
	o:=page_lab_origin(pose, surface); x:=p.x-o.x; v:=o.z-p.y
	ink:=rl.Color{35, 45, 58, 255}; blue:=rl.Color{46, 105, 134, 255}; coral:=rl.Color{200, 72, 63, 255}
	switch surface {
	case .Page:
		front={236, 226, 201, 255}
		if int(math.floor(p.x*2)+math.floor(p.y*2))%2==0 { front={232, 222, 197, 255} }
	case .Hero:
		front=blue
		if v<.1875 { front=ink }
		// Print boundaries coincide with the source grid; eyes and chest have
		// straight ink edges even when the two triangles use different diagonals.
		if v > .75 && v < 1.3125 { front = coral }
		if v > .9375 && v < 1.1875 && abs(x) < .25 { front = ink }
		if v > 1.4375 { front = {224, 186, 78, 255} }
		if v > 1.5625 && v < 1.8125 { front = ink }
		if v > 1.625 && v < 1.75 && abs(x) > .0625 && abs(x) < .1875 { front = {126, 232, 221, 255} }
		if v > 2.0 { front = {79, 201, 199, 255} }
		if pose.act == .Mount && v < .6875 { front = {88, 133, 99, 255} }
	case .Enemy:
		front = coral
		if v < .1875 || (v > .6875 && v < .875) { front = ink }
		if v > 1.3125 && v < 1.625 { front = ink }
		if v > 1.375 && v < 1.5 && abs(x) > .125 && abs(x) < .25 { front = {255, 199, 77, 255} }
		if v > 1.6875 { front = {228, 211, 164, 255} }
	case .Object:
		front={180, 116, 45, 255}
		if v>.625 || abs(abs(x)-.36)<.065 { front={225, 180, 73, 255} }
		if abs(x)<.12 && v>.35 && v<.65 { front=ink }
	case .Arch:
		front={145, 163, 163, 255}
		if int(v*8)%4==0 { front={188, 196, 181, 255} }
	case .Bridge:
		front={164, 116, 76, 255}
		if int(p.y*8)%3==0 { front={198, 156, 108, 255} }
	case .Roof:
		front={95, 126, 150, 255}
		if int(p.y*8)%3==0 { front={117, 151, 168, 255} }
	case .Arrow: front=blue; if v>1.375 { front={228, 174, 64, 255} }
	case .Bomb:
		front=ink
		if v>.8 && x<-.08 { front={93, 112, 128, 255} }
		if v>1.375 { front={234, 146, 63, 255} }
	case .Flight:
		front={155, 94, 137, 255}
		if abs(x)>.40 { front={189, 133, 163, 255} }
		if v>1.68 && v<1.87 { front={235, 205, 133, 255} }
	}
	return
}

@(private)
page_lab_axis_add :: proc(values: []f32, count: ^int, value: f32, overflow: ^bool) {
	for old in values[:count^] { if abs(old-value)<.0001 { return } }
	if count^>=len(values) { overflow^=true; return }
	i:=count^
	for i>0 && values[i-1]>value { values[i]=values[i-1]; i-=1 }
	values[i]=value; count^+=1
}

@(private)
page_lab_axes :: proc(m: ^Page_Lab_Model) {
	for i in 0..=32 { page_lab_axis_add(m.xs[:], &m.x_count, f32(i)*.5, &m.overflow) }
	for i in 0..=24 { page_lab_axis_add(m.ys[:], &m.y_count, f32(i)*.5, &m.overflow) }
	for surface in Page_Lab_Surface.Hero..=Page_Lab_Surface.Flight {
		r := page_lab_refinement(m.pose, surface)
		for i in 0..=int(math.ceil(r.width*2/PAGE_LAB_STEP)) {
			page_lab_axis_add(m.xs[:], &m.x_count, r.origin.x-r.width+f32(i)*PAGE_LAB_STEP, &m.overflow)
		}
		for i in 0..=int(math.ceil(r.depth/PAGE_LAB_STEP)) {
			page_lab_axis_add(m.ys[:], &m.y_count, r.end_y-f32(i)*PAGE_LAB_STEP, &m.overflow)
		}
	}
}

@(private)
page_lab_cell :: proc(m: ^Page_Lab_Model, x, y: int) -> Page_Lab_Surface {
	if x<0 || y<0 || x>=m.x_count-1 || y>=m.y_count-1 { return .Page }
	return m.cells[y*PAGE_LAB_AXIS_X+x]
}

// Raster outlines can surround a small unprinted cell after another moving
// cut adds an axis subdivision. Such a cell cannot stay as detached floor:
// it is blank stock inside its enclosing cutout. Preserve every Page component
// that reaches the sheet boundary, including the open gap between the soles.
// Reuse the vertex-ID scratch as visited flags and a queue before meshing.
@(private)
page_lab_close_enclosed_stock :: proc(m: ^Page_Lab_Model) {
	width, height := m.x_count-1, m.y_count-1
	for y in 0..<height { for x in 0..<width {
		start := y*PAGE_LAB_AXIS_X+x
		if m.cells[start] != .Page || m.page_ids[start] != 0 { continue }
		m.flap_ids[0] = u32(start); m.page_ids[start] = 1
		head, count := 0, 1
		exterior, ambiguous := false, false
		owner := Page_Lab_Surface.Page
		for head < count {
			node := int(m.flap_ids[head]); head += 1
			cx, cy := node%PAGE_LAB_AXIS_X, node/PAGE_LAB_AXIS_X
			for step in ([4][2]int{{-1, 0}, {1, 0}, {0, -1}, {0, 1}}) {
				nx, ny := cx+step.x, cy+step.y
				if nx < 0 || ny < 0 || nx >= width || ny >= height { exterior = true; continue }
				neighbour := ny*PAGE_LAB_AXIS_X+nx
				surface := m.cells[neighbour]
				if surface != .Page {
					if owner == .Page { owner = surface } else if owner != surface { ambiguous = true }
				} else if m.page_ids[neighbour] == 0 {
					m.page_ids[neighbour] = 1
					m.flap_ids[count] = u32(neighbour); count += 1
				}
			}
		}
		if exterior { continue }
		// Never hide a collision between independent cutouts by joining them.
		if ambiguous || owner == .Page { m.overflow = true; break }
		for node in m.flap_ids[:count] { m.cells[node] = owner }
	} }
	m.page_ids = {}; m.flap_ids = {}
}

@(private)
page_lab_vertex :: proc(m: ^Page_Lab_Model, x, y: int, surface: Page_Lab_Surface) -> u32 {
	node:=y*PAGE_LAB_AXIS_X+x; p:=rl.Vector2{m.xs[x], m.ys[y]}
	shared:=surface==.Page || page_lab_root(m.pose, surface, p)
	ids:=&m.flap_ids[node]
	if shared { ids=&m.page_ids[node] }
	if ids^ > 0 {
		// One source node may border Page and one cutout. Different cutouts
		// must never silently weld through this shared scratch slot.
		if !shared && m.flap_surfaces[node] != surface { m.overflow = true }
		return ids^-1
	}
	if m.vertex_count>=PAGE_LAB_MAX_VERTICES { m.overflow=true; return 0 }
	index:=u32(m.vertex_count); m.vertex_count+=1
	m.vertices[index]={position=page_lab_position(m.pose, surface, p), sheet=p}
	ids^=index+1
	if !shared { m.flap_surfaces[node]=surface }
	return index
}

@(private)
page_lab_triangle :: proc(m: ^Page_Lab_Model, ids: [3]u32, surface: Page_Lab_Surface, print_point: rl.Vector2 = {-1, -1}) {
	if m.triangle_count >= PAGE_LAB_MAX_TRIANGLES { m.overflow = true; return }
	point := print_point
	if point.x < 0 { point = (m.vertices[ids[0]].sheet+m.vertices[ids[1]].sheet+m.vertices[ids[2]].sheet)/3 }
	front, back := page_lab_colors(m.pose, surface, point)
	m.triangles[m.triangle_count] = {indices = ids, surface = surface, front = front, back = back}
	m.triangle_count += 1
}

// Page strips keep only contour events, avoiding a dense grid over blank paper.
// At a cut boundary every edge subdivision is retained; both feet therefore
// meet actual page edges, with shared IDs rather than geometric T-junctions.
@(private)
page_lab_row_event :: proc(m: ^Page_Lab_Model, x, y: int) -> bool {
	if x==0 || x==m.x_count-1 { return true }
	if m.pose.act==.Climb && (abs(m.xs[x]-4.5)<.0001 || abs(m.xs[x]-9.5)<.0001) { return true }
	for row in ([2]int{y-1, y}) {
		if page_lab_cell(m, x-1, row)!=.Page || page_lab_cell(m, x, row)!=.Page { return true }
	}
	return false
}

@(private)
page_lab_strip_event :: proc(m: ^Page_Lab_Model, x, y: int, surface: Page_Lab_Surface) -> bool {
	if surface == .Page { return page_lab_row_event(m, x, y) }
	point := rl.Vector2{m.xs[x], m.ys[y]}
	// The bridge's two end edges retain every page subdivision. Between
	// them its section is linear across X, so only the sides are needed.
	if surface == .Bridge && page_lab_root(m.pose, surface, point) { return true }
	if surface == .Roof && abs(point.x-PAGE_LAB_ROOF_ORIGIN.x) < .0001 { return true }
	return m.pose.act == .Climb && (abs(point.x-4.5) < .0001 || abs(point.x-9.5) < .0001)
}

@(private)
page_lab_strip :: proc(m: ^Page_Lab_Model, lo, hi, y: int, surface: Page_Lab_Surface) {
	bottom, top: [PAGE_LAB_AXIS_X]int
	bc, tc := 0, 0
	for x in lo..=hi {
		if x == lo || x == hi || page_lab_strip_event(m, x, y, surface) { bottom[bc] = x; bc += 1 }
		if x == lo || x == hi || page_lab_strip_event(m, x, y+1, surface) { top[tc] = x; tc += 1 }
	}
	print_point := rl.Vector2{-1, -1}
	if surface != .Page { print_point = {(m.xs[lo]+m.xs[hi])*.5, (m.ys[y]+m.ys[y+1])*.5} }
	bi, ti := 0, 0
	for bi < bc-1 || ti < tc-1 {
		b := page_lab_vertex(m, bottom[bi], y, surface)
		t := page_lab_vertex(m, top[ti], y+1, surface)
		advance_bottom := ti == tc-1 || (bi < bc-1 && m.xs[bottom[bi+1]] <= m.xs[top[ti+1]])
		if advance_bottom {
			next := page_lab_vertex(m, bottom[bi+1], y, surface)
			page_lab_triangle(m, {b, t, next}, surface, print_point); bi += 1
		} else {
			next := page_lab_vertex(m, top[ti+1], y+1, surface)
			page_lab_triangle(m, {b, t, next}, surface, print_point); ti += 1
		}
	}
}

@(private)
page_lab_record_edge :: proc(m: ^Page_Lab_Model, a, b: u32, surface: Page_Lab_Surface) {
	lo, hi:=min(a,b), max(a,b)
	key:=(u64(lo+1)<<32)|u64(hi+1)
	slot:=int((key ~ (key>>23) ~ (key<<11))%PAGE_LAB_EDGE_SLOTS)
	for _ in 0..<PAGE_LAB_EDGE_SLOTS {
		e:=&m.edges[slot]
		if e.key==0 { e^={key=key, indices={a,b}, surface=surface, other=surface, count=1}; return }
		if e.key==key { e.count+=1; e.other=surface; if e.count>2 { m.overflow=true }; return }
		slot=(slot+1)%PAGE_LAB_EDGE_SLOTS
	}
	m.overflow=true
}

@(private)
page_lab_boundaries :: proc(m: ^Page_Lab_Model) {
	for triangle in m.triangles[:m.triangle_count] {
		for i in 0..<3 { page_lab_record_edge(m, triangle.indices[i], triangle.indices[(i+1)%3], triangle.surface) }
	}
	for e in m.edges {
		if e.count==1 {
			if m.cut_edge_count>=PAGE_LAB_MAX_EDGES { m.overflow=true; return }
			m.cut_edges[m.cut_edge_count]={indices=e.indices, surface=e.surface}; m.cut_edge_count+=1
		} else if e.count==2 && e.surface!=e.other && (e.surface==.Page || e.other==.Page) {
			if m.hinge_count>=PAGE_LAB_MAX_HINGES { m.overflow=true; return }
			m.hinges[m.hinge_count]={indices=e.indices, surface=e.other if e.surface==.Page else e.surface}; m.hinge_count+=1
		}
	}
}

page_lab_build :: proc(m: ^Page_Lab_Model, pose: Page_Lab_Pose) {
	if m==nil { return }
	m.vertex_count=0; m.triangle_count=0; m.cut_edge_count=0; m.hinge_count=0
	m.x_count=0; m.y_count=0; m.overflow=false; m.pose=pose
	if math.is_nan(pose.time) || math.is_inf(pose.time) { m.overflow=true; return }
	m.page_ids={}; m.edges={}
	page_lab_axes(m)
	if m.overflow { return }
	samples: Page_Lab_Shape_Samples
	page_lab_prepare_shape_samples(m, &samples)
	page_lab_fill_sampled_cells(m, &samples)
	page_lab_close_enclosed_stock(m)
	if m.overflow { return }
	for y in 0..<m.y_count-1 {
		x:=0
		for x<m.x_count-1 {
			surface:=page_lab_cell(m, x, y)
			if surface == .Page || surface == .Bridge || surface == .Roof {
				start := x
				for x < m.x_count-1 && page_lab_cell(m, x, y) == surface { x += 1 }
				page_lab_strip(m, start, x, y, surface)
				continue
			}
			a := page_lab_vertex(m, x, y, surface); b := page_lab_vertex(m, x+1, y, surface)
			c := page_lab_vertex(m, x+1, y+1, surface); d := page_lab_vertex(m, x, y+1, surface)
			print_point := (m.vertices[a].sheet+m.vertices[c].sheet)*.5
			page_lab_triangle(m, {a, d, b}, surface, print_point)
			page_lab_triangle(m, {b, d, c}, surface, print_point)
			x += 1
		}
	}
	page_lab_boundaries(m)
}

@(private)
page_lab_find :: proc(m: ^Page_Lab_Model, index: u32) -> u32 {
	i:=index
	for m.parents[i]!=i { m.parents[i]=m.parents[m.parents[i]]; i=m.parents[i] }
	return i
}

// Topology is checked on the unthickened sheet. Rendering may split normals,
// but must keep this authority for drawing, picking and shadow geometry.
page_lab_validate :: proc(m: ^Page_Lab_Model) -> bool {
	if m==nil || m.overflow || m.vertex_count<3 || m.triangle_count<1 { return false }
	for vertex, i in m.vertices[:m.vertex_count] {
		for coordinate in vertex.position { if math.is_nan(coordinate) || math.is_inf(coordinate) { return false } }
		if vertex.sheet.x<-.001 || vertex.sheet.y<-.001 || vertex.sheet.x>PAGE_LAB_SIZE.x+.001 || vertex.sheet.y>PAGE_LAB_SIZE.y+.001 { return false }
		m.parents[i]=u32(i); m.incidence[i]=0
	}
	area:=f64(0)
	for triangle in m.triangles[:m.triangle_count] {
		ids:=triangle.indices
		for id in ids { if int(id)>=m.vertex_count { return false }; m.incidence[id]|=u16(1)<<u16(triangle.surface) }
		a,b,c:=m.vertices[ids[0]],m.vertices[ids[1]],m.vertices[ids[2]]
		u,v:=b.sheet-a.sheet,c.sheet-a.sheet
		signed:=u.x*v.y-u.y*v.x
		if signed>=0 { return false }
		area-=f64(signed)*.5
		cross:=rl.Vector3CrossProduct(b.position-a.position,c.position-a.position)
		if rl.Vector3LengthSqr(cross)<1e-14 { return false }
		root:=page_lab_find(m,ids[0]); m.parents[page_lab_find(m,ids[1])]=root; m.parents[page_lab_find(m,ids[2])]=root
	}
	if abs(area-f64(PAGE_LAB_SIZE.x*PAGE_LAB_SIZE.y))>.01 { return false }
	root:=page_lab_find(m,0)
	for i in 0..<m.vertex_count { if m.incidence[i]==0 || page_lab_find(m,u32(i))!=root { return false } }
	counts: [Page_Lab_Surface]int
	for hinge in m.hinges[:m.hinge_count] {
		counts[hinge.surface]+=1
		for id in hinge.indices {
			mask:=(u16(1)<<u16(Page_Lab_Surface.Page))|(u16(1)<<u16(hinge.surface))
			if m.incidence[id]&mask!=mask || !page_lab_root(m.pose,hinge.surface,m.vertices[id].sheet) { return false }
		}
	}
	for surface in Page_Lab_Surface.Hero..=Page_Lab_Surface.Flight { if counts[surface]==0 { return false } }
	return true
}
