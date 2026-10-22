package render

import "core:math"
import "core:testing"
import rl "vendor:raylib"
import campaign "../campaign"
import game "../game"
import world "../expedition"

// A CPU-only lighting fixture: no window, texture, shader, or OpenGL state.
@(private)
lighting_test_renderer :: proc() -> ^Renderer {
	r := new(Renderer)
	r.tactical.expedition = true
	r.tactical.expedition_material = new(Expedition_Material)
	r.tactical.snapshot = new(Room_Presentation)
	r.tactical.camera.target = {4, 0, 4}
	return r
}

@(private)
lighting_test_free :: proc(r: ^Renderer) {
	free(r.tactical.snapshot)
	free(r.tactical.expedition_material)
	free(r)
}

@(private)
lighting_test_at :: proc(l: ^Expedition_Lights, at: rl.Vector3) -> int {
	for p, i in l.start[:l.count] {
		if rl.Vector3Distance({p.x, p.y, p.z}, at) < .0001 { return i }
	}
	return -1
}

@(test)
test_expedition_light_gpu_reciprocals_preserve_segment_and_point_bounds :: proc(t:^testing.T) {
	l:Expedition_Lights
	a,b:=rl.Vector3{1,2,3},rl.Vector3{4,6,3}
	expedition_add_light(&l,a,b,{2,.5,.1},5)
	expedition_add_light(&l,b,b,{.1,.4,.8},3)
	expedition_add_light(&l,a,b,{1,1,1},0)
	testing.expect_value(t,l.count,2)
	for i in 0..<int(l.count) {
		start,end:=l.start[i],l.end[i];segment:=end.xyz-start.xyz
		for p in ([4]rl.Vector3{{-8,-4,2},{2,3,3},{3,4,9},{10,12,3}}) {
			reference:=start.xyz+segment*clamp(rl.Vector3DotProduct(p-start.xyz,segment)/max(rl.Vector3LengthSqr(segment),.0001),0,1)
			packed:=start.xyz+segment*clamp(rl.Vector3DotProduct(p-start.xyz,segment)*end.w,0,1)
			testing.expect(t,rl.Vector3DistanceSqr(reference,packed)<.000001)
		}
		// The exact radius is rejected by the packed shader threshold; a
		// nearby pixel remains inside. Zero-length point sources stay finite.
		testing.expect(t,abs(start.w*start.w*l.color[i].w-1)<.000001)
		testing.expect(t,(start.w-.01)*(start.w-.01)*l.color[i].w<1)
		testing.expect(t,!math.is_nan(end.w) && !math.is_inf(end.w))
	}
}

@(test)
test_expedition_lights_follow_rendered_player_and_live_objects :: proc(t: ^testing.T) {
	r := lighting_test_renderer(); defer lighting_test_free(r)
	w := new(world.World); defer free(w)
	s := r.tactical.snapshot
	s.player = {entity = game.PLAYER_ENTITY, position = {2.25, 3.5}, visible = true}
	// The free walker and encounter handover have a visual offset that the
	// light must share, rather than snapping to an integer gameplay cell.
	r.tactical.expedition_free = true
	r.tactical.expedition_player_offset = {.2, -.1}
	s.object_count = 1
	s.objects[0] = {kind = .Tesla_Coil, position = {4, 3}, visible = true}
	l := &r.tactical.expedition_material.lights
	prepare_expedition_lights(r, nil, w)
	testing.expect_value(t, l.count, 2)
	testing.expect(t, lighting_test_at(l, {2.95, .65, 3.9}) >= 0)
	testing.expect(t, lighting_test_at(l, {4.5, .65, 3.5}) >= 0)

	s.player.position = {5.75, 7.125}
	s.objects[0].position = {6, 7}
	prepare_expedition_lights(r, nil, w)
	testing.expect_value(t, l.count, 2)
	testing.expect(t, lighting_test_at(l, {6.45, .65, 7.525}) >= 0)
	testing.expect(t, lighting_test_at(l, {6.5, .65, 7.5}) >= 0)
	testing.expect_value(t, lighting_test_at(l, {4.5, .65, 3.5}), -1)
	testing.expect_value(t, w.clock, f32(0))
	testing.expect_value(t, s.objects[0].position.x, f32(6))

	s.player.visible = false
	s.objects[0].visible = false
	prepare_expedition_lights(r, nil, w)
	testing.expect_value(t, l.count, 0)
}

@(test)
test_expedition_lights_filter_sources_and_keep_hdr_pulse_bounded :: proc(t: ^testing.T) {
	r := lighting_test_renderer(); defer lighting_test_free(r)
	w := new(world.World); defer free(w)
	s := r.tactical.snapshot
	kinds := [?]game.Grid_Object_Kind{.Tesla_Coil, .Shock_Floor, .Fire, .Bomb, .Bomb_Marley, .Black_Hole}
	for kind, i in kinds { s.objects[i] = {kind = kind, position = {f32(i), 3}, visible = true} }
	s.objects[6] = {kind = .Barrel, position = {4, 5}, visible = true}
	s.objects[7] = {kind = .Fire, position = {4, 6}, visible = false}
	s.objects[8] = {kind = .Tesla_Coil, position = {40, 40}, visible = true}
	s.object_count = 9
	l := &r.tactical.expedition_material.lights
	for clock in ([4]f32{0, .3, 17.5, 10000}) {
		w.clock = clock
		prepare_expedition_lights(r, nil, w)
		testing.expect_value(t, l.count, len(kinds))
		for _, i in kinds {
			index := lighting_test_at(l, {f32(i)+.5, .65, 3.5})
			testing.expect(t, index >= 0)
			if index < 0 { continue }
			color := l.color[index]
			testing.expect(t, max(color.x, max(color.y, color.z)) > 1)
			for component in color { testing.expect(t, !math.is_nan(component) && !math.is_inf(component) && component >= 0 && component <= 3.5) }
			testing.expect_value(t, l.start[index].w, f32(4))
			testing.expect(t, l.end[index].xyz == l.start[index].xyz)
		}
		testing.expect_value(t, lighting_test_at(l, {4.5, .65, 5.5}), -1)
		testing.expect_value(t, lighting_test_at(l, {4.5, .65, 6.5}), -1)
		testing.expect_value(t, lighting_test_at(l, {40.5, .65, 40.5}), -1)
		testing.expect_value(t, w.clock, clock)
	}
}

@(test)
test_expedition_ground_fire_light_moves_and_expires_without_ghosts :: proc(t: ^testing.T) {
	r := lighting_test_renderer(); defer lighting_test_free(r)
	w := new(world.World); defer free(w)
	s := r.tactical.snapshot
	s.ground.fire_count = 2
	s.ground.fires[0] = {id = 7, center = {3, 4}, stage = 3, burn = 2}
	s.ground.fires[1] = {id = 8, center = {50, 50}, stage = 1, burn = 1}
	l := &r.tactical.expedition_material.lights
	prepare_expedition_lights(r, nil, w)
	testing.expect_value(t, l.count, 1)
	testing.expect_value(t, lighting_test_at(l, {3.5, .45, 4.5}), 0)
	testing.expect(t, l.color[0].x > l.color[0].y && l.color[0].y > l.color[0].z)
	testing.expect_value(t, l.start[0].w, f32(4.5))
	s.ground.fires[0].center = {6, 2}
	prepare_expedition_lights(r, nil, w)
	testing.expect_value(t, lighting_test_at(l, {6.5, .45, 2.5}), 0)
	testing.expect_value(t, lighting_test_at(l, {3.5, .45, 4.5}), -1)
	// Expiration changes the active count; stale backing-array contents must
	// never leave a floating light in the next frame.
	s.ground.fire_count = 0
	prepare_expedition_lights(r, nil, w)
	testing.expect_value(t, l.count, 0)
}

@(test)
test_expedition_lights_keep_actual_edge_segments_and_reserve_live_slots :: proc(t: ^testing.T) {
	r := lighting_test_renderer(); defer lighting_test_free(r)
	w := new(world.World); defer free(w)
	m := r.tactical.expedition_material
	s := r.tactical.snapshot
	for i := 40; i > 0; i -= 1 {
		x := f32(i)*.1
		expedition_collect_edge(&m.edges, {x, 1, 0}, {x, 2, 0}, {80, 200, 255, 255})
	}
	testing.expect_value(t, m.edges.emitter_count, 32)
	s.player = {entity = game.PLAYER_ENTITY, position = {4, 4}, visible = true}
	s.object_count = 20
	for i in 0..<s.object_count { s.objects[i] = {kind = .Fire, position = {f32(i%8), f32(i/8)+5}, visible = true} }
	s.ground.fire_count = game.MAX_GROUND_FIRES
	for &fire, i in s.ground.fires { fire = {id = u32(i+1), center = {i%8, i/8}} }
	prepare_expedition_lights(r, nil, w)
	l := &m.lights
	testing.expect_value(t, l.count, EXPEDITION_LIGHTS)
	// Static lighting uses the actual nearest architectural segment and
	// its linear HDR radiance, not a replacement point or guessed palette.
	for emitter, i in m.edges.emitters[:24] {
		testing.expect_value(t, l.start[i].xyz, emitter.a)
		testing.expect_value(t, l.end[i].xyz, emitter.b)
		testing.expect_value(t, l.color[i].xyz, emitter.radiance)
		testing.expect(t, l.start[i].w > 0 && l.color[i].z > 1)
	}
	testing.expect(t, lighting_test_at(l, {4.5, .65, 4.5}) >= 24)
	testing.expect(t, l.count > 25)
	// A fresh frame must release all dynamic slots when their sources go.
	s.player.visible = false; s.object_count = 0; s.ground.fire_count = 0
	prepare_expedition_lights(r, nil, w)
	testing.expect_value(t, l.count, 24)
	m.edges.emitter_count = 0
	prepare_expedition_lights(r, nil, w)
	testing.expect_value(t, l.count, 0)
}

@(test)
test_expedition_dynamic_light_budget_retains_nearest_fire_and_devices :: proc(t: ^testing.T) {
	r := lighting_test_renderer(); defer lighting_test_free(r)
	w := new(world.World); defer free(w)
	m := r.tactical.expedition_material
	s := r.tactical.snapshot
	r.tactical.camera.target = {}
	for i in 0..<24 { expedition_collect_edge(&m.edges, {f32(i)+20, 1, 0}, {f32(i)+20, 2, 0}, {80, 200, 255, 255}) }
	s.player = {entity = game.PLAYER_ENTITY, position = {0, 0}, visible = true}
	s.object_count = 12
	for i in 0..<s.object_count { s.objects[i] = {kind = .Tesla_Coil, position = {f32(14-i), 0}, visible = true} }
	s.ground.fire_count = 3
	for i in 0..<3 { s.ground.fires[i] = {id = u32(i+1), center = {i, 0}} }
	prepare_expedition_lights(r, nil, w)
	l := &m.lights
	testing.expect_value(t, l.count, EXPEDITION_LIGHTS)
	// Ground fires are gathered after objects, but these three close fires
	// must displace farther objects from the seven contested dynamic slots.
	for i in 0..<3 { testing.expect(t, lighting_test_at(l, {f32(i)+.5, .45, .5}) >= 25) }
	for i in 3..<7 { testing.expect(t, lighting_test_at(l, {f32(i)+.5, .65, .5}) >= 25) }
	testing.expect_value(t, lighting_test_at(l, {14.5, .65, .5}), -1)
	for i in 26..<EXPEDITION_LIGHTS {
		testing.expect(t, rl.Vector3LengthSqr(l.start[i-1].xyz) <= rl.Vector3LengthSqr(l.start[i].xyz))
	}
	before := l^
	for i in 0..<s.object_count/2 { j := s.object_count-1-i; s.objects[i], s.objects[j] = s.objects[j], s.objects[i] }
	prepare_expedition_lights(r, nil, w)
	testing.expect_value(t, l^, before)
	// Moving the view selects nearby active lights again, without moving a
	// source or changing any gameplay state to make the shader look right.
	r.tactical.camera.target = {14, 0, 0}
	prepare_expedition_lights(r, nil, w)
	testing.expect(t, lighting_test_at(l, {14.5, .65, .5}) >= 25)
	testing.expect_value(t, lighting_test_at(l, {.5, .45, .5}), -1)
	testing.expect_value(t, s.ground.fires[0].center.x, 0)
	for emitter, i in m.edges.emitters[:24] { testing.expect_value(t, l.start[i].xyz, emitter.a) }
}

@(test)
test_expedition_lights_clear_stale_snapshot_and_allow_uninitialized_material :: proc(t: ^testing.T) {
	r := lighting_test_renderer(); defer lighting_test_free(r)
	w := new(world.World); defer free(w)
	m := r.tactical.expedition_material
	expedition_collect_edge(&m.edges, {1, 2, 3}, {4, 5, 6}, {255, 180, 80, 255})
	s := r.tactical.snapshot
	s.player.visible = true
	prepare_expedition_lights(r, nil, w)
	testing.expect_value(t, m.lights.count, 2)
	r.tactical.snapshot = nil
	prepare_expedition_lights(r, nil, w)
	testing.expect_value(t, m.lights.count, 1)
	testing.expect_value(t, m.lights.end[0].xyz, (rl.Vector3{4, 5, 6}))
	r.tactical.snapshot = s
	r.tactical.expedition_material = nil
	prepare_expedition_lights(r, nil, w)
	r.tactical.expedition_material = m
}

@(test)
test_expedition_surface_profiles_are_finite_and_materially_distinct :: proc(t: ^testing.T) {
	profiles: [campaign.Biome]Expedition_Surface_Profile
	for biome in campaign.Biome {
		p := expedition_biome_surface(biome)
		profiles[biome] = p
		for value in ([3]f32{p.roughness, p.reflection, p.exposure}) { testing.expect(t, !math.is_nan(value) && !math.is_inf(value)) }
		testing.expect(t, p.roughness > 0 && p.roughness <= 1)
		testing.expect(t, p.reflection >= 0 && p.reflection <= 1)
		testing.expect(t, p.exposure >= .5 && p.exposure <= 2)
	}
	// Sand/vegetation should not resolve as the same mirror as ice or the
	// secret polished surface; this protects visible artistic distinctions.
	testing.expect(t, profiles[.West].roughness-profiles[.Snow].roughness > .25)
	testing.expect(t, profiles[.Jungle].roughness-profiles[.City].roughness > .15)
	testing.expect(t, profiles[.Snow].reflection-profiles[.West].reflection > .25)
	testing.expect(t, profiles[.Secret].roughness < profiles[.Cyber].roughness)
	testing.expect(t, profiles[.Secret].reflection > profiles[.Cyber].reflection)
}

@(test)
test_expedition_light_tiles_conservatively_cover_segment_capsules :: proc(t:^testing.T) {
	l:Expedition_Lights
	// Include long diagonal segments, vertical segments, points, negative
	// coordinates and lights extending beyond the finite tiling window.
	for i in 0..<EXPEDITION_LIGHTS {
		a:=rl.Vector3{f32((i*17)%97)-48,f32(i%7)-3,f32((i*29)%101)-50}
		b:=a+rl.Vector3{f32((i*11)%41)-20,f32(i%5)-2,f32((i*7)%37)-18}
		if i%4==0 {b=a}
		if i%4==1 {b={a.x,a.y+9,a.z}}
		expedition_add_light(&l,a,b,{1,2,3},f32(i%9)+.25)
	}
	starts,ends,colors,count:=l.start,l.end,l.color,l.count
	directions:=[?]rl.Vector3{{1,0,0},{-1,0,0},{0,1,0},{0,-1,0},{0,0,1},{0,0,-1},
		{1,1,1},{-1,1,1},{1,-1,1},{1,1,-1},{-1,-1,1},{-1,1,-1},{1,-1,-1},{-1,-1,-1}}
	checked,inside,outside:int
	for focus in ([5]rl.Vector3{{},{-.001,0,-.001},{31.999,0,-24},{-48,12,48},{160,-8,192}}) {
		expedition_build_light_tiles(&l,focus)
		for i in 0..<int(l.count) {
			a,b:=l.start[i],l.end[i];segment:=b.xyz-a.xyz
			for step in 0..=8 {
				center:=a.xyz+segment*(f32(step)/8)
				for d in directions {for shell in ([3]f32{0,.5,.9999}) {
					p:=center+rl.Vector3Normalize(d)*(a.w*shell)
					// Independent closest-point oracle: every positive capsule
					// contribution must survive tiling, at every sampled height.
					nearest:=a.xyz+segment*clamp(rl.Vector3DotProduct(p-a.xyz,segment)/max(rl.Vector3LengthSqr(segment),.0001),0,1)
					if rl.Vector3DistanceSqr(p,nearest)>=a.w*a.w {continue}
					mask:=expedition_light_mask_at(&l,p)
					testing.expect(t,mask&(u32(1)<<u32(i))!=0)
					checked+=1
					if p.x>=l.tile_origin.x && p.x<l.tile_origin.x+64 && p.z>=l.tile_origin.y && p.z<l.tile_origin.y+64 {inside+=1}
					else {outside+=1;testing.expect_value(t,mask,u32(0xffffffff))}
				}}
			}
		}
	}
	testing.expect(t,checked>50000 && inside>10000 && outside>10000)
	// Tiling is presentation data: source positions, radiance, reciprocal
	// radius and light ordering must be byte-for-byte unchanged.
	testing.expect_value(t,l.start,starts);testing.expect_value(t,l.end,ends)
	testing.expect_value(t,l.color,colors);testing.expect_value(t,l.count,count)
}

@(test)
test_expedition_light_tiles_preserve_slot31_and_signed_upload_bits :: proc(t:^testing.T) {
	l:Expedition_Lights
	for i in 0..<31 {p:=rl.Vector3{1000+f32(i),1,1000};expedition_add_light(&l,p,p,{1,1,1},1)}
	p:=rl.Vector3{-8,2,-16};expedition_add_light(&l,p,p,{1,2,3},2)
	expedition_build_light_tiles(&l,{-8,0,-16})
	mask:=expedition_light_mask_at(&l,p)
	testing.expect_value(t,mask,u32(0x80000000))
	signed_tiles:int
	for packed in l.tiles {
		if packed==0 {continue}
		testing.expect(t,packed<0)
		testing.expect_value(t,u32(packed),u32(0x80000000))
		signed_tiles+=1
	}
	testing.expect_value(t,signed_tiles,4)
	testing.expect_value(t,expedition_light_mask_at(&l,{p.x+48,p.y,p.z}),u32(0xffffffff))
	// A mask with every bit set is also signed -1, not an empty mask.
	for i in 0..<31 {l.start[i]=l.start[31];l.end[i]=l.end[31]}
	expedition_build_light_tiles(&l,p)
	testing.expect_value(t,expedition_light_mask_at(&l,p),u32(0xffffffff))
}

@(test)
test_expedition_light_tiles_negative_alignment_boundaries_and_fallback :: proc(t:^testing.T) {
	l:Expedition_Lights
	expedition_build_light_tiles(&l,{-.001,0,8})
	testing.expect_value(t,l.tile_origin,(rl.Vector2{-40,-24}))
	// Lower edges belong to the grid; upper edges and the immediately
	// preceding lower coordinates must take the unrestricted fallback.
	for p in ([4]rl.Vector3{{-40,0,-24},{23.999,0,39.999},{-40,100,39.999},{23.999,-100,-24}}) {
		testing.expect_value(t,expedition_light_mask_at(&l,p),u32(0))
	}
	for p in ([6]rl.Vector3{{-40.001,0,0},{24,0,0},{0,0,-24.001},{0,0,40},{-10000,0,-10000},{10000,0,10000}}) {
		testing.expect_value(t,expedition_light_mask_at(&l,p),u32(0xffffffff))
	}
	// Radius8 touches both neighboring tile boundaries exactly. Padding
	// keeps the touching tile on either side, including negative positions.
	a:=rl.Vector3{-8,4,0};expedition_add_light(&l,a,a,{1,1,1},8)
	expedition_build_light_tiles(&l,{-.001,0,8})
	for p in ([8]rl.Vector3{{-16.001,0,0},{-16,0,0},{-.001,0,0},{0,0,0},
		{-8,0,-8.001},{-8,0,-8},{-8,0,7.999},{-8,0,8}}) {
		testing.expect_value(t,expedition_light_mask_at(&l,p),u32(1))
	}
	testing.expect_value(t,expedition_light_mask_at(&l,{16,0,24}),u32(0))
}

@(test)
test_expedition_light_tiles_match_closed_aabb_overlap_and_recenter :: proc(t:^testing.T) {
	l:Expedition_Lights
	expedition_add_light(&l,{-27,4,-15},{18,-2,13},{1,1,1},3)
	expedition_add_light(&l,{31,8,8},{31,8,8},{1,1,1},2)
	expedition_add_light(&l,{-100,0,100},{-90,0,120},{1,1,1},8)
	for focus in ([5]rl.Vector3{{},{7.999,0,7.999},{8,0,8},{-8.001,0,-8.001},{72,0,72}}) {
		expedition_build_light_tiles(&l,focus)
		for z in 0..<EXPEDITION_LIGHT_TILE_SIDE {for x in 0..<EXPEDITION_LIGHT_TILE_SIDE {
			lo:=l.tile_origin+rl.Vector2{f32(x)*8,f32(z)*8};hi:=lo+rl.Vector2{8,8}
			expected:u32
			for i in 0..<int(l.count) {
				a,b:=l.start[i],l.end[i];r:=a.w+.001
				if min(a.x,b.x)-r<=hi.x && max(a.x,b.x)+r>=lo.x && min(a.z,b.z)-r<=hi.y && max(a.z,b.z)+r>=lo.y {expected|=u32(1)<<u32(i)}
			}
			testing.expect_value(t,u32(l.tiles[z*EXPEDITION_LIGHT_TILE_SIDE+x]),expected)
		}}
	}
	// Reuse must clear all prior source bits, even if the camera is fixed.
	l.count=0;expedition_build_light_tiles(&l,{})
	for packed in l.tiles {testing.expect_value(t,packed,0)}
}

@(test)
test_expedition_light_tiles_prepare_after_dynamic_sort_and_clear_stale_bits :: proc(t:^testing.T) {
	when !EXPEDITION_TILED_LIGHTS {return}
	r:=lighting_test_renderer();defer lighting_test_free(r)
	w:=new(world.World);defer free(w)
	m:=r.tactical.expedition_material;s:=r.tactical.snapshot;l:=&m.lights
	for i in 0..<24 {expedition_collect_edge(&m.edges,{f32(i)-12,1,-8},{f32(i)-12,3,-8},{80,200,255,255})}
	s.object_count=10
	for i in 0..<s.object_count {s.objects[i]={kind=.Tesla_Coil,position={f32(10-i),2},visible=true}}
	s.ground.fire_count=2
	s.ground.fires[0]={id=1,center={0,0}};s.ground.fires[1]={id=2,center={1,0}}
	prepare_expedition_lights(r,nil,w)
	testing.expect_value(t,l.count,EXPEDITION_LIGHTS)
	for i in 0..<int(l.count) {
		bit:=u32(1)<<u32(i)
		testing.expect(t,expedition_light_mask_at(l,l.start[i].xyz)&bit!=0)
		testing.expect(t,expedition_light_mask_at(l,l.end[i].xyz)&bit!=0)
	}
	// A nil snapshot still prepares static masks, and removes every old
	// dynamic bit. An empty next frame clears the backing array as well.
	r.tactical.snapshot=nil
	prepare_expedition_lights(r,nil,w)
	testing.expect_value(t,l.count,24)
	for packed in l.tiles {testing.expect_value(t,u32(packed)&0xff000000,u32(0))}
	m.edges.emitter_count=0;prepare_expedition_lights(r,nil,w)
	for packed in l.tiles {testing.expect_value(t,packed,0)}
	r.tactical.snapshot=s
}
