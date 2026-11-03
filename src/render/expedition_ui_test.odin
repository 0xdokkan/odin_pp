package render

import "core:testing"
import rl "vendor:raylib"
import game "../game"
import view "../engine/view"

@(test)
expedition_exploration_command_tabs_share_input_and_draw_bounds :: proc(t:^testing.T) {
	r:=new(Renderer);defer free(r)
	r.tactical.snapshot=new(Room_Presentation);defer free(r.tactical.snapshot)
	r.canvas_width=960;r.canvas_height=540
	r.tactical.expedition=true
	r.tactical.snapshot.phase=.Loot
	explore:=tactical_hud_layout(r)
	testing.expect(t,!rl.CheckCollisionRecs(explore.map_button,explore.character))
	testing.expect_value(t,explore.map_button.y,explore.character.y)
	r.tactical.snapshot.phase=.Combat
	combat:=tactical_hud_layout(r)
	testing.expect(t,!rl.CheckCollisionRecs(combat.refocus,combat.character))
	testing.expect(t,!rl.CheckCollisionRecs(combat.dodge,combat.character))
}

@(test)
expedition_compact_combat_hud_and_hand_share_hit_bounds_and_recover_world_space :: proc(t:^testing.T) {
	r:=new(Renderer);defer free(r)
	r.tactical.snapshot=new(Room_Presentation);defer free(r.tactical.snapshot)
	r.tactical.snapshot.phase=.Combat
	for canvas in ([4]view.Vec2{{960,540},{1280,720},{1600,900},{720,540}}) {
		r.canvas_width,r.canvas_height=canvas.x,canvas.y
		r.tactical.expedition=false
		legacy:=tactical_world_bounds(r)
		r.tactical.expedition=true
		world:=tactical_world_bounds(r);hud:=tactical_hud_layout(r)
		testing.expect_value(t,world.height-legacy.height,f32(44))
		for bounds in ([6]rl.Rectangle{hud.vitals,hud.pulse,hud.map_button,hud.refocus,hud.dodge,hud.character}) {
			testing.expect(t,bounds.y+bounds.height<=world.y)
			testing.expect(t,!card_drop_area_contains(r,{bounds.x+bounds.width*.5,bounds.y+bounds.height*.5}))
		}
		testing.expect(t,refocus_button_at_point(r,{hud.refocus.x+2,hud.refocus.y+2}))
		for count in 1..=game.MAX_HAND_CAPACITY {
			deck:=game.Deck_State{combat_active=true,hand_count=count}
			for i in 0..<count {deck.hand[i].id=u32(i+1)}
			for i in 0..<count {
				bounds:=hand_card_bounds(r,i,count)
				testing.expect(t,bounds.y>world.y+world.height && bounds.y+bounds.height<=canvas.y)
				testing.expect(t,bounds.x>=0 && bounds.x+bounds.width<=canvas.x)
				shown:=tactical_hand_card_visible_width(r,i,count)
				point:=view.Vec2{bounds.x+shown*.5,bounds.y+bounds.height*.5}
				index,found:=hand_card_at_point(r,&deck,point)
				testing.expect(t,found && index==i,"Every visible compact card must keep its real pointer target")
				testing.expect(t,!card_drop_area_contains(r,point))
			}
		}
	}
}

@(test)
expedition_enemy_names_follow_inspection_without_hiding_other_enemy_information :: proc(t:^testing.T) {
	r:=new(Renderer);defer free(r)
	r.tactical.expedition=true
	room:=game.Room{}
	append(&room.enemies,game.Enemy{id=7,position={x=2,y=3},health=5},game.Enemy{id=9,position={x=3,y=3},health=6})
	defer delete(room.enemies)
	testing.expect(t,!tactical_enemy_name_shown(r,&room,room.enemies[0]))
	testing.expect(t,!tactical_enemy_name_shown(r,&room,room.enemies[1]))
	r.tactical.inspected=7
	testing.expect(t,tactical_enemy_name_shown(r,&room,room.enemies[0]))
	testing.expect(t,!tactical_enemy_name_shown(r,&room,room.enemies[1]))
	r.has_hovered_cell=true;r.hovered_cell=room.enemies[1].position
	testing.expect(t,!tactical_enemy_name_shown(r,&room,room.enemies[0]))
	testing.expect(t,tactical_enemy_name_shown(r,&room,room.enemies[1]))
	r.has_hovered_cell=false;r.tactical.pointer_window={10,20}
	testing.expect(t,!tactical_enemy_name_shown(r,&room,room.enemies[0]))
	// Formatting and intent stay independently available for an unlabelled foe.
	testing.expect_value(t,living_heart_text(room.enemies[0].health,8),"5/8")
}
