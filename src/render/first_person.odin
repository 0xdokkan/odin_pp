package render

import "core:c"
import "core:fmt"
import "core:math"
import rl "vendor:raylib"
import rlgl "vendor:raylib/rlgl"
import gfx "../engine/gfx"
import tween "../engine/tween"
import game "../game"
import grid "../engine/grid"
import view "../engine/view"

// FIRST PERSON SHOOTER on the board (game/first_person.odin). As the card's
// cue plays (First_Person_Begun) the camera dives from the board's own view
// into the player's eyes in his cell, turning to look the way he faces when
// that is near its own look, else along the grid way nearest it
// (first_person_dive_way); there the room is the 3D board seen from 1.05
// above the floor, its foes and props their usual paper, facing him. The
// mouse turns the view (the controller writes yaw and pitch here, as it writes
// the orbit's). The player's own card fades as the camera reaches it; the
// inner walls stand whole and opaque, the edge's no longer cut toward the
// camera, and what the overlays show of a foe behind a wall is left out. At
// the bottom right a paper AK, an embedded pixel-art cutout matching the
// reference artwork, kicks back at each shot with a flash at its muzzle; a
// crosshair marks the middle (warm over a foe, its corners marked on a hit);
// a plate at the bottom left counts the seconds left, the hand slides away
// under the canvas, and the edges flash red when he is hurt. Each shot of the
// room's trail flies as a paper tracer from the muzzle to where it stopped
// (on the body that stopped it, however low: first_person_landing), and
// sparks there: a red star on a foe, a gold one and chips off stone, dust off
// the floor. When the room's seconds are over (or the fight is) the camera
// rises back the way it came. The board follows the room; nothing here holds
// the player's input. The countdown's tag, the HUD's line and what is in hand
// are the weapon's (FIRST_PERSON_LOOKS): the AK's as above, the others' an
// empty hand until their own drawing comes; only the AK's shots fly.

// The rise back to the board's view (and a dive the card's cue does not pace).
FIRST_PERSON_VIEW_SECONDS :: f64(0.6)
FIRST_PERSON_FOV :: f32(70)
// The player's card fades from this far into the dive, over this much more.
FIRST_PERSON_HIDE_FROM :: f32(0.35)
FIRST_PERSON_HIDE_SPAN :: f32(0.25)
// From this far in the inner walls are opaque, drawn with the floor.
FIRST_PERSON_SOLID_WALLS :: f32(0.5)
// The AK and the HUD come in over the end of the dive.
FIRST_PERSON_AK_FROM :: f32(0.6)
// A tracer leaves the muzzle this far in front of the eye and flies this
// fast (cells a second); its spark lasts so long.
FIRST_PERSON_TRACER_FROM :: f32(0.6)
FIRST_PERSON_TRACER_SPEED :: f32(50)
FIRST_PERSON_TRACER_TEXEL :: f32(0.0045)
FIRST_PERSON_SPARK_SECONDS :: f64(0.32)
// A shot's kick and flash, the crosshair's red after a hit, the red edge.
FIRST_PERSON_KICK_SECONDS :: f64(0.09)
FIRST_PERSON_FLASH_SECONDS :: f64(0.05)
FIRST_PERSON_MARK_SECONDS :: f64(0.12)
FIRST_PERSON_HURT_SECONDS :: f64(0.35)
FIRST_PERSON_SHAKE :: f32(0.06)
// Canvas pixels a texel of the AK, its flash and the countdown's plate.
FIRST_PERSON_AK_SCALE :: f32(4)
FIRST_PERSON_HURT_SEEN :: 8
FIRST_PERSON_PRINT_TEXELS :: 24*24
FIRST_PERSON_OLIVE :: rl.Color{176, 186, 132, 255}

// Embedded paper print from the supplied reference, with no hands or arms.
// Native art resolution is independent of its logical HUD size, so replacing
// a cutout does not multiply the weapon's footprint or its recoil distance.
// Provenance and edit prompt: assets/gothic/first-person-ak.md.
@(rodata)
FIRST_PERSON_AK_PNG := #load("../../assets/gothic/first-person-ak.png")
FIRST_PERSON_AK_TEXTURE_SIZE :: [2]f32{1589, 990}
FIRST_PERSON_AK_WIDTH :: f32(128)
FIRST_PERSON_AK_TEXEL :: FIRST_PERSON_AK_WIDTH/FIRST_PERSON_AK_TEXTURE_SIZE.x
FIRST_PERSON_AK_SIZE :: [2]f32{FIRST_PERSON_AK_WIDTH, FIRST_PERSON_AK_TEXTURE_SIZE.y*FIRST_PERSON_AK_TEXEL}
// The barrel opening in source texels (not the front sight). Flash and world
// tracer use its logical position, including the entry slide and recoil.
FIRST_PERSON_AK_MUZZLE_TEXEL :: [2]f32{244, 183}
FIRST_PERSON_AK_MUZZLE :: [2]f32{FIRST_PERSON_AK_MUZZLE_TEXEL.x*FIRST_PERSON_AK_TEXEL, FIRST_PERSON_AK_MUZZLE_TEXEL.y*FIRST_PERSON_AK_TEXEL}

// The muzzle's flashes, one shot the one, the next the other.
@(rodata)
FIRST_PERSON_FLASH_ROWS := [2][13]string{
	{
		"......Y......",
		"......Y......",
		".....YOY.....",
		".Y...YWY...Y.",
		"..YOYWWWYOY..",
		"...YWWWWWY...",
		"YYOWWWWWWWOYY",
		"...YWWWWWY...",
		"..YOYWWWYOY..",
		".Y...YWY...Y.",
		".....YOY.....",
		"......Y......",
		"......Y......",
	},
	{
		".............",
		"...Y.....Y...",
		"....YO.OY....",
		".....YWY.....",
		"...OYWWWYO...",
		"....WWWWW....",
		".YYWWWWWWWYY.",
		"....WWWWW....",
		"...OYWWWYO...",
		".....YWY.....",
		"....YO.OY....",
		"...Y.....Y...",
		".............",
	},
}
FIRST_PERSON_FLASH_MARGIN :: 4

// A tracer: a long streak of white gold off an orange tail, its head
// forward (to the right).
@(rodata)
FIRST_PERSON_TRACER_ROWS := [?]string{
	"OOOYYYYYYWWWWWWWWW",
	"OOOYYYYYYWWWWWWWWW",
}
FIRST_PERSON_TRACER_MARGIN :: 3

// A small flash/tracer print and its paper, ready for a texture.
First_Person_Print :: struct {
	width, height: int,
	pixels: [FIRST_PERSON_PRINT_TEXELS]rl.Color,
}

// One shot's tracer and the spark where it stopped (`pending` until the
// camera of its frame has placed its muzzle).
First_Person_Tracer :: struct {
	used, pending: bool,
	number: i32,
	hit: game.First_Person_Hit,
	from, to: rl.Vector3,
	born, flight: f64,
}

// What makes a wound of the player this one, whichever frame shows it.
First_Person_Hurt_Key :: struct {
	batch: u32,
	source: game.Entity_Ref,
	amount: i32,
}

// Whether the eye sees a foe's cell, for the overlays (tactical_overlay_visible).
First_Person_Sight :: struct {
	cell: grid.Position,
	seen: bool,
}

First_Person_View :: struct {
	// The look as the mouse turns it (turn_first_person_view): yaw on the
	// board (0 east, a quarter turn south), pitch up from level.
	yaw, pitch: f32,
	// The room's view as last seen: behind his eyes (`engaged`) since
	// `changed` (sprite clock); how far the camera is into them now (0: the
	// board's own camera, 1: his eyes) and was at the change, and whether the
	// card's cue paced the dive.
	engaged, paced: bool,
	changed: f64,
	amount, from: f32,
	// The weapon in hand: the room's while the view is on, kept through the
	// rise back (FIRST_PERSON_LOOKS).
	weapon: game.First_Person_Weapon,
	// The fists' body as last seen and its lift off his floor (first_person_fists.odin).
	fists_body: [2]f32,
	fists_lift: f32,
	// The eye and its cell, as this frame's camera puts them, and the foes'
	// cards where this frame shows them: what a shot sees (first_person_aim).
	eye: rl.Vector3,
	eye_cell: grid.Position,
	cards: [game.MAX_ENEMIES_PER_ROOM]game.First_Person_Card,
	card_count: int,
	// The room's shots seen so far and their tracers; the last shot's kick and
	// number (its flash), a hit's mark, the player's last wound.
	seen_shots: i32,
	tracers: [game.FIRST_PERSON_TRAIL]First_Person_Tracer,
	tracer_next: int,
	kick_at, hit_at, hurt_at: f64,
	flash: i32,
	hurt_seen: [FIRST_PERSON_HURT_SEEN]First_Person_Hurt_Key,
	hurt_next: int,
	// What the crosshair is over now.
	aimed: game.First_Person_Hit,
	// The foes' cells the eye sees this frame, for the overlays.
	sight: [game.MAX_ENEMIES_PER_ROOM]First_Person_Sight,
	sight_count: int,
	// The painted prints.
	ak_texture, tracer_texture: rl.Texture2D,
	flash_textures: [2]rl.Texture2D,
	// The fists' gloves (first_person_gloves.odin).
	gloves: First_Person_Glove_Kit,
	// What the board has shown so far (the lab's sounds, the smoke and tests).
	shots, hits, ricochets, enters, exits: int,
}

// A fresh board: what was shown of the last view goes, the prints and the
// counts stay.
@(private)
first_person_view_reset :: proc(f: ^First_Person_View) {
	f^ = {ak_texture = f.ak_texture, tracer_texture = f.tracer_texture, flash_textures = f.flash_textures, gloves = f.gloves,
		shots = f.shots, hits = f.hits, ricochets = f.ricochets, enters = f.enters, exits = f.exits}
}

@(private)
destroy_first_person_view :: proc(renderer: ^Renderer) {
	f := &renderer.tactical.first_person
	if f.ak_texture.id != 0 { rl.UnloadTexture(f.ak_texture) }
	if f.tracer_texture.id != 0 { rl.UnloadTexture(f.tracer_texture) }
	for texture in f.flash_textures { if texture.id != 0 { rl.UnloadTexture(texture) } }
	destroy_first_person_glove_kit(&f.gloves)
	f^ = {}
}

// --------------------------------------------------------------------------
// Following the room.

// Once per frame, before the vision and the camera (update_tactical_view,
// which may run twice a frame): follows the room's view, paces the dive and
// the rise, and takes the room's new shots and the player's wounds.
@(private)
update_tactical_first_person :: proc(renderer: ^Renderer, room: ^game.Room) {
	v := &renderer.tactical
	f := &v.first_person
	if room == nil || room.player == nil || v.snapshot == nil { return }
	now := renderer.sprite_assets.elapsed
	active := game.tactical_first_person_active(room)
	if active { f.weapon = room.first_person.weapon }
	follow_first_person_fists(renderer, room)
	if active != f.engaged {
		if active {
			// The eyes look the way he faces, or along the grid way nearest the
			// board camera's look (first_person_dive_way).
			look := v.camera.target-v.camera.position
			way := first_person_dive_way(math.atan2(look.z, look.x), room.player.tactical.facing)
			f.yaw, f.pitch = game.first_person_yaw(way), 0
			f.seen_shots, f.paced = room.first_person.shots, false
			f.enters += 1
		} else {
			f.exits += 1
		}
		f.engaged, f.changed, f.from = active, now, f.amount
	}
	ramp := tween.smoothstep(f32(clamp((now-f.changed)/FIRST_PERSON_VIEW_SECONDS, 0, 1)))
	if f.engaged {
		// The card's own cue paces the dive, waiting with it; without one, the
		// sprite clock does.
		progress, found := shadow_cue_progress(renderer, .First_Person_Begun)
		if found {
			f.paced = true
			ramp = tween.smoothstep(progress)
		} else if f.paced {
			ramp = 1
		}
		f.amount = f.from+(1-f.from)*ramp
	} else {
		f.amount = f.from*(1-ramp)
	}
	// The room's new shots: their tracers, the kick, the hit's mark. Only the
	// AK keeps a trail; another weapon's bytes are its own.
	if f.weapon != .AK { f.seen_shots = room.first_person.shots }
	trail := &room.first_person.trail
	for f.seen_shots < room.first_person.shots {
		f.seen_shots += 1
		if room.first_person.shots-f.seen_shots >= game.FIRST_PERSON_TRAIL { continue }
		shot := trail[(f.seen_shots-1)%game.FIRST_PERSON_TRAIL]
		f.tracers[f.tracer_next] = {used = true, pending = true, number = shot.number, hit = shot.hit,
			to = first_person_landing(room, shot), born = now}
		f.tracer_next = (f.tracer_next+1)%len(f.tracers)
		f.kick_at, f.flash = now, shot.number
		f.shots += 1
		#partial switch shot.hit {
		case .Foe:
			f.hit_at = now
			f.hits += 1
		case .Solid:
			f.ricochets += 1
		}
	}
	// The player's wounds as their cues start (a blow as it lands).
	if f.amount <= 0 { return }
	for offset in 0..<renderer_active_cue_count(renderer) {
		cue, found := renderer_active_cue_at(renderer, offset)
		if !found || !cue.started || cue.kind != .Damage || cue.event.target != game.PLAYER_ENTITY || cue.event.amount <= 0 { continue }
		key := First_Person_Hurt_Key{batch = cue.batch, source = cue.event.source, amount = cue.event.amount}
		seen := false
		for previous in f.hurt_seen { if previous == key && key.batch != 0 { seen = true; break } }
		if seen { continue }
		f.hurt_seen[f.hurt_next] = key
		f.hurt_next = (f.hurt_next+1)%len(f.hurt_seen)
		landing, _ := attack_fx_landing_in(renderer, game.PLAYER_ENTITY, now, cue.event.source)
		f.hurt_at = now+landing
	}
}

// Right after the board's own camera (update_tactical_view): the camera goes
// as far into the player's eyes as the dive has, the eye riding his card's
// glide from cell to cell; then the tracers of this frame leave the muzzle,
// and the eye's sight, the foes' cards where they stand now (sliding from cell
// to cell, hopping) and the crosshair's mark are taken.
@(private)
frame_first_person_camera :: proc(renderer: ^Renderer, room: ^game.Room) {
	v := &renderer.tactical
	f := &v.first_person
	if room == nil || room.player == nil || v.snapshot == nil { return }
	now := renderer.sprite_assets.elapsed
	p := v.snapshot.player.position
	f.eye = {p.x+0.5, game.FIRST_PERSON_EYE_HEIGHT+entity_point_ground(game.PLAYER_ENTITY, p), p.y+0.5}
	// With the fists the eye rides the free body (first_person_fists.odin).
	if eye, fists := first_person_fists_eye(renderer, room, p); fists { f.eye = eye }
	f.eye_cell = {x = int(math.round(p.x)), y = int(math.round(p.y))}
	f.card_count = 0
	for actor in v.snapshot.enemies[:v.snapshot.enemy_count] {
		if f.card_count == len(f.cards) { break }
		if actor.entity.kind != .Enemy || !actor.visible { continue }
		at, lift := living_card_position(renderer, actor.entity, sprite_key_for_enemy(actor.archetype), actor.position)
		f.cards[f.card_count] = {enemy_id = actor.entity.id, at = {at.x+0.5, at.y+0.5}, lift = lift}
		f.card_count += 1
	}
	if f.amount > 0 {
		orbit := v.camera
		forward := rl.Vector3Normalize(orbit.target-orbit.position)
		yaw0 := math.atan2(forward.z, forward.x)
		pitch0 := math.asin(clamp(forward.y, -1, 1))
		s := clamp(f.amount, 0, 1)
		yaw := yaw0+first_person_wrap(f.yaw-yaw0)*s
		pitch := pitch0+(f.pitch-pitch0)*s
		look := rl.Vector3{math.cos(yaw)*math.cos(pitch), math.sin(pitch), math.sin(yaw)*math.cos(pitch)}
		position := orbit.position+(f.eye-orbit.position)*s
		// A wound shakes the eye a moment.
		if trauma := first_person_trauma(f, now); trauma > 0 {
			right := rl.Vector3Normalize(rl.Vector3CrossProduct(look, {0, 1, 0}))
			up := rl.Vector3CrossProduct(right, look)
			t := f32(now)
			position += (right*math.sin(t*53.1)+up*math.sin(t*41.7+1.3))*(FIRST_PERSON_SHAKE*trauma*trauma)
		}
		fovy := orbit.fovy if orbit.projection == .PERSPECTIVE else f32(40)
		fov := FIRST_PERSON_FISTS_FOV if f.weapon == .Fists else FIRST_PERSON_FOV
		v.camera = {position = position, target = position+look, up = {0, 1, 0}, fovy = fovy+(fov-fovy)*s,
			projection = .PERSPECTIVE}
	}
	for &tracer in f.tracers {
		if !tracer.used || !tracer.pending { continue }
		tracer.pending = false
		muzzle := first_person_muzzle(renderer, now)
		ray := rl.GetScreenToWorldRayEx(muzzle, v.camera, c.int(renderer.canvas_width), c.int(renderer.canvas_height))
		tracer.from = ray.position+ray.direction*FIRST_PERSON_TRACER_FROM
		tracer.flight = f64(rl.Vector3Distance(tracer.from, tracer.to)/FIRST_PERSON_TRACER_SPEED)
	}
	f.sight_count = 0
	if f.amount > 0 {
		context_data := Tactical_Visibility_Context{renderer, room}
		for actor in v.snapshot.enemies[:v.snapshot.enemy_count] {
			if f.sight_count == len(f.sight) { break }
			cell := grid.Position{x = int(math.round(actor.position.x)), y = int(math.round(actor.position.y))}
			f.sight[f.sight_count] = {cell = cell, seen = game.tactical_line_visible(f.eye_cell, cell, tactical_snapshot_opaque, &context_data, tactical_snapshot_height)}
			f.sight_count += 1
		}
	}
	f.aimed = .None
	if f.engaged { f.aimed = game.first_person_trace(room, room.player.position, first_person_aim(renderer)).hit }
}

// The way the eyes look as the dive starts: the way the player faces when it
// is within FIRST_PERSON_DIVE_FACING of the board camera's look (the board's
// own camera looks along a diagonal, half way between two ways), else the grid
// way nearest that look.
FIRST_PERSON_DIVE_FACING :: f32(50*math.PI/180)

@(private)
first_person_dive_way :: proc(look_yaw: f32, facing: game.Move_Direction) -> game.Move_Direction {
	if abs(first_person_wrap(game.first_person_yaw(facing)-look_yaw)) <= FIRST_PERSON_DIVE_FACING { return facing }
	return game.first_person_key_directions(look_yaw)[0]
}

// The cover's block and cap (draw_voxel_cover): half its width, its height.
FIRST_PERSON_COVER_HALF :: f32(0.38)
FIRST_PERSON_COVER_HEIGHT :: f32(0.49)

// Where a shot shows it stopped: where the game's trace did, a solid cell's
// spark on the body standing there (a wall, a cover block, an object's box),
// where the shot's line meets it, or on the body's edge nearest that line when
// the line passes over a low one or above a wall (the trace stops the shot at
// the cell, whatever stands there: game/first_person.odin).
@(private)
first_person_landing :: proc(room: ^game.Room, shot: game.First_Person_Shot) -> rl.Vector3 {
	// The rules' heights count from 0, the drawing's from the map's base (board_drawn).
	point := rl.Vector3{shot.point.x, shot.point.y-board_base_drawn(), shot.point.z}
	if shot.hit != .Solid || room == nil { return point }
	box := first_person_solid_box(room, shot.cell)
	origin := rl.Vector3{shot.origin.x, shot.origin.y, shot.origin.z}
	if way := point-origin; rl.Vector3Length(way) > 1e-4 {
		collision := rl.GetRayCollisionBox({position = origin, direction = rl.Vector3Normalize(way)}, box)
		if collision.hit && collision.distance > 0 { return collision.point }
	}
	return {clamp(point.x, box.min.x, box.max.x), clamp(point.y, box.min.y, box.max.y), clamp(point.z, box.min.z, box.max.z)}
}

// The body a solid cell shows: a wall's whole height (or past the room's
// edge), a cover block, an object's box (voxel_object_bounds).
@(private = "file")
first_person_solid_box :: proc(room: ^game.Room, cell: grid.Position) -> rl.BoundingBox {
	wall := rl.BoundingBox{{f32(cell.x), 0, f32(cell.y)}, {f32(cell.x)+1, DIORAMA_WALL_HEIGHT, f32(cell.y)+1}}
	if !game.base_cell_is_walkable(room, cell) { return wall }
	if game.obstacle_at(room, cell) {
		centre := rl.Vector3{f32(cell.x)+0.5, 0, f32(cell.y)+0.5}
		half := FIRST_PERSON_COVER_HALF
		return {centre-{half, 0, half}, centre+{half, FIRST_PERSON_COVER_HEIGHT, half}}
	}
	if object, found := game.grid_object_at(room, cell); found {
		return voxel_object_bounds(object.kind, {f32(cell.x), f32(cell.y)})
	}
	return wall
}

first_person_wrap :: proc(angle: f32) -> f32 {
	a := math.mod(angle+math.PI, 2*math.PI)
	if a < 0 { a += 2*math.PI }
	return a-math.PI
}

// How hard a wound shakes the eye now (0 when it does not).
@(private)
first_person_trauma :: proc(f: ^First_Person_View, now: f64) -> f32 {
	t := now-f.hurt_at
	if f.hurt_at <= 0 || t < 0 || t >= FIRST_PERSON_HURT_SECONDS { return 0 }
	return 0.6*f32(1-t/FIRST_PERSON_HURT_SECONDS)
}

// --------------------------------------------------------------------------
// What the rest of the board asks.

// How far the camera is into the player's eyes (0: not at all).
first_person_amount :: proc(renderer: ^Renderer) -> f32 {
	if renderer == nil { return 0 }
	return clamp(renderer.tactical.first_person.amount, 0, 1)
}

// The camera still diving: the AK does not fire yet.
first_person_diving :: proc(renderer: ^Renderer) -> bool {
	if renderer == nil { return false }
	f := &renderer.tactical.first_person
	return f.engaged && f.amount < 1
}

// The view remains active until its return to the board has finished.
@(private = "file")
first_person_transition_active :: proc(renderer: ^Renderer, room: ^game.Room) -> bool {
	return game.tactical_first_person_active(room) || first_person_amount(renderer) > 0
}

// The pointer is the view's (hidden, or the camera still rising): it reaches
// nothing on the board, the hand or the HUD.
first_person_owns_pointer :: proc(renderer: ^Renderer, room: ^game.Room) -> bool {
	return first_person_transition_active(renderer, room)
}

// The view's aim, for the AK's shots and the crosshair's mark: its look, and
// behind his eyes the eye and the foes' cards as the last frame showed them,
// so that a shot goes where the crosshair was over what the board showed.
first_person_aim :: proc(renderer: ^Renderer) -> (aim: game.First_Person_Aim) {
	f := &renderer.tactical.first_person
	aim.yaw, aim.pitch = f.yaw, f.pitch
	if !f.engaged { return }
	aim.framed, aim.eye = true, {f.eye.x, f.eye.z}
	aim.cards, aim.card_count = f.cards, f.card_count
	return
}

// The ways W, D, S and A step: turned with the view behind the player's eyes.
first_person_keys :: proc(renderer: ^Renderer) -> [4]game.Move_Direction {
	if renderer == nil || !renderer.tactical.first_person.engaged { return game.MOVEMENT_KEY_DIRECTIONS }
	return game.first_person_key_directions(renderer.tactical.first_person.yaw)
}

// The mouse's turn of the view (radians): any yaw, the pitch held within its limit.
turn_first_person_view :: proc(renderer: ^Renderer, yaw, pitch: f32) {
	f := &renderer.tactical.first_person
	f.yaw = first_person_wrap(f.yaw+yaw)
	f.pitch = clamp(f.pitch+pitch, -game.FIRST_PERSON_PITCH_LIMIT, game.FIRST_PERSON_PITCH_LIMIT)
}

// How much of the player's own card shows (it fades as the camera reaches it).
@(private)
first_person_player_shown :: proc(renderer: ^Renderer) -> f32 {
	return 1-clamp((first_person_amount(renderer)-FIRST_PERSON_HIDE_FROM)/FIRST_PERSON_HIDE_SPAN, 0, 1)
}

// The player's card and what it carries are left off the board.
first_person_hides_player :: proc(renderer: ^Renderer) -> bool {
	return first_person_player_shown(renderer) <= 0
}

// The inner walls are opaque, drawn with the floor (depth hides what is behind).
@(private)
first_person_solid_walls :: proc(renderer: ^Renderer) -> bool {
	return first_person_amount(renderer) >= FIRST_PERSON_SOLID_WALLS
}

// 0..1 toward opaque inner walls over the start of the dive.
@(private)
first_person_wall_ramp :: proc(renderer: ^Renderer) -> f32 {
	return clamp(first_person_amount(renderer)/FIRST_PERSON_SOLID_WALLS, 0, 1)
}

// What the overlays may show over a foe's cell: in sight, and behind his eyes
// before the eye on the canvas (a label pinned to the edge would point at
// nothing) and not behind a wall from it (the overlays have no depth to hide
// them).
@(private)
tactical_overlay_visible :: proc(renderer: ^Renderer, cell: grid.Position) -> bool {
	if !tactical_render_visible(renderer, cell) { return false }
	f := &renderer.tactical.first_person
	if f.amount <= 0 { return true }
	if !first_person_on_canvas(renderer, tactical_project(renderer, {f32(cell.x)+0.5, f32(cell.y)+0.5}, 0.8)) { return false }
	for sight in f.sight[:f.sight_count] { if sight.cell == cell { return sight.seen } }
	return true
}

// A projected point on the canvas, or near enough to it.
@(private)
first_person_on_canvas :: proc(renderer: ^Renderer, point: view.Vec2) -> bool {
	margin :: f32(40)
	return point.x >= -margin && point.y >= -margin && point.x <= renderer.canvas_width+margin && point.y <= renderer.canvas_height+margin
}

// How far the hand has slid down off the canvas (pixels).
first_person_hand_drop :: proc(renderer: ^Renderer) -> f32 {
	return tween.smoothstep(first_person_amount(renderer))*(TACTICAL_HAND_HEIGHT+24)
}

// --------------------------------------------------------------------------
// The prints.

@(private)
first_person_print_color :: proc(letter: u8) -> (color: rl.Color, ok: bool) {
	switch letter {
	// Flash and tracer: white, gold and orange. The weapon is an embedded PNG.
	case 'W': return {255, 250, 222, 255}, true
	case 'Y': return {250, 206, 92, 255}, true
	case 'O': return {232, 128, 52, 255}, true
	}
	return
}

// `rows` of palette letters cut from paper as the board's props are: an ink
// line round the print, `paper` texels of white paper, an ink cut round that,
// and the cut edge one texel down and right of it; `margin` texels of room.
@(private)
first_person_paint :: proc(rows: []string, margin, paper: int) -> (print: First_Person_Print) {
	if len(rows) == 0 { return }
	print.width, print.height = len(rows[0])+margin*2, len(rows)+margin*2
	if print.width*print.height > FIRST_PERSON_PRINT_TEXELS { return {} }
	w, h := print.width, print.height
	layers, staged: [FIRST_PERSON_PRINT_TEXELS]Paper_Outline_Layer
	for row, y in rows {
		for x in 0..<len(row) {
			if color, ok := first_person_print_color(row[x]); ok {
				print.pixels[(y+margin)*w+x+margin] = color
				layers[(y+margin)*w+x+margin] = .Print
			}
		}
	}
	paper_outline_grow(layers[:w*h], staged[:w*h], w, h, .Ink, true)
	for ring in 0..<paper { paper_outline_grow(layers[:w*h], staged[:w*h], w, h, .Paper, ring%2 == 1) }
	paper_outline_grow(layers[:w*h], staged[:w*h], w, h, .Cut, true)
	for index in 0..<w*h {
		#partial switch layers[index] {
		case .Ink, .Cut: print.pixels[index] = LIVING_TOKEN_INK
		case .Paper: print.pixels[index] = LIVING_TOKEN_PAPER
		}
	}
	// The cut edge shows the paper's thickness, down and right.
	for y := h-1; y > 0; y -= 1 {
		for x := w-1; x > 0; x -= 1 {
			if layers[y*w+x] == .Clear && layers[(y-1)*w+x-1] != .Clear { print.pixels[y*w+x] = LIVING_TOKEN_EDGE }
		}
	}
	return
}

@(private = "file")
first_person_texture :: proc(texture: ^rl.Texture2D, rows: []string, margin, paper: int) -> rl.Texture2D {
	if texture.id != 0 { return texture^ }
	print := first_person_paint(rows, margin, paper)
	if print.width == 0 { return {} }
	image := rl.GenImageColor(c.int(print.width), c.int(print.height), rl.BLANK)
	defer rl.UnloadImage(image)
	for y in 0..<print.height {
		for x in 0..<print.width { rl.ImageDrawPixel(&image, c.int(x), c.int(y), print.pixels[y*print.width+x]) }
	}
	texture^ = rl.LoadTextureFromImage(image)
	if texture.id != 0 { rl.SetTextureFilter(texture^, .POINT) }
	return texture^
}

@(private = "file")
first_person_ak_texture :: proc(f: ^First_Person_View) -> rl.Texture2D {
	if f.ak_texture.id == 0 {
		if sprite, ok := gfx.sprite_load({FIRST_PERSON_AK_PNG, 1}); ok { f.ak_texture = sprite.texture }
	}
	return f.ak_texture
}

@(private = "file")
first_person_flash_texture :: proc(f: ^First_Person_View, which: int) -> rl.Texture2D {
	return first_person_texture(&f.flash_textures[which], FIRST_PERSON_FLASH_ROWS[which][:], FIRST_PERSON_FLASH_MARGIN, 2)
}

@(private = "file")
first_person_tracer_texture :: proc(f: ^First_Person_View) -> rl.Texture2D {
	return first_person_texture(&f.tracer_texture, FIRST_PERSON_TRACER_ROWS[:], FIRST_PERSON_TRACER_MARGIN, 1)
}

// The AK's print's top left on the canvas now: at the bottom right, sliding up
// into place over the end of the dive, kicked back and down by a shot.
@(private)
first_person_ak_origin :: proc(renderer: ^Renderer, now: f64) -> rl.Vector2 {
	f := &renderer.tactical.first_person
	scale := first_person_ak_scale(renderer)
	w, h := FIRST_PERSON_AK_SIZE.x*scale, FIRST_PERSON_AK_SIZE.y*scale
	ready := tween.smoothstep(clamp((first_person_amount(renderer)-FIRST_PERSON_AK_FROM)/(1-FIRST_PERSON_AK_FROM), 0, 1))
	// The magazine and stock continue beyond the canvas; the source cutout's
	// bottom and right crop never appears as a floating paper edge.
	at := rl.Vector2{renderer.canvas_width-w+scale*6, renderer.canvas_height-h+scale*6}
	at.y += (1-ready)*h*1.2
	if t := now-f.kick_at; f.kick_at > 0 && t >= 0 && t < FIRST_PERSON_KICK_SECONDS {
		k := f32(1-t/FIRST_PERSON_KICK_SECONDS)
		at += rl.Vector2{1.25*k, 1.75*k}*scale
	}
	return {math.round(at.x/scale)*scale, math.round(at.y/scale)*scale}
}

// Integer texels at every canvas size, including the smaller effect window.
@(private)
first_person_ak_scale :: proc(renderer: ^Renderer) -> f32 {
	return max(1, math.floor(FIRST_PERSON_AK_SCALE*min(renderer.canvas_width/960, renderer.canvas_height/540)))
}

// The muzzle's tip on the canvas now.
@(private)
first_person_muzzle :: proc(renderer: ^Renderer, now: f64) -> rl.Vector2 {
	at := first_person_ak_origin(renderer, now)
	return at+(FIRST_PERSON_AK_MUZZLE+0.5)*first_person_ak_scale(renderer)
}

// --------------------------------------------------------------------------
// The board's pass: tracers and sparks.

// The tracers in flight and the sparks of those landed, for the sorted pass.
@(private)
collect_first_person_entries :: proc(renderer: ^Renderer, entries: ^[dynamic]Tactical_Alpha_Entry) {
	f := &renderer.tactical.first_person
	now := renderer.sprite_assets.elapsed
	for &tracer, index in f.tracers {
		if !tracer.used || tracer.pending { continue }
		t := now-tracer.born
		if t > tracer.flight+FIRST_PERSON_SPARK_SECONDS {
			tracer.used = false
			continue
		}
		if t < tracer.flight {
			at := first_person_tracer_point(&tracer, t)
			append(entries, Tactical_Alpha_Entry{kind = .First_Person, first_person = i32(index), position = {at.x-0.5, at.z-0.5}})
		} else if tracer.hit != .None {
			append(entries, Tactical_Alpha_Entry{kind = .First_Person, first_person = i32(index+len(f.tracers)),
				position = {tracer.to.x-0.5, tracer.to.z-0.5}})
		}
	}
}

@(private = "file")
first_person_tracer_point :: proc(tracer: ^First_Person_Tracer, t: f64) -> rl.Vector3 {
	u := f32(clamp(t/max(tracer.flight, 1e-6), 0, 1))
	return tracer.from+(tracer.to-tracer.from)*u
}

@(private)
draw_first_person_entry :: proc(renderer: ^Renderer, entry: Tactical_Alpha_Entry) {
	f := &renderer.tactical.first_person
	now := renderer.sprite_assets.elapsed
	index := int(entry.first_person)
	if index < 0 || index >= 2*len(f.tracers) { return }
	rlgl.DrawRenderBatchActive()
	rlgl.DisableBackfaceCulling()
	defer { rlgl.DrawRenderBatchActive(); rlgl.EnableBackfaceCulling() }
	if index < len(f.tracers) {
		tracer := &f.tracers[index]
		draw_first_person_tracer(renderer, first_person_tracer_point(tracer, now-tracer.born), tracer.to-tracer.from)
		return
	}
	tracer := &f.tracers[index-len(f.tracers)]
	draw_first_person_spark(renderer, tracer, now-tracer.born-tracer.flight)
}

// The streak at `at`, laid along `way` as the screen shows it, the same size
// on screen however far it has flown.
@(private = "file")
draw_first_person_tracer :: proc(renderer: ^Renderer, at, way: rl.Vector3) {
	texture := first_person_tracer_texture(&renderer.tactical.first_person)
	if texture.id == 0 { return }
	camera := renderer.tactical.camera
	distance := max(f32(0.2), rl.Vector3Distance(at, camera.position))
	u, v := attack_prop_axes(way, rl.Vector3Normalize(camera.target-camera.position), {1, 0}, FIRST_PERSON_TRACER_TEXEL*distance)
	w, h := f32(texture.width), f32(texture.height)
	corners := [4][2]f32{{-w*0.5, -h*0.5}, {-w*0.5, h*0.5}, {w*0.5, h*0.5}, {w*0.5, -h*0.5}}
	uv := [4][2]f32{{0, 0}, {0, 1}, {1, 1}, {1, 0}}
	rlgl.SetTexture(texture.id)
	rlgl.Begin(rlgl.QUADS)
	rlgl.Color4ub(255, 255, 255, 255)
	for corner, index in corners {
		p := at+u*corner.x+v*corner.y
		rlgl.TexCoord2f(uv[index].x, uv[index].y)
		rlgl.Vertex3f(p.x, p.y, p.z)
	}
	rlgl.End()
	rlgl.SetTexture(0)
}

// A shot landed `t` seconds ago: a paper star where it stopped (red on a foe,
// gold on stone, grey on the floor), stone chips or floor dust thrown off it.
@(private = "file")
draw_first_person_spark :: proc(renderer: ^Renderer, tracer: ^First_Person_Tracer, t: f64) {
	if t < 0 || t > FIRST_PERSON_SPARK_SECONDS || !renderer.tactical.attack_props.loaded { return }
	camera := renderer.tactical.camera
	// A little toward the eye: the paper never sinks into what it struck (a
	// wall's body stands a little proud of its cell, and a star on a block's
	// edge would cut into its top).
	at := tracer.to+rl.Vector3Normalize(camera.position-tracer.to)*(0.06 if tracer.hit == .Foe else 0.16)
	right, up := attack_screen_axes(renderer)
	texel := attack_texel(.Pilgrim)
	tint := rl.Color{196, 44, 44, 255}
	#partial switch tracer.hit {
	case .Solid: tint = TACTICAL_FEEDBACK_CRITICAL
	case .Floor: tint = {186, 180, 168, 255}
	}
	star := t/(FIRST_PERSON_SPARK_SECONDS*0.7)
	if star < 1 {
		grip, tip, size, opacity := attack_impact_star(renderer, at, star*ATTACK_IMPACT_SECONDS, int(tracer.number))
		draw_attack_prop(renderer, .Impact, grip, tip, size*0.5, opacity, tint)
	}
	p := f32(t/FIRST_PERSON_SPARK_SECONDS)
	#partial switch tracer.hit {
	case .Solid:
		shards := [3]gfx.Attack_Prop{.Shard_A, .Shard_B, .Shard_C}
		for index in 0..<3 {
			angle := f32(int(tracer.number)*7+index*3)*1.9
			out := right*math.cos(angle)+up*math.sin(angle)*0.6
			point := at+out*(0.32*p)+rl.Vector3{0, 0.18*p-0.6*p*p, 0}
			turn := p*9+f32(index)
			draw_attack_prop(renderer, shards[index], point, point+up*math.cos(turn)+right*math.sin(turn), texel*0.8, clamp((1-p)*2.5, 0, 1))
		}
	case .Floor:
		for index in 0..<2 {
			side := f32(index*2-1)
			point := at+right*(side*0.12*p)+rl.Vector3{0, 0.22*p, 0}
			draw_attack_prop(renderer, .Dust_A if index == 0 else .Dust_B, point, point+up, texel*0.8, clamp((1-p)*1.8, 0, 1))
		}
	}
}

// --------------------------------------------------------------------------
// Over the board: the AK, its flash, the crosshair, the countdown, the wound.

// At the top of the HUD (draw_tactical_hud), so every pass that shows the
// board's HUD shows it.
@(private)
draw_first_person_overlay :: proc(renderer: ^Renderer, room: ^game.Room) {
	f := &renderer.tactical.first_person
	if f.amount <= 0 { return }
	now := renderer.sprite_assets.elapsed
	w, h := renderer.canvas_width, renderer.canvas_height
	// Hurt: the edges flash red.
	if t := now-f.hurt_at; f.hurt_at > 0 && t >= 0 && t < FIRST_PERSON_HURT_SECONDS {
		alpha := f32(1-t/FIRST_PERSON_HURT_SECONDS)
		for ring in 0..<3 {
			inset := f32(ring*4)
			rl.DrawRectangleLinesEx({inset, inset, w-inset*2, h-inset*2}, 4, color_with_opacity(GOTHIC_RED, alpha*(0.85-0.25*f32(ring))))
		}
	}
	if first_person_amount(renderer) <= FIRST_PERSON_AK_FROM { return }
	switch FIRST_PERSON_LOOKS[f.weapon].hand {
	case .AK: draw_first_person_ak(renderer, now)
	case .Fists:
		draw_first_person_marks(renderer, room, now)
		draw_first_person_gloves(renderer, room, now)
	case .Empty:
	}
	// The crosshair: four paper ticks in ink round a dot, warm over a foe; a
	// hit marks it with four corners a moment.
	draw_first_person_crosshair(renderer, f.aimed == .Foe, f.hit_at > 0 && now-f.hit_at >= 0 && now-f.hit_at < FIRST_PERSON_MARK_SECONDS)
	// The countdown, while he is behind his eyes.
	if !f.engaged || room == nil { return }
	bounds := first_person_countdown_bounds(renderer)
	left := room.first_person.remaining
	duration := max(room.first_person.duration, 0.001)
	accent := GOTHIC_RED if left <= 3 else FIRST_PERSON_OLIVE
	hud_frame(bounds, accent)
	gothic_text_fit(renderer, first_person_countdown_text(left, f.weapon), {bounds.x+12, bounds.y+4, bounds.width-24, 24}, 18, GOTHIC_PAPER)
	hud_bar({bounds.x+12, bounds.y+bounds.height-12, bounds.width-24, 6}, left/duration, accent, int(min(duration, 30)))
}

// The AK at the bottom right, its flash at the muzzle a moment after a shot.
@(private = "file")
draw_first_person_ak :: proc(renderer: ^Renderer, now: f64) {
	f := &renderer.tactical.first_person
	ak := first_person_ak_texture(f)
	if ak.id == 0 { return }
	at := first_person_ak_origin(renderer, now)
	scale := first_person_ak_scale(renderer)
	weapon_size := FIRST_PERSON_AK_SIZE*scale
	rl.DrawTexturePro(ak, {0, 0, f32(ak.width), f32(ak.height)}, {at.x, at.y, weapon_size.x, weapon_size.y}, {}, 0, rl.WHITE)
	if t := now-f.kick_at; f.kick_at > 0 && t >= 0 && t < FIRST_PERSON_FLASH_SECONDS {
		flash := first_person_flash_texture(f, int(f.flash)%2)
		if flash.id != 0 {
			muzzle := first_person_muzzle(renderer, now)
			size := rl.Vector2{f32(flash.width), f32(flash.height)}*scale
			rl.DrawTextureEx(flash, {math.round(muzzle.x-size.x*0.5), math.round(muzzle.y-size.y*0.5)}, 0, scale, rl.WHITE)
		}
	}
}

@(private = "file")
draw_first_person_crosshair :: proc(renderer: ^Renderer, on_foe, hit: bool) {
	color := rl.Color{255, 196, 150, 255} if on_foe else GOTHIC_PAPER
	cx, cy := math.round(renderer.canvas_width*0.5), math.round(renderer.canvas_height*0.5)
	ticks := [4]rl.Rectangle{{cx-14, cy-1, 9, 3}, {cx+6, cy-1, 9, 3}, {cx-1, cy-14, 3, 9}, {cx-1, cy+6, 3, 9}}
	for tick in ticks { rl.DrawRectangleRec({tick.x-1, tick.y-1, tick.width+2, tick.height+2}, LIVING_TOKEN_INK) }
	for tick in ticks { rl.DrawRectangleRec(tick, color) }
	rl.DrawRectangleRec({cx-2, cy-2, 5, 5}, LIVING_TOKEN_INK)
	rl.DrawRectangleRec({cx-1, cy-1, 3, 3}, color)
	if !hit { return }
	// The hit's corners, white in ink, between the ticks.
	for corner in ([4][2]f32{{-1, -1}, {1, -1}, {-1, 1}, {1, 1}}) {
		for step in 0..<3 {
			x := cx+1+corner.x*f32(7+step*2)-1
			y := cy+1+corner.y*f32(7+step*2)-1
			rl.DrawRectangleRec({x-1, y-1, 4, 4}, LIVING_TOKEN_INK)
		}
	}
	for corner in ([4][2]f32{{-1, -1}, {1, -1}, {-1, 1}, {1, 1}}) {
		for step in 0..<3 {
			x := cx+1+corner.x*f32(7+step*2)-1
			y := cy+1+corner.y*f32(7+step*2)-1
			rl.DrawRectangleRec({x, y, 2, 2}, rl.WHITE)
		}
	}
}

// The countdown's plate, at the bottom left where the hand was.
first_person_countdown_bounds :: proc(renderer: ^Renderer) -> rl.Rectangle {
	return {16, renderer.canvas_height-62, 176, 46}
}

// "FPS 12s": the weapon's tag and the whole seconds left, counted up.
first_person_countdown_text :: proc(left: f32, weapon := game.First_Person_Weapon.AK) -> cstring {
	return fmt.ctprintf("%s %ds", FIRST_PERSON_LOOKS[weapon].tag, int(math.ceil(max(f32(0), left)-0.0001)))
}

// The HUD's line behind his eyes: how the AK and the steps are worked.
FIRST_PERSON_HUD_STATUS :: cstring("MIRA COL MOUSE / CLIC: SPARA / WASD: PASSI")
// A weapon whose rules are still to come: only the look and the steps work.
FIRST_PERSON_HUD_STATUS_BARE :: cstring("MIRA COL MOUSE / WASD: PASSI")
// The fists: free moves, the four punches, the jump (the dash is a double tap).
FIRST_PERSON_HUD_STATUS_FISTS :: cstring("WASD LIBERO / CLIC: PUGNI / SPAZIO: SALTO")

// --------------------------------------------------------------------------
// Each weapon's look (game.FIRST_PERSON_WEAPONS has its rules).

// What is in hand: the AK's print, or nothing (the crosshair and the plate
// alone, as Doom's fist leaves the ammo box blank) until a weapon's own
// drawing comes (docs/piano-prima-persona.md, Fasi 3, 5 e 7).
First_Person_Hand :: enum u8 {Empty, AK, Fists}

First_Person_Look :: struct {
	// The countdown's tag (the new ones provisional, as wide as the AK's,
	// until Fase 3 names them), the HUD's line, the print in hand.
	tag: string,
	status: cstring,
	hand: First_Person_Hand,
}

@(rodata)
FIRST_PERSON_LOOKS := [game.First_Person_Weapon]First_Person_Look{
	.AK = {tag = "FPS", status = FIRST_PERSON_HUD_STATUS, hand = .AK},
	.Fists = {tag = "FPB", status = FIRST_PERSON_HUD_STATUS_FISTS, hand = .Fists},
	.Sword = {tag = "FPF", status = FIRST_PERSON_HUD_STATUS_BARE},
	.Bow = {tag = "FPA", status = FIRST_PERSON_HUD_STATUS_BARE},
}

// The weapon the board shows: the room's while the view is on, the last one
// through the rise back.
first_person_shown_weapon :: proc(renderer: ^Renderer) -> game.First_Person_Weapon {
	if renderer == nil { return .AK }
	return renderer.tactical.first_person.weapon
}

// The HUD's line for the weapon in hand.
first_person_hud_status :: proc(renderer: ^Renderer) -> cstring {
	return FIRST_PERSON_LOOKS[first_person_shown_weapon(renderer)].status
}
