package render

import "core:fmt"
import "core:math"
import rl "vendor:raylib"
import tween "../engine/tween"
import game "../game"
import grid "../engine/grid"
import view "../engine/view"

// BENVENUTI A NAPOLI's grandpa (game/napoli.odin, docs/piano-napoli.md, Fase 1),
// provisional (his real look is the plan's Fase 5): with the table or the purse
// he walks in from the camera's side while the world stands still (the
// visit cue is a cinematic one, cast_playback.odin), sets the table down by the
// player or holds the purse out to him, and walks back out. He is a paper print
// (a coppola, a white moustache, a red kerchief, a dark waistcoat); the table is
// resin like the board's props (draw_napoli_table), the purse a print.

// The visit's parts, in its progress: in, the gift, out.
NAPOLI_VISIT_IN :: f32(0.4)
NAPOLI_VISIT_GIFT :: f32(0.6)
NAPOLI_PRINT_HEIGHT :: f32(1.1)
// How far off he starts and ends his walk, in cells.
NAPOLI_VISIT_REACH :: f32(6)

Napoli_View :: struct {
	// The prints, made the first time they are drawn: the grandpa and the purse.
	nonno, purse: rl.Texture2D,
	// The 3D paper models' meshes and shader (napoli_models.odin).
	models: Napoli_Model_Kit,
}

@(private)
destroy_napoli_view :: proc(renderer: ^Renderer) {
	n := &renderer.tactical.napoli
	if n.nonno.id != 0 { rl.UnloadTexture(n.nonno) }
	if n.purse.id != 0 { rl.UnloadTexture(n.purse) }
	destroy_napoli_model_kit(&n.models)
	n^ = {}
}

// Whether a Napoli_Begun brings the grandpa: the table (face 2) or the purse (3).
napoli_event_is_visit :: proc(event: game.Game_Event) -> bool {
	return event.kind == .Napoli_Begun && (event.duration == 2 || event.duration == 3)
}

// The visit under way, if one is: its cue (started).
napoli_visit_cue :: proc(renderer: ^Renderer) -> (cue: ^Presentation_Cue, found: bool) {
	for offset in 0..<renderer_active_cue_count(renderer) {
		active, ok := renderer_active_cue_at(renderer, offset)
		if ok && active.started && active.kind == .Napoli_Begun && napoli_event_is_visit(active.event) { return active, true }
	}
	return
}

// Where the gift goes: the table's cell (the table the room has now), or the
// player's for the purse (and for a table with no cell, his meal served where
// he stands).
@(private = "file")
napoli_gift_cell :: proc(room: ^game.Room, cue: ^Presentation_Cue) -> grid.Position {
	if cue.event.duration == 2 {
		if index, found := game.napoli_table_index(room); found { return room.objects[index].position }
	}
	return cue.event.to_position
}

// The grandpa's way: in from the camera's side, NAPOLI_VISIT_REACH cells off,
// so he is never behind a wall or the player's card, to the cell beside the
// gift toward the camera (beside it again if that is the player's), and back.
@(private = "file")
napoli_visit_way :: proc(renderer: ^Renderer, room: ^game.Room, gift: grid.Position) -> (edge, stand: view.Vec2) {
	camera := renderer.tactical.camera
	back := view.Vec2{camera.position.x-camera.target.x, camera.position.z-camera.target.z}
	length := math.sqrt(back.x*back.x+back.y*back.y)
	back = {back.x/length, back.y/length} if length > 0.001 else {0, 1}
	way := grid.Position{x = int(math.round(back.x)), y = int(math.round(back.y))}
	if way.x == 0 && way.y == 0 { way.y = 1 }
	at := grid.offset(gift, way.x, way.y)
	if room != nil && room.player != nil && at == room.player.position {
		at = grid.offset(gift, way.x, 0) if way.x != 0 else grid.offset(gift, 1, way.y)
		if at == room.player.position { at = grid.offset(gift, 0, way.y) if way.y != 0 else grid.offset(gift, way.x, 1) }
	}
	stand = {f32(at.x), f32(at.y)}
	edge = {stand.x+back.x*NAPOLI_VISIT_REACH, stand.y+back.y*NAPOLI_VISIT_REACH}
	return
}

// Where the grandpa is at `p` of his visit, and how far through his walk (for
// his steps' bob).
@(private = "file")
napoli_visit_at :: proc(edge, stand: view.Vec2, p: f32) -> (at: view.Vec2, walking: f32) {
	lerp :: proc(a, b: view.Vec2, k: f32) -> view.Vec2 { return {a.x+(b.x-a.x)*k, a.y+(b.y-a.y)*k} }
	if p < NAPOLI_VISIT_IN { k := tween.smoothstep(p/NAPOLI_VISIT_IN); return lerp(edge, stand, k), p/NAPOLI_VISIT_IN }
	if p < NAPOLI_VISIT_GIFT { return stand, 0 }
	k := tween.smoothstep((p-NAPOLI_VISIT_GIFT)/(1-NAPOLI_VISIT_GIFT))
	return lerp(stand, edge, k), (p-NAPOLI_VISIT_GIFT)/(1-NAPOLI_VISIT_GIFT)
}

// The table, laid for the Sunday lunch (the user's choice, Fase 5): a checked
// cloth on four legs, two plates of pasta al ragù, the parmigiana in its
// terracotta dish, the babà, a guantiera of pastries, the moka, bread and the
// wine. `p` its middle on the floor; `lift` above it (carried); `bites` how far
// the meal has gone (0 laid; 1 half: the pasta eaten, half the parmigiana and
// the babà gone).
@(private)
draw_napoli_table :: proc(renderer: ^Renderer, p: rl.Vector3, lift: f32 = 0, bites: i32 = 0) {
	base := p+rl.Vector3{0, lift, 0}
	wood := rl.Color{112, 72, 42, 255}
	for corner in ([4][2]f32{{-0.33, -0.33}, {0.33, -0.33}, {-0.33, 0.33}, {0.33, 0.33}}) {
		draw_resin_cube(renderer, base+rl.Vector3{corner.x, 0.22, corner[1]}, 0.07, 0.44, 0.07, wood)
	}
	// The cloth: red and white squares, a hem hanging down its sides.
	for y in 0..<4 { for x in 0..<4 {
		color := rl.Color{214, 52, 48, 255} if (x+y)%2 == 0 else rl.Color{244, 240, 228, 255}
		draw_resin_cube(renderer, base+rl.Vector3{-0.3+f32(x)*0.2, 0.47, -0.3+f32(y)*0.2}, 0.2, 0.05, 0.2, color)
	} }
	draw_resin_cube(renderer, base+rl.Vector3{0, 0.41, 0}, 0.84, 0.08, 0.84, {196, 44, 42, 255})
	top := f32(0.5)
	plate := rl.Color{250, 250, 246, 255}
	half := bites >= 1
	// The pasta al ragù: two plates, wiped clean once eaten.
	for at in ([2][2]f32{{-0.2, 0.18}, {0.2, -0.2}}) {
		c := base+rl.Vector3{at.x, top+0.012, at[1]}
		draw_resin_cube(renderer, c, 0.22, 0.025, 0.22, plate)
		if half {
			draw_resin_cube(renderer, c+{0, 0.016, 0}, 0.07, 0.008, 0.05, {196, 120, 80, 255})
			continue
		}
		draw_resin_cube(renderer, c+{0, 0.03, 0}, 0.15, 0.04, 0.15, {236, 196, 104, 255})
		draw_resin_cube(renderer, c+{0, 0.055, 0}, 0.09, 0.025, 0.09, {170, 36, 30, 255})
		draw_resin_cube(renderer, c+{0.02, 0.07, -0.01}, 0.03, 0.012, 0.03, {246, 236, 210, 255})
	}
	// The parmigiana: its dish, the layers of aubergine, sauce and cheese; half of it gone.
	{
		c := base+rl.Vector3{0.2, top+0.03, 0.16}
		draw_resin_cube(renderer, c, 0.24, 0.06, 0.17, {176, 86, 46, 255})
		width := f32(0.1) if half else f32(0.2)
		shift := f32(0.05) if half else 0
		draw_resin_cube(renderer, c+{shift, 0.03, 0}, width, 0.03, 0.13, {92, 52, 70, 255})
		draw_resin_cube(renderer, c+{shift, 0.05, 0}, width, 0.02, 0.13, {188, 44, 34, 255})
		for spot in ([3][2]f32{{-0.05, -0.03}, {0.03, 0.03}, {0.07, -0.04}}) {
			if half && spot.x < 0 { continue }
			draw_resin_cube(renderer, c+{spot.x, 0.065, spot[1]}, 0.04, 0.012, 0.035, {244, 214, 120, 255})
		}
	}
	// The babà on their plate: three, then one.
	{
		c := base+rl.Vector3{-0.2, top+0.012, -0.18}
		draw_resin_cube(renderer, c, 0.16, 0.02, 0.16, plate)
		cakes := [3][2]f32{{-0.04, -0.03}, {0.04, -0.02}, {0, 0.04}}
		for cake, k in cakes {
			if half && k > 0 { continue }
			at := c+rl.Vector3{cake.x, 0.045, cake[1]}
			draw_resin_cube(renderer, at, 0.05, 0.07, 0.05, {196, 128, 52, 255})
			draw_resin_cube(renderer, at+{0, 0.04, 0}, 0.055, 0.02, 0.055, {222, 160, 70, 255})
		}
	}
	// The guantiera of pastries in its gilded paper tray, in the middle.
	{
		c := base+rl.Vector3{0, top+0.012, 0}
		draw_resin_cube(renderer, c, 0.2, 0.02, 0.14, {232, 210, 150, 255})
		colors := [4]rl.Color{{238, 214, 160, 255}, {120, 70, 40, 255}, {246, 240, 226, 255}, {214, 150, 80, 255}}
		for k in 0..<4 {
			at := c+rl.Vector3{-0.06+f32(k%2)*0.12, 0.03, -0.03+f32(k/2)*0.06}
			draw_resin_cube(renderer, at, 0.06, 0.035, 0.045, colors[k])
		}
	}
	// The moka: its eight-sided steel body, its waist, its black handle.
	{
		c := base+rl.Vector3{-0.31, top, 0.31}
		steel := rl.Color{176, 182, 192, 255}
		draw_resin_cube(renderer, c+{0, 0.05, 0}, 0.09, 0.1, 0.09, steel)
		draw_resin_cube(renderer, c+{0, 0.11, 0}, 0.06, 0.03, 0.06, {120, 126, 138, 255})
		draw_resin_cube(renderer, c+{0, 0.16, 0}, 0.08, 0.08, 0.08, steel)
		draw_resin_cube(renderer, c+{0, 0.205, 0}, 0.03, 0.015, 0.03, {40, 40, 46, 255})
		draw_resin_cube(renderer, c+{-0.065, 0.13, 0}, 0.025, 0.09, 0.025, {32, 30, 34, 255})
	}
	// The bread and the wine.
	draw_resin_cube(renderer, base+rl.Vector3{0.3, top+0.03, -0.33}, 0.16, 0.06, 0.08, {214, 160, 84, 255})
	draw_resin_cube(renderer, base+rl.Vector3{0.33, top+0.1, 0.33}, 0.07, 0.2, 0.07, {38, 92, 46, 255})
	draw_resin_cube(renderer, base+rl.Vector3{0.33, top+0.23, 0.33}, 0.03, 0.06, 0.03, {38, 92, 46, 255})
}

// How far the meal at a table has gone, from its `life` (the meal's beats left,
// 0 before it): 0 laid, 1 half eaten.
napoli_table_bites :: proc(life: i32) -> i32 {
	if life <= 0 || life >= game.NAPOLI_FEAST_BEATS { return 0 }
	return game.NAPOLI_FEAST_BEATS-life
}

// Whether the grandpa is still to bring the table, or bringing it (his visit
// queued behind the die, or under way): the board's own table waits.
napoli_table_carried :: proc(renderer: ^Renderer) -> bool {
	for offset in 0..<renderer_queued_cue_count(renderer) {
		cue, found := renderer_queued_cue_at(renderer, offset)
		if found && cue.kind == .Napoli_Begun && cue.event.duration == 2 { return true }
	}
	return false
}

// In the props' pass (the resin shader on): the table in the grandpa's arms,
// then where he set it, until its own spawn shows it.
@(private)
draw_napoli_visit_table :: proc(renderer: ^Renderer, room: ^game.Room) {
	cue, found := napoli_visit_cue(renderer)
	if !found || cue.event.duration != 2 { return }
	index, laid := game.napoli_table_index(room)
	if !laid { return }
	cell := room.objects[index].position
	edge, stand := napoli_visit_way(renderer, room, cell)
	p := presentation_cue_progress(cue)
	at, walking := napoli_visit_at(edge, stand, p)
	ground := entity_point_ground(NO_FIGURE, {f32(cell.x), f32(cell.y)})
	if p < NAPOLI_VISIT_IN {
		// Carried before him, at his chest, swaying with his steps.
		front := rl.Vector3{f32(cell.x)-stand.x, 0, f32(cell.y)-stand.y}*0.45
		bob := 0.04*f32(math.abs(math.sin(walking*math.PI*6)))
		draw_napoli_table(renderer, {at.x+0.5+front.x, ground, at.y+0.5+front.z}, 0.32+bob)
	} else if p < NAPOLI_VISIT_GIFT {
		// Set down on its cell.
		k := tween.smoothstep((p-NAPOLI_VISIT_IN)/(NAPOLI_VISIT_GIFT-NAPOLI_VISIT_IN))
		from := rl.Vector3{stand.x+0.5+(f32(cell.x)-stand.x)*0.45, ground, stand.y+0.5+(f32(cell.y)-stand.y)*0.45}
		to := rl.Vector3{f32(cell.x)+0.5, ground, f32(cell.y)+0.5}
		draw_napoli_table(renderer, from+(to-from)*k, 0.32*(1-k))
	} else {
		draw_napoli_table(renderer, {f32(cell.x)+0.5, ground, f32(cell.y)+0.5})
	}
}

// The grandpa in the sorted cards, while he visits (the player as the grandpa
// is a 3D model: first_person_club.odin).
@(private)
collect_napoli_entries :: proc(renderer: ^Renderer, room: ^game.Room, entries: ^[dynamic]Tactical_Alpha_Entry) {
	cue, found := napoli_visit_cue(renderer)
	if !found { return }
	edge, stand := napoli_visit_way(renderer, room, napoli_gift_cell(room, cue))
	at, _ := napoli_visit_at(edge, stand, presentation_cue_progress(cue))
	append(entries, Tactical_Alpha_Entry{kind = .Napoli, position = at, opacity = 1})
}

// The grandpa's print on his way, his steps bobbing; with the purse, the purse
// held out and flying to the player.
@(private)
draw_napoli_entry :: proc(renderer: ^Renderer, room: ^game.Room, entry: Tactical_Alpha_Entry) {
	n := &renderer.tactical.napoli
	if n.nonno.id == 0 { n.nonno = napoli_print(NAPOLI_NONNO_ART[:]) }
	if n.purse.id == 0 { n.purse = napoli_print(NAPOLI_PURSE_ART[:]) }
	cue, found := napoli_visit_cue(renderer)
	if !found { return }
	gift := napoli_gift_cell(room, cue)
	edge, stand := napoli_visit_way(renderer, room, gift)
	p := presentation_cue_progress(cue)
	_, walking := napoli_visit_at(edge, stand, p)
	ground := entity_point_ground(NO_FIGURE, entry.position)
	bob := 0.05*f32(math.abs(math.sin(walking*math.PI*6))) if walking > 0 else 0
	height := NAPOLI_PRINT_HEIGHT
	marley_draw_print(renderer, n.nonno, {entry.position.x+0.5, ground+height*0.5+bob, entry.position.y+0.5}, height, 0, rl.WHITE)
	if cue.event.duration != 3 { return }
	// The purse: in his hand coming in, then tossed to the player.
	hand := rl.Vector3{entry.position.x+0.5, ground+0.45+bob, entry.position.y+0.5}
	if p >= NAPOLI_VISIT_IN {
		k := clamp((p-NAPOLI_VISIT_IN)/(NAPOLI_VISIT_GIFT-NAPOLI_VISIT_IN), f32(0), f32(1))
		if k >= 1 { return }
		to := rl.Vector3{f32(gift.x)+0.5, entity_point_ground(NO_FIGURE, {f32(gift.x), f32(gift.y)})+0.45, f32(gift.y)+0.5}
		hand = hand+(to-hand)*k+rl.Vector3{0, 0.4*math.sin(k*math.PI), 0}
	}
	marley_draw_print(renderer, n.purse, hand, 0.3, 0, rl.WHITE)
}

// Pixel art (one letter a texel, '.' clear) cut from paper as the board's prints.
@(private = "file")
napoli_print :: proc(art: []string) -> rl.Texture2D {
	h := len(art)
	w := len(art[0])
	pixels := make([]rl.Color, w*h, context.temp_allocator)
	for line, y in art {
		for x in 0..<w {
			pixels[y*w+x] = napoli_ink(line[x])
		}
	}
	return marley_paper_texture(pixels, w, h, 3, 1)
}

@(private = "file")
napoli_ink :: proc(letter: u8) -> rl.Color {
	switch letter {
	case 'K': return {13, 20, 30, 255}
	case 'C': return {74, 68, 66, 255}
	case 'c': return {104, 96, 92, 255}
	case 'S': return {232, 184, 146, 255}
	case 's': return {196, 146, 112, 255}
	case 'W': return {246, 244, 236, 255}
	case 'V': return {52, 46, 62, 255}
	case 'P': return {88, 74, 58, 255}
	case 'p': return {62, 52, 42, 255}
	case 'B': return {40, 28, 22, 255}
	case 'R': return {178, 40, 40, 255}
	case 'L': return {132, 86, 46, 255}
	case 'l': return {170, 116, 66, 255}
	case 'Y': return {236, 196, 72, 255}
	case 'y': return {196, 152, 56, 255}
	case 'w': return {206, 204, 196, 255}
	case 'U': return {64, 104, 170, 255}
	case 'u': return {40, 70, 130, 255}
	}
	return {}
}

// The grandpa at the seaside (the user's choice, Fase 5): a straw hat with a
// red band, a big white moustache, a white vest over his belly, blue shorts,
// white socks in brown sandals.
@(private = "file", rodata)
NAPOLI_NONNO_ART := [27]string{
	"......KKKKKK......",
	".....KYYYYYYK.....",
	".....KYyYYyYK.....",
	".....KRRRRRRK.....",
	"..KKKYYYYYYYYKKK..",
	".KYYYYYYYYYYYYYYK.",
	"..KKKKSSSSSSKKKK..",
	"....KSSKSSKSSK....",
	"....KSSSSsSSSK....",
	"....KWWWWWWWWK....",
	"....KsWWSSWWsK....",
	".....KSSSSSSK.....",
	"......KKSSKK......",
	"...KKSWWWWWWSKK...",
	"..KSSKWWWWWWKSSK..",
	"..KSKWWWWWWWWKSK..",
	"..KSKWWWWWWWWKSK..",
	"..KsKwWWWWWWwKsK..",
	"..KSKKwWWWWwKKSK..",
	"..KKKUUUUUUUUKKK..",
	"....KUUUUUUUUK....",
	"....KUUuKKuUUK....",
	"....KSSSKKSSSK....",
	"....KSSSKKSSSK....",
	"....KWWWKKWWWK....",
	"...KLLLLKKLLLLK...",
	"...KKKKKK.KKKKKK..",
}

// The purse: leather, tied at its neck, gold showing.
@(private = "file", rodata)
NAPOLI_PURSE_ART := [10]string{
	"...KKKK...",
	"..KYKKYK..",
	"...KllK...",
	"..KLLLLK..",
	".KLlLLLLK.",
	"KLlLLLLLLK",
	"KLLLLYLLLK",
	"KLLLYYYLLK",
	".KLLLLLLK.",
	"..KKKKKK..",
}

// Over the view's plate while the player is the grandpa: his health (as the
// board's cues show it) and his two keys, lit until used.
@(private)
draw_napoli_nonno_hud :: proc(renderer: ^Renderer, room: ^game.Room, plate: rl.Rectangle) {
	if room == nil || !game.napoli_nonno_active(room) { return }
	n := &room.first_person.nonno
	health, most := n.health, n.most
	if s := renderer.tactical.snapshot; s != nil && s.nonno.active { health, most = s.nonno.health, s.nonno.most }
	bounds := rl.Rectangle{plate.x, plate.y-58, plate.width, 50}
	hud_frame(bounds, NAPOLI_LABEL_COLOR)
	gothic_text_fit(renderer, fmt.ctprintf("NONNO %d/%d", health, most), {bounds.x+12, bounds.y+4, bounds.width-24, 22}, 16, GOTHIC_PAPER)
	hud_bar({bounds.x+12, bounds.y+bounds.height-14, bounds.width-24, 8}, f32(health)/f32(max(most, 1)), GOTHIC_RED, 0)
	keys := [2]struct{label: cstring, used: bool}{{"Q CURA", n.healed}, {"E SOLDI", n.paid}}
	for key, index in keys {
		at := rl.Rectangle{plate.x+plate.width+8+f32(index)*92, plate.y, 84, plate.height}
		hud_frame(at, NAPOLI_LABEL_COLOR if !key.used else GOTHIC_STEEL)
		gothic_text_fit(renderer, key.label, {at.x+8, at.y+12, at.width-16, 22}, 16, GOTHIC_PAPER if !key.used else color_with_opacity(GOTHIC_PAPER, 0.35))
	}
}
