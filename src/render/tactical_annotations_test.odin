package render

import "core:testing"
import "core:math"
import rl "vendor:raylib"
import game "../game"
import view "../engine/view"
import gfx "../engine/gfx"
import campaign "../campaign"

@(test)
test_west_health_tags_reserve_the_hat_above_the_living_rig :: proc(t:^testing.T) {
	r:=new(Renderer);defer free(r)
	r.canvas_width=960;r.canvas_height=540
	r.tactical.expedition=true;r.tactical.expedition_biome=u8(campaign.Biome.West)
	r.tactical.no_fog=true;r.tactical.perspective=true
	r.tactical.living=true;r.tactical.flipbook.loaded=true;r.tactical.living_assets.loaded=true
	r.tactical.expedition_material=new(Expedition_Material)
	defer {free(r.tactical.expedition_material.costumes);free(r.tactical.expedition_material)}
	for yaw in ([4]f32{.2,.8,1.5,2.5}) {
		r.tactical.camera=tactical_orbit_camera({yaw=yaw,pitch=.65,distance=15},{.5,.8,.5},true)
		for role in game.Enemy_Archetype {if role!=.Count {
			key:=sprite_key_for_enemy(role);character,_:=flipbook_character(key)
			actor:=Presentation_Actor{entity=game.enemy_entity(u32(role)+1),archetype=role,visible=true,opacity=1,position={0,0}}
			costume,head,found:=tactical_costume_annotation_quad(r,key,actor.position,actor.entity)
			testing.expect(t,found)
			testing.expect(t,head.y>gfx.LIVING_SHEETS[character].world_height*1.3,"The ink-edged West hat must move HP above the uncostumed head")
			layout:Tactical_Label_Layout;r.tactical.labels=&layout
			reserve_tactical_actor_label_bounds(r,&actor)
			testing.expect_value(t,layout.actor_count,1)
			bounds:=layout.actor_bounds[0]
			for corner in costume {
				p:=tactical_project(r,{corner.x,corner.z},corner.y)
				testing.expect(t,p.x>=bounds.x-.001 && p.x<=bounds.x+bounds.width+.001 && p.y>=bounds.y-.001 && p.y<=bounds.y+bounds.height+.001,"Wardrobe paper must participate in annotation occupancy")
			}
			anchor:=tactical_project(r,{head.x,head.z},head.y+.06)
			tag,placed:=place_tactical_label_near(&layout,anchor,{29,14},{12,64,936,308})
			testing.expect(t,placed && !rl.CheckCollisionRecs(tag,bounds),"Exact HP and intent must clear every West role's hat")
		}}
	}
	r.tactical.expedition=false
	_,_,found:=tactical_costume_annotation_quad(r,.Archer,{},game.enemy_entity(1))
	testing.expect(t,!found,"Other game modes must retain their original health anchors")
}

@(test)
test_expedition_health_tags_clear_clustered_actors_and_remain_near_their_owners :: proc(t:^testing.T) {
	viewport:=rl.Rectangle{12,64,936,308}
	// The actual six role masks at the crowded Cyber capture's head anchors,
	// including the low crab and the archer directly behind it. Full atlas
	// rectangles previously pushed these HP tags above the boss/below feet.
	heads:=[6]view.Vec2{{386,203},{400,230},{460,260},{535,254},{575,208},{496,130}}
	bands:[7][CARTOON_LABEL_BANDS]rl.Rectangle
	opaque:[7]rl.Rectangle
	for actor in 0..<7 {
		mask:=cartoon_paper_mask(actor)
		for value,i in mask {if value>0 {
			x,y:=i%CARTOON_CELL,i/CARTOON_CELL
			cartoon_include_pixel(&opaque[actor],x,y)
			cartoon_include_pixel(&bands[actor][y*CARTOON_LABEL_BANDS/CARTOON_CELL],x,y)
		}}
	}
	first:[6]rl.Rectangle
	for repeat in 0..<2 {
		layout:Tactical_Label_Layout
		for actor in 0..<7 {
			head:=view.Vec2{480,191} if actor==0 else heads[actor-1]
			for band in bands[actor] {if band.width>0 {
				layout.actor_bounds[layout.actor_count]={head.x+(band.x-CARTOON_CELL*.5)*.75,head.y+3+(band.y-opaque[actor].y)*.55,band.width*.75,band.height*.55}
				layout.actor_ids[layout.actor_count]=game.PLAYER_ENTITY if actor==0 else game.enemy_entity(u32(actor))
				layout.actor_count+=1
			}}
		}
		for head,index in heads {
			w,h:=living_heart_size(living_heart_compact_text(20,20),true,true)
			reference:=layout
			expected,expected_found:=reference_place_tactical_label_near(&reference,head,{f32(w),f32(h)},viewport)
			bounds,found:=place_tactical_label_near(&layout,head,{f32(w),f32(h)},viewport)
			testing.expect_value(t,found,expected_found);testing.expect_value(t,bounds,expected)
			testing.expectf(t,found,"HP/intent for role %d must fit the real-mask combat group",index)
			if !found {continue}
			for actor in layout.actor_bounds[:layout.actor_count] {testing.expect(t,!rl.CheckCollisionRecs(bounds,actor),"A health tag must not cover any character")}
			for prior in layout.bounds[:layout.count-1] {testing.expect(t,!rl.CheckCollisionRecs(bounds,prior),"HP tags cannot overlap one another")}
			end:=rl.Vector2{clamp(head.x,bounds.x,bounds.x+bounds.width),clamp(head.y,bounds.y,bounds.y+bounds.height)}
			testing.expect(t,rl.Vector2Distance(end,{head.x,head.y})<=36,"No HP tag may drift to a distant lane")
			testing.expect(t,bounds.y+bounds.height-head.y<=24,"HP must remain near a head, never migrate under its feet")
			if repeat==0 {first[index]=bounds} else {testing.expect_value(t,bounds,first[index])}
		}
	}
}

// Frozen exhaustive search from before the collision-scan optimization.
// Tests use its original distance calculation and visit every candidate's
// occupancy first, independently of the optimized early rejections.
@(private)
reference_place_tactical_label_near :: proc(layout:^Tactical_Label_Layout,anchor:view.Vec2,size:view.Vec2,viewport:rl.Rectangle)->(result:rl.Rectangle,ok:bool) {
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
		if !tactical_label_candidate_is_clear(layout,candidate) {continue}
		end:=rl.Vector2{clamp(anchor.x,candidate.x,candidate.x+size.x),clamp(anchor.y,candidate.y,candidate.y+size.y)}
		if rl.Vector2Distance(end,{anchor.x,anchor.y})>36 {continue}
		dx:=candidate.x+size.x*.5-anchor.x;dy:=candidate.y+size.y-anchor.y
		distance:=dx*dx+dy*dy*1.3+(size.y*size.y if dy>size.y else 0)
		if distance>=best {continue}
		result,ok,best=candidate,true,distance
	}}
	if ok {layout.bounds[layout.count]=result;layout.count+=1}
	return
}

@(test)
test_health_tag_search_optimization_preserves_exhaustive_results :: proc(t:^testing.T) {
	seed:=u32(0x91ed2a73)
	next :: proc(seed:^u32)->f32 {seed^=seed^*1664525+1013904223;return f32(seed^%4096)/4096}
	viewports:=[4]rl.Rectangle{{12,64,936,308},{12,64,696,308},{12.25,64.5,936,308},{12,64,48,48}}
	for scene in 0..<64 {
		viewport:=viewports[scene%4]
		layout:Tactical_Label_Layout
		center:=view.Vec2{viewport.x+viewport.width*.5,viewport.y+viewport.height*.5}
		layout.actor_count=scene%5*16
		for &box in layout.actor_bounds[:layout.actor_count] {
			box={center.x+(next(&seed)-.5)*160,center.y+(next(&seed)-.5)*100,8+next(&seed)*42,8+next(&seed)*32}
		}
		layout.count=scene%4*3
		for &box in layout.bounds[:layout.count] {
			box={center.x+(next(&seed)-.5)*120,center.y+(next(&seed)-.5)*80,29,14}
		}
		if scene==62 {layout.count=len(layout.bounds)}
		if scene==63 {layout.actor_count=len(layout.actor_bounds);for &box in layout.actor_bounds {box=viewport}}
		reference:=layout
		for request in 0..<6 {
			anchor:=center+view.Vec2{(next(&seed)-.5)*160,(next(&seed)-.5)*100}
			if request==4 {anchor={viewport.x,viewport.y}}
			if request==5 {anchor={viewport.x+viewport.width,viewport.y+viewport.height}}
			size:=view.Vec2{29,14}*(2 if scene%3==0 else 1)
			expected,expected_ok:=reference_place_tactical_label_near(&reference,anchor,size,viewport)
			actual,actual_ok:=place_tactical_label_near(&layout,anchor,size,viewport)
			testing.expect_value(t,actual_ok,expected_ok);testing.expect_value(t,actual,expected)
			testing.expect_value(t,layout,reference)
		}
	}
}

@(test)
test_expedition_annotation_projection_ignores_padding_and_leaders_avoid_other_figures :: proc(t:^testing.T) {
	r:=new(Renderer);defer free(r)
	r.canvas_width=960;r.canvas_height=540
	r.tactical.camera={position={0,0,10},target={0,0,0},up={0,1,0},fovy=10,projection=.ORTHOGRAPHIC}
	points:=[4]rl.Vector3{{-1,2,0},{-1,0,0},{1,0,0},{1,2,0}}
	full:=tactical_opaque_quad_bounds(r,points,{0,0,CARTOON_CELL,CARTOON_CELL})
	crab:=tactical_opaque_quad_bounds(r,points,{20,65,64,37})
	testing.expect(t,crab.height<full.height*.4 && crab.y>full.y+full.height*.6,"The low crab must not reserve the air above it")
	layout:=Tactical_Label_Layout{actor_count=2}
	layout.actor_ids[0]=game.enemy_entity(1);layout.actor_bounds[0]={20,20,20,30}
	layout.actor_ids[1]=game.enemy_entity(2);layout.actor_bounds[1]={55,20,20,30}
	testing.expect(t,tactical_label_link_crosses_body(&layout,{30,30},{90,30},game.enemy_entity(1)))
	testing.expect(t,!tactical_label_link_crosses_body(&layout,{30,15},{90,15},game.enemy_entity(1)))
	testing.expect(t,!tactical_label_link_crosses_body(&layout,{30,30},{5,30},game.enemy_entity(1)),"The short attachment can leave its own head")
}

@(test)
test_tactical_labels_pack_shared_anchor_without_overlap_or_leaving_viewport :: proc(t: ^testing.T) {
	viewport := rl.Rectangle{20, 80, 600, 240}
	for anchor in ([3]view.Vec2{{320, 260}, {20, 320}, {620, 320}}) {
		layout: Tactical_Label_Layout
		for _ in 0..<6 {
			bounds, placed := place_tactical_label(&layout, anchor, {90, 30}, viewport)
			testing.expect(t, placed, "six clustered health/intent/fuse labels must fit")
			if !placed { continue }
			testing.expect(t, bounds.x >= viewport.x && bounds.y >= viewport.y)
			testing.expect(t, bounds.x+bounds.width <= viewport.x+viewport.width)
			testing.expect(t, bounds.y+bounds.height <= viewport.y+viewport.height)
			for previous in layout.bounds[:layout.count-1] {
				testing.expect(t, !rl.CheckCollisionRecs(bounds, previous))
			}
		}
		testing.expect_value(t, layout.count, 6)
	}
}

@(test)
test_tactical_label_capacity_and_full_viewport_fail_without_overwriting :: proc(t: ^testing.T) {
	layout: Tactical_Label_Layout
	viewport := rl.Rectangle{0, 0, 120, 80}
	_, placed := place_tactical_label(&layout, {60, 80}, {120, 80}, viewport)
	testing.expect(t, placed)
	before := layout
	_, placed = place_tactical_label(&layout, {60, 80}, {20, 15}, viewport)
	testing.expect(t, !placed)
	testing.expect_value(t, layout, before)
	_, placed = place_tactical_label(&layout, {60, 80}, {121, 15}, viewport)
	testing.expect(t, !placed)
	testing.expect_value(t, layout, before)
	// Occupancy storage also has a hard cap independent of free screen space.
	layout.count = len(layout.bounds)
	before = layout
	_, placed = place_tactical_label(&layout, {2000, 2000}, {20, 15}, {0, 0, 4000, 4000})
	testing.expect(t, !placed)
	testing.expect_value(t, layout, before)
}

@(test)
test_tactical_label_clamped_at_top_avoids_its_actor_and_adjacent_actor :: proc(t: ^testing.T) {
	// A tall archer reaches above the world viewport. Its intended label is
	// clamped down onto its head unless bodies participate in label placement.
	viewport := rl.Rectangle{12, 116, 600, 300}
	layout := Tactical_Label_Layout{actor_count = 2}
	layout.actor_bounds[0] = {278, 105, 64, 94}
	layout.actor_bounds[1] = {205, 119, 66, 102}
	bounds, placed := place_tactical_label(&layout, {310, 103}, {70, 34}, viewport)
	testing.expect(t, placed, "an adjacent free lane exists for the clamped health/intent label")
	testing.expect(t, bounds.y >= viewport.y)
	for actor in layout.actor_bounds[:layout.actor_count] {
		testing.expect(t, !rl.CheckCollisionRecs(bounds, actor), "clamping must never place health text over a character")
	}
	testing.expect_value(t, layout.actor_count, 2)
	testing.expect(t, layout.count == 1, "actor reservations must not consume the 96 label slots")
}

@(test)
test_tactical_crowded_front_actor_retains_label_using_a_free_lower_lane :: proc(t: ^testing.T) {
	viewport := rl.Rectangle{12, 116, 600, 240}
	layout := Tactical_Label_Layout{actor_count = 6}
	// A projected group behind the front actor occupies every old +/-2
	// column above its anchor, while free space remains below and beside it.
	for index in 0..<5 { layout.actor_bounds[index] = {120+f32(index)*76, 116, 74, 180} }
	layout.actor_bounds[5] = {278, 288, 64, 60}
	bounds, placed := place_tactical_label(&layout, {310, 280}, {70, 34}, viewport)
	testing.expect(t, placed, "a crowded front actor must retain health/intent when a nearby lower lane is free")
	if !placed { return }
	for actor in layout.actor_bounds[:layout.actor_count] { testing.expect(t, !rl.CheckCollisionRecs(bounds, actor)) }
	testing.expect(t, bounds.y > 296, "prefer the nearby lower lane to a far lateral label")
	testing.expect(t, bounds.x >= viewport.x && bounds.x+bounds.width <= viewport.x+viewport.width)
	testing.expect(t, bounds.y >= viewport.y && bounds.y+bounds.height <= viewport.y+viewport.height)
	testing.expect_value(t, layout.count, 1)
}
