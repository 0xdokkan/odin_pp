package render

import "core:testing"
import game "../game"
import level "../level"

@(test)
test_expedition_actor_shadow_cave_exclusion_follows_each_actor :: proc(t:^testing.T) {
	r:=new(Renderer);defer free(r);r.tactical.expedition=true
	when !EXPEDITION_ACTOR_SHADOW {
		testing.expect(t,!expedition_actor_sun_visible(r,game.PLAYER_ENTITY,{1,1}))
		return
	}
	data,ok:=level.create(14,9,{.Floor});testing.expect(t,ok);defer level.destroy(&data)
	for x in 8..=10 {
		level.set_height(&data,{x=x,y=4},14)
		level.set_tile(&data,{x=x,y=4,layer=-1},{.Floor})
	}
	set_board_level(&data);defer set_board_level(nil)
	set_board_actors(nil);defer set_board_actors(nil)
	foe:=game.enemy_entity(1)
	add_board_actor(game.PLAYER_ENTITY,{x=1,y=1})
	add_board_actor(foe,{x=9,y=4,layer=-1})
	testing.expect(t,expedition_actor_sun_visible(r,game.PLAYER_ENTITY,{1,1}))
	testing.expect(t,!expedition_actor_sun_visible(r,foe,{9,4}),"A cave foe receives no sun while the player stands outside")
	r.tactical.expedition_in_cave=true
	testing.expect(t,expedition_actor_sun_visible(r,game.PLAYER_ENTITY,{1,1}),"Known actor layers take precedence over the viewer's cave flag")
	r.tactical.expedition=false
	testing.expect(t,!expedition_actor_sun_visible(r,game.PLAYER_ENTITY,{1,1}))
}
