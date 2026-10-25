package render

import "core:c"
import "core:math"
import "core:testing"
import rl "vendor:raylib"
import audio "../engine/audio"
import gfx "../engine/gfx"
import game "../game"
import grid "../engine/grid"
import level "../level"
import view "../engine/view"

// An open room with a wall stub: the player in the middle (6, 6) with one
// First Person Shooter in hand, a foe held three cells north, one held three
// east behind a wall two cells east of him (5, 6 sees it, the eye does not).
first_person_view_test_room :: proc(t: ^testing.T, data: ^level.Level, player: ^game.Player) -> (room: game.Room) {
	rows := [?]string{
		"#############",
		"#...........#",
		"#...........#",
		"#...........#",
		"#...........#",
		"#...........#",
		"#.....@.#...#",
		"#...........#",
		"#...........#",
		"#...........#",
		"#...........#",
		"#..........>#",
		"#############",
	}
	parsed: level.Parse_Error
	data^, parsed, _ = level.from_ascii(rows[:])
	testing.expect_value(t, parsed, level.Parse_Error.None)
	made: bool
	player^, made = game.create_player({max_health = 40, attack = 2})
	testing.expect(t, made)
	testing.expect(t, game.initialize_empty_deck(&player.deck, {hand_size = 1, max_energy = 3, energy_regen_per_pulse = 1}, 99))
	_, added := game.add_owned_card(&player.deck, .First_Person)
	testing.expect(t, added)
	config := game.DEFAULT_TACTICAL_CONFIG
	config.vision_size = 0
	testing.expect(t, game.configure_tactical(player, config))
	enemies := [?]game.Enemy_Spawn{{position = {x = 6, y = 3}, health = 30, attack = 1}, {position = {x = 9, y = 6}, health = 30, attack = 1}}
	built: bool
	room, built = game.create_room(data, player, {enemies = enemies[:]})
	testing.expect(t, built)
	for &enemy in room.enemies {
		enemy.recovery_pulses = 999
		enemy.intent, enemy.tactical_cooldown = {}, 0
	}
	game.plan_enemy_intents(&room)
	return
}

// The card played from the hand, its cues on the board's lane.
first_person_view_test_play :: proc(t: ^testing.T, renderer: ^Renderer, room: ^game.Room) {
	before := capture_room_presentation(room)
	play := game.play_card(room, room.player.deck.hand[0].id, game.entity_target(game.PLAYER_ENTITY))
	testing.expect_value(t, play.result, game.Card_Play_Result.Played)
	after := capture_room_presentation(room)
	testing.expect(t, begin_renderer_event_timeline(renderer, before, room.recent_events, &after))
}

// Frames until the camera is in his eyes (the card's cue played out).
first_person_view_test_dive :: proc(t: ^testing.T, renderer: ^Renderer, room: ^game.Room) {
	for _ in 0..<200 {
		if first_person_amount(renderer) >= 1 && !renderer_blocks_player_input(renderer) { break }
		shadow_view_test_frame(renderer, room, 0.02)
	}
	testing.expect_value(t, first_person_amount(renderer), f32(1))
}

// The view dives into his eyes as the card's cue plays, from the board's own
// camera, looking along a grid way; there the camera is his eye, his card and
// its stand gone, the inner walls opaque, what is behind the eye off the
// canvas, the keys turned with the view. Over it the camera rises back the
// same way, to the board's camera exactly, and the keys are the board's.
@(test)
test_first_person_view_dives_into_his_eyes_and_rises_back :: proc(t: ^testing.T) {
	data: level.Level
	player: game.Player
	room := first_person_view_test_room(t, &data, &player)
	defer level.destroy(&data)
	defer game.destroy_room(&room)
	snapshot: Room_Presentation
	renderer := shadow_view_test_renderer(&data, &snapshot)
	defer free(renderer)
	defer destroy_renderer_world_playback(renderer)
	f := &renderer.tactical.first_person
	shadow_view_test_frame(renderer, &room, 0.02)
	orbit := renderer.tactical.camera
	testing.expect(t, f.amount == 0 && !f.engaged && !first_person_hides_player(renderer))
	testing.expect(t, m8_control_enabled(renderer, &room, .Character))
	player_blow, foe_blow := Attack_Fx{attacker = game.PLAYER_ENTITY}, Attack_Fx{attacker = game.enemy_entity(room.enemies[0].id)}
	testing.expect(t, attack_weapon_shown(renderer, &player_blow) == 1 && attack_weapon_shown(renderer, &foe_blow) == 1)
	testing.expect_value(t, first_person_keys(renderer), game.MOVEMENT_KEY_DIRECTIONS)
	first_person_view_test_play(t, renderer, &room)
	// The card's own cue first: the camera waits.
	shadow_view_test_frame(renderer, &room, 0.02)
	testing.expect(t, f.engaged && f.amount == 0 && first_person_diving(renderer))
	eye := rl.Vector3{6.5, game.FIRST_PERSON_EYE_HEIGHT, 6.5}
	// It looks along a grid way: a whole number of quarter turns.
	turns := f.yaw/(math.PI/2)
	testing.expect(t, abs(turns-math.round(turns)) < 1e-4)
	testing.expect_value(t, first_person_keys(renderer), game.first_person_key_directions(f.yaw))
	last := rl.Vector3Distance(renderer.tactical.camera.position, eye)
	rising := false
	for _ in 0..<200 {
		shadow_view_test_frame(renderer, &room, 0.02)
		distance := rl.Vector3Distance(renderer.tactical.camera.position, eye)
		testing.expect(t, distance <= last+1e-4, "the dive went back")
		last = distance
		if f.amount > 0 { rising = true }
		if f.amount >= 1 { break }
	}
	testing.expect(t, rising && f.amount == 1 && !first_person_diving(renderer))
	camera := renderer.tactical.camera
	testing.expect(t, rl.Vector3Distance(camera.position, eye) < 1e-4)
	look := rl.Vector3Normalize(camera.target-camera.position)
	testing.expect(t, abs(look.x-math.cos(f.yaw)) < 1e-4 && abs(look.z-math.sin(f.yaw)) < 1e-4 && abs(look.y) < 1e-4)
	testing.expect(t, camera.projection == .PERSPECTIVE && abs(camera.fovy-FIRST_PERSON_FOV) < 1e-4)
	testing.expect(t, first_person_hides_player(renderer) && first_person_solid_walls(renderer) && first_person_wall_ramp(renderer) == 1)
	// Behind the eye is off the canvas; in front, where the camera puts it
	// (on the 3D board the view stands on).

	behind := rl.Vector3{eye.x-math.cos(f.yaw)*2, 0.5, eye.z-math.sin(f.yaw)*2}
	off := tactical_project(renderer, {behind.x, behind.z}, behind.y)
	testing.expect(t, off.x == -100000 && off.y == -100000)
	ahead := tactical_project(renderer, {eye.x+math.cos(f.yaw)*3, eye.z+math.sin(f.yaw)*3}, game.FIRST_PERSON_EYE_HEIGHT)
	testing.expect(t, abs(ahead.x-480) < 0.5 && abs(ahead.y-270) < 0.5)
	// The edge stands whole behind his eyes.
	testing.expect_value(t, diorama_wall_height(renderer, &room, {x = 0, y = 6}), DIORAMA_WALL_HEIGHT)
	// The hand is away under the canvas.
	testing.expect_value(t, first_person_hand_drop(renderer), TACTICAL_HAND_HEIGHT+24)
	// No button the pointer cannot reach is drawn as if it could be used.
	testing.expect(t, !m8_control_enabled(renderer, &room, .Character))
	// His lantern goes with his card: a bump of his swings nothing across the
	// eye (only where it lands shows); a foe's blow keeps its weapon.
	testing.expect(t, attack_weapon_shown(renderer, &player_blow) == 0 && attack_weapon_shown(renderer, &foe_blow) == 1)
	// The mouse turns it: any yaw, the pitch within its limit.
	yaw := f.yaw
	turn_first_person_view(renderer, 0.3, 2)
	testing.expect(t, abs(first_person_wrap(f.yaw-yaw-0.3)) < 1e-4 && f.pitch == game.FIRST_PERSON_PITCH_LIMIT)
	turn_first_person_view(renderer, 0, -5)
	testing.expect_value(t, f.pitch, -game.FIRST_PERSON_PITCH_LIMIT)
	// A shot's aim: the look, the eye and the foes' cards as the view shows them.
	aim := first_person_aim(renderer)
	testing.expect(t, aim.yaw == f.yaw && aim.pitch == f.pitch && aim.framed && aim.eye == [2]f32{6.5, 6.5} && aim.card_count == 2)
	for card in aim.cards[:aim.card_count] {
		index, found := game.enemy_index_by_id(&room, card.enemy_id)
		testing.expect(t, found && card.lift == 0)
		cell := room.enemies[index].position
		testing.expect_value(t, card.at, [2]f32{f32(cell.x)+0.5, f32(cell.y)+0.5})
	}
	// The seconds over: the camera rises back the way it came.
	room.first_person.remaining = 0.01
	game.tactical_first_person_tick(&room, 0.02)
	testing.expect(t, !game.tactical_first_person_active(&room))
	shadow_view_test_frame(renderer, &room, 0)
	testing.expect(t, !f.engaged && f.amount == 1 && f.exits == 1 && f.enters == 1)
	testing.expect_value(t, first_person_keys(renderer), game.MOVEMENT_KEY_DIRECTIONS)
	previous := f.amount
	for _ in 0..<60 {
		shadow_view_test_frame(renderer, &room, 0.02)
		testing.expect(t, f.amount <= previous, "the rise went back")
		previous = f.amount
		if f.amount <= 0 { break }
	}
	testing.expect_value(t, f.amount, f32(0))
	camera = renderer.tactical.camera
	testing.expect(t, rl.Vector3Distance(camera.position, orbit.position) < 1e-3 && camera.projection == orbit.projection)
	testing.expect(t, !first_person_hides_player(renderer) && !first_person_solid_walls(renderer))
	testing.expect_value(t, first_person_hand_drop(renderer), f32(0))
	testing.expect(t, m8_control_enabled(renderer, &room, .Character))
}

// The dive looks the way he faces when that is near the board camera's look
// (its own diagonal flanked by two ways), else along the way nearest it.
@(test)
test_first_person_dive_looks_the_way_he_faces :: proc(t: ^testing.T) {
	north_west := f32(-3*math.PI/4)
	testing.expect_value(t, first_person_dive_way(north_west, .North), game.Move_Direction.North)
	testing.expect_value(t, first_person_dive_way(north_west, .West), game.Move_Direction.West)
	// Facing away from the look: the way nearest it.
	testing.expect_value(t, first_person_dive_way(north_west+0.1, .South), game.Move_Direction.North)
	testing.expect_value(t, first_person_dive_way(north_west-0.1, .East), game.Move_Direction.West)
	// Looking along a way, a facing a quarter turn off it is not taken.
	testing.expect_value(t, first_person_dive_way(-math.PI/2, .East), game.Move_Direction.North)
	testing.expect_value(t, first_person_dive_way(0, .East), game.Move_Direction.East)
}

// Behind his eyes the overlays leave out a foe the eye cannot see past a wall
// (there is no depth to hide them); the board's own view shows it.
@(test)
test_first_person_overlays_leave_out_what_a_wall_hides :: proc(t: ^testing.T) {
	data: level.Level
	player: game.Player
	room := first_person_view_test_room(t, &data, &player)
	defer level.destroy(&data)
	defer game.destroy_room(&room)
	snapshot: Room_Presentation
	renderer := shadow_view_test_renderer(&data, &snapshot)
	defer free(renderer)
	defer destroy_renderer_world_playback(renderer)
	shadow_view_test_frame(renderer, &room, 0.02)
	north, behind := grid.Position{x = 6, y = 3}, grid.Position{x = 9, y = 6}
	testing.expect(t, tactical_overlay_visible(renderer, north) && tactical_overlay_visible(renderer, behind))
	first_person_view_test_play(t, renderer, &room)
	first_person_view_test_dive(t, renderer, &room)
	turn_first_person_view(renderer, first_person_wrap(-math.PI/2-renderer.tactical.first_person.yaw), -renderer.tactical.first_person.pitch)
	shadow_view_test_frame(renderer, &room, 0.02)
	testing.expect(t, tactical_overlay_visible(renderer, north))
	testing.expect(t, !tactical_overlay_visible(renderer, behind))
	actor, found := presentation_actor_in_view(renderer.tactical.snapshot, game.enemy_entity(room.enemies[1].id))
	testing.expect(t, found && !living_heart_shown(renderer, actor^))
}

// The room's shots: each one a tracer from the muzzle to where it stopped,
// then its spark; the kick, and a foe's hit marked; the player's wound
// flashing the edges once a blow, with a smooth return to the board.
@(test)
test_first_person_view_shows_each_shot_and_each_wound :: proc(t: ^testing.T) {
	data: level.Level
	player: game.Player
	room := first_person_view_test_room(t, &data, &player)
	defer level.destroy(&data)
	defer game.destroy_room(&room)
	snapshot: Room_Presentation
	renderer := shadow_view_test_renderer(&data, &snapshot)
	defer free(renderer)
	defer destroy_renderer_world_playback(renderer)
	f := &renderer.tactical.first_person
	shadow_view_test_frame(renderer, &room, 0.02)
	first_person_view_test_play(t, renderer, &room)
	first_person_view_test_dive(t, renderer, &room)
	// North: the foe; the crosshair is on it.
	turn_first_person_view(renderer, first_person_wrap(-math.PI/2-f.yaw), -f.pitch)
	shadow_view_test_frame(renderer, &room, 0.02)
	testing.expect_value(t, f.aimed, game.First_Person_Hit.Foe)
	game.first_person_set_trigger(&room, true)
	fire :: proc(t: ^testing.T, renderer: ^Renderer, room: ^game.Room) {
		before := capture_room_presentation(room)
		_, fired := game.first_person_fire(room, first_person_aim(renderer))
		testing.expect(t, fired)
		after := capture_room_presentation(room)
		if room.recent_events.count > 0 { testing.expect(t, begin_renderer_world_timeline(renderer, before, room.recent_events, &after)) }
	}
	fire(t, renderer, &room)
	shadow_view_test_frame(renderer, &room, 0)
	now := renderer.sprite_assets.elapsed
	testing.expect(t, f.shots == 1 && f.hits == 1 && f.kick_at == now && f.hit_at == now && f.flash == 1)
	tracer := f.tracers[0]
	testing.expect(t, tracer.used && !tracer.pending && tracer.hit == .Foe && tracer.flight > 0)
	testing.expect(t, rl.Vector3Distance(tracer.from, f.eye) > 0.5 && rl.Vector3Distance(tracer.from, f.eye) < 0.7)
	testing.expect(t, abs(tracer.to.z-3.5) < 1e-3)
	entries: [dynamic]Tactical_Alpha_Entry
	defer delete(entries)
	collect_first_person_entries(renderer, &entries)
	testing.expect(t, len(entries) == 1 && entries[0].kind == .First_Person && entries[0].first_person == 0)
	// Landed: its spark, then nothing.
	renderer.sprite_assets.elapsed += tracer.flight+0.01
	clear(&entries)
	collect_first_person_entries(renderer, &entries)
	testing.expect(t, len(entries) == 1 && int(entries[0].first_person) == len(f.tracers))
	renderer.sprite_assets.elapsed += FIRST_PERSON_SPARK_SECONDS
	clear(&entries)
	collect_first_person_entries(renderer, &entries)
	testing.expect(t, len(entries) == 0 && !f.tracers[0].used)
	// East: the wall stub, a shot on stone.
	turn_first_person_view(renderer, math.PI/2, 0)
	game.tactical_first_person_tick(&room, game.FIRST_PERSON_SHOT_SECONDS)
	fire(t, renderer, &room)
	shadow_view_test_frame(renderer, &room, 0)
	testing.expect(t, f.shots == 2 && f.hits == 1 && f.ricochets == 1 && f.tracers[1].hit == .Solid && f.flash == 2)
	// A blow on the player: the edges flash once for it, however long its cue.
	world: game.Event_Log
	game.record_event(&world, {kind = .Damaged, source = game.enemy_entity(room.enemies[0].id), target = game.PLAYER_ENTITY, amount = 2})
	testing.expect(t, begin_renderer_world_timeline(renderer, capture_room_presentation(&room), &world))
	shadow_view_test_frame(renderer, &room, 0.02)
	hurt := f.hurt_at
	testing.expect(t, hurt > 0 && first_person_trauma(f, renderer.sprite_assets.elapsed) > 0)
	shadow_view_test_frame(renderer, &room, 0.02)
	testing.expect_value(t, f.hurt_at, hurt)
	// The view out: input ownership returns once the camera is back.
	room.first_person.remaining = 0.01
	game.tactical_first_person_tick(&room, 0.02)
	for _ in 0..<60 {
		shadow_view_test_frame(renderer, &room, 0.02)
		if f.amount <= 0 { break }
	}
	testing.expect(t, f.amount == 0)
}

// A shot stopped by a solid cell sparks on the body standing there: on a cover
// block's or an object's top edge when the line passes over it, where the
// line meets its face when it comes down onto it, on a wall's face, and on a
// wall's top when the view looks up over it. A foe's and the floor's stay
// where the trace stopped.
@(test)
test_first_person_sparks_land_on_what_stopped_them :: proc(t: ^testing.T) {
	data: level.Level
	player: game.Player
	room := first_person_view_test_room(t, &data, &player)
	defer level.destroy(&data)
	defer game.destroy_room(&room)
	from := grid.Position{x = 6, y = 6}
	append(&room.obstacles, game.Obstacle{position = {x = 6, y = 8}})
	append(&room.objects, game.Grid_Object{id = room.next_object_id, kind = .Ice_Block, position = {x = 4, y = 6}, health = 4, max_health = 4})
	room.next_object_id += 1
	near :: proc(a, b: rl.Vector3) -> bool { return rl.Vector3Distance(a, b) < 1e-3 }
	// South, level: over the cover's top, which stops it.
	south := game.first_person_trace(&room, from, {yaw = math.PI/2})
	testing.expect(t, south.hit == .Solid && south.cell == grid.Position{x = 6, y = 8})
	testing.expect(t, near(first_person_landing(&room, south), {6.5, FIRST_PERSON_COVER_HEIGHT, 8.5-FIRST_PERSON_COVER_HALF}))
	// West, level: over the ice block's top; looking down, onto its face.
	ice := voxel_object_bounds(.Ice_Block, {4, 6})
	west := game.first_person_trace(&room, from, {yaw = math.PI})
	testing.expect(t, west.hit == .Solid && west.cell == grid.Position{x = 4, y = 6})
	testing.expect(t, near(first_person_landing(&room, west), {ice.max.x, ice.max.y, 6.5}))
	down := game.first_person_trace(&room, from, {yaw = math.PI, pitch = -0.3})
	landed := first_person_landing(&room, down)
	testing.expect(t, down.hit == .Solid && abs(landed.x-ice.max.x) < 1e-3 && landed.y > ice.min.y && landed.y < ice.max.y)
	testing.expect(t, abs(landed.y-(game.FIRST_PERSON_EYE_HEIGHT-math.tan(f32(0.3))*(6.5-ice.max.x))) < 1e-3)
	// East, level: the wall stub's face, as the trace has it.
	east := game.first_person_trace(&room, from, {yaw = 0})
	testing.expect(t, east.hit == .Solid && east.cell == grid.Position{x = 8, y = 6})
	testing.expect(t, near(first_person_landing(&room, east), {east.point.x, east.point.y, east.point.z}))
	// North, looking up over the foe: the room's edge, at the wall's top.
	up := game.first_person_trace(&room, from, {yaw = -math.PI/2, pitch = 0.5})
	testing.expect(t, up.hit == .Solid && up.cell == grid.Position{x = 6, y = 0} && up.point.y > DIORAMA_WALL_HEIGHT)
	testing.expect(t, near(first_person_landing(&room, up), {6.5, DIORAMA_WALL_HEIGHT, 1}))
	// A foe's and the floor's stay.
	foe := game.first_person_trace(&room, from, {yaw = -math.PI/2})
	floor := game.first_person_trace(&room, from, {yaw = -math.PI/2, pitch = -0.5})
	testing.expect(t, foe.hit == .Foe && floor.hit == .Floor)
	testing.expect(t, near(first_person_landing(&room, foe), {foe.point.x, foe.point.y, foe.point.z}))
	testing.expect(t, near(first_person_landing(&room, floor), {floor.point.x, floor.point.y, floor.point.z}))
}

// The AK's wounds start no clip: the struck card keeps its telegraph (no
// hurt, no guard), the player's card swings at nothing; they pop small
// tokens. Any other blow of his still does.
@(test)
test_first_person_wounds_start_no_clip :: proc(t: ^testing.T) {
	foe := game.enemy_entity(3)
	shot := Presentation_Cue{kind = .Damage, started = true, event = {kind = .Damaged, source = game.PLAYER_ENTITY, target = foe, amount = 1,
		visual_group = game.FIRST_PERSON_VISUAL_GROUP}}
	_, struck := living_cue_action(&shot, foe)
	_, swung := living_cue_action(&shot, game.PLAYER_ENTITY)
	testing.expect(t, !struck && !swung)
	guard := shot
	guard.kind = .Damage_Absorbed
	guard.event.kind = .Damage_Absorbed
	_, guarded := living_cue_action(&guard, foe)
	testing.expect(t, !guarded)
	blow := shot
	blow.event.visual_group = 0
	hurt, hurt_found := living_cue_action(&blow, foe)
	attack, attack_found := living_cue_action(&blow, game.PLAYER_ENTITY)
	testing.expect(t, hurt_found && hurt == .Hurt && attack_found && attack == .Attack)
}

// The shots' cards are the foes' living cards: at every row of a card's paper
// (its field cut where the board's shader cuts it) the outline is as wide as
// the paper there, to two pixels, on either side of the feet alike; nothing of
// it stands over the paper's top or under its foot; the card standing on its
// stand as living_billboard_geometry stands it.
@(test)
test_first_person_foe_outlines_follow_the_living_cards :: proc(t: ^testing.T) {
	for archetype in game.Enemy_Archetype {
		if archetype == .Count { continue }
		character, ok := flipbook_character(sprite_key_for_enemy(archetype))
		testing.expect(t, ok)
		sheet := &gfx.LIVING_SHEETS[character]
		bytes := gfx.LIVING_PAPER_PNG[character]
		image := rl.LoadImageFromMemory(".png", raw_data(bytes), c.int(len(bytes)))
		defer rl.UnloadImage(image)
		colors := rl.LoadImageColors(image)
		defer rl.UnloadImageColors(colors)
		w, h := int(image.width), int(image.height)
		testing.expect(t, colors != nil && w == int(sheet.paper_cell.x) && h == int(sheet.paper_cell.y))
		if colors == nil { continue }
		scale := sheet.world_height/max(sheet.rest_height, 1)
		base := 0.02+(sheet.ground+gfx.FLIPBOOK_PAPER+gfx.FLIPBOOK_INK)*scale+0.03
		cut := (gfx.FLIPBOOK_PAPER+gfx.FLIPBOOK_INK)*gfx.FLIPBOOK_PAPER_SCALE
		top := f32(-1)
		rows := 0
		for y in 0..<h {
			lo, hi := -1, -1
			for x in 0..<w {
				if f32(colors[y*w+x].r) > cut { continue }
				if lo < 0 { lo = x }
				hi = x
			}
			// The row's top edge above the floor, and its middle.
			edge := base+(sheet.feet.y+f32(sheet.card_margin)-f32(y))*scale
			outline := game.first_person_outline_half_width(archetype, edge-scale*0.5)
			if lo < 0 {
				testing.expectf(t, outline == 0, "%v: %.3f wide at %.3f over no paper", archetype, outline, edge-scale*0.5)
				continue
			}
			left := (sheet.feet.x+f32(sheet.card_margin)-f32(lo))*scale
			right := (f32(hi+1)-f32(sheet.card_margin)-sheet.feet.x)*scale
			testing.expectf(t, abs(left-right) < scale*1.01, "%v row %d: %.3f left, %.3f right", archetype, y, left, right)
			testing.expectf(t, abs(outline-max(left, right)) < 0.03, "%v row %d at %.3f: %.3f for paper %.3f wide", archetype, y,
				edge-scale*0.5, outline, max(left, right))
			if top < 0 { top = edge }
			rows += 1
		}
		testing.expectf(t, rows > 80 && abs(game.first_person_outline_top(archetype)-top) < 0.002, "%v: top %.3f for paper to %.3f",
			archetype, game.first_person_outline_top(archetype), top)
	}
}

// Whether the crosshair of `camera` is over the card of a foe standing at
// `at` (lifted `lift`) as the board draws it: the card facing the camera
// across its look, as wide as its outline where the look crosses it.
first_person_view_test_crosshair_on :: proc(camera: rl.Camera3D, archetype: game.Enemy_Archetype, at: view.Vec2, lift: f32) -> bool {
	look := rl.Vector3Normalize(camera.target-camera.position)
	level_look := math.sqrt(look.x*look.x+look.z*look.z)
	if level_look < 1e-6 { return false }
	dx, dz := look.x/level_look, look.z/level_look
	cx, cz := at.x+0.5, at.y+0.5
	o := camera.position
	depth := (cx-o.x)*dx+(cz-o.z)*dz
	if depth <= 0 { return false }
	lateral := abs((cx-o.x)*dz-(cz-o.z)*dx)
	return lateral <= game.first_person_outline_half_width(archetype, o.y+look.y/level_look*depth-lift)
}

// A shot goes where the crosshair is over what the board shows: while his
// eye glides a step aside, and while a foe's card slides from cell to cell,
// the shot (and the crosshair's mark) meets the foe in every frame the
// crosshair is over its card as drawn, and in none other.
@(test)
test_first_person_shots_follow_the_glides_the_view_shows :: proc(t: ^testing.T) {
	data: level.Level
	player: game.Player
	room := first_person_view_test_room(t, &data, &player)
	defer level.destroy(&data)
	defer game.destroy_room(&room)
	snapshot: Room_Presentation
	renderer := shadow_view_test_renderer(&data, &snapshot)
	defer free(renderer)
	defer destroy_renderer_world_playback(renderer)
	f := &renderer.tactical.first_person
	shadow_view_test_frame(renderer, &room, 0.02)
	first_person_view_test_play(t, renderer, &room)
	first_person_view_test_dive(t, renderer, &room)
	turn_first_person_view(renderer, first_person_wrap(-math.PI/2-f.yaw), -f.pitch)
	shadow_view_test_frame(renderer, &room, 0.02)
	foe := game.enemy_entity(room.enemies[0].id)
	archetype := room.enemies[0].archetype
	Counts :: struct {on, off, wrong: int}
	watch :: proc(renderer: ^Renderer, room: ^game.Room, foe: game.Entity_Ref, archetype: game.Enemy_Archetype, counts: ^Counts) {
		actor, found := presentation_actor_in_view(renderer.tactical.snapshot, foe)
		if !found { counts.wrong += 1; return }
		at, lift := living_card_position(renderer, foe, sprite_key_for_enemy(archetype), actor.position)
		drawn := first_person_view_test_crosshair_on(renderer.tactical.camera, archetype, at, lift)
		shot := game.first_person_trace(room, room.player.position, first_person_aim(renderer))
		struck := shot.hit == .Foe && shot.target == foe
		if drawn { counts.on += 1 } else { counts.off += 1 }
		if drawn != struck || (renderer.tactical.first_person.aimed == .Foe) != struck { counts.wrong += 1 }
	}
	// His step east, the ghoul three cells north in the crosshair: the eye
	// glides off it (D steps right of the view).
	keys := first_person_keys(renderer)
	before := capture_room_presentation(&room)
	testing.expect_value(t, game.try_move_player(&room, keys[1]), game.Action_Result.Moved)
	after := capture_room_presentation(&room)
	testing.expect(t, begin_renderer_event_timeline(renderer, before, room.recent_events, &after))
	glide: Counts
	for _ in 0..<45 {
		shadow_view_test_frame(renderer, &room, 1.0/60.0)
		watch(renderer, &room, foe, archetype, &glide)
	}
	testing.expectf(t, glide.wrong == 0 && glide.on > 0 && glide.off > 0, "his glide: %v", glide)
	testing.expect(t, abs(f.eye.x-7.5) < 1e-4)
	// The ghoul's step east, into the crosshair from his new cell (7, 6): its
	// cell at once, its card sliding there.
	for _ in 0..<120 {
		if !renderer_blocks_player_input(renderer) { break }
		shadow_view_test_frame(renderer, &room, 1.0/60.0)
	}
	before = capture_room_presentation(&room)
	action := game.make_action(.Move, foe, game.cell_target({x = 7, y = 3}), .Walkable_Cell)
	testing.expect(t, game.add_effect(&action, game.move_effect(foe, {x = 7, y = 3})))
	report := game.resolve_action(&room, &action)
	testing.expect(t, report.accepted && room.enemies[0].position == grid.Position{x = 7, y = 3})
	game.clear_event_log(room.recent_events)
	game.append_event_log(room.recent_events, &report.events)
	after = capture_room_presentation(&room)
	testing.expect(t, begin_renderer_world_timeline(renderer, before, room.recent_events, &after))
	slide: Counts
	for _ in 0..<45 {
		shadow_view_test_frame(renderer, &room, 1.0/60.0)
		watch(renderer, &room, foe, archetype, &slide)
	}
	testing.expectf(t, slide.wrong == 0 && slide.on > 0 && slide.off > 0, "its slide: %v", slide)
}

// The reference AK has actual alpha transparency, light paper and dark ink;
// flashes and tracers retain their procedural paper palette. Neither needs
// a GPU to validate the embedded art and its muzzle anchor.
@(test)
test_first_person_prints_are_paper_cutouts :: proc(t: ^testing.T) {
	// The AK is embedded with the same paper layers; decoding needs no GPU.
	ak := gfx.sprite_asset_image({FIRST_PERSON_AK_PNG, 1})
	defer rl.UnloadImage(ak)
	testing.expect(t, ak.data != nil)
	if ak.data == nil { return }
	testing.expect(t, f32(ak.width) == FIRST_PERSON_AK_TEXTURE_SIZE.x && f32(ak.height) == FIRST_PERSON_AK_TEXTURE_SIZE.y)
	colors := rl.LoadImageColors(ak)
	defer rl.UnloadImageColors(colors)
	paper, ink, transparent := 0, 0, 0
	for color in colors[:int(ak.width*ak.height)] {
		if color.a >= 250 && color.r > 220 && color.g > 215 && color.b > 190 { paper += 1 }
		if color.a >= 250 && color.r < 35 && color.g < 40 && color.b < 55 { ink += 1 }
		if color.a == 0 { transparent += 1 }
	}
	testing.expect(t, paper > 0 && ink > 0 && transparent > int(ak.width*ak.height)/4 && colors[0].a == 0)
	muzzle := FIRST_PERSON_AK_MUZZLE_TEXEL
	testing.expect(t, colors[int(muzzle.y)*int(ak.width)+int(muzzle.x)].a >= 250)
	pixel :: proc(print: ^First_Person_Print, x, y: int) -> rl.Color { return print.pixels[y*print.width+x] }
	for which in 0..<2 {
		flash := first_person_paint(FIRST_PERSON_FLASH_ROWS[which][:], FIRST_PERSON_FLASH_MARGIN, 2)
		testing.expect(t, flash.width == 13+2*FIRST_PERSON_FLASH_MARGIN && pixel(&flash, flash.width/2, flash.height/2) == rl.Color{255, 250, 222, 255})
	}
	tracer := first_person_paint(FIRST_PERSON_TRACER_ROWS[:], FIRST_PERSON_TRACER_MARGIN, 1)
	testing.expect(t, tracer.width > 0 && pixel(&tracer, FIRST_PERSON_TRACER_MARGIN-2, FIRST_PERSON_TRACER_MARGIN) == LIVING_TOKEN_PAPER)
}

// The shouldered print stays attached to the bottom/right at rest and under
// recoil. Its muzzle stays beside the crosshair, in the visible world; this
// exact anchor also launches the 3D tracers (covered by the shot test above).
@(test)
test_first_person_weapon_is_shouldered_and_muzzle_tracks_recoil :: proc(t: ^testing.T) {
	r := new(Renderer)
	defer free(r)
	r.tactical.first_person.amount = 1
	for size in ([3][2]f32{{640, 360}, {960, 540}, {1280, 720}}) {
		r.canvas_width, r.canvas_height = size.x, size.y
		scale := first_person_ak_scale(r)
		at := first_person_ak_origin(r, 1)
		muzzle := first_person_muzzle(r, 1)
		testing.expect(t, at.x+FIRST_PERSON_AK_SIZE.x*scale > size.x && at.y+FIRST_PERSON_AK_SIZE.y*scale > size.y)
		testing.expect(t, muzzle.x > size.x*0.5 && muzzle.x < size.x*0.75 && muzzle.y > size.y*0.35 && muzzle.y < size.y*0.7)
		r.tactical.first_person.kick_at = 2
		kicked, kicked_muzzle := first_person_ak_origin(r, 2), first_person_muzzle(r, 2)
		testing.expect(t, kicked.x > at.x && kicked.y > at.y)
		testing.expect_value(t, kicked_muzzle-muzzle, kicked-at)
		r.tactical.first_person.kick_at = 0
	}
}

// The HUD behind his eyes: the countdown's whole seconds counted up.
@(test)
test_first_person_countdown_counts_whole_seconds :: proc(t: ^testing.T) {
	testing.expect_value(t, string(first_person_countdown_text(20)), "FPS 20s")
	testing.expect_value(t, string(first_person_countdown_text(13.2)), "FPS 14s")
	testing.expect_value(t, string(first_person_countdown_text(0.4)), "FPS 1s")
	testing.expect_value(t, string(first_person_countdown_text(30)), "FPS 30s")
	testing.expect_value(t, string(FIRST_PERSON_HUD_STATUS), "MIRA COL MOUSE / CLIC: SPARA / WASD: PASSI")
}

// The card's words: its upgrade's seconds, its inspector's rules, no window
// time, on himself; its short name; a sound of its own.
@(test)
test_first_person_card_says_its_seconds_and_its_ak :: proc(t: ^testing.T) {
	card := game.Card_Instance{id = 1, definition_id = .First_Person}
	testing.expect_value(t, string(card_upgrade_preview(card)), "SECONDI 20 -> 22")
	testing.expect_value(t, string(card_upgrade_preview({id = 1, definition_id = .First_Person, upgrade_level = 4})), "SECONDI 28 -> 30")
	testing.expect_value(t, string(card_upgrade_preview({id = 1, definition_id = .First_Person, upgrade_level = 5})), "MAX UPGRADE")
	definition, _ := game.card_definition_by_id(.First_Person)
	reaction, rule := tactical_card_inspector_rules(card, definition)
	testing.expect_value(t, string(reaction), "NIENTE CARTE: SOLO L'AK")
	testing.expect_value(t, string(rule), "WASD SECONDO LA VISTA")
	testing.expect_value(t, string(tactical_card_time_badge(.First_Person)), "0s")
	testing.expect_value(t, string(tactical_card_target_label(definition)), "SU DI TE")
	testing.expect_value(t, string(card_short_name(.First_Person)), "FPS")
	// Its short name on a narrow card; on a wide one only where the whole name
	// would not hold, which takes the game's font to say (the lab's smoke: on
	// every face of the game it would not, FPS); with nothing to measure it, it
	// holds.
	testing.expect_value(t, string(tactical_card_face_title(nil, card, definition, 109)), "FPS")
	testing.expect_value(t, string(tactical_card_face_title(nil, card, definition, 166)), "First Person Shooter")
	sfx, sounds := lab_card_sfx(.First_Person)
	testing.expect(t, sounds && sfx == LAB_FIRST_PERSON_CARD)
	testing.expect_value(t, gothic_card_icon(.First_Person), 26)
}

// The lab hears the view with its own sounds: the card as it is played, the
// dive as the card's cue paces it (never before, never twice), each shot at
// the muzzle, a hit a moment after its shot, a shot on stone ricocheting, and
// the rise out once the seconds are over.
@(test)
test_first_person_lab_sounds_follow_the_view :: proc(t: ^testing.T) {
	data: level.Level
	player: game.Player
	room := first_person_view_test_room(t, &data, &player)
	defer level.destroy(&data)
	defer game.destroy_room(&room)
	snapshot: Room_Presentation
	renderer := shadow_view_test_renderer(&data, &snapshot)
	defer free(renderer)
	defer destroy_renderer_world_playback(renderer)
	renderer.tactical.mechanics_lab = true
	renderer.tactical.living_state = new(Living_State)
	defer free(renderer.tactical.living_state)
	defer destroy_lab_sounds(renderer)
	frame :: proc(renderer: ^Renderer, room: ^game.Room, dt: f32) {
		shadow_view_test_frame(renderer, room, dt)
		update_lab_sounds(renderer, room, renderer.sprite_assets.elapsed)
		play_lab_sounds(renderer, nil, 0)
	}
	frame(renderer, &room, 0.01)
	sounds := renderer.tactical.lab_sounds
	if !testing.expect(t, sounds != nil) { return }
	first_person_view_test_play(t, renderer, &room)
	played := renderer.sprite_assets.elapsed
	carded, dived := -1.0, -1.0
	for _ in 0..<150 {
		frame(renderer, &room, 0.01)
		now := renderer.sprite_assets.elapsed
		if carded < 0 && sounds.played[LAB_FIRST_PERSON_CARD] > 0 { carded = now-played }
		if dived < 0 && sounds.played[LAB_FIRST_PERSON_ENTER] > 0 { dived = now-played }
		if first_person_amount(renderer) >= 1 && !renderer_blocks_player_input(renderer) { break }
	}
	testing.expect(t, carded >= 0 && carded < 0.05, "the card sounds as it is played")
	testing.expect(t, dived > 0.2 && dived < 0.35, "the dive sounds as the card's cue starts it")
	testing.expect(t, sounds.played[LAB_FIRST_PERSON_CARD] == 1 && sounds.played[LAB_FIRST_PERSON_ENTER] == 1)
	// A shot into the foe north, then one into the wall east.
	f := &renderer.tactical.first_person
	turn_first_person_view(renderer, first_person_wrap(-math.PI/2-f.yaw), -f.pitch)
	frame(renderer, &room, 0.02)
	game.first_person_set_trigger(&room, true)
	fire :: proc(t: ^testing.T, renderer: ^Renderer, room: ^game.Room) {
		before := capture_room_presentation(room)
		_, fired := game.first_person_fire(room, first_person_aim(renderer))
		testing.expect(t, fired)
		after := capture_room_presentation(room)
		if room.recent_events.count > 0 { testing.expect(t, begin_renderer_world_timeline(renderer, before, room.recent_events, &after)) }
	}
	fire(t, renderer, &room)
	for _ in 0..<6 { frame(renderer, &room, 0.01) }
	testing.expect(t, sounds.played[LAB_FIRST_PERSON_SHOT] == 1 && sounds.played[LAB_FIRST_PERSON_HIT] == 1 &&
		sounds.played[LAB_FIRST_PERSON_RICOCHET] == 0)
	turn_first_person_view(renderer, math.PI/2, 0)
	game.tactical_first_person_tick(&room, game.FIRST_PERSON_SHOT_SECONDS)
	fire(t, renderer, &room)
	for _ in 0..<6 { frame(renderer, &room, 0.01) }
	testing.expect(t, sounds.played[LAB_FIRST_PERSON_SHOT] == 2 && sounds.played[LAB_FIRST_PERSON_HIT] == 1 &&
		sounds.played[LAB_FIRST_PERSON_RICOCHET] == 1)
	// The seconds over: the rise, once; never a second dive.
	room.first_person.remaining = 0.01
	game.tactical_first_person_tick(&room, 0.02)
	for _ in 0..<80 {
		frame(renderer, &room, 0.02)
		if first_person_amount(renderer) <= 0 { break }
	}
	testing.expect(t, sounds.played[LAB_FIRST_PERSON_EXIT] == 1 && sounds.played[LAB_FIRST_PERSON_ENTER] == 1)
	// Its sounds are its own, none another card's or another's of its own.
	own := [6]audio.Lab_Sfx{LAB_FIRST_PERSON_CARD, LAB_FIRST_PERSON_ENTER, LAB_FIRST_PERSON_EXIT, LAB_FIRST_PERSON_SHOT,
		LAB_FIRST_PERSON_HIT, LAB_FIRST_PERSON_RICOCHET}
	for a, i in own { for b in own[i+1:] { testing.expect(t, a != b) } }
	for card in game.Card_Id {
		if card == .Count || card == .First_Person { continue }
		other, _ := lab_card_sfx(card)
		for sfx in own { testing.expect(t, other != sfx) }
	}
}
