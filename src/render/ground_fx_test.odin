package render

import "core:math"
import "core:testing"
import rl "vendor:raylib"
import audio "../engine/audio"
import game "../game"
import grid "../engine/grid"
import level "../level"

// The ground on the board (ground_fx.odin): the snapshot carries it and shows
// a card's pool from its landing; the decal merges neighbouring pools, keeps
// diagonal ones apart, cuts them from paper and bakes the same incrementally
// as at once; the flames stand on the burning cells; a card stepping into a
// pool splashes.

ground_test_level :: proc(t: ^testing.T) -> level.Level {
	rows := [?]string{"###########", "#.........#", "#.........#", "#....@....#", "#.........#", "#........>#", "###########"}
	data, err, _ := level.from_ascii(rows[:])
	testing.expect_value(t, err, level.Parse_Error.None)
	return data
}

ground_test_pour :: proc(room: ^game.Room, kind: game.Status_Kind, cell: grid.Position, amount: i32 = 2) -> bool {
	action := game.make_action(.Card, game.PLAYER_ENTITY, game.cell_target(cell), .Walkable_Cell)
	return game.add_effect(&action, game.place_ground_effect(cell, kind, amount)) && game.resolve_action(room, &action).accepted
}

ground_test_is_venom :: proc(fx: ^Ground_Fx, gx, gy: int) -> bool {
	at := (gy*fx.width*fx.texels+gx)*4
	c := [4]u8{fx.pixels[at], fx.pixels[at+1], fx.pixels[at+2], fx.pixels[at+3]}
	for colour in ([?][4]u8{
		{GROUND_VENOM.r, GROUND_VENOM.g, GROUND_VENOM.b, 255}, {GROUND_VENOM_DEEP.r, GROUND_VENOM_DEEP.g, GROUND_VENOM_DEEP.b, 255},
		{GROUND_VENOM_LIGHT.r, GROUND_VENOM_LIGHT.g, GROUND_VENOM_LIGHT.b, 255}, {GROUND_VENOM_GLINT.r, GROUND_VENOM_GLINT.g, GROUND_VENOM_GLINT.b, 255},
		{GROUND_VENOM_BUBBLE.r, GROUND_VENOM_BUBBLE.g, GROUND_VENOM_BUBBLE.b, 255},
	}) { if c == colour { return true } }
	return false
}

ground_test_pixel :: proc(fx: ^Ground_Fx, gx, gy: int) -> [4]u8 {
	at := (gy*fx.width*fx.texels+gx)*4
	return {fx.pixels[at], fx.pixels[at+1], fx.pixels[at+2], fx.pixels[at+3]}
}

// Whether the liquid runs from texel `from` to texel `to` (4-neighbour).
ground_test_joined :: proc(fx: ^Ground_Fx, from, to: grid.Position) -> bool {
	width, height := fx.width*fx.texels, fx.height*fx.texels
	seen := make([]bool, width*height)
	defer delete(seen)
	queue: [dynamic]grid.Position
	defer delete(queue)
	append(&queue, from)
	seen[from.y*width+from.x] = true
	for head := 0; head < len(queue); head += 1 {
		at := queue[head]
		if at == to { return true }
		for step in ([4]grid.Position{{x = 1, y = 0}, {x = -1, y = 0}, {x = 0, y = 1}, {x = 0, y = -1}}) {
			next := grid.offset(at, step.x, step.y)
			if next.x < 0 || next.y < 0 || next.x >= width || next.y >= height || seen[next.y*width+next.x] ||
			   !ground_test_is_venom(fx, next.x, next.y) { continue }
			seen[next.y*width+next.x] = true
			append(&queue, next)
		}
	}
	return false
}

ground_test_free :: proc(fx: ^Ground_Fx) {
	delete(fx.cells)
	delete(fx.pixels)
	delete(fx.wanted)
	delete(fx.centre)
	delete(fx.last)
}

@(test)
test_ground_snapshot_shows_a_pool_from_its_landing :: proc(t: ^testing.T) {
	data := ground_test_level(t)
	defer level.destroy(&data)
	player := spell_presentation_player(t, .Poison_Pool)
	testing.expect(t, game.configure_tactical(&player, game.DEFAULT_TACTICAL_CONFIG))
	enemies := [?]game.Enemy_Spawn{{position = {x = 8, y = 1}, health = 20, attack = 1}}
	room, created := game.create_room(&data, &player, {enemies = enemies[:]})
	testing.expect(t, created)
	defer game.destroy_room(&room)
	cell := grid.Position{x = 5, y = 1}
	before := capture_room_presentation(&room)
	played := game.play_card(&room, player.deck.hand[0].id, game.cell_target(cell))
	testing.expect(t, game.card_play_was_committed(played.result))
	after := capture_room_presentation(&room)
	testing.expect(t, !presentation_ground_pool(&before.ground, cell) && presentation_ground_pool(&after.ground, cell))
	testing.expect(t, !presentation_ground_pool(&after.ground, {x = 4, y = 1}) && after.ground.width == data.tiles.width)
	renderer := new(Renderer)
	defer { destroy_renderer_world_playback(renderer); free(renderer) }
	testing.expect(t, begin_renderer_event_timeline(renderer, before, room.recent_events, &after))
	timeline := &renderer.timeline
	landed := false
	for _ in 0..<2000 {
		cue, found := active_presentation_cue(timeline)
		if !found { break }
		if cue.started {
			shown := presentation_ground_pool(&timeline.view.ground, cell)
			if cue.kind == .Spell_Impact { landed = true }
			testing.expectf(t, shown == landed, "%v: the pool shown %v", cue.kind, shown)
			// The board's snapshot keeps the shown floor while gameplay stays as it ended.
			snapshot := renderer_presentation_snapshot(renderer, &room)
			testing.expect_value(t, presentation_ground_pool(&snapshot.ground, cell), landed)
		}
		update_event_timeline(timeline, 0.01)
	}
	testing.expect(t, landed && !event_timeline_is_busy(timeline))
	testing.expect_value(t, timeline.update_failures, 0)
	testing.expect_value(t, timeline.dropped_count, 0)
	snapshot := renderer_presentation_snapshot(renderer, &room)
	testing.expect(t, presentation_ground_pool(&snapshot.ground, cell))
	// The fires are copied as they stand: a centre and its arms.
	testing.expect(t, ground_test_pour(&room, .Burn, {x = 3, y = 4}, 2))
	burn: game.Pulse_Report
	game.grow_ground_fires(&room, &burn)
	fires := capture_room_presentation(&room)
	testing.expect_value(t, fires.ground.fire_count, 1)
	value, centre, last := presentation_ground_burn(&fires.ground, {x = 3, y = 4})
	testing.expect(t, value == 2 && centre && !last)
	value, centre, _ = presentation_ground_burn(&fires.ground, {x = 3, y = 5})
	testing.expect(t, value == 2 && !centre)
	value, _, _ = presentation_ground_burn(&fires.ground, {x = 3, y = 6})
	testing.expect_value(t, value, i32(0))
}

// Neighbouring pool cells are one puddle, cells meeting at a corner two; the
// liquid has paper round it, then ink, then the cut edge toward the camera.
// The rows the bake computes are the texel-by-texel cut.
@(test)
test_ground_decal_merges_neighbours_and_cuts_them_from_paper :: proc(t: ^testing.T) {
	fx: Ground_Fx
	defer ground_test_free(&fx)
	ground_fx_resize(&fx, 11, 9)
	tx := fx.texels
	for cell in ([?]grid.Position{{x = 2, y = 2}, {x = 3, y = 2}, {x = 6, y = 5}, {x = 7, y = 6}, {x = 2, y = 6}}) { fx.cells[cell.y*fx.width+cell.x].layers += {.Pool} }
	for y in 0..<fx.height { for x in 0..<fx.width {
		fx.cells[y*fx.width+x].content = bake_ground_cell(&fx, {x = x, y = y})
	} }
	// One across the shared side of (2, 2) and (3, 2)...
	for v in tx/4..<tx*3/4 { testing.expect(t, ground_test_is_venom(&fx, 3*tx, 2*tx+v) && ground_test_is_venom(&fx, 3*tx-1, 2*tx+v)) }
	testing.expect(t, ground_test_joined(&fx, {x = 2*tx+tx/2, y = 2*tx+tx/2}, {x = 3*tx+tx/2, y = 2*tx+tx/2}))
	// ...two at the corner (6, 5) and (7, 6) share.
	testing.expect(t, ground_test_is_venom(&fx, 6*tx+tx/2, 5*tx+tx/2) && ground_test_is_venom(&fx, 7*tx+tx/2, 6*tx+tx/2))
	testing.expect(t, !ground_test_joined(&fx, {x = 6*tx+tx/2, y = 5*tx+tx/2}, {x = 7*tx+tx/2, y = 6*tx+tx/2}))
	// The lone pool (2, 6): its middle row from the centre to the right runs
	// liquid, paper, ink, then the cut edge; to the left liquid, paper, ink.
	row := 6*tx+tx/2
	x := 2*tx+tx/2
	for ground_test_is_venom(&fx, x, row) { x += 1 }
	paper := [4]u8{LIVING_TOKEN_PAPER.r, LIVING_TOKEN_PAPER.g, LIVING_TOKEN_PAPER.b, 255}
	ink := [4]u8{LIVING_TOKEN_INK.r, LIVING_TOKEN_INK.g, LIVING_TOKEN_INK.b, 255}
	edge := [4]u8{LIVING_TOKEN_EDGE.r, LIVING_TOKEN_EDGE.g, LIVING_TOKEN_EDGE.b, 255}
	testing.expect(t, ground_test_pixel(&fx, x, row) == paper && ground_test_pixel(&fx, x+1, row) == paper)
	for ground_test_pixel(&fx, x, row) == paper { x += 1 }
	testing.expect_value(t, ground_test_pixel(&fx, x, row), ink)
	after := ground_test_pixel(&fx, x+1, row)
	testing.expect(t, after == edge || after[3] == 0)
	testing.expect_value(t, ground_test_pixel(&fx, x+3, row)[3], u8(0))
	// Under it, the cut edge shows below the ink (toward the camera).
	y := 6*tx+tx/2
	for ground_test_is_venom(&fx, 2*tx+tx/2, y) { y += 1 }
	for ground_test_pixel(&fx, 2*tx+tx/2, y) == paper { y += 1 }
	testing.expect_value(t, ground_test_pixel(&fx, 2*tx+tx/2, y), ink)
	testing.expect_value(t, ground_test_pixel(&fx, 2*tx+tx/2+1, y+1), edge)
	x = 2*tx+tx/2
	for ground_test_is_venom(&fx, x, row) { x -= 1 }
	testing.expect(t, ground_test_pixel(&fx, x, row) == paper && ground_test_pixel(&fx, x-1, row) == paper)
	for ground_test_pixel(&fx, x, row) == paper { x -= 1 }
	testing.expect_value(t, ground_test_pixel(&fx, x, row), ink)
	testing.expect_value(t, ground_test_pixel(&fx, x-1, row)[3], u8(0))
	// The bake's rows against the cut texel by texel, everywhere.
	for gy in 0..<fx.height*tx { for gx in 0..<fx.width*tx {
		if ground_test_is_venom(&fx, gx, gy) != ground_texel_liquid(&fx, .Pool, gx, gy) {
			testing.expectf(t, false, "texel %d, %d", gx, gy)
			return
		}
	} }
	// A cell far from any pool is not drawn at all.
	testing.expect(t, !fx.cells[0].content && fx.cells[2*fx.width+2].content)
}

// Pools poured one by one and baked a few cells a frame give the very
// texture of baking their final floor at once.
@(test)
test_ground_decal_bakes_the_same_a_little_at_a_time :: proc(t: ^testing.T) {
	steps := [?]struct{cell: grid.Position, layers: Ground_Layers}{
		{{x = 4, y = 4}, {.Pool}}, {{x = 5, y = 4}, {.Pool}}, {{x = 4, y = 3}, {.Char}}, {{x = 5, y = 5}, {.Pool, .Char}}, {{x = 5, y = 4}, {}}, {{x = 1, y = 1}, {.Pool}},
	}
	whole: Ground_Fx
	defer ground_test_free(&whole)
	ground_fx_resize(&whole, 10, 8)
	for step in steps { whole.cells[step.cell.y*whole.width+step.cell.x].layers = step.layers }
	for y in 0..<whole.height { for x in 0..<whole.width { whole.cells[y*whole.width+x].content = bake_ground_cell(&whole, {x = x, y = y}) } }
	step_by_step: Ground_Fx
	defer ground_test_free(&step_by_step)
	ground_fx_resize(&step_by_step, 10, 8)
	for step in steps {
		step_by_step.cells[step.cell.y*step_by_step.width+step.cell.x].layers = step.layers
		ground_fx_mark(&step_by_step, step.cell)
		step_by_step.seed = step.cell
		ground_fx_bake(&step_by_step, 7)
	}
	for step_by_step.pending > 0 { ground_fx_bake(&step_by_step, 7) }
	testing.expect(t, len(whole.pixels) == len(step_by_step.pixels))
	same := true
	for value, index in whole.pixels { same = same && step_by_step.pixels[index] == value }
	testing.expect(t, same)
	for cell, index in whole.cells { testing.expect_value(t, step_by_step.cells[index].content, cell.content) }
}

// The flames stand on every burning cell the board shows, sink once the fire
// is out; a card stepping into a pool splashes. The lab hears the fire grow
// and go out, and the splash.
@(test)
test_ground_flames_and_splashes_follow_the_board :: proc(t: ^testing.T) {
	data := ground_test_level(t)
	defer level.destroy(&data)
	player, made := game.create_player({max_health = 20, attack = 2})
	testing.expect(t, made)
	config := game.DEFAULT_TACTICAL_CONFIG
	config.vision_size = 0
	testing.expect(t, game.configure_tactical(&player, config))
	enemies := [?]game.Enemy_Spawn{{position = {x = 8, y = 1}, health = 20, attack = 1}}
	room, created := game.create_room(&data, &player, {enemies = enemies[:]})
	testing.expect(t, created)
	defer game.destroy_room(&room)
	snapshot: Room_Presentation
	renderer := attack_test_renderer(&snapshot)
	defer { destroy_ground_fx(renderer); attack_test_free(renderer) }
	renderer.tactical.attack_props.loaded = true
	defer renderer.tactical.attack_props.loaded = false
	renderer.tactical.mechanics_lab = true
	renderer.tactical.lab_sounds = new(Lab_Sounds)
	// Past the queue's repeat guard, which counts a clock at 0 as just played.
	renderer.sprite_assets.elapsed = 1
	frame :: proc(renderer: ^Renderer, room: ^game.Room, snapshot: ^Room_Presentation, dt: f64 = 1.0/60) {
		snapshot^ = renderer_presentation_snapshot(renderer, room)
		update_ground_fx(renderer, room)
		renderer.sprite_assets.elapsed += dt
	}
	flames :: proc(renderer: ^Renderer, room: ^game.Room) -> int {
		entries: [dynamic]Tactical_Alpha_Entry
		defer delete(entries)
		collect_ground_entries(renderer, room, &entries)
		count := 0
		for entry in entries { if entry.kind == .Ground && int(entry.ground) < len(renderer.tactical.ground.cells) { count += 1 } }
		return count
	}
	queued :: proc(renderer: ^Renderer, sfx: audio.Lab_Sfx) -> (count: int) {
		sounds := renderer.tactical.lab_sounds
		for sound in sounds.queue[:sounds.count] { if sound.sfx == sfx { count += 1 } }
		return
	}
	testing.expect(t, ground_test_pour(&room, .Burn, {x = 3, y = 3}, 1))
	burn: game.Pulse_Report
	game.grow_ground_fires(&room, &burn)
	frame(renderer, &room, &snapshot)
	testing.expect_value(t, flames(renderer, &room), 5)
	fx := renderer.tactical.ground
	testing.expect(t, fx.cells[3*fx.width+3].fire && fx.cells[3*fx.width+3].centre && !fx.cells[3*fx.width+4].centre)
	// The lab: a fire just lit is its card's landing, not a spread; its arms
	// reaching further at a new window roar once, and it hisses out once.
	testing.expect_value(t, queued(renderer, .World_Fire_Spread), 0)
	game.grow_ground_fires(&room, &burn)
	frame(renderer, &room, &snapshot)
	frame(renderer, &room, &snapshot)
	testing.expect_value(t, flames(renderer, &room), 9)
	testing.expect_value(t, queued(renderer, .World_Fire_Spread), 1)
	testing.expect_value(t, queued(renderer, .World_Fire_Out), 0)
	for _ in 0..<3 { game.grow_ground_fires(&room, &burn) }
	testing.expect_value(t, room.ground.fire_count, 0)
	frame(renderer, &room, &snapshot)
	frame(renderer, &room, &snapshot)
	testing.expect_value(t, queued(renderer, .World_Fire_Out), 1)
	testing.expect_value(t, queued(renderer, .World_Fire_Spread), 1)
	// Out: the flames sink for a moment, the scorch under them, then both go.
	testing.expect_value(t, flames(renderer, &room), 9)
	testing.expect(t, .Char in fx.cells[3*fx.width+3].layers)
	frame(renderer, &room, &snapshot, GROUND_FLAME_OUT_SECONDS+0.1)
	frame(renderer, &room, &snapshot)
	testing.expect_value(t, flames(renderer, &room), 0)
	testing.expect(t, .Char not_in fx.cells[3*fx.width+3].layers)
	// A card steps into a pool: one splash, its sound queued.
	testing.expect(t, ground_test_pour(&room, .Poison, {x = 7, y = 1}))
	frame(renderer, &room, &snapshot)
	splashed := fx.splashed
	room.enemies[0].position = {x = 7, y = 1}
	frame(renderer, &room, &snapshot)
	frame(renderer, &room, &snapshot)
	testing.expect_value(t, fx.splashed, splashed+1)
	testing.expect_value(t, queued(renderer, .World_Pool_Splash), 1)
	// A new board starts dry.
	forget_ground_fx(renderer)
	testing.expect(t, fx.cells[1*fx.width+7].layers == {} && fx.tracked_count == 0 && fx.fire_count == 0)
}

ground_test_bake_all :: proc(fx: ^Ground_Fx) {
	for y in 0..<fx.height { for x in 0..<fx.width { fx.cells[y*fx.width+x].content = bake_ground_cell(fx, {x = x, y = y}) } }
}

// Where texels of `colour` lie around a lone pool: their mean against the
// middle of the pool's cell, in texels, and how many there are.
ground_test_side :: proc(fx: ^Ground_Fx, pool: grid.Position, colour: rl.Color) -> (dx, dy: f32, count: int) {
	tx := fx.texels
	cx, cy := f32(pool.x*tx)+f32(tx)*0.5, f32(pool.y*tx)+f32(tx)*0.5
	for gy in (pool.y-1)*tx..<(pool.y+2)*tx { for gx in (pool.x-1)*tx..<(pool.x+2)*tx {
		if ground_test_pixel(fx, gx, gy) != {colour.r, colour.g, colour.b, 255} { continue }
		dx += f32(gx)+0.5-cx
		dy += f32(gy)+0.5-cy
		count += 1
	} }
	if count > 0 { dx, dy = dx/f32(count), dy/f32(count) }
	return
}

// The decal's cut edge shows toward the camera and the liquid's light on its
// far side whichever way the camera looks across the board: a camera orbited
// round to the other side has the floor baked again for it, the same as if it
// had always looked from there; one resting near an axis keeps its diagonal.
@(test)
test_ground_decal_cuts_toward_the_orbiting_camera :: proc(t: ^testing.T) {
	fx: Ground_Fx
	defer ground_test_free(&fx)
	ground_fx_resize(&fx, 11, 9)
	pool := grid.Position{x = 5, y = 4}
	fx.cells[pool.y*fx.width+pool.x].layers += {.Pool}
	ground_test_bake_all(&fx)
	ex, ey, edges := ground_test_side(&fx, pool, LIVING_TOKEN_EDGE)
	lx, ly, lights := ground_test_side(&fx, pool, GROUND_VENOM_LIGHT)
	testing.expect(t, edges > 0 && ex > 0 && ey > 0)
	testing.expect(t, lights > 0 && lx < 0 && ly < 0)
	// The camera on the board's axis, 45 degrees off the diagonal, or 50: kept.
	angle :: proc(degrees: f32) -> rl.Vector3 {
		r := degrees*math.PI/180
		return {math.cos(r), 0, math.sin(r)}
	}
	for degrees in ([3]f32{90, 95, -5}) { testing.expect(t, !ground_fx_face(&fx, angle(degrees), pool)) }
	testing.expect(t, fx.pending == 0 && !fx.camera_west && !fx.camera_north)
	// Orbited round to the other side: every cell near the pool bakes again,
	// from the cell looked at out.
	testing.expect(t, ground_fx_face(&fx, angle(225), pool))
	testing.expect(t, fx.camera_west && fx.camera_north && fx.pending == 25 && fx.seed == pool)
	for fx.pending > 0 { ground_fx_bake(&fx, GROUND_BAKES_PER_FRAME) }
	ex, ey, edges = ground_test_side(&fx, pool, LIVING_TOKEN_EDGE)
	lx, ly, lights = ground_test_side(&fx, pool, GROUND_VENOM_LIGHT)
	testing.expect(t, edges > 0 && ex < 0 && ey < 0)
	testing.expect(t, lights > 0 && lx > 0 && ly > 0)
	direct: Ground_Fx
	defer ground_test_free(&direct)
	ground_fx_resize(&direct, 11, 9)
	direct.camera_west, direct.camera_north = true, true
	direct.cells[pool.y*direct.width+pool.x].layers += {.Pool}
	ground_test_bake_all(&direct)
	same := len(direct.pixels) == len(fx.pixels)
	for value, index in direct.pixels { same = same && fx.pixels[index] == value }
	testing.expect(t, same)
	// Sixty degrees past its diagonal it turns again: the board's west and south.
	testing.expect(t, ground_fx_face(&fx, angle(105), pool))
	testing.expect(t, fx.camera_west && !fx.camera_north)
}

// The ground follows the board once a frame, as the board begins (one budget
// of cells baked): the sorted pass of walls, cards and flames reads it as it
// stands. Its decal follows the board's own camera round.
@(test)
test_the_ground_is_followed_once_a_frame :: proc(t: ^testing.T) {
	data := ground_test_level(t)
	defer level.destroy(&data)
	player, made := game.create_player({max_health = 20, attack = 2})
	testing.expect(t, made)
	config := game.DEFAULT_TACTICAL_CONFIG
	config.vision_size = 0
	testing.expect(t, game.configure_tactical(&player, config))
	enemies := [?]game.Enemy_Spawn{{position = {x = 9, y = 4}, health = 20, attack = 1}}
	room, created := game.create_room(&data, &player, {enemies = enemies[:]})
	testing.expect(t, created)
	defer game.destroy_room(&room)
	snapshot: Room_Presentation
	renderer := attack_test_renderer(&snapshot)
	defer { destroy_tactical_translucents(renderer); destroy_ground_fx(renderer); attack_test_free(renderer) }
	// No living cards: their atlas wants a window.
	renderer.tactical.living = false
	for cell in ([3]grid.Position{{x = 2, y = 2}, {x = 7, y = 4}, {x = 8, y = 1}}) { testing.expect(t, ground_test_pour(&room, .Poison, cell)) }
	snapshot = renderer_presentation_snapshot(renderer, &room)
	update_ground_fx(renderer, &room)
	fx := renderer.tactical.ground
	testing.expect(t, fx != nil && fx.pending > GROUND_BAKES_PER_FRAME)
	if fx == nil { return }
	pending := fx.pending
	_ = collect_tactical_translucents(renderer, &room)
	testing.expect_value(t, fx.pending, pending)
	update_ground_fx(renderer, &room)
	testing.expect_value(t, fx.pending, pending-GROUND_BAKES_PER_FRAME)
	// The board's camera orbited round to the north-west of what it looks at.
	testing.expect(t, !fx.camera_west && !fx.camera_north)
	renderer.tactical.camera.position = {-4, 9, -6}
	update_ground_fx(renderer, &room)
	testing.expect(t, fx.camera_west && fx.camera_north)
}

// The window's end grows the fires among the world's cues, whose board is the
// room as it ends: a fire that catches a foe stands on the foe's cell from the
// very frame its Bruciatura shows, after another foe's bite.
@(test)
test_a_fire_catches_with_its_flames_at_the_window :: proc(t: ^testing.T) {
	data := ground_test_level(t)
	defer level.destroy(&data)
	player, made := game.create_player({max_health = 20, attack = 2})
	testing.expect(t, made)
	config := game.DEFAULT_TACTICAL_CONFIG
	config.vision_size = 0
	testing.expect(t, game.configure_tactical(&player, config))
	caught := grid.Position{x = 4, y = 1}
	enemies := [?]game.Enemy_Spawn{{position = caught, health = 20, attack = 1}, {position = {x = 8, y = 4}, health = 20, attack = 1}}
	room, created := game.create_room(&data, &player, {enemies = enemies[:]})
	testing.expect(t, created)
	defer game.destroy_room(&room)
	testing.expect(t, ground_test_pour(&room, .Burn, {x = 3, y = 1}, 1))
	foe := game.enemy_entity(room.enemies[0].id)
	_, _ = game.apply_status(&room, game.enemy_entity(room.enemies[1].id), .Burn, 1, 0)
	game.clear_event_log(room.recent_events)
	before := capture_room_presentation(&room)
	player.tactical.remaining, player.tactical.phase = 0, .Decision
	testing.expect(t, game.tactical_expire_window(&room))
	after := capture_room_presentation(&room)
	burn, _, _ := presentation_ground_burn(&after.ground, caught)
	testing.expect_value(t, burn, i32(1))
	bitten := false
	for event in room.recent_events.events[:room.recent_events.count] { bitten = bitten || (event.kind == .Damaged && event.has_status_cause) }
	testing.expect(t, bitten)
	// As the game shows a window's end (commit_gameplay_command): a world command.
	renderer := new(Renderer)
	defer { destroy_renderer_world_playback(renderer); free(renderer) }
	testing.expect(t, begin_renderer_world_timeline(renderer, before, room.recent_events, &after))
	seen := false
	for _ in 0..<200 {
		snapshot := renderer_presentation_snapshot(renderer, &room)
		for offset in 0..<renderer_active_cue_count(renderer) {
			cue, found := renderer_active_cue_at(renderer, offset)
			if !found || !cue.started || cue.kind != .Status_Applied || cue.event.target != foe { continue }
			shown, _, _ := presentation_ground_burn(&snapshot.ground, caught)
			testing.expect_value(t, shown, i32(1))
			seen = true
		}
		if !renderer_world_is_busy(renderer) { break }
		update_renderer_world_playback(renderer, 0.01)
	}
	testing.expect(t, seen)
}
