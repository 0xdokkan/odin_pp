package render

import "core:fmt"
import "core:math"
import rl "vendor:raylib"
import rlgl "vendor:raylib/rlgl"
import gfx "../engine/gfx"
import game "../game"
import grid "../engine/grid"
import view "../engine/view"

// PINBALL on the board (game/pinball.odin). The foe's card turns into a big
// steel ball of pixel art painted by code (pinball_ball_pixels): a sphere in
// six tones of steel that mirrors the room (a light top, a bright horizon, a
// dark floor), its white highlight, a band of the foe's own colour round it so
// the player knows who it was, an ink line, and the cards' white paper margin
// with its ink cut and the cut edge's shadow down and to the right. The card's
// own cue (Pinball_Made, stretched with the card's others over the cast) pops
// it: the card fades in a puff of paper and the ball swells past its size and
// settles. As the Pinball_Launched cue starts the player's card is set to swing
// its weapon so that the blow lands as the cast ends, when the ball starts to
// roll, and a star flashes on the ball there. Then the board shows the ball
// where the room says it is, every frame (the roll records no event of its
// own but its contacts), turning as it rolls: its band rolls round the axis
// across its way, the distance over its radius. A soft round shadow lies under
// it, a grey star flashes where it touches a solid thing and a red one between
// it and a foe it strikes (COLPO n over the foe). When its time is up it swells
// with a white flash and bursts into paper and confetti of its colour (POP!);
// the foe falls there, its card never shown again. Behind the player's eyes
// (first_person.odin) it fades as it rolls over him, gone at the eye. Nothing here gates gameplay
// or input.

PINBALL_STEEL_LIGHT :: rl.Color{214, 222, 232, 255}
PINBALL_STEEL_DARK :: rl.Color{44, 50, 60, 255}
// The steel's six tones, from the floor's dark to the light's.
@(rodata)
PINBALL_STEEL := [6]rl.Color{{30, 34, 44, 255}, {62, 70, 86, 255}, {102, 112, 130, 255}, {148, 158, 176, 255}, {198, 206, 218, 255}, {238, 242, 248, 255}}
// The ball's sprite: its texels a side, the steel's radius and the paper's
// width round it, in texels of the board's props (attack_texel: 60 texels of
// steel are 1.2 cells across).
PINBALL_SPRITE :: 70
PINBALL_SPRITE_STEEL :: f32(30)
PINBALL_SPRITE_PAPER :: f32(3)
// The band round it: the share of the normal across its axis it covers, then
// its ink edges.
PINBALL_BAND :: f32(0.2)
PINBALL_BAND_EDGE :: f32(0.26)
// The making, as shares of its cue: the card fades from FADE to HIDE (then it
// is gone), the ball swells from HIDE to SWELL, past its size and back, and
// paper puffs from FADE to PUFF_END.
PINBALL_CARD_FADE :: f32(0.2)
PINBALL_MADE_HIDE :: f32(0.35)
PINBALL_MADE_SWELL :: f32(0.75)
PINBALL_MADE_PUFF_END :: f32(0.75)
// The swell's spring: 15% past its size at its height.
PINBALL_SWELL_SPRING :: f32(2.2)
// Without the card's cue (a board that missed it), its own length.
PINBALL_MADE_SECONDS :: f64(PRESENTATION_PINBALL_MADE_DURATION)
// The burst: the ball swells a quarter with a white flash, then bursts into
// paper and confetti that fly out and fall; its POP! stands clear over it.
PINBALL_BURST_SWELL :: f64(0.15)
PINBALL_BURST_SECONDS :: f64(0.6)
PINBALL_BURST_GROWTH :: f32(0.25)
PINBALL_BURST_BADGE_CLEAR :: f32(0.12)
PINBALL_IMPACTS :: 8
PINBALL_IMPACTS_SEEN :: 32
PINBALL_IMPACT_SECONDS :: f64(0.42)
// The quad stands this far toward the eye from the ball's centre, so that no
// wall or card right behind it cuts into it.
PINBALL_TOWARD_EYE :: f32(0.3)
// Behind the player's eyes (first_person.odin) the ball rolls over him and
// through the eye: whole while its centre is this far from the eye or more,
// it fades as it nears and is gone this near, before it would fill the view.
PINBALL_EYE_CLEAR :: f32(1.4)
PINBALL_EYE_GONE :: f32(0.75)
// A touch of a solid thing (stone grey), of a foe (red), the strike (gold).
PINBALL_WALL_GREY :: rl.Color{176, 170, 160, 255}
PINBALL_HIT_RED :: rl.Color{196, 44, 44, 255}
PINBALL_STRIKE_GOLD :: rl.Color{250, 214, 112, 255}
// The card's aim: the foes it can take, the one under the mouse, its launch.
PINBALL_AIM_LINE :: rl.Color{196, 206, 220, 235}
PINBALL_AIM_HOT :: rl.Color{238, 242, 248, 255}

// What makes a contact's cue this one, whichever frame shows it.
Pinball_Cue_Key :: struct {
	batch: u32,
	kind: Presentation_Cue_Kind,
	source, target: game.Entity_Ref,
	amount, duration: i32,
	from, to: grid.Position,
}

Pinball_Impact_Kind :: enum u8 {Wall, Foe, Strike}

Pinball_Impact :: struct {
	used: bool,
	kind: Pinball_Impact_Kind,
	// Where it shows, and the cell it happened on (the fog asks that).
	at: rl.Vector3,
	cell: grid.Position,
	born: f64,
	seed: int,
}

Pinball_View :: struct {
	// The room's ball as last seen: the foe it is and its colour, where it is
	// (the snapshot shows the foe there), its way, its value and the card's,
	// and its seconds left.
	active: bool,
	enemy: game.Entity_Ref,
	archetype: game.Enemy_Archetype,
	at: view.Vec2,
	heading: [2]f32,
	value, base: i32,
	left: f32,
	// When it was first seen (sprite clock), the making's progress (1: made)
	// and whether the card's Pinball_Made cue paces it.
	began: f64,
	made: f32,
	made_paced: bool,
	// The strike: the swing set to land at `contact` (sprite clock), and its
	// star shown there.
	struck, launched: bool,
	contact: f64,
	// The roll's look: the band's axis in the world, and the place it was
	// last turned to.
	axis: rl.Vector3,
	turned_at: view.Vec2,
	// The burst, from `ended` (sprite clock) at `end_at`; `dead` once its foe
	// has fallen: that card never shows again.
	ending, dead: bool,
	ended: f64,
	end_at: view.Vec2,
	impacts: [PINBALL_IMPACTS]Pinball_Impact,
	impact_next: int,
	seen: [PINBALL_IMPACTS_SEEN]Pinball_Cue_Key,
	seen_next: int,
	// The sprite's texture and its pixels as last painted, for that band and
	// that axis on screen.
	texture: rl.Texture2D,
	pixels: [PINBALL_SPRITE*PINBALL_SPRITE*4]u8,
	painted: bool,
	painted_axis: rl.Vector3,
	painted_band: rl.Color,
	// What the board has shown so far (the lab's sounds, the smoke and tests).
	makes, strikes, bounces, bumps, bursts: int,
}

// A fresh ball (or board): what was shown of the last one goes, the texture
// and the counts stay.
@(private)
pinball_view_reset :: proc(b: ^Pinball_View) {
	texture := b.texture
	makes, strikes, bounces, bumps, bursts := b.makes, b.strikes, b.bounces, b.bumps, b.bursts
	seen, seen_next := b.seen, b.seen_next
	b^ = {}
	b.texture = texture
	b.makes, b.strikes, b.bounces, b.bumps, b.bursts = makes, strikes, bounces, bumps, bursts
	b.seen, b.seen_next = seen, seen_next
}

@(private)
destroy_pinball_view :: proc(renderer: ^Renderer) {
	b := &renderer.tactical.pinball
	if b.texture.id != 0 { rl.UnloadTexture(b.texture) }
	b^ = {}
}

// The steel's radius in world units: the ball's centre stands that high.
@(private)
pinball_steel_radius :: proc() -> f32 {
	return PINBALL_SPRITE_STEEL*attack_texel(.Pilgrim)
}

// The band identifies the archetype of the foe inside the ball.
@(private)
pinball_band_color :: proc(archetype: game.Enemy_Archetype) -> rl.Color {
	switch archetype {
	case .Chaser: return {224, 99, 86, 255}
	case .Archer: return {92, 154, 215, 255}
	case .Brute: return {213, 142, 66, 255}
	case .Bomber: return {191, 113, 212, 255}
	// Never a ball (game.pinball_target_error): too heavy.
	case .Custodian, .Demolitionist, .Count:
	}
	return GOTHIC_RED
}

// The ball's centre in the world as the board shows it at `at`.
@(private)
pinball_centre_at :: proc(at: view.Vec2) -> rl.Vector3 {
	return {at.x+0.5, pinball_steel_radius(), at.y+0.5}
}

// Where the burst's POP! stands (tactical_feedback_badges): its foot over the
// top of the ball at its fullest swell, paper rim and all.
@(private)
pinball_burst_badge_height :: proc() -> f32 {
	return pinball_steel_radius()+(pinball_steel_radius()+PINBALL_SPRITE_PAPER*attack_texel(.Pilgrim))*(1+PINBALL_BURST_GROWTH)+
		PINBALL_BURST_BADGE_CLEAR
}

// The snapshot's `entity` shown at `at` (the ball, or where it burst).
@(private = "file")
pinball_override :: proc(renderer: ^Renderer, entity: game.Entity_Ref, at: view.Vec2) {
	if actor, found := presentation_actor_in_view(renderer.tactical.snapshot, entity); found { actor.position = at }
}

// The card the ball has taken the place of: past the making's hide (or
// bursting, or fallen), its card never shows.
@(private)
tactical_pinball_holds :: proc(renderer: ^Renderer, entity: game.Entity_Ref) -> bool {
	if renderer == nil { return false }
	b := &renderer.tactical.pinball
	return entity.kind == .Enemy && entity == b.enemy && ((b.active && b.made >= PINBALL_MADE_HIDE) || b.ending || b.dead)
}

// How much of the foe's card shows while it turns into the ball: whole, then
// fading in the puff of paper, then none (tactical_pinball_holds).
@(private)
pinball_card_opacity :: proc(renderer: ^Renderer, entity: game.Entity_Ref) -> f32 {
	if renderer == nil { return 1 }
	b := &renderer.tactical.pinball
	if entity.kind != .Enemy || entity != b.enemy || !b.active { return 1 }
	u := clamp((b.made-PINBALL_CARD_FADE)/(PINBALL_MADE_HIDE-PINBALL_CARD_FADE), 0, 1)
	return 1-u*u*(3-2*u)
}

// The ball's size now (1: its own) and how white its flash is: nothing before
// the making's hide, then a swell past its size and back; at its burst a swell
// with a flash, then nothing.
@(private)
pinball_ball_scale :: proc(b: ^Pinball_View, now: f64) -> (scale, flash: f32) {
	if b.ending {
		t := now-b.ended
		if t >= PINBALL_BURST_SWELL { return 0, 0 }
		p := f32(t/PINBALL_BURST_SWELL)
		return 1+PINBALL_BURST_GROWTH*p, p
	}
	if !b.active || b.made <= PINBALL_MADE_HIDE { return 0, 0 }
	if b.made >= PINBALL_MADE_SWELL { return 1, 0 }
	p := (b.made-PINBALL_MADE_HIDE)/(PINBALL_MADE_SWELL-PINBALL_MADE_HIDE)
	w := p-1
	c := PINBALL_SWELL_SPRING
	return 1+w*w*((c+1)*w+c), 0
}

// `v` turned `angle` radians round the unit axis `k`.
@(private = "file")
pinball_rotate :: proc(v, k: rl.Vector3, angle: f32) -> rl.Vector3 {
	c, s := math.cos(angle), math.sin(angle)
	return v*c+rl.Vector3CrossProduct(k, v)*s+k*(rl.Vector3DotProduct(k, v)*(1-c))
}

// The band turns as the ball rolls on the floor without slipping: round the
// axis across its way, by the distance over its radius.
@(private = "file")
pinball_turn_ball :: proc(b: ^Pinball_View) {
	d := rl.Vector3{b.at.x-b.turned_at.x, 0, b.at.y-b.turned_at.y}
	b.turned_at = b.at
	distance := rl.Vector3Length(d)
	if distance < 0.00001 || distance > 2 { return }
	k := rl.Vector3Normalize(rl.Vector3CrossProduct({0, 1, 0}, d))
	b.axis = rl.Vector3Normalize(pinball_rotate(b.axis, k, distance/pinball_steel_radius()))
}

// Once per frame, right after the Lazzo's (update_tactical_view, which may run
// twice a frame): follows the room's ball and shows its foe where it rolls;
// then the strike, the burst and the cues of its contacts.
@(private)
update_tactical_pinball :: proc(renderer: ^Renderer, room: ^game.Room) {
	v := &renderer.tactical
	b := &v.pinball
	if room == nil || room.player == nil || v.snapshot == nil { return }
	now := renderer.sprite_assets.elapsed
	s := &room.pinball
	rolling := game.tactical_pinball_active(room)
	foe := game.enemy_entity(s.enemy_id)
	if rolling && (!b.active || b.enemy != foe) {
		pinball_view_reset(b)
		b.active, b.enemy, b.began = true, foe, now
		if index, found := game.enemy_index_by_id(room, s.enemy_id); found { b.archetype = room.enemies[index].archetype }
		_, b.made_paced = shadow_cue_progress(renderer, .Pinball_Made)
		// A board that first sees it after its strike (a fresh board) shows it
		// as it is: made, and struck.
		if !b.made_paced && !game.tactical_is_casting(room) { b.made, b.struck, b.launched = 1, true, true }
		// The band starts round its middle, a little tilted.
		b.axis = rl.Vector3Normalize({0.3, 1, -0.2})
		p := game.pinball_position(s)
		b.turned_at = {f32(p.x), f32(p.y)}
		b.makes += 1
	}
	if rolling {
		p := game.pinball_position(s)
		b.at = {f32(p.x), f32(p.y)}
		b.heading = {f32(s.heading.x), f32(s.heading.y)}
		b.value, b.base = s.value, s.base
		b.left = f32(game.pinball_seconds_left(s))
		if b.made_paced {
			progress, found := shadow_cue_progress(renderer, .Pinball_Made)
			b.made = progress if found else 1
		} else if b.made < 1 {
			b.made = f32(clamp((now-b.began)/(PINBALL_MADE_SECONDS*renderer_action_scale(renderer)), 0, 1))
		}
		pinball_strike(renderer, room, b, now)
		pinball_turn_ball(b)
		pinball_override(renderer, b.enemy, b.at)
	} else if b.active {
		// The ball is gone: it burst and its foe fell where it was, or the
		// fight ended with it still rolling (the player fell): then its card
		// is simply back on its cell.
		b.active = false
		if _, alive := game.enemy_index_by_id(room, b.enemy.id); !alive {
			b.ending, b.dead, b.ended, b.end_at = true, true, now, b.at
			b.bursts += 1
		}
	}
	if b.ending && now-b.ended >= PINBALL_BURST_SECONDS { b.ending = false }
	// A fallen foe still on show (its defeat's cue) stands where it burst; one
	// alive in the room with its id is another (a new room's).
	if b.dead && !b.ending {
		if _, alive := game.enemy_index_by_id(room, b.enemy.id); alive { b.dead = false }
	}
	if b.dead { pinball_override(renderer, b.enemy, b.end_at) }
	observe_pinball_cues(renderer, now)
}

// The strike: as the Pinball_Launched cue starts (at once on a board without
// it) the player's card is set to swing its weapon at the ball, the blow
// landing as the cast ends, when the ball rolls; at that contact a star
// flashes on the ball.
@(private = "file")
pinball_strike :: proc(renderer: ^Renderer, room: ^game.Room, b: ^Pinball_View, now: f64) {
	if !b.struck {
		waiting := false
		for offset in 0..<renderer.timeline.count {
			cue, ok := presentation_cue_at(&renderer.timeline, offset)
			if ok && cue.kind == .Pinball_Launched && cue.event.target == b.enemy && !cue.started { waiting = true }
		}
		if waiting { return }
		delay := f64(max(f32(0), room.player.tactical.cast_remaining))
		b.struck, b.contact = true, now+delay
		b.strikes += 1
		cell := grid.Position{x = int(math.round(b.at.x)), y = int(math.round(b.at.y))}
		// The swing's own impact would follow the ball as it flies off: the
		// strike's star is the ball's own, where the blow lands.
		weapon := renderer.tactical.snapshot.weapon if renderer.tactical.snapshot != nil else game.Weapon_Id.None
		_, _ = play_attack_swing(renderer, game.PLAYER_ENTITY, game.SYSTEM_ENTITY, attack_player_look(weapon), cell, contact = delay)
		if pilgrim := living_find(renderer, game.PLAYER_ENTITY, .Pilgrim); pilgrim != nil {
			if player, found := presentation_actor_in_view(renderer.tactical.snapshot, game.PLAYER_ENTITY); found {
				d := rl.Vector3{b.at.x-player.position.x, 0, b.at.y-player.position.y}
				living_face(pilgrim, rl.Vector3DotProduct(d, flipbook_camera_right(renderer)), now)
			}
			living_start(pilgrim, .Attack, b.contact-attack_fx_impact_seconds(.Pilgrim, pilgrim.scale))
			pilgrim.cause, pilgrim.shot = .Pinball_Launched, false
		}
	}
	if b.struck && !b.launched && now >= b.contact {
		b.launched = true
		centre := pinball_centre_at(b.at)
		toward := attack_toward_camera(renderer)
		pinball_impact(b, .Strike, centre+toward*0.35, {x = int(math.round(b.at.x)), y = int(math.round(b.at.y))}, now, int(b.enemy.id)*5)
	}
}

@(private = "file")
pinball_impact :: proc(b: ^Pinball_View, kind: Pinball_Impact_Kind, at: rl.Vector3, cell: grid.Position, now: f64, seed: int) {
	b.impacts[b.impact_next] = {used = true, kind = kind, at = at, cell = cell, born = now, seed = seed}
	b.impact_next = (b.impact_next+1)%len(b.impacts)
}

// A star for each contact as its cue starts showing: at the solid thing's
// side nearest the ball (grey, with stone dust), or between the ball and the
// foe it struck (red); either a little toward the camera.
@(private = "file")
observe_pinball_cues :: proc(renderer: ^Renderer, now: f64) {
	b := &renderer.tactical.pinball
	for offset in 0..<renderer_active_cue_count(renderer) {
		cue, found := renderer_active_cue_at(renderer, offset)
		if !found || !cue.started || (cue.kind != .Pinball_Bounced && cue.kind != .Pinball_Bumped) { continue }
		key := Pinball_Cue_Key{batch = cue.batch, kind = cue.kind, source = cue.event.source, target = cue.event.target,
			amount = cue.event.amount, duration = cue.event.duration, from = cue.event.from_position, to = cue.event.to_position}
		seen := false
		for previous in b.seen { if previous == key && key.batch != 0 { seen = true; break } }
		if seen { continue }
		b.seen[b.seen_next] = key
		b.seen_next = (b.seen_next+1)%len(b.seen)
		at := b.end_at if b.dead else b.at
		ball := pinball_centre_at(at)
		toward := attack_toward_camera(renderer)
		seed := int(cue.event.amount)*7+cue.event.to_position.x*3+cue.event.to_position.y+int(cue.event.duration)
		if cue.kind == .Pinball_Bounced {
			wall := cue.event.to_position
			point := rl.Vector3{clamp(ball.x, f32(wall.x), f32(wall.x+1)), ball.y*0.8, clamp(ball.z, f32(wall.y), f32(wall.y+1))}
			// In front of the wall's face as the camera sees it.
			facing := max(f32(0), rl.Vector3DotProduct(rl.Vector3Normalize(ball-point+{0, 0.0001, 0}), toward))
			pinball_impact(b, .Wall, point+toward*(0.12+0.25*(1-facing)), cue.event.from_position, now, seed)
			b.bounces += 1
		} else {
			point := ball
			if struck, ok := attack_struck_point(renderer, cue.event.target); ok { point = (ball+struck)*0.5 }
			pinball_impact(b, .Foe, point+toward*0.3, cue.event.to_position, now, seed)
			b.bumps += 1
		}
	}
}

// The ball (its making's puffs and its burst with it) and the contacts'
// stars, sorted with the cards and walls (one entry each). The ball sorts
// where it rolls; it is drawn without a room too (the map's hologram).
@(private)
collect_pinball_entries :: proc(renderer: ^Renderer, entries: ^[dynamic]Tactical_Alpha_Entry) {
	b := &renderer.tactical.pinball
	now := renderer.sprite_assets.elapsed
	if b.active || b.ending {
		at := b.end_at if b.ending else b.at
		if tactical_render_visible(renderer, {x = int(math.round(at.x)), y = int(math.round(at.y))}) {
			append(entries, Tactical_Alpha_Entry{kind = .Pinball, pinball = 0, entity = b.enemy, position = at})
		}
	}
	toward := attack_toward_camera(renderer)
	for impact, index in b.impacts {
		if !impact.used || now-impact.born > PINBALL_IMPACT_SECONDS { continue }
		append(entries, Tactical_Alpha_Entry{kind = .Pinball, pinball = i32(1+index),
			position = {impact.at.x-0.5+toward.x*0.4, impact.at.z-0.5+toward.z*0.4}})
	}
}

@(private)
draw_pinball_entry :: proc(renderer: ^Renderer, entry: Tactical_Alpha_Entry) {
	b := &renderer.tactical.pinball
	rlgl.DrawRenderBatchActive()
	rlgl.DisableBackfaceCulling()
	defer { rlgl.DrawRenderBatchActive(); rlgl.EnableBackfaceCulling() }
	if entry.pinball == 0 {
		draw_pinball_ball(renderer, b)
		return
	}
	index := int(entry.pinball)-1
	if index >= 0 && index < len(b.impacts) { draw_pinball_impact(renderer, &b.impacts[index]) }
}

// The band's axis on screen (x right, y down, z toward the eye), as the
// painter takes it.
@(private = "file")
pinball_view_axis :: proc(renderer: ^Renderer, axis: rl.Vector3) -> rl.Vector3 {
	camera := renderer.tactical.camera
	right, up := attack_screen_axes(renderer)
	toward := rl.Vector3Normalize(camera.position-camera.target)
	return {rl.Vector3DotProduct(axis, right), -rl.Vector3DotProduct(axis, up), rl.Vector3DotProduct(axis, toward)}
}

// The sprite's texture, painted afresh when its band or its axis on screen
// has changed.
@(private = "file")
pinball_texture :: proc(renderer: ^Renderer, b: ^Pinball_View) -> rl.Texture2D {
	if b.texture.id == 0 {
		image := rl.GenImageColor(PINBALL_SPRITE, PINBALL_SPRITE, rl.BLANK)
		defer rl.UnloadImage(image)
		b.texture = rl.LoadTextureFromImage(image)
		if b.texture.id == 0 { return {} }
		rl.SetTextureFilter(b.texture, .POINT)
		rl.SetTextureWrap(b.texture, .CLAMP)
		b.painted = false
	}
	axis := pinball_view_axis(renderer, b.axis)
	band := pinball_band_color(b.archetype)
	if !b.painted || b.painted_axis != axis || b.painted_band != band {
		pinball_ball_pixels(band, axis, b.pixels[:])
		rl.UpdateTexture(b.texture, raw_data(b.pixels[:]))
		b.painted, b.painted_axis, b.painted_band = true, axis, band
	}
	return b.texture
}

@(private = "file")
draw_pinball_ball :: proc(renderer: ^Renderer, b: ^Pinball_View) {
	now := renderer.sprite_assets.elapsed
	centre := pinball_centre_at(b.end_at if b.ending else b.at)
	if b.active { draw_pinball_puffs(renderer, b, centre) }
	if b.ending { draw_pinball_burst(renderer, b, centre, now) }
	scale, flash := pinball_ball_scale(b, now)
	if scale <= 0.01 { return }
	// Behind the player's eyes it fades as it rolls over him.
	shown := pinball_eye_opacity(renderer, centre)
	if shown <= 0.01 { return }
	texture := pinball_texture(renderer, b)
	if texture.id == 0 { return }
	camera := renderer.tactical.camera
	right, up := attack_screen_axes(renderer)
	toward := rl.Vector3Normalize(camera.position-centre)
	c := centre+toward*PINBALL_TOWARD_EYE
	half := f32(PINBALL_SPRITE)*0.5*attack_texel(.Pilgrim)*scale
	corners := [4]rl.Vector3{c-right*half+up*half, c-right*half-up*half, c+right*half-up*half, c+right*half+up*half}
	uv := [4][2]f32{{0, 0}, {0, 1}, {1, 1}, {1, 0}}
	passes := 2 if flash > 0.01 else 1
	for pass in 0..<passes {
		// The flash: the sprite again, added over itself.
		if pass == 1 { rl.BeginBlendMode(.ADDITIVE) }
		alpha := u8(255*shown) if pass == 0 else u8(clamp(flash, 0, 1)*230*shown)
		rlgl.SetTexture(texture.id)
		rlgl.Begin(rlgl.QUADS)
		rlgl.Color4ub(255, 255, 255, alpha)
		for corner, k in corners {
			rlgl.TexCoord2f(uv[k].x, uv[k].y)
			rlgl.Vertex3f(corner.x, corner.y, corner.z)
		}
		rlgl.End()
		rlgl.SetTexture(0)
		if pass == 1 { rl.EndBlendMode() }
	}
}

// How much of the ball shows with its centre at `centre`: all of it, but
// behind the player's eyes it fades as it nears the eye (it rolls over him
// harmlessly), as far as the camera has gone into them.
@(private)
pinball_eye_opacity :: proc(renderer: ^Renderer, centre: rl.Vector3) -> f32 {
	amount := first_person_amount(renderer)
	if amount <= 0 { return 1 }
	distance := rl.Vector3Distance(renderer.tactical.camera.position, centre)
	u := 1-clamp((distance-PINBALL_EYE_GONE)/(PINBALL_EYE_CLEAR-PINBALL_EYE_GONE), 0, 1)
	return 1-u*u*(3-2*u)*amount
}

// The puff of paper the card goes up in as it turns into the ball.
@(private = "file")
draw_pinball_puffs :: proc(renderer: ^Renderer, b: ^Pinball_View, centre: rl.Vector3) {
	if b.made < PINBALL_CARD_FADE || b.made >= PINBALL_MADE_PUFF_END { return }
	p := (b.made-PINBALL_CARD_FADE)/(PINBALL_MADE_PUFF_END-PINBALL_CARD_FADE)
	right, up := attack_screen_axes(renderer)
	texel := attack_texel(.Pilgrim)
	for index in 0..<9 {
		angle := f32(index)*math.TAU/9+0.25
		out := right*math.cos(angle)+up*(0.85*math.sin(angle))
		point := centre+out*(0.22+0.55*p)+up*(0.12*p)
		puff := gfx.Attack_Prop.Dust_A if index%2 == 0 else gfx.Attack_Prop.Dust_B
		turn := (f32(index%3)-1)*0.4+p*0.6*(1 if index%2 == 0 else -1)
		swell := texel*(1.1+0.3*f32(index%3))*(1+0.9*p)
		draw_attack_prop(renderer, puff, point, point+up*math.cos(turn)+right*math.sin(turn), swell, clamp((1-p)*1.8, 0, 1), LIVING_TOKEN_PAPER)
	}
	shards := [3]gfx.Attack_Prop{.Shard_A, .Shard_B, .Shard_C}
	for index in 0..<5 {
		angle := f32(index)*2.1+0.6
		out := right*math.cos(angle)+rl.Vector3CrossProduct(right, up)*math.sin(angle)*0.4
		point := centre+out*(0.6*p)+rl.Vector3{0, 0.35*p-0.8*p*p, 0}
		turn := p*9+f32(index)
		draw_attack_prop(renderer, shards[index%3], point, point+up*math.cos(turn)+right*math.sin(turn), texel, clamp((1-p)*2.5, 0, 1))
	}
}

// The burst: a white paper star where the ball was, steel-grey paper and
// confetti of its colour flung out and falling, and puffs of paper.
@(private = "file")
draw_pinball_burst :: proc(renderer: ^Renderer, b: ^Pinball_View, centre: rl.Vector3, now: f64) {
	t := now-b.ended
	if t < PINBALL_BURST_SWELL || t > PINBALL_BURST_SECONDS { return }
	p := f32((t-PINBALL_BURST_SWELL)/(PINBALL_BURST_SECONDS-PINBALL_BURST_SWELL))
	right, up := attack_screen_axes(renderer)
	texel := attack_texel(.Pilgrim)
	if p < 0.45 {
		spin := p*1.2
		draw_attack_prop(renderer, .Impact, centre, centre+up*math.cos(spin)+right*math.sin(spin), texel*(2.6-1.4*p),
			clamp((0.45-p)/0.45*2, 0, 1), rl.WHITE)
	}
	band := pinball_band_color(b.archetype)
	shards := [3]gfx.Attack_Prop{.Shard_A, .Shard_B, .Shard_C}
	for index in 0..<14 {
		angle := f32(index)*math.TAU/14+0.3
		out := right*math.cos(angle)+up*math.sin(angle)
		reach := 0.25+0.9*p*(0.8+0.2*f32(index%3))
		point := centre+out*reach+rl.Vector3{0, -0.75*p*p, 0}
		turn := p*11+f32(index)*1.3
		tint := band if index%2 == 0 else PINBALL_STEEL_LIGHT
		draw_attack_prop(renderer, shards[index%3], point, point+up*math.cos(turn)+right*math.sin(turn), texel*1.5, clamp((1-p)*2, 0, 1), tint)
	}
	for index in 0..<6 {
		angle := f32(index)*math.TAU/6+0.5
		point := centre+(right*math.cos(angle)+up*(0.7*math.sin(angle)))*(0.2+0.45*p)
		puff := gfx.Attack_Prop.Dust_A if index%2 == 0 else gfx.Attack_Prop.Dust_B
		turn := p*0.8*(1 if index%2 == 0 else -1)
		draw_attack_prop(renderer, puff, point, point+up*math.cos(turn)+right*math.sin(turn), texel*(1.3+0.9*p),
			clamp((1-p)*1.6, 0, 1), LIVING_TOKEN_PAPER)
	}
}

// A contact's paper star (grey at a wall, red on a foe, gold at the strike)
// and paper bits thrown off it; a wall's, stone dust too.
@(private = "file")
draw_pinball_impact :: proc(renderer: ^Renderer, impact: ^Pinball_Impact) {
	t := renderer.sprite_assets.elapsed-impact.born
	if !impact.used || t < 0 || t > PINBALL_IMPACT_SECONDS || !tactical_render_visible(renderer, impact.cell) { return }
	right, up := attack_screen_axes(renderer)
	texel := attack_texel(.Pilgrim)
	tint := PINBALL_WALL_GREY
	size := f32(1)
	switch impact.kind {
	case .Wall:
	case .Foe: tint, size = PINBALL_HIT_RED, 1.2
	case .Strike: tint, size = PINBALL_STRIKE_GOLD, 1.45
	}
	if t < ATTACK_IMPACT_SECONDS {
		grip, tip, star, opacity := attack_impact_star(renderer, impact.at, t, impact.seed)
		draw_attack_prop(renderer, .Impact, grip, tip, star*size, opacity, tint)
	}
	p := f32(t/PINBALL_IMPACT_SECONDS)
	shards := [3]gfx.Attack_Prop{.Shard_A, .Shard_B, .Shard_C}
	for index in 0..<3 {
		angle := f32(impact.seed*5+index*3)*1.9
		out := right*math.cos(angle)+rl.Vector3CrossProduct(right, up)*math.sin(angle)*0.4
		point := impact.at+out*(0.45*p)+rl.Vector3{0, 0.3*p-0.9*p*p, 0}
		turn := p*9+f32(index)
		draw_attack_prop(renderer, shards[index], point, point+up*math.cos(turn)+right*math.sin(turn), texel, clamp((1-p)*2.5, 0, 1))
	}
	if impact.kind != .Wall { return }
	for index in 0..<4 {
		angle := f32(index)*math.TAU/4+f32(impact.seed%5)*0.5
		point := impact.at+(right*math.cos(angle)+up*(0.35*math.sin(angle)))*(0.1+0.3*p)+up*(0.14*p)
		puff := gfx.Attack_Prop.Dust_A if index%2 == 0 else gfx.Attack_Prop.Dust_B
		turn := p*0.5*(1 if index%2 == 0 else -1)
		draw_attack_prop(renderer, puff, point, point+up*math.cos(turn)+right*math.sin(turn), texel*(0.8+0.6*p),
			clamp((1-p)*1.6, 0, 1)*0.85, LASSO_DUST)
	}
}

// Under the ball, in place of its card's stand (draw_tactical_actor_bases): a
// soft round shadow on the floor, as wide as the ball is now.
@(private)
draw_pinball_shadow :: proc(renderer: ^Renderer) {
	b := &renderer.tactical.pinball
	scale, _ := pinball_ball_scale(b, renderer.sprite_assets.elapsed)
	if scale <= 0.01 { return }
	at := b.end_at if b.ending else b.at
	if !tactical_render_visible(renderer, {x = int(math.round(at.x)), y = int(math.round(at.y))}) { return }
	for layer in 0..<4 {
		radius := (f32(0.5)-f32(layer)*0.06)*min(scale, 1.1)
		rl.DrawCylinder({at.x+0.5, 0.024+f32(layer)*0.001, at.y+0.5}, radius, radius, 0.001, 28, {1, 5, 12, u8(9+layer*6)})
	}
}

// --------------------------------------------------------------------------
// The ball's sprite.

@(private = "file")
pinball_dot3 :: proc(a, b: [3]f32) -> f32 {
	return a.x*b.x+a.y*b.y+a.z*b.z
}

@(private = "file")
pinball_normalize3 :: proc(v: [3]f32) -> [3]f32 {
	length := math.sqrt(pinball_dot3(v, v))
	return v/length if length > 0.000001 else {0, 1, 0}
}

// The ball's sprite into `out` (RGBA rows, PINBALL_SPRITE texels a side): a
// steel sphere lit from the top left of the view, mirroring the room (the
// light above, a bright horizon, the dark floor and its light back under its
// rim), a white highlight, a band of `band` round the axis `axis` (in the
// view: x right, y down, z toward the eye) between two ink lines; an ink line
// round the steel, the white paper round it, its ink cut, and the cut edge
// one texel down and to the right.
@(private)
pinball_ball_pixels :: proc(band: rl.Color, axis: [3]f32, out: []u8) {
	if len(out) < PINBALL_SPRITE*PINBALL_SPRITE*4 { return }
	put :: proc(out: []u8, x, y: int, colour: rl.Color) {
		at := (y*PINBALL_SPRITE+x)*4
		out[at], out[at+1], out[at+2], out[at+3] = colour.r, colour.g, colour.b, colour.a
	}
	R, P := PINBALL_SPRITE_STEEL, PINBALL_SPRITE_PAPER
	centre := f32(PINBALL_SPRITE)*0.5-0.5
	light := pinball_normalize3({-0.5, -0.65, 0.58})
	half := pinball_normalize3(light+{0, 0, 1})
	a := pinball_normalize3(axis)
	lit :: proc(channel: u8, k: f32) -> u8 { return u8(clamp(f32(channel)*k, 0, 255)) }
	for y in 0..<PINBALL_SPRITE {
		for x in 0..<PINBALL_SPRITE {
			dx, dy := f32(x)-centre, f32(y)-centre
			d := math.sqrt(dx*dx+dy*dy)
			colour := rl.BLANK
			switch {
			case d > R+P+1:
				// The cut edge, behind the paper one texel down and to the right.
				sx, sy := dx-1, dy-1
				shadow := math.sqrt(sx*sx+sy*sy)
				if shadow <= R+P+1 { colour = LIVING_TOKEN_INK if shadow > R+P else LIVING_TOKEN_EDGE }
			case d > R+P: colour = LIVING_TOKEN_INK
			case d > R: colour = LIVING_TOKEN_PAPER
			case d > R-1.2: colour = LIVING_TOKEN_INK
			case:
				n := [3]f32{dx/R, dy/R, 0}
				n.z = math.sqrt(max(0, 1-n.x*n.x-n.y*n.y))
				diffuse := max(0, pinball_dot3(n, light))
				env := f32(0.62) if n.y < -0.08 else (f32(0.95) if n.y < 0.02 else f32(0.18))
				tone := 0.15+0.45*diffuse+0.4*env*(0.6+0.4*n.z)
				if n.y > 0.55 && n.z < 0.55 { tone += 0.22 }
				colour = PINBALL_STEEL[clamp(int(tone*6), 0, 5)]
				across := abs(pinball_dot3(n, a))
				if across < PINBALL_BAND {
					k := 0.5+0.5*diffuse+0.25*env
					colour = {lit(band.r, k), lit(band.g, k), lit(band.b, k), 255}
					if k > 0.95 { colour = {u8(min(255, int(band.r)+40)), u8(min(255, int(band.g)+40)), u8(min(255, int(band.b)+40)), 255} }
				} else if across < PINBALL_BAND_EDGE {
					colour = LIVING_TOKEN_INK
				}
				spec := math.pow(max(0, pinball_dot3(n, half)), 60)
				if spec > 0.55 { colour = rl.WHITE } else if spec > 0.3 && across >= PINBALL_BAND_EDGE { colour = PINBALL_STEEL[5] }
			}
			put(out, x, y, colour)
		}
	}
}

// --------------------------------------------------------------------------
// The card's aim (draw_card_target_details).

PINBALL_HEAVY :: rl.Color{235, 91, 91, 255}

// While the Pinball is aimed: a boss or a miniboss beside the player, which it
// cannot take, marked with a red reticle (and
// TROPPO PESANTE, after the cards: draw_pinball_heavy_labels); for the foe under
// the mouse, the way the strike would send the ball now, up to the first solid
// thing on it.
@(private)
draw_pinball_preview :: proc(renderer: ^Renderer, room: ^game.Room, card: game.Card_Instance) {
	if renderer == nil || room == nil || room.player == nil || room.level_data == nil { return }
	definition, found := game.card_definition_by_id(card.definition_id)
	if !found { return }
	for enemy in room.enemies {
		if game.enemy_is_out_of_play(room, enemy.id) || !tactical_render_visible(renderer, enemy.position) { continue }
		evaluation := game.evaluate_card_targeting(room, card, game.card_target_request_at(definition, enemy.position))
		if evaluation.error == .Target_Too_Heavy {
			draw_aim_reticle(renderer, enemy.position, 0.46, 2, PINBALL_HEAVY)
			continue
		}
		if evaluation.error != .None { continue }
		// The foe itself is marked by the general "can be hit" mark (card_hit_mark.odin).
		if renderer.has_hovered_cell && renderer.hovered_cell == enemy.position { draw_pinball_launch_line(renderer, room, enemy.position) }
	}
}

// While the Pinball is aimed, TROPPO PESANTE
// under each foe in reach it cannot take: drawn after the cards and the seals
// (draw_tactical_world), so none of them hides it, and kept in the labels'
// layout, so the words over the board drawn after it keep clear.
@(private)
draw_pinball_heavy_labels :: proc(renderer: ^Renderer, room: ^game.Room, card_id: u32) {
	if renderer == nil || room == nil || room.player == nil || room.level_data == nil || room.phase != .Combat || card_id == 0 { return }
	if !tactical_telegraphs_are_visible(renderer, room) || renderer_blocks_player_input(renderer) { return }
	index, found := game.hand_card_index_by_id(&room.player.deck, card_id)
	if !found { return }
	card := room.player.deck.hand[index]
	if card.definition_id != .Pinball { return }
	definition, known := game.card_definition_by_id(card.definition_id)
	if !known { return }
	for enemy in room.enemies {
		if !tactical_render_visible(renderer, enemy.position) { continue }
		evaluation := game.evaluate_card_targeting(room, card, game.card_target_request_at(definition, enemy.position))
		if evaluation.error == .Target_Too_Heavy { draw_pinball_heavy_label(renderer, enemy.position) }
	}
}

// TROPPO PESANTE under the feet of a foe that cannot become a ball (over its head
// it would sit under its heart, or under the HUD), clear of the hearts and
// labels already placed (pinball_heavy_label_place).
@(private = "file")
draw_pinball_heavy_label :: proc(renderer: ^Renderer, cell: grid.Position) {
	label: cstring = "TROPPO PESANTE"
	anchor := tactical_project(renderer, {f32(cell.x)+0.5, f32(cell.y)+0.5})
	width := gothic_text_width(renderer, label, 12)+12
	bounds := pinball_heavy_label_place(renderer.tactical.labels, anchor, width, tactical_world_bounds(renderer))
	rl.DrawRectangleRec(bounds, {8, 15, 26, 235})
	rl.DrawRectangleRec({bounds.x, bounds.y, 2, bounds.height}, PINBALL_HEAVY)
	gothic_text(renderer, label, bounds.x+6, bounds.y+3, 12, PINBALL_HEAVY)
	if layout := renderer.tactical.labels; layout != nil && layout.count < len(layout.bounds) {
		layout.bounds[layout.count] = bounds
		layout.count += 1
	}
}

// Where TROPPO PESANTE goes under feet projected at `anchor`, `width` wide:
// just under them, else a row lower at a time, then beside them, left then
// right, the first place clear of the labels and hearts in `layout` (a
// neighbour's heart below them stays readable), inside `viewport`; with none
// clear, just under them still.
@(private)
pinball_heavy_label_place :: proc(layout: ^Tactical_Label_Layout, anchor: view.Vec2, width: f32, viewport: rl.Rectangle) -> rl.Rectangle {
	first := rl.Rectangle{math.round(anchor.x-width*0.5), math.round(anchor.y+12), width, 19}
	if layout == nil { return first }
	for side in ([3]f32{0, -1, 1}) {
		for row in 0..<4 {
			x := first.x+side*(width*0.5+8)
			y := first.y+f32(row)*13
			candidate := rl.Rectangle{math.round(clamp(x, viewport.x, viewport.x+viewport.width-width)),
				math.round(clamp(y, viewport.y, viewport.y+viewport.height-first.height)), width, first.height}
			if living_heart_is_clear(layout, candidate) { return candidate }
		}
	}
	return first
}

// The launch a strike at `cell` would give now (game.pinball_next_launch):
// paper dashes over ink from the ball's cell along its way, up to where its
// disc would first touch a solid thing (four cells at most), and a chevron.
@(private = "file")
draw_pinball_launch_line :: proc(renderer: ^Renderer, room: ^game.Room, cell: grid.Position) {
	heading, _ := game.pinball_next_launch(room, cell)
	start := [2]f64{f64(cell.x), f64(cell.y)}
	reach := f64(4)
	for distance := f64(0); distance <= 4; distance += 0.05 {
		p := start+heading*distance
		touches := false
		for dy in -1..=1 {
			for dx in -1..=1 {
				solid := grid.Position{x = int(math.round(p.x))+dx, y = int(math.round(p.y))+dy}
				if !game.lasso_cell_is_solid(room, solid) { continue }
				closest := [2]f64{clamp(p.x, f64(solid.x)-0.5, f64(solid.x)+0.5), clamp(p.y, f64(solid.y)-0.5, f64(solid.y)+0.5)}
				if math.hypot(p.x-closest.x, p.y-closest.y) < game.PINBALL_RADIUS { touches = true }
			}
		}
		if touches { reach = distance; break }
	}
	point :: proc(renderer: ^Renderer, start, heading: [2]f64, distance: f64) -> rl.Vector2 {
		p := start+heading*distance
		q := tactical_project(renderer, {f32(p.x)+0.5, f32(p.y)+0.5}, 0.03)
		return {q.x, q.y}
	}
	for from := f64(0.35); from < reach; from += 0.4 {
		to := min(from+0.24, reach)
		a, b := point(renderer, start, heading, from), point(renderer, start, heading, to)
		rl.DrawLineEx(a, b, 5, color_with_opacity(LIVING_TOKEN_INK, 0.8))
		rl.DrawLineEx(a, b, 3, PINBALL_AIM_HOT)
	}
	if reach < 0.5 { return }
	tip := point(renderer, start, heading, reach)
	back := point(renderer, start, heading, reach-0.3)
	side := [2]f64{-heading.y, heading.x}
	left := point(renderer, start+side*0.16, heading, reach-0.3)
	right := point(renderer, start-side*0.16, heading, reach-0.3)
	rl.DrawLineEx(back, tip, 3, PINBALL_AIM_HOT)
	rl.DrawLineEx(left, tip, 3, PINBALL_AIM_HOT)
	rl.DrawLineEx(right, tip, 3, PINBALL_AIM_HOT)
}

// --------------------------------------------------------------------------
// The HUD's chip and the hand's hints.

// The ball's chip after the bites (tactical_status_chip_layout): its seconds
// left, a whole second up, and the value the next foe takes.
@(private)
pinball_chip_text :: proc(seconds: f64, value: i32, short: bool) -> cstring {
	left := int(math.ceil(max(seconds, 0)-0.000001))
	return fmt.ctprintf("PIN %ds x%d" if short else "PINBALL %ds x%d", left, value)
}

// Whether the HUD shows the ball's chip, and its words.
@(private)
pinball_chip :: proc(room: ^game.Room, short: bool) -> (text: cstring, shown: bool) {
	if !game.tactical_pinball_active(room) { return }
	return pinball_chip_text(game.pinball_seconds_left(&room.pinball), room.pinball.value, short), true
}

// The hand's hint while the Pinball is aimed at `error`'s cell.
@(private)
pinball_aim_hint :: proc(room: ^game.Room, error: game.Card_Compile_Error) -> cstring {
	#partial switch error {
	case .Target_Too_Heavy: return "TROPPO PESANTE PER IL PINBALL"
	case .Target_Blocked: if room.pinball.active { return "UNA PALLA ALLA VOLTA" }
	}
	return ""
}
