package render

import "core:math"
import rl "vendor:raylib"
import game "../game"
import grid "../engine/grid"
import view "../engine/view"
import gfx "../engine/gfx"
import campaign "../campaign"

Tactical_Label_Layout :: struct {
	bounds: [96]rl.Rectangle,
	count: int,
	actor_bounds: [(game.MAX_ENEMIES_PER_ROOM+1)*8]rl.Rectangle,
	actor_ids: [(game.MAX_ENEMIES_PER_ROOM+1)*8]game.Entity_Ref,
	actor_count: int,
	// Each enemy's heart as placed this frame (draw_living_hearts), for the
	// tags drawn after them that keep clear of it (the Dado del Destino's die).
	hearts: [game.MAX_ENEMIES_PER_ROOM]rl.Rectangle,
	heart_ids: [game.MAX_ENEMIES_PER_ROOM]u32,
	heart_count: int,
}

// Where the heart of enemy `id` stands this frame, when it is shown.
@(private)
tactical_label_heart :: proc(layout: ^Tactical_Label_Layout, id: u32) -> (bounds: rl.Rectangle, found: bool) {
	if layout == nil { return }
	for heart_id, index in layout.heart_ids[:layout.heart_count] {
		if heart_id == id { return layout.hearts[index], true }
	}
	return
}

@(private)
tactical_label_candidate_is_clear :: proc(layout: ^Tactical_Label_Layout, candidate: rl.Rectangle) -> bool {
	for occupied in layout.bounds[:layout.count] {
		padded := rl.Rectangle{occupied.x-3, occupied.y-3, occupied.width+6, occupied.height+6}
		if rl.CheckCollisionRecs(candidate, padded) { return false }
	}
	for actor in layout.actor_bounds[:layout.actor_count] {
		padded := rl.Rectangle{actor.x-2, actor.y-2, actor.width+4, actor.height+4}
		if rl.CheckCollisionRecs(candidate, padded) { return false }
	}
	return true
}

// Names explain the enemy being inspected. Health, intent and threat tiles
// remain independent and visible for every enemy; six name banners need not
// compete with those immediate combat decisions.
@(private)
tactical_enemy_name_shown :: proc(renderer:^Renderer,room:^game.Room,enemy:game.Enemy)->bool {
	if !renderer.tactical.expedition {return true}
	if enemy.health<=0 {return false}
	if renderer.has_hovered_cell && !renderer_blocks_player_input(renderer) {
		if index,found:=game.enemy_index_at(room,renderer.hovered_cell);found {return room.enemies[index].id==enemy.id}
	}
	v:=&renderer.tactical
	return v.inspected==enemy.id && (v.pointer_window==v.inspected_mouse || renderer_blocks_player_input(renderer))
}

// Priority annotations use the closest free rectangle to their own head.
// Unlike secondary text, they do not scan distant columns before trying the
// next vertical lane. Stable owner order makes identical frames identical.
@(private)
place_tactical_label_near :: proc(layout:^Tactical_Label_Layout,anchor:view.Vec2,size:view.Vec2,viewport:rl.Rectangle)->(result:rl.Rectangle,ok:bool) {
	if size.x>viewport.width || size.y>viewport.height || layout.count>=len(layout.bounds) {return}
	preferred:=rl.Rectangle{math.round(anchor.x-size.x*.5),math.round(anchor.y-size.y),size.x,size.y}
	if preferred.x>=viewport.x && preferred.x+size.x<=viewport.x+viewport.width && preferred.y>=viewport.y && preferred.y+size.y<=viewport.y+viewport.height && tactical_label_candidate_is_clear(layout,preferred) {
		layout.bounds[layout.count]=preferred;layout.count+=1
		return preferred,true
	}
	best:=f32(1e30)
	for row in -18..=12 {for column in -16..=16 {
		candidate:=rl.Rectangle{
			clamp(math.round(anchor.x-size.x*.5+f32(column)*4),viewport.x,viewport.x+viewport.width-size.x),
			clamp(math.round(anchor.y-size.y+f32(row)*2),viewport.y,viewport.y+viewport.height-size.y),size.x,size.y}
		dx:=candidate.x+size.x*.5-anchor.x;dy:=candidate.y+size.y-anchor.y
		distance:=dx*dx+dy*dy*1.3+(size.y*size.y if dy>size.y else 0)
		if distance>=best {continue}
		end:=rl.Vector2{clamp(anchor.x,candidate.x,candidate.x+size.x),clamp(anchor.y,candidate.y,candidate.y+size.y)}
		ex,ey:=end.x-anchor.x,end.y-anchor.y
		distance_squared:=ex*ex+ey*ey
		// Reject distant candidates before scanning every body/tag. Retain
		// the original sqrt comparison in a narrow boundary band so f32
		// rounding at exactly 36 pixels cannot change an accepted position.
		if distance_squared>37*37 || distance_squared>36*36 && rl.Vector2Distance(end,{anchor.x,anchor.y})>36 {continue}
		if !tactical_label_candidate_is_clear(layout,candidate) {continue}
		result,ok,best=candidate,true,distance
	}}
	if ok {layout.bounds[layout.count]=result;layout.count+=1}
	return
}

@(private)
tactical_label_link_crosses_body :: proc(layout:^Tactical_Label_Layout,from,to:rl.Vector2,owner:game.Entity_Ref)->bool {
	for box,i in layout.actor_bounds[:layout.actor_count] {
		if layout.actor_ids[i]==owner {continue}
		lo,hi:=f32(0),f32(1)
		intersects:=true
		for axis in 0..<2 {
			start,delta:=from[axis],to[axis]-from[axis]
			minimum:=box.x if axis==0 else box.y
			maximum:=minimum+(box.width if axis==0 else box.height)
			if abs(delta)<.00001 {if start<minimum || start>maximum {intersects=false;break};continue}
			a,b:=(minimum-start)/delta,(maximum-start)/delta
			lo,hi=max(lo,min(a,b)),min(hi,max(a,b))
			if lo>hi {intersects=false;break}
		}
		if intersects {return true}
	}
	return false
}

// Pixel bounds project on the stationary paper support, not the narrower
// animated print and never the transparent padding of its atlas cell.
@(private)
tactical_opaque_quad_bounds :: proc(renderer:^Renderer,points:[4]rl.Vector3,pixels:rl.Rectangle)->rl.Rectangle {
	left,top,right,bottom:=max(f32),max(f32),-max(f32),-max(f32)
	for uv in ([4]rl.Vector2{{pixels.x,pixels.y},{pixels.x+pixels.width,pixels.y},
		{pixels.x,pixels.y+pixels.height},{pixels.x+pixels.width,pixels.y+pixels.height}}) {
		p:=points[0]+(points[3]-points[0])*(uv.x/CARTOON_CELL)+(points[1]-points[0])*(uv.y/CARTOON_CELL)
		projected:=tactical_project(renderer,{p.x,p.z},p.y)
		left,top=min(left,projected.x),min(top,projected.y)
		right,bottom=max(right,projected.x),max(bottom,projected.y)
	}
	return {left,top,right-left,bottom-top}
}

// The non-Cyber wardrobe can rise above its underlying living rig (hats,
// horns and staves). Reuse its immutable support and the same expanded edge
// as drawing/picking: reserving only the naked rig leaves that paper exposed
// to health tags. Both facings belong to the stationary support.
@(private)
tactical_costume_annotation_quad :: proc(renderer:^Renderer,key:Sprite_Key,position:view.Vec2,entity:game.Entity_Ref)->(points:[4]rl.Vector3,head:rl.Vector3,ok:bool) {
	v:=&renderer.tactical
	if !v.expedition || v.outline_mode==.Hologram || key<.Chaser || key>.Demolitionist {return}
	role:=game.Enemy_Archetype(int(key)-int(Sprite_Key.Chaser))
	support:=expedition_costume_support(v.expedition_material,campaign.Biome(v.expedition_biome),role)
	if support==nil || support.count==0 {return}
	half_width,bottom,top:=f32(0),max(f32),-max(f32)
	for &part,i in support.parts[:support.count] {for j in 0..<part.count {
		width:=EXPEDITION_COSTUME_INK_MARGIN*(.94+f32((i*7+j*11)%5)*.035)
		p:=paper_cut_vertex(&part,j,width)
		half_width=max(half_width,abs(p.x));bottom=min(bottom,max(p.y,0));top=max(top,max(p.y,0))
	}}
	scale:=f32(1.2)
	if character,found:=flipbook_character(key);found {scale=gfx.LIVING_SHEETS[character].world_height}
	at,lift:=living_card_position(renderer,entity,key,position)
	right:=flipbook_camera_right(renderer);normal:=rl.Vector3Normalize(rl.Vector3CrossProduct(right,{0,1,0}))
	base:=rl.Vector3{at.x+.5,.035+lift,at.y+.5}+normal*.061
	left,right_edge:=base-right*(half_width*scale),base+right*(half_width*scale)
	points={left+{0,top*scale,0},left+{0,bottom*scale,0},right_edge+{0,bottom*scale,0},right_edge+{0,top*scale,0}}
	return points,base+{0,top*scale,0},true
}

// One allocator for bomb labels and feedback badges (the hearts over the heads
// keep their places in it too). Small fixed storage keeps
// frame cost bounded. Prefer above the anchor, then a nearby side column.
@(private)
place_tactical_label :: proc(layout: ^Tactical_Label_Layout, anchor: view.Vec2,
	size: view.Vec2, viewport: rl.Rectangle) -> (result: rl.Rectangle, ok: bool) {
	if size.x > viewport.width || size.y > viewport.height || layout.count >= len(layout.bounds) { return }
	for row in 0..<12 {
		for column in ([5]int{0, -1, 1, -2, 2}) {
			candidate := rl.Rectangle{
				clamp(anchor.x-size.x/2+f32(column)*(size.x+5), viewport.x, viewport.x+viewport.width-size.x),
				clamp(anchor.y-size.y-f32(row)*13, viewport.y, viewport.y+viewport.height-size.y), size.x, size.y}
			if !tactical_label_candidate_is_clear(layout, candidate) { continue }
			layout.bounds[layout.count] = candidate
			layout.count += 1
			return candidate, true
		}
	}
	// Dense groups can fill every preferred lane above an actor. Search a
	// bounded wider/below neighborhood only then, retaining the nearest free
	// label center so readable health does not require crossing the whole room.
	best_distance := f32(1e30)
	for row in -11..=11 {
		for column in -4..=4 {
			candidate := rl.Rectangle{
				clamp(anchor.x-size.x/2+f32(column)*(size.x+5), viewport.x, viewport.x+viewport.width-size.x),
				clamp(anchor.y-size.y+f32(row)*13, viewport.y, viewport.y+viewport.height-size.y), size.x, size.y}
			if !tactical_label_candidate_is_clear(layout, candidate) { continue }
			dx, dy := candidate.x+size.x/2-anchor.x, candidate.y+size.y-anchor.y
			distance := dx*dx+dy*dy
			if distance >= best_distance { continue }
			result, ok, best_distance = candidate, true, distance
		}
	}
	if ok { layout.bounds[layout.count] = result; layout.count += 1 }
	return
}

// Use the drawn quad, including actor-specific height and the current cue pose.
// Body occupancy is separate from labels so a full encounter keeps its existing
// fuse/status/QTE budget. Only 3D billboards participate in this reservation.
@(private)
reserve_tactical_actor_label_bounds :: proc(renderer: ^Renderer, actor: ^Presentation_Actor) {
	v := &renderer.tactical
	if v.labels.actor_count >= len(v.labels.actor_bounds) { return }
	// Down in his shadow the player's card is no standing figure but a dark
	// hood in its pool: labels and badges may lie over it (the CRITICO of a
	// diagonal step just over the pool, a bomb's label by its cell).
	if actor.entity == game.PLAYER_ENTITY && tactical_shadow_depth(renderer, game.PLAYER_ENTITY) > 0 { return }
	// The Pinball's ball is no standing card either (pinball.odin).
	if tactical_pinball_holds(renderer, actor.entity) { return }
	// Behind his eyes there is no card of his to keep clear of.
	if actor.entity == game.PLAYER_ENTITY && first_person_hides_player(renderer) { return }
	key:=Sprite_Key.Player if actor.entity==game.PLAYER_ENTITY else sprite_key_for_enemy(actor.archetype)
	if index,cartoon:=expedition_cartoon_actor(renderer,key);cartoon && !renderer.sprite_assets.sprites[int(key)].configured {
		if quad,ready:=expedition_cartoon_geometry(renderer,key,actor.position,actor.entity);ready {
			if !actor.visible || actor.opacity<=0 {return}
			cell:=grid.Position{x=int(math.round(actor.position.x)),y=int(math.round(actor.position.y))}
			if !tactical_render_visible(renderer,cell) {return}
			for pixels in v.expedition_material.cartoon.label_bands[index] {
				if pixels.width<=0 || pixels.height<=0 {continue}
				v.labels.actor_bounds[v.labels.actor_count]=tactical_opaque_quad_bounds(renderer,quad.card_points,pixels)
				v.labels.actor_ids[v.labels.actor_count]=actor.entity
				v.labels.actor_count+=1
			}
			return
		}
	}
	bounds, ok := tactical_actor_screen_bounds(renderer, actor)
	if !ok { return }
	if costume,_,shown:=tactical_costume_annotation_quad(renderer,key,actor.position,actor.entity);shown {
		left,top,right,bottom:=bounds.x,bounds.y,bounds.x+bounds.width,bounds.y+bounds.height
		for corner in costume {
			projected:=tactical_project(renderer,{corner.x,corner.z},corner.y)
			left,top=min(left,projected.x),min(top,projected.y)
			right,bottom=max(right,projected.x),max(bottom,projected.y)
		}
		bounds={left,top,right-left,bottom-top}
	}
	v.labels.actor_bounds[v.labels.actor_count] = bounds
	v.labels.actor_ids[v.labels.actor_count] = actor.entity
	v.labels.actor_count += 1
}

// A 3D actor's drawn quad on screen; false out of sight.
@(private)
tactical_actor_screen_bounds :: proc(renderer: ^Renderer, actor: ^Presentation_Actor) -> (bounds: rl.Rectangle, ok: bool) {
	if !actor.visible || actor.opacity <= 0 { return }
	cell := grid.Position{x = int(math.round(actor.position.x)), y = int(math.round(actor.position.y))}
	if !tactical_render_visible(renderer, cell) { return }
	key := Sprite_Key.Player if actor.entity == game.PLAYER_ENTITY else sprite_key_for_enemy(actor.archetype)
	quad := tactical_billboard_geometry(renderer, key, actor.position, true, actor.entity)
	if index,cartoon:=expedition_cartoon_actor(renderer,key);cartoon && quad.cartoon {
		pixels:=renderer.tactical.expedition_material.cartoon.bounds[index]
		if pixels.width>0 && pixels.height>0 {return tactical_opaque_quad_bounds(renderer,quad.card_points,pixels),true}
	}
	point := quad.points[0]
	first := tactical_project(renderer, {point.x, point.z}, point.y)
	left, top, right, bottom := first.x, first.y, first.x, first.y
	for corner in quad.points[1:] {
		projected := tactical_project(renderer, {corner.x, corner.z}, corner.y)
		left, top = min(left, projected.x), min(top, projected.y)
		right, bottom = max(right, projected.x), max(bottom, projected.y)
	}
	return {left, top, right-left, bottom-top}, true
}

// The bomb, fuse and exit labels. (Enemy health is a paper heart over the
// head, living_heart.odin.)
@(private)
draw_tactical_label :: proc(renderer: ^Renderer, anchor: view.Vec2, first, second: cstring, color: rl.Color) {
	viewport := tactical_world_bounds(renderer)
	if !point_in_rectangle(anchor, {viewport.x-30, viewport.y-35, viewport.width+60, viewport.height+80}) { return }
	width := max(gothic_text_width(renderer, first, 11), gothic_text_width(renderer, second, 10))+12
	height := f32(17) if second == "" else f32(30)
	bounds, placed := place_tactical_label(renderer.tactical.labels, anchor, {width, height}, viewport)
	if !placed { return }
	bottom := rl.Vector2{bounds.x+bounds.width/2, bounds.y+bounds.height}
	if abs(bottom.x-anchor.x) > 4 || abs(bottom.y-anchor.y) > 8 {
		rl.DrawLineEx(bottom, to_raylib(anchor), 1, color_with_opacity(color, 0.5))
	}
	rl.DrawRectangleRec(bounds, EXPEDITION_PAPER_EDGE if renderer.tactical.expedition else GOTHIC_INK)
	if renderer.tactical.expedition {rl.DrawRectangleLinesEx(bounds,1,EXPEDITION_PAPER_INK)}
	rl.DrawRectangleRec({bounds.x, bounds.y, 2, bounds.height}, color)
	gothic_text(renderer, first, bounds.x+6, bounds.y+1, 11, hud_ink(renderer))
	if second != "" { gothic_text(renderer, second, bounds.x+6, bounds.y+14, 10, hud_ink(renderer) if renderer.tactical.expedition else color) }
}

@(private)
draw_tactical_annotations :: proc(renderer: ^Renderer, room: ^game.Room) {
	v := &renderer.tactical
	v.labels^ = {}
	reserve_tactical_actor_label_bounds(renderer, &v.snapshot.player)
	for &actor in v.snapshot.enemies[:v.snapshot.enemy_count] {
		reserve_tactical_actor_label_bounds(renderer, &actor)
	}
	if room.qte.kind != .None { v.labels.bounds[0] = {14, TACTICAL_HUD_HEIGHT+13, 237, 143}; v.labels.count = 1 }
	if v.mechanics_lab && !v.showcase {
		// The mechanics lab's banner is drawn over the board: labels keep clear
		// of it, as wide as it is drawn now. MOSTRA EFFETTO's film has the lab's
		// flag for the lab's sounds alone, and no banner.
		v.labels.bounds[v.labels.count] = mechanics_lab_banner_bounds(renderer, room)
		v.labels.count += 1
	}
	// Existing status glyphs retain their ground lane, the paper tags under
	// them included; text badges avoid it.
	for &actor in v.snapshot.enemies[:v.snapshot.enemy_count] {
		cell := grid.Position{x = int(math.round(actor.position.x)), y = int(math.round(actor.position.y))}
		// The tags go with the card the Pinball's ball takes the place of.
		if !actor.visible || actor.statuses.count == 0 || !tactical_overlay_visible(renderer, cell) ||
		   tactical_pinball_holds(renderer, actor.entity) { continue }
		p := tactical_status_anchor(renderer, &actor)
		tags := draw_status_set(renderer, &actor.statuses, p, 14, actor.opacity, tactical_status_tag_pixel(renderer, &actor))
		if v.labels.count < len(v.labels.bounds) { v.labels.bounds[v.labels.count] = tactical_status_lane(p, tags); v.labels.count += 1 }
	}
	// Behind his eyes his own tags are the HUD's chips alone.
	if v.snapshot.player.visible && v.snapshot.player.statuses.count > 0 && !first_person_hides_player(renderer) {
		player := &v.snapshot.player
		p := tactical_status_anchor(renderer, player)
		tags := draw_status_set(renderer, &player.statuses, p, 14, player.opacity, tactical_status_tag_pixel(renderer, player))
		if v.labels.count < len(v.labels.bounds) { v.labels.bounds[v.labels.count] = tactical_status_lane(p, tags); v.labels.count += 1 }
	}
	// Enemies keep their own clock: their health and intent stay on screen
	// while the player's move or cast plays, and only leave with the enemy.
	draw_living_hearts(renderer, room)
	// Bomb/fuse labels find space around the fixed health attachments.
	draw_voxel_fuse_labels(renderer, room)
	draw_advice_word(renderer, room)
	// The mechanics sandbox cleared for the rod keeps its exit shut: no USCITA.
	if tactical_exit_is_open(room, v.snapshot.phase) {
		p := room.exit_position
		draw_tactical_label(renderer, tactical_project(renderer, {f32(p.x)+0.5, f32(p.y)+0.5}, 1.3), "USCITA", "", {124, 199, 215, 255})
	}
}
