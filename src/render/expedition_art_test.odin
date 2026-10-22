package render

import "core:testing"
import "core:math"
import campaign "../campaign"
import game "../game"
import gfx "../engine/gfx"

@(private)
expedition_art_signature :: proc(m:^Expedition_Paper)->u64 {
	h:u64=1469598103934665603
	for part in m.parts[:m.count] {
		h=(h~u64(part.count))*1099511628211
		h=(h~u64(part.color.r)~(u64(part.color.g)<<8)~(u64(part.color.b)<<16)~(u64(part.color.a)<<24))*1099511628211
		for i in 0..<part.count {p:=part.points[i];h=(h~u64(i64(math.round(p.x*10000))+100000))*1099511628211;h=(h~u64(i64(math.round(p.y*10000))+100000))*1099511628211}
	}
	return h
}

@(private)
expect_expedition_art_safe :: proc(t:^testing.T,m:^Expedition_Paper) {
	testing.expect(t,m.count>0 && m.count<EXPEDITION_PAPER_PARTS)
	for &part in m.parts[:m.count] {
		testing.expect(t,part.count>=3 && part.count<=len(part.points))
		area:f32
		for p,i in part.points[:part.count] {
			testing.expect(t,p.x==p.x && p.y==p.y && abs(p.x)<2.5 && p.y>-.25 && p.y<2)
			n:=part.points[(i+1)%part.count];area+=p.x*n.y-p.y*n.x
		}
		testing.expect(t,abs(area)>.00001)
	}
}

@(test)
test_expedition_mounts_have_unique_bounded_animated_silhouettes :: proc(t:^testing.T) {
	signatures:[13]u64;count:=0
	for biome in campaign.Biome {
		if biome==.Count {continue}
		art:=expedition_mount_art(biome,0.1);later:=expedition_mount_art(biome,.45)
		expect_expedition_art_safe(t,&art);expect_expedition_art_safe(t,&later)
		signature:=expedition_art_signature(&art)
		for prior in signatures[:count] {testing.expect(t,signature!=prior)}
		testing.expect(t,signature!=expedition_art_signature(&later))
		signatures[count]=signature;count+=1
	}
	dinosaur:=expedition_mount_art(.Jungle,.1,true);expect_expedition_art_safe(t,&dinosaur)
	for prior in signatures[:count] {testing.expect(t,expedition_art_signature(&dinosaur)!=prior)}
}

@(test)
test_expedition_costumes_distinguish_biomes_and_all_six_combat_roles :: proc(t:^testing.T) {
	signatures:[12*6]u64;count:=0
	for biome in campaign.Biome {
		if biome==.Count {continue}
		for role in game.Enemy_Archetype {
			if role==.Count {continue}
			art:=expedition_enemy_costume_art(biome,role,.3);expect_expedition_art_safe(t,&art)
			signature:=expedition_art_signature(&art)
			for prior in signatures[:count] {testing.expect(t,signature!=prior)}
			signatures[count]=signature;count+=1
		}
	}
	testing.expect_value(t,count,72)
}

@(test)
test_expedition_robot_is_bounded_and_reacts_to_combat_and_riding :: proc(t:^testing.T) {
	for action in gfx.Living_Action {
		for seated in ([2]bool{false,true}) {
			for progress in ([3]f32{0,.5,1}) {art:=expedition_robot_art(.3,action,progress,seated);expect_expedition_art_safe(t,&art)}
		}
	}
	idle:=expedition_robot_art(.3);hurt:=expedition_robot_art(.3,.Hurt,.5);cast_pose:=expedition_robot_art(.3,.Cast,.5);seated:=expedition_robot_art(.3,.Idle,0,true)
	testing.expect(t,expedition_art_signature(&idle)!=expedition_art_signature(&hurt))
	testing.expect(t,expedition_art_signature(&idle)!=expedition_art_signature(&cast_pose))
	testing.expect(t,expedition_art_signature(&idle)!=expedition_art_signature(&seated))
}
