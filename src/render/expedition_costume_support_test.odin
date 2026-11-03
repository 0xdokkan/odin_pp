package render

import "core:testing"
import rl "vendor:raylib"
import campaign "../campaign"
import game "../game"

@(test)
expedition_costume_support_contains_all_authored_motion_and_is_cached :: proc(t:^testing.T) {
	m:=new(Expedition_Material)
	defer {if m.costumes!=nil {free(m.costumes)};free(m)}
	for biome in campaign.Biome {
		if biome==.Cyber || biome==.Count {continue}
		for role in game.Enemy_Archetype {
			if role==.Count {continue}
			support:=expedition_costume_support(m,biome,role)
			expect_expedition_art_safe(t,support)
			signature:=expedition_art_signature(support)
			for frame in 0..<64 {
				art:=expedition_enemy_costume_art(biome,role,f32(frame)*.173)
				testing.expect_value(t,support.count,art.count)
				for &part,i in art.parts[:art.count] {
					envelope:=&support.parts[i]
					for p in part.points[:part.count] {for a,j in envelope.points[:envelope.count] {
						b:=envelope.points[(j+1)%envelope.count]
						testing.expect(t,costume_cross(a,b,p)>=-.00001,"animated print escaped its stationary envelope")
					}}
				}
			}
			testing.expect_value(t,support,expedition_costume_support(m,biome,role))
			testing.expect_value(t,signature,expedition_art_signature(support))
		}
	}
}

@(test)
expedition_costume_picking_tracks_the_cut_and_rejects_empty_space :: proc(t:^testing.T) {
	support:=build_expedition_costume_support(.West,.Archer)
	for side in ([2]f32{-1,1}) {
		ray:=rl.Ray{position={side*.39,1.06,2},direction={0,0,-1}}
		distance,hit:=expedition_costume_support_hit(&support,ray,{}, {1,0,0},1)
		testing.expect(t,hit,"the stationary hat margin is part of the actor hit silhouette")
		testing.expect(t,abs(distance-2)<.00001,"ray/triangle contact must remain on the paper plane")
	}
	for origin in ([3]rl.Vector3{{1.5,.6,2},{0,-.1,2},{0,1.8,2}}) {
		_,hit:=expedition_costume_support_hit(&support,{position=origin,direction={0,0,-1}}, {}, {1,0,0},1)
		testing.expect(t,!hit,"costume picking must not use its enclosing rectangle or extend below the floor")
	}
}

@(test)
expedition_costume_bold_border_is_pickable_without_joining_the_feet :: proc(t:^testing.T) {
	// A pair of separated paper legs: the mirrored support must keep the
	// opening between them and stop at their soles as the border grows.
	support:Expedition_Paper
	paper_box(&support,.2,0,.2,1,EXPEDITION_PAPER_EDGE)
	for side in ([2]f32{-1,1}) {
		_,hit:=expedition_costume_support_hit(&support,{position={side*.49,.5,2},direction={0,0,-1}}, {}, {1,0,0},1)
		testing.expect(t,hit,"the expanded visible rim must participate in picking")
	}
	for point in ([3]rl.Vector3{{0,.015,2},{.3,-.001,2},{.6,.5,2}}) {
		_,hit:=expedition_costume_support_hit(&support,{position=point,direction={0,0,-1}}, {}, {1,0,0},1)
		testing.expect(t,!hit,"a heavier border must not create a base, close the leg gap, or an oversized hitbox")
	}
}
